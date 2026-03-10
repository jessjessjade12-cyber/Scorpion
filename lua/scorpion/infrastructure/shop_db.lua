local EOInt = require("scorpion.transport.eoint")

local ShopDb = {}

local Reader = {}
Reader.__index = Reader

local function new_empty_db()
  return {
    signature = "ESF",
    rid = { 0, 0 },
    shops = {},
    by_behavior_id = {},
    bytes_remaining = 0,
  }
end

function Reader.new(data)
  return setmetatable({
    data = data or "",
    len = #(data or ""),
    pos = 1,
  }, Reader)
end

function Reader:remaining()
  return self.len - self.pos + 1
end

function Reader:ensure(count, label)
  if self:remaining() < count then
    error(("unexpected EOF while reading %s"):format(label or "data"))
  end
end

function Reader:read_bytes(count, label)
  self:ensure(count, label)
  local out = self.data:sub(self.pos, self.pos + count - 1)
  self.pos = self.pos + count
  return out
end

function Reader:read_raw_byte(label)
  self:ensure(1, label)
  local byte = self.data:byte(self.pos)
  self.pos = self.pos + 1
  return byte
end

function Reader:read_char(label)
  return EOInt.pack(self:read_raw_byte(label))
end

function Reader:read_short(label)
  return EOInt.pack(
    self:read_raw_byte(label),
    self:read_raw_byte(label)
  )
end

function Reader:read_three(label)
  return EOInt.pack(
    self:read_raw_byte(label),
    self:read_raw_byte(label),
    self:read_raw_byte(label)
  )
end

local function parse_unsafe(data)
  if type(data) ~= "string" then
    error("shop data must be a string")
  end

  local reader = Reader.new(data)
  local signature = reader:read_bytes(3, "signature")
  if signature ~= "ESF" then
    error("invalid ESF signature")
  end

  local rid = {
    reader:read_short("rid[1]"),
    reader:read_short("rid[2]"),
  }

  local shop_count = reader:read_short("shop_count")
  reader:read_char("padding")

  local shops = {}
  local by_behavior_id = {}

  for shop_index = 1, shop_count do
    local prefix = ("shops[%d]."):format(shop_index)
    local behavior_id = reader:read_short(prefix .. "behavior_id")
    local name_length = reader:read_char(prefix .. "name_length")
    local name = reader:read_bytes(name_length, prefix .. "name")
    local min_level = reader:read_short(prefix .. "min_level")
    local max_level = reader:read_short(prefix .. "max_level")
    local class_requirement = reader:read_char(prefix .. "class_requirement")
    local trade_count = reader:read_short(prefix .. "trade_count")
    local craft_count = reader:read_char(prefix .. "craft_count")

    local trades = {}
    for trade_index = 1, trade_count do
      local trade_prefix = prefix .. ("trades[%d]."):format(trade_index)
      trades[#trades + 1] = {
        item_id = reader:read_short(trade_prefix .. "item_id"),
        buy_price = reader:read_three(trade_prefix .. "buy_price"),
        sell_price = reader:read_three(trade_prefix .. "sell_price"),
        max_amount = reader:read_char(trade_prefix .. "max_amount"),
      }
    end

    local crafts = {}
    for craft_index = 1, craft_count do
      local craft_prefix = prefix .. ("crafts[%d]."):format(craft_index)
      local craft = {
        item_id = reader:read_short(craft_prefix .. "item_id"),
        ingredients = {},
      }

      for ingredient_index = 1, 4 do
        local ingredient_prefix = craft_prefix .. ("ingredients[%d]."):format(ingredient_index)
        craft.ingredients[#craft.ingredients + 1] = {
          item_id = reader:read_short(ingredient_prefix .. "item_id"),
          amount = reader:read_char(ingredient_prefix .. "amount"),
        }
      end

      crafts[#crafts + 1] = craft
    end

    local shop = {
      behavior_id = behavior_id,
      name = name,
      min_level = min_level,
      max_level = max_level,
      class_requirement = class_requirement,
      trades = trades,
      crafts = crafts,
    }

    shops[#shops + 1] = shop
    if by_behavior_id[behavior_id] == nil then
      by_behavior_id[behavior_id] = shop
    end
  end

  return {
    signature = signature,
    rid = rid,
    shops = shops,
    by_behavior_id = by_behavior_id,
    bytes_remaining = reader:remaining(),
  }
end

function ShopDb.empty()
  return new_empty_db()
end

function ShopDb.parse(data)
  local ok, result = pcall(parse_unsafe, data)
  if not ok then
    return nil, result
  end

  return result
end

function ShopDb.from_blob(blob)
  if blob and blob.parsed then
    return blob.parsed
  end

  return ShopDb.empty()
end

function ShopDb.find_by_behavior_id(db, behavior_id)
  local id = tonumber(behavior_id) or 0
  local by_behavior_id = ((db or {}).by_behavior_id or {})
  return by_behavior_id[id]
end

return ShopDb
