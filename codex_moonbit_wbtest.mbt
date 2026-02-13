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
