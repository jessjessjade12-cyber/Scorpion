local ArenaSupport = require("scorpion.application.handlers.support.arena_support")
local Protocol = require("scorpion.transport.protocol")

local Action = Protocol.Action

local ArenaHandlers = {}
ArenaHandlers.__index = ArenaHandlers

function ArenaHandlers.new(deps)
  return setmetatable({
    settings = deps.settings,
    world = deps.world,
  }, ArenaHandlers)
end

function ArenaHandlers:spawn_profile()
  local spawn = self.settings.new_character
  return {
    direction = spawn.spawn_direction,
    map = spawn.spawn_map,
    x = spawn.spawn_x,
    y = spawn.spawn_y,
  }
end

function ArenaHandlers:on_login(session)
  local spawn = self:spawn_profile()
  session.map_id = spawn.map
  session.x = spawn.x
  session.y = spawn.y
  session.direction = spawn.direction
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end
end

function ArenaHandlers:get_map_meta(map_id)
  return self.world:get_map_meta(map_id)
end

function ArenaHandlers:get_tile_spec(meta, x, y)
  return ArenaSupport.get_tile_spec(meta, x, y)
end

function ArenaHandlers:is_tile_walkable(meta, x, y)
  return ArenaSupport.is_tile_walkable(meta, x, y)
end

function ArenaHandlers:get_attack_target_player_id(attacker_session, direction)
  return ArenaSupport.get_attack_target_player_id(self.world, attacker_session, direction)
end

-- Arena handlers orchestrate packet flow while ArenaSupport owns low-level helpers.
function ArenaHandlers:handle_walk(packet, session)
  if packet.action ~= Action.Player and packet.action ~= Action.Special and packet.action ~= Action.Admin then
    return nil, ("unhandled walk action %d"):format(packet.action)
  end

  local direction = ArenaSupport.read_walk_direction(packet)
  local previous = ArenaSupport.apply_step(session, direction)
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end
  local runner = self.world.arena_script_runner

  if session.script_npc_proxy_enabled == true and runner and runner.sync_npc_proxy then
    runner:sync_npc_proxy(session, previous)
  else
    -- Broadcast Walk.Player to all nearby players on the same map
    local broadcast = ArenaSupport.walk_player_packet(session)
    self.world:broadcast_near(session, broadcast)
  end

  -- Walk.Reply to the mover: include newly-visible players.
  local visible_player_ids = ArenaSupport.newly_visible_player_ids(self.world, session, previous)
  local visible_npc_indexes = ArenaSupport.newly_visible_npc_indexes(self.world, session, previous)
  return ArenaSupport.walk_reply_packet(visible_player_ids, visible_npc_indexes)
end

function ArenaHandlers:handle_attack(packet, session)
  if packet.action ~= Action.Use then
    return nil, ("unhandled attack action %d"):format(packet.action)
  end

  session.direction = ArenaSupport.read_attack_direction(packet)

  local runner = self.world.arena_script_runner
  if session.script_npc_proxy_enabled == true and runner and runner.sync_npc_proxy then
    runner:sync_npc_proxy(session)
  else
    local broadcast = ArenaSupport.attack_player_packet(session)
    self.world:broadcast_near(session, broadcast)
  end

  if self.world:is_arena_session(session.id) then
    local victim_id = self:get_attack_target_player_id(session, session.direction)
    if victim_id ~= nil then
      self.world:arena_eliminate(victim_id, session.id, session.direction)
    end
  end

  return true
end

function ArenaHandlers:handle_warp(packet, session)
  if packet.action == Action.Accept then
    return ArenaSupport.warp_agree_packet(session)
  end

  if packet.action == Action.Take then
    return ArenaSupport.warp_take_packet()
  end

  return nil, ("unhandled warp action %d"):format(packet.action)
end

function ArenaHandlers:arena_only_map_allowed(map_id)
  if not self.settings.arena.only then
    return true
  end

  return map_id == self.settings.arena.map
end

return ArenaHandlers
