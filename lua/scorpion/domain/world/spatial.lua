local M = {}

local MAP_ID_MIN = 0
local MAP_ID_MAX = 64008
local COORD_MIN = 0
local COORD_MAX = 252
local DEFAULT_DISTANCE = 15
local BUCKET_SIZE = 8

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function normalize_map_id(value)
  return clamp(to_int(value, 0), MAP_ID_MIN, MAP_ID_MAX)
end

local function normalize_coord(value)
  return clamp(to_int(value, 0), COORD_MIN, COORD_MAX)
end

local function normalize_distance(value)
  return math.max(0, to_int(value, DEFAULT_DISTANCE))
end

local function bucket_coord(coord)
  return math.floor(normalize_coord(coord) / BUCKET_SIZE)
end

local function bucket_key(bucket_x, bucket_y)
  return ("%d:%d"):format(bucket_x, bucket_y)
end

local function ensure_tables(self)
  self.spatial_index = self.spatial_index or {}
  self.session_spatial = self.session_spatial or {}
end

local function remove_spatial_ref(self, session_id)
  local refs = self.session_spatial[session_id]
  if not refs then
    return
  end

  local map_index = self.spatial_index[refs.map_id]
  if map_index then
    local bucket = map_index[refs.bucket_key]
    if bucket then
      bucket[session_id] = nil
      if next(bucket) == nil then
        map_index[refs.bucket_key] = nil
      end
    end

    if next(map_index) == nil then
      self.spatial_index[refs.map_id] = nil
    end
  end

  self.session_spatial[session_id] = nil
end

function M.remove_session_spatial(self, session_id)
  ensure_tables(self)
  local id = to_int(session_id, 0)
  if id <= 0 then
    return false
  end
  remove_spatial_ref(self, id)
  return true
end

function M.sync_session_spatial(self, session)
  ensure_tables(self)
  if not session then
    return false
  end

  local session_id = to_int(session.id, 0)
  if session_id <= 0 then
    return false
  end

  remove_spatial_ref(self, session_id)

  if session.connected ~= true then
    return false
  end

  local map_id = normalize_map_id(session.map_id)
  local x = normalize_coord(session.x)
  local y = normalize_coord(session.y)
  local bucket_x = bucket_coord(x)
  local bucket_y = bucket_coord(y)
  local key = bucket_key(bucket_x, bucket_y)

  local map_index = self.spatial_index[map_id]
  if map_index == nil then
    map_index = {}
    self.spatial_index[map_id] = map_index
  end

  local bucket = map_index[key]
  if bucket == nil then
    bucket = {}
    map_index[key] = bucket
  end

  bucket[session_id] = session
  self.session_spatial[session_id] = {
    map_id = map_id,
    bucket_key = key,
    bucket_x = bucket_x,
    bucket_y = bucket_y,
  }

  return true
end

function M.list_map_sessions(self, map_id)
  ensure_tables(self)
  local normalized_map = normalize_map_id(map_id)
  local result = {}
  local seen = {}
  local map_index = self.spatial_index[normalized_map]
  if map_index == nil then
    return result
  end

  for _, bucket in pairs(map_index) do
    for session_id, session in pairs(bucket) do
      if not seen[session_id]
        and session
        and session.connected
        and normalize_map_id(session.map_id) == normalized_map
      then
        seen[session_id] = true
        result[#result + 1] = session
      end
    end
  end

  return result
end

function M.list_nearby_sessions(self, center, max_distance)
  ensure_tables(self)
  local result = {}
  if center == nil then
    return result
  end

  local map_id = normalize_map_id(center.map_id)
  local map_index = self.spatial_index[map_id]
  if map_index == nil then
    return result
  end

  local x = normalize_coord(center.x)
  local y = normalize_coord(center.y)
  local distance = normalize_distance(max_distance)

  local min_x = math.max(COORD_MIN, x - distance)
  local max_x = math.min(COORD_MAX, x + distance)
  local min_y = math.max(COORD_MIN, y - distance)
  local max_y = math.min(COORD_MAX, y + distance)

  local min_bucket_x = bucket_coord(min_x)
  local max_bucket_x = bucket_coord(max_x)
  local min_bucket_y = bucket_coord(min_y)
  local max_bucket_y = bucket_coord(max_y)

  local seen = {}
  for bucket_y = min_bucket_y, max_bucket_y do
    for bucket_x = min_bucket_x, max_bucket_x do
      local bucket = map_index[bucket_key(bucket_x, bucket_y)]
      if bucket ~= nil then
        for session_id, session in pairs(bucket) do
          if not seen[session_id]
            and session
            and session.connected
            and normalize_map_id(session.map_id) == map_id
            and math.abs(normalize_coord(session.x) - x) <= distance
            and math.abs(normalize_coord(session.y) - y) <= distance
          then
            seen[session_id] = true
            result[#result + 1] = session
          end
        end
      end
    end
  end

  return result
end

return M
