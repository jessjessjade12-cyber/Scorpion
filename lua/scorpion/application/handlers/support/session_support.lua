local M = {}

function M.auth_client(auth)
  auth = auth + 1
  local result = ((auth % 11) + 1) * 119
  if result == 0 then
    return 0
  end
  return 110905 + ((auth % 9) + 1) * ((11092004 - auth) % result) * 119 + (auth % 2004)
end

function M.load_character_location(session, character)
  session.character_id = character.id
  session.character = character.name
  session.map_id = character.map_id
  session.x = character.x
  session.y = character.y
  session.direction = character.direction
end

function M.valid_account_name(name)
  if #name < 4 or #name > 20 then
    return false
  end
  return name:find("[^%da-z]") == nil
end

function M.valid_character_name(name)
  if #name < 4 or #name > 12 then
    return false
  end
  return name:find("[^a-z]") == nil
end

function M.apply_arena_only_location(settings, session)
  local arena = settings.arena or {}
  if not arena.only then
    return
  end

  local target_map = arena.map or ((settings.new_character or {}).spawn_map) or session.map_id
  if session.map_id == target_map then
    return
  end

  local spawn = settings.new_character or {}
  local x = spawn.spawn_x or session.x
  local y = spawn.spawn_y or session.y

  local first_spawn = (arena.spawns or {})[1]
  if first_spawn and first_spawn.from then
    x = first_spawn.from.x
    y = first_spawn.from.y
  end

  session.map_id = target_map
  session.x = x
  session.y = y
  session.direction = spawn.spawn_direction or session.direction
end

function M.apply_map_relog_location(world, session)
  local relog = world:get_map_relog(session.map_id)
  if not relog then
    return
  end

  session.x = relog.x
  session.y = relog.y
end

function M.get_pub_blob(world, key)
  return ((world.pub or {}).client or {})[key]
end

function M.add_rid(reply, data)
  if data == nil or #data < 7 then
    reply:add_byte(0)
    reply:add_byte(0)
    reply:add_byte(0)
    reply:add_byte(0)
    return
  end

  reply:add_byte(data:byte(4))
  reply:add_byte(data:byte(5))
  reply:add_byte(data:byte(6))
  reply:add_byte(data:byte(7))
end

function M.add_pub_meta(reply, blob)
  local data = blob and blob.data or nil
  M.add_rid(reply, data)
  if data == nil or #data < 9 then
    reply:add_byte(0)
    reply:add_byte(0)
    return
  end

  reply:add_byte(data:byte(8))
  reply:add_byte(data:byte(9))
end

function M.parse_player_ids(packet)
  local player_ids = {}
  while #packet.data >= 2 do
    player_ids[#player_ids + 1] = packet:get_int2()
  end
  return player_ids
end

function M.parse_range_request(packet)
  local player_ids = {}

  while #packet.data > 0 and packet.data:byte(1) ~= 255 do
    if #packet.data < 2 then
      break
    end
    player_ids[#player_ids + 1] = packet:get_int2()
  end

  return player_ids
end

function M.broadcast_all(world, packet, exclude_session)
  for _, session in pairs(world.sessions) do
    if session.connected and (exclude_session == nil or session.id ~= exclude_session.id) then
      world:push_pending(session.address, packet)
    end
  end
end

function M.find_session_by_character_name(world, accounts, name)
  local wanted = string.lower(name or "")
  if wanted == "" then
    return nil, nil
  end

  for _, session in pairs(world.sessions) do
    if session.connected and (session.character_id and session.character_id > 0) then
      local character = accounts:get_character(session.account, session.character_id)
      if character and string.lower(character.name or "") == wanted then
        return session, character
      end
    end
  end

  return nil, nil
end

return M
