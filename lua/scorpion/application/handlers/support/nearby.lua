local util = require("scorpion.util")
local clamp = util.clamp

local M = {}

function M.add_character_map_info(reply, session, character)
  local map_id = clamp(tonumber(session.map_id) or 0, 0, 64008)
  local x = clamp(tonumber(session.x) or 0, 0, 64008)
  local y = clamp(tonumber(session.y) or 0, 0, 64008)
  local direction = clamp(tonumber(session.direction) or 0, 0, 3)
  local level = clamp(tonumber(character.level) or 0, 0, 252)
  local gender = clamp(tonumber(character.sex) or 0, 0, 1)
  local hair_style = clamp(tonumber(character.hair_style) or 1, 0, 252)
  local hair_color = clamp(tonumber(character.hair_color) or 0, 0, 252)
  local skin = clamp(tonumber(character.race) or 0, 0, 252)
  local sit_state = clamp(tonumber(session.sit_state) or 0, 0, 2)
  local invisible = (session.invisible and 1) or 0

  reply:add_break_string(character.name)
  reply:add_int2(session.id)
  reply:add_int2(map_id)
  reply:add_int2(x)
  reply:add_int2(y)
  reply:add_int1(direction)
  reply:add_int1(0)
  reply:add_string("   ")
  reply:add_int1(level)
  reply:add_int1(gender)
  reply:add_int1(hair_style)
  reply:add_int1(hair_color)
  reply:add_int1(skin)
  reply:add_int2(10)
  reply:add_int2(10)
  reply:add_int2(1)
  reply:add_int2(1)
  for _ = 1, 9 do
    reply:add_int2(0)
  end
  reply:add_int1(sit_state)
  reply:add_int1(invisible)
end

function M.add_nearby_info(reply, nearby)
  reply:add_int1(#nearby)
  reply:add_byte(255)
  for _, entry in ipairs(nearby) do
    M.add_character_map_info(reply, entry.session, entry.character)
    reply:add_byte(255)
  end
  reply:add_byte(255)
end

function M.get_nearby_sessions(world, accounts, center_session)
  local result = {}
  for _, session in pairs(world.sessions) do
    if session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
      and (session.id == center_session.id or world:in_client_range(center_session, session))
    then
      local character = accounts:get_character(session.account, session.character_id)
      if character then
        result[#result + 1] = { session = session, character = character }
      end
    end
  end
  return result
end

function M.get_requested_nearby_sessions(world, accounts, center_session, player_ids)
  if #player_ids == 0 then
    return {}
  end

  local requested = {}
  local wanted = {}
  for _, id in ipairs(player_ids) do
    wanted[id] = true
  end

  for _, session in pairs(world.sessions) do
    if wanted[session.id]
      and session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
    then
      if session.id == center_session.id or world:in_client_range(center_session, session) then
        local character = accounts:get_character(session.account, session.character_id)
        if character then
          requested[#requested + 1] = { session = session, character = character }
        end
      end
    end
  end

  return requested
end

return M
