local ShopTextDb = {}

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_numbers(value)
  local out = {}
  for token in (value or ""):gmatch("[%-]?%d+") do
    out[#out + 1] = tonumber(token) or 0
  end
  return out
end

local function ensure_shop(shop_map, behavior_id)
  local shop = shop_map[behavior_id]
  if shop ~= nil then
    return shop
  end

  shop = {
    behavior_id = behavior_id,
    name = "",
    min_level = 0,
    max_level = 0,
    class_requirement = 0,
    trades = {},
    crafts = {},
  }
  shop_map[behavior_id] = shop
  return shop
end

local function add_trade_entries(shop, numbers)
  local i = 1
  while i + 2 <= #numbers do
    shop.trades[#shop.trades + 1] = {
      item_id = numbers[i],
      buy_price = numbers[i + 1],
      sell_price = numbers[i + 2],
      max_amount = 252,
    }
    i = i + 3
  end
end

local function add_craft_entries(shop, numbers)
  local i = 1
  while i + 8 <= #numbers do
    shop.crafts[#shop.crafts + 1] = {
      item_id = numbers[i],
      ingredients = {
        { item_id = numbers[i + 1], amount = numbers[i + 2] },
        { item_id = numbers[i + 3], amount = numbers[i + 4] },
        { item_id = numbers[i + 5], amount = numbers[i + 6] },
        { item_id = numbers[i + 7], amount = numbers[i + 8] },
      },
    }
    i = i + 9
  end
end

local function parse_unsafe(text)
  if type(text) ~= "string" then
    error("shop text must be a string")
  end

  local shop_map = {}
  local line_number = 0

  for raw_line in text:gmatch("[^\r\n]+") do
    line_number = line_number + 1

    local line = raw_line:gsub("//.*$", "")
    line = trim(line)
    if line ~= "" then
      local id_text, field, value = line:match("^(%d+)%.([%a_]+)%s*=%s*(.+)$")
      if not id_text then
        error(("invalid shop definition on line %d"):format(line_number))
      end

      local behavior_id = tonumber(id_text) or 0
      if behavior_id <= 0 then
        error(("invalid behavior id on line %d"):format(line_number))
      end

      local shop = ensure_shop(shop_map, behavior_id)
      local normalized_field = string.lower(field or "")

      if normalized_field == "name" then
        shop.name = trim(value)
      elseif normalized_field == "trade" then
        add_trade_entries(shop, parse_numbers(value))
      elseif normalized_field == "craft" then
        add_craft_entries(shop, parse_numbers(value))
      elseif normalized_field == "min_level" then
        shop.min_level = tonumber(trim(value)) or 0
      elseif normalized_field == "max_level" then
        shop.max_level = tonumber(trim(value)) or 0
      elseif normalized_field == "class_requirement" then
        shop.class_requirement = tonumber(trim(value)) or 0
      else
        error(("unknown shop field '%s' on line %d"):format(field, line_number))
      end
    end
  end

  local shops = {}
  local by_behavior_id = {}
  for _, shop in pairs(shop_map) do
    shops[#shops + 1] = shop
    by_behavior_id[shop.behavior_id] = shop
  end
  table.sort(shops, function(a, b)
    return a.behavior_id < b.behavior_id
  end)

  return {
    signature = "TXT",
    rid = { 0, 0 },
    shops = shops,
    by_behavior_id = by_behavior_id,
    bytes_remaining = 0,
  }
end

function ShopTextDb.parse(text)
  local ok, result = pcall(parse_unsafe, text)
  if not ok then
    return nil, result
  end
  return result
end

return ShopTextDb
