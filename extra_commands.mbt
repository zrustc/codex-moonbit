///|
fn with_effective_api_key(options : RunOptions) -> RunOptions {
  let key = match normalize_non_empty(options.api_key) {
    Some(value) => Some(value)
    None => load_saved_api_key()
  }
  match key {
    Some(value) =>
      RunOptions::{
        model: options.model,
        base_url: options.base_url,
        api_key: Some(value),
        cwd: options.cwd,
        max_turns: options.max_turns,
        json_mode: options.json_mode,
      }
    None =>
      fatal(
        "missing API key. Set OPENAI_API_KEY, pass --api-key, or run 'codex login'",
      )
  }
}

///|
fn run_login_command(
  status : Bool,
  with_api_key : Bool,
  options : RunOptions,
) -> Unit {
  let stored_key = load_saved_api_key()
  if status {
    let env_key = normalize_non_empty(@sys.get_env_var("OPENAI_API_KEY"))
    let cli_key = normalize_non_empty(options.api_key)
    let effective = match cli_key {
      Some(value) => Some(value)
      None =>
        match env_key {
          Some(value) => Some(value)
          None => stored_key
        }
    }
    if options.json_mode {
      let payload : Json = {
        "logged_in": stored_key is Some(_),
        "stored": stored_key is Some(_),
        "env": env_key is Some(_),
        "effective": effective is Some(_),
      }
      println(payload.stringify(indent=2))
    } else {
      let stored_state = match stored_key {
        Some(key) => mask_secret(key)
        None => "(none)"
      }
      let env_state = if env_key is Some(_) { "present" } else { "(none)" }
      let effective_state = if effective is Some(_) {
        "present"
      } else {
        "(none)"
      }
      println("Stored API key: \{stored_state}")
      println("Env API key: \{env_state}")
      println("Effective API key: \{effective_state}")
    }
    return
  }
  let candidate = if with_api_key {
    match normalize_non_empty(options.api_key) {
      Some(value) => Some(value)
      None => normalize_non_empty(@sys.get_env_var("OPENAI_API_KEY"))
    }
  } else {
    normalize_non_empty(options.api_key)
  }
  let key = match candidate {
    Some(value) => value
    None =>
      fatal(
        "missing API key for login. Use --api-key <KEY> or set OPENAI_API_KEY with --with-api-key",
      )
  }
  save_saved_api_key(Some(key))
  if options.json_mode {
    let payload : Json = { "success": true, "config_path": config_file_path() }
    println(payload.stringify(indent=2))
  } else {
    println("Login successful. Credentials saved at \{config_file_path()}.")
  }
}

///|
fn run_logout_command(options : RunOptions) -> Unit {
  save_saved_api_key(None)
  if options.json_mode {
    let payload : Json = { "success": true, "logged_in": false }
    println(payload.stringify(indent=2))
  } else {
    println("Logged out. Stored API key removed.")
  }
}

///|
fn describe_mcp_entry(entry : Json) -> String {
  guard entry is Object(obj) else { return "invalid" }
  let entry_type = match obj.get("type") {
    Some(String(value)) => value
    _ => "unknown"
  }
  match entry_type {
    "http" => {
      let url = match obj.get("url") {
        Some(String(value)) => value
        _ => ""
      }
      if url == "" {
        "http"
      } else {
        "http \{url}"
      }
    }
    "stdio" => {
      let command = match obj.get("command") {
        Some(String(value)) => value
        _ => ""
      }
      if command == "" {
        "stdio"
      } else {
        "stdio \{command}"
      }
    }
    _ => entry_type
  }
}

///|
fn load_mcp_token(name : String) -> String? {
  let tokens = load_named_config_object("mcp_tokens")
  match tokens.get(name) {
    Some(String(value)) => normalize_non_empty(Some(value))
    _ => None
  }
}

///|
fn is_valid_server_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  for c in name {
    let is_letter = ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
    let is_digit = '0' <= c && c <= '9'
    let is_safe_symbol = c == '-' || c == '_'
    if !(is_letter || is_digit || is_safe_symbol) {
      return false
    }
  }
  true
}

///|
fn run_mcp_list_command(options : RunOptions) -> Unit {
  let servers = load_named_config_object("mcp_servers")
  let tokens = load_named_config_object("mcp_tokens")
  if options.json_mode {
    let payload : Json = {
      "servers": Json::object(servers),
      "mcp_tokens": Json::object(tokens),
    }
    println(payload.stringify(indent=2))
    return
  }
  if servers.is_empty() {
    println("No MCP servers configured.")
    return
  }
  for name, entry in servers {
    let auth_state = if load_mcp_token(name) is Some(_) {
      "logged-in"
    } else {
      "logged-out"
    }
    println("\{name}\t\{describe_mcp_entry(entry)}\t\{auth_state}")
  }
}

///|
fn run_mcp_get_command(name : String, options : RunOptions) -> Unit {
  let servers = load_named_config_object("mcp_servers")
  let entry = match servers.get(name) {
    Some(value) => value
    None => fatal("MCP server not found: \{name}")
  }
  let logged_in = load_mcp_token(name) is Some(_)
  if options.json_mode {
    let payload : Json = {
      "name": name,
      "server": entry,
      "logged_in": logged_in,
    }
    println(payload.stringify(indent=2))
  } else {
    println("Name: \{name}")
    println("Config: \{describe_mcp_entry(entry)}")
    let auth_state = if logged_in { "logged-in" } else { "logged-out" }
    println("Auth: \{auth_state}")
  }
}

///|
fn run_mcp_add_command(
  name : String,
  url : String?,
  command : String?,
  options : RunOptions,
) -> Unit {
  if !is_valid_server_name(name) {
    fatal("invalid MCP server name: \{name}")
  }
  let entry : Json = match normalize_non_empty(url) {
    Some(value) => {
      if normalize_non_empty(command) is Some(_) {
        fatal("mcp add accepts only one of URL or command")
      }
      { "type": "http", "url": value }
    }
    None => {
      let cmd = match normalize_non_empty(command) {
        Some(value) => value
        None => fatal("mcp add requires URL or command")
      }
      { "type": "stdio", "command": cmd }
    }
  }
  let servers = load_named_config_object("mcp_servers")
  servers.set(name, entry)
  save_named_config_object("mcp_servers", servers)
  if options.json_mode {
    let payload : Json = { "success": true, "name": name }
    println(payload.stringify(indent=2))
  } else {
    println("Added MCP server '\{name}'.")
  }
}

///|
fn run_mcp_remove_command(name : String, options : RunOptions) -> Unit {
  let servers = load_named_config_object("mcp_servers")
  if !servers.contains(name) {
    fatal("MCP server not found: \{name}")
  }
  servers.remove(name)
  save_named_config_object("mcp_servers", servers)
  let tokens = load_named_config_object("mcp_tokens")
  if tokens.contains(name) {
    tokens.remove(name)
    save_named_config_object("mcp_tokens", tokens)
  }
  if options.json_mode {
    let payload : Json = { "success": true, "name": name }
    println(payload.stringify(indent=2))
  } else {
    println("Removed MCP server '\{name}'.")
  }
}

///|
fn run_mcp_login_command(
  name : String,
  token : String?,
  options : RunOptions,
) -> Unit {
  let servers = load_named_config_object("mcp_servers")
  if !servers.contains(name) {
    fatal("MCP server not found: \{name}")
  }
  let resolved_token = match normalize_non_empty(token) {
    Some(value) => Some(value)
    None => normalize_non_empty(@sys.get_env_var("MCP_TOKEN"))
  }
  let access_token = match resolved_token {
    Some(value) => value
    None => fatal("missing MCP token. Use --token <TOKEN> or set MCP_TOKEN")
  }
  let tokens = load_named_config_object("mcp_tokens")
  tokens.set(name, Json::string(access_token))
  save_named_config_object("mcp_tokens", tokens)
  if options.json_mode {
    let payload : Json = { "success": true, "name": name, "logged_in": true }
    println(payload.stringify(indent=2))
  } else {
    println("MCP server '\{name}' logged in.")
  }
}

///|
fn run_mcp_logout_command(name : String, options : RunOptions) -> Unit {
  let tokens = load_named_config_object("mcp_tokens")
  if tokens.contains(name) {
    tokens.remove(name)
    save_named_config_object("mcp_tokens", tokens)
  }
  if options.json_mode {
    let payload : Json = { "success": true, "name": name, "logged_in": false }
    println(payload.stringify(indent=2))
  } else {
    println("MCP server '\{name}' logged out.")
  }
}

///|
fn run_features_list_command(options : RunOptions) -> Unit {
  let features = load_named_config_object("features")
  if options.json_mode {
    let payload : Json = { "features": Json::object(features) }
    println(payload.stringify(indent=2))
    return
  }
  if features.is_empty() {
    println("No feature toggles configured.")
    return
  }
  for name, value in features {
    let state = match value {
      True => "enabled"
      False => "disabled"
      _ => "invalid"
    }
    println("\{name}\t\{state}")
  }
}

///|
fn run_features_set_command(
  name : String,
  enabled : Bool,
  options : RunOptions,
) -> Unit {
  let key = name.trim().to_string()
  if key == "" {
    fatal("feature name cannot be empty")
  }
  let features = load_named_config_object("features")
  features.set(key, Json::boolean(enabled))
  save_named_config_object("features", features)
  if options.json_mode {
    let payload : Json = { "success": true, "feature": key, "enabled": enabled }
    println(payload.stringify(indent=2))
  } else {
    let state = if enabled { "enabled" } else { "disabled" }
    println("Feature '\{key}' set to \{state}.")
  }
}
