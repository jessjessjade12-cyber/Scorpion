local Protocol = require("scorpion.transport.protocol")

local Action = Protocol.Action

local M = {}

local ActionHandlers = {
  [Action.Request] = require("scorpion.application.handlers.families.gamedata.request"),
  [Action.Agree] = require("scorpion.application.handlers.families.gamedata.agree"),
  [Action.Message] = require("scorpion.application.handlers.families.gamedata.message"),
}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "gamedata before login"
  end

  local handler = ActionHandlers[packet.action]
  if not handler then
    return nil, ("unhandled gamedata action %d"):format(packet.action)
  end
  return handler.handle(self, packet, session)
end

return M
