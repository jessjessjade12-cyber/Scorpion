local M = {}

function M.parse_player_ids(packet)
  local player_ids = {}
  while #packet.data >= 2 do
    player_ids[#player_ids + 1] = packet:get_int2()
  end
  return player_ids
end

function M.parse_range_request(packet)
  local player_ids = {}

  while #packet.data > 0 and packet.data:byte(1) ~= 255 do
    if #packet.data < 2 then
      break
    end
    player_ids[#player_ids + 1] = packet:get_int2()
  end

  return player_ids
end

return M
