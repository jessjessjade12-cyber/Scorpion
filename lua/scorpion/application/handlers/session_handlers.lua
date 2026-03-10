local ArenaHandlers = require("scorpion.application.handlers.arena_handlers")
local CharacterList = require("scorpion.application.handlers.support.character_list")
local Directory = require("scorpion.application.handlers.support.directory")
local GameDataBlob = require("scorpion.application.handlers.support.gamedata_blob")
local Identity = require("scorpion.application.handlers.support.identity")
local Location = require("scorpion.application.handlers.support.location")
local Nearby = require("scorpion.application.handlers.support.nearby")
local Pub = require("scorpion.application.handlers.support.pub")
local RangeParser = require("scorpion.application.handlers.support.range_parser")
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
  return Identity.auth_client(auth)
end

function SessionHandlers:load_character_location(session, character)
  return Identity.load_character_location(session, character)
end

function SessionHandlers:valid_account_name(name)
  return Identity.valid_account_name(name)
end

function SessionHandlers:valid_character_name(name)
  return Identity.valid_character_name(name)
end

function SessionHandlers:apply_arena_only_location(session)
  return Location.apply_arena_only_location(self.settings, session)
end

function SessionHandlers:apply_map_relog_location(session)
  return Location.apply_map_relog_location(self.world, session)
end

function SessionHandlers:get_pub_blob(key)
  return Pub.get_blob(self.world, key)
end

function SessionHandlers:add_rid(reply, data)
  return Pub.add_rid(reply, data)
end

function SessionHandlers:add_pub_meta(reply, blob)
  return Pub.add_meta(reply, blob)
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
  return RangeParser.parse_player_ids(packet)
end

function SessionHandlers:parse_range_request(packet)
  return RangeParser.parse_range_request(packet)
end

function SessionHandlers:broadcast_all(packet, exclude_session)
  return Directory.broadcast_all(self.world, packet, exclude_session)
end

function SessionHandlers:find_session_by_character_name(name)
  return Directory.find_session_by_character_name(self.world, self.accounts, name)
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
