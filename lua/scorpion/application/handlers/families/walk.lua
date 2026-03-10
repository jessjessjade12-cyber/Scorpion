local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "walk before login"
  end
  return self.movement:handle_walk(packet, session)
end

return M
