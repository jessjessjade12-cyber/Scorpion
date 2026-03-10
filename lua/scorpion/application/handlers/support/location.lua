local M = {}

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

return M
