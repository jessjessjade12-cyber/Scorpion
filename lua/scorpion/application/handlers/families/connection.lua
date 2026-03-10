local Protocol = require("scorpion.transport.protocol")

local Action = Protocol.Action

local M = {}

function M.handle(_self, packet, context)
  if packet.action == Action.Ping then
    context.ping_replied = true
  end
  return true
end

return M
