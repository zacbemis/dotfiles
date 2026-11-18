use std::time::{Duration, Instant};

const PASTE: &[u8] = b"\x1b[200~";
const PASTE_END: &[u8] = b"\x1b[201~";
const PAGE_UP: &[u8] = b"\x1b[5~";
const PAGE_DOWN: &[u8] = b"\x1b[6~";
const MOUSE: &[u8] = b"\x1b[<";
pub(crate) const MAX_INPUT: usize = 1024 * 1024;

pub(crate) enum Input {
    Bytes(Vec<u8>),
    Paste(Vec<u8>),
    Scroll { up: bool, cell: Option<(u16, u16)> },
}

#[derive(Default)]
pub(crate) struct Decoder {
    pending: Vec<u8>,
    received: Option<Instant>,
}

impl Decoder {
    pub(crate) fn push(&mut self, input: &[u8]) -> Vec<Input> {
        if self.pending.len() + input.len() > MAX_INPUT {
            self.pending.clear();
            self.received = None;
            return Vec::new();
        }
        self.pending.extend(input);
        self.received = Some(Instant::now());
        let mut commands = Vec::new();
        let mut cursor = 0;
        while cursor < self.pending.len() {
            let rest = &self.pending[cursor..];
            if rest.starts_with(PASTE) {
                let Some(end) = rest[PASTE.len()..]
                    .windows(PASTE_END.len())
                    .position(|window| window == PASTE_END)
                else {
                    break;
                };
                let end = PASTE.len() + end + PASTE_END.len();
                commands.push(Input::Paste(rest[..end].to_vec()));
                cursor += end;
            } else if rest.starts_with(PAGE_UP) || rest.starts_with(PAGE_DOWN) {
                commands.push(Input::Scroll {
                    up: rest.starts_with(PAGE_UP),
                    cell: None,
                });
                cursor += PAGE_UP.len();
            } else if rest.starts_with(MOUSE) {
                let Some(end) = rest.iter().position(|byte| matches!(byte, b'M' | b'm')) else {
                    if rest.len() < 32 {
                        break;
                    }
                    cursor += rest.len();
                    continue;
                };
                if rest[end] == b'M'
                    && let Some(scroll) = wheel(&rest[MOUSE.len()..end])
                {
                    commands.push(scroll);
                }
                cursor += end + 1;
            } else if [PASTE, PAGE_UP, PAGE_DOWN, MOUSE]
                .iter()
                .any(|sequence| sequence.starts_with(rest))
            {
                break;
            } else {
                let end = rest[1..]
                    .iter()
                    .position(|byte| *byte == 27)
                    .map_or(rest.len(), |index| index + 1);
                commands.push(Input::Bytes(rest[..end].to_vec()));
                cursor += end;
            }
        }
        self.pending.drain(..cursor);
        commands
    }

    pub(crate) fn flush_escape(&mut self) -> Option<Input> {
        let age = self.received?.elapsed();
        if self.pending.starts_with(PASTE) || self.pending.starts_with(MOUSE) {
            if age >= Duration::from_secs(2) {
                self.pending.clear();
            }
            return None;
        }
        (!self.pending.is_empty() && age >= Duration::from_millis(45))
            .then(|| Input::Bytes(std::mem::take(&mut self.pending)))
    }
}

fn wheel(bytes: &[u8]) -> Option<Input> {
    let mut parts = std::str::from_utf8(bytes).ok()?.split(';');
    let button = parts.next()?.parse::<u8>().ok()? & !28;
    let col = parts.next()?.parse::<u16>().ok()?.checked_sub(1)?;
    let row = parts.next()?.parse::<u16>().ok()?.checked_sub(1)?;
    matches!(button, 64 | 65).then_some(Input::Scroll {
        up: button == 64,
        cell: Some((col, row)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compose_reassembles_split_paste_and_keeps_enter_separate() {
        let mut decoder = Decoder::default();
        assert!(decoder.push(b"\x1b[20").is_empty());
        assert!(decoder.push(b"0~hello\nworld\x1b[20").is_empty());
        let result = decoder.push(b"1~\r");
        assert!(
            matches!(result.as_slice(), [Input::Paste(text), Input::Bytes(enter)]
            if text == b"\x1b[200~hello\nworld\x1b[201~" && enter == b"\r")
        );
    }

    #[test]
    fn decodes_phone_wheel_and_keyboard_page_actions() {
        let mut decoder = Decoder::default();
        assert!(decoder.push(b"\x1b[<64;11").is_empty());
        let result = decoder.push(b";9M\x1b[6~");
        assert!(matches!(
            result.as_slice(),
            [
                Input::Scroll {
                    up: true,
                    cell: Some((10, 8))
                },
                Input::Scroll {
                    up: false,
                    cell: None
                }
            ]
        ));
    }
}
