local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "attack before login"
  end
  local ok, err = self.arena:handle_attack(packet, session)
  if not ok then
    return nil, err
  end

  return true
end

return M
