local ArenaScriptRunner = {}
ArenaScriptRunner.__index = ArenaScriptRunner

local Nearby = require("scorpion.application.handlers.support.nearby")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")
local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action
local AVATAR_CHANGE_TYPE_HAIR = 2
local AVATAR_CHANGE_TYPE_HAIR_COLOR = 3
local MAX_INT4 = 4097152080
local MAX_INT3 = 16194276
local DEFAULT_MAX_WEIGHT = 120

local function random_choice(list)
  if type(list) ~= "table" or #list == 0 then
    return nil
  end
  return list[math.random(1, #list)]
end

local function clamp_int(value, low, high)
  value = math.floor(tonumber(value) or low)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function resolve_appearance_limits(settings)
  local limits = (settings and settings.appearance_limits) or {}
  return {
    hair_style_max = math.max(1, clamp_int(limits.hair_style_max or 20, 1, 252)),
    hair_color_max = math.max(0, clamp_int(limits.hair_color_max or 9, 0, 252)),
    skin_max = math.max(0, clamp_int(limits.skin_max or 4, 0, 252)),
  }
end

local function derive_appearance_from_npc_id(npc_id, limits)
  local id = clamp_int(npc_id, 0, 252)
  return {
    sex = id % 2,
    hair_style = (id % limits.hair_style_max) + 1,
    hair_color = math.floor(id / 2) % (limits.hair_color_max + 1),
    skin = math.floor(id / 3) % (limits.skin_max + 1),
  }
end

local function disguise_requires_full_refresh(disguise)
  if not disguise then
    return false
  end
  return disguise.name ~= nil
    or disguise.level ~= nil
    or disguise.sex ~= nil
    or disguise.skin ~= nil
end

local function active_disguise(session)
  local disguise = session and session.script_disguise or nil
  if not disguise then
    return nil
  end

  local expires_at = tonumber(disguise.expires_at) or 0
  if expires_at > 0 and os.time() >= expires_at then
    session.script_disguise = nil
    session.script_disguise_full_refresh = nil
    return nil
  end

  return disguise
end

local function resolve_hair(character, disguise)
  local hair_style = character and character.hair_style or 1
  local hair_color = character and character.hair_color or 0

  if disguise and disguise.hair_style ~= nil then
    hair_style = disguise.hair_style
  end
  if disguise and disguise.hair_color ~= nil then
    hair_color = disguise.hair_color
  end

  return clamp_int(hair_style, 0, 252), clamp_int(hair_color, 0, 252)
end

local function add_avatar_hair_change(reply, session, character, disguise)
  local hair_style, hair_color = resolve_hair(character, disguise)
  local change_type = AVATAR_CHANGE_TYPE_HAIR
  if disguise and disguise.hair_style == nil and disguise.hair_color ~= nil then
    change_type = AVATAR_CHANGE_TYPE_HAIR_COLOR
  end

  reply:add_int2(session.id)
  reply:add_int1(change_type)
  reply:add_int1(0)

  if change_type == AVATAR_CHANGE_TYPE_HAIR_COLOR then
    reply:add_int1(hair_color)
    return
  end

  reply:add_int1(hair_style)
  reply:add_int1(hair_color)
end

local function point_from_session(session)
  return {
    map_id = clamp_int(session and session.map_id, 0, 64008),
    x = clamp_int(session and session.x, 0, 252),
    y = clamp_int(session and session.y, 0, 252),
  }
end

local function push_packet_near_origin(world, origin, packet, include_session, exclude_session_or_id)
  if not world or not origin or not packet then
    return
  end

  local include_id = include_session and include_session.id or nil
  local exclude_id = nil
  if type(exclude_session_or_id) == "table" then
    exclude_id = exclude_session_or_id.id
  else
    exclude_id = exclude_session_or_id
  end

  for _, receiver in pairs(world.sessions) do
    local in_scope = receiver.connected
      and receiver.pending_warp == nil
      and receiver.address ~= nil
      and (exclude_id == nil or receiver.id ~= exclude_id)
      and receiver.map_id == origin.map_id
      and (world:in_range(receiver, origin) or (include_id ~= nil and receiver.id == include_id))
    if in_scope then
      world:push_pending(receiver.address, packet)
    end
  end
end

local function build_npc_agree_packet(npc)
  local packet = Packet.new(Family.Npc, Action.Agree)
  packet:add_int1(1)
  Nearby.add_npc_map_info(packet, npc)
  return packet
end

local function build_npc_position_packet(npc)
  local packet = Packet.new(Family.Npc, Action.Player)
  packet:add_int1(clamp_int(npc and npc.index, 0, 252))
  packet:add_int1(clamp_int(npc and npc.x, 0, 252))
  packet:add_int1(clamp_int(npc and npc.y, 0, 252))
  packet:add_int1(clamp_int(npc and npc.direction, 0, 3))
  packet:add_byte(255)
  packet:add_byte(255)
  packet:add_byte(255)
  return packet
end

local function build_npc_despawn_packet(npc)
  local packet = Packet.new(Family.Npc, Action.Spec)
  packet:add_int2(0) -- killer_id
  packet:add_int1(clamp_int(npc and npc.direction, 0, 3))
  packet:add_int2(clamp_int(npc and npc.index, 0, 64008))
  packet:add_int2(0) -- drop_index
  packet:add_int2(0) -- drop_id
  packet:add_int1(clamp_int(npc and npc.x, 0, 252))
  packet:add_int1(clamp_int(npc and npc.y, 0, 252))
  packet:add_int4(0) -- drop_amount
  packet:add_int3(0) -- damage
  return packet
end

local function inventory_proxy(runner)
  return {
    get_pub_blob = function(_, key)
      return (((runner.world or {}).pub or {}).client or {})[key]
    end,
  }
end

local function resolve_weight(runner, session)
  local current = 0
  local ok, result = pcall(function()
    return InventoryState.total_weight(inventory_proxy(runner), session)
  end)
  if ok then
    current = result or 0
  end

  local max = clamp_int(session and session.max_weight or DEFAULT_MAX_WEIGHT, 0, 252)
  return clamp_int(current, 0, 252), max
end

local function build_item_get_packet(runner, session, item_id, amount)
  local packet = Packet.new(Family.Item, Action.Get)
  local current_weight, max_weight = resolve_weight(runner, session)

  packet:add_int2(0) -- taken_item_index (0 for script-granted item)
  packet:add_int2(clamp_int(item_id, 0, 64008))
  packet:add_int3(clamp_int(amount, 0, MAX_INT3))
  packet:add_int1(current_weight)
  packet:add_int1(max_weight)
  return packet
end

local function build_item_kick_packet(runner, session, item_id, remaining_amount)
  local packet = Packet.new(Family.Item, Action.Kick)
  local current_weight = select(1, resolve_weight(runner, session))

  packet:add_int2(clamp_int(item_id, 0, 64008))
  packet:add_int4(clamp_int(remaining_amount, 0, MAX_INT4))
  packet:add_int1(current_weight)
  return packet
end

function ArenaScriptRunner.new(deps)
  local cfg = (((deps.settings or {}).scripts or {}).arena or {})
  local runner = setmetatable({
    accounts = deps.accounts,
    enabled = cfg.enabled ~= false,
    logger = deps.logger,
    module = nil,
    path = cfg.path or "lua/scorpion/scripts/arena.lua",
    settings = cfg,
    world = deps.world,
  }, ArenaScriptRunner)

  runner.api = {
    -- Returns arena script config from settings.scripts.arena.
    config = function()
      return runner.settings
    end,
    log = function(level, message, fields)
      if not runner.logger then
        return
      end
      if level == "error" then
        runner.logger:error(message, fields)
      elseif level == "warn" then
        runner.logger:warn(message, fields)
      else
        runner.logger:info(message, fields)
      end
    end,
    random_choice = function(list)
      return random_choice(list)
    end,
    random_npc_id = function(list)
      local source = list or runner.settings.loser_npc_ids
      local picked = random_choice(source)
      if picked ~= nil then
        return clamp_int(picked, 0, 252)
      end
      return clamp_int(math.random(1, 252), 0, 252)
    end,
    clear_disguise = function(session)
      if session then
        local force_full_refresh = session.script_disguise_full_refresh == true
          or session.script_npc_proxy_enabled == true
        runner:disable_npc_proxy(session, "clear_disguise")
        session.script_disguise = nil
        session.script_disguise_full_refresh = nil
        runner:refresh_character(session, "clear_disguise", force_full_refresh)
      end
    end,
    -- Returns current gold amount for a session.
    get_gold = function(session)
      if not session then
        return 0
      end
      return InventoryState.gold_amount(session)
    end,
    -- Adds or removes gold from a session inventory.
    -- Positive delta adds gold, negative delta subtracts (clamped at 0).
    -- Returns: next_amount, applied_delta
    add_gold = function(session, delta)
      if not session then
        return 0, 0
      end
      local change = clamp_int(delta or 0, -MAX_INT4, MAX_INT4)
      local current = InventoryState.gold_amount(session)
      local next_amount = InventoryState.set_gold_amount(session, current + change)
      runner:sync_gold_packet(session, current, next_amount)
      return next_amount, next_amount - current
    end,
    -- Sets absolute gold amount for a session.
    set_gold = function(session, amount)
      if not session then
        return 0
      end
      local current = InventoryState.gold_amount(session)
      local next_amount = InventoryState.set_gold_amount(session, amount)
      runner:sync_gold_packet(session, current, next_amount)
      return next_amount
    end,
    -- Warps a player to the given map and coordinates.
    -- direction: 0=down, 1=left, 2=up, 3=right (optional, keeps current if nil)
    warp_player = function(session, map_id, x, y, direction)
      if not session then
        return false
      end
      return runner.world:request_local_warp(session, map_id, x, y, direction)
    end,
    -- Respawns a player at the arena relog/spawn point.
    arena_respawn = function(session)
      if not session then
        return
      end
      runner.world:arena_respawn(session)
    end,
    -- Applies a temporary appearance override using only provided fields.
    -- Unspecified fields keep the character's current appearance.
    temporarily_override_appearance = function(session, opts)
      if not session then
        return nil
      end

      runner:disable_npc_proxy(session, "override")

      opts = opts or {}
      local limits = resolve_appearance_limits(runner.settings)
      local seconds = math.max(
        1,
        math.floor(tonumber(opts.seconds) or tonumber(runner.settings.loser_duration_seconds) or 60)
      )

      local disguise = {
        expires_at = os.time() + seconds,
      }

      if opts.name ~= nil then
        disguise.name = opts.name
      end
      if opts.level ~= nil then
        disguise.level = clamp_int(opts.level, 0, 252)
      end
      if opts.sex ~= nil then
        disguise.sex = clamp_int(opts.sex, 0, 1)
      end
      if opts.hair_style ~= nil then
        disguise.hair_style = clamp_int(opts.hair_style, 0, limits.hair_style_max)
      end
      if opts.hair_color ~= nil then
        disguise.hair_color = clamp_int(opts.hair_color, 0, limits.hair_color_max)
      end
      if opts.skin ~= nil then
        disguise.skin = clamp_int(opts.skin, 0, limits.skin_max)
      end

      session.script_disguise = disguise
      session.script_disguise_full_refresh = disguise_requires_full_refresh(disguise)
      runner:refresh_character(session, "override")
      return disguise
    end,
    -- Applies a temporary appearance override interpreted as an NPC-like disguise.
    -- The disguise is serialized by handlers/support/nearby.lua.
    temporarily_disguise_as_npc = function(session, opts)
      if not session then
        return nil
      end

      opts = opts or {}
      local limits = resolve_appearance_limits(runner.settings)
      local npc_id = clamp_int(
        opts.npc_id or runner.api.random_npc_id(opts.npc_ids),
        0,
        252
      )
      local appearance = derive_appearance_from_npc_id(npc_id, limits)
      local seconds = math.max(
        1,
        math.floor(tonumber(opts.seconds) or tonumber(runner.settings.loser_duration_seconds) or 60)
      )
      local now = os.time()

      session.script_disguise = {
        expires_at = now + seconds,
        hair_color = clamp_int(opts.hair_color or appearance.hair_color, 0, limits.hair_color_max),
        hair_style = clamp_int(opts.hair_style or appearance.hair_style, 0, limits.hair_style_max),
        level = opts.level ~= nil and clamp_int(opts.level, 0, 252) or nil,
        name = opts.name,
        npc_id = npc_id,
        sex = clamp_int(opts.sex or appearance.sex, 0, 1),
        skin = clamp_int(opts.skin or appearance.skin, 0, limits.skin_max),
      }
      session.script_disguise_full_refresh = true
      session.script_npc_proxy_enabled = true
      session.script_npc_proxy_npc_id = npc_id
      session.script_force_invisible = true
      session.invisible = true

      runner:refresh_character(session, "npc_disguise")
      return session.script_disguise
    end,
  }

  runner:reload()
  return runner
end

function ArenaScriptRunner:reload()
  if not self.enabled then
    self.module = nil
    return false
  end

  local chunk, load_err = loadfile(self.path)
  if not chunk then
    if self.logger then
      self.logger:warn("arena script load failed", {
        error = load_err or "unknown",
        path = self.path,
      })
    end
    self.module = nil
    return false
  end

  local ok, script = pcall(chunk)
  if not ok or type(script) ~= "table" then
    if self.logger then
      self.logger:warn("arena script init failed", {
        error = ok and "script must return table" or tostring(script),
        path = self.path,
      })
    end
    self.module = nil
    return false
  end

  self.module = script
  if self.logger then
    self.logger:info("arena script loaded", { path = self.path })
  end
  return true
end

function ArenaScriptRunner:is_proxy_session(session)
  return session ~= nil and session.script_npc_proxy_enabled == true
end

function ArenaScriptRunner:sync_npc_proxy(session, previous_position)
  if not session or not session.connected then
    return false
  end
  if not self.world then
    return false
  end
  if not self:is_proxy_session(session) then
    return false
  end

  local disguise = active_disguise(session)
  local npc_id = clamp_int(disguise and disguise.npc_id, 0, 64008)
  if npc_id <= 0 then
    self:disable_npc_proxy(session, "proxy_without_npc")
    return false
  end

  local npc, created, removed = self.world:upsert_runtime_npc_for_owner(session.id, {
    map_id = session.map_id,
    npc_id = npc_id,
    x = session.x,
    y = session.y,
    direction = session.direction,
  })
  if not npc then
    return false
  end

  if removed then
    local remove_packet = build_npc_despawn_packet(removed)
    push_packet_near_origin(self.world, {
      map_id = removed.map_id,
      x = removed.x,
      y = removed.y,
    }, remove_packet, nil, session.id)
  end

  if created then
    local spawn_packet = build_npc_agree_packet(npc)
    push_packet_near_origin(self.world, point_from_session(session), spawn_packet, nil, session.id)
    return true
  end

  local move_packet = build_npc_position_packet(npc)
  local origin = previous_position or point_from_session(session)
  origin.map_id = clamp_int(origin.map_id, 0, 64008)
  origin.x = clamp_int(origin.x, 0, 252)
  origin.y = clamp_int(origin.y, 0, 252)
  push_packet_near_origin(self.world, origin, move_packet, nil, session.id)
  return true
end

function ArenaScriptRunner:disable_npc_proxy(session, reason)
  if not session or not self.world then
    return false
  end

  local removed = self.world:remove_runtime_npc_for_owner(session.id)
  session.script_npc_proxy_enabled = nil
  session.script_npc_proxy_npc_id = nil

  if session.script_force_invisible == true then
    session.invisible = nil
    session.script_force_invisible = nil
  end

  if not removed then
    return false
  end

  local remove_packet = build_npc_despawn_packet(removed)
  push_packet_near_origin(self.world, {
    map_id = removed.map_id,
    x = removed.x,
    y = removed.y,
  }, remove_packet, nil, session.id)

  if self.logger then
    self.logger:info("arena script npc proxy removed", {
      player_id = session.id or 0,
      reason = reason or "unknown",
    })
  end

  return true
end

function ArenaScriptRunner:clear_session_proxy(session, reason)
  if not session then
    return false
  end
  return self:disable_npc_proxy(session, reason or "session_clear")
end

function ArenaScriptRunner:sync_gold_packet(session, previous_amount, next_amount)
  if not session or not session.connected or not session.address then
    return false
  end
  if not self.world then
    return false
  end

  local before = clamp_int(previous_amount or 0, 0, MAX_INT4)
  local after = clamp_int(next_amount or 0, 0, MAX_INT4)
  local delta = after - before
  local gold_item_id = clamp_int(InventoryState.GOLD_ITEM_ID or 1, 1, 64008)

  if delta > 0 then
    local remaining = delta
    while remaining > 0 do
      local chunk = math.min(remaining, MAX_INT3)
      local packet = build_item_get_packet(self, session, gold_item_id, chunk)
      self.world:push_pending(session.address, packet)
      remaining = remaining - chunk
    end
    return true
  end

  if delta < 0 then
    local packet = build_item_kick_packet(self, session, gold_item_id, after)
    self.world:push_pending(session.address, packet)
    return true
  end

  return false
end

function ArenaScriptRunner:refresh_character(session, reason, force_full_refresh)
  if not session or not session.connected then
    return false
  end
  if not self.world or not self.accounts then
    return false
  end

  local character_id = tonumber(session.character_id) or 0
  if character_id <= 0 then
    return false
  end

  local character = self.accounts:get_character(session.account, character_id)
  if not character then
    return false
  end

  local disguise = active_disguise(session)
  local full_refresh = force_full_refresh == true or disguise_requires_full_refresh(disguise)
  local use_npc_proxy = self:is_proxy_session(session)
    and disguise ~= nil
    and tonumber(disguise.npc_id) ~= nil
    and tonumber(disguise.npc_id) > 0

  if not use_npc_proxy and session.script_npc_proxy_enabled == true then
    self:disable_npc_proxy(session, "missing_disguise")
    full_refresh = true
  end

  if use_npc_proxy then
    session.script_force_invisible = true
    session.invisible = true
    self.world:broadcast_remove_from(point_from_session(session), session.id)
    self:sync_npc_proxy(session)
  elseif full_refresh then
    self.world:broadcast_remove_from(point_from_session(session), session.id)

    local packet = Packet.new(Family.Players, Action.Agree)
    Nearby.add_nearby_info(packet, { { session = session, character = character } })
    self.world:broadcast_near(session, packet)
  else
    local packet = Packet.new(Family.Avatar, Action.Agree)
    add_avatar_hair_change(packet, session, character, disguise)
    self.world:broadcast_near(session, packet)
  end

  if not use_npc_proxy then
    local self_packet = Packet.new(Family.Players, Action.Agree)
    Nearby.add_nearby_info(self_packet, { { session = session, character = character } })
    if session.address then
      self.world:push_pending(session.address, self_packet)
    end
  end

  if self.logger then
    self.logger:info("arena script appearance refresh", {
      full_refresh = full_refresh,
      npc_proxy = use_npc_proxy,
      player_id = session.id or 0,
      reason = reason or "unknown",
    })
  end

  return true
end

function ArenaScriptRunner:tick()
  if not self.enabled then
    return
  end
  if not self.world then
    return
  end

  local now = os.time()
  for _, session in pairs(self.world.sessions) do
    local disguise = session and session.script_disguise or nil
    if disguise then
      local expires_at = tonumber(disguise.expires_at) or 0
      if expires_at > 0 and now >= expires_at then
        local force_full_refresh = session.script_disguise_full_refresh == true
          or session.script_npc_proxy_enabled == true
        self:disable_npc_proxy(session, "expired")
        session.script_disguise = nil
        session.script_disguise_full_refresh = nil
        self:refresh_character(session, "expired", force_full_refresh)
      end
    end
  end

  local orphan_owner_ids = {}
  for owner_id in pairs(self.world.runtime_npc_owners or {}) do
    local owner = self.world.sessions[owner_id]
    if not owner or not owner.connected or owner.script_npc_proxy_enabled ~= true then
      orphan_owner_ids[#orphan_owner_ids + 1] = owner_id
    end
  end

  for _, owner_id in ipairs(orphan_owner_ids) do
    local removed = self.world:remove_runtime_npc_for_owner(owner_id)
    if removed then
      local remove_packet = build_npc_despawn_packet(removed)
      push_packet_near_origin(self.world, {
        map_id = removed.map_id,
        x = removed.x,
        y = removed.y,
      }, remove_packet, nil)
    end
  end
end

function ArenaScriptRunner:run(hook_name, context)
  if not self.enabled then
    return
  end
  local script = self.module
  if type(script) ~= "table" then
    return
  end
  local hook = script[hook_name]
  if type(hook) ~= "function" then
    return
  end

  local ok, err = pcall(hook, self.api, context or {})
  if not ok and self.logger then
    self.logger:warn("arena script hook failed", {
      error = tostring(err),
      hook = hook_name,
      path = self.path,
    })
  end
end

return ArenaScriptRunner
