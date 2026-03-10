local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action
local LoginReply = Protocol.LoginReply

local M = {}

function M.handle(self, packet, context)
  if packet.action ~= Action.Request then
    return nil, ("unhandled login action %d"):format(packet.action)
  end

  local username = string.lower(packet:get_break_string())
  local password = packet:get_break_string()
  self:trace("info", "login request", {
    address = context and context.address or "unknown",
    username = username,
  })

  local reply = Packet.new(Family.Login, Action.Reply)
  local account = self.accounts:find(username)

  if account == nil then
    self:trace("warn", "login rejected", { username = username, reason = "unknown_user" })
    reply:add_int2(LoginReply.UnknownUser)
    return reply
  end

  if account.password ~= password then
    self:trace("warn", "login rejected", { username = username, reason = "wrong_password" })
    reply:add_int2(LoginReply.WrongPassword)
    return reply
  end

  if self.world:find_session_by_account(username) ~= nil then
    self:trace("warn", "login rejected", { username = username, reason = "already_logged_in" })
    reply:add_int2(LoginReply.AlreadyLoggedIn)
    return reply
  end

  local session = self.world:create_session((context and context.address) or "unknown", username)
  if context then
    context.session_id = session.id
  end

  reply:add_int2(LoginReply.OK)
  self:build_characters_packet(reply, username)
  self:trace("info", "login success", { username = username, session_id = session.id })
  return reply
end

return M
