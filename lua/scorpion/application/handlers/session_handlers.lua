local ArenaHandlers = require("scorpion.application.handlers.arena_handlers")
local MovementHandlers = require("scorpion.application.handlers.movement_handlers")
local CharacterList = require("scorpion.application.handlers.support.character_list")
local GameDataBlob = require("scorpion.application.handlers.support.gamedata_blob")
local Nearby = require("scorpion.application.handlers.support.nearby")
local SessionSupport = require("scorpion.application.handlers.support.session_support")
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
  item = require("scorpion.application.handlers.families.item"),
  login = require("scorpion.application.handlers.families.login"),
  message = require("scorpion.application.handlers.families.message"),
  paperdoll = require("scorpion.application.handlers.families.paperdoll"),
  npc_range = require("scorpion.application.handlers.families.npc_range"),
  player_range = require("scorpion.application.handlers.families.player_range"),
  range = require("scorpion.application.handlers.families.range"),
  raw = require("scorpion.application.handlers.families.raw"),
  refresh = require("scorpion.application.handlers.families.refresh"),
  shop = require("scorpion.application.handlers.families.shop"),
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
    movement = MovementHandlers.new({
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

-- Shared helper surface used by family handler modules.
function SessionHandlers:auth_client(auth)
  return SessionSupport.auth_client(auth)
end

function SessionHandlers:load_character_location(session, character)
  local out = SessionSupport.load_character_location(session, character)
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end
  return out
end

function SessionHandlers:valid_account_name(name)
  return SessionSupport.valid_account_name(name)
end

function SessionHandlers:valid_character_name(name)
  return SessionSupport.valid_character_name(name)
end

function SessionHandlers:apply_arena_only_location(session)
  local out = SessionSupport.apply_arena_only_location(self.settings, session)
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end
  return out
end

function SessionHandlers:apply_map_relog_location(session)
  local out = SessionSupport.apply_map_relog_location(self.world, session)
  if self.world.sync_session_spatial then
    self.world:sync_session_spatial(session)
  end
  return out
end

function SessionHandlers:get_pub_blob(key)
  return SessionSupport.get_pub_blob(self.world, key)
end

function SessionHandlers:add_rid(reply, data)
  return SessionSupport.add_rid(reply, data)
end

function SessionHandlers:add_pub_meta(reply, blob)
  return SessionSupport.add_pub_meta(reply, blob)
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

function SessionHandlers:get_nearby_npcs(center_session)
  return Nearby.get_nearby_npcs(self.world, center_session)
end

function SessionHandlers:get_nearby_items(center_session)
  return Nearby.get_nearby_items(self.world, center_session)
end

function SessionHandlers:add_npc_map_info(reply, npc)
  return Nearby.add_npc_map_info(reply, npc)
end

function SessionHandlers:add_item_map_info(reply, item)
  return Nearby.add_item_map_info(reply, item)
end

-- Write NearbyInfo (characters + NPCs + items) into reply.
function SessionHandlers:add_nearby_info(reply, nearby, npcs, items)
  return Nearby.add_nearby_info(reply, nearby, npcs, items)
end

function SessionHandlers:get_requested_nearby_sessions(center_session, player_ids)
  return Nearby.get_requested_nearby_sessions(self.world, self.accounts, center_session, player_ids)
end

function SessionHandlers:get_requested_nearby_npcs(center_session, npc_indexes)
  return Nearby.get_requested_nearby_npcs(self.world, center_session, npc_indexes)
end

function SessionHandlers:get_requested_nearby_items(center_session, item_uids)
  return Nearby.get_requested_nearby_items(self.world, center_session, item_uids)
end

function SessionHandlers:parse_player_ids(packet)
  return SessionSupport.parse_player_ids(packet)
end

function SessionHandlers:parse_range_request(packet)
  return SessionSupport.parse_range_request(packet)
end

function SessionHandlers:parse_npc_range_request(packet)
  return SessionSupport.parse_npc_range_request(packet)
end

function SessionHandlers:broadcast_all(packet, exclude_session)
  return SessionSupport.broadcast_all(self.world, packet, exclude_session)
end

function SessionHandlers:find_session_by_character_name(name)
  return SessionSupport.find_session_by_character_name(self.world, self.accounts, name)
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

-- Register protocol families to stable source-style handler names.
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
    { family = Family.Paperdoll,  name = "HandlePaperdoll" },
    { family = Family.Players,    name = "HandleUnimplemented" },
    { family = Family.Door,       name = "HandleUnimplemented" },
    { family = Family.Emote,      name = "HandleUnimplemented" },
    { family = Family.Shop,       name = "HandleShop"          },
    { family = Family.Chair,      name = "HandleUnimplemented" },
    { family = Family.Item,       name = "HandleItem"          },
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

function SessionHandlers:HandleShop(packet, context)
  return FamilyModules.shop.handle(self, packet, context)
end

function SessionHandlers:HandlePaperdoll(packet, context)
  return FamilyModules.paperdoll.handle(self, packet, context)
end

function SessionHandlers:HandleItem(packet, context)
  return FamilyModules.item.handle(self, packet, context)
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
