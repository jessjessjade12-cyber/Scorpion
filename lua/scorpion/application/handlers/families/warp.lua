local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local M = {}

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "warp before login"
  end

  if packet.action == Action.Accept then
    local map_id = packet:get_int2()
    local warp_session_id = packet:get_int2()
    local pending = session.pending_warp

    if pending ~= nil then
      local runner = self.world.arena_script_runner
      if warp_session_id ~= pending.session_id then
        return nil, "invalid warp session"
      end
      if map_id ~= pending.map_id then
        return nil, "invalid warp map"
      end

      local old_position = {
        map_id = session.map_id,
        x = session.x,
        y = session.y,
      }
      if session.character_id and session.character_id > 0 then
        self.world:broadcast_remove_from(old_position, session.id)
      end

      session.map_id = pending.map_id
      session.x = pending.x
      session.y = pending.y
      session.direction = pending.direction or session.direction
      session.pending_warp = nil
      session.shop_context = nil
      if self.world.sync_session_spatial then
        self.world:sync_session_spatial(session)
      end

      local self_character = self.accounts:get_character(session.account, session.character_id or 0)
      if session.script_npc_proxy_enabled == true and runner and runner.sync_npc_proxy then
        runner:sync_npc_proxy(session, old_position)
      elseif self_character then
        local appear = Packet.new(Family.Players, Action.Agree)
        self:add_nearby_info(appear, { { session = session, character = self_character } })
        self.world:broadcast_near(session, appear)
      end

      local nearby = self:get_nearby_sessions(session)
      local nearby_npcs = self:get_nearby_npcs(session)
      local reply = Packet.new(Family.Warp, Action.Agree)
      reply:add_int1(1)
      self:add_nearby_info(reply, nearby, nearby_npcs)
      return reply
    end
  end

  if self.settings.arena.only and not self.arena:arena_only_map_allowed(session.map_id) then
    return nil, "arena map only"
  end
  return self.arena:handle_warp(packet, session)
end

return M
