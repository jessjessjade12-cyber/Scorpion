local M = {}

function M.handle(self, packet, context)
  self:trace("warn", "unhandled packet family", {
    address = context and context.address or "unknown",
    family = packet.family,
    action = packet.action,
  })
  return true
end

return M
