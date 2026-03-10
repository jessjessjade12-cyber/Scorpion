local M = {}

function M.lower(value)
  return string.lower(value or "")
end

function M.to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

function M.copy_table(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[M.copy_table(k)] = M.copy_table(v)
  end
  return out
end

function M.copy_character(row)
  return {
    id = row.id,
    name = row.name,
    level = row.level,
    sex = row.sex,
    hair_style = row.hair_style,
    hair_color = row.hair_color,
    race = row.race,
    admin = row.admin,
    map_id = row.map_id,
    x = row.x,
    y = row.y,
    direction = row.direction,
    inventory = M.copy_table(row.inventory),
    max_weight = row.max_weight,
    paperdoll = M.copy_table(row.paperdoll),
  }
end

function M.resolve_spawn(settings)
  local cfg = settings or {}
  local arena = cfg.arena or {}
  local base_spawn = cfg.new_character or {
    spawn_direction = 0,
    spawn_map = 5,
    spawn_x = 12,
    spawn_y = 24,
  }

  local spawn = {
    spawn_direction = base_spawn.spawn_direction or 0,
    spawn_map = base_spawn.spawn_map or arena.map or 5,
    spawn_x = base_spawn.spawn_x or 12,
    spawn_y = base_spawn.spawn_y or 24,
  }

  local first_spawn = (arena.spawns or {})[1]
  if arena.only and first_spawn and first_spawn.from then
    spawn.spawn_map = arena.map or spawn.spawn_map
    spawn.spawn_x = first_spawn.from.x
    spawn.spawn_y = first_spawn.from.y
  end

  return spawn
end

function M.mongo_config(settings)
  local root = (settings or {}).persistence or {}
  local cfg = root.mongodb or root.mongo or {}

  return {
    binary = cfg.mongosh_path or cfg.binary or "mongosh",
    database = cfg.database or "scorpion",
    uri = cfg.uri or "mongodb://127.0.0.1:27017",
  }
end

function M.js_quote(value)
  local s = tostring(value or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\r", "\\r")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end

  local count = 0
  local max_index = 0

  for key in pairs(tbl) do
    if type(key) ~= "number" then
      return false
    end

    local int_key = math.floor(key)
    if int_key ~= key or int_key < 1 then
      return false
    end

    if int_key > max_index then
      max_index = int_key
    end
    count = count + 1
  end

  return count == max_index
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  return keys
end

function M.lua_to_js(value)
  local kind = type(value)

  if kind == "nil" then
    return "null"
  end

  if kind == "boolean" then
    return value and "true" or "false"
  end

  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "0"
    end
    return tostring(value)
  end

  if kind == "string" then
    return M.js_quote(value)
  end

  if kind ~= "table" then
    return "null"
  end

  local pieces = {}

  if is_array(value) then
    for index = 1, #value do
      pieces[#pieces + 1] = M.lua_to_js(value[index])
    end
    return "[" .. table.concat(pieces, ",") .. "]"
  end

  for _, key in ipairs(sorted_keys(value)) do
    local encoded_key = M.js_quote(tostring(key))
    local encoded_value = M.lua_to_js(value[key])
    pieces[#pieces + 1] = encoded_key .. ":" .. encoded_value
  end

  return "{" .. table.concat(pieces, ",") .. "}"
end

local function convert_numeric_keys(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, entry in pairs(value) do
    local numeric_key = tonumber(key)
    if numeric_key ~= nil and tostring(numeric_key) == tostring(key) then
      key = numeric_key
    end
    out[key] = convert_numeric_keys(entry)
  end
  return out
end

function M.normalize_character(row, spawn)
  if type(row) ~= "table" then
    return nil
  end

  local normalized = {
    id = M.to_int(row.id, 0) or 0,
    name = M.lower(row.name),
    level = M.to_int(row.level, 0) or 0,
    sex = M.to_int(row.sex, 0) or 0,
    hair_style = M.to_int(row.hair_style, 1) or 1,
    hair_color = M.to_int(row.hair_color, 0) or 0,
    race = M.to_int(row.race, 0) or 0,
    admin = M.to_int(row.admin, 0) or 0,
    map_id = M.to_int(row.map_id, spawn.spawn_map) or spawn.spawn_map,
    x = M.to_int(row.x, spawn.spawn_x) or spawn.spawn_x,
    y = M.to_int(row.y, spawn.spawn_y) or spawn.spawn_y,
    direction = M.to_int(row.direction, spawn.spawn_direction) or spawn.spawn_direction,
    inventory = convert_numeric_keys(M.copy_table(row.inventory)),
    max_weight = row.max_weight ~= nil and M.to_int(row.max_weight, 0) or nil,
    paperdoll = convert_numeric_keys(M.copy_table(row.paperdoll)),
  }

  if normalized.id <= 0 or normalized.name == "" then
    return nil
  end

  return normalized
end

return M
