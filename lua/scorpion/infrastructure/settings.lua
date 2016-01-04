local Settings = {}

local function deep_copy(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do
    out[k] = deep_copy(v)
  end
  return out
end

local defaults = {
  account = {
    max_characters = 3,
  },
  accounts = {
    admin  = { password = "admin",  role = "admin"  },
    player = { password = "player", role = "player" },
  },
  arena = {
    allow_single_player = true,
    block = 4,
    enforce_pub = false,
    map = 46,
    only = true,
    rate = 5,
    spawns = {
      { from = { x = 11, y = 44 }, to = { x = 12, y = 24 } },
      { from = { x = 13, y = 44 }, to = { x = 12, y = 17 } },
      { from = { x = 15, y = 44 }, to = { x = 12, y = 10 } },
      { from = { x = 17, y = 44 }, to = { x = 18, y = 24 } },
      { from = { x = 19, y = 44 }, to = { x = 18, y = 10 } },
      { from = { x = 21, y = 44 }, to = { x = 24, y = 24 } },
      { from = { x = 23, y = 44 }, to = { x = 24, y = 17 } },
      { from = { x = 25, y = 44 }, to = { x = 24, y = 10 } },
    },
  },
  data = {
    map_dirs = { "Data/Maps", "data/maps" },
    pub_dirs = { "Data/Pub", "Data/pub", "data/pub" },
  },
  host = "127.0.0.1",
  logging = {
    enabled       = true,
    path          = "logs/scorpion.log",
    console       = true,
    console_level = "info",
    file_level    = "info",
    colors        = true,
    packet_flow   = false,
  },
  name = "Scorpion",
  net = {
    ping_seconds = 10,
    sequence_repeat_max = 2,
    tick_sleep_ms = 20,
    websocket_port = 8079,
  },
  new_character = {
    spawn_direction = 0,
    spawn_map = 46,
    spawn_x = 12,
    spawn_y = 24,
  },
  port = 8081,
}

function Settings.load()
  return deep_copy(defaults)
end

return Settings
