local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "gamedata before login"
  end

  if packet.action == Action.Request then
    local requested_id = packet:get_int4()
    if requested_id > 0 then
      local character = self.accounts:get_character(session.account, requested_id)
      if character then
        self:load_character_location(session, character)
        self:apply_arena_only_location(session)
      end
    end

    local map = self.world.maps[session.map_id]
    if map == nil or map.data == nil then
      return nil, ("request for invalid map #%d"):format(session.map_id)
    end

    local character = self.accounts:get_character(session.account, session.character_id or 0)
    local character_id = (character and character.id) or session.id

    local reply = Packet.new(Family.GameData, Action.Reply)
    reply:add_int2(1) -- WelcomeCode::SelectCharacter
    reply:add_int2(session.id)
    reply:add_int4(character_id)
    reply:add_int2(session.map_id)
    self:add_rid(reply, map.data)
    reply:add_int3(#map.data)
    self:add_pub_meta(reply, self:get_pub_blob("eif"))
    self:add_pub_meta(reply, self:get_pub_blob("enf"))
    self:add_pub_meta(reply, self:get_pub_blob("esf"))
    self:add_pub_meta(reply, self:get_pub_blob("ecf"))

    reply:add_break_string((character and character.name) or (session.character or ""))
    reply:add_break_string("")
    reply:add_break_string("")
    reply:add_break_string("")
    reply:add_int1(1)
    reply:add_string("   ")

    reply:add_int1((character and character.admin) or 0)
    reply:add_int1((character and character.level) or 0)
    reply:add_int4(0)
    reply:add_int4(0)
    reply:add_int2(10)
    reply:add_int2(10)
    reply:add_int2(10)
    reply:add_int2(10)
    reply:add_int2(10)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(1000)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    reply:add_int2(0)
    for _ = 1, 15 do
      reply:add_int2(0)
    end
    reply:add_int1(0)
    reply:add_int1(4)
    reply:add_int1(24)
    reply:add_int1(24)
    reply:add_int2(10)
    reply:add_int2(10)
    reply:add_int2(1)
    reply:add_int2(1)
    reply:add_int1(0)
    reply:add_byte(255)
    return reply
  end

  if packet.action == Action.Agree then
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

  if packet.action == Action.Message then
    packet:discard(3)
    local character_id = packet:get_int4()
    if character_id > 0 then
      local character = self.accounts:get_character(session.account, character_id)
      if character then
        self:load_character_location(session, character)
      end
    end
    self:apply_arena_only_location(session)
    self:apply_map_relog_location(session)

    if session.character_id and session.character_id > 0 then
      local character = self.accounts:get_character(session.account, session.character_id)
      if character then
        local appear = Packet.new(Family.Players, Action.Agree)
        self:add_nearby_info(appear, { { session = session, character = character } })
        self.world:broadcast_near(session, appear)
      end
    end

    local nearby = self:get_nearby_sessions(session)
    local reply = Packet.new(Family.GameData, Action.Reply)
    reply:add_int2(2)
    reply:add_byte(255)
    reply:add_break_string(self.settings.name or "Kalandra")
    for _ = 1, 8 do
      reply:add_break_string("")
    end
    reply:add_int1(0)
    reply:add_int1(100)
    reply:add_byte(255)
    reply:add_byte(255)
    self:add_nearby_info(reply, nearby)
    return reply
  end

  return nil, ("unhandled gamedata action %d"):format(packet.action)
end

return M
