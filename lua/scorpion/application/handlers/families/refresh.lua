local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "refresh before login"
  end
  if packet.action ~= Action.Request then
    return true
  end
  local nearby = self:get_nearby_sessions(session)
  local nearby_npcs = self:get_nearby_npcs(session)
  local reply = Packet.new(Family.Refresh, Action.Reply)
  self:add_nearby_info(reply, nearby, nearby_npcs)
  return reply
end

return M
