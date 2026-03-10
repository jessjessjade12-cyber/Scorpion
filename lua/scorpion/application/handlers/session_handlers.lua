local ArenaHandlers = require("scorpion.application.handlers.arena_handlers")
local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local util = require("scorpion.util")
local clamp = util.clamp

local Family = Protocol.Family
local Action = Protocol.Action
local LoginReply = Protocol.LoginReply
local RequiredVersion = { 0, 0, 28 }
local ReplyContinue = 1000
local ReplyStrOK = "OK"
local ReplyStrNO = "NO"

local AccountReply = {
  AlreadyExists = 1,
  NotApproved = 2,
  Created = 3,
  ChangeFailed = 5,
  Changed = 6,
}

local CharacterReply = {
  AlreadyExists = 1,
  Full = 2,
  NotApproved = 4,
  OK = 5,
  Deleted = 6,
}

local MaxCreateSex = 1
local MaxCreateHairStyle = 20
local MaxCreateHairColour = 9
local MaxCreateRace = 3
local FileIDMap = 1
local FileIDItem = 2
local FileIDMob = 3
local FileIDSkill = 4
local FileIDClass = 5

local function auth_client(auth)
  auth = auth + 1
  local result = ((auth % 11) + 1) * 119
  if result == 0 then
    return 0
  end
  return 110905 + ((auth % 9) + 1) * ((11092004 - auth) % result) * 119 + (auth % 2004)
end

local function load_character_location(session, character)
  session.character_id = character.id
  session.character = character.name
  session.map_id = character.map_id
  session.x = character.x
  session.y = character.y
  session.direction = character.direction
end

local function valid_account_name(name)
  if #name < 4 or #name > 20 then return false end
  return name:find("[^%da-z]") == nil
end

local function valid_character_name(name)
  if #name < 4 or #name > 12 then return false end
  return name:find("[^a-z]") == nil
end

local SessionHandlers = {}
SessionHandlers.__index = SessionHandlers

function SessionHandlers.new(deps)
  return setmetatable({
    accounts = deps.accounts,
    arena = ArenaHandlers.new({
      settings = deps.settings,
      world = deps.world,
    }),
    logger = deps.logger,
    settings = deps.settings,
    world = deps.world,
  }, SessionHandlers)
end

function SessionHandlers:trace(level, message, fields)
  if not self.logger then return end
  if level == "error" then
    self.logger:error(message, fields)
  elseif level == "warn" then
    self.logger:warn(message, fields)
  else
    self.logger:info(message, fields)
  end
end

function SessionHandlers:get_session(context)
  if not context then return nil end
  if context.session_id ~= nil then
    return self.world.sessions[context.session_id]
  end
  if context.address ~= nil then
    return self.world:find_session_by_address(context.address)
  end
  return nil
end

function SessionHandlers:max_characters()
  return ((self.settings.account or {}).max_characters or 3)
end

function SessionHandlers:apply_arena_only_location(session)
  local arena = self.settings.arena or {}
  if not arena.only then
    return
  end

  local target_map = arena.map or ((self.settings.new_character or {}).spawn_map) or session.map_id
  if session.map_id == target_map then
    return
  end

  local spawn = self.settings.new_character or {}
  local x = spawn.spawn_x or session.x
  local y = spawn.spawn_y or session.y

  local first_spawn = (arena.spawns or {})[1]
  if first_spawn and first_spawn.from then
    x = first_spawn.from.x
    y = first_spawn.from.y
  end

  session.map_id = target_map
  session.x = x
  session.y = y
  session.direction = spawn.spawn_direction or session.direction
end

function SessionHandlers:apply_map_relog_location(session)
  local relog = self.world:get_map_relog(session.map_id)
  if not relog then
    return
  end

  session.x = relog.x
  session.y = relog.y
end

function SessionHandlers:get_pub_blob(key)
  return ((self.world.pub or {}).client or {})[key]
end

function SessionHandlers:add_rid(reply, data)
  if data == nil or #data < 7 then
    reply:add_byte(0) reply:add_byte(0) reply:add_byte(0) reply:add_byte(0)
    return
  end
  reply:add_byte(data:byte(4))
  reply:add_byte(data:byte(5))
  reply:add_byte(data:byte(6))
  reply:add_byte(data:byte(7))
end

function SessionHandlers:add_pub_meta(reply, blob)
  local data = blob and blob.data or nil
  self:add_rid(reply, data)
  if data == nil or #data < 9 then
    reply:add_byte(0) reply:add_byte(0)
    return
  end
  reply:add_byte(data:byte(8))
  reply:add_byte(data:byte(9))
end

-- Encode a CharacterMapInfo entry into reply.
-- Caller is responsible for the trailing 0xFF break after this.
function SessionHandlers:add_character_map_info(reply, session, character)
  local map_id = clamp(tonumber(session.map_id) or 0, 0, 64008)
  local x = clamp(tonumber(session.x) or 0, 0, 64008)
  local y = clamp(tonumber(session.y) or 0, 0, 64008)
  local direction = clamp(tonumber(session.direction) or 0, 0, 3)
  local level = clamp(tonumber(character.level) or 0, 0, 252)
  local gender = clamp(tonumber(character.sex) or 0, 0, 1)
  local hair_style = clamp(tonumber(character.hair_style) or 1, 0, 252)
  local hair_color = clamp(tonumber(character.hair_color) or 0, 0, 252)
  local skin = clamp(tonumber(character.race) or 0, 0, 252)
  local sit_state = clamp(tonumber(session.sit_state) or 0, 0, 2)
  local invisible = (session.invisible and 1) or 0

  reply:add_break_string(character.name)       -- name + 0xFF
  reply:add_int2(session.id)                   -- player_id (short)
  reply:add_int2(map_id)                       -- map_id (short)
  reply:add_int2(x)                            -- coords.x (BigCoords, short)
  reply:add_int2(y)                            -- coords.y (BigCoords, short)
  reply:add_int1(direction)                    -- direction
  reply:add_int1(0)                            -- class_id
  reply:add_string("   ")                      -- guild_tag (fixed 3 chars)
  reply:add_int1(level)                        -- level
  reply:add_int1(gender)                       -- gender
  reply:add_int1(hair_style)                   -- hair_style
  reply:add_int1(hair_color)                   -- hair_color
  reply:add_int1(skin)                         -- skin
  reply:add_int2(10)                           -- max_hp
  reply:add_int2(10)                           -- hp
  reply:add_int2(1)                            -- max_tp
  reply:add_int2(1)                            -- tp
  -- EquipmentMapInfo: boots, pad x3, armor, pad, hat, shield, weapon (9 shorts)
  for _ = 1, 9 do reply:add_int2(0) end
  reply:add_int1(sit_state)                    -- sit_state
  reply:add_int1(invisible)                    -- invisible (visible = 0)
end

-- Return {session, character} pairs for all connected characters within range
-- on the same map, always including self.
function SessionHandlers:get_nearby_sessions(center_session)
  local result = {}
  for _, session in pairs(self.world.sessions) do
    if session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
      and (session.id == center_session.id or self.world:in_client_range(center_session, session))
    then
      local character = self.accounts:get_character(session.account, session.character_id)
      if character then
        result[#result + 1] = { session = session, character = character }
      end
    end
  end
  return result
end

-- Write NearbyInfo (characters + empty NPCs + empty items) into reply.
function SessionHandlers:add_nearby_info(reply, nearby)
  reply:add_int1(#nearby)   -- character count
  reply:add_byte(255)       -- break (opens char section)
  for _, entry in ipairs(nearby) do
    self:add_character_map_info(reply, entry.session, entry.character)
    reply:add_byte(255)     -- break after each character
  end
  reply:add_byte(255)       -- NPC section terminator (0 NPCs)
  -- 0 items on map; no trailing break needed
end

function SessionHandlers:get_requested_nearby_sessions(center_session, player_ids)
  if #player_ids == 0 then
    return {}
  end

  local requested = {}
  local wanted = {}
  for _, id in ipairs(player_ids) do
    wanted[id] = true
  end

  for _, session in pairs(self.world.sessions) do
    if wanted[session.id]
      and session.connected
      and session.pending_warp == nil
      and (session.character_id and session.character_id > 0)
      and session.map_id == center_session.map_id
    then
      if session.id == center_session.id or self.world:in_client_range(center_session, session) then
        local character = self.accounts:get_character(session.account, session.character_id)
        if character then
          requested[#requested + 1] = { session = session, character = character }
        end
      end
    end
  end

  return requested
end

function SessionHandlers:parse_player_ids(packet)
  local player_ids = {}
  while #packet.data >= 2 do
    player_ids[#player_ids + 1] = packet:get_int2()
  end
  return player_ids
end

function SessionHandlers:parse_range_request(packet)
  local player_ids = {}

  while #packet.data > 0 and packet.data:byte(1) ~= 255 do
    if #packet.data < 2 then
      break
    end
    player_ids[#player_ids + 1] = packet:get_int2()
  end

  return player_ids
end

function SessionHandlers:broadcast_all(packet, exclude_session)
  for _, session in pairs(self.world.sessions) do
    if session.connected and (exclude_session == nil or session.id ~= exclude_session.id) then
      self.world:push_pending(session.address, packet)
    end
  end
end

function SessionHandlers:find_session_by_character_name(name)
  local wanted = string.lower(name or "")
  if wanted == "" then
    return nil, nil
  end

  for _, session in pairs(self.world.sessions) do
    if session.connected and (session.character_id and session.character_id > 0) then
      local character = self.accounts:get_character(session.account, session.character_id)
      if character and string.lower(character.name or "") == wanted then
        return session, character
      end
    end
  end

  return nil, nil
end

function SessionHandlers:send_gamedata_blob(file_id, packet)
  local reply = Packet.new(Family.Raw, Action.Raw)
  reply.force_raw = true

  if file_id == FileIDMap then
    packet:discard(2)
    local map_id = packet:get_int2()
    local map = self.world.maps[map_id]
    if map == nil or map.data == nil then
      return nil, ("request for invalid map #%d"):format(map_id)
    end
    reply:add_int1(4)
    reply:add_string(map.data)
    return reply
  end

  local pub_configs = {
    [FileIDItem]  = { key = "eif", id = 5  },
    [FileIDMob]   = { key = "enf", id = 6  },
    [FileIDSkill] = { key = "esf", id = 7  },
    [FileIDClass] = { key = "ecf", id = 11 },
  }

  local cfg = pub_configs[file_id]
  if cfg then
    local blob = self:get_pub_blob(cfg.key)
    if blob == nil or blob.data == nil then
      return nil, (cfg.key .. " pub missing")
    end
    reply:add_int1(cfg.id)
    reply:add_int1(1)
    reply:add_string(blob.data)
    return reply
  end

  return nil, ("unknown game data request %d"):format(file_id)
end

function SessionHandlers:build_characters_packet(packet, username)
  local characters = self.accounts:list_characters(username)
  packet:add_int1(#characters)
  packet:add_byte(1)
  packet:add_byte(255)
  for _, character in ipairs(characters) do
    packet:add_break_string(character.name)
    packet:add_int4(character.id)
    packet:add_int1(character.level or 0)
    packet:add_int1(character.sex or 0)
    packet:add_int1(character.hair_style or 1)
    packet:add_int1(character.hair_color or 0)
    packet:add_int1(character.race or 0)
    packet:add_int1(character.admin or 0)
    packet:add_int2(0) packet:add_int2(0) packet:add_int2(0)
    packet:add_int2(0) packet:add_int2(0)
    packet:add_byte(255)
  end
end

function SessionHandlers:register(router)
  local map = {
    { family = Family.Raw,        name = "HandleRaw"        },
    { family = Family.Connection, name = "HandleConnection"  },
    { family = Family.Account,    name = "HandleAccount"     },
    { family = Family.Character,  name = "HandleCharacter"   },
    { family = Family.Login,      name = "HandleLogin"       },
    { family = Family.GameData,   name = "HandleGameData"    },
    { family = Family.Walk,       name = "HandleWalk"        },
    { family = Family.PlayerRange,name = "HandlePlayerRange" },
    { family = Family.NpcRange,   name = "HandleNpcRange"    },
    { family = Family.Range,      name = "HandleRange"       },
    { family = Family.Face,       name = "HandleFace"        },
    { family = Family.Talk,       name = "HandleTalk"        },
    { family = Family.Sit,        name = "HandleUnimplemented" },
    { family = Family.Warp,       name = "HandleWarp"          },
    { family = Family.Message,    name = "HandleMessage"        },
    { family = Family.Paperdoll,  name = "HandleUnimplemented" },
    { family = Family.Players,    name = "HandleUnimplemented" },
    { family = Family.Door,       name = "HandleUnimplemented" },
    { family = Family.Emote,      name = "HandleUnimplemented" },
    { family = Family.Chair,      name = "HandleUnimplemented" },
    { family = Family.Item,       name = "HandleUnimplemented" },
    { family = Family.Locker,     name = "HandleUnimplemented" },
    { family = Family.Attack,     name = "HandleAttack"        },
    { family = Family.Refresh,    name = "HandleRefresh"       },
    { family = Family.Skill,      name = "HandleUnimplemented" },
    { family = Family.Barber,     name = "HandleUnimplemented" },
    { family = Family.Bank,       name = "HandleUnimplemented" },
  }

  router:set_default(function(packet, context)
    return self:DefaultHandler(packet, context)
  end)

  for _, item in ipairs(map) do
    local family = item.family
    local method = item.name
    router:register(family, function(packet, context)
      return self[method](self, packet, context)
    end)
  end
end

function SessionHandlers:DefaultHandler(packet, _context)
  self:trace("warn", "unhandled packet family", {
    address = _context and _context.address or "unknown",
    family = packet.family,
    action = packet.action,
  })
  return true
end

function SessionHandlers:HandleRaw(packet, _context)
  if packet.action ~= Action.Raw then
    return nil, ("unhandled raw action %d"):format(packet.action)
  end

  local auth = packet:get_int3()
  local v1 = packet:get_int1()
  local v2 = packet:get_int1()
  local v3 = packet:get_int1()

  local reply = Packet.new(Family.Raw, Action.Raw)
  if v1 < RequiredVersion[1] or v2 < RequiredVersion[2] or v3 < RequiredVersion[3] then
    self:trace("warn", "raw rejected version", {
      address = _context and _context.address or "unknown",
      version = ("%d.%d.%d"):format(v1, v2, v3),
    })
    reply:add_byte(1)
    reply:add_byte(RequiredVersion[1] + 1)
    reply:add_byte(RequiredVersion[2] + 1)
    reply:add_byte(RequiredVersion[3] + 1)
    return reply
  end

  _context.sequence_start = math.random(1, 220)
  _context.sequence_last = _context.sequence_start + 4
  _context.sequence_count = 0
  _context.ping_replied = true

  local s1 = math.floor((_context.sequence_start + 12) / 7)
  local s2 = (_context.sequence_start + 5) % 7

  reply:add_byte(2)
  reply:add_byte(s1)
  reply:add_byte(s2)
  reply:add_byte(_context.send_key)
  reply:add_byte(_context.receive_key)
  reply:add_int2(_context.connection_id or 1)
  reply:add_int3(auth_client(auth))

  _context.initialized = true
  _context.raw = true
  self:trace("info", "raw accepted", {
    address = _context and _context.address or "unknown",
    connection_id = _context.connection_id or 1,
  })
  return reply
end

function SessionHandlers:HandleConnection(packet, _context)
  if packet.action == Action.Ping then
    _context.ping_replied = true
  end
  return true
end

function SessionHandlers:HandleAccount(packet, _context)
  if packet.action == Action.Accept then
    self:trace("info", "account accept", {
      address = _context and _context.address or "unknown",
    })
    local accepted = Packet.new(Family.Account, Action.Accept)
    accepted:add_int2(1)
    return accepted
  end

  local reply = Packet.new(Family.Account, Action.Reply)

  if packet.action == Action.Request then
    local account_name = string.lower(packet:get_break_string())
    self:trace("info", "account request", {
      address = _context and _context.address or "unknown",
      username = account_name,
    })

    if not valid_account_name(account_name) then
      self:trace("warn", "account request rejected", { reason = "invalid_name", username = account_name })
      reply:add_int2(AccountReply.NotApproved)
      reply:add_string(ReplyStrNO)
    elseif self.accounts:account_exists(account_name) then
      self:trace("warn", "account request rejected", { reason = "already_exists", username = account_name })
      reply:add_int2(AccountReply.AlreadyExists)
      reply:add_string(ReplyStrNO)
    else
      self:trace("info", "account request accepted", { username = account_name })
      reply:add_int2(ReplyContinue)
      reply:add_string(ReplyStrOK)
    end
    return reply
  end

  if packet.action == Action.Create then
    local raw = packet.data
    local function parse_create(skip)
      local p = Packet.new(Family.Account, Action.Create, raw)
      p:discard(skip)
      local name = string.lower(p:get_break_string())
      local pass = p:get_break_string()
      for _ = 1, 5 do p:get_break_string() end
      return name, pass
    end

    self:trace("info", "account create", {
      address = _context and _context.address or "unknown",
      bytes = #raw,
    })

    local account_name, password = parse_create(3)
    local parse_mode = 3
    if not valid_account_name(account_name) then
      local fallback_name, fallback_password = parse_create(2)
      if valid_account_name(fallback_name) then
        account_name = fallback_name
        password = fallback_password
        parse_mode = 2
      end
    end

    self:trace("info", "account create parse", { mode = parse_mode, username = account_name })

    if not valid_account_name(account_name) then
      self:trace("warn", "account create rejected", { reason = "invalid_name", username = account_name })
      reply:add_int2(AccountReply.NotApproved)
      reply:add_string(ReplyStrNO)
      return reply
    end

    if self.accounts:account_exists(account_name) then
      self:trace("warn", "account create rejected", { reason = "already_exists", username = account_name })
      reply:add_int2(AccountReply.AlreadyExists)
      reply:add_string(ReplyStrNO)
      return reply
    end

    local created = self.accounts:create_account(account_name, password)
    if not created then
      self:trace("warn", "account create rejected", { reason = "create_failed", username = account_name })
      reply:add_int2(AccountReply.ChangeFailed)
      reply:add_string(ReplyStrNO)
      return reply
    end

    self:trace("info", "account create success", { username = account_name })
    reply:add_int2(AccountReply.Created)
    reply:add_string(ReplyStrOK)
    return reply
  end

  if packet.action == Action.Agree then
    self:trace("warn", "account agree unsupported", { address = _context and _context.address or "unknown" })
    reply:add_int2(AccountReply.ChangeFailed)
    reply:add_string(ReplyStrNO)
    return reply
  end

  return nil, ("unhandled account action %d"):format(packet.action)
end

function SessionHandlers:HandleCharacter(packet, _context)
  local session = self:get_session(_context)
  if not session then
    self:trace("warn", "character packet rejected", {
      action = packet.action,
      address = _context and _context.address or "unknown",
      reason = "before_login",
    })
    return nil, "character before login"
  end

  local reply = Packet.new(Family.Character, Action.Reply)

  if packet.action == Action.Request then
    if self.accounts:character_count(session.account) >= self:max_characters() then
      reply:add_int2(CharacterReply.Full)
      reply:add_string(ReplyStrNO)
    else
      reply:add_int2(ReplyContinue)
      reply:add_string(ReplyStrOK)
    end
    return reply
  end

  if packet.action == Action.Create then
    packet:discard(2)
    local sex = clamp(packet:get_int2(), 0, MaxCreateSex)
    local hair_style = clamp(packet:get_int2(), 1, MaxCreateHairStyle)
    local hair_color = clamp(packet:get_int2(), 0, MaxCreateHairColour)
    local race = clamp(packet:get_int2(), 0, MaxCreateRace)
    packet:discard()
    local name = string.lower(packet:get_break_string())
    self:trace("info", "character create", { account = session.account, name = name })

    if not valid_character_name(name) then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "invalid_name" })
      reply:add_int2(CharacterReply.NotApproved)
      return reply
    end

    if self.accounts:character_exists(name) then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "already_exists" })
      reply:add_int2(CharacterReply.AlreadyExists)
      return reply
    end

    if self.accounts:character_count(session.account) >= self:max_characters() then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "full" })
      reply:add_int2(CharacterReply.Full)
      return reply
    end

    local character = self.accounts:create_character(session.account, {
      hair_color = hair_color,
      hair_style = hair_style,
      race = race,
      sex = sex,
      name = name,
    })

    if not character then
      self:trace("warn", "character create rejected", { account = session.account, name = name, reason = "create_failed" })
      reply:add_int2(CharacterReply.NotApproved)
      return reply
    end

    self:trace("info", "character create success", { account = session.account, name = name, id = character.id })
    reply:add_int2(CharacterReply.OK)
    self:build_characters_packet(reply, session.account)
    return reply
  end

  if packet.action == Action.Remove then
    packet:discard(2)
    local character_id = packet:get_int4()
    local ok = self.accounts:remove_character(session.account, character_id)
    if not ok then
      return nil, "invalid delete id"
    end
    if session.character_id == character_id then
      session.character_id = 0
      session.character = nil
      session.map_id = 0
      session.x = 0
      session.y = 0
      session.direction = 0
    end
    reply:add_int2(CharacterReply.Deleted)
    self:build_characters_packet(reply, session.account)
    return reply
  end

  if packet.action == Action.Take then
    local character_id = packet:get_int4()
    local character = self.accounts:get_character(session.account, character_id)
    if not character then
      return nil, "invalid character id"
    end
    load_character_location(session, character)
    self:apply_arena_only_location(session)
    local take = Packet.new(Family.Character, Action.Player)
    take:add_int2(ReplyContinue)
    take:add_int4(character.id)
    return take
  end

  return nil, ("unhandled character action %d"):format(packet.action)
end

function SessionHandlers:HandleLogin(packet, context)
  if packet.action ~= Action.Request then
    return nil, ("unhandled login action %d"):format(packet.action)
  end

  local username = string.lower(packet:get_break_string())
  local password = packet:get_break_string()
  self:trace("info", "login request", {
    address = context and context.address or "unknown",
    username = username,
  })

  local reply = Packet.new(Family.Login, Action.Reply)
  local account = self.accounts:find(username)

  if account == nil then
    self:trace("warn", "login rejected", { username = username, reason = "unknown_user" })
    reply:add_int2(LoginReply.UnknownUser)
    return reply
  end

  if account.password ~= password then
    self:trace("warn", "login rejected", { username = username, reason = "wrong_password" })
    reply:add_int2(LoginReply.WrongPassword)
    return reply
  end

  if self.world:find_session_by_account(username) ~= nil then
    self:trace("warn", "login rejected", { username = username, reason = "already_logged_in" })
    reply:add_int2(LoginReply.AlreadyLoggedIn)
    return reply
  end

  local session = self.world:create_session((context and context.address) or "unknown", username)
  if context then
    context.session_id = session.id
  end

  reply:add_int2(LoginReply.OK)
  self:build_characters_packet(reply, username)
  self:trace("info", "login success", { username = username, session_id = session.id })
  return reply
end

function SessionHandlers:HandleGameData(packet, _context)
  local session = self:get_session(_context)
  if not session then
    return nil, "gamedata before login"
  end

  if packet.action == Action.Request then
    local requested_id = packet:get_int4()
    if requested_id > 0 then
      local character = self.accounts:get_character(session.account, requested_id)
      if character then
        load_character_location(session, character)
        self:apply_arena_only_location(session)
      end
    end

    local map = self.world.maps[session.map_id]
    if map == nil or map.data == nil then
      return nil, ("request for invalid map #%d"):format(session.map_id)
    end

    local character = self.accounts:get_character(session.account, session.character_id or 0)
    local character_id = (character and character.id) or session.id

    local reply = Packet.new(Family.GameData, Action.Reply)
    reply:add_int2(1)                          -- WelcomeCode::SelectCharacter
    reply:add_int2(session.id)
    reply:add_int4(character_id)
    reply:add_int2(session.map_id)
    self:add_rid(reply, map.data)
    reply:add_int3(#map.data)
    self:add_pub_meta(reply, self:get_pub_blob("eif"))
    self:add_pub_meta(reply, self:get_pub_blob("enf"))
    self:add_pub_meta(reply, self:get_pub_blob("esf"))
    self:add_pub_meta(reply, self:get_pub_blob("ecf"))

    -- Character info strings
    reply:add_break_string((character and character.name) or (session.character or ""))
    reply:add_break_string("") -- title
    reply:add_break_string("") -- guild name
    reply:add_break_string("") -- guild rank name
    reply:add_int1(1)          -- class_id
    reply:add_string("   ")    -- guild_tag

    -- Stats
    reply:add_int1((character and character.admin) or 0)
    reply:add_int1((character and character.level) or 0)
    reply:add_int4(0)          -- experience
    reply:add_int4(0)          -- usage (minutes)
    -- CharacterStatsWelcome: hp, max_hp, tp, max_tp, max_sp, stat_points, skill_points, karma (8 shorts)
    reply:add_int2(10) reply:add_int2(10) -- hp / max_hp
    reply:add_int2(10) reply:add_int2(10) -- tp / max_tp
    reply:add_int2(10) reply:add_int2(0)  -- max_sp / stat_points
    reply:add_int2(0)  reply:add_int2(1000) -- skill_points / karma
    -- CharacterSecondaryStats (min_damage, max_damage, accuracy, evade, armor)
    reply:add_int2(0) reply:add_int2(0) reply:add_int2(0) reply:add_int2(0) reply:add_int2(0)
    -- CharacterBaseStatsWelcome (str, intl, wis, agi, con, cha)
    reply:add_int2(0) reply:add_int2(0) reply:add_int2(0)
    reply:add_int2(0) reply:add_int2(0) reply:add_int2(0)
    -- EquipmentWelcome: boots, accessory, gloves, belt, armor, necklace, hat, shield, weapon,
    --                   ring x2, armlet x2, bracer x2 (15 shorts, all 0 = no equipment)
    for _ = 1, 15 do reply:add_int2(0) end
    reply:add_int1(0)          -- guild_rank
    -- ServerSettings: light, animation, transition (3 chars) + music_on, sound_on (2 chars)
    reply:add_int1(4) reply:add_int1(24) reply:add_int1(24)
    reply:add_int2(10) reply:add_int2(10)
    reply:add_int2(1) reply:add_int2(1)
    reply:add_int1(0)          -- login_message_code
    reply:add_byte(255)
    return reply
  end

  if packet.action == Action.Agree then
    local file_id = packet:get_int1()
    self:trace("info", "gamedata agree", { account = session.account, file_id = file_id })
    local reply, err = self:send_gamedata_blob(file_id, packet)
    if not reply then
      self:trace("warn", "gamedata agree rejected", { account = session.account, file_id = file_id, reason = err or "unknown" })
      return nil, err
    end
    return reply
  end

  if packet.action == Action.Message then
    packet:discard(3)
    local character_id = packet:get_int4()
    if character_id > 0 then
      local character = self.accounts:get_character(session.account, character_id)
      if character then
        load_character_location(session, character)
      end
    end
    self:apply_arena_only_location(session)
    self:apply_map_relog_location(session)

    -- Notify existing nearby players that this player has entered
    if session.character_id and session.character_id > 0 then
      local character = self.accounts:get_character(session.account, session.character_id)
      if character then
        local appear = Packet.new(Family.Players, Action.Agree)
        self:add_nearby_info(appear, { { session = session, character = character } })
        self.world:broadcast_near(session, appear)
      end
    end

    local nearby = self:get_nearby_sessions(session)
    local reply = Packet.new(Family.GameData, Action.Reply)
    reply:add_int2(2)          -- WelcomeCode::EnterGame
    -- News: initial break + 9 strings each with break
    reply:add_byte(255)
    reply:add_break_string(self.settings.name or "Kalandra")
    for _ = 1, 8 do reply:add_break_string("") end
    -- Weight: current + max (both chars)
    reply:add_int1(0)
    reply:add_int1(100)
    reply:add_byte(255)        -- items section (empty)
    reply:add_byte(255)        -- spells section (empty)
    self:add_nearby_info(reply, nearby)
    return reply
  end

  return nil, ("unhandled gamedata action %d"):format(packet.action)
end

function SessionHandlers:HandleWalk(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "walk before login" end
  return self.arena:handle_walk(packet, session)
end

function SessionHandlers:HandlePlayerRange(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "player range before login" end
  if packet.action ~= Action.Request then return true end

  local player_ids = self:parse_player_ids(packet)
  local nearby = self:get_requested_nearby_sessions(session, player_ids)

  local reply = Packet.new(Family.Range, Action.Reply)
  self:add_nearby_info(reply, nearby)
  return reply
end

function SessionHandlers:HandleNpcRange(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "npc range before login" end
  if packet.action ~= Action.Request then return true end

  local reply = Packet.new(Family.Mob, Action.Agree)
  reply:add_int1(0) -- no NPCs in arena mode
  return reply
end

function SessionHandlers:HandleRange(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "range before login" end
  if packet.action ~= Action.Request then return true end

  local player_ids = self:parse_range_request(packet)
  local nearby = self:get_requested_nearby_sessions(session, player_ids)

  local reply = Packet.new(Family.Range, Action.Reply)
  self:add_nearby_info(reply, nearby)
  return reply
end

function SessionHandlers:HandleFace(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "face before login" end
  if packet.action ~= Action.Player then
    return nil, ("unhandled face action %d"):format(packet.action)
  end
  session.direction = clamp(packet:get_int1(), 0, 3)
  local broadcast = Packet.new(Family.Face, Action.Player)
  broadcast:add_int2(session.id)
  broadcast:add_int1(session.direction)
  self.world:broadcast_near(session, broadcast)
  return true
end

function SessionHandlers:HandleTalk(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "talk before login" end
  if not (session.character_id and session.character_id > 0) then return true end

  local sender = self.accounts:get_character(session.account, session.character_id)
  if not sender then return true end

  if packet.action == Action.Report or packet.action == Action.Player or packet.action == Action.Use then
    local text = packet:get_string()
    if #text == 0 then return true end
    local speak = Packet.new(Family.Talk, Action.Player)
    speak:add_int2(session.id)
    speak:add_string(text)
    self.world:broadcast_near(session, speak)
    return true
  end

  if packet.action == Action.Tell then
    local raw_target = packet:get_break_string()
    local target_name = string.lower(raw_target or "")
    local text = packet:get_string()
    if target_name == "" or #text == 0 then return true end

    local target_session = self:find_session_by_character_name(target_name)
    if not target_session then
      local not_found = Packet.new(Family.Talk, Action.Reply)
      not_found:add_int2(1) -- TalkReply::NotFound
      not_found:add_string(raw_target or target_name)
      return not_found
    end

    local tell = Packet.new(Family.Talk, Action.Tell)
    tell:add_break_string(sender.name or session.character or "")
    tell:add_break_string(text)
    self.world:push_pending(target_session.address, tell)
    return true
  end

  if packet.action == Action.Message then
    local text = packet:get_string()
    if #text == 0 then return true end
    local global = Packet.new(Family.Talk, Action.Message)
    global:add_break_string(sender.name or session.character or "")
    global:add_break_string(text)
    self:broadcast_all(global)
    return true
  end

  if packet.action == Action.Request then
    local text = packet:get_string()
    if #text == 0 then return true end
    local guild = Packet.new(Family.Talk, Action.Request)
    guild:add_break_string(sender.name or session.character or "")
    guild:add_break_string(text)
    self.world:broadcast_near(session, guild)
    return true
  end

  if packet.action == Action.Open then
    return true -- party chat not implemented yet
  end

  if packet.action == Action.Admin or packet.action == Action.Announce or packet.action == Action.Report then
    return true
  end

  return true
end

function SessionHandlers:HandleUnimplemented(_packet, _context)
  return true
end

function SessionHandlers:HandleWarp(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "warp before login" end

  if packet.action == Action.Accept then
    local map_id = packet:get_int2()
    local warp_session_id = packet:get_int2()
    local pending = session.pending_warp

    if pending ~= nil then
      if warp_session_id ~= pending.session_id then
        return nil, "invalid warp session"
      end
      if map_id ~= pending.map_id then
        return nil, "invalid warp map"
      end

      local old_position = {
        map_id = session.map_id,
        x = session.x,
        y = session.y,
      }
      if session.character_id and session.character_id > 0 then
        self.world:broadcast_remove_from(old_position, session.id)
      end

      session.map_id = pending.map_id
      session.x = pending.x
      session.y = pending.y
      session.direction = pending.direction or session.direction
      session.pending_warp = nil

      local self_character = self.accounts:get_character(session.account, session.character_id or 0)
      if self_character then
        local appear = Packet.new(Family.Players, Action.Agree)
        self:add_nearby_info(appear, { { session = session, character = self_character } })
        self.world:broadcast_near(session, appear)
      end

      local nearby = self:get_nearby_sessions(session)
      local reply = Packet.new(Family.Warp, Action.Agree)
      reply:add_int1(1) -- WarpType.Local
      self:add_nearby_info(reply, nearby)
      return reply
    end
  end

  if self.settings.arena.only and not self.arena:arena_only_map_allowed(session.map_id) then
    return nil, "arena map only"
  end
  return self.arena:handle_warp(packet, session)
end

function SessionHandlers:HandleMessage(packet, _context)
  if packet.action == Action.Ping then
    _context.ping_replied = true
  end
  return Packet.new(Family.Message, Action.Pong)
end

function SessionHandlers:HandleAttack(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "attack before login" end
  local ok, err = self.arena:handle_attack(packet, session)
  if not ok then
    return nil, err
  end

  return true
end

function SessionHandlers:HandleRefresh(packet, _context)
  local session = self:get_session(_context)
  if not session then return nil, "refresh before login" end
  if packet.action ~= Action.Request then return true end
  local nearby = self:get_nearby_sessions(session)
  local reply = Packet.new(Family.Refresh, Action.Reply)
  self:add_nearby_info(reply, nearby)
  return reply
end

return SessionHandlers
