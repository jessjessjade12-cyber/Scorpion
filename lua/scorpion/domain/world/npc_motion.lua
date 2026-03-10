local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local M = {}

local Family = Protocol.Family
local Action = Protocol.Action

local SHOP_NPC_TYPE = 6
local DEFAULT_INTERVAL_SECONDS = 0.35
local DEFAULT_LEASH_RADIUS = 6
local DEFAULT_MOMENTUM_BIAS = 0.8
local DEFAULT_PAUSE_CHANCE = 0.18
local DEFAULT_CROWD_AVOID_RADIUS = 1
local DEFAULT_CROWD_AVOID_WEIGHT = 0.25
local DEFAULT_SCAN_DISTANCE = 14
local DEFAULT_SPEEDS = {
  [0] = 0.35,
  [1] = 0.45,
  [2] = 0.55,
  [3] = 0.70,
  [4] = 0.85,
  [5] = 1.05,
  [6] = 1.25,
  [7] = 0, -- no movement
}

local BLOCKED_TILE_SPECS = {
  [0] = true,  -- Wall
  [1] = true,  -- ChairDown
  [2] = true,  -- ChairLeft
  [3] = true,  -- ChairRight
  [4] = true,  -- ChairUp
  [5] = true,  -- ChairDownRight
  [6] = true,  -- ChairUpLeft
  [7] = true,  -- ChairAll
  [9] = true,  -- Chest
  [16] = true, -- BankVault
  [18] = true, -- Edge
  [20] = true, -- Board1
  [21] = true, -- Board2
  [22] = true, -- Board3
  [23] = true, -- Board4
  [24] = true, -- Board5
  [25] = true, -- Board6
  [26] = true, -- Board7
  [27] = true, -- Board8
  [28] = true, -- Jukebox
}

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

local function key_xy(x, y)
  return ("%d:%d"):format(x, y)
end

local function map_scan_distance(self)
  local cfg = self.npc_movement or {}
  return clamp(cfg.scan_distance, 1, 15, DEFAULT_SCAN_DISTANCE)
end

local function direction_step(x, y, direction)
  if direction == 0 then
    return x, y + 1
  end
  if direction == 1 then
    return x - 1, y
  end
  if direction == 2 then
    return x, y - 1
  end
  return x + 1, y
end

local function manhattan(ax, ay, bx, by)
  return math.abs(ax - bx) + math.abs(ay - by)
end

local function ensure_state(self)
  self.npc_movement = self.npc_movement or {
    crowd_avoid_radius = DEFAULT_CROWD_AVOID_RADIUS,
    crowd_avoid_weight = DEFAULT_CROWD_AVOID_WEIGHT,
    enabled = true,
    include_shop_npcs = false,
    interval_seconds = DEFAULT_INTERVAL_SECONDS,
    leash_radius = DEFAULT_LEASH_RADIUS,
    map_state = {},
    momentum_bias = DEFAULT_MOMENTUM_BIAS,
    next_tick = 0,
    pause_chance = DEFAULT_PAUSE_CHANCE,
    scan_distance = DEFAULT_SCAN_DISTANCE,
    speeds = DEFAULT_SPEEDS,
  }

  local cfg = self.npc_movement
  cfg.map_state = cfg.map_state or {}
  cfg.speeds = cfg.speeds or DEFAULT_SPEEDS
  cfg.next_tick = tonumber(cfg.next_tick) or 0
  cfg.enabled = cfg.enabled ~= false
  cfg.include_shop_npcs = cfg.include_shop_npcs == true
  cfg.interval_seconds = math.max(
    0.10,
    tonumber(cfg.interval_seconds) or DEFAULT_INTERVAL_SECONDS
  )
  cfg.leash_radius = math.max(1, to_int(cfg.leash_radius, DEFAULT_LEASH_RADIUS))
  cfg.momentum_bias = tonumber(cfg.momentum_bias) or DEFAULT_MOMENTUM_BIAS
  cfg.pause_chance = math.max(0, math.min(1, tonumber(cfg.pause_chance) or DEFAULT_PAUSE_CHANCE))
  cfg.crowd_avoid_radius = math.max(
    0,
    to_int(cfg.crowd_avoid_radius, DEFAULT_CROWD_AVOID_RADIUS)
  )
  cfg.crowd_avoid_weight = tonumber(cfg.crowd_avoid_weight) or DEFAULT_CROWD_AVOID_WEIGHT
  cfg.scan_distance = clamp(cfg.scan_distance, 1, 15, DEFAULT_SCAN_DISTANCE)

  return cfg
end

local function emf_npcs(map_meta)
  return (map_meta and map_meta.npcs) or {}
end

local function tile_lookup_for_map(state, map_meta)
  if state.tile_lookup then
    return state.tile_lookup
  end

  local lookup = {}
  for _, row in ipairs((map_meta and map_meta.tile_spec_rows) or {}) do
    local y = clamp(row and row.y, 0, 252, 0)
    local row_map = lookup[y]
    if not row_map then
      row_map = {}
      lookup[y] = row_map
    end

    for _, tile in ipairs((row and row.tiles) or {}) do
      local x = clamp(tile and tile.x, 0, 252, 0)
      row_map[x] = clamp(tile and tile.tile_spec, 0, 252, 0)
    end
  end

  state.tile_lookup = lookup
  return lookup
end

local function tile_spec(lookup, x, y)
  local row = lookup[y]
  if not row then
    return nil
  end
  return row[x]
end

local function npc_coords(npc)
  local coords = npc.coords or {}
  local x = clamp(coords.x or npc.x, 0, 252, 0)
  local y = clamp(coords.y or npc.y, 0, 252, 0)
  return x, y
end

local function npc_direction(npc)
  return clamp(npc and npc.direction, 0, 3, 0)
end

local function set_npc_position(npc, x, y, direction)
  npc.coords = npc.coords or {}
  npc.coords.x = x
  npc.coords.y = y
  npc.x = x
  npc.y = y
  npc.direction = clamp(direction, 0, 3, 0)
end

local function is_walkable(meta, lookup, x, y)
  local max_x = clamp(meta and meta.width, 0, 252, 0)
  local max_y = clamp(meta and meta.height, 0, 252, 0)
  if x < 0 or y < 0 or x > max_x or y > max_y then
    return false
  end
  local spec = tile_spec(lookup, x, y)
  if spec == nil then
    return true
  end
  return not BLOCKED_TILE_SPECS[spec]
end

local function session_point(session)
  return {
    map_id = clamp(session and session.map_id, 0, 64008, 0),
    x = clamp(session and session.x, 0, 252, 0),
    y = clamp(session and session.y, 0, 252, 0),
  }
end

local function npc_point(map_id, x, y)
  return {
    map_id = map_id,
    x = x,
    y = y,
  }
end

local function map_sessions(self, map_id)
  if self.list_map_sessions then
    return self:list_map_sessions(map_id)
  end
  local out = {}
  for _, session in pairs(self.sessions or {}) do
    if session.connected and session.map_id == map_id then
      out[#out + 1] = session
    end
  end
  return out
end

local function runtime_npcs_for_map(self, map_id)
  local runtime = (self.runtime_npcs or {})[map_id]
  if type(runtime) ~= "table" then
    return {}
  end
  return runtime
end

local function speed_for_spawn_type(cfg, spawn_type)
  local speeds = cfg.speeds or DEFAULT_SPEEDS
  local normalized = clamp(spawn_type, 0, 7, 7)
  local speed = tonumber(speeds[normalized])
  if speed == nil then
    speed = tonumber(DEFAULT_SPEEDS[normalized]) or 0
  end
  return math.max(0, speed)
end

local function is_shop_npc(self, npc_id)
  local enf = ((((self.pub or {}).client or {}).enf or {}).parsed or {})
  local by_id = enf.by_id or {}
  local npc = by_id[to_int(npc_id, 0)]
  if not npc then
    return false
  end
  return to_int(npc.type, 0) == SHOP_NPC_TYPE
end

local function ensure_map_state(cfg, map_id)
  local map_state = cfg.map_state[map_id]
  if not map_state then
    map_state = {
      npcs = {},
      tile_lookup = nil,
    }
    cfg.map_state[map_id] = map_state
  end
  return map_state
end

local function ensure_npc_state(map_state, npc)
  local index = clamp(npc and npc.index, 0, 252, 0)
  local state = map_state.npcs[index]
  local x, y = npc_coords(npc)
  local direction = npc_direction(npc)

  if not state then
    state = {
      direction = direction,
      home_x = x,
      home_y = y,
      next_move_at = 0,
      x = x,
      y = y,
    }
    map_state.npcs[index] = state
  else
    state.x = x
    state.y = y
    state.direction = direction
  end

  return state
end

local function score_player_crowd(cfg, player_occupied, x, y)
  local radius = cfg.crowd_avoid_radius or DEFAULT_CROWD_AVOID_RADIUS
  if radius <= 0 then
    return 0
  end

  local crowded = 0
  for dy = -radius, radius do
    for dx = -radius, radius do
      if player_occupied[key_xy(x + dx, y + dy)] then
        crowded = crowded + 1
      end
    end
  end

  local weight = cfg.crowd_avoid_weight or DEFAULT_CROWD_AVOID_WEIGHT
  return crowded * weight
end

local function choose_direction(self, cfg, meta, lookup, state, occupied, player_occupied)
  local x = state.x
  local y = state.y
  local current_direction = clamp(state.direction, 0, 3, 0)
  local best_direction = nil
  local best_score = nil
  local leash = cfg.leash_radius or DEFAULT_LEASH_RADIUS
  local dist_now = manhattan(x, y, state.home_x, state.home_y)
  local momentum_bias = cfg.momentum_bias or DEFAULT_MOMENTUM_BIAS

  for direction = 0, 3 do
    local nx, ny = direction_step(x, y, direction)
    if is_walkable(meta, lookup, nx, ny) and not occupied[key_xy(nx, ny)] then
      local score = math.random() * 0.5
      if direction == current_direction then
        score = score + momentum_bias
      end

      local dist_next = manhattan(nx, ny, state.home_x, state.home_y)
      if dist_now > leash then
        if dist_next < dist_now then
          score = score + 1.2
        else
          score = score - 1.2
        end
      elseif dist_next > leash then
        score = score - 0.4
      else
        score = score + 0.1
      end

      score = score - score_player_crowd(cfg, player_occupied, nx, ny)

      if best_score == nil or score > best_score then
        best_score = score
        best_direction = direction
      end
    end
  end

  return best_direction
end

local function build_move_packet(npc)
  local packet = Packet.new(Family.Npc, Action.Player)
  packet:add_int1(clamp(npc and npc.index, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.x, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.y, 0, 252, 0))
  packet:add_int1(clamp(npc and npc.direction, 0, 3, 0))
  packet:add_byte(255)
  packet:add_byte(255)
  packet:add_byte(255)
  return packet
end

local function notify_move(self, map_id, old_x, old_y, npc)
  local old_point = npc_point(map_id, old_x, old_y)
  local new_point = npc_point(map_id, clamp(npc.x, 0, 252, 0), clamp(npc.y, 0, 252, 0))
  local packet = build_move_packet(npc)
  local candidates = {}

  local scan_distance = map_scan_distance(self)
  if self.list_nearby_sessions then
    for _, session in ipairs(self:list_nearby_sessions(old_point, scan_distance)) do
      candidates[session.id] = session
    end
    for _, session in ipairs(self:list_nearby_sessions(new_point, scan_distance)) do
      candidates[session.id] = session
    end
  else
    for _, session in ipairs(map_sessions(self, map_id)) do
      candidates[session.id] = session
    end
  end

  for _, session in pairs(candidates) do
    if session.connected
      and session.pending_warp == nil
      and session.address ~= nil
      and session.map_id == map_id
      and (self:in_client_range(session, old_point) or self:in_client_range(session, new_point))
    then
      self:push_pending(session.address, packet)
    end
  end
end

local function active_map_ids(self)
  local ids = {}
  local seen = {}

  for map_id, count in pairs(self.spatial_map_counts or {}) do
    if count > 0 and not seen[map_id] then
      ids[#ids + 1] = map_id
      seen[map_id] = true
    end
  end

  if #ids == 0 then
    for _, session in pairs(self.sessions or {}) do
      if session.connected and session.pending_warp == nil then
        local map_id = clamp(session.map_id, 0, 64008, 0)
        if not seen[map_id] then
          ids[#ids + 1] = map_id
          seen[map_id] = true
        end
      end
    end
  end

  return ids
end

local function build_occupancy(self, map_id, static_npcs, runtime_npcs)
  local occupied = {}
  local player_occupied = {}

  for _, session in ipairs(map_sessions(self, map_id)) do
    if session.connected and session.pending_warp == nil then
      local x = clamp(session.x, 0, 252, 0)
      local y = clamp(session.y, 0, 252, 0)
      local key = key_xy(x, y)
      occupied[key] = true
      player_occupied[key] = true
    end
  end

  for _, npc in ipairs(static_npcs) do
    local x, y = npc_coords(npc)
    occupied[key_xy(x, y)] = true
  end

  for _, npc in pairs(runtime_npcs) do
    local x = clamp(npc and npc.x, 0, 252, 0)
    local y = clamp(npc and npc.y, 0, 252, 0)
    occupied[key_xy(x, y)] = true
  end

  return occupied, player_occupied
end

local function tick_map(self, cfg, map_id, now)
  local map_meta = self:get_map_meta(map_id)
  local static_npcs = emf_npcs(map_meta)
  if #static_npcs == 0 then
    return 0
  end

  local map_state = ensure_map_state(cfg, map_id)
  local lookup = tile_lookup_for_map(map_state, map_meta)
  local runtime = runtime_npcs_for_map(self, map_id)
  local occupied, player_occupied = build_occupancy(self, map_id, static_npcs, runtime)
  local moved = 0

  for _, npc in ipairs(static_npcs) do
    local index = clamp(npc and npc.index, 0, 252, 0)
    local npc_id = clamp(npc and npc.id, 0, 64008, 0)
    local spawn_type = clamp(npc and npc.spawn_type, 0, 7, 7)

    if index > 0 and npc_id > 0 then
      if cfg.include_shop_npcs or not is_shop_npc(self, npc_id) then
        local speed = speed_for_spawn_type(cfg, spawn_type)
        if speed > 0 then
          local state = ensure_npc_state(map_state, npc)
          if now >= (state.next_move_at or 0) then
            local next_move_at = now + speed
            if math.random() < cfg.pause_chance then
              state.next_move_at = next_move_at
            else
              local x, y = npc_coords(npc)
              occupied[key_xy(x, y)] = nil

              local direction = choose_direction(
                self,
                cfg,
                map_meta,
                lookup,
                state,
                occupied,
                player_occupied
              )

              if direction ~= nil then
                local nx, ny = direction_step(x, y, direction)
                set_npc_position(npc, nx, ny, direction)
                state.next_move_at = next_move_at
                state.direction = direction
                state.x = nx
                state.y = ny
                occupied[key_xy(nx, ny)] = true
                notify_move(self, map_id, x, y, npc)
                moved = moved + 1
              else
                occupied[key_xy(x, y)] = true
                state.next_move_at = next_move_at
              end
            end
          end
        end
      end
    end
  end

  return moved
end

function M.configure_npc_movement(self, settings)
  local cfg = ensure_state(self)
  local input = (settings and settings.npc_movement) or {}

  if input.enabled ~= nil then
    cfg.enabled = input.enabled ~= false
  end
  if input.include_shop_npcs ~= nil then
    cfg.include_shop_npcs = input.include_shop_npcs == true
  end
  if input.interval_seconds ~= nil then
    cfg.interval_seconds = math.max(0.10, tonumber(input.interval_seconds) or cfg.interval_seconds)
  end
  if input.pause_chance ~= nil then
    cfg.pause_chance = math.max(0, math.min(1, tonumber(input.pause_chance) or cfg.pause_chance))
  end
  if input.leash_radius ~= nil then
    cfg.leash_radius = math.max(1, to_int(input.leash_radius, cfg.leash_radius))
  end
  if input.momentum_bias ~= nil then
    cfg.momentum_bias = tonumber(input.momentum_bias) or cfg.momentum_bias
  end
  if input.crowd_avoid_radius ~= nil then
    cfg.crowd_avoid_radius = math.max(0, to_int(input.crowd_avoid_radius, cfg.crowd_avoid_radius))
  end
  if input.crowd_avoid_weight ~= nil then
    cfg.crowd_avoid_weight = tonumber(input.crowd_avoid_weight) or cfg.crowd_avoid_weight
  end
  if input.scan_distance ~= nil then
    cfg.scan_distance = clamp(input.scan_distance, 1, 15, cfg.scan_distance)
  end
  if type(input.speeds) == "table" then
    cfg.speeds = cfg.speeds or {}
    for spawn_type = 0, 7 do
      local override = input.speeds[spawn_type]
      if override ~= nil then
        cfg.speeds[spawn_type] = math.max(0, tonumber(override) or 0)
      end
    end
  end

  return true
end

function M.tick_npcs(self, now)
  local cfg = ensure_state(self)
  if not cfg.enabled then
    return 0
  end

  now = tonumber(now) or os.clock()
  if now < (cfg.next_tick or 0) then
    return 0
  end
  cfg.next_tick = now + cfg.interval_seconds

  local moved = 0
  for _, map_id in ipairs(active_map_ids(self)) do
    moved = moved + tick_map(self, cfg, map_id, now)
  end

  return moved
end

return M
