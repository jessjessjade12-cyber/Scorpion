local M = {}

local MAP_ID_MIN = 0
local MAP_ID_MAX = 64008
local COORD_MIN = 0
local COORD_MAX = 252
local DEFAULT_DISTANCE = 15
local DEFAULT_BUCKET_SIZE = 8
local MIN_BUCKET_SIZE = 4
local MAX_BUCKET_SIZE = 16
local DEFAULT_SPARSE_BUCKET_SIZE = 16
local DEFAULT_DENSE_BUCKET_SIZE = 4
local DEFAULT_SPARSE_ENTER = 48
local DEFAULT_SPARSE_EXIT = 72
local DEFAULT_DENSE_ENTER = 220
local DEFAULT_DENSE_EXIT = 180

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

local function normalize_bucket_size(value, fallback)
  local size = to_int(value, fallback)
  return clamp(size, MIN_BUCKET_SIZE, MAX_BUCKET_SIZE)
end

local function bucket_coord(coord, bucket_size)
  return math.floor(normalize_coord(coord) / bucket_size)
end

local function bucket_key(bucket_x, bucket_y)
  return ("%d:%d"):format(bucket_x, bucket_y)
end

local function ensure_tables(self)
  self.spatial_index = self.spatial_index or {}
  self.session_spatial = self.session_spatial or {}
  self.spatial_bucket_size = self.spatial_bucket_size or {}
  self.spatial_map_counts = self.spatial_map_counts or {}
  self.spatial_map_bucket_counts = self.spatial_map_bucket_counts or {}
  self.spatial_reindexing = self.spatial_reindexing or {}
  self.spatial_metrics = self.spatial_metrics or {
    map_calls = 0,
    map_results = 0,
    nearby_buckets = 0,
    nearby_calls = 0,
    nearby_results = 0,
    rebalances = 0,
  }
end

local function spatial_config(self)
  local cfg = self.spatial_config or {}
  local normal_bucket_size = normalize_bucket_size(
    cfg.normal_bucket_size or cfg.default_bucket_size,
    DEFAULT_BUCKET_SIZE
  )
  local sparse_bucket_size = normalize_bucket_size(
    cfg.sparse_bucket_size,
    DEFAULT_SPARSE_BUCKET_SIZE
  )
  local dense_bucket_size = normalize_bucket_size(
    cfg.dense_bucket_size,
    DEFAULT_DENSE_BUCKET_SIZE
  )
  local sparse_enter = math.max(0, to_int(cfg.sparse_enter, DEFAULT_SPARSE_ENTER))
  local sparse_exit = math.max(sparse_enter, to_int(cfg.sparse_exit, DEFAULT_SPARSE_EXIT))
  local dense_enter = math.max(sparse_exit + 1, to_int(cfg.dense_enter, DEFAULT_DENSE_ENTER))
  local dense_exit = to_int(cfg.dense_exit, DEFAULT_DENSE_EXIT)
  dense_exit = math.max(sparse_exit + 1, math.min(dense_enter, dense_exit))

  return {
    normal_bucket_size = normal_bucket_size,
    sparse_bucket_size = sparse_bucket_size,
    dense_bucket_size = dense_bucket_size,
    sparse_enter = sparse_enter,
    sparse_exit = sparse_exit,
    dense_enter = dense_enter,
    dense_exit = dense_exit,
  }
end

local function current_bucket_size(self, map_id)
  local configured = self.spatial_bucket_size[map_id]
  if configured ~= nil then
    return normalize_bucket_size(configured, DEFAULT_BUCKET_SIZE)
  end
  local cfg = spatial_config(self)
  return cfg.normal_bucket_size
end

local function clear_map_index(self, map_id)
  self.spatial_index[map_id] = nil
  self.spatial_map_counts[map_id] = nil
  self.spatial_map_bucket_counts[map_id] = nil
end

local function upsert_spatial_ref(self, session, map_id)
  local session_id = to_int(session and session.id, 0)
  if session_id <= 0 then
    return false
  end

  local bucket_size = current_bucket_size(self, map_id)
  local x = normalize_coord(session.x)
  local y = normalize_coord(session.y)
  local bucket_x = bucket_coord(x, bucket_size)
  local bucket_y = bucket_coord(y, bucket_size)
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
    self.spatial_map_bucket_counts[map_id] = (self.spatial_map_bucket_counts[map_id] or 0) + 1
  end

  if bucket[session_id] == nil then
    self.spatial_map_counts[map_id] = (self.spatial_map_counts[map_id] or 0) + 1
  end

  bucket[session_id] = session
  self.session_spatial[session_id] = {
    map_id = map_id,
    bucket_key = key,
    bucket_x = bucket_x,
    bucket_y = bucket_y,
    bucket_size = bucket_size,
  }

  return true
end

local function remove_spatial_ref(self, session_id)
  local refs = self.session_spatial[session_id]
  if not refs then
    return nil
  end

  local map_id = refs.map_id
  local map_index = self.spatial_index[map_id]
  if map_index then
    local bucket = map_index[refs.bucket_key]
    if bucket then
      if bucket[session_id] ~= nil then
        bucket[session_id] = nil
        local map_count = (self.spatial_map_counts[map_id] or 1) - 1
        if map_count > 0 then
          self.spatial_map_counts[map_id] = map_count
        else
          self.spatial_map_counts[map_id] = nil
        end
      end

      if next(bucket) == nil then
        map_index[refs.bucket_key] = nil
        local bucket_count = (self.spatial_map_bucket_counts[map_id] or 1) - 1
        if bucket_count > 0 then
          self.spatial_map_bucket_counts[map_id] = bucket_count
        else
          self.spatial_map_bucket_counts[map_id] = nil
        end
      end
    end

    if next(map_index) == nil then
      clear_map_index(self, map_id)
    end
  end

  self.session_spatial[session_id] = nil
  return map_id
end

local function collect_map_sessions(self, map_id)
  local sessions = {}
  for _, session in pairs(self.sessions or {}) do
    if session and session.connected == true and normalize_map_id(session.map_id) == map_id then
      sessions[#sessions + 1] = session
    end
  end
  return sessions
end

local function target_bucket_size(self, map_id, current_size, session_count)
  local cfg = spatial_config(self)
  local sparse_bucket_size = cfg.sparse_bucket_size
  local normal_bucket_size = cfg.normal_bucket_size
  local dense_bucket_size = cfg.dense_bucket_size
  local sparse_enter = cfg.sparse_enter
  local sparse_exit = cfg.sparse_exit
  local dense_enter = cfg.dense_enter
  local dense_exit = cfg.dense_exit

  if current_size == dense_bucket_size then
    if session_count <= dense_exit then
      return normal_bucket_size
    end
    return dense_bucket_size
  end

  if current_size == sparse_bucket_size then
    if session_count >= sparse_exit then
      return normal_bucket_size
    end
    return sparse_bucket_size
  end

  if session_count >= dense_enter then
    return dense_bucket_size
  end
  if session_count <= sparse_enter then
    return sparse_bucket_size
  end

  return normal_bucket_size
end

local function rebuild_map(self, map_id, bucket_size)
  if self.spatial_reindexing[map_id] then
    return false
  end

  local normalized = normalize_bucket_size(bucket_size, DEFAULT_BUCKET_SIZE)
  local sessions = collect_map_sessions(self, map_id)
  self.spatial_reindexing[map_id] = true
  self.spatial_bucket_size[map_id] = normalized
  clear_map_index(self, map_id)

  for _, session in ipairs(sessions) do
    local session_id = to_int(session.id, 0)
    if session_id > 0 then
      self.session_spatial[session_id] = nil
    end
  end

  for _, session in ipairs(sessions) do
    upsert_spatial_ref(self, session, map_id)
  end

  self.spatial_reindexing[map_id] = nil
  self.spatial_metrics.rebalances = (self.spatial_metrics.rebalances or 0) + 1
  return true
end

local function rebalance_map_if_needed(self, map_id)
  if map_id == nil then
    return false
  end

  if self.spatial_reindexing[map_id] then
    return false
  end

  local current_size = current_bucket_size(self, map_id)
  local session_count = self.spatial_map_counts[map_id] or 0
  local target_size = target_bucket_size(self, map_id, current_size, session_count)

  if target_size == current_size then
    return false
  end

  return rebuild_map(self, map_id, target_size)
end

function M.remove_session_spatial(self, session_id)
  ensure_tables(self)
  local id = to_int(session_id, 0)
  if id <= 0 then
    return false
  end
  local removed_map_id = remove_spatial_ref(self, id)
  rebalance_map_if_needed(self, removed_map_id)
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

  local previous_map_id = remove_spatial_ref(self, session_id)
  rebalance_map_if_needed(self, previous_map_id)

  if session.connected ~= true then
    return false
  end

  local map_id = normalize_map_id(session.map_id)
  upsert_spatial_ref(self, session, map_id)
  rebalance_map_if_needed(self, map_id)
  return true
end

function M.list_map_sessions(self, map_id)
  ensure_tables(self)
  local normalized_map = normalize_map_id(map_id)
  local result = {}
  local map_index = self.spatial_index[normalized_map]
  if map_index == nil then
    return result
  end

  self.spatial_metrics.map_calls = (self.spatial_metrics.map_calls or 0) + 1

  for _, bucket in pairs(map_index) do
    for _, session in pairs(bucket) do
      if session
        and session.connected
        and session.map_id == normalized_map
      then
        result[#result + 1] = session
      end
    end
  end

  self.spatial_metrics.map_results = (self.spatial_metrics.map_results or 0) + #result
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
  local bucket_size = current_bucket_size(self, map_id)

  local min_x = math.max(COORD_MIN, x - distance)
  local max_x = math.min(COORD_MAX, x + distance)
  local min_y = math.max(COORD_MIN, y - distance)
  local max_y = math.min(COORD_MAX, y + distance)

  local min_bucket_x = bucket_coord(min_x, bucket_size)
  local max_bucket_x = bucket_coord(max_x, bucket_size)
  local min_bucket_y = bucket_coord(min_y, bucket_size)
  local max_bucket_y = bucket_coord(max_y, bucket_size)

  local buckets_scanned = 0
  self.spatial_metrics.nearby_calls = (self.spatial_metrics.nearby_calls or 0) + 1

  for bucket_y = min_bucket_y, max_bucket_y do
    for bucket_x = min_bucket_x, max_bucket_x do
      local bucket = map_index[bucket_key(bucket_x, bucket_y)]
      if bucket ~= nil then
        buckets_scanned = buckets_scanned + 1
        for _, session in pairs(bucket) do
          if session
            and session.connected
            and session.map_id == map_id
            and math.abs((session.x or 0) - x) <= distance
            and math.abs((session.y or 0) - y) <= distance
          then
            result[#result + 1] = session
          end
        end
      end
    end
  end

  self.spatial_metrics.nearby_buckets = (self.spatial_metrics.nearby_buckets or 0) + buckets_scanned
  self.spatial_metrics.nearby_results = (self.spatial_metrics.nearby_results or 0) + #result
  return result
end

function M.spatial_snapshot(self)
  ensure_tables(self)
  local indexed_sessions = 0
  local map_count = 0
  local top_maps = {}

  for map_id, session_count in pairs(self.spatial_map_counts) do
    map_count = map_count + 1
    indexed_sessions = indexed_sessions + session_count
    top_maps[#top_maps + 1] = {
      map_id = map_id,
      sessions = session_count,
      bucket_size = current_bucket_size(self, map_id),
      buckets = self.spatial_map_bucket_counts[map_id] or 0,
    }
  end

  table.sort(top_maps, function(a, b)
    if a.sessions == b.sessions then
      return a.map_id < b.map_id
    end
    return a.sessions > b.sessions
  end)

  local metrics = self.spatial_metrics or {}
  local nearby_calls = metrics.nearby_calls or 0
  local map_calls = metrics.map_calls or 0

  return {
    indexed_sessions = indexed_sessions,
    maps_indexed = map_count,
    map_avg_results = map_calls > 0 and (metrics.map_results or 0) / map_calls or 0,
    map_calls = map_calls,
    nearby_avg_buckets = nearby_calls > 0 and (metrics.nearby_buckets or 0) / nearby_calls or 0,
    nearby_avg_results = nearby_calls > 0 and (metrics.nearby_results or 0) / nearby_calls or 0,
    nearby_calls = nearby_calls,
    rebalances = metrics.rebalances or 0,
    top_maps = top_maps,
  }
end

return M
