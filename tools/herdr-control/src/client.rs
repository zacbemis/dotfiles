//! One newline-delimited JSON request per connection to Herdr's local API.

use std::env;
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, de::DeserializeOwned};
use serde_json::{Value, json};

const TIMEOUT: Duration = Duration::from_secs(3);
const MAX_RESPONSE_BYTES: u64 = 16 * 1024 * 1024;
static NEXT_REQUEST: AtomicU64 = AtomicU64::new(1);

#[derive(Deserialize)]
struct Response {
    id: String,
    result: Option<Value>,
    error: Option<ApiError>,
}

#[derive(Deserialize)]
struct ApiError {
    code: String,
    message: String,
}

pub struct Client {
    socket: PathBuf,
    // Keep the lock for the whole read/modify/write operation so simultaneous
    // keybindings do not compute moves from the same stale snapshot.
    _lock: File,
}

impl Client {
    pub fn from_env() -> Result<Self> {
        // Do not guess a default: named and remote sessions may use another
        // socket, and modifying the wrong running session would be surprising.
        let socket = PathBuf::from(
            env::var_os("HERDR_SOCKET_PATH")
                .context("HERDR_SOCKET_PATH is not set; run inside Herdr")?,
        );
        let mut lock_path = socket.as_os_str().to_owned();
        lock_path.push(".herdr-control.lock");
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)
            .context("opening the per-session command lock")?;
        lock.lock().context("locking the Herdr session")?;
        Ok(Self {
            socket,
            _lock: lock,
        })
    }

    pub fn call<T: DeserializeOwned>(&self, method: &str, params: Value) -> Result<T> {
        let stream = UnixStream::connect(&self.socket)
            .with_context(|| format!("connecting to {}", self.socket.display()))?;
        stream.set_read_timeout(Some(TIMEOUT))?;
        stream.set_write_timeout(Some(TIMEOUT))?;
        let id = format!(
            "herdr-control:{}:{}",
            std::process::id(),
            NEXT_REQUEST.fetch_add(1, Ordering::Relaxed)
        );
        let request = json!({"id": id, "method": method, "params": params});
        writeln!(&stream, "{request}").with_context(|| format!("sending {method}"))?;

        let mut line = Vec::new();
        BufReader::new(&stream)
            .take(MAX_RESPONSE_BYTES)
            .read_until(b'\n', &mut line)
            .with_context(|| format!("reading {method} response"))?;
        if line.last() != Some(&b'\n') {
            bail!("{method}: incomplete response or response exceeds {MAX_RESPONSE_BYTES} bytes");
        }
        let response: Response =
            serde_json::from_slice(&line).with_context(|| format!("decoding {method} response"))?;
        if response.id != id {
            bail!("{method}: response ID does not match request");
        }
        match (response.result, response.error) {
            (Some(result), None) => {
                serde_json::from_value(result).with_context(|| format!("invalid {method} result"))
            }
            (None, Some(error)) => bail!("{method}: {}: {}", error.code, error.message),
            _ => bail!("{method}: expected exactly one of result or error"),
        }
    }
}
