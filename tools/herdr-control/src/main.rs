mod actions;
mod client;

use std::env;
use std::process::ExitCode;

use actions::Action;

const USAGE: &str = "Usage: herdr-control <command>

Commands:
  tab-left        Move the active tab one position left
  tab-right       Move the active tab one position right
  workspace-up    Move the active workspace one position up
  workspace-down  Move the active workspace one position down
  new-tab         Create and focus a tab immediately after the active tab

Run inside Herdr, or set HERDR_SOCKET_PATH explicitly.
Reordering stops at the ends and preserves focus.
";

fn main() -> ExitCode {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() == 1 && matches!(args[0].as_str(), "--help" | "-h") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    let action = match args.as_slice() {
        [command] => Action::parse(command),
        _ => None,
    };
    let Some(action) = action else {
        eprint!("{USAGE}");
        return ExitCode::from(2);
    };
    match client::Client::from_env().and_then(|client| actions::run(&client, action)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("herdr-control: {error:#}");
            ExitCode::FAILURE
        }
    }
}
