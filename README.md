# Scorpion

A dedicated **Endless Online arena server** written in Lua 5.1. Players queue, get warped into combat zones, fight, and respawn until one remains.

---

## Quick Start

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Installs Lua 5.1 via Chocolatey if needed, then starts the server. To start manually after install:

```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" lua/main.lua
```

---

## Connecting

EO client version `0.0.28` — point it at `127.0.0.1:8081`. Browser/WebSocket clients use port `8079`.

---

## Data Files

Copy your EO client's pub files and map files into:

| Path | Contents |
|---|---|
| `Data/Maps/` | `.emf` map files, named by ID (e.g. `46.emf`) |
| `Data/Pub/` | `dat001.ecf`, `dat001.eif`, `dtn001.enf`, `dsl001.esf` |

---

## Configuration

All settings are in [lua/scorpion/infrastructure/settings.lua](lua/scorpion/infrastructure/settings.lua).

| Setting | Default | Description |
|---|---|---|
| `host` | `127.0.0.1` | Bind address — set to `0.0.0.0` for public |
| `port` | `8081` | TCP port |
| `net.websocket_port` | `8079` | WebSocket port |
| `arena.map` | `46` | Arena map ID |
| `arena.block` | `4` | Max players per round |
| `logging.packet_flow` | `false` | Log every packet (verbose) |

Accounts are hardcoded in settings — no database:

```lua
accounts = {
  admin  = { password = "admin",  role = "admin" },
  player = { password = "player", role = "player" },
}
```

---

## Architecture

```
EO Client (TCP)          Browser Client (WebSocket)
      |                          |
      +----------+---------------+
                 |
          [ net_server.lua ]
          socket.select loop
                 |
          [ codec.lua / websocket.lua ]
          decrypt / unwrap frames
                 |
          [ router.lua ]
          dispatch by family+action
                 |
        +--------+--------+
        |                 |
[ session_handlers ]  [ arena_handlers ]
  login, character,    walk, attack,
  warp, chat           arena rounds
        |                 |
        +--------+--------+
                 |
           [ world.lua ]
           arena state,
           sessions, spawns
                 |
        +--------+--------+
        |                 |
  [ asset_loader ]   [ accounts_memory ]
  maps, pub files    in-memory accounts
```

Logs → `logs/scorpion.log`
