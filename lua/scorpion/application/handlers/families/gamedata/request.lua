local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, session)
  local requested_id = packet:get_int4()
  if requested_id > 0 then
    local requested = nil
    if requested_id == (session.character_id or 0) then
      requested = self:resolve_session_character(session)
    else
      requested = self.accounts:get_character(session.account, requested_id)
    end
    if requested then
      self:load_character_location(session, requested)
      self:apply_arena_only_location(session)
    end
  end

  InventoryState.ensure(self, session)

  local map = self.world.maps[session.map_id]
  if map == nil or map.data == nil then
    return nil, ("request for invalid map #%d"):format(session.map_id)
  end

  local character = self:resolve_session_character(session)
  local character_id = (character and character.id) or session.id

  local reply = Packet.new(Family.GameData, Action.Reply)
  reply:add_int2(1) -- WelcomeCode::SelectCharacter
  reply:add_int2(session.id)
  reply:add_int4(character_id)
  reply:add_int2(session.map_id)
  self:add_rid(reply, map.data)
  reply:add_int3(#map.data)
  self:add_pub_meta(reply, self:get_pub_blob("eif"))
  self:add_pub_meta(reply, self:get_pub_blob("enf"))
  self:add_pub_meta(reply, self:get_pub_blob("esf"))
  self:add_pub_meta(reply, self:get_pub_blob("ecf"))

  reply:add_break_string((character and character.name) or (session.character or ""))
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_break_string("")
  reply:add_int1(1)
  reply:add_string("   ")

  reply:add_int1((character and character.admin) or 0)
  reply:add_int1((character and character.level) or 0)
  reply:add_int4(0)
  reply:add_int4(0)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(1000)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  for _, item_id in ipairs(InventoryState.welcome_equipment_item_ids(session)) do
    reply:add_int2(item_id)
  end
  reply:add_int1(0)
  reply:add_int1(4)
  reply:add_int1(24)
  reply:add_int1(24)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(1)
  reply:add_int2(1)
  reply:add_int1(0)
  reply:add_byte(255)
  return reply
end

return M
