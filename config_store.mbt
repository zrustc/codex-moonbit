///|
fn config_file_path() -> String {
  let base = ensure_storage_dirs()
  path_join(base, "config.json")
}

///|
fn load_config_object() -> Map[String, Json] {
  let path = config_file_path()
  if !@fs.path_exists(path) {
    return {}
  }
  let content = @fs.read_file_to_string(path) catch { _ => return {} }
  let parsed = @json.parse(content) catch { _ => return {} }
  match parsed {
    Object(obj) => obj
    _ => {}
  }
}

///|
fn save_config_object(config : Map[String, Json]) -> Unit {
  let path = config_file_path()
  let payload : Json = Json::object(config)
  @fs.write_string_to_file(path, payload.stringify(indent=2)) catch {
    _ => ()
  }
}

///|
fn load_config_string(key : String) -> String? {
  let config = load_config_object()
  match config.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn save_config_string(key : String, value : String?) -> Unit {
  let config = load_config_object()
  match value {
    Some(raw) => {
      let normalized = raw.trim().to_string()
      if normalized == "" {
        config.remove(key)
      } else {
        config.set(key, Json::string(normalized))
      }
    }
    None => config.remove(key)
  }
  save_config_object(config)
}

///|
fn normalize_non_empty(value : String?) -> String? {
  match value {
    Some(raw) => {
      let trimmed = raw.trim().to_string()
      if trimmed == "" {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn load_saved_api_key() -> String? {
  normalize_non_empty(load_config_string("api_key"))
}

///|
fn save_saved_api_key(api_key : String?) -> Unit {
  save_config_string("api_key", normalize_non_empty(api_key))
}

///|
fn mask_secret(value : String) -> String {
  if value.length() <= 8 {
    "********"
  } else {
    let head = try! value[:4]
    let tail = try! value[value.length() - 4:]
    head.to_string() + "..." + tail.to_string()
  }
}

///|
fn load_named_config_object(key : String) -> Map[String, Json] {
  let config = load_config_object()
  match config.get(key) {
    Some(Object(obj)) => obj.copy()
    _ => {}
  }
}

///|
fn save_named_config_object(key : String, value : Map[String, Json]) -> Unit {
  let config = load_config_object()
  config.set(key, Json::object(value))
  save_config_object(config)
}
