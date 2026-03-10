local M = {}

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp(value, low, high, fallback)
  local n = to_int(value, fallback)
  if n < low then
    return low
  end
  if n > high then
    return high
  end
  return n
end

local function normalize_map_id(value)
  return clamp(value, 0, 64008, 0)
end

local function normalize_npc_id(value)
  return clamp(value, 0, 64008, 0)
end

local function normalize_coord(value)
  return clamp(value, 0, 252, 0)
end

local function normalize_direction(value)
  return clamp(value, 0, 3, 0)
end

local function normalize_char(value)
  return clamp(value, 0, 252, 0)
end

local function static_map_npcs(self, map_id)
  local map = self.maps[map_id]
  local map_meta = map and map.meta or nil
  return (map_meta and map_meta.npcs) or {}
end

local function runtime_map_npcs(self, map_id, create)
  local runtime = self.runtime_npcs or {}
  self.runtime_npcs = runtime

  local map_npcs = runtime[map_id]
  if map_npcs == nil and create then
    map_npcs = {}
    runtime[map_id] = map_npcs
  end
  return map_npcs
end

local function prune_runtime_map(self, map_id)
  local map_npcs = runtime_map_npcs(self, map_id, false)
  if not map_npcs then
    return
  end

  for _ in pairs(map_npcs) do
    return
  end

  self.runtime_npcs[map_id] = nil
end

local function next_runtime_index(self, map_id)
  local used = {}

  for _, npc in ipairs(static_map_npcs(self, map_id)) do
    local npc_index = normalize_char(npc and npc.index)
    if npc_index > 0 then
      used[npc_index] = true
    end
  end

  local runtime = runtime_map_npcs(self, map_id, false) or {}
  for index in pairs(runtime) do
    local npc_index = normalize_char(index)
    if npc_index > 0 then
      used[npc_index] = true
    end
  end

  for index = 252, 1, -1 do
    if not used[index] then
      return index
    end
  end

  return 0
end

function M.list_map_npcs(self, map_id)
  local normalized_map = normalize_map_id(map_id)
  local merged = {}

  for _, npc in ipairs(static_map_npcs(self, normalized_map)) do
    merged[#merged + 1] = npc
  end

  local runtime = runtime_map_npcs(self, normalized_map, false) or {}
  for _, npc in pairs(runtime) do
    merged[#merged + 1] = npc
  end

  table.sort(merged, function(a, b)
    return normalize_char(a and a.index) < normalize_char(b and b.index)
  end)

  return merged
end

function M.get_runtime_npc_for_owner(self, owner_session_id)
  local owner_id = to_int(owner_session_id, 0)
  if owner_id <= 0 then
    return nil
  end

  local owners = self.runtime_npc_owners or {}
  self.runtime_npc_owners = owners

  local ref = owners[owner_id]
  if not ref then
    return nil
  end

  local runtime = runtime_map_npcs(self, normalize_map_id(ref.map_id), false)
  if not runtime then
    owners[owner_id] = nil
    return nil
  end

  local npc = runtime[normalize_char(ref.index)]
  if not npc then
    owners[owner_id] = nil
    return nil
  end

  return npc
end

function M.remove_runtime_npc_for_owner(self, owner_session_id)
  local owner_id = to_int(owner_session_id, 0)
  if owner_id <= 0 then
    return nil
  end

  local owners = self.runtime_npc_owners or {}
  self.runtime_npc_owners = owners

  local ref = owners[owner_id]
  if not ref then
    return nil
  end

  local map_id = normalize_map_id(ref.map_id)
  local index = normalize_char(ref.index)
  local runtime = runtime_map_npcs(self, map_id, false)
  local removed = nil

  if runtime then
    removed = runtime[index]
    runtime[index] = nil
    prune_runtime_map(self, map_id)
  end

  owners[owner_id] = nil
  return removed
end

function M.upsert_runtime_npc_for_owner(self, owner_session_id, spec)
  local owner_id = to_int(owner_session_id, 0)
  if owner_id <= 0 then
    return nil, false, nil
  end

  spec = spec or {}
  local map_id = normalize_map_id(spec.map_id)
  local npc_id = normalize_npc_id(spec.npc_id)
  if map_id <= 0 or npc_id <= 0 then
    return nil, false, nil
  end

  local x = normalize_coord(spec.x)
  local y = normalize_coord(spec.y)
  local direction = normalize_direction(spec.direction)

  local owners = self.runtime_npc_owners or {}
  self.runtime_npc_owners = owners

  local ref = owners[owner_id]
  local removed = nil

  if ref and normalize_map_id(ref.map_id) ~= map_id then
    removed = self:remove_runtime_npc_for_owner(owner_id)
    ref = nil
  end

  if ref then
    local runtime = runtime_map_npcs(self, map_id, false)
    local existing = runtime and runtime[normalize_char(ref.index)] or nil
    if existing then
      existing.id = npc_id
      existing.x = x
      existing.y = y
      existing.direction = direction
      existing.map_id = map_id
      return existing, false, removed
    end
    owners[owner_id] = nil
  end

  local index = next_runtime_index(self, map_id)
  if index <= 0 then
    return nil, false, removed
  end

  local runtime = runtime_map_npcs(self, map_id, true)
  local created = {
    map_id = map_id,
    index = index,
    id = npc_id,
    x = x,
    y = y,
    direction = direction,
    owner_session_id = owner_id,
    runtime = true,
  }

  runtime[index] = created
  owners[owner_id] = {
    map_id = map_id,
    index = index,
  }

  return created, true, removed
end

return M
