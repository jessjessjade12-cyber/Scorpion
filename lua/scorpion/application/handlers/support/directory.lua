local M = {}

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
