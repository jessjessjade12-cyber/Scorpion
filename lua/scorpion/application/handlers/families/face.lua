local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "face before login"
  end
  if packet.action ~= Action.Player then
    return nil, ("unhandled face action %d"):format(packet.action)
  end
  session.direction = clamp(packet:get_int1(), 0, 3)

  local runner = self.world.arena_script_runner
  if session.script_npc_proxy_enabled == true and runner and runner.sync_npc_proxy then
    runner:sync_npc_proxy(session)
    return true
  end

  local broadcast = Packet.new(Family.Face, Action.Player)
  broadcast:add_int2(session.id)
  broadcast:add_int1(session.direction)
  self.world:broadcast_near(session, broadcast)
  return true
end

return M
