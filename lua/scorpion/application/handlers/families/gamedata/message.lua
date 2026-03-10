local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, session)
  packet:discard(3)
  local character_id = packet:get_int4()
  if character_id > 0 then
    local requested = self.accounts:get_character(session.account, character_id)
    if requested then
      self:load_character_location(session, requested)
    end
  end

  self:apply_arena_only_location(session)
  self:apply_map_relog_location(session)

  if session.character_id and session.character_id > 0 then
    local character = self.accounts:get_character(session.account, session.character_id)
    if character then
      local appear = Packet.new(Family.Players, Action.Agree)
      self:add_nearby_info(appear, { { session = session, character = character } })
      self.world:broadcast_near(session, appear)
    end
  end

  local nearby = self:get_nearby_sessions(session)
  local reply = Packet.new(Family.GameData, Action.Reply)
  reply:add_int2(2) -- WelcomeCode::EnterGame
  reply:add_byte(255)
  reply:add_break_string(self.settings.name or "Kalandra")
  for _ = 1, 8 do
    reply:add_break_string("")
  end
  reply:add_int1(0)
  reply:add_int1(100)
  reply:add_byte(255)
  reply:add_byte(255)
  self:add_nearby_info(reply, nearby)
  return reply
end

return M
