local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

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

function M.send_arena_full(self)
  local packet = Packet.new(Family.Arena, Action.Drop)
  packet:add_string("N")
  self:broadcast_map(self.arena.map, packet)
end

function M.send_arena_launch(self, players_count)
  local packet = Packet.new(Family.Arena, Action.Use)
  packet:add_int1(players_count)
  self:broadcast_map(self.arena.map, packet)
end

function M.send_arena_spec(self, killer_session, victim_session, direction)
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

function M.send_arena_accept(self, winner_session, victim_session)
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

function M.arena_queue_candidates(self)
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

function M.start_arena_round(self)
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

function M.is_arena_session(self, session_id)
  return contains(self.arena_round.players, session_id)
end

function M.arena_eliminate(self, victim_id, killer_id, direction)
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

function M.tick_arena(self)
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

return M
