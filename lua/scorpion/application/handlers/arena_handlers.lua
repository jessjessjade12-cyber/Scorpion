local ArenaSupport = require("scorpion.application.handlers.support.arena_support")
local Protocol = require("scorpion.transport.protocol")

local Action = Protocol.Action

local ArenaHandlers = {}
ArenaHandlers.__index = ArenaHandlers

function ArenaHandlers.new(deps)
  return setmetatable({
    world = deps.world,
  }, ArenaHandlers)
end

function ArenaHandlers:get_attack_target_player_id(attacker_session, direction)
  return ArenaSupport.get_attack_target_player_id(self.world, attacker_session, direction)
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

return ArenaHandlers
