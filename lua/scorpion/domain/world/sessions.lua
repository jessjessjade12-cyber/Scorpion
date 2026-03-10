local Session = require("scorpion.domain.session")

local M = {}

function M.add_session(self, session)
  self.sessions[session.id] = session
end

function M.remove_session(self, session_id)
  self.sessions[session_id] = nil
end

function M.find_session_by_account(self, account_name)
  for _, session in pairs(self.sessions) do
    if session.account == account_name and session.connected then
      return session
    end
  end

  return nil
end

function M.find_session_by_address(self, address)
  for _, session in pairs(self.sessions) do
    if session.address == address and session.connected then
      return session
    end
  end

  return nil
end

function M.create_session(self, address, account_name)
  local session = Session.new(self.next_session_id, address)
  session.account = account_name

  self.next_session_id = self.next_session_id + 1
  self:add_session(session)

  return session
end

return M
