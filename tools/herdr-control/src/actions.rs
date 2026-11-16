//! Ordering policy, independent of CLI parsing and socket framing.

use std::env;

use anyhow::{Context, Result};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::client::Client;

#[derive(Clone, Copy, Debug)]
pub enum Action {
    TabLeft,
    TabRight,
    WorkspaceUp,
    WorkspaceDown,
    NewTab,
}

impl Action {
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "tab-left" => Self::TabLeft,
            "tab-right" => Self::TabRight,
            "workspace-up" => Self::WorkspaceUp,
            "workspace-down" => Self::WorkspaceDown,
            "new-tab" => Self::NewTab,
            _ => return None,
        })
    }
}

#[derive(Deserialize)]
struct SnapshotResult {
    snapshot: Snapshot,
}

#[derive(Deserialize)]
struct Snapshot {
    focused_tab_id: Option<String>,
    focused_workspace_id: Option<String>,
    tabs: Vec<Tab>,
    workspaces: Vec<Workspace>,
}

#[derive(Deserialize)]
struct Tab {
    tab_id: String,
    workspace_id: String,
}

#[derive(Deserialize)]
struct Workspace {
    workspace_id: String,
}

#[derive(Deserialize)]
struct CreatedTab {
    tab: Tab,
}

#[derive(Clone, Copy)]
enum Direction {
    Backward,
    Forward,
}

/// Herdr's insert_index refers to a gap in the list BEFORE source removal.
/// Moving right/down therefore skips two gaps, not one. Never wrap at edges.
fn move_gap(index: usize, len: usize, direction: Direction) -> Option<usize> {
    if index >= len {
        return None;
    }
    match direction {
        Direction::Backward => index.checked_sub(1),
        Direction::Forward if index + 1 < len => Some(index + 2),
        Direction::Forward => None,
    }
}

fn target_id(focused: Option<String>, variable: &str) -> Result<String> {
    // HERDR_*_ID belongs to the shell that launched the server. Only ACTIVE_*
    // is keypress context; otherwise consult the live snapshot.
    env::var(variable)
        .ok()
        .filter(|id| !id.is_empty())
        .or(focused)
        .with_context(|| format!("no active target ({variable})"))
}

pub fn run(client: &Client, action: Action) -> Result<()> {
    let SnapshotResult { snapshot } = client.call("session.snapshot", json!({}))?;
    match action {
        Action::TabLeft | Action::TabRight | Action::NewTab => {
            let target = target_id(snapshot.focused_tab_id, "HERDR_ACTIVE_TAB_ID")?;
            let source = snapshot
                .tabs
                .iter()
                .find(|tab| tab.tab_id == target)
                .with_context(|| format!("tab {target} no longer exists"))?;
            let tabs: Vec<_> = snapshot
                .tabs
                .iter()
                .filter(|tab| tab.workspace_id == source.workspace_id)
                .collect();
            let index = tabs.iter().position(|tab| tab.tab_id == target).unwrap();
            if matches!(action, Action::NewTab) {
                // Append without changing focus, place next to the original
                // tab, then focus. This avoids briefly showing the tab at end.
                let created: CreatedTab = client.call(
                    "tab.create",
                    json!({"workspace_id": source.workspace_id, "focus": false}),
                )?;
                if index + 1 < tabs.len() {
                    client.call::<Value>(
                        "tab.move",
                        json!({"tab_id": created.tab.tab_id, "insert_index": index + 1}),
                    )?;
                }
                client.call::<Value>("tab.focus", json!({"tab_id": created.tab.tab_id}))?;
            } else {
                let direction = if matches!(action, Action::TabLeft) {
                    Direction::Backward
                } else {
                    Direction::Forward
                };
                if let Some(gap) = move_gap(index, tabs.len(), direction) {
                    client.call::<Value>(
                        "tab.move",
                        json!({"tab_id": target, "insert_index": gap}),
                    )?;
                }
            }
        }
        Action::WorkspaceUp | Action::WorkspaceDown => {
            let target = target_id(snapshot.focused_workspace_id, "HERDR_ACTIVE_WORKSPACE_ID")?;
            let index = snapshot
                .workspaces
                .iter()
                .position(|workspace| workspace.workspace_id == target)
                .with_context(|| format!("workspace {target} no longer exists"))?;
            let direction = if matches!(action, Action::WorkspaceUp) {
                Direction::Backward
            } else {
                Direction::Forward
            };
            if let Some(gap) = move_gap(index, snapshot.workspaces.len(), direction) {
                client.call::<Value>(
                    "workspace.move",
                    json!({"workspace_id": target, "insert_index": gap}),
                )?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn move_gap_produces_exactly_one_step_in_both_directions() {
        for len in 1..8 {
            for from in 0..len {
                for direction in [Direction::Backward, Direction::Forward] {
                    let gap = move_gap(from, len, direction);
                    let expected = match direction {
                        Direction::Backward => from.checked_sub(1),
                        Direction::Forward => (from + 1 < len).then_some(from + 1),
                    };
                    match (gap, expected) {
                        (Some(gap), Some(expected)) => {
                            // Apply the server's pre-removal-gap convention.
                            let mut items: Vec<_> = (0..len).collect();
                            let value = items.remove(from);
                            let destination = gap - usize::from(from < gap);
                            items.insert(destination, value);
                            assert_eq!(items.iter().position(|item| *item == from), Some(expected));
                        }
                        (None, None) => {}
                        _ => panic!("incorrect boundary handling: from={from}, len={len}"),
                    }
                }
            }
        }
    }

    #[test]
    fn empty_or_invalid_source_cannot_move() {
        for direction in [Direction::Backward, Direction::Forward] {
            assert_eq!(move_gap(0, 0, direction), None);
            assert_eq!(move_gap(3, 3, direction), None);
        }
    }
}
