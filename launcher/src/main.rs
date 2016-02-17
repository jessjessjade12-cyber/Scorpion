use std::env;
use std::path::PathBuf;
use std::process::{exit, Command};

fn find_lua() -> Option<PathBuf> {
    // Known Lua 5.1 install location (Lua for Windows)
    let known = PathBuf::from(r"C:\Program Files (x86)\Lua\5.1\lua.exe");
    if known.exists() {
        return Some(known);
    }

    // Fall back to PATH
    if let Ok(path_var) = env::var("PATH") {
        for dir in env::split_paths(&path_var) {
            let candidate = dir.join("lua.exe");
            if candidate.exists() {
                return Some(candidate);
            }
        }
    }

    None
}

fn main() {
    let exe_dir = env::current_exe()
        .expect("cannot determine exe path")
        .parent()
        .expect("exe has no parent directory")
        .to_path_buf();

    let lua_exe = find_lua().unwrap_or_else(|| {
        eprintln!("ERROR: Lua 5.1 not found.");
        eprintln!("Install Lua for Windows from https://luaforwindows.luaforge.net/");
        exit(1);
    });

    let main_lua = exe_dir.join("lua").join("main.lua");
    if !main_lua.exists() {
        eprintln!(
            "ERROR: lua/main.lua not found next to the executable.\n  looked at: {}",
            main_lua.display()
        );
        exit(1);
    }

    let status = Command::new(&lua_exe)
        .arg(&main_lua)
        .current_dir(&exe_dir)
        .status()
        .unwrap_or_else(|e| {
            eprintln!("ERROR: Failed to launch {}: {}", lua_exe.display(), e);
            exit(1);
        });

    exit(status.code().unwrap_or(1));
}
