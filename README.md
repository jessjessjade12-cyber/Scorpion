# Scorpion

A dedicated **Endless Online arena server** written in Lua 5.1 with a Rust launcher. Scorpion hosts PvP arena combat for Endless Online clients — players queue, get warped into combat zones, fight, and respawn until one player remains.

---

## Requirements

- **Lua 5.1** — [LuaForWindows](https://github.com/rjpcomputing/luaforwindows/releases) (includes LuaSocket and BitOp)
- **Rust** (only needed if you want to rebuild the launcher from source)

> Scorpion uses LuaSocket for networking and BitOp for bitwise operations in the EO encryption codec. Both are bundled with LuaForWindows.

---

## Running the Server

### Option 1 — Launcher executable

```
Scorpion.exe
```

The launcher automatically finds Lua 5.1 in the following locations (in order):

1. `lua.exe` on your system `PATH`
2. `C:\Program Files (x86)\Lua\5.1\lua.exe`

### Option 2 — Run Lua directly

```bash
lua.exe lua/main.lua
```

Run from the project root directory.

---

## Building the Launcher (optional)

```bash
cd launcher
cargo build --release
```

The compiled binary will be at `launcher/target/release/Scorpion.exe`. Copy it to the project root.

---

## Configuration

All settings are in [lua/scorpion/infrastructure/settings.lua](lua/scorpion/infrastructure/settings.lua).

### Network

| Setting | Default | Description |
|---|---|---|
| `host` | `127.0.0.1` | Bind address |
| `port` | `8081` | TCP port for EO clients |
| `net.ping_seconds` | `10` | Ping interval |

Change `host` to `0.0.0.0` to accept connections from other machines.

### Accounts

Accounts are defined directly in settings — there is no database. Add or remove entries under the `accounts` table:

```lua
accounts = {
  admin  = { password = "admin",  role = "admin" },
  player = { password = "player", role = "player" },
}
```

Each account can hold up to `account.max_characters` characters (default: `3`).

### Arena

| Setting | Default | Description |
|---|---|---|
| `arena.map` | `46` | Map ID used for the arena |
| `arena.block` | `4` | Max players per combat round |
| `arena.rate` | `5` | Ticks between new round starts |
| `arena.allow_single_player` | `true` | Allow solo queuing |

Spawn positions (queue zones and combat zones) are configured under `arena.spawns`.

### New Character Defaults

```lua
new_character = {
  spawn_map = 46,
  spawn_x   = 12,
  spawn_y   = 24,
}
```

### Logging

| Setting | Default | Description |
|---|---|---|
| `logging.enabled` | `true` | Enable file logging |
| `logging.path` | `logs/scorpion.log` | Log file location |
| `logging.console` | `true` | Print to console |
| `logging.colors` | `true` | ANSI colour output |
| `logging.packet_flow` | `false` | Log every packet (verbose) |

---

## Data Files

### Maps

Place `.emf` map files in:

```
Data/Maps/
```

Files must be named by map ID — e.g., `46.emf` for map 46. The server loads all `.emf` files it finds on startup.

The arena map ID is set via `arena.map` in settings. The default is `46`.

### Pub Files

Place pub files in:

```
Data/Pub/
```

The following files are required for the client login flow:

| File | Contents |
|---|---|
| `dat001.ecf` | Character classes |
| `dat001.eif` | Items |
| `dtn001.enf` | NPCs / monsters |
| `dsl001.esf` | Skills / spells |

Optional server-side pub files (drop tables, shops, inns, etc.):

| File | Contents |
|---|---|
| `serv_drops.epf` | Loot tables |
| `serv_inns.epf` | Inn/rest points |
| `serv_shops.epf` | Shops |
| `serv_chats.epf` | NPC dialogue |
| `serv_trainers.epf` | Trainer NPCs |

> These files must match what the connecting EO client expects. Use the pub files from your EO client installation.

---

## Connecting

Use an **Endless Online client version `0.0.28`**. The server rejects older client versions.

Point your client at:

```
Host: 127.0.0.1
Port: 8081
```

---

## Project Structure

```
Scorpion/
├── launcher/                   # Rust launcher source
│   └── src/main.rs
├── lua/
│   ├── main.lua                # Entry point
│   └── scorpion/
│       ├── bootstrap.lua       # Wires all components together
│       ├── domain/             # Pure game state (world, sessions)
│       ├── application/        # Packet handlers and business logic
│       ├── transport/          # EO protocol encoding/decoding
│       └── infrastructure/     # Network, logging, asset loading, settings
├── Data/
│   ├── Maps/                   # .emf map files
│   └── Pub/                    # .ecf / .eif / .enf / .esf pub files
├── logs/                       # Log output (auto-created)
└── Scorpion.exe                # Compiled launcher
```

---

## Logs

Logs are written to `logs/scorpion.log` and printed to the console with colour-coded levels:

| Level | Colour |
|---|---|
| DEBUG | Cyan |
| INFO | Green |
| WARN | Yellow |
| ERROR | Red |

Enable `logging.packet_flow = true` in settings to log every packet sent and received (useful for debugging protocol issues).
