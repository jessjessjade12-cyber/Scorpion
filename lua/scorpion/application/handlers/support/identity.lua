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

return M
