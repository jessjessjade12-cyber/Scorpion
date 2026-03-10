local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, session)
  packet:discard(3)
  local character_id = packet:get_int4()
  if character_id > 0 then
    local requested = nil
    if character_id == (session.character_id or 0) then
      requested = self:resolve_session_character(session)
    else
      requested = self.accounts:get_character(session.account, character_id)
    end
    if requested then
      self:load_character_location(session, requested)
    end
  end

  self:apply_arena_only_location(session)
  self:apply_map_relog_location(session)
  InventoryState.ensure(self, session)

  if session.character_id and session.character_id > 0 then
    local character = self:resolve_session_character(session)
    if character then
      local appear = Packet.new(Family.Players, Action.Agree)
      self:add_nearby_info(appear, { { session = session, character = character } })
      self.world:broadcast_near(session, appear)
    end
  end

  local nearby = self:get_nearby_sessions(session)
  local nearby_npcs = self:get_nearby_npcs(session)
  local nearby_items = self:get_nearby_items(session)
  local reply = Packet.new(Family.GameData, Action.Reply)
  reply:add_int2(2) -- WelcomeCode::EnterGame
  reply:add_byte(255)
  reply:add_break_string(self.settings.name or "Kalandra")
  for _ = 1, 8 do
    reply:add_break_string("")
  end

  InventoryState.add_weight(reply, self, session)
  for _, item in ipairs(InventoryState.list_items(session)) do
    reply:add_int2(item.item_id)
    reply:add_int4(item.amount)
  end

  reply:add_byte(255)
  reply:add_byte(255)
  self:add_nearby_info(reply, nearby, nearby_npcs, nearby_items)
  return reply
end

return M
