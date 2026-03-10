local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local ReplyContinue = 1000
local ReplyStrOK = "OK"
local ReplyStrNO = "NO"

local AccountReply = {
  AlreadyExists = 1,
  NotApproved = 2,
  Created = 3,
  ChangeFailed = 5,
  Changed = 6,
}

local M = {}

function M.handle(self, packet, context)
  if packet.action == Action.Accept then
    self:trace("info", "account accept", {
      address = context and context.address or "unknown",
    })
    local accepted = Packet.new(Family.Account, Action.Accept)
    accepted:add_int2(1)
    return accepted
  end

  local reply = Packet.new(Family.Account, Action.Reply)

  if packet.action == Action.Request then
    local account_name = string.lower(packet:get_break_string())
    self:trace("info", "account request", {
      address = context and context.address or "unknown",
      username = account_name,
    })

    if not self:valid_account_name(account_name) then
      self:trace("warn", "account request rejected", { reason = "invalid_name", username = account_name })
      reply:add_int2(AccountReply.NotApproved)
      reply:add_string(ReplyStrNO)
    elseif self.accounts:account_exists(account_name) then
      self:trace("warn", "account request rejected", { reason = "already_exists", username = account_name })
      reply:add_int2(AccountReply.AlreadyExists)
      reply:add_string(ReplyStrNO)
    else
      self:trace("info", "account request accepted", { username = account_name })
      reply:add_int2(ReplyContinue)
      reply:add_string(ReplyStrOK)
    end
    return reply
  end

  if packet.action == Action.Create then
    local raw = packet.data
    local function parse_create(skip)
      local p = Packet.new(Family.Account, Action.Create, raw)
      p:discard(skip)
      local name = string.lower(p:get_break_string())
      local pass = p:get_break_string()
      for _ = 1, 5 do
        p:get_break_string()
      end
      return name, pass
    end

    self:trace("info", "account create", {
      address = context and context.address or "unknown",
      bytes = #raw,
    })

    local account_name, password = parse_create(3)
    local parse_mode = 3
    if not self:valid_account_name(account_name) then
      local fallback_name, fallback_password = parse_create(2)
      if self:valid_account_name(fallback_name) then
        account_name = fallback_name
        password = fallback_password
        parse_mode = 2
      end
    end

    self:trace("info", "account create parse", { mode = parse_mode, username = account_name })

    if not self:valid_account_name(account_name) then
      self:trace("warn", "account create rejected", { reason = "invalid_name", username = account_name })
      reply:add_int2(AccountReply.NotApproved)
      reply:add_string(ReplyStrNO)
      return reply
    end

    if self.accounts:account_exists(account_name) then
      self:trace("warn", "account create rejected", { reason = "already_exists", username = account_name })
      reply:add_int2(AccountReply.AlreadyExists)
      reply:add_string(ReplyStrNO)
      return reply
    end

    local created = self.accounts:create_account(account_name, password)
    if not created then
      self:trace("warn", "account create rejected", { reason = "create_failed", username = account_name })
      reply:add_int2(AccountReply.ChangeFailed)
      reply:add_string(ReplyStrNO)
      return reply
    end

    self:trace("info", "account create success", { username = account_name })
    reply:add_int2(AccountReply.Created)
    reply:add_string(ReplyStrOK)
    return reply
  end

  if packet.action == Action.Agree then
    self:trace("warn", "account agree unsupported", { address = context and context.address or "unknown" })
    reply:add_int2(AccountReply.ChangeFailed)
    reply:add_string(ReplyStrNO)
    return reply
  end

  return nil, ("unhandled account action %d"):format(packet.action)
end

return M
