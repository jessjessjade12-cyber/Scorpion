local MovementSupport = require("scorpion.application.handlers.support.movement_support")
local Protocol = require("scorpion.transport.protocol")

local Action = Protocol.Action

local MovementHandlers = {}
MovementHandlers.__index = MovementHandlers

function MovementHandlers.new(deps)
  return setmetatable({
    settings = deps.settings,
    world = deps.world,
  }, MovementHandlers)
end

function MovementHandlers:map_allowed(map_id)
  if not self.settings.arena.only then
    return true
  end

  return map_id == self.settings.arena.map
end

function MovementHandlers:handle_walk(packet, session)
  if packet.action ~= Action.Player and packet.action ~= Action.Special and packet.action ~= Action.Admin then
    return nil, ("unhandled walk action %d"):format(packet.action)
  end

  if session.pending_warp ~= nil then
    return true
  end

  local direction = MovementSupport.read_walk_direction(packet)
  local previous = MovementSupport.apply_step(session, direction)
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end

  local map_meta = self.world:get_map_meta(session.map_id)
  local warp = MovementSupport.get_warp(map_meta, session.x, session.y)
  if warp then
    local destination_map = tonumber(warp.destination_map) or 0
    local destination_coords = warp.destination_coords or {}
    local destination_x = tonumber(destination_coords.x) or 0
    local destination_y = tonumber(destination_coords.y) or 0

    if destination_map > 0 and self.world:has_map(destination_map) then
      if destination_x <= 0 or destination_y <= 0 then
        local relog = self.world:get_map_relog(destination_map)
        if relog then
          destination_x = relog.x
          destination_y = relog.y
        end
      end

      if destination_x > 0 and destination_y > 0 then
        self.world:request_local_warp(
          session,
          destination_map,
          destination_x,
          destination_y,
          session.direction
        )
        return true
      end
    end
  end

  local runner = self.world.arena_script_runner
  if session.script_npc_proxy_enabled == true and runner and runner.sync_npc_proxy then
    runner:sync_npc_proxy(session, previous)
  else
    local broadcast = MovementSupport.walk_player_packet(session)
    self.world:broadcast_near(session, broadcast)
  end

  local visible_player_ids = MovementSupport.newly_visible_player_ids(self.world, session, previous)
  local visible_npc_indexes = MovementSupport.newly_visible_npc_indexes(self.world, session, previous)
  local visible_items = MovementSupport.newly_visible_items(self.world, session, previous)
  return MovementSupport.walk_reply_packet(visible_player_ids, visible_npc_indexes, visible_items)
end

function MovementHandlers:handle_warp(packet, session)
  if packet.action == Action.Accept then
    return MovementSupport.warp_agree_packet(session)
  end

  if packet.action == Action.Take then
    return MovementSupport.warp_take_packet()
  end

  return nil, ("unhandled warp action %d"):format(packet.action)
end

return MovementHandlers
