local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(_self, packet, context)
  if packet.action == Action.Ping then
    context.ping_replied = true
  end
  return Packet.new(Family.Message, Action.Pong)
end

return M
