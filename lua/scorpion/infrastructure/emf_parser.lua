local EOInt = require("scorpion.transport.eoint")

local EmfParser = {}

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

function Reader:skip(count, label)
  self:read_bytes(count, label)
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

local function read_coords(reader, label)
  local prefix = label and (label .. ".") or ""
  return {
    x = reader:read_char(prefix .. "x"),
    y = reader:read_char(prefix .. "y"),
  }
end

local function read_bool(reader, label)
  return reader:read_char(label) ~= 0
end

local function parse_emf_unsafe(data)
  local reader = Reader.new(data)
  local signature = reader:read_bytes(3, "signature")
  if signature ~= "EMF" then
    error("invalid EMF signature")
  end

  local rid = {
    reader:read_short("rid[1]"),
    reader:read_short("rid[2]"),
  }

  local name = reader:read_bytes(24, "name")
  local map_type = reader:read_char("type")
  local timed_effect = reader:read_char("timed_effect")
  local music_id = reader:read_char("music_id")
  local music_control = reader:read_char("music_control")
  local ambient_sound_id = reader:read_short("ambient_sound_id")
  local width = reader:read_char("width")
  local height = reader:read_char("height")
  local fill_tile = reader:read_short("fill_tile")
  local map_available = read_bool(reader, "map_available")
  local can_scroll = read_bool(reader, "can_scroll")
  local relog_x = reader:read_char("relog_x")
  local relog_y = reader:read_char("relog_y")
  local unknown = reader:read_char("unknown")

  local npcs_count = reader:read_char("npcs_count")
  local npcs = {}
  for i = 1, npcs_count do
    local prefix = ("npcs[%d]."):format(i)
    local coords = read_coords(reader, prefix .. "coords")
    local npc_id = reader:read_short(prefix .. "id")
    local spawn_type = reader:read_char(prefix .. "spawn_type")
    local spawn_time = reader:read_short(prefix .. "spawn_time")
    local amount = reader:read_char(prefix .. "amount")

    npcs[#npcs + 1] = {
      index = i,
      coords = coords,
      id = npc_id,
      spawn_type = spawn_type,
      spawn_time = spawn_time,
      amount = amount,
    }
  end

  local legacy_door_keys_count = reader:read_char("legacy_door_keys_count")
  for i = 1, legacy_door_keys_count do
    read_coords(reader, ("legacy_door_keys[%d].coords"):format(i))
    reader:read_short(("legacy_door_keys[%d].key"):format(i))
  end

  local items_count = reader:read_char("items_count")
  for i = 1, items_count do
    read_coords(reader, ("items[%d].coords"):format(i))
    reader:read_short(("items[%d].key"):format(i))
    reader:read_char(("items[%d].chest_slot"):format(i))
    reader:read_short(("items[%d].item_id"):format(i))
    reader:read_short(("items[%d].spawn_time"):format(i))
    reader:read_three(("items[%d].amount"):format(i))
  end

  local tile_spec_rows_count = reader:read_char("tile_spec_rows_count")
  local tile_spec_rows = {}
  for i = 1, tile_spec_rows_count do
    local row_y = reader:read_char(("tile_spec_rows[%d].y"):format(i))
    local tiles_count = reader:read_char(("tile_spec_rows[%d].tiles_count"):format(i))
    local tiles = {}
    for j = 1, tiles_count do
      tiles[#tiles + 1] = {
        x = reader:read_char(("tile_spec_rows[%d].tiles[%d].x"):format(i, j)),
        tile_spec = reader:read_char(("tile_spec_rows[%d].tiles[%d].tile_spec"):format(i, j)),
      }
    end
    tile_spec_rows[#tile_spec_rows + 1] = {
      y = row_y,
      tiles = tiles,
    }
  end

  local warp_rows_count = reader:read_char("warp_rows_count")
  local warp_rows = {}
  for i = 1, warp_rows_count do
    local row_y = reader:read_char(("warp_rows[%d].y"):format(i))
    local tiles_count = reader:read_char(("warp_rows[%d].tiles_count"):format(i))
    local tiles = {}
    for j = 1, tiles_count do
      local prefix = ("warp_rows[%d].tiles[%d]."):format(i, j)
      tiles[#tiles + 1] = {
        x = reader:read_char(prefix .. "x"),
        warp = {
          destination_map = reader:read_short(prefix .. "warp.destination_map"),
          destination_coords = read_coords(reader, prefix .. "warp.destination_coords"),
          level_required = reader:read_char(prefix .. "warp.level_required"),
          door = reader:read_short(prefix .. "warp.door"),
        },
      }
    end
    warp_rows[#warp_rows + 1] = {
      y = row_y,
      tiles = tiles,
    }
  end

  for layer = 1, 9 do
    local rows_count = reader:read_char(("graphic_layers[%d].graphic_rows_count"):format(layer))
    for row = 1, rows_count do
      reader:read_char(("graphic_layers[%d].graphic_rows[%d].y"):format(layer, row))
      local tiles_count = reader:read_char(("graphic_layers[%d].graphic_rows[%d].tiles_count"):format(layer, row))
      for tile = 1, tiles_count do
        reader:read_char(("graphic_layers[%d].graphic_rows[%d].tiles[%d].x"):format(layer, row, tile))
        reader:read_short(("graphic_layers[%d].graphic_rows[%d].tiles[%d].graphic"):format(layer, row, tile))
      end
    end
  end

  local signs_count = reader:read_char("signs_count")
  for i = 1, signs_count do
    read_coords(reader, ("signs[%d].coords"):format(i))
    local string_data_length = reader:read_short(("signs[%d].string_data_length"):format(i)) - 1
    if string_data_length < 0 then
      error(("invalid sign string length at index %d"):format(i))
    end
    reader:skip(string_data_length, ("signs[%d].string_data"):format(i))
    reader:read_char(("signs[%d].title_length"):format(i))
  end

  return {
    signature = signature,
    rid = rid,
    name = name,
    type = map_type,
    timed_effect = timed_effect,
    music_id = music_id,
    music_control = music_control,
    ambient_sound_id = ambient_sound_id,
    width = width,
    height = height,
    fill_tile = fill_tile,
    map_available = map_available,
    can_scroll = can_scroll,
    relog_x = relog_x,
    relog_y = relog_y,
    unknown = unknown,
    npcs = npcs,
    tile_spec_rows = tile_spec_rows,
    warp_rows = warp_rows,
    bytes_remaining = reader:remaining(),
  }
end

function EmfParser.parse(data)
  local ok, result = pcall(parse_emf_unsafe, data)
  if not ok then
    return nil, result
  end

  return result
end

return EmfParser
