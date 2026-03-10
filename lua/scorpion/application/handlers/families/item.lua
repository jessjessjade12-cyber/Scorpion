local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")
local MovementSupport = require("scorpion.application.handlers.support.movement_support")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local MAX_INT4 = 4097152080
local MAX_INT3 = 16194276
local MAX_COORD = 252
local DROP_DISTANCE = 2
local GUI_DROP_COORD = 254

local M = {}

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp_int4(value)
  return clamp(to_int(value, 0), 0, MAX_INT4)
end

local function clamp_int3(value)
  return clamp(to_int(value, 0), 0, MAX_INT3)
end

local function map_coord_limits(world, map_id)
  local max_x = MAX_COORD
  local max_y = MAX_COORD
  local map_meta = world:get_map_meta(map_id)

  if map_meta then
    max_x = clamp(to_int(map_meta.width, MAX_COORD), 0, MAX_COORD)
    max_y = clamp(to_int(map_meta.height, MAX_COORD), 0, MAX_COORD)
  end

  return max_x, max_y, map_meta
end

local function manhattan_distance(a, b)
  return math.abs((to_int(a.x, 0) or 0) - (to_int(b.x, 0) or 0))
    + math.abs((to_int(a.y, 0) or 0) - (to_int(b.y, 0) or 0))
end

local function resolve_drop_coords(world, session, requested_x, requested_y)
  local x = to_int(requested_x, 0)
  local y = to_int(requested_y, 0)

  if x >= GUI_DROP_COORD or y >= GUI_DROP_COORD then
    x = to_int(session.x, 0)
    y = to_int(session.y, 0)
  end

  local max_x, max_y = map_coord_limits(world, session.map_id)
  x = clamp(x, 0, max_x)
  y = clamp(y, 0, max_y)

  return x, y
end

local function can_reach_coords(session, x, y)
  return manhattan_distance(session, { x = x, y = y }) <= DROP_DISTANCE
end

local function broadcast_item_near(world, origin, packet, options)
  options = options or {}
  local include_session_id = to_int(options.include_session_id, 0)
  local exclude_session_id = to_int(options.exclude_session_id, 0)
  local include_sent = false

  local candidates = world.list_nearby_sessions
    and world:list_nearby_sessions(origin, 15)
    or world.sessions

  for _, receiver in pairs(candidates) do
    local include_self = include_session_id > 0 and receiver.id == include_session_id
    local skip_excluded = exclude_session_id > 0 and receiver.id == exclude_session_id
    if not skip_excluded
      and receiver.connected
      and receiver.pending_warp == nil
      and receiver.address ~= nil
      and receiver.map_id == origin.map_id
      and (include_self or world:in_client_range(receiver, origin))
    then
      include_sent = include_sent or include_self
      world:push_pending(receiver.address, packet)
    end
  end

  if include_session_id > 0 and not include_sent then
    local include_session = world.sessions[include_session_id]
    if include_session
      and include_session.connected
      and include_session.pending_warp == nil
      and include_session.address ~= nil
      and include_session.map_id == origin.map_id
    then
      world:push_pending(include_session.address, packet)
    end
  end
end

local function item_add_packet(item_uid, item_id, amount, x, y)
  local packet = Packet.new(Family.Item, Action.Add)
  packet:add_int2(item_id)
  packet:add_int2(item_uid)
  packet:add_int3(amount)
  packet:add_int1(x)
  packet:add_int1(y)
  return packet
end

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "item before login"
  end
  if not (session.character_id and session.character_id > 0) then
    return true
  end

  InventoryState.ensure(self, session)

  if packet.action == Action.Use then
    local item_id = to_int(packet:get_int2(), 0)
    if item_id <= 0 then
      return true
    end

    if InventoryState.item_amount(session, item_id) <= 0 then
      local missing = Packet.new(Family.Item, Action.Agree)
      missing:add_int2(item_id)
      return missing
    end

    return true
  end

  if packet.action == Action.Drop then
    local item_id = to_int(packet:get_int2(), 0)
    local amount = clamp_int3(packet:get_int3())
    local requested_x = to_int(packet:get_int1(), 0)
    local requested_y = to_int(packet:get_int1(), 0)

    if item_id <= 0 or amount <= 0 then
      return true
    end

    local owned = InventoryState.item_amount(session, item_id)
    if owned <= 0 then
      return true
    end

    local drop_amount = math.min(owned, amount)
    local x, y = resolve_drop_coords(self.world, session, requested_x, requested_y)
    if not can_reach_coords(session, x, y) then
      return true
    end

    local _, _, map_meta = map_coord_limits(self.world, session.map_id)
    if map_meta and not MovementSupport.is_tile_walkable(map_meta, x, y) then
      return true
    end

    InventoryState.remove_item(session, item_id, drop_amount)

    local dropped = self.world:add_map_item(session.map_id, item_id, drop_amount, x, y, session.id)
    if not dropped then
      InventoryState.add_item(session, item_id, drop_amount)
      return true
    end

    local reply = Packet.new(Family.Item, Action.Drop)
    reply:add_int2(item_id)
    reply:add_int3(drop_amount)
    reply:add_int4(InventoryState.item_amount(session, item_id))
    reply:add_int2(dropped.uid)
    reply:add_int1(dropped.x)
    reply:add_int1(dropped.y)
    InventoryState.add_weight(reply, self, session)

    local add = item_add_packet(dropped.uid, dropped.id, dropped.amount, dropped.x, dropped.y)
    broadcast_item_near(self.world, {
      map_id = session.map_id,
      x = dropped.x,
      y = dropped.y,
    }, add, {
      exclude_session_id = session.id,
    })

    return reply
  end

  if packet.action == Action.Get then
    local item_uid = to_int(packet:get_int2(), 0)
    if item_uid <= 0 then
      return true
    end

    local ground = self.world:find_map_item(session.map_id, item_uid)
    if not ground then
      return true
    end

    if not can_reach_coords(session, ground.x, ground.y) then
      return true
    end

    local owned = InventoryState.item_amount(session, ground.id)
    local room = math.max(0, MAX_INT4 - owned)
    if room <= 0 then
      return true
    end

    local to_take = math.min(clamp_int3(ground.amount), room)
    if to_take <= 0 then
      return true
    end

    local taken, remaining = self.world:take_map_item(session.map_id, item_uid, to_take)
    if not taken then
      return true
    end

    InventoryState.add_item(session, taken.id, taken.amount)

    local reply = Packet.new(Family.Item, Action.Get)
    reply:add_int2(taken.uid)
    reply:add_int2(taken.id)
    reply:add_int3(taken.amount)
    InventoryState.add_weight(reply, self, session)

    local origin = {
      map_id = session.map_id,
      x = taken.x,
      y = taken.y,
    }

    local remove = Packet.new(Family.Item, Action.Remove)
    remove:add_int2(taken.uid)
    broadcast_item_near(self.world, origin, remove, {
      include_session_id = session.id,
    })

    if remaining and remaining > 0 then
      local add = item_add_packet(taken.uid, taken.id, remaining, taken.x, taken.y)
      broadcast_item_near(self.world, origin, add, {
        include_session_id = session.id,
      })
    end

    return reply
  end

  if packet.action == Action.Junk then
    local item_id = to_int(packet:get_int2(), 0)
    local amount = clamp_int4(packet:get_int4())
    if item_id <= 0 or amount <= 0 then
      return true
    end

    local owned = InventoryState.item_amount(session, item_id)
    if owned <= 0 then
      return true
    end

    local removed = math.min(owned, amount)
    InventoryState.remove_item(session, item_id, removed)

    local reply = Packet.new(Family.Item, Action.Junk)
    reply:add_int2(item_id)
    reply:add_int3(removed)
    reply:add_int4(InventoryState.item_amount(session, item_id))
    InventoryState.add_weight(reply, self, session)
    return reply
  end

  return true
end

return M
