package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./lua/?/?.lua",
  package.path,
}, ";")

local World = require("scorpion.domain.world")

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function abs(n)
  if n < 0 then
    return -n
  end
  return n
end

local config = {
  sessions = to_int(arg[1], 5000),
  queries = to_int(arg[2], 300),
  radius = to_int(arg[3], 15),
  map_id = to_int(arg[4], 46),
  seed = to_int(arg[5], 1337),
  dense_sessions = to_int(arg[6], 500),
  bucket_mode = tostring(arg[7] or "adaptive"),
}

if config.sessions < 1 then
  config.sessions = 1
end
if config.queries < 1 then
  config.queries = 1
end
if config.radius < 0 then
  config.radius = 0
end
if config.dense_sessions < 0 then
  config.dense_sessions = 0
end
if config.dense_sessions > config.sessions then
  config.dense_sessions = config.sessions
end

math.randomseed(config.seed)

local world = World.new()
if config.bucket_mode == "fixed4" then
  world.spatial_config.default_bucket_size = 4
  world.spatial_config.sparse_bucket_size = 4
  world.spatial_config.dense_bucket_size = 4
elseif config.bucket_mode == "fixed8" then
  world.spatial_config.default_bucket_size = 8
  world.spatial_config.sparse_bucket_size = 8
  world.spatial_config.dense_bucket_size = 8
elseif config.bucket_mode == "fixed16" then
  world.spatial_config.default_bucket_size = 16
  world.spatial_config.sparse_bucket_size = 16
  world.spatial_config.dense_bucket_size = 16
else
  config.bucket_mode = "adaptive"
end

for i = 1, config.sessions do
  local session = world:create_session("127.0.0.1:" .. tostring(20000 + i), "bench_" .. tostring(i))
  session.map_id = config.map_id

  if i <= config.dense_sessions then
    session.x = 100 + (i % 20)
    session.y = 100 + (math.floor(i / 20) % 20)
  else
    session.x = math.random(0, 252)
    session.y = math.random(0, 252)
  end

  world:sync_session_spatial(session)
end

local query_sessions = {}
for i = 1, config.queries do
  query_sessions[i] = world.sessions[math.random(1, config.sessions)]
end

local function list_to_set(list)
  local set = {}
  for _, session in ipairs(list) do
    set[session.id] = true
  end
  return set
end

local function set_size(set)
  local total = 0
  for _ in pairs(set) do
    total = total + 1
  end
  return total
end

local function equal_sets(a, b)
  for key in pairs(a) do
    if not b[key] then
      return false
    end
  end
  for key in pairs(b) do
    if not a[key] then
      return false
    end
  end
  return true
end

local function naive_nearby(center, radius)
  local list = {}
  for _, other in pairs(world.sessions) do
    if other.connected
      and other.map_id == center.map_id
      and abs(other.x - center.x) <= radius
      and abs(other.y - center.y) <= radius
    then
      list[#list + 1] = other
    end
  end
  return list
end

local indexed_results = {}
local naive_results = {}

local t0 = os.clock()
for i, center in ipairs(query_sessions) do
  indexed_results[i] = world:list_nearby_sessions(center, config.radius)
end
local t1 = os.clock()

for i, center in ipairs(query_sessions) do
  naive_results[i] = naive_nearby(center, config.radius)
end
local t2 = os.clock()

local mismatches = 0
local indexed_total = 0
local naive_total = 0

for i = 1, config.queries do
  local indexed_set = list_to_set(indexed_results[i])
  local naive_set = list_to_set(naive_results[i])
  indexed_total = indexed_total + set_size(indexed_set)
  naive_total = naive_total + set_size(naive_set)
  if not equal_sets(indexed_set, naive_set) then
    mismatches = mismatches + 1
  end
end

local indexed_ms = (t1 - t0) * 1000
local naive_ms = (t2 - t1) * 1000
local speedup = 0
if indexed_ms > 0 then
  speedup = naive_ms / indexed_ms
end

local spatial = world:spatial_snapshot()
local map_bucket_size = 0
local map_bucket_count = 0
for _, map_stats in ipairs(spatial.top_maps or {}) do
  if map_stats.map_id == config.map_id then
    map_bucket_size = map_stats.bucket_size or 0
    map_bucket_count = map_stats.buckets or 0
    break
  end
end

print("Spatial Benchmark")
print(string.rep("-", 64))
print(string.format("sessions=%d queries=%d radius=%d map=%d seed=%d dense=%d mode=%s",
  config.sessions,
  config.queries,
  config.radius,
  config.map_id,
  config.seed,
  config.dense_sessions,
  config.bucket_mode
))
print(string.format("indexed_total_ms=%.2f indexed_avg_ms=%.4f",
  indexed_ms,
  indexed_ms / config.queries
))
print(string.format("naive_total_ms=%.2f naive_avg_ms=%.4f",
  naive_ms,
  naive_ms / config.queries
))
print(string.format("speedup_x=%.2f", speedup))
print(string.format("indexed_avg_nearby=%.2f naive_avg_nearby=%.2f",
  indexed_total / config.queries,
  naive_total / config.queries
))
print(string.format("map_bucket_size=%d map_bucket_count=%d rebalances=%d nearby_avg_buckets=%.2f",
  map_bucket_size,
  map_bucket_count,
  spatial.rebalances or 0,
  spatial.nearby_avg_buckets or 0
))
print(string.format("mismatches=%d", mismatches))
print(string.rep("-", 64))
print("Usage: lua benchmark_spatial.lua [sessions] [queries] [radius] [map_id] [seed] [dense_sessions] [bucket_mode]")
print("bucket_mode: adaptive | fixed4 | fixed8 | fixed16")
