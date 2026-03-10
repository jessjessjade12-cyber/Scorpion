local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

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

local M = {}

function M.normalize_direction(direction)
  direction = tonumber(direction) or 0
  if direction < 0 or direction > 3 then
    return 0
  end
  return direction
end

-- WalkPlayerClientPacket: direction (int1), timestamp (int3), x (int1), y (int1)
function M.read_walk_direction(packet)
  local direction = M.normalize_direction(packet:get_int1())
  packet:get_int3() -- timestamp (discard; server calculates position)
  packet:get_int1() -- client x (discard)
  packet:get_int1() -- client y (discard)
  return direction
end

function M.read_attack_direction(packet)
  local direction = M.normalize_direction(packet:get_int1())
  packet:get_int3() -- timestamp
  return direction
end

function M.apply_step(session, direction)
  local previous = {
    map_id = session.map_id,
    x = session.x,
    y = session.y,
  }

  session.direction = M.normalize_direction(direction)

  if session.direction == 0 then
    session.y = session.y + 1
  elseif session.direction == 1 then
    session.x = session.x - 1
  elseif session.direction == 2 then
    session.y = session.y - 1
  elseif session.direction == 3 then
    session.x = session.x + 1
  end

  if session.x < 0 then
    session.x = 0
  end
  if session.y < 0 then
    session.y = 0
  end

  return previous
end

function M.newly_visible_player_ids(world, session, previous)
  local visible_player_ids = {}
  local candidates = {}
  local indexed = world.list_nearby_sessions ~= nil

  if indexed then
    for _, other in ipairs(world:list_nearby_sessions(session, 14)) do
      candidates[other.id] = other
    end
    for _, other in ipairs(world:list_nearby_sessions(previous, 14)) do
      candidates[other.id] = other
    end
  else
    for _, other in pairs(world.sessions) do
      candidates[other.id] = other
    end
  end

  for _, other in pairs(candidates) do
    if other.id ~= session.id
      and other.connected
      and (other.character_id and other.character_id > 0)
      and other.map_id == session.map_id
      and other.invisible ~= true
      and world:in_client_range(session, other)
      and not world:in_client_range(previous, other)
    then
      visible_player_ids[#visible_player_ids + 1] = other.id
    end
  end
  table.sort(visible_player_ids)
  return visible_player_ids
end

function M.newly_visible_npc_indexes(world, session, previous)
  local visible_npc_indexes = {}
  local session_id = tonumber(session and session.id) or 0
  local map_npcs = {}
  if world.list_map_npcs then
    map_npcs = world:list_map_npcs(session.map_id) or {}
  else
    local map_meta = world:get_map_meta(session.map_id)
    map_npcs = (map_meta and map_meta.npcs) or {}
  end

  for _, npc in ipairs(map_npcs) do
    local owner_session_id = tonumber(npc and npc.owner_session_id) or 0
    if session_id <= 0 or owner_session_id ~= session_id then
      local coords = npc.coords or {}
      local x = tonumber(coords.x) or tonumber(npc.x) or 0
      local y = tonumber(coords.y) or tonumber(npc.y) or 0
      local point = {
        map_id = session.map_id,
        x = x,
        y = y,
      }
      if world:in_client_range(session, point) and not world:in_client_range(previous, point) then
        local npc_index = clamp(tonumber(npc.index) or 0, 0, 252)
        if npc_index > 0 then
          visible_npc_indexes[#visible_npc_indexes + 1] = npc_index
        end
      end
    end
  end

  table.sort(visible_npc_indexes)
  return visible_npc_indexes
end

function M.next_coords(x, y, direction, width, height)
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

  return clamp(nx, 0, width), clamp(ny, 0, height)
end

function M.get_tile_spec(meta, x, y)
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

function M.is_tile_walkable(meta, x, y)
  local tile_spec = M.get_tile_spec(meta, x, y)
  if tile_spec == nil then
    return true
  end
  return not BLOCKED_TILE_SPECS[tile_spec]
end

function M.get_attack_target_player_id(world, attacker_session, direction)
  if not world:is_arena_session(attacker_session.id) then
    return nil
  end

  local meta = world:get_map_meta(attacker_session.map_id)
  if not meta then
    return nil
  end

  local width = tonumber(meta.width) or 0
  local height = tonumber(meta.height) or 0
  local target_x, target_y = M.next_coords(
    attacker_session.x,
    attacker_session.y,
    direction,
    width,
    height
  )

  if not M.is_tile_walkable(meta, target_x, target_y) then
    return nil
  end

  for _, id in ipairs(world.arena_round.players) do
    local target = world.sessions[id]
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

function M.walk_player_packet(session)
  local packet = Packet.new(Family.Walk, Action.Player)
  packet:add_int2(session.id)
  packet:add_int1(session.direction)
  packet:add_int1(session.x)
  packet:add_int1(session.y)
  return packet
end

function M.walk_reply_packet(visible_player_ids, visible_npc_indexes)
  local packet = Packet.new(Family.Walk, Action.Reply)
  for _, player_id in ipairs(visible_player_ids) do
    packet:add_int2(player_id)
  end
  packet:add_byte(255) -- break
  for _, npc_index in ipairs(visible_npc_indexes or {}) do
    packet:add_int1(npc_index)
  end
  packet:add_byte(255) -- break (0 items)
  return packet
end

function M.attack_player_packet(session)
  local packet = Packet.new(Family.Attack, Action.Player)
  packet:add_int2(session.id)
  packet:add_int1(session.direction)
  return packet
end

function M.warp_agree_packet(session)
  local packet = Packet.new(Family.Warp, Action.Agree)
  packet:add_int2(session.map_id)
  packet:add_int1(session.x)
  packet:add_int1(session.y)
  packet:add_int1(session.direction)
  return packet
end

function M.warp_take_packet()
  return Packet.new(Family.Raw, Action.Raw)
end

return M
