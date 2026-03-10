local ArenaRound = require("scorpion.domain.world.arena_round")
local Sessions = require("scorpion.domain.world.sessions")
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
    pub = {
      client = {},
      server = {},
    },
    next_session_id = 1,
    pending_sends = {},
  }, World)
end

function World:attach_assets(assets)
  self.maps = assets.maps or {}
  self.pub = assets.pub or { client = {}, server = {} }
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
  self.arena_ready = self:has_map(arena_map)
end

function World:attach_arena_script_runner(runner)
  self.arena_script_runner = runner
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

-- Visibility and broadcast behavior.
World.in_range = Visibility.in_range
World.in_client_range = Visibility.in_client_range
World.broadcast_near = Visibility.broadcast_near
World.broadcast_map = Visibility.broadcast_map
World.broadcast_remove_from = Visibility.broadcast_remove_from

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
  return {
    arena_ready = self.arena_ready,
    arena_round = self.arena_round.active,
    arena_players = #self.arena_round.players,
    sessions = count(self.sessions),
    maps = count(self.maps),
    pub_client = count(self.pub.client or {}),
    pub_server = count(self.pub.server or {}),
  }
end

return World
