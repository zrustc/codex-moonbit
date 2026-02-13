///|
test "normalize_path canonicalization" {
  assert_eq(normalize_path("/a/./b//c"), "/a/b/c")
  assert_eq(normalize_path("a/../../b"), "../b")
  assert_eq(normalize_path("./x/y"), "x/y")
  assert_eq(normalize_path("/../../tmp"), "/tmp")
}

///|
test "resolve_tool_path blocks traversal" {
  let options = RunOptions::{
    model: "gpt-5",
    base_url: "https://api.openai.com/v1",
    api_key: None,
    cwd: "/tmp/codex-moonbit-root",
    max_turns: 1,
    json_mode: false,
  }
  assert_eq(
    resolve_tool_path("src/main.mbt", options),
    Some("/tmp/codex-moonbit-root/src/main.mbt"),
  )
  assert_true(resolve_tool_path("../etc/passwd", options) is None)
}

///|
test "list_files_under_path walks with moonbit fs" {
  let tmp_base = @os.tmpdir() catch { _ => "/tmp" }
  let root = path_join(tmp_base, "codex-moonbit-test-\{@env.now().to_string()}")
  let src_dir = path_join(root, "src")
  let nested_dir = path_join(src_dir, "nested")
  ensure_dir(root)
  ensure_dir(src_dir)
  ensure_dir(nested_dir)
  @fs.write_string_to_file(path_join(src_dir, "a.mbt"), "fn a {}") catch {
    _ => fail("failed to write test file")
  }
  @fs.write_string_to_file(path_join(nested_dir, "b.mbt"), "fn b {}") catch {
    _ => fail("failed to write test file")
  }
  let options = RunOptions::{
    model: "gpt-5",
    base_url: "https://api.openai.com/v1",
    api_key: None,
    cwd: root,
    max_turns: 1,
    json_mode: false,
  }
  let listed = list_files_under_path(".", options)
  guard listed is Ok(files) else { fail("expected successful listing") }
  assert_true(files.contains("src/a.mbt"))
  assert_true(files.contains("src/nested/b.mbt"))
  let escaped = list_files_under_path("../", options)
  assert_true(escaped is Err(_))
}

///|
test "parse review and sandbox commands" {
  let review = parse_cli(["review", "src/app.mbt"])
  assert_true(review.error is None)
  guard review.command is Review(prompt~) else {
    fail("expected review command")
  }
  assert_true(prompt.contains("src/app.mbt"))
  let sandbox = parse_cli(["sandbox", "echo", "hello"])
  assert_true(sandbox.error is None)
  guard sandbox.command is Sandbox(command~) else {
    fail("expected sandbox command")
  }
  assert_eq(command, "echo hello")
  let sandbox_linux = parse_cli(["sandbox", "linux", "echo", "ok"])
  assert_true(sandbox_linux.error is None)
  guard sandbox_linux.command is Sandbox(command=linux_command) else {
    fail("expected sandbox command")
  }
  assert_eq(linux_command, "echo ok")
}

///|
test "parse resume --last and mcp auth commands" {
  let tmp_base = @os.tmpdir() catch { _ => "/tmp" }
  let root = path_join(
    tmp_base,
    "codex-moonbit-parse-test-\{@env.now().to_string()}",
  )
  ensure_dir(root)
  let options = RunOptions::{
    model: "gpt-5",
    base_url: "https://api.openai.com/v1",
    api_key: None,
    cwd: root,
    max_turns: 1,
    json_mode: false,
  }
  save_session(
    "session-123",
    options,
    [{ "role": "user", "content": "hello" }],
    None,
  )
  let resumed = parse_cli(["--cwd", root, "resume", "--last"])
  assert_true(resumed.error is None)
  guard resumed.command is Exec(prompt~, resume_id=Some(id)) else {
    fail("expected resume as exec command")
  }
  assert_eq(id, "session-123")
  assert_true(prompt.contains("Continue"))
  let mcp_login = parse_cli(["mcp", "login", "demo", "--token", "abc"])
  assert_true(mcp_login.error is None)
  guard mcp_login.command is McpLogin(name~, token=Some(token)) else {
    fail("expected mcp login command")
  }
  assert_eq(name, "demo")
  assert_eq(token, "abc")
  let mcp_logout = parse_cli(["mcp", "logout", "demo"])
  assert_true(mcp_logout.error is None)
  guard mcp_logout.command is McpLogout(name=logout_name) else {
    fail("expected mcp logout command")
  }
  assert_eq(logout_name, "demo")
}

///|
test "parse completion and sessions commands" {
  let completion = parse_cli(["completion", "zsh"])
  assert_true(completion.error is None)
  guard completion.command is Completion(shell~) else {
    fail("expected completion command")
  }
  assert_eq(shell, "zsh")
  let sessions = parse_cli(["sessions", "--all"])
  assert_true(sessions.error is None)
  guard sessions.command is Sessions(all~) else {
    fail("expected sessions command")
  }
  assert_true(all)
}

///|
test "parse cloud commands" {
  let cloud_exec = parse_cli([
    "cloud", "exec", "fix failing tests", "--env", "dev", "--branch", "main", "--attempts",
    "3",
  ])
  assert_true(cloud_exec.error is None)
  guard cloud_exec.command
    is CloudExec(
      query~,
      environment=Some(env_id),
      branch=Some(branch),
      attempts~
    ) else {
    fail("expected cloud exec command")
  }
  assert_true(query.contains("fix failing tests"))
  assert_eq(env_id, "dev")
  assert_eq(branch, "main")
  assert_eq(attempts, 3)
  let cloud_status = parse_cli(["cloud", "status", "task-1"])
  assert_true(cloud_status.error is None)
  guard cloud_status.command is CloudStatus(task_id~) else {
    fail("expected cloud status command")
  }
  assert_eq(task_id, "task-1")
  let cloud_apply = parse_cli(["cloud", "apply", "task-1", "--attempt", "1"])
  assert_true(cloud_apply.error is None)
  guard cloud_apply.command
    is CloudApply(task_id=apply_task_id, attempt=Some(n)) else {
    fail("expected cloud apply command")
  }
  assert_eq(apply_task_id, "task-1")
  assert_eq(n, 1)
}
