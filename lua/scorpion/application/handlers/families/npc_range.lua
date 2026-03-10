local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "npc range before login"
  end
  if packet.action ~= Action.Request then
    return true
  end

  local npc_indexes = self:parse_npc_range_request(packet)
  local nearby_npcs = self:get_requested_nearby_npcs(session, npc_indexes)

  local reply = Packet.new(Family.Npc, Action.Agree)
  reply:add_int1(#nearby_npcs)
  for _, npc in ipairs(nearby_npcs) do
    self:add_npc_map_info(reply, npc)
  end
  return reply
end

return M
