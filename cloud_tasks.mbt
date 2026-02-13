///|
fn cloud_tasks_dir_path() -> String {
  let base = ensure_storage_dirs()
  let dir = path_join(base, "cloud_tasks")
  ensure_dir(dir)
  dir
}

///|
fn cloud_task_file_path(task_id : String) -> String {
  path_join(cloud_tasks_dir_path(), task_id + ".json")
}

///|
fn new_cloud_task_id() -> String {
  "task-\{@env.now().to_string()}"
}

///|
fn save_cloud_task(task : Json) -> Unit {
  guard task is Object(obj) else { return }
  let id = match obj.get("id") {
    Some(String(value)) => value
    _ => return
  }
  let path = cloud_task_file_path(id)
  @fs.write_string_to_file(path, task.stringify(indent=2)) catch {
    _ => ()
  }
}

///|
fn load_cloud_task(task_id : String) -> Json? {
  let id = task_id.trim().to_string()
  if id == "" {
    return None
  }
  let path = cloud_task_file_path(id)
  if !@fs.path_exists(path) {
    return None
  }
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  Some(@json.parse(content)) catch {
    _ => None
  }
}

///|
fn list_cloud_tasks() -> Array[Json] {
  let dir = cloud_tasks_dir_path()
  let names = @fs.read_dir(dir) catch { _ => [] }
  let tasks : Array[Json] = []
  for name in names {
    if !name.has_suffix(".json") {
      continue
    }
    let path = path_join(dir, name)
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    let parsed = @json.parse(content) catch { _ => continue }
    guard parsed is Object(_) else { continue }
    tasks.push(parsed)
  }
  tasks.sort_by((a, b) => if cloud_task_created_at(b) > cloud_task_created_at(a) {
    1
  } else if cloud_task_created_at(b) < cloud_task_created_at(a) {
    -1
  } else {
    0
  })
  tasks
}

///|
fn cloud_task_created_at(task : Json) -> String {
  guard task is Object(obj) else { return "0" }
  match obj.get("created_at_ms") {
    Some(String(value)) => value
    Some(Number(value, ..)) => "\{value.to_int()}"
    _ => "0"
  }
}

///|
fn cloud_task_id(task : Json) -> String {
  guard task is Object(obj) else { return "" }
  match obj.get("id") {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn cloud_task_status(task : Json) -> String {
  guard task is Object(obj) else { return "unknown" }
  match obj.get("status") {
    Some(String(value)) => value
    _ => "unknown"
  }
}

///|
fn cloud_task_query(task : Json) -> String {
  guard task is Object(obj) else { return "" }
  match obj.get("query") {
    Some(String(value)) => value
    _ => ""
  }
}

///|
fn cloud_task_diff(task : Json, attempt : Int?) -> String? {
  if attempt is Some(n) && n != 1 {
    return None
  }
  guard task is Object(obj) else { return None }
  match obj.get("diff") {
    Some(String(value)) => if value == "" { None } else { Some(value) }
    _ => None
  }
}

///|
fn truncate_preview(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    (try! text[:limit]).to_string() + "..."
  }
}

///|
fn run_cloud_exec_command(
  query : String,
  environment : String?,
  branch : String?,
  attempts : Int,
  options : RunOptions,
) -> Unit {
  let cleaned_query = query.trim().to_string()
  if cleaned_query == "" {
    fatal("cloud exec requires a non-empty query")
  }
  let task_id = new_cloud_task_id()
  let now_ms = @env.now().to_string()
  let latest_diff = match load_latest_patch() {
    Some(diff) => diff
    None => ""
  }
  let task_obj : Map[String, Json] = {}
  task_obj.set("id", Json::string(task_id))
  task_obj.set("query", Json::string(cleaned_query))
  task_obj.set(
    "environment",
    match normalize_non_empty(environment) {
      Some(value) => Json::string(value)
      None => Json::null()
    },
  )
  task_obj.set(
    "branch",
    match normalize_non_empty(branch) {
      Some(value) => Json::string(value)
      None => Json::null()
    },
  )
  task_obj.set(
    "attempts",
    Json::number(clamp_cloud_attempts(attempts).to_double()),
  )
  task_obj.set("attempt", Json::number(1.0))
  task_obj.set("status", Json::string("submitted"))
  task_obj.set(
    "message",
    Json::string("Stored locally in codex-moonbit cloud task store"),
  )
  task_obj.set("diff", Json::string(latest_diff))
  task_obj.set("created_at_ms", Json::string(now_ms))
  task_obj.set("updated_at_ms", Json::string(now_ms))
  let task = Json::object(task_obj)
  save_cloud_task(task)
  if options.json_mode {
    println(task.stringify(indent=2))
  } else {
    println("Created cloud task: \{task_id}")
    println("Status: submitted")
  }
}

///|
fn run_cloud_status_command(task_id : String, options : RunOptions) -> Unit {
  let task = match load_cloud_task(task_id) {
    Some(value) => value
    None => fatal("cloud task not found: \{task_id}")
  }
  if options.json_mode {
    println(task.stringify(indent=2))
    return
  }
  println("Task: \{cloud_task_id(task)}")
  println("Status: \{cloud_task_status(task)}")
  println("Query: \{truncate_preview(cloud_task_query(task), 120)}")
}

///|
fn run_cloud_list_command(limit : Int, options : RunOptions) -> Unit {
  let tasks = list_cloud_tasks()
  let cap = clamp_cloud_limit(limit)
  let limited : Array[Json] = []
  for task in tasks {
    if limited.length() >= cap {
      break
    }
    limited.push(task)
  }
  if options.json_mode {
    let payload : Json = { "tasks": limited, "count": limited.length() }
    println(payload.stringify(indent=2))
    return
  }
  if limited.is_empty() {
    println("No cloud tasks found.")
    return
  }
  for task in limited {
    println(
      "\{cloud_task_id(task)}\t\{cloud_task_status(task)}\t\{cloud_task_created_at(task)}\t\{truncate_preview(cloud_task_query(task), 80)}",
    )
  }
}

///|
fn run_cloud_diff_command(
  task_id : String,
  attempt : Int?,
  options : RunOptions,
) -> Unit {
  let task = match load_cloud_task(task_id) {
    Some(value) => value
    None => fatal("cloud task not found: \{task_id}")
  }
  let diff = match cloud_task_diff(task, attempt) {
    Some(value) => value
    None => ""
  }
  if options.json_mode {
    let attempt_number = match attempt {
      Some(n) => n
      None => 1
    }
    let payload : Json = {
      "task_id": cloud_task_id(task),
      "attempt": attempt_number,
      "diff": diff,
      "has_diff": diff != "",
    }
    println(payload.stringify(indent=2))
    return
  }
  if diff == "" {
    println("No diff available for task \{task_id}.")
  } else {
    println(diff)
  }
}

///|
fn run_cloud_apply_command(
  task_id : String,
  attempt : Int?,
  options : RunOptions,
) -> Unit {
  let task = match load_cloud_task(task_id) {
    Some(value) => value
    None => fatal("cloud task not found: \{task_id}")
  }
  let diff = match cloud_task_diff(task, attempt) {
    Some(value) => value
    None => fatal("no diff available for task \{task_id}")
  }
  let apply_output = apply_patch_tool(diff, options)
  if options.json_mode {
    let attempt_number = match attempt {
      Some(n) => n
      None => 1
    }
    let payload : Json = {
      "task_id": cloud_task_id(task),
      "attempt": attempt_number,
      "result": @json.parse(apply_output) catch {
        _ => { "raw": apply_output }
      },
    }
    println(payload.stringify(indent=2))
  } else {
    println(apply_output)
  }
}
