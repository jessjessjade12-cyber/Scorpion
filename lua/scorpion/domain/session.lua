local Session = {}
Session.__index = Session

function Session.new(id, address)
  return setmetatable({
    account = nil,
    arena_in = false,
    arena_kills = 0,
    character = nil,
    character_id = 0,
    direction = 0,
    id = id,
    address = address,
    connected = true,
    map_id = 0,
    pending_warp = nil,
    x = 0,
    y = 0,
  }, Session)
end

return Session
