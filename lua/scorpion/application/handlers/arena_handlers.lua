local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action

local ArenaHandlers = {}
ArenaHandlers.__index = ArenaHandlers

-- Tile specs treated as impassable for attack collision.
local BLOCKED_TILE_SPECS = {
  [0] = true,  -- Wall
  [1] = true,  -- ChairDown
  [2] = true,  -- ChairLeft
  [3] = true,  -- ChairRight
  [4] = true,  -- ChairUp
  [5] = true,  -- ChairDownRight
  [6] = true,  -- ChairUpLeft
  [7] = true,  -- ChairAll
  [9] = true,  -- Chest
  [16] = true, -- BankVault
  [18] = true, -- Edge
  [20] = true, -- Board1
  [21] = true, -- Board2
  [22] = true, -- Board3
  [23] = true, -- Board4
  [24] = true, -- Board5
  [25] = true, -- Board6
  [26] = true, -- Board7
  [27] = true, -- Board8
  [28] = true, -- Jukebox
}

local function get_next_coords(x, y, direction, width, height)
  local nx, ny = x, y
  if direction == 0 then
    ny = y + 1
  elseif direction == 1 then
    nx = x - 1
  elseif direction == 2 then
    ny = y - 1
  elseif direction == 3 then
    nx = x + 1
  end

  return util.clamp(nx, 0, width), util.clamp(ny, 0, height)
end

function ArenaHandlers.new(deps)
  return setmetatable({
    settings = deps.settings,
    world = deps.world,
  }, ArenaHandlers)
end

function ArenaHandlers:spawn_profile()
  local spawn = self.settings.new_character
  return {
    direction = spawn.spawn_direction,
    map = spawn.spawn_map,
    x = spawn.spawn_x,
    y = spawn.spawn_y,
  }
end

function ArenaHandlers:on_login(session)
  local spawn = self:spawn_profile()
  session.map_id = spawn.map
  session.x = spawn.x
  session.y = spawn.y
  session.direction = spawn.direction
end

function ArenaHandlers:get_map_meta(map_id)
  local map = self.world.maps[map_id]
  if not map then
    return nil
  end
  return map.meta
end

function ArenaHandlers:get_tile_spec(meta, x, y)
  if not meta or not meta.tile_spec_rows then
    return nil
  end

  for _, row in ipairs(meta.tile_spec_rows) do
    if row.y == y then
      for _, tile in ipairs(row.tiles or {}) do
        if tile.x == x then
          return tile.tile_spec
        end
      end
      return nil
    end
  end

  return nil
end

function ArenaHandlers:is_tile_walkable(meta, x, y)
  local tile_spec = self:get_tile_spec(meta, x, y)
  if tile_spec == nil then
    return true
  end
  return not BLOCKED_TILE_SPECS[tile_spec]
end

function ArenaHandlers:get_attack_target_player_id(attacker_session, direction)
  if not self.world:is_arena_session(attacker_session.id) then
    return nil
  end

  local meta = self:get_map_meta(attacker_session.map_id)
  if not meta then
    return nil
  end

  local width = tonumber(meta.width) or 0
  local height = tonumber(meta.height) or 0
  local target_x, target_y = get_next_coords(
    attacker_session.x,
    attacker_session.y,
    direction,
    width,
    height
  )

  if not self:is_tile_walkable(meta, target_x, target_y) then
    return nil
  end

  for _, id in ipairs(self.world.arena_round.players) do
    local target = self.world.sessions[id]
    if id ~= attacker_session.id
      and target
      and target.connected
      and target.pending_warp == nil
      and target.map_id == attacker_session.map_id
      and target.x == target_x
      and target.y == target_y
    then
      return id
    end
  end

  return nil
end

function ArenaHandlers:handle_walk(packet, session)
  if packet.action ~= Action.Player and packet.action ~= Action.Special and packet.action ~= Action.Admin then
    return nil, ("unhandled walk action %d"):format(packet.action)
  end

  -- WalkPlayerClientPacket: direction (int1), timestamp (int3), x (int1), y (int1)
  session.direction = packet:get_int1()
  if session.direction < 0 or session.direction > 3 then
    session.direction = 0
  end
  packet:get_int3() -- timestamp (discard; server calculates position)
  packet:get_int1() -- client x (discard)
  packet:get_int1() -- client y (discard)

  local previous = {
    map_id = session.map_id,
    x = session.x,
    y = session.y,
  }

  if session.direction == 0 then
    session.y = session.y + 1
  elseif session.direction == 1 then
    session.x = session.x - 1
  elseif session.direction == 2 then
    session.y = session.y - 1
  elseif session.direction == 3 then
    session.x = session.x + 1
  end

  if session.x < 0 then session.x = 0 end
  if session.y < 0 then session.y = 0 end

  -- Broadcast Walk.Player to all nearby players on the same map
  local broadcast = Packet.new(Family.Walk, Action.Player)
  broadcast:add_int2(session.id)
  broadcast:add_int1(session.direction)
  broadcast:add_int1(session.x)
  broadcast:add_int1(session.y)
  self.world:broadcast_near(session, broadcast)

  -- Walk.Reply to the mover: include newly-visible players.
  local reply = Packet.new(Family.Walk, Action.Reply)
  local visible_player_ids = {}
  for _, other in pairs(self.world.sessions) do
    if other.id ~= session.id
      and other.connected
      and (other.character_id and other.character_id > 0)
      and other.map_id == session.map_id
      and self.world:in_client_range(session, other)
      and not self.world:in_client_range(previous, other)
    then
      visible_player_ids[#visible_player_ids + 1] = other.id
    end
  end
  table.sort(visible_player_ids)

  for _, player_id in ipairs(visible_player_ids) do
    reply:add_int2(player_id)
  end
  reply:add_byte(255) -- break
  reply:add_byte(255) -- break (0 items)
  return reply
end

function ArenaHandlers:handle_attack(packet, session)
  if packet.action ~= Action.Use then
    return nil, ("unhandled attack action %d"):format(packet.action)
  end

  session.direction = packet:get_int1()
  if session.direction < 0 or session.direction > 3 then
    session.direction = 0
  end
  packet:get_int3() -- timestamp

  local broadcast = Packet.new(Family.Attack, Action.Player)
  broadcast:add_int2(session.id)
  broadcast:add_int1(session.direction)
  self.world:broadcast_near(session, broadcast)

  if self.world:is_arena_session(session.id) then
    local victim_id = self:get_attack_target_player_id(session, session.direction)
    if victim_id ~= nil then
      self.world:arena_eliminate(victim_id, session.id, session.direction)
    end
  end

  return true
end

function ArenaHandlers:handle_warp(packet, session)
  if packet.action == Action.Accept then
    local reply = Packet.new(Family.Warp, Action.Agree)
    reply:add_int2(session.map_id)
    reply:add_int1(session.x)
    reply:add_int1(session.y)
    reply:add_int1(session.direction)
    return reply
  end

  if packet.action == Action.Take then
    return Packet.new(Family.Raw, Action.Raw)
  end

  return nil, ("unhandled warp action %d"):format(packet.action)
end

function ArenaHandlers:arena_only_map_allowed(map_id)
  if not self.settings.arena.only then
    return true
  end

  return map_id == self.settings.arena.map
end

return ArenaHandlers
