mod input;
mod relay;
mod screen;

use std::collections::BTreeMap;
use std::env;
use std::fs::File;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use serde::Deserialize;
use serde_json::{Value, json};

const PLUGIN_ID: &str = "herdr-mobile-bridge";
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

#[derive(Deserialize)]
struct AgentList {
    agents: Vec<Agent>,
}

#[derive(Deserialize)]
struct Agent {
    terminal_id: String,
    pane_id: String,
    agent: String,
    agent_status: String,
    agent_session: Option<AgentSession>,
}

#[derive(Deserialize)]
struct AgentSession {
    value: String,
}

#[derive(Deserialize)]
struct PluginList {
    plugins: Vec<Plugin>,
}

#[derive(Deserialize)]
struct Plugin {
    plugin_id: String,
    enabled: bool,
}

#[derive(Deserialize)]
struct CoreList {
    terminals: Vec<CoreTerminal>,
}

#[derive(Deserialize)]
struct CoreTerminal {
    address: String,
    name: Option<String>,
    labels: BTreeMap<String, String>,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{PLUGIN_ID}: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    match args.as_slice() {
        [mode] if mode == "sync" => sync(),
        [mode, binary, socket, terminal] if mode == "relay" => relay::run(
            Path::new(binary),
            Path::new(socket),
            terminal.to_str().ok_or("invalid terminal id")?,
        ),
        _ => Err("run the sync action through Herdr's plugin API".into()),
    }
}

fn required_path(key: &str) -> Result<PathBuf> {
    let path = PathBuf::from(env::var_os(key).ok_or_else(|| format!("missing {key}"))?);
    if !path.is_absolute() {
        return Err(format!("{key} must be an absolute path").into());
    }
    Ok(path)
}

fn request<T: serde::de::DeserializeOwned>(socket: &Path, method: &str) -> Result<T> {
    request_with(socket, method, json!({}))
}

fn request_with<T: serde::de::DeserializeOwned>(
    socket: &Path,
    method: &str,
    params: Value,
) -> Result<T> {
    let mut connection = UnixStream::connect(socket)?;
    let timeout = Some(Duration::from_secs(2));
    connection.set_read_timeout(timeout)?;
    connection.set_write_timeout(timeout)?;
    serde_json::to_writer(
        &mut connection,
        &json!({"id": "mobile-bridge", "method": method, "params": params}),
    )?;
    connection.write_all(b"\n")?;
    // A reply larger than this is unusable to the bridge. Never echo a reply
    // into logs because it can include terminal and workspace metadata.
    let mut line = Vec::new();
    BufReader::new(connection)
        .take(8 * 1024 * 1024)
        .read_until(b'\n', &mut line)?;
    let mut response: Value = serde_json::from_slice(&line)
        .map_err(|_| format!("invalid {method} response from Herdr"))?;
    let result = response
        .as_object_mut()
        .and_then(|object| object.remove("result"))
        .ok_or_else(|| format!("{method} rejected by Herdr"))?;
    serde_json::from_value(result)
        .map_err(|_| format!("unexpected {method} response from Herdr").into())
}

fn enabled(socket: &Path) -> Result<bool> {
    let plugins: PluginList = request(socket, "plugin.list")?;
    Ok(plugins
        .plugins
        .iter()
        .any(|plugin| plugin.enabled && plugin.plugin_id == PLUGIN_ID))
}

fn agents(socket: &Path) -> Result<Vec<Agent>> {
    let result: AgentList = request(socket, "agent.list")?;
    Ok(result.agents)
}

fn scope_hash(value: impl Hash) -> String {
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn safe_app_name(agent: &str) -> String {
    let name: String = agent
        .bytes()
        .filter(|byte| byte.is_ascii_alphanumeric() || b"-_".contains(byte))
        .take(12)
        .map(|byte| byte.to_ascii_lowercase() as char)
        .collect();
    if name.is_empty() {
        "agent".to_owned()
    } else {
        name
    }
}

fn hc(herdr: &Path) -> Command {
    // The official phone app connects to the default local Core session.
    // A server launched from a desktop may not inherit the shell's PATH.
    let sibling = herdr.with_file_name("hc");
    let mut command = Command::new(if sibling.is_file() {
        sibling.as_os_str()
    } else {
        std::ffi::OsStr::new("hc")
    });
    command
        .env("HC_SESSION", "default")
        .env_remove("HC_SOCKET")
        .env_remove("HC_TERMINAL_SOCKET")
        .env_remove("HC_TERMINAL_ID");
    command
}

fn core_request<T: serde::de::DeserializeOwned>(
    herdr: &Path,
    method: &str,
    params: Value,
) -> Result<T> {
    let mut client = hc(herdr)
        .arg("connect")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("could not start hc beside Herdr or on PATH: {error}"))?;
    let mut input = client.stdin.take().expect("piped Core input");
    serde_json::to_writer(
        &mut input,
        &json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}),
    )?;
    input.write_all(b"\n")?;
    drop(input);
    let output = client.wait_with_output()?;
    if !output.status.success() {
        return Err("could not connect to the default Core session".into());
    }
    let response: CoreResponse<T> = serde_json::from_slice(&output.stdout)
        .map_err(|_| format!("{method} failed or returned an invalid response from Core"))?;
    Ok(response.result)
}

#[derive(Deserialize)]
struct CoreResponse<T> {
    result: T,
}

fn sync() -> Result<()> {
    let socket = required_path("HERDR_SOCKET_PATH")?;
    let binary = required_path("HERDR_BIN_PATH")?;
    let state = required_path("HERDR_PLUGIN_STATE_DIR")?;
    let scope = scope_hash(&socket);
    let lock = File::create(state.join(format!("sync-{scope}.lock")))?;
    // Startup and agent events can arrive concurrently. Serialize discovery
    // and publishing for this source session.
    lock.lock()?;

    if !enabled(&socket)? {
        return Ok(());
    }
    let agents = agents(&socket)?;
    if agents.is_empty() {
        return Ok(());
    }

    let existing: CoreList = core_request(&binary, "terminal.list", json!({}))?;
    let executable = env::current_exe()?;
    let mut failed = 0;
    for agent in agents {
        let name = format!(
            "{}-tui-{}",
            safe_app_name(&agent.agent),
            scope_hash((&scope, &agent.terminal_id))
        );
        if existing.terminals.iter().any(|terminal| {
            !terminal.address.contains('/')
                && terminal.name.as_deref() == Some(&name)
                && terminal.labels.get(PLUGIN_ID) == Some(&scope)
        }) {
            continue;
        }
        let params = json!({
            "argv": [executable, PathBuf::from("relay"), binary, socket, PathBuf::from(agent.terminal_id)],
            "name": name,
            "labels": {PLUGIN_ID: scope},
            "size": {"cols": 42, "rows": 30},
            "no_parent": true,
            "rm": true,
        });
        if core_request::<Value>(&binary, "terminal.run", params).is_err() {
            failed += 1;
        }
    }
    if failed > 0 {
        return Err(format!("{failed} agent relay(s) could not be published").into());
    }
    Ok(())
}
