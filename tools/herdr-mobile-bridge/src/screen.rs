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

#[derive(Deserialize)]
struct LayoutResult {
    layout: Layout,
}

#[derive(Deserialize)]
struct Layout {
    panes: Vec<LayoutPane>,
}

#[derive(Deserialize)]
struct LayoutPane {
    pane_id: String,
    rect: Grid,
}

#[derive(Deserialize)]
pub(crate) struct Grid {
    pub(crate) width: u16,
    pub(crate) height: u16,
}

pub(crate) fn source_grid(socket: &Path, pane: &str) -> Result<Option<Grid>> {
    let response: LayoutResult = request_with(socket, "pane.layout", json!({"pane_id": pane}))?;
    Ok(response
        .layout
        .panes
        .into_iter()
        .find(|item| item.pane_id == pane && item.rect.width > 0 && item.rect.height > 0)
        .map(|item| item.rect))
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
    visible: Vec<String>,
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
        let mut logical: Vec<String> = text
            .lines()
            .map(|line| {
                line.trim_end()
                    .chars()
                    .filter(|character| !character.is_control())
                    .collect()
            })
            .collect();
        while logical.last().is_some_and(String::is_empty) {
            logical.pop();
        }
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
        let mut patch = Vec::new();
        let mut repaint = self.size != Some(size);
        if !scrolled && self.size.is_none_or(|old| old == size) {
            let old = overlap(&self.history, history);
            // A fullscreen redraw can replace the whole prefix without
            // scrolling. Do not add the whole prefix as new history.
            if old < history.len() && (old > 0 || self.history.is_empty()) {
                write!(patch, "\x1b[0m\x1b[2J\x1b[{rows};1H")?;
                for line in &history[old..] {
                    write!(patch, "{line}\r\n")?;
                }
                repaint = true;
            }
        }
        if !scrolled {
            self.history = history.to_vec();
        }
        let previous = if repaint {
            patch.extend_from_slice(b"\x1b[0m\x1b[2J");
            &[][..]
        } else {
            &self.visible[..]
        };
        paint_rows(&mut patch, previous, current)?;
        if !patch.is_empty() {
            write!(patch, "\x1b[{};1H", current.len().max(1))?;
            output.write_all(&patch)?;
            output.flush()?;
        }
        self.visible = current.to_vec();
        self.size = Some(size);
        self.scrolled = scrolled;
        self.text = text;
        Ok(())
    }
}

fn paint_rows(
    output: &mut impl Write,
    previous: &[String],
    current: &[String],
) -> std::io::Result<()> {
    for index in 0..current.len().max(previous.len()) {
        if current.get(index) != previous.get(index) {
            let line = current.get(index).map_or("", String::as_str);
            write!(output, "\x1b[{};1H\x1b[2K{line}", index + 1)?;
        }
    }
    Ok(())
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
    fn editing_the_prompt_repaints_only_its_row() {
        let mut screen = Screen::default();
        screen
            .paint(&mut Vec::new(), "response\n> a".into(), false, 42, 30)
            .unwrap();
        let mut patch = Vec::new();
        screen
            .paint(&mut patch, "response\n> ab".into(), false, 42, 30)
            .unwrap();
        let patch = String::from_utf8(patch).unwrap();
        assert!(patch.contains("> ab"));
        assert!(!patch.contains("response"));
        assert!(!patch.contains("\x1b[2J"));
    }

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
