local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "npc range before login"
  end
  if packet.action ~= Action.Request then
    return true
  end

  local reply = Packet.new(Family.Mob, Action.Agree)
  reply:add_int1(0)
  return reply
end

return M
