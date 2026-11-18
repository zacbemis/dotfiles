use std::io::{self, BufRead, BufReader, Read, Write};
use std::mem::MaybeUninit;
use std::path::Path;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, SyncSender};
use std::thread;
use std::time::{Duration, Instant};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde::Deserialize;
use serde_json::json;

use crate::input::{Decoder, Input, MAX_INPUT};
use crate::screen::{Screen, snapshot, source_grid};
use crate::{Agent, Result, agents, enabled, safe_app_name};

const CHECK_INTERVAL: Duration = Duration::from_secs(1);
const CONTROL_IDLE: Duration = Duration::from_secs(2);
const CONTROL_TIMEOUT: Duration = Duration::from_secs(2);
const PAINT_INTERVAL: Duration = Duration::from_millis(160);
const MAX_FRAME_LINE: u64 = 24 * 1024 * 1024;

#[derive(Deserialize)]
#[serde(tag = "type")]
enum Frame {
    #[serde(rename = "terminal.frame")]
    Data {},
    #[serde(rename = "terminal.closed")]
    Closed,
}

enum Event {
    Frame(u64),
    StreamClosed(u64),
    Input(Vec<u8>),
    InputClosed,
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct Size {
    cols: u16,
    rows: u16,
}

impl Size {
    fn current() -> Self {
        let mut size = MaybeUninit::<libc::winsize>::uninit();
        // ioctl initializes the output buffer when it returns successfully.
        if unsafe { libc::ioctl(libc::STDIN_FILENO, libc::TIOCGWINSZ, size.as_mut_ptr()) } == 0 {
            let size = unsafe { size.assume_init() };
            if size.ws_col > 0 && size.ws_row > 0 {
                return Self {
                    cols: size.ws_col,
                    rows: size.ws_row,
                };
            }
        }
        Self { cols: 80, rows: 24 }
    }
}

struct RawTerminal(libc::termios);

impl RawTerminal {
    fn enter() -> io::Result<Self> {
        let mut original = MaybeUninit::<libc::termios>::uninit();
        // stdin is the Core PTY. Preserve its settings while forwarding bytes.
        if unsafe { libc::tcgetattr(libc::STDIN_FILENO, original.as_mut_ptr()) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let original = unsafe { original.assume_init() };
        let mut raw = original;
        unsafe { libc::cfmakeraw(&mut raw) };
        if unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &raw) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(original))
    }
}

impl Drop for RawTerminal {
    fn drop(&mut self) {
        unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &self.0) };
    }
}

struct Stream {
    child: Child,
    id: u64,
}

impl Stream {
    fn launch(
        binary: &Path,
        socket: &Path,
        terminal: &str,
        size: Size,
        control: bool,
        id: u64,
        events: SyncSender<Event>,
    ) -> Result<Self> {
        let mut child = Command::new(binary)
            .env("HERDR_SOCKET_PATH", socket)
            .env_remove("HERDR_SESSION")
            .args([
                "terminal",
                "session",
                if control { "control" } else { "observe" },
            ])
            .arg(terminal)
            .args([
                "--cols",
                &size.cols.to_string(),
                "--rows",
                &size.rows.to_string(),
            ])
            .stdin(if control {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let stdout = child.stdout.take().expect("piped stream");
        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            let mut line = Vec::new();
            let mut announced = false;
            loop {
                line.clear();
                let read = reader
                    .by_ref()
                    .take(MAX_FRAME_LINE)
                    .read_until(b'\n', &mut line);
                if !matches!(read, Ok(n) if n > 0) || line.last() != Some(&b'\n') {
                    break;
                }
                match serde_json::from_slice(&line) {
                    Ok(Frame::Data {}) => {
                        // The first controller frame confirms input ownership.
                        // Observer frames are redraw notifications. The screen
                        // projection reads uncropped text from the source.
                        if (!control || !announced) && events.send(Event::Frame(id)).is_err() {
                            return;
                        }
                        announced = true;
                    }
                    Ok(Frame::Closed) | Err(_) => break,
                }
            }
            let _ = events.send(Event::StreamClosed(id));
        });
        Ok(Self { child, id })
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

struct Controller {
    stream: Stream,
    ready: bool,
    touched: Instant,
    pending: Vec<Input>,
    pending_size: usize,
    last_paste: Option<Instant>,
}

impl Controller {
    fn send(&mut self, input: Input, rows: u16) -> io::Result<()> {
        if self.ready {
            let stdin: &mut ChildStdin = self.stream.child.stdin.as_mut().expect("piped input");
            let message = match input {
                Input::Bytes(bytes) => {
                    if let Some(paste_at) = self.last_paste.take() {
                        thread::sleep(Duration::from_millis(40).saturating_sub(paste_at.elapsed()));
                    }
                    json!({"type": "terminal.input", "bytes": STANDARD.encode(bytes)})
                }
                Input::Paste(bytes) => {
                    self.last_paste = Some(Instant::now());
                    json!({"type": "terminal.input", "bytes": STANDARD.encode(bytes)})
                }
                Input::Scroll { up, cell } => json!({
                    "type": "terminal.scroll",
                    "direction": if up { "up" } else { "down" },
                    "source": if cell.is_some() { "wheel" } else { "page_key" },
                    "lines": if cell.is_some() { 3 } else { rows.saturating_sub(1).max(1) },
                    "column": cell.map(|(col, _)| col),
                    "row": cell.map(|(_, row)| row),
                }),
            };
            serde_json::to_writer(&mut *stdin, &message)?;
            stdin.write_all(b"\n")?;
        } else {
            let size = match &input {
                Input::Bytes(bytes) | Input::Paste(bytes) => bytes.len(),
                Input::Scroll { .. } => 1,
            };
            if self.pending_size + size > MAX_INPUT {
                return Err(io::Error::other("input arrived before control was granted"));
            }
            self.pending_size += size;
            self.pending.push(input);
        }
        self.touched = Instant::now();
        Ok(())
    }
}

struct Target<'a> {
    socket: &'a Path,
    terminal: &'a str,
    agent: String,
    session: Option<String>,
}

impl Target<'_> {
    fn current(&mut self) -> Result<Option<Agent>> {
        let Some(agent) = find_agent(self.socket, self.terminal)? else {
            return Ok(None);
        };
        let session = agent.agent_session.as_ref().map(|identity| &identity.value);
        if agent.agent != self.agent
            || self
                .session
                .as_ref()
                .is_some_and(|old| session != Some(old))
        {
            return Ok(None);
        }
        self.session = session.cloned();
        Ok(Some(agent))
    }
}

fn find_agent(socket: &Path, terminal: &str) -> Result<Option<Agent>> {
    Ok(agents(socket)?
        .into_iter()
        .find(|agent| agent.terminal_id == terminal))
}

fn core_status(status: &str) -> &'static str {
    match status {
        "working" => "working",
        "done" => "done",
        "blocked" => "blocked",
        "error" => "error",
        _ => "idle",
    }
}

pub(crate) fn run(binary: &Path, socket: &Path, terminal: &str) -> Result<()> {
    let Some(agent) = find_agent(socket, terminal)? else {
        return Ok(());
    };
    let mut target = Target {
        socket,
        terminal,
        agent: agent.agent,
        session: agent.agent_session.map(|identity| identity.value),
    };
    let app = safe_app_name(&target.agent);
    let _raw = RawTerminal::enter()?;
    let mut output = io::stdout().lock();
    // Compose uses bracketed paste. Mouse reporting lets terminal clients
    // route wheel gestures to fullscreen agents with application history.
    output.write_all(b"\x1b[?2004h\x1b[?1000h\x1b[?1006h")?;
    output.flush()?;
    let (send, events) = mpsc::sync_channel(16);
    let input_events = send.clone();
    thread::spawn(move || {
        let mut input = io::stdin().lock();
        let mut bytes = [0; 4096];
        while let Ok(count @ 1..) = input.read(&mut bytes) {
            if input_events
                .send(Event::Input(bytes[..count].to_vec()))
                .is_err()
            {
                return;
            }
        }
        let _ = input_events.send(Event::InputClosed);
    });

    let mut generation = 1;
    let mut size = Size::current();
    let observer = Stream::launch(
        binary,
        socket,
        terminal,
        size,
        false,
        generation,
        send.clone(),
    )?;
    let mut controller: Option<Controller> = None;
    let mut next_check = Instant::now();
    let mut status_sent = None;
    let mut screen = Screen::default();
    let mut dirty = true;
    let mut next_paint = Instant::now();
    let mut pane = agent.pane_id;
    let mut decoder = Decoder::default();
    loop {
        let now = Instant::now();
        if now >= next_check {
            if !enabled(socket)? {
                return Ok(());
            }
            let Some(agent) = target.current()? else {
                return Ok(());
            };
            pane = agent.pane_id;
            dirty = true;
            let status = core_status(&agent.agent_status);
            if status_sent != Some(status) {
                write!(output, "\x1b]7501;state={status}:app={app}\x1b\\")?;
                output.flush()?;
                status_sent = Some(status);
            }
            next_check = Instant::now() + CHECK_INTERVAL;
        }

        if let Some(held) = &controller {
            let limit = if held.ready {
                CONTROL_IDLE
            } else {
                CONTROL_TIMEOUT
            };
            if now.duration_since(held.touched) >= limit {
                controller = None;
            }
        }

        let new_size = Size::current();
        if new_size != size {
            size = new_size;
            dirty = true;
        }
        if dirty && now >= next_paint {
            if let Ok(Some((text, scrolled))) = snapshot(socket, &pane, terminal) {
                screen.paint(&mut output, text, scrolled, size.cols, size.rows)?;
            }
            dirty = false;
            next_paint = Instant::now() + PAINT_INTERVAL;
        }

        let mut inputs = decoder.flush_escape().into_iter().collect::<Vec<_>>();
        match events.recv_timeout(Duration::from_millis(100)) {
            Ok(Event::Frame(id)) if id == observer.id => dirty = true,
            Ok(Event::StreamClosed(id)) if id == observer.id => return Ok(()),
            Ok(Event::Frame(id))
                if controller.as_ref().is_some_and(|held| held.stream.id == id) =>
            {
                if !enabled(socket)? || target.current()?.is_none() {
                    return Ok(());
                }
                let held = controller.as_mut().expect("matching controller");
                held.ready = true;
                let pending = std::mem::take(&mut held.pending);
                if pending
                    .into_iter()
                    .any(|input| held.send(input, size.rows).is_err())
                {
                    controller = None;
                }
            }
            Ok(Event::StreamClosed(id))
                if controller.as_ref().is_some_and(|held| held.stream.id == id) =>
            {
                controller = None;
            }
            Ok(Event::Input(bytes)) => inputs.extend(decoder.push(&bytes)),
            Ok(Event::InputClosed) | Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            _ => {}
        }

        if !inputs.is_empty() {
            if !enabled(socket)? {
                return Ok(());
            }
            let Some(agent) = target.current()? else {
                return Ok(());
            };
            if controller.is_none() {
                generation += 1;
                // The relay reflows the output itself. Taking input control
                // should not also reformat the original pane to phone width.
                let source_size =
                    source_grid(socket, &agent.pane_id)
                        .ok()
                        .flatten()
                        .map_or(size, |grid| Size {
                            cols: grid.width,
                            rows: grid.height,
                        });
                controller = Some(Controller {
                    stream: Stream::launch(
                        binary,
                        socket,
                        terminal,
                        source_size,
                        true,
                        generation,
                        send.clone(),
                    )?,
                    ready: false,
                    touched: Instant::now(),
                    pending: Vec::new(),
                    pending_size: 0,
                    last_paste: None,
                });
            }
            let held = controller.as_mut().expect("active controller");
            if inputs
                .into_iter()
                .any(|input| held.send(input, size.rows).is_err())
            {
                controller = None;
            }
            dirty = true;
        }
    }
}
