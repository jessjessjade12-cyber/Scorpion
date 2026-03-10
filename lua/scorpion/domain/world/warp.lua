local M = {}

function M.has_map(self, map_id)
  return self.maps[map_id] ~= nil
end

function M.get_map_meta(self, map_id)
  local map = self.maps[map_id]
  if map == nil then
    return nil
  end
  return map.meta
end

function M.get_map_relog(self, map_id)
  local meta = self:get_map_meta(map_id)
  if not meta then
    return nil
  end

  local x = tonumber(meta.relog_x) or 0
  local y = tonumber(meta.relog_y) or 0
  if x <= 0 or y <= 0 then
    return nil
  end

  return { x = x, y = y }
end

function M.arena_spawn_point(self, x, y)
  for _, spawn in ipairs((self.arena and self.arena.spawns) or {}) do
    if spawn.from and spawn.from.x == x and spawn.from.y == y then
      return spawn.to
    end
  end

  return nil
end

function M.request_local_warp(self, session, map_id, x, y, direction)
  if not session or not session.connected then
    return false
  end

  local target_map = tonumber(map_id) or 0
  local target_x = tonumber(x) or 0
  local target_y = tonumber(y) or 0
  local target_direction = tonumber(direction) or session.direction or 0
  if target_direction < 0 or target_direction > 3 then
    target_direction = 0
  end
  local session_id = math.random(10, 64008)

  session.pending_warp = {
    map_id = target_map,
    x = target_x,
    y = target_y,
    direction = target_direction,
    session_id = session_id,
    warp_type = 1, -- Local
  }

  local transport = self.transport
  if not transport or not transport.warp_request_packet then
    return false
  end
  local packet = transport.warp_request_packet(target_map, session_id)
  self:push_pending(session.address, packet)
  return true
end

function M.arena_respawn(self, session)
  local target_map = session.map_id
  local target_x = session.x
  local target_y = session.y
  local target_direction = 0

  local relog = self:get_map_relog(session.map_id)
  if relog then
    target_x = relog.x
    target_y = relog.y
  else
    -- Fallback to configured spawn if EMF relog is unavailable.
    local spawn = self.arena_spawn or {}
    if spawn.map and spawn.map > 0 then
      target_map = spawn.map
    end
    if spawn.x and spawn.x >= 0 then
      target_x = spawn.x
    end
    if spawn.y and spawn.y >= 0 then
      target_y = spawn.y
    end
    target_direction = spawn.direction or 0
  end

  -- In arena flow (same-map ejection), notify victim via local warp.
  if target_map == session.map_id then
    local warped = self:request_local_warp(
      session,
      target_map,
      target_x,
      target_y,
      target_direction
    )
    if warped then
      return
    end
  end

  -- Fallback if warp request could not be queued.
  session.map_id = target_map
  session.x = target_x
  session.y = target_y
  session.direction = target_direction
  if self.sync_session_spatial then
    self:sync_session_spatial(session)
  end
end

return M
