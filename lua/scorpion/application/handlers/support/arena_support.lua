local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

-- Tile specs treated as impassable for melee collision checks.
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

function M.read_attack_direction(packet)
  local direction = M.normalize_direction(packet:get_int1())
  packet:get_int3() -- timestamp
  return direction
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

function M.attack_player_packet(session)
  local packet = Packet.new(Family.Attack, Action.Player)
  packet:add_int2(session.id)
  packet:add_int1(session.direction)
  return packet
end

return M
