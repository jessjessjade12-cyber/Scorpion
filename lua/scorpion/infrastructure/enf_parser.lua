local EOInt = require("scorpion.transport.eoint")

local EnfParser = {}

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
    error("ENF data must be a string")
  end

  local reader = Reader.new(data)
  local signature = reader:read_bytes(3, "signature")
  if signature ~= "ENF" then
    error("invalid ENF signature")
  end

  local rid = {
    reader:read_short("rid[1]"),
    reader:read_short("rid[2]"),
  }

  local npc_count = reader:read_short("npc_count")
  local version = reader:read_char("version")
  local npcs = {}
  local by_id = {}

  for index = 1, npc_count do
    local prefix = ("npcs[%d]."):format(index)
    local name_length = reader:read_char(prefix .. "name_length")
    local name = reader:read_bytes(name_length, prefix .. "name")
    local graphic_id = reader:read_short(prefix .. "graphic_id")
    local race = reader:read_char(prefix .. "race")
    local boss = reader:read_short(prefix .. "boss") ~= 0
    local child = reader:read_short(prefix .. "child") ~= 0
    local npc_type = reader:read_short(prefix .. "type")
    local behavior_id = reader:read_short(prefix .. "behavior_id")
    local hp = reader:read_three(prefix .. "hp")
    local tp = reader:read_short(prefix .. "tp")
    local min_damage = reader:read_short(prefix .. "min_damage")
    local max_damage = reader:read_short(prefix .. "max_damage")
    local accuracy = reader:read_short(prefix .. "accuracy")
    local evade = reader:read_short(prefix .. "evade")
    local armor = reader:read_short(prefix .. "armor")
    local return_damage = reader:read_char(prefix .. "return_damage")
    local element = reader:read_short(prefix .. "element")
    local element_damage = reader:read_short(prefix .. "element_damage")
    local element_weakness = reader:read_short(prefix .. "element_weakness")
    local element_weakness_damage = reader:read_short(prefix .. "element_weakness_damage")
    local level = reader:read_char(prefix .. "level")
    local experience = reader:read_three(prefix .. "experience")

    local record = {
      id = index,
      name = name,
      graphic_id = graphic_id,
      race = race,
      boss = boss,
      child = child,
      type = npc_type,
      behavior_id = behavior_id,
      hp = hp,
      tp = tp,
      min_damage = min_damage,
      max_damage = max_damage,
      accuracy = accuracy,
      evade = evade,
      armor = armor,
      return_damage = return_damage,
      element = element,
      element_damage = element_damage,
      element_weakness = element_weakness,
      element_weakness_damage = element_weakness_damage,
      level = level,
      experience = experience,
    }

    npcs[#npcs + 1] = record
    by_id[index] = record
  end

  return {
    signature = signature,
    rid = rid,
    version = version,
    npcs = npcs,
    by_id = by_id,
    bytes_remaining = reader:remaining(),
  }
end

function EnfParser.parse(data)
  local ok, result = pcall(parse_unsafe, data)
  if not ok then
    return nil, result
  end
  return result
end

return EnfParser
