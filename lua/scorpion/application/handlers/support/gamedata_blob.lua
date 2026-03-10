local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

local FileIDMap = 1
local FileIDItem = 2
local FileIDMob = 3
local FileIDSkill = 4
local FileIDClass = 5

local PubConfigs = {
  [FileIDItem] = { key = "eif", id = 5 },
  [FileIDMob] = { key = "enf", id = 6 },
  [FileIDSkill] = { key = "esf", id = 7 },
  [FileIDClass] = { key = "ecf", id = 11 },
}

local M = {}

function M.build(file_id, packet, deps)
  local reply = Packet.new(Family.Raw, Action.Raw)
  reply.force_raw = true

  if file_id == FileIDMap then
    packet:discard(2)
    local map_id = packet:get_int2()
    local map = deps.world.maps[map_id]
    if map == nil or map.data == nil then
      return nil, ("request for invalid map #%d"):format(map_id)
    end
    reply:add_int1(4)
    reply:add_string(map.data)
    return reply
  end

  local cfg = PubConfigs[file_id]
  if cfg then
    local blob = deps.get_pub_blob(cfg.key)
    if blob == nil or blob.data == nil then
      return nil, (cfg.key .. " pub missing")
    end
    reply:add_int1(cfg.id)
    reply:add_int1(1)
    reply:add_string(blob.data)
    return reply
  end

  return nil, ("unknown game data request %d"):format(file_id)
end

return M
