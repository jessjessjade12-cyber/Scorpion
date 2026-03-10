local M = {}

function M.handle(self, packet, session)
  local file_id = packet:get_int1()
  self:trace("info", "gamedata agree", { account = session.account, file_id = file_id })

  local reply, err = self:send_gamedata_blob(file_id, packet)
  if not reply then
    self:trace("warn", "gamedata agree rejected", {
      account = session.account,
      file_id = file_id,
      reason = err or "unknown",
    })
    return nil, err
  end

  return reply
end

return M
