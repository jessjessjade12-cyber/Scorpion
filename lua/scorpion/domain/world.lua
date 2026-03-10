local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local Session = require("scorpion.domain.session")

local Family = Protocol.Family
local Action = Protocol.Action

local World = {}
World.__index = World

local function count(map)
  local total = 0
  for _ in pairs(map) do
    total = total + 1
  end
  return total
end

local function contains(list, value)
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

local function session_name(session)
  if not session then
    return "unknown"
  end
  return session.character or session.account or ("player" .. tostring(session.id or 0))
end

local function get_distance(a, b)
  return math.abs((a.x or 0) - (b.x or 0)) + math.abs((a.y or 0) - (b.y or 0))
end

local function in_directional_range(observer, other, near_limit, far_limit)
  local distance = get_distance(observer, other)
  if (observer.x or 0) >= (other.x or 0) or (observer.y or 0) >= (other.y or 0) then
    return distance <= near_limit
  end
  return distance <= far_limit
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

function World:add_session(session)
  self.sessions[session.id] = session
end

function World:remove_session(session_id)
  self.sessions[session_id] = nil
end

function World:push_pending(address, packet)
  self.pending_sends[#self.pending_sends + 1] = { address = address, packet = packet }
end

function World:flush_pending()
  local q = self.pending_sends
  self.pending_sends = {}
  return q
end

-- Broadcast visibility range.
function World:in_range(s1, s2)
  if s1.map_id ~= s2.map_id then
    return false
  end
  return in_directional_range(s1, s2, 12, 15)
end

-- Client entity visibility range.
function World:in_client_range(s1, s2)
  if s1.map_id ~= s2.map_id then
    return false
  end
  return in_directional_range(s1, s2, 11, 14)
end

-- Queue a packet to all connected sessions near from_session (excluding sender)
function World:broadcast_near(from_session, packet)
  for _, session in pairs(self.sessions) do
    if session.id ~= from_session.id and session.connected and self:in_range(from_session, session) then
      self:push_pending(session.address, packet)
    end
  end
end

-- Queue a packet to all connected sessions on a map.
function World:broadcast_map(map_id, packet)
  for _, session in pairs(self.sessions) do
    if session.connected and session.map_id == map_id then
      self:push_pending(session.address, packet)
    end
  end
end

-- Queue Avatar.Remove to sessions near an origin position (excluding player_id).
function World:broadcast_remove_from(origin, player_id, warp_effect)
  if not origin or not player_id then
    return
  end

  local remove = Packet.new(Family.Avatar, Action.Remove)
  remove:add_int2(player_id)
  if warp_effect ~= nil then
    remove:add_int1(warp_effect)
  end

  for _, session in pairs(self.sessions) do
    if session.connected and session.id ~= player_id and self:in_range(origin, session) then
      self:push_pending(session.address, remove)
    end
  end
end

function World:find_session_by_account(account_name)
  for _, session in pairs(self.sessions) do
    if session.account == account_name and session.connected then
      return session
    end
  end

  return nil
end

function World:find_session_by_address(address)
  for _, session in pairs(self.sessions) do
    if session.address == address and session.connected then
      return session
    end
  end

  return nil
end

function World:has_map(map_id)
  return self.maps[map_id] ~= nil
end

function World:get_map_meta(map_id)
  local map = self.maps[map_id]
  if map == nil then
    return nil
  end
  return map.meta
end

function World:get_map_relog(map_id)
  local meta = self:get_map_meta(map_id)
  if not meta then
    return nil
  end

  local x = tonumber(meta.relog_x) or 0
  local y = tonumber(meta.relog_y) or 0
  if x <= 0 or y <= 0 then
    return nil
  end

  return { x = x, y = y }
end

function World:arena_spawn_point(x, y)
  for _, spawn in ipairs((self.arena and self.arena.spawns) or {}) do
    if spawn.from and spawn.from.x == x and spawn.from.y == y then
      return spawn.to
    end
  end

  return nil
end

function World:request_local_warp(session, map_id, x, y, direction)
  if not session or not session.connected then
    return false
  end

  local target_map = tonumber(map_id) or 0
  local target_x = tonumber(x) or 0
  local target_y = tonumber(y) or 0
  local target_direction = tonumber(direction) or session.direction or 0
  if target_direction < 0 or target_direction > 3 then
    target_direction = 0
  end
  local session_id = math.random(10, 64008)

  session.pending_warp = {
    map_id = target_map,
    x = target_x,
    y = target_y,
    direction = target_direction,
    session_id = session_id,
    warp_type = 1, -- Local
  }

  local packet = Packet.new(Family.Warp, Action.Request)
  packet:add_int1(1) -- WarpType.Local
  packet:add_int2(target_map)
  packet:add_int2(session_id)
  self:push_pending(session.address, packet)
  return true
end

function World:arena_respawn(session)
  local target_map = session.map_id
  local target_x = session.x
  local target_y = session.y
  local target_direction = 0

  local relog = self:get_map_relog(session.map_id)
  if relog then
    target_x = relog.x
    target_y = relog.y
  else
    -- Fallback to configured spawn if EMF relog is unavailable.
    local spawn = self.arena_spawn or {}
    if spawn.map and spawn.map > 0 then
      target_map = spawn.map
    end
    if spawn.x and spawn.x >= 0 then
      target_x = spawn.x
    end
    if spawn.y and spawn.y >= 0 then
      target_y = spawn.y
    end
    target_direction = spawn.direction or 0
  end

  -- In arena flow (same-map ejection), notify victim via local warp.
  if target_map == session.map_id then
    local warped = self:request_local_warp(
      session,
      target_map,
      target_x,
      target_y,
      target_direction
    )
    if warped then
      return
    end
  end

  -- Fallback if warp request could not be queued.
  session.map_id = target_map
  session.x = target_x
  session.y = target_y
  session.direction = target_direction
end

function World:send_arena_full()
  local packet = Packet.new(Family.Arena, Action.Drop)
  packet:add_string("N")
  self:broadcast_map(self.arena.map, packet)
end

function World:send_arena_launch(players_count)
  local packet = Packet.new(Family.Arena, Action.Use)
  packet:add_int1(players_count)
  self:broadcast_map(self.arena.map, packet)
end

function World:send_arena_spec(killer_session, victim_session, direction)
  local packet = Packet.new(Family.Arena, Action.Spec)
  packet:add_int2(killer_session.id)
  packet:add_byte(255)
  packet:add_int1(direction or killer_session.direction or 0)
  packet:add_byte(255)
  packet:add_int4(killer_session.arena_kills or 0)
  packet:add_byte(255)
  packet:add_string(session_name(killer_session))
  packet:add_byte(255)
  packet:add_string(session_name(victim_session))
  self:broadcast_map(self.arena.map, packet)
end

function World:send_arena_accept(winner_session, victim_session)
  local winner_name = session_name(winner_session)
  local packet = Packet.new(Family.Arena, Action.Accept)
  packet:add_string(winner_name)
  packet:add_byte(255)
  packet:add_int4((winner_session and winner_session.arena_kills) or 0)
  packet:add_byte(255)
  packet:add_string(winner_name)
  packet:add_byte(255)
  packet:add_string(session_name(victim_session))
  self:broadcast_map(self.arena.map, packet)
end

function World:arena_queue_candidates()
  local candidates = {}

  for _, session in pairs(self.sessions) do
    if session.connected and not session.arena_in and session.map_id == self.arena.map then
      local to = self:arena_spawn_point(session.x, session.y)
      if to then
        candidates[#candidates + 1] = { session = session, to = to }
      end
    end
  end

  table.sort(candidates, function(a, b)
    return a.session.id < b.session.id
  end)

  return candidates
end

function World:start_arena_round()
  if not self.arena_ready then
    return false
  end

  local queued = self:arena_queue_candidates()
  if #queued == 0 then
    return false
  end

  local active_count = #self.arena_round.players
  local max_players = math.max(1, self.arena.block or 4)
  if active_count >= max_players then
    self:send_arena_full()
    return false
  end

  if active_count == 0 and #queued == 1 and not self.arena.allow_single_player then
    return false
  end

  local slots = math.max(0, max_players - active_count)
  local picked_count = math.min(#queued, slots)
  if picked_count <= 0 then
    return false
  end

  self:send_arena_launch(picked_count)

  for i = 1, picked_count do
    local entry = queued[i]
    local session = entry.session

    session.arena_in = true
    session.arena_kills = 0

    local warped = self:request_local_warp(
      session,
      session.map_id,
      entry.to.x,
      entry.to.y,
      session.direction
    )
    if not warped then
      session.x = entry.to.x
      session.y = entry.to.y
    end

    if not contains(self.arena_round.players, session.id) then
      self.arena_round.players[#self.arena_round.players + 1] = session.id
    end
  end

  self.arena_round.active = #self.arena_round.players > 0
  self.arena_round.ticks = 0
  return self.arena_round.active
end

function World:is_arena_session(session_id)
  return contains(self.arena_round.players, session_id)
end

function World:arena_eliminate(victim_id, killer_id, direction)
  if not contains(self.arena_round.players, victim_id) then
    return nil
  end

  local victim = self.sessions[victim_id]
  local killer = self.sessions[killer_id]
  if victim then
    victim.arena_in = false
    self:arena_respawn(victim)
  end

  if killer ~= nil then
    killer.arena_kills = (killer.arena_kills or 0) + 1
  end

  local kept = {}
  for _, id in ipairs(self.arena_round.players) do
    local session = self.sessions[id]
    if id ~= victim_id and session ~= nil and session.connected then
      kept[#kept + 1] = id
    end
  end
  self.arena_round.players = kept
  self.arena_round.active = #kept > 0

  if #kept == 0 then
    self.arena_round.ticks = 0
    return nil
  end

  if #kept == 1 then
    local winner = self.sessions[kept[1]]
    if winner ~= nil and victim ~= nil then
      self:send_arena_accept(winner, victim)
    end

    -- End of round: eject the winner as well so both players leave arena combat.
    if winner ~= nil then
      winner.arena_in = false
      self:arena_respawn(winner)
      winner.arena_kills = 0
    end

    self.arena_round.players = {}
    self.arena_round.active = false
    self.arena_round.ticks = 0
    self.arena_round.winner = winner
    return winner
  end

  if killer ~= nil and victim ~= nil then
    self:send_arena_spec(killer, victim, direction)
  end

  return nil
end

function World:tick_arena()
  self.arena_round.ticks = self.arena_round.ticks + 1

  local online = {}
  for _, id in ipairs(self.arena_round.players) do
    local session = self.sessions[id]
    if session ~= nil and session.connected and session.map_id == self.arena.map then
      online[#online + 1] = id
    elseif session ~= nil then
      session.arena_in = false
    end
  end

  self.arena_round.players = online
  self.arena_round.active = #online > 0

  local rate = tonumber(self.arena.rate) or 0
  if rate > 0 and (self.arena_round.ticks % rate) == 0 then
    self:start_arena_round()
  end

  local winner = self.arena_round.winner
  self.arena_round.winner = nil
  return winner
end

function World:create_session(address, account_name)
  local session = Session.new(self.next_session_id, address)
  session.account = account_name

  self.next_session_id = self.next_session_id + 1
  self:add_session(session)

  return session
end

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
