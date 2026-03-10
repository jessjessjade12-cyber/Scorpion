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
    -- "auto" prefers EMF local warp rows for arena queue spawns, then falls back to settings.
    -- Use "settings" to force static pairs below, or "emf" to force map-driven spawns only.
    spawn_source = "settings",
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
  npc_movement = {
    enabled = true,
    include_shop_npcs = false,
    interval_seconds = 0.35,
    pause_chance = 0.18,
    leash_radius = 6,
    momentum_bias = 0.8,
    crowd_avoid_radius = 1,
    crowd_avoid_weight = 0.25,
    scan_distance = 14,
    -- Spawn type -> seconds per move (0 fastest, 7 disabled).
    speeds = {
      [0] = 0.35,
      [1] = 0.45,
      [2] = 0.55,
      [3] = 0.70,
      [4] = 0.85,
      [5] = 1.05,
      [6] = 1.25,
      [7] = 0,
    },
  },
  scripts = {
    arena = {
      enabled = true,
      path = "lua/scorpion/scripts/arena.lua",
      loser_duration_seconds = 60,
      winner_gold_reward = 500,
      loser_gold_penalty = 100,
      -- Character disguise values stay within these limits by default.
      appearance_limits = {
        hair_style_max = 20,
        hair_color_max = 9,
        skin_max = 4,
      },
      mass_bald_enabled = false,
      mass_bald_seconds = 20,
      -- NPC ids are used as a deterministic seed for disguise style.
      loser_npc_ids = { 17, 28, 44, 63, 88, 101, 120, 146, 177, 203 },
    },
  },
  new_character = {
    spawn_direction = 0,
    spawn_map = 46,
    spawn_x = 12,
    spawn_y = 24,
    start_gold = 1000,
  },
  port = 8081,
  persistence = {
    mongodb = {
      mongosh_path = "mongosh",
      uri = "mongodb://127.0.0.1:27017",
      database = "scorpion",
    },
  },
}

function Settings.load()
  return deep_copy(defaults)
end

return Settings
