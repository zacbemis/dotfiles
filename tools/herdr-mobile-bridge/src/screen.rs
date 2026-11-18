use std::io::Write;
use std::path::Path;

use serde::Deserialize;
use serde_json::json;
use unicode_width::UnicodeWidthChar;

use crate::{Result, request_with};

#[derive(Deserialize)]
struct PaneInfo {
    pane: Pane,
}

#[derive(Deserialize)]
struct Pane {
    terminal_id: String,
    scroll: Option<Scroll>,
}

#[derive(Deserialize)]
struct Scroll {
    offset_from_bottom: usize,
}

#[derive(Deserialize)]
struct Read {
    read: ReadText,
}

#[derive(Deserialize)]
struct ReadText {
    text: String,
}

pub(crate) fn snapshot(
    socket: &Path,
    pane: &str,
    terminal: &str,
) -> Result<Option<(String, bool)>> {
    let info: PaneInfo = request_with(socket, "pane.get", json!({"pane_id": pane}))?;
    if info.pane.terminal_id != terminal {
        return Ok(None);
    }
    let scrolled = info
        .pane
        .scroll
        .is_some_and(|scroll| scroll.offset_from_bottom > 0);
    let read: Read = request_with(
        socket,
        "pane.read",
        json!({
            "pane_id": pane,
            "source": if scrolled { "visible" } else { "recent_unwrapped" },
            // Herdr may drive an alternate-screen agent with synthetic
            // wheel events for a recent text read. ANSI reads are passive.
            "format": "ansi",
            "lines": 1000,
        }),
    )?;
    Ok(Some((
        strip_ansi_escapes::strip_str(&read.read.text),
        scrolled,
    )))
}

#[derive(Default)]
pub(crate) struct Screen {
    size: Option<(u16, u16)>,
    text: String,
    scrolled: bool,
    history: Vec<String>,
}

impl Screen {
    pub(crate) fn paint(
        &mut self,
        output: &mut impl Write,
        text: String,
        scrolled: bool,
        cols: u16,
        rows: u16,
    ) -> std::io::Result<()> {
        let size = (cols, rows);
        if self.size == Some(size) && self.text == text && self.scrolled == scrolled {
            return Ok(());
        }
        let logical: Vec<String> = text
            .lines()
            .map(|line| {
                line.chars()
                    .filter(|character| !character.is_control())
                    .collect()
            })
            .collect();
        let mut lines = Vec::new();
        let starts: Vec<_> = logical
            .iter()
            .map(|line| {
                let index = lines.len();
                lines.extend(wrap(line, usize::from(cols)));
                if lines.len() == index {
                    lines.push(String::new());
                }
                index
            })
            .collect();
        let split = lines.len().saturating_sub(usize::from(rows));
        let current = &lines[split..];
        let history = &logical[..starts.partition_point(|&start| start < split)];
        // Write only the newly displaced rows into Core's real primary
        // scrollback. Erases use ED2, which leaves scrollback intact.
        if !scrolled {
            let old = overlap(&self.history, history);
            if old < history.len() {
                write!(output, "\x1b[0m\x1b[2J\x1b[{rows};1H")?;
                for line in &history[old..] {
                    write!(output, "{line}\r\n")?;
                }
            }
        }
        if !scrolled {
            self.history = history.to_vec();
        }
        output.write_all(b"\x1b[0m\x1b[2J\x1b[H")?;
        for (index, line) in current.iter().enumerate() {
            if index != 0 {
                output.write_all(b"\r\n")?;
            }
            output.write_all(line.as_bytes())?;
        }
        output.flush()?;
        self.size = Some(size);
        self.scrolled = scrolled;
        self.text = text;
        Ok(())
    }
}

fn overlap(previous: &[String], current: &[String]) -> usize {
    if previous.starts_with(current) {
        return current.len();
    }
    (0..=previous.len().min(current.len()))
        .rev()
        .find(|&length| previous[previous.len() - length..] == current[..length])
        .unwrap_or(0)
}

fn wrap(text: &str, cols: usize) -> Vec<String> {
    let mut lines = Vec::new();
    for source in text.lines() {
        let mut line = String::new();
        let mut column = 0;
        for character in source.chars().filter(|character| !character.is_control()) {
            let width = character.width().unwrap_or(0);
            if column + width > cols && !line.is_empty() {
                lines.push(std::mem::take(&mut line));
                column = 0;
            }
            if width <= cols {
                column += width;
                line.push(character);
            }
        }
        lines.push(line);
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reflows_without_losing_the_right_edge_or_splitting_wide_characters() {
        assert_eq!(wrap("ABC界DEF", 4), ["ABC", "界DE", "F"]);
    }

    #[test]
    fn growing_and_rolling_scrollback_only_publish_new_rows() {
        let lines = |items: &[&str]| {
            items
                .iter()
                .map(|line| line.to_string())
                .collect::<Vec<_>>()
        };
        let old = lines(&["zero", "one", "two"]);
        assert_eq!(overlap(&old, &lines(&["zero", "one", "two", "three"])), 3);
        assert_eq!(overlap(&old, &lines(&["one", "two", "three"])), 2);
        assert_eq!(overlap(&old, &lines(&["zero", "one"])), 2);
    }
}
