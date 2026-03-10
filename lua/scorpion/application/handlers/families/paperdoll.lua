local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local CHANGE_TYPE_EQUIPMENT = 1
local ICON_PLAYER = 1
local ITEM_TYPE_VISIBLE = {
  [10] = true, -- Weapon
  [11] = true, -- Shield
  [12] = true, -- Armor
  [13] = true, -- Hat
  [14] = true, -- Boots
}

local M = {}

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp_char(value)
  return clamp(to_int(value, 0), 0, 252)
end

local function add_avatar_change(reply, self, session)
  local graphics = InventoryState.visible_equipment_graphics(self, session)
  reply:add_int2(session.id)
  reply:add_int1(CHANGE_TYPE_EQUIPMENT)
  reply:add_int1(0)
  reply:add_int2(graphics.boots)
  reply:add_int2(graphics.armor)
  reply:add_int2(graphics.hat)
  reply:add_int2(graphics.weapon)
  reply:add_int2(graphics.shield)
end

local function add_default_equipment_stats(reply)
  reply:add_int2(10)
  reply:add_int2(10)
  for _ = 1, 6 do
    reply:add_int2(0)
  end
  for _ = 1, 5 do
    reply:add_int2(0)
  end
end

local function build_request_reply(self, target_session, target_character)
  InventoryState.ensure(self, target_session)

  local reply = Packet.new(Family.Paperdoll, Action.Reply)
  reply:add_break_string(target_character.name or "")
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_int2(target_session.id)
  reply:add_int1(0)
  reply:add_int1(clamp_char(target_character.sex or 0))
  reply:add_int1(clamp_char(target_character.admin or 0))

  for _, item_id in ipairs(InventoryState.paperdoll_equipment_item_ids(target_session)) do
    reply:add_int2(item_id)
  end

  reply:add_int1(ICON_PLAYER)
  return reply
end

local function broadcast_avatar_change(self, session)
  local nearby = Packet.new(Family.Avatar, Action.Agree)
  add_avatar_change(nearby, self, session)
  self.world:broadcast_near(session, nearby)
end

local function is_visible_change(self, item_id)
  local item = InventoryState.item_def(self, item_id)
  local item_type = to_int(item and item.type, -1)
  return ITEM_TYPE_VISIBLE[item_type] == true
end

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "paperdoll before login"
  end
  if not (session.character_id and session.character_id > 0) then
    return true
  end

  InventoryState.ensure(self, session)

  if packet.action == Action.Add then
    local item_id = to_int(packet:get_int2(), 0)
    local sub_loc = clamp_char(packet:get_int1())
    if item_id <= 0 then
      return true
    end

    local equipped = InventoryState.equip_item(self, session, item_id, sub_loc)
    if not equipped then
      return true
    end

    local reply = Packet.new(Family.Paperdoll, Action.Agree)
    add_avatar_change(reply, self, session)
    reply:add_int2(equipped.item_id)
    reply:add_int3(equipped.remaining_amount)
    reply:add_int1(equipped.sub_loc)
    add_default_equipment_stats(reply)
    if is_visible_change(self, equipped.item_id) then
      broadcast_avatar_change(self, session)
    end
    return reply
  end

  if packet.action == Action.Remove then
    local item_id = to_int(packet:get_int2(), 0)
    local sub_loc = clamp_char(packet:get_int1())
    if item_id <= 0 then
      return true
    end

    local unequipped = InventoryState.unequip_item(self, session, item_id, sub_loc)
    if not unequipped then
      return true
    end

    local reply = Packet.new(Family.Paperdoll, Action.Remove)
    add_avatar_change(reply, self, session)
    reply:add_int2(unequipped.item_id)
    reply:add_int1(unequipped.sub_loc)
    add_default_equipment_stats(reply)
    if is_visible_change(self, unequipped.item_id) then
      broadcast_avatar_change(self, session)
    end
    return reply
  end

  if packet.action == Action.Request then
    local player_id = to_int(packet:get_int2(), 0)
    if player_id <= 0 then
      player_id = session.id
    end

    local target_session = self.world.sessions[player_id]
    if not target_session or not target_session.connected then
      return true
    end
    if not (target_session.character_id and target_session.character_id > 0) then
      return true
    end

    local target_character = self.accounts:get_character(target_session.account, target_session.character_id)
    if not target_character then
      return true
    end

    return build_request_reply(self, target_session, target_character)
  end

  return true
end

return M
