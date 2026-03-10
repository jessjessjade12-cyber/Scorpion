local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local ReplyContinue = 1000
local ReplyStrOK = "OK"
local ReplyStrNO = "NO"

local CharacterReply = {
  AlreadyExists = 1,
  Full = 2,
  NotApproved = 4,
  OK = 5,
  Deleted = 6,
}

local MaxCreateSex = 1
local MaxCreateHairStyle = 20
local MaxCreateHairColour = 9
local MaxCreateRace = 3

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    self:trace("warn", "character packet rejected", {
      action = packet.action,
      address = context and context.address or "unknown",
      reason = "before_login",
    })
    return nil, "character before login"
  end

  local reply = Packet.new(Family.Character, Action.Reply)

  if packet.action == Action.Request then
    if self.accounts:character_count(session.account) >= self:max_characters() then
      reply:add_int2(CharacterReply.Full)
      reply:add_string(ReplyStrNO)
    else
      reply:add_int2(ReplyContinue)
      reply:add_string(ReplyStrOK)
    end
    return reply
  end

  if packet.action == Action.Create then
    packet:discard(2)
    local sex = clamp(packet:get_int2(), 0, MaxCreateSex)
    local hair_style = clamp(packet:get_int2(), 1, MaxCreateHairStyle)
    local hair_color = clamp(packet:get_int2(), 0, MaxCreateHairColour)
    local race = clamp(packet:get_int2(), 0, MaxCreateRace)
    packet:discard()
    local name = string.lower(packet:get_break_string())
    self:trace("info", "character create", { account = session.account, name = name })

    if not self:valid_character_name(name) then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "invalid_name" })
      reply:add_int2(CharacterReply.NotApproved)
      return reply
    end

    if self.accounts:character_exists(name) then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "already_exists" })
      reply:add_int2(CharacterReply.AlreadyExists)
      return reply
    end

    if self.accounts:character_count(session.account) >= self:max_characters() then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "full" })
      reply:add_int2(CharacterReply.Full)
      return reply
    end

    local character = self.accounts:create_character(session.account, {
      hair_color = hair_color,
      hair_style = hair_style,
      race = race,
      sex = sex,
      name = name,
    })

    if not character then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "create_failed" })
      reply:add_int2(CharacterReply.NotApproved)
      return reply
    end

    self:trace("info", "character create success", { account = session.account, name = name, id = character.id })
    reply:add_int2(CharacterReply.OK)
    self:build_characters_packet(reply, session.account)
    return reply
  end

  if packet.action == Action.Remove then
    packet:discard(2)
    local character_id = packet:get_int4()
    local ok = self.accounts:remove_character(session.account, character_id)
    if not ok then
      return nil, "invalid delete id"
    end
    if session.character_id == character_id then
      session.character_id = 0
      session.character = nil
      session.map_id = 0
      session.x = 0
      session.y = 0
      session.direction = 0
    end
    reply:add_int2(CharacterReply.Deleted)
    self:build_characters_packet(reply, session.account)
    return reply
  end

  if packet.action == Action.Take then
    local character_id = packet:get_int4()
    local character = self.accounts:get_character(session.account, character_id)
    if not character then
      return nil, "invalid character id"
    end
    self:load_character_location(session, character)
    self:apply_arena_only_location(session)
    local take = Packet.new(Family.Character, Action.Player)
    take:add_int2(ReplyContinue)
    take:add_int4(character.id)
    return take
  end

  return nil, ("unhandled character action %d"):format(packet.action)
end

return M
