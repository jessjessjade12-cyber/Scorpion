local ArenaScriptRunner = {}
ArenaScriptRunner.__index = ArenaScriptRunner

local Nearby = require("scorpion.application.handlers.support.nearby")
local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family
local Action = Protocol.Action

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
        session.script_disguise = nil
        runner:refresh_character(session, "clear_disguise")
      end
    end,
    -- Applies a temporary appearance override using only provided fields.
    -- Unspecified fields keep the character's current appearance.
    temporarily_override_appearance = function(session, opts)
      if not session then
        return nil
      end

      opts = opts or {}
      local limits = resolve_appearance_limits(runner.settings)
      local seconds = math.max(
        1,
        math.floor(tonumber(opts.seconds) or tonumber(runner.settings.loser_duration_seconds) or 3)
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
        math.floor(tonumber(opts.seconds) or tonumber(runner.settings.loser_duration_seconds) or 3)
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

function ArenaScriptRunner:refresh_character(session, reason)
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

  local packet = Packet.new(Family.Players, Action.Agree)
  Nearby.add_nearby_info(packet, { { session = session, character = character } })

  self.world:broadcast_near(session, packet)
  if session.address then
    self.world:push_pending(session.address, packet)
  end

  if self.logger then
    self.logger:info("arena script appearance refresh", {
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
        session.script_disguise = nil
        self:refresh_character(session, "expired")
      end
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
