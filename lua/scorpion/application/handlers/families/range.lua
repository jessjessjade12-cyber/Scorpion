local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "range before login"
  end
  if packet.action ~= Action.Request then
    return true
  end

  local player_ids = self:parse_range_request(packet)
  local nearby = self:get_requested_nearby_sessions(session, player_ids)

  local reply = Packet.new(Family.Range, Action.Reply)
  self:add_nearby_info(reply, nearby)
  return reply
end

return M
