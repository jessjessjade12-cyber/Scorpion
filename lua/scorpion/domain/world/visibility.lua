local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

local function get_distance(a, b)
  return math.abs((a.x or 0) - (b.x or 0)) + math.abs((a.y or 0) - (b.y or 0))
end

local function in_directional_range(observer, other, near_limit, far_limit)
  local distance = get_distance(observer, other)
  if (observer.x or 0) >= (other.x or 0) or (observer.y or 0) >= (other.y or 0) then
    return distance <= near_limit
  end
  return distance <= far_limit
end

-- Broadcast visibility range.
function M.in_range(self, s1, s2)
  if s1.map_id ~= s2.map_id then
    return false
  end
  return in_directional_range(s1, s2, 12, 15)
end

-- Client entity visibility range.
function M.in_client_range(self, s1, s2)
  if s1.map_id ~= s2.map_id then
    return false
  end
  return in_directional_range(s1, s2, 11, 14)
end

-- Queue a packet to all connected sessions near from_session (excluding sender).
function M.broadcast_near(self, from_session, packet)
  for _, session in pairs(self.sessions) do
    -- Range must be evaluated from the receiver perspective.
    if session.id ~= from_session.id and session.connected and self:in_range(session, from_session) then
      self:push_pending(session.address, packet)
    end
  end
end

-- Queue a packet to all connected sessions on a map.
function M.broadcast_map(self, map_id, packet)
  for _, session in pairs(self.sessions) do
    if session.connected and session.map_id == map_id then
      self:push_pending(session.address, packet)
    end
  end
end

-- Queue Avatar.Remove to sessions near an origin position (excluding player_id).
function M.broadcast_remove_from(self, origin, player_id, warp_effect)
  if not origin or not player_id then
    return
  end

  local remove = Packet.new(Family.Avatar, Action.Remove)
  remove:add_int2(player_id)
  if warp_effect ~= nil then
    remove:add_int1(warp_effect)
  end

  for _, session in pairs(self.sessions) do
    if session.connected and session.id ~= player_id and self:in_range(session, origin) then
      self:push_pending(session.address, remove)
    end
  end
end

return M
