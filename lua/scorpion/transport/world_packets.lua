local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local WorldPackets = {}

local function session_name(session)
  if not session then
    return "unknown"
  end
  return session.character or session.account or ("player" .. tostring(session.id or 0))
end

local function clamp(value, low, high, fallback)
  local n = math.floor(tonumber(value) or fallback)
  if n < low then
    return low
  end
  if n > high then
    return high
  end
  return n
end

function WorldPackets.avatar_remove_packet(player_id, warp_effect)
  local remove = Packet.new(Family.Avatar, Action.Remove)
  remove:add_int2(player_id or 0)
  if warp_effect ~= nil then
    remove:add_int1(warp_effect)
  end
  return remove
end

function WorldPackets.warp_request_packet(target_map, session_id)
  local packet = Packet.new(Family.Warp, Action.Request)
  packet:add_int1(1) -- WarpType.Local
  packet:add_int2(target_map or 0)
  packet:add_int2(session_id or 0)
  return packet
end

function WorldPackets.arena_full_packet()
  local packet = Packet.new(Family.Arena, Action.Drop)
  packet:add_string("N")
  return packet
end

function WorldPackets.arena_launch_packet(players_count)
  local packet = Packet.new(Family.Arena, Action.Use)
  packet:add_int1(players_count or 0)
  return packet
end

function WorldPackets.arena_spec_packet(killer_session, victim_session, direction)
  local packet = Packet.new(Family.Arena, Action.Spec)
  packet:add_int2((killer_session and killer_session.id) or 0)
  packet:add_byte(255)
  packet:add_int1(direction or (killer_session and killer_session.direction) or 0)
  packet:add_byte(255)
  packet:add_int4((killer_session and killer_session.arena_kills) or 0)
  packet:add_byte(255)
  packet:add_string(session_name(killer_session))
  packet:add_byte(255)
  packet:add_string(session_name(victim_session))
  return packet
end

function WorldPackets.arena_accept_packet(winner_session, victim_session)
  local winner_name = session_name(winner_session)
  local packet = Packet.new(Family.Arena, Action.Accept)
  packet:add_string(winner_name)
  packet:add_byte(255)
  packet:add_int4((winner_session and winner_session.arena_kills) or 0)
  packet:add_byte(255)
  packet:add_string(winner_name)
  packet:add_byte(255)
  packet:add_string(session_name(victim_session))
  return packet
end

function WorldPackets.npc_move_packet(npc)
  local packet = Packet.new(Family.Npc, Action.Player)
  packet:add_int1(clamp(npc and npc.index, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.x, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.y, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.direction, 0, 3, 0))
  packet:add_byte(255)
  packet:add_byte(255)
  packet:add_byte(255)
  return packet
end

return WorldPackets
