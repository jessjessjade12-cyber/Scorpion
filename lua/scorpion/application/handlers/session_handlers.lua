local ArenaHandlers = require("scorpion.application.handlers.arena_handlers")
local CharacterList = require("scorpion.application.handlers.support.character_list")
local GameDataBlob = require("scorpion.application.handlers.support.gamedata_blob")
local Nearby = require("scorpion.application.handlers.support.nearby")
local Protocol = require("scorpion.transport.protocol")

local Family = Protocol.Family

local FamilyModules = {
  account = require("scorpion.application.handlers.families.account"),
  attack = require("scorpion.application.handlers.families.attack"),
  character = require("scorpion.application.handlers.families.character"),
  connection = require("scorpion.application.handlers.families.connection"),
  default = require("scorpion.application.handlers.families.default"),
  face = require("scorpion.application.handlers.families.face"),
  gamedata = require("scorpion.application.handlers.families.gamedata"),
  login = require("scorpion.application.handlers.families.login"),
  message = require("scorpion.application.handlers.families.message"),
  npc_range = require("scorpion.application.handlers.families.npc_range"),
  player_range = require("scorpion.application.handlers.families.player_range"),
  range = require("scorpion.application.handlers.families.range"),
  raw = require("scorpion.application.handlers.families.raw"),
  refresh = require("scorpion.application.handlers.families.refresh"),
  talk = require("scorpion.application.handlers.families.talk"),
  unimplemented = require("scorpion.application.handlers.families.unimplemented"),
  walk = require("scorpion.application.handlers.families.walk"),
  warp = require("scorpion.application.handlers.families.warp"),
}

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

function SessionHandlers:auth_client(auth)
  return auth_client(auth)
end

function SessionHandlers:load_character_location(session, character)
  return load_character_location(session, character)
end

function SessionHandlers:valid_account_name(name)
  return valid_account_name(name)
end

function SessionHandlers:valid_character_name(name)
  return valid_character_name(name)
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
  return Nearby.add_character_map_info(reply, session, character)
end

-- Return {session, character} pairs for all connected characters within range
-- on the same map, always including self.
function SessionHandlers:get_nearby_sessions(center_session)
  return Nearby.get_nearby_sessions(self.world, self.accounts, center_session)
end

-- Write NearbyInfo (characters + empty NPCs + empty items) into reply.
function SessionHandlers:add_nearby_info(reply, nearby)
  return Nearby.add_nearby_info(reply, nearby)
end

function SessionHandlers:get_requested_nearby_sessions(center_session, player_ids)
  return Nearby.get_requested_nearby_sessions(self.world, self.accounts, center_session, player_ids)
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
  return GameDataBlob.build(file_id, packet, {
    world = self.world,
    get_pub_blob = function(key)
      return self:get_pub_blob(key)
    end,
  })
end

function SessionHandlers:build_characters_packet(packet, username)
  local characters = self.accounts:list_characters(username)
  return CharacterList.append(packet, characters)
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

function SessionHandlers:DefaultHandler(packet, context)
  return FamilyModules.default.handle(self, packet, context)
end

function SessionHandlers:HandleRaw(packet, context)
  return FamilyModules.raw.handle(self, packet, context)
end

function SessionHandlers:HandleConnection(packet, context)
  return FamilyModules.connection.handle(self, packet, context)
end

function SessionHandlers:HandleAccount(packet, context)
  return FamilyModules.account.handle(self, packet, context)
end

function SessionHandlers:HandleCharacter(packet, context)
  return FamilyModules.character.handle(self, packet, context)
end

function SessionHandlers:HandleLogin(packet, context)
  return FamilyModules.login.handle(self, packet, context)
end

function SessionHandlers:HandleGameData(packet, context)
  return FamilyModules.gamedata.handle(self, packet, context)
end

function SessionHandlers:HandleWalk(packet, context)
  return FamilyModules.walk.handle(self, packet, context)
end

function SessionHandlers:HandlePlayerRange(packet, context)
  return FamilyModules.player_range.handle(self, packet, context)
end

function SessionHandlers:HandleNpcRange(packet, context)
  return FamilyModules.npc_range.handle(self, packet, context)
end

function SessionHandlers:HandleRange(packet, context)
  return FamilyModules.range.handle(self, packet, context)
end

function SessionHandlers:HandleFace(packet, context)
  return FamilyModules.face.handle(self, packet, context)
end

function SessionHandlers:HandleTalk(packet, context)
  return FamilyModules.talk.handle(self, packet, context)
end

function SessionHandlers:HandleUnimplemented(packet, context)
  return FamilyModules.unimplemented.handle(self, packet, context)
end

function SessionHandlers:HandleWarp(packet, context)
  return FamilyModules.warp.handle(self, packet, context)
end

function SessionHandlers:HandleMessage(packet, context)
  return FamilyModules.message.handle(self, packet, context)
end

function SessionHandlers:HandleAttack(packet, context)
  return FamilyModules.attack.handle(self, packet, context)
end

function SessionHandlers:HandleRefresh(packet, context)
  return FamilyModules.refresh.handle(self, packet, context)
end

return SessionHandlers
