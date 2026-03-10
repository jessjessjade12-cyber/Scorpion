local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local MAX_INT4 = 4097152080

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
