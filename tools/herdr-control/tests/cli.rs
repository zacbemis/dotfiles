//! Exercise the real binary against a local fake Herdr socket, never a live session.

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

static NEXT_SOCKET: AtomicUsize = AtomicUsize::new(0);

struct SocketDir(PathBuf);

impl SocketDir {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "herdr-control-test-{}-{}",
            std::process::id(),
            NEXT_SOCKET.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn socket(&self) -> PathBuf {
        self.0.join("api.sock")
    }
}

impl Drop for SocketDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn command() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_herdr-control"));
    for variable in [
        "HERDR_SOCKET_PATH",
        "HERDR_ACTIVE_TAB_ID",
        "HERDR_ACTIVE_WORKSPACE_ID",
    ] {
        command.env_remove(variable);
    }
    // These IDs identify the inherited shell, not the active keypress target.
    command.env("HERDR_TAB_ID", "wrong-tab");
    command.env("HERDR_WORKSPACE_ID", "wrong-workspace");
    command
}

fn snapshot() -> Value {
    json!({"snapshot": {
        "focused_tab_id": "b2",
        "focused_workspace_id": "b",
        "tabs": [
            {"tab_id": "a1", "workspace_id": "a"},
            {"tab_id": "b1", "workspace_id": "b"},
            {"tab_id": "b2", "workspace_id": "b"},
            {"tab_id": "b3", "workspace_id": "b"},
            {"tab_id": "c1", "workspace_id": "c"}
        ],
        "workspaces": [{"workspace_id": "a"}, {"workspace_id": "b"}, {"workspace_id": "c"}]
    }})
}

struct Step {
    method: &'static str,
    params: Value,
    reply: Reply,
}

enum Reply {
    Result(Value),
    Error,
    WrongId,
    Raw(&'static str),
}

fn step(method: &'static str, params: Value, result: Value) -> Step {
    Step {
        method,
        params,
        reply: Reply::Result(result),
    }
}

fn initial() -> Step {
    step("session.snapshot", json!({}), snapshot())
}

fn serve(listener: UnixListener, steps: Vec<Step>) {
    listener.set_nonblocking(true).unwrap();
    for step in steps {
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut connection = loop {
            match listener.accept() {
                Ok((stream, _)) => break stream,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(
                        Instant::now() < deadline,
                        "missing request: {}",
                        step.method
                    );
                    thread::sleep(Duration::from_millis(5));
                }
                Err(error) => panic!("accept failed: {error}"),
            }
        };
        connection
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let mut line = String::new();
        BufReader::new(&connection).read_line(&mut line).unwrap();
        let request: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(request["method"], step.method);
        assert_eq!(request["params"], step.params);
        assert!(
            request["id"]
                .as_str()
                .unwrap()
                .starts_with("herdr-control:")
        );
        let response = match step.reply {
            Reply::Result(result) => {
                json!({"id": request["id"], "result": result}).to_string() + "\n"
            }
            Reply::Error => {
                json!({"id": request["id"], "error": {
                    "code": "test_error", "message": "operation refused"
                }})
                .to_string()
                    + "\n"
            }
            Reply::WrongId => json!({"id": "wrong", "result": snapshot()}).to_string() + "\n",
            Reply::Raw(text) => text.to_owned(),
        };
        // Responses may arrive in multiple reads on a stream socket.
        let split = response.len() / 2;
        connection.write_all(&response.as_bytes()[..split]).unwrap();
        thread::sleep(Duration::from_millis(2));
        connection.write_all(&response.as_bytes()[split..]).unwrap();
    }
}

fn run(action: &str, context: &[(&str, &str)], steps: Vec<Step>) -> Output {
    let directory = SocketDir::new();
    let listener = UnixListener::bind(directory.socket()).unwrap();
    let server = thread::spawn(move || serve(listener, steps));
    let output = command()
        .arg(action)
        .env("HERDR_SOCKET_PATH", directory.socket())
        .envs(context.iter().copied())
        .output()
        .unwrap();
    server.join().unwrap();
    output
}

fn assert_success(output: Output) {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
}

#[test]
fn all_four_reorder_commands_move_one_position_without_focus_requests() {
    for (action, method, params) in [
        (
            "tab-left",
            "tab.move",
            json!({"tab_id": "b2", "insert_index": 0}),
        ),
        (
            "tab-right",
            "tab.move",
            json!({"tab_id": "b2", "insert_index": 3}),
        ),
        (
            "workspace-up",
            "workspace.move",
            json!({"workspace_id": "b", "insert_index": 0}),
        ),
        (
            "workspace-down",
            "workspace.move",
            json!({"workspace_id": "b", "insert_index": 3}),
        ),
    ] {
        assert_success(run(
            action,
            &[],
            vec![initial(), step(method, params, json!({}))],
        ));
    }
}

#[test]
fn keypress_context_overrides_live_focus() {
    assert_success(run(
        "tab-right",
        &[("HERDR_ACTIVE_TAB_ID", "b1")],
        vec![
            initial(),
            step(
                "tab.move",
                json!({"tab_id": "b1", "insert_index": 2}),
                json!({}),
            ),
        ],
    ));
    assert_success(run(
        "workspace-down",
        &[("HERDR_ACTIVE_WORKSPACE_ID", "a")],
        vec![
            initial(),
            step(
                "workspace.move",
                json!({"workspace_id": "a", "insert_index": 2}),
                json!({}),
            ),
        ],
    ));
}

#[test]
fn boundaries_and_single_tab_workspaces_are_noops() {
    for (action, variable, target) in [
        ("tab-left", "HERDR_ACTIVE_TAB_ID", "b1"),
        ("tab-right", "HERDR_ACTIVE_TAB_ID", "b3"),
        ("tab-left", "HERDR_ACTIVE_TAB_ID", "a1"),
        ("tab-right", "HERDR_ACTIVE_TAB_ID", "a1"),
        ("workspace-up", "HERDR_ACTIVE_WORKSPACE_ID", "a"),
        ("workspace-down", "HERDR_ACTIVE_WORKSPACE_ID", "c"),
    ] {
        assert_success(run(action, &[(variable, target)], vec![initial()]));
    }
}

fn created(workspace: &str) -> Value {
    json!({"tab": {"tab_id": "new", "workspace_id": workspace}})
}

#[test]
fn creates_adjacent_tab_before_focusing_it() {
    for (current, gap) in [("b1", 1), ("b2", 2)] {
        assert_success(run(
            "new-tab",
            &[("HERDR_ACTIVE_TAB_ID", current)],
            vec![
                initial(),
                step(
                    "tab.create",
                    json!({"workspace_id": "b", "focus": false}),
                    created("b"),
                ),
                step(
                    "tab.move",
                    json!({"tab_id": "new", "insert_index": gap}),
                    json!({}),
                ),
                step("tab.focus", json!({"tab_id": "new"}), json!({})),
            ],
        ));
    }
}

#[test]
fn creating_after_last_or_only_tab_does_not_move_it() {
    for (current, workspace) in [("b3", "b"), ("a1", "a")] {
        assert_success(run(
            "new-tab",
            &[("HERDR_ACTIVE_TAB_ID", current)],
            vec![
                initial(),
                step(
                    "tab.create",
                    json!({"workspace_id": workspace, "focus": false}),
                    created(workspace),
                ),
                step("tab.focus", json!({"tab_id": "new"}), json!({})),
            ],
        ));
    }
}

#[test]
fn stale_keypress_target_does_not_modify_another_tab() {
    let output = run(
        "new-tab",
        &[("HERDR_ACTIVE_TAB_ID", "gone")],
        vec![initial()],
    );
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("tab gone no longer exists"));
}

#[test]
fn no_focused_tab_is_a_clear_error() {
    let mut state = snapshot();
    state["snapshot"]["focused_tab_id"] = Value::Null;
    let output = run(
        "new-tab",
        &[],
        vec![step("session.snapshot", json!({}), state)],
    );
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("no active target"));
}

#[test]
fn server_error_stops_creation_without_move_or_focus() {
    let output = run(
        "new-tab",
        &[],
        vec![
            initial(),
            Step {
                method: "tab.create",
                params: json!({"workspace_id": "b", "focus": false}),
                reply: Reply::Error,
            },
        ],
    );
    assert!(!output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .contains("tab.create: test_error: operation refused")
    );
}

#[test]
fn rejects_malformed_incomplete_mismatched_and_invalid_results() {
    for (reply, message) in [
        (
            Reply::Raw("not-json\n"),
            "decoding session.snapshot response",
        ),
        (Reply::Raw("{}"), "incomplete response"),
        (Reply::WrongId, "response ID does not match"),
        (Reply::Result(json!({})), "invalid session.snapshot result"),
    ] {
        let output = run(
            "tab-left",
            &[],
            vec![Step {
                method: "session.snapshot",
                params: json!({}),
                reply,
            }],
        );
        assert!(!output.status.success());
        assert!(String::from_utf8_lossy(&output.stderr).contains(message));
    }
}

#[test]
fn help_and_invalid_arguments_do_not_need_a_socket() {
    let output = command().arg("--help").output().unwrap();
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("new-tab"));
    for args in [vec![], vec!["unknown"], vec!["tab-left", "extra"]] {
        let output = command().args(args).output().unwrap();
        assert_eq!(output.status.code(), Some(2));
    }
}

#[test]
fn concurrent_commands_serialize_the_entire_snapshot_and_move() {
    let directory = SocketDir::new();
    let listener = UnixListener::bind(directory.socket()).unwrap();
    let mut after_move = snapshot();
    after_move["snapshot"]["tabs"]
        .as_array_mut()
        .unwrap()
        .swap(2, 3);
    let server = thread::spawn(move || {
        // Give both processes time to start. Without the session lock they
        // would both queue a snapshot before either sends its move.
        thread::sleep(Duration::from_millis(100));
        serve(
            listener,
            vec![
                initial(),
                step(
                    "tab.move",
                    json!({"tab_id": "b2", "insert_index": 3}),
                    json!({}),
                ),
                step("session.snapshot", json!({}), after_move),
            ],
        );
    });
    let spawn = || {
        command()
            .arg("tab-right")
            .env("HERDR_SOCKET_PATH", directory.socket())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap()
    };
    let first = spawn();
    let second = spawn();
    assert_success(first.wait_with_output().unwrap());
    assert_success(second.wait_with_output().unwrap());
    server.join().unwrap();
}

#[test]
fn missing_socket_environment_fails_without_guessing_another_session() {
    let output = command().arg("tab-left").output().unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("HERDR_SOCKET_PATH is not set"));
}
