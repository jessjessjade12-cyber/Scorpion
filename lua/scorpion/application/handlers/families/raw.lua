local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local RequiredVersion = { 0, 0, 28 }

local M = {}

function M.handle(self, packet, context)
  if packet.action ~= Action.Raw then
    return nil, ("unhandled raw action %d"):format(packet.action)
  end

  local auth = packet:get_int3()
  local v1 = packet:get_int1()
  local v2 = packet:get_int1()
  local v3 = packet:get_int1()

  local reply = Packet.new(Family.Raw, Action.Raw)
  if v1 < RequiredVersion[1] or v2 < RequiredVersion[2] or v3 < RequiredVersion[3] then
    self:trace("warn", "raw rejected version", {
      address = context and context.address or "unknown",
      version = ("%d.%d.%d"):format(v1, v2, v3),
    })
    reply:add_byte(1)
    reply:add_byte(RequiredVersion[1] + 1)
    reply:add_byte(RequiredVersion[2] + 1)
    reply:add_byte(RequiredVersion[3] + 1)
    return reply
  end

  context.sequence_start = math.random(1, 220)
  context.sequence_last = context.sequence_start + 4
  context.sequence_count = 0
  context.ping_replied = true

  local s1 = math.floor((context.sequence_start + 12) / 7)
  local s2 = (context.sequence_start + 5) % 7

  reply:add_byte(2)
  reply:add_byte(s1)
  reply:add_byte(s2)
  reply:add_byte(context.send_key)
  reply:add_byte(context.receive_key)
  reply:add_int2(context.connection_id or 1)
  reply:add_int3(self:auth_client(auth))

  context.initialized = true
  context.raw = true
  self:trace("info", "raw accepted", {
    address = context and context.address or "unknown",
    connection_id = context.connection_id or 1,
  })
  return reply
end

return M
