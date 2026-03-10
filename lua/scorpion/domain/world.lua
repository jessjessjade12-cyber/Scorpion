local ArenaRound = require("scorpion.domain.world.arena_round")
local MapItems = require("scorpion.domain.world.map_items")
local NpcMotion = require("scorpion.domain.world.npc_motion")
local RuntimeNpcs = require("scorpion.domain.world.runtime_npcs")
local Sessions = require("scorpion.domain.world.sessions")
local Shops = require("scorpion.domain.world.shops")
local Spatial = require("scorpion.domain.world.spatial")
local Visibility = require("scorpion.domain.world.visibility")
local Warp = require("scorpion.domain.world.warp")

local World = {}
World.__index = World

local function count(map)
  local total = 0
  for _ in pairs(map) do
    total = total + 1
  end
  return total
end

local function sorted_pairs(spawns)
  table.sort(spawns, function(a, b)
    if a.from.y ~= b.from.y then
      return a.from.y < b.from.y
    end
    return a.from.x < b.from.x
  end)
  return spawns
end

local function build_arena_spawns_from_emf(map_meta, arena_map)
  local out = {}
  if type(map_meta) ~= "table" then
    return out
  end

  for _, row in ipairs(map_meta.warp_rows or {}) do
    local from_y = tonumber(row and row.y) or 0
    for _, tile in ipairs((row and row.tiles) or {}) do
      local warp = (tile or {}).warp or {}
      local destination_map = tonumber(warp.destination_map) or 0
      local destination = warp.destination_coords or {}
      local to_x = tonumber(destination.x) or 0
      local to_y = tonumber(destination.y) or 0
      local from_x = tonumber(tile and tile.x) or 0

      -- Arena queue mapping expects local warps on the arena map.
      if destination_map == arena_map and from_x > 0 and from_y > 0 and to_x > 0 and to_y > 0 then
        out[#out + 1] = {
          from = { x = from_x, y = from_y },
          to = { x = to_x, y = to_y },
        }
      end
    end
  end

  return sorted_pairs(out)
end

function World.new()
  return setmetatable({
    arena = {},
    arena_ready = false,
    arena_spawn = {
      direction = 0,
      map = 0,
      x = 0,
      y = 0,
    },
    arena_round = {
      active = false,
      players = {},
      ticks = 0,
      winner = nil,
    },
    sessions = {},
    maps = {},
    map_items = {},
    pub = {
      client = {},
      server = {},
    },
    npc_movement = {
      crowd_avoid_radius = 1,
      crowd_avoid_weight = 0.25,
      enabled = true,
      include_shop_npcs = false,
      interval_seconds = 0.35,
      leash_radius = 6,
      map_state = {},
      momentum_bias = 0.8,
      next_tick = 0,
      pause_chance = 0.18,
      scan_distance = 14,
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
    spatial_config = {
      default_bucket_size = 8,
      sparse_bucket_size = 16,
      dense_bucket_size = 4,
      sparse_enter = 48,
      sparse_exit = 72,
      dense_enter = 220,
      dense_exit = 180,
    },
    session_spatial = {},
    spatial_index = {},
    spatial_bucket_size = {},
    spatial_map_counts = {},
    spatial_map_bucket_counts = {},
    spatial_metrics = {
      map_calls = 0,
      map_results = 0,
      nearby_buckets = 0,
      nearby_calls = 0,
      nearby_results = 0,
      rebalances = 0,
    },
    runtime_npc_owners = {},
    runtime_npcs = {},
    shop_db = {
      shops = {},
      by_behavior_id = {},
    },
    next_session_id = 1,
    pending_sends = {},
    transport = nil,
  }, World)
end

function World:attach_assets(assets)
  self.maps = assets.maps or {}
  self.pub = assets.pub or { client = {}, server = {} }
  self:attach_shop_db(assets.shop_db)
end

function World:configure_arena(settings)
  self.arena = settings.arena or {}
  local spawn = settings.new_character or {}
  self.arena_spawn = {
    direction = spawn.spawn_direction or 0,
    map = spawn.spawn_map or ((self.arena and self.arena.map) or 0),
    x = spawn.spawn_x or 0,
    y = spawn.spawn_y or 0,
  }
  local arena_map = (self.arena and self.arena.map) or self.arena_spawn.map or 5

  local spawn_source = tostring(self.arena.spawn_source or "auto"):lower()
  local map_meta = self:get_map_meta(arena_map)
  local emf_spawns = build_arena_spawns_from_emf(map_meta, arena_map)
  local configured_spawns = self.arena.spawns or {}

  if spawn_source == "emf" then
    self.arena.spawns = emf_spawns
  elseif spawn_source == "settings" then
    self.arena.spawns = configured_spawns
  else
    -- auto: prefer EMF queue warps, fallback to configured static spawn pairs.
    if #emf_spawns > 0 then
      self.arena.spawns = emf_spawns
    else
      self.arena.spawns = configured_spawns
    end
  end

  self.arena_ready = self:has_map(arena_map)
end

function World:attach_arena_script_runner(runner)
  self.arena_script_runner = runner
end

function World:attach_transport(adapter)
  self.transport = adapter or nil
end

function World:run_arena_script_hook(hook_name, context)
  if not self.arena_script_runner then
    return
  end
  self.arena_script_runner:run(hook_name, context)
end

function World:push_pending(address, packet)
  self.pending_sends[#self.pending_sends + 1] = { address = address, packet = packet }
end

function World:flush_pending()
  local q = self.pending_sends
  self.pending_sends = {}
  return q
end

-- Session lifecycle and lookup.
World.add_session = Sessions.add_session
World.remove_session = Sessions.remove_session
World.find_session_by_account = Sessions.find_session_by_account
World.find_session_by_address = Sessions.find_session_by_address
World.create_session = Sessions.create_session

-- Spatial session index behavior.
World.sync_session_spatial = Spatial.sync_session_spatial
World.remove_session_spatial = Spatial.remove_session_spatial
World.list_map_sessions = Spatial.list_map_sessions
World.list_nearby_sessions = Spatial.list_nearby_sessions
World.spatial_snapshot = Spatial.spatial_snapshot

-- Visibility and broadcast behavior.
World.in_range = Visibility.in_range
World.in_client_range = Visibility.in_client_range
World.broadcast_near = Visibility.broadcast_near
World.broadcast_map = Visibility.broadcast_map
World.broadcast_remove_from = Visibility.broadcast_remove_from

-- Shop database behavior.
World.attach_shop_db = Shops.attach_shop_db
World.find_shop_by_behavior_id = Shops.find_shop_by_behavior_id
World.list_shops = Shops.list_shops
World.shop_count = Shops.shop_count

-- Runtime NPC proxy behavior.
World.list_map_npcs = RuntimeNpcs.list_map_npcs
World.get_runtime_npc_for_owner = RuntimeNpcs.get_runtime_npc_for_owner
World.upsert_runtime_npc_for_owner = RuntimeNpcs.upsert_runtime_npc_for_owner
World.remove_runtime_npc_for_owner = RuntimeNpcs.remove_runtime_npc_for_owner

-- Ground item behavior.
World.list_map_items = MapItems.list_map_items
World.find_map_item = MapItems.find_map_item
World.add_map_item = MapItems.add_map_item
World.take_map_item = MapItems.take_map_item
World.remove_map_item = MapItems.remove_map_item
World.map_item_count = MapItems.map_item_count

-- Static NPC movement behavior.
World.configure_npc_movement = NpcMotion.configure_npc_movement
World.tick_npcs = NpcMotion.tick_npcs

-- Map and warp behavior.
World.has_map = Warp.has_map
World.get_map_meta = Warp.get_map_meta
World.get_map_relog = Warp.get_map_relog
World.arena_spawn_point = Warp.arena_spawn_point
World.request_local_warp = Warp.request_local_warp
World.arena_respawn = Warp.arena_respawn

-- Arena round lifecycle.
World.send_arena_full = ArenaRound.send_arena_full
World.send_arena_launch = ArenaRound.send_arena_launch
World.send_arena_spec = ArenaRound.send_arena_spec
World.send_arena_accept = ArenaRound.send_arena_accept
World.arena_queue_candidates = ArenaRound.arena_queue_candidates
World.start_arena_round = ArenaRound.start_arena_round
World.is_arena_session = ArenaRound.is_arena_session
World.arena_eliminate = ArenaRound.arena_eliminate
World.tick_arena = ArenaRound.tick_arena

function World:snapshot()
  local spatial = self:spatial_snapshot()
  return {
    arena_ready = self.arena_ready,
    arena_round = self.arena_round.active,
    arena_players = #self.arena_round.players,
    sessions = count(self.sessions),
    maps = count(self.maps),
    pub_client = count(self.pub.client or {}),
    pub_server = count(self.pub.server or {}),
    shops = self:shop_count(),
    map_items = self:map_item_count(),
    spatial_indexed_sessions = spatial.indexed_sessions or 0,
    spatial_maps = spatial.maps_indexed or 0,
    spatial_nearby_avg_results = spatial.nearby_avg_results or 0,
    spatial_rebalances = spatial.rebalances or 0,
  }
end

return World
