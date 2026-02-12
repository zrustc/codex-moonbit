///|
const VERSION = "0.1.0"

///|
const DEFAULT_MODEL = "gpt-5"

///|
const DEFAULT_BASE_URL = "https://api.openai.com/v1"

///|
const DEFAULT_MAX_TURNS = 20

///|
const SYSTEM_PROMPT = "You are Codex, a software engineering agent. Use tools when needed and finish with a concise final answer."

///|
priv struct RunOptions {
  model : String
  base_url : String
  api_key : String?
  cwd : String
  max_turns : Int
  json_mode : Bool
}

///|
priv enum ParsedCommand {
  Help
  Version
  Exec(prompt~ : String, resume_id~ : String?)
  Apply(path_or_patch~ : String?)
  Login(status~ : Bool, with_api_key~ : Bool)
  Logout
  McpList
  McpGet(name~ : String)
  McpAdd(name~ : String, url~ : String?, command~ : String?)
  McpRemove(name~ : String)
  FeaturesList
  FeaturesEnable(name~ : String)
  FeaturesDisable(name~ : String)
  Fork(session_id~ : String, prompt~ : String)
}

///|
priv struct ParseResult {
  command : ParsedCommand
  options : RunOptions
  error : String?
}

///|
priv struct ProcessResult {
  status : Int
  stdout : String
  stderr : String
}

///|
priv struct CompletionParsed {
  assistant_message : Json
  content : String?
  tool_calls : Array[Json]
  error : String?
}

///|
priv struct ToolResult {
  content : String
  latest_patch : String?
}

///|
priv struct ToolExecution {
  message : Json
  latest_patch : String?
}

///|
priv struct AgentRunResult {
  final_message : String
  messages : Array[Json]
  session_id : String
  latest_patch : String?
}

///|
fn[X] fatal(message : String) -> X {
  println("ERROR: \{message}")
  @sys.exit(1)
  panic()
}

///|
pub fn main_entry() -> Unit {
  let argv = @sys.get_cli_args()
  let args : Array[String] = []
  for i = 1; i < argv.length(); i = i + 1 {
    args.push(argv[i])
  }
  let parsed = parse_cli(args)
  if parsed.error is Some(err) {
    println("ERROR: \{err}")
    print_help()
    @sys.exit(1)
    return
  }
  match parsed.command {
    Help => print_help()
    Version => println("codex-moonbit \{VERSION}")
    Exec(prompt~, resume_id~) =>
      run_exec_command(prompt, resume_id, parsed.options)
    Apply(path_or_patch~) => run_apply_command(path_or_patch, parsed.options)
    Login(status~, with_api_key~) =>
      run_login_command(status, with_api_key, parsed.options)
    Logout => run_logout_command(parsed.options)
    McpList => run_mcp_list_command(parsed.options)
    McpGet(name~) => run_mcp_get_command(name, parsed.options)
    McpAdd(name~, url~, command~) =>
      run_mcp_add_command(name, url, command, parsed.options)
    McpRemove(name~) => run_mcp_remove_command(name, parsed.options)
    FeaturesList => run_features_list_command(parsed.options)
    FeaturesEnable(name~) =>
      run_features_set_command(name, true, parsed.options)
    FeaturesDisable(name~) =>
      run_features_set_command(name, false, parsed.options)
    Fork(session_id~, prompt~) =>
      run_fork_command(session_id, prompt, parsed.options)
  }
}

///|
fn default_cwd() -> String {
  @os.cwd() catch {
    _ =>
      match @sys.get_env_var("PWD") {
        Some(pwd) => pwd
        None => "."
      }
  }
}

///|
fn parse_int_or_default(value : String, fallback : Int) -> Int {
  @strconv.parse_int(value) catch {
    _ => fallback
  }
}

///|
fn parse_cli(args : Array[String]) -> ParseResult {
  let mut model = DEFAULT_MODEL
  let mut base_url = match @sys.get_env_var("OPENAI_BASE_URL") {
    Some(v) => v
    None => DEFAULT_BASE_URL
  }
  let mut api_key = @sys.get_env_var("OPENAI_API_KEY")
  let mut cwd = default_cwd()
  let mut max_turns = DEFAULT_MAX_TURNS
  let mut json_mode = false
  let mut with_api_key = false
  let mut mcp_url : String? = None
  let mut mcp_command : String? = None
  let mut parse_error : String? = None
  let mut want_help = false
  let mut want_version = false
  let mut skip_next = false
  let positionals : Array[String] = []
  for i = 0; i < args.length(); i = i + 1 {
    if skip_next {
      skip_next = false
      continue
    }
    let arg = args[i]
    match arg {
      "-h" | "--help" => want_help = true
      "-V" | "--version" => want_version = true
      "--json" => json_mode = true
      "--with-api-key" => with_api_key = true
      "-m" | "--model" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --model")
          break
        }
        model = args[i + 1]
        skip_next = true
      }
      [.. "--model=", .. value] => model = value.to_string()
      "--base-url" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --base-url")
          break
        }
        base_url = args[i + 1]
        skip_next = true
      }
      [.. "--base-url=", .. value] => base_url = value.to_string()
      "--api-key" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --api-key")
          break
        }
        api_key = Some(args[i + 1])
        skip_next = true
      }
      [.. "--api-key=", .. value] => api_key = Some(value.to_string())
      "--url" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --url")
          break
        }
        mcp_url = Some(args[i + 1])
        skip_next = true
      }
      [.. "--url=", .. value] => mcp_url = Some(value.to_string())
      "--command" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --command")
          break
        }
        mcp_command = Some(args[i + 1])
        skip_next = true
      }
      [.. "--command=", .. value] => mcp_command = Some(value.to_string())
      "-C" | "--cwd" | "--cd" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --cwd")
          break
        }
        cwd = args[i + 1]
        skip_next = true
      }
      [.. "--cwd=", .. value] => cwd = value.to_string()
      "--max-turns" => {
        if i + 1 >= args.length() {
          parse_error = Some("missing value for --max-turns")
          break
        }
        max_turns = parse_int_or_default(args[i + 1], DEFAULT_MAX_TURNS)
        skip_next = true
      }
      [.. "--max-turns=", .. value] =>
        max_turns = parse_int_or_default(value.to_string(), DEFAULT_MAX_TURNS)
      ['-', ..] => {
        parse_error = Some("unknown flag: \{arg}")
        break
      }
      _ => positionals.push(arg)
    }
  }
  let options = RunOptions::{
    model,
    base_url,
    api_key,
    cwd,
    max_turns,
    json_mode,
  }
  if parse_error is Some(err) {
    return ParseResult::{ command: Help, options, error: Some(err) }
  }
  if want_help {
    return ParseResult::{ command: Help, options, error: None }
  }
  if want_version {
    return ParseResult::{ command: Version, options, error: None }
  }
  if positionals.is_empty() {
    return ParseResult::{
      command: Help,
      options,
      error: Some("missing prompt or subcommand"),
    }
  }
  let first = positionals[0]
  match first {
    "help" => ParseResult::{ command: Help, options, error: None }
    "version" => ParseResult::{ command: Version, options, error: None }
    "exec" | "e" =>
      if positionals.length() < 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("exec requires a prompt"),
        }
      } else {
        ParseResult::{
          command: Exec(prompt=join_strings(positionals, 1), resume_id=None),
          options,
          error: None,
        }
      }
    "resume" =>
      if positionals.length() < 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("resume requires a session id"),
        }
      } else {
        let session_id = positionals[1]
        let prompt = if positionals.length() > 2 {
          join_strings(positionals, 2)
        } else {
          "Continue from previous context."
        }
        ParseResult::{
          command: Exec(prompt~, resume_id=Some(session_id)),
          options,
          error: None,
        }
      }
    "fork" =>
      if positionals.length() < 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("fork requires a session id"),
        }
      } else {
        let prompt = if positionals.length() > 2 {
          join_strings(positionals, 2)
        } else {
          "Continue from forked context."
        }
        ParseResult::{
          command: Fork(session_id=positionals[1], prompt~),
          options,
          error: None,
        }
      }
    "apply" => {
      let patch_arg = if positionals.length() > 1 {
        Some(join_strings(positionals, 1))
      } else {
        None
      }
      ParseResult::{
        command: Apply(path_or_patch=patch_arg),
        options,
        error: None,
      }
    }
    "login" =>
      if positionals.length() > 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("login supports at most one action: status"),
        }
      } else if positionals.length() == 2 && positionals[1] != "status" {
        ParseResult::{
          command: Help,
          options,
          error: Some("unknown login action: \{positionals[1]}"),
        }
      } else {
        ParseResult::{
          command: Login(
            status=positionals.length() == 2 && positionals[1] == "status",
            with_api_key~,
          ),
          options,
          error: None,
        }
      }
    "logout" => ParseResult::{ command: Logout, options, error: None }
    "mcp" =>
      if positionals.length() < 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("mcp requires a subcommand: list|get|add|remove"),
        }
      } else {
        match positionals[1] {
          "list" => ParseResult::{ command: McpList, options, error: None }
          "get" =>
            if positionals.length() < 3 {
              ParseResult::{
                command: Help,
                options,
                error: Some("mcp get requires a server name"),
              }
            } else {
              ParseResult::{
                command: McpGet(name=positionals[2]),
                options,
                error: None,
              }
            }
          "add" =>
            if positionals.length() < 3 {
              ParseResult::{
                command: Help,
                options,
                error: Some("mcp add requires a server name"),
              }
            } else {
              let add_url = mcp_url
              let mut add_command = mcp_command
              if add_url is None &&
                add_command is None &&
                positionals.length() > 3 {
                add_command = Some(join_strings(positionals, 3))
              }
              if add_url is Some(_) && add_command is Some(_) {
                ParseResult::{
                  command: Help,
                  options,
                  error: Some("mcp add accepts only one of --url or --command"),
                }
              } else if add_url is None && add_command is None {
                ParseResult::{
                  command: Help,
                  options,
                  error: Some("mcp add requires --url <URL> or --command <CMD>"),
                }
              } else {
                ParseResult::{
                  command: McpAdd(
                    name=positionals[2],
                    url=add_url,
                    command=add_command,
                  ),
                  options,
                  error: None,
                }
              }
            }
          "remove" =>
            if positionals.length() < 3 {
              ParseResult::{
                command: Help,
                options,
                error: Some("mcp remove requires a server name"),
              }
            } else {
              ParseResult::{
                command: McpRemove(name=positionals[2]),
                options,
                error: None,
              }
            }
          _ =>
            ParseResult::{
              command: Help,
              options,
              error: Some("unknown mcp subcommand: \{positionals[1]}"),
            }
        }
      }
    "features" =>
      if positionals.length() < 2 {
        ParseResult::{
          command: Help,
          options,
          error: Some("features requires a subcommand: list|enable|disable"),
        }
      } else {
        match positionals[1] {
          "list" => ParseResult::{ command: FeaturesList, options, error: None }
          "enable" =>
            if positionals.length() < 3 {
              ParseResult::{
                command: Help,
                options,
                error: Some("features enable requires a feature name"),
              }
            } else {
              ParseResult::{
                command: FeaturesEnable(name=positionals[2]),
                options,
                error: None,
              }
            }
          "disable" =>
            if positionals.length() < 3 {
              ParseResult::{
                command: Help,
                options,
                error: Some("features disable requires a feature name"),
              }
            } else {
              ParseResult::{
                command: FeaturesDisable(name=positionals[2]),
                options,
                error: None,
              }
            }
          _ =>
            ParseResult::{
              command: Help,
              options,
              error: Some("unknown features subcommand: \{positionals[1]}"),
            }
        }
      }
    "cloud" | "sandbox" | "review" =>
      ParseResult::{
        command: Help,
        options,
        error: Some(
          "subcommand '\{first}' is not implemented yet in codex-moonbit",
        ),
      }
    _ =>
      ParseResult::{
        command: Exec(prompt=join_strings(positionals, 0), resume_id=None),
        options,
        error: None,
      }
  }
}

///|
fn print_help() -> Unit {
  println("Codex MoonBit CLI")
  println("")
  println("Usage:")
  println("  codex [OPTIONS] <PROMPT>")
  println("  codex [OPTIONS] exec <PROMPT>")
  println("  codex [OPTIONS] resume <SESSION_ID> [PROMPT]")
  println("  codex [OPTIONS] fork <SESSION_ID> [PROMPT]")
  println("  codex [OPTIONS] apply [PATCH_FILE]")
  println("  codex login [status] [--with-api-key] [--api-key <KEY>]")
  println("  codex logout")
  println("  codex mcp list|get|add|remove ...")
  println("  codex features list|enable|disable ...")
  println("")
  println("Options:")
  println("  -m, --model <MODEL>            Model name (default: gpt-5)")
  println("      --base-url <URL>           OpenAI-compatible base URL")
  println("      --api-key <KEY>            API key (or set OPENAI_API_KEY)")
  println(
    "      --with-api-key             Login using --api-key or OPENAI_API_KEY",
  )
  println("      --url <URL>                MCP add: streamable HTTP URL")
  println("      --command <CMD>            MCP add: launcher command")
  println("  -C, --cwd <DIR>                Working directory")
  println("      --max-turns <N>            Max tool-call turns")
  println("      --json                     Print final result as JSON")
  println("  -h, --help                     Show help")
  println("  -V, --version                  Show version")
}

///|
fn join_strings(parts : Array[String], start : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < parts.length(); i = i + 1 {
    if i > start {
      buf.write_string(" ")
    }
    buf.write_string(parts[i])
  }
  buf.to_string()
}

///|
fn decode_utf8(bytes : Bytes) -> String {
  @utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
fn run_process_capture(
  program : String,
  args : Array[String],
  cwd : String?,
) -> ProcessResult {
  let command = @process.Command::new(program)
    .args(args)
    .stdout(@process.Piped)
    .stderr(@process.Piped)
  let command = match cwd {
    Some(dir) => command.current_dir(dir)
    None => command
  }
  let output = command.output() catch {
    error =>
      return ProcessResult::{
        status: -1,
        stdout: "",
        stderr: "process error: \{error}",
      }
  }
  ProcessResult::{
    status: output.status.code(),
    stdout: decode_utf8(output.stdout),
    stderr: decode_utf8(output.stderr),
  }
}

///|
fn path_join(base : String, child : String) -> String {
  if child == "" {
    return base
  }
  match child {
    ['/', ..] => child
    _ =>
      match base {
        [.., '/'] => base + child
        _ => base + "/" + child
      }
  }
}

///|
fn ensure_dir(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn codex_home_dir() -> String {
  let home = @os.home() catch {
    _ =>
      match @sys.get_env_var("HOME") {
        Some(v) => v
        None => "."
      }
  }
  path_join(home, ".codex-moonbit")
}

///|
fn ensure_storage_dirs() -> String {
  let home = codex_home_dir()
  ensure_dir(home)
  ensure_dir(path_join(home, "sessions"))
  home
}

///|
fn new_session_id() -> String {
  @env.now().to_string()
}

///|
fn session_file_path(session_id : String) -> String {
  let base = ensure_storage_dirs()
  path_join(path_join(base, "sessions"), session_id + ".json")
}

///|
fn save_latest_patch(patch : String) -> Unit {
  let base = ensure_storage_dirs()
  let path = path_join(base, "latest.patch")
  @fs.write_string_to_file(path, patch) catch {
    _ => ()
  }
}

///|
fn load_latest_patch() -> String? {
  let base = ensure_storage_dirs()
  let path = path_join(base, "latest.patch")
  if !@fs.path_exists(path) {
    return None
  }
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
fn save_session(
  session_id : String,
  options : RunOptions,
  messages : Array[Json],
  latest_patch : String?,
) -> Unit {
  let payload : Json = {
    "id": session_id,
    "created_at_ms": @env.now().to_string(),
    "cwd": options.cwd,
    "model": options.model,
    "messages": messages,
    "latest_patch": latest_patch,
  }
  let path = session_file_path(session_id)
  @fs.write_string_to_file(path, payload.stringify(indent=2)) catch {
    _ => ()
  }
}

///|
fn load_session_messages(session_id : String) -> Array[Json]? {
  let path = session_file_path(session_id)
  if !@fs.path_exists(path) {
    return None
  }
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let parsed = @json.parse(content) catch { _ => return None }
  guard parsed is Object(obj) else { return None }
  guard obj.get("messages") is Some(Array(messages)) else { return None }
  Some(messages)
}

///|
fn run_apply_command(path_or_patch : String?, options : RunOptions) -> Unit {
  let patch_text = match path_or_patch {
    Some(value) =>
      if @fs.path_exists(value) {
        @fs.read_file_to_string(value) catch {
          _ => fatal("failed to read patch file: \{value}")
        }
      } else {
        value
      }
    None =>
      match load_latest_patch() {
        Some(patch) => patch
        None => fatal("no patch provided and no latest patch saved")
      }
  }
  let output = apply_patch_tool(patch_text, options)
  println(output)
}

///|
fn run_exec_command(
  prompt : String,
  resume_id : String?,
  options : RunOptions,
) -> Unit {
  let options = with_effective_api_key(options)
  let session_id = match resume_id {
    Some(id) => id
    None => new_session_id()
  }
  let messages : Array[Json] = match resume_id {
    Some(id) =>
      match load_session_messages(id) {
        Some(existing) => {
          let copied : Array[Json] = []
          copied.append(existing)
          copied
        }
        None => fatal("session not found: \{id}")
      }
    None => [{ "role": "system", "content": SYSTEM_PROMPT }]
  }
  messages.push({ "role": "user", "content": prompt })
  let result = run_agent(messages, options, session_id)
  save_session(result.session_id, options, result.messages, result.latest_patch)
  if result.latest_patch is Some(patch) {
    save_latest_patch(patch)
  }
  if options.json_mode {
    let out : Json = {
      "session_id": result.session_id,
      "message": result.final_message,
    }
    println(out.stringify())
  } else {
    println(result.final_message)
    println("\nSession: \{result.session_id}")
  }
}

///|
fn run_fork_command(
  session_id : String,
  prompt : String,
  options : RunOptions,
) -> Unit {
  let options = with_effective_api_key(options)
  let source_messages = match load_session_messages(session_id) {
    Some(messages) => messages
    None => fatal("session not found: \{session_id}")
  }
  let messages : Array[Json] = []
  messages.append(source_messages)
  messages.push({ "role": "user", "content": prompt })
  let fork_session_id = new_session_id()
  let result = run_agent(messages, options, fork_session_id)
  save_session(result.session_id, options, result.messages, result.latest_patch)
  if result.latest_patch is Some(patch) {
    save_latest_patch(patch)
  }
  if options.json_mode {
    let out : Json = {
      "session_id": result.session_id,
      "forked_from": session_id,
      "message": result.final_message,
    }
    println(out.stringify())
  } else {
    println(result.final_message)
    println("\nSession: \{result.session_id} (forked from \{session_id})")
  }
}

///|
fn tool_schema() -> Array[Json] {
  [
    {
      "type": "function",
      "function": {
        "name": "exec_command",
        "description": "Run a shell command and return stdout/stderr/exit code.",
        "parameters": {
          "type": "object",
          "properties": {
            "cmd": { "type": "string" },
            "cwd": { "type": "string" },
          },
          "required": ["cmd"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "read_file",
        "description": "Read a UTF-8 text file.",
        "parameters": {
          "type": "object",
          "properties": { "path": { "type": "string" } },
          "required": ["path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "write_file",
        "description": "Write UTF-8 text to a file.",
        "parameters": {
          "type": "object",
          "properties": {
            "path": { "type": "string" },
            "content": { "type": "string" },
          },
          "required": ["path", "content"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "list_files",
        "description": "List files using rg --files.",
        "parameters": {
          "type": "object",
          "properties": { "path": { "type": "string" } },
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "apply_patch",
        "description": "Apply unified patch via git apply.",
        "parameters": {
          "type": "object",
          "properties": { "patch": { "type": "string" } },
          "required": ["patch"],
        },
      },
    },
  ]
}

///|
fn chat_completion(messages : Array[Json], options : RunOptions) -> Json? {
  let body : Json = {
    "model": options.model,
    "messages": messages,
    "tools": tool_schema(),
    "tool_choice": "auto",
  }
  let tmp_dir = @os.tmpdir() catch { _ => "/tmp" }
  let request_path = path_join(
    tmp_dir,
    "codex-moonbit-request-\{@env.now().to_string()}" + ".json",
  )
  let wrote = try {
    @fs.write_string_to_file(request_path, body.stringify())
    true
  } catch {
    _ => false
  }
  if !wrote {
    return None
  }
  let key = match options.api_key {
    Some(k) => k
    None => return None
  }
  let endpoint = options.base_url + "/chat/completions"
  let result = run_process_capture(
    "curl",
    [
      "-sS",
      "-X",
      "POST",
      endpoint,
      "-H",
      "Authorization: Bearer \{key}",
      "-H",
      "Content-Type: application/json",
      "--data-binary",
      "@\{request_path}",
    ],
    Some(options.cwd),
  )
  @fs.remove_file(request_path) catch {
    _ => ()
  }
  if result.status != 0 {
    println("ERROR: OpenAI request failed: \{result.stderr}")
    return None
  }
  Some(@json.parse(result.stdout)) catch {
    _ => {
      println("ERROR: invalid JSON response from model")
      None
    }
  }
}

///|
fn parse_completion(json : Json) -> CompletionParsed {
  let empty_calls : Array[Json] = []
  let fallback_assistant : Json = {
    "role": "assistant",
    "content": "",
    "tool_calls": empty_calls,
  }
  guard json is Object(obj) else {
    return CompletionParsed::{
      assistant_message: fallback_assistant,
      content: None,
      tool_calls: [],
      error: Some("response is not an object"),
    }
  }
  guard obj.get("choices") is Some(Array(choices)) else {
    return CompletionParsed::{
      assistant_message: fallback_assistant,
      content: None,
      tool_calls: [],
      error: Some("missing choices"),
    }
  }
  if choices.is_empty() {
    return CompletionParsed::{
      assistant_message: fallback_assistant,
      content: None,
      tool_calls: [],
      error: Some("empty choices"),
    }
  }
  guard choices[0] is Object(choice_obj) else {
    return CompletionParsed::{
      assistant_message: fallback_assistant,
      content: None,
      tool_calls: [],
      error: Some("invalid first choice"),
    }
  }
  guard choice_obj.get("message") is Some(Object(message_obj)) else {
    return CompletionParsed::{
      assistant_message: fallback_assistant,
      content: None,
      tool_calls: [],
      error: Some("missing message"),
    }
  }
  let content = match message_obj.get("content") {
    Some(String(text)) => Some(text)
    _ => None
  }
  let calls = match message_obj.get("tool_calls") {
    Some(Array(calls)) => calls
    _ => []
  }
  let assistant_message : Json = {
    "role": "assistant",
    "content": content,
    "tool_calls": calls,
  }
  CompletionParsed::{
    assistant_message,
    content,
    tool_calls: calls,
    error: None,
  }
}

///|
fn json_get_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn resolve_tool_path(path : String, options : RunOptions) -> String {
  path_join(options.cwd, path)
}

///|
fn apply_patch_tool(patch : String, options : RunOptions) -> String {
  let tmp_dir = @os.tmpdir() catch { _ => "/tmp" }
  let patch_path = path_join(
    tmp_dir,
    "codex-moonbit-apply-\{@env.now().to_string()}" + ".patch",
  )
  let write_ok = try {
    @fs.write_string_to_file(patch_path, patch)
    true
  } catch {
    _ => false
  }
  if !write_ok {
    let err : Json = {
      "success": false,
      "error": "failed to write temporary patch file",
    }
    return err.stringify()
  }
  let result = run_process_capture(
    "git",
    ["apply", "--whitespace=nowarn", patch_path],
    Some(options.cwd),
  )
  @fs.remove_file(patch_path) catch {
    _ => ()
  }
  let payload : Json = {
    "success": result.status == 0,
    "status": result.status,
    "stdout": result.stdout,
    "stderr": result.stderr,
  }
  payload.stringify()
}

///|
fn tool_exec_command(arguments : Json, options : RunOptions) -> ToolResult {
  guard arguments is Object(obj) else {
    let err : Json = { "error": "exec_command expects object arguments" }
    return ToolResult::{ content: err.stringify(), latest_patch: None }
  }
  let cmd = match json_get_string(obj, "cmd") {
    Some(cmd) => cmd
    None => {
      let err : Json = { "error": "missing cmd" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let command_cwd = match json_get_string(obj, "cwd") {
    Some(path) => Some(resolve_tool_path(path, options))
    None => Some(options.cwd)
  }
  let result = run_process_capture("bash", ["-lc", cmd], command_cwd)
  let payload : Json = {
    "status": result.status,
    "success": result.status == 0,
    "stdout": result.stdout,
    "stderr": result.stderr,
  }
  ToolResult::{ content: payload.stringify(), latest_patch: None }
}

///|
fn tool_read_file(arguments : Json, options : RunOptions) -> ToolResult {
  guard arguments is Object(obj) else {
    let err : Json = { "error": "read_file expects object arguments" }
    return ToolResult::{ content: err.stringify(), latest_patch: None }
  }
  let path = match json_get_string(obj, "path") {
    Some(path) => resolve_tool_path(path, options)
    None => {
      let err : Json = { "error": "missing path" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let content = @fs.read_file_to_string(path) catch {
    error => {
      let err : Json = { "error": "failed to read file", "detail": "\{error}" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let payload : Json = { "path": path, "content": content }
  ToolResult::{ content: payload.stringify(), latest_patch: None }
}

///|
fn tool_write_file(arguments : Json, options : RunOptions) -> ToolResult {
  guard arguments is Object(obj) else {
    let err : Json = { "error": "write_file expects object arguments" }
    return ToolResult::{ content: err.stringify(), latest_patch: None }
  }
  let path = match json_get_string(obj, "path") {
    Some(path) => resolve_tool_path(path, options)
    None => {
      let err : Json = { "error": "missing path" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let content = match json_get_string(obj, "content") {
    Some(content) => content
    None => {
      let err : Json = { "error": "missing content" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let ok = try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    _ => false
  }
  let payload : Json = {
    "success": ok,
    "path": path,
    "bytes": content.length(),
  }
  ToolResult::{ content: payload.stringify(), latest_patch: None }
}

///|
fn tool_list_files(arguments : Json, options : RunOptions) -> ToolResult {
  let path = match arguments {
    Object(obj) =>
      match json_get_string(obj, "path") {
        Some(path) => path
        None => "."
      }
    _ => "."
  }
  let rg_result = run_process_capture(
    "rg",
    ["--files", path],
    Some(options.cwd),
  )
  let result = if rg_result.status == 0 {
    rg_result
  } else {
    run_process_capture(
      "find",
      [path, "-maxdepth", "4", "-type", "f"],
      Some(options.cwd),
    )
  }
  let payload : Json = {
    "status": result.status,
    "stdout": result.stdout,
    "stderr": result.stderr,
  }
  ToolResult::{ content: payload.stringify(), latest_patch: None }
}

///|
fn tool_apply_patch(arguments : Json, options : RunOptions) -> ToolResult {
  guard arguments is Object(obj) else {
    let err : Json = { "error": "apply_patch expects object arguments" }
    return ToolResult::{ content: err.stringify(), latest_patch: None }
  }
  let patch = match json_get_string(obj, "patch") {
    Some(patch) => patch
    None => {
      let err : Json = { "error": "missing patch" }
      return ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  ToolResult::{
    content: apply_patch_tool(patch, options),
    latest_patch: Some(patch),
  }
}

///|
fn execute_tool_call(call : Json, options : RunOptions) -> ToolExecution {
  guard call is Object(call_obj) else {
    let msg : Json = {
      "role": "tool",
      "tool_call_id": "tool-error",
      "content": "invalid tool call",
    }
    return ToolExecution::{ message: msg, latest_patch: None }
  }
  let call_id = match call_obj.get("id") {
    Some(String(id)) => id
    _ => "tool-\{@env.now().to_string()}"
  }
  guard call_obj.get("function") is Some(Object(function_obj)) else {
    let msg : Json = {
      "role": "tool",
      "tool_call_id": call_id,
      "content": "missing function payload",
    }
    return ToolExecution::{ message: msg, latest_patch: None }
  }
  let name = match function_obj.get("name") {
    Some(String(name)) => name
    _ => ""
  }
  let arguments = match function_obj.get("arguments") {
    Some(String(raw)) =>
      @json.parse(raw) catch {
        _ => {
          let empty : Json = {}
          empty
        }
      }
    _ => {
      let empty : Json = {}
      empty
    }
  }
  let result = match name {
    "exec_command" => tool_exec_command(arguments, options)
    "read_file" => tool_read_file(arguments, options)
    "write_file" => tool_write_file(arguments, options)
    "list_files" => tool_list_files(arguments, options)
    "apply_patch" => tool_apply_patch(arguments, options)
    _ => {
      let err : Json = { "error": "unknown tool: \{name}" }
      ToolResult::{ content: err.stringify(), latest_patch: None }
    }
  }
  let msg : Json = {
    "role": "tool",
    "tool_call_id": call_id,
    "content": result.content,
  }
  ToolExecution::{ message: msg, latest_patch: result.latest_patch }
}

///|
fn run_agent(
  messages : Array[Json],
  options : RunOptions,
  session_id : String,
) -> AgentRunResult {
  let mut final_message = ""
  let mut latest_patch : String? = None
  for _turn = 0; _turn < options.max_turns; _turn = _turn + 1 {
    let response = match chat_completion(messages, options) {
      Some(response) => response
      None => {
        final_message = "Model request failed."
        break
      }
    }
    let parsed = parse_completion(response)
    if parsed.error is Some(err) {
      final_message = "Failed to parse model response: \{err}"
      break
    }
    messages.push(parsed.assistant_message)
    if parsed.tool_calls.is_empty() {
      final_message = match parsed.content {
        Some(text) => text
        None => ""
      }
      break
    }
    for tool_call in parsed.tool_calls {
      let tool_result = execute_tool_call(tool_call, options)
      messages.push(tool_result.message)
      if tool_result.latest_patch is Some(patch) {
        latest_patch = Some(patch)
      }
    }
  }
  if final_message == "" {
    final_message = "Done."
  }
  AgentRunResult::{ final_message, messages, session_id, latest_patch }
}
