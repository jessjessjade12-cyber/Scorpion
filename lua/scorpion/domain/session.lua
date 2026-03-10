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
    equipment_graphics = nil,
    map_id = 0,
    max_weight = nil,
    pending_warp = nil,
    paperdoll = nil,
    shop_context = nil,
    shop_gold = nil,
    shop_items = nil,
    shop_max_weight = nil,
    inventory = nil,
    x = 0,
    y = 0,
  }, Session)
end

return Session
