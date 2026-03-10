local util = require("scorpion.util")
local clamp = util.clamp

local M = {}

local function active_disguise(session)
  local disguise = session and session.script_disguise or nil
  if not disguise then
    return nil
  end

  local expires_at = tonumber(disguise.expires_at) or 0
  if expires_at > 0 and os.time() >= expires_at then
    session.script_disguise = nil
    return nil
  end

  return disguise
end

function M.add_character_map_info(reply, session, character)
  local disguise = active_disguise(session)
  local display_name = (disguise and disguise.name) or character.name

  local char_level = character.level
  local char_sex = character.sex
  local char_hair_style = character.hair_style
  local char_hair_color = character.hair_color
  local char_skin = character.race

  if disguise then
    if disguise.level ~= nil then
      char_level = disguise.level
    end
    if disguise.sex ~= nil then
      char_sex = disguise.sex
    end
    if disguise.hair_style ~= nil then
      char_hair_style = disguise.hair_style
    end
    if disguise.hair_color ~= nil then
      char_hair_color = disguise.hair_color
    end
    if disguise.skin ~= nil then
      char_skin = disguise.skin
    end
  end

  local map_id = clamp(tonumber(session.map_id) or 0, 0, 64008)
  local x = clamp(tonumber(session.x) or 0, 0, 64008)
  local y = clamp(tonumber(session.y) or 0, 0, 64008)
  local direction = clamp(tonumber(session.direction) or 0, 0, 3)
  local level = clamp(tonumber(char_level) or 0, 0, 252)
  local gender = clamp(tonumber(char_sex) or 0, 0, 1)
  local hair_style = clamp(tonumber(char_hair_style) or 1, 0, 252)
  local hair_color = clamp(tonumber(char_hair_color) or 0, 0, 252)
  local skin = clamp(tonumber(char_skin) or 0, 0, 252)
  local sit_state = clamp(tonumber(session.sit_state) or 0, 0, 2)
  local invisible = (session.invisible and 1) or 0

  reply:add_break_string(display_name)
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
  local equipment_graphics = session and session.equipment_graphics or {}
  reply:add_int2(clamp(tonumber(equipment_graphics.boots) or 0, 0, 64008))
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(0)
  reply:add_int2(clamp(tonumber(equipment_graphics.armor) or 0, 0, 64008))
  reply:add_int2(0)
  reply:add_int2(clamp(tonumber(equipment_graphics.hat) or 0, 0, 64008))
  reply:add_int2(clamp(tonumber(equipment_graphics.shield) or 0, 0, 64008))
  reply:add_int2(clamp(tonumber(equipment_graphics.weapon) or 0, 0, 64008))
  reply:add_int1(sit_state)
  reply:add_int1(invisible)
end

function M.add_npc_map_info(reply, npc)
  reply:add_int1(clamp(tonumber(npc.index) or 0, 0, 252))
  reply:add_int2(clamp(tonumber(npc.id) or 0, 0, 64008))
  reply:add_int1(clamp(tonumber(npc.x) or 0, 0, 252))
  reply:add_int1(clamp(tonumber(npc.y) or 0, 0, 252))
  reply:add_int1(clamp(tonumber(npc.direction) or 0, 0, 3))
end

function M.add_nearby_info(reply, nearby, npcs)
  reply:add_int1(#nearby)
  reply:add_byte(255)
  for _, entry in ipairs(nearby) do
    M.add_character_map_info(reply, entry.session, entry.character)
    reply:add_byte(255)
  end

  for _, npc in ipairs(npcs or {}) do
    M.add_npc_map_info(reply, npc)
  end

  reply:add_byte(255)
end

local function normalize_map_npc(map_id, npc)
  if npc == nil then
    return nil
  end

  local coords = npc.coords or {}
  local x = tonumber(coords.x) or tonumber(npc.x) or 0
  local y = tonumber(coords.y) or tonumber(npc.y) or 0

  return {
    map_id = map_id,
    index = clamp(tonumber(npc.index) or 0, 0, 252),
    id = clamp(tonumber(npc.id) or 0, 0, 64008),
    x = clamp(x, 0, 252),
    y = clamp(y, 0, 252),
    direction = clamp(tonumber(npc.direction) or 0, 0, 3),
  }
end

local function collect_map_npcs(world, center_session, wanted)
  local result = {}
  local map_npcs = {}
  local center_id = tonumber(center_session and center_session.id) or 0

  if world.list_map_npcs then
    map_npcs = world:list_map_npcs(center_session.map_id) or {}
  else
    local map = world.maps[center_session.map_id]
    local map_meta = map and map.meta or nil
    map_npcs = (map_meta and map_meta.npcs) or {}
  end

  for _, npc in ipairs(map_npcs) do
    local owner_session_id = tonumber(npc and npc.owner_session_id) or 0
    if not (center_id > 0 and owner_session_id > 0 and owner_session_id == center_id) then
      local normalized = normalize_map_npc(center_session.map_id, npc)
      if normalized ~= nil and normalized.index > 0 then
        if (wanted == nil or wanted[normalized.index]) and world:in_client_range(center_session, normalized) then
          result[#result + 1] = normalized
        end
      end
    end
  end

  return result
end

local function local_view_session(session, is_self)
  if not is_self or session.invisible ~= true then
    return session
  end

  return setmetatable({
    invisible = nil,
  }, {
    __index = session,
  })
end

function M.get_nearby_sessions(world, accounts, center_session)
  local result = {}
  for _, session in pairs(world.sessions) do
    local is_self = session.id == center_session.id
    if session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
      and (is_self or session.invisible ~= true)
      and (is_self or world:in_client_range(center_session, session))
    then
      local character = accounts:get_character(session.account, session.character_id)
      if character then
        result[#result + 1] = {
          session = local_view_session(session, is_self),
          character = character,
        }
      end
    end
  end
  return result
end

function M.get_nearby_npcs(world, center_session)
  return collect_map_npcs(world, center_session, nil)
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
    local is_self = session.id == center_session.id
    if wanted[session.id]
      and session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
      and (is_self or session.invisible ~= true)
    then
      if is_self or world:in_client_range(center_session, session) then
        local character = accounts:get_character(session.account, session.character_id)
        if character then
          requested[#requested + 1] = {
            session = local_view_session(session, is_self),
            character = character,
          }
        end
      end
    end
  end

  return requested
end

function M.get_requested_nearby_npcs(world, center_session, npc_indexes)
  if #npc_indexes == 0 then
    return {}
  end

  local wanted = {}
  for _, index in ipairs(npc_indexes) do
    wanted[index] = true
  end

  return collect_map_npcs(world, center_session, wanted)
end

return M
