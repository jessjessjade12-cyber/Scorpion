local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "talk before login"
  end
  if not (session.character_id and session.character_id > 0) then
    return true
  end

  local sender = self.accounts:get_character(session.account, session.character_id)
  if not sender then
    return true
  end

  if packet.action == Action.Report or packet.action == Action.Player or packet.action == Action.Use then
    local text = packet:get_string()
    if #text == 0 then
      return true
    end
    local speak = Packet.new(Family.Talk, Action.Player)
    speak:add_int2(session.id)
    speak:add_string(text)
    self.world:broadcast_near(session, speak)
    return true
  end

  if packet.action == Action.Tell then
    local raw_target = packet:get_break_string()
    local target_name = string.lower(raw_target or "")
    local text = packet:get_string()
    if target_name == "" or #text == 0 then
      return true
    end

    local target_session = self:find_session_by_character_name(target_name)
    if not target_session then
      local not_found = Packet.new(Family.Talk, Action.Reply)
      not_found:add_int2(1)
      not_found:add_string(raw_target or target_name)
      return not_found
    end

    local tell = Packet.new(Family.Talk, Action.Tell)
    tell:add_break_string(sender.name or session.character or "")
    tell:add_break_string(text)
    self.world:push_pending(target_session.address, tell)
    return true
  end

  if packet.action == Action.Message then
    local text = packet:get_string()
    if #text == 0 then
      return true
    end
    local global = Packet.new(Family.Talk, Action.Message)
    global:add_break_string(sender.name or session.character or "")
    global:add_break_string(text)
    self:broadcast_all(global)
    return true
  end

  if packet.action == Action.Request then
    local text = packet:get_string()
    if #text == 0 then
      return true
    end
    local guild = Packet.new(Family.Talk, Action.Request)
    guild:add_break_string(sender.name or session.character or "")
    guild:add_break_string(text)
    self.world:broadcast_near(session, guild)
    return true
  end

  if packet.action == Action.Open then
    return true
  end

  if packet.action == Action.Admin or packet.action == Action.Announce or packet.action == Action.Report then
    return true
  end

  return true
end

return M
