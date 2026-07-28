// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // Invoked by an agent's hook: `desktoppet hook --agent <kind>` (reads stdin).
    if args.get(1).map(String::as_str) == Some("hook") {
        desktoppet_lib::cli::run_hook(&args[2..]);
        return;
    }
    // `desktoppet run [--session id] [--project path] [--agent kind] -- <cmd...>`:
    // wraps any CLI agent , working while it runs, done when it exits.
    if args.get(1).map(String::as_str) == Some("run") {
        desktoppet_lib::cli::run_wrapper(&args[2..]);
    }
    desktoppet_lib::run();
}
