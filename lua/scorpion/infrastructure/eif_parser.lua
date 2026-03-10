local EOInt = require("scorpion.transport.eoint")

local EifParser = {}

local Reader = {}
Reader.__index = Reader

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
  local b = self.data:byte(self.pos)
  self.pos = self.pos + 1
  return b
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
    error("EIF data must be a string")
  end

  local reader = Reader.new(data)
  local signature = reader:read_bytes(3, "signature")
  if signature ~= "EIF" then
    error("invalid EIF signature")
  end

  local rid = {
    reader:read_short("rid[1]"),
    reader:read_short("rid[2]"),
  }

  local item_count = reader:read_short("item_count")
  local version = reader:read_char("version")
  local items = {}
  local by_id = {}

  for index = 1, item_count do
    local prefix = ("items[%d]."):format(index)
    local name_length = reader:read_char(prefix .. "name_length")
    local name = reader:read_bytes(name_length, prefix .. "name")
    local graphic_id = reader:read_short(prefix .. "graphic_id")
    local item_type = reader:read_char(prefix .. "type")
    local subtype = reader:read_char(prefix .. "subtype")
    local special = reader:read_char(prefix .. "special")
    reader:read_short(prefix .. "hp")
    reader:read_short(prefix .. "tp")
    reader:read_short(prefix .. "min_damage")
    reader:read_short(prefix .. "max_damage")
    reader:read_short(prefix .. "accuracy")
    reader:read_short(prefix .. "evade")
    reader:read_short(prefix .. "armor")
    reader:read_char(prefix .. "return_damage")
    reader:read_char(prefix .. "str")
    reader:read_char(prefix .. "int")
    reader:read_char(prefix .. "wis")
    reader:read_char(prefix .. "agi")
    reader:read_char(prefix .. "con")
    reader:read_char(prefix .. "cha")
    reader:read_char(prefix .. "light_resistance")
    reader:read_char(prefix .. "dark_resistance")
    reader:read_char(prefix .. "earth_resistance")
    reader:read_char(prefix .. "air_resistance")
    reader:read_char(prefix .. "water_resistance")
    reader:read_char(prefix .. "fire_resistance")
    local spec1 = reader:read_three(prefix .. "spec1")
    local spec2 = reader:read_char(prefix .. "spec2")
    reader:read_char(prefix .. "spec3")
    local level_requirement = reader:read_short(prefix .. "level_requirement")
    local class_requirement = reader:read_short(prefix .. "class_requirement")
    local str_requirement = reader:read_short(prefix .. "str_requirement")
    local int_requirement = reader:read_short(prefix .. "int_requirement")
    local wis_requirement = reader:read_short(prefix .. "wis_requirement")
    local agi_requirement = reader:read_short(prefix .. "agi_requirement")
    local con_requirement = reader:read_short(prefix .. "con_requirement")
    local cha_requirement = reader:read_short(prefix .. "cha_requirement")
    reader:read_char(prefix .. "element")
    reader:read_char(prefix .. "element_damage")
    local weight = reader:read_char(prefix .. "weight")
    reader:read_char(prefix .. "weapon_target_area")
    reader:read_char(prefix .. "size")

    local record = {
      id = index,
      name = name,
      graphic_id = graphic_id,
      type = item_type,
      subtype = subtype,
      special = special,
      spec1 = spec1,
      spec2 = spec2,
      weight = weight,
      level_requirement = level_requirement,
      class_requirement = class_requirement,
      str_requirement = str_requirement,
      int_requirement = int_requirement,
      wis_requirement = wis_requirement,
      agi_requirement = agi_requirement,
      con_requirement = con_requirement,
      cha_requirement = cha_requirement,
    }

    items[#items + 1] = record
    by_id[index] = record
  end

  return {
    signature = signature,
    rid = rid,
    version = version,
    items = items,
    by_id = by_id,
    bytes_remaining = reader:remaining(),
  }
end

function EifParser.parse(data)
  local ok, result = pcall(parse_unsafe, data)
  if not ok then
    return nil, result
  end
  return result
end

return EifParser
