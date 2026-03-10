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
    server = deps.server,
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
  if self.server and (session.character_id and session.character_id > 0) then
    self.server:save_session(session, "character_switch")
  end

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

function SessionHandlers:resolve_session_character(session)
  local cached = SessionSupport.cached_character_profile(session)
  if cached then
    return cached
  end

  if not session then
    return nil
  end

  local character_id = tonumber(session.character_id) or 0
  if character_id <= 0 then
    return nil
  end

  local character = self.accounts:get_character(session.account, character_id)
  if character then
    return SessionSupport.cache_character_profile(session, character) or character
  end

  return nil
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
  return Nearby.get_nearby_sessions(
    self.world,
    self.accounts,
    center_session,
    function(session)
      return self:resolve_session_character(session)
    end
  )
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
  return Nearby.get_requested_nearby_sessions(
    self.world,
    self.accounts,
    center_session,
    player_ids,
    function(session)
      return self:resolve_session_character(session)
    end
  )
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
  return SessionSupport.find_session_by_character_name(
    self.world,
    self.accounts,
    name,
    function(session)
      return self:resolve_session_character(session)
    end
  )
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

local FamilyRoutes = {
  [Family.Raw] = "raw",
  [Family.Connection] = "connection",
  [Family.Account] = "account",
  [Family.Character] = "character",
  [Family.Login] = "login",
  [Family.GameData] = "gamedata",
  [Family.Walk] = "walk",
  [Family.PlayerRange] = "player_range",
  [Family.NpcRange] = "npc_range",
  [Family.Range] = "range",
  [Family.Face] = "face",
  [Family.Talk] = "talk",
  [Family.Sit] = "unimplemented",
  [Family.Warp] = "warp",
  [Family.Message] = "message",
  [Family.Paperdoll] = "paperdoll",
  [Family.Players] = "unimplemented",
  [Family.Door] = "unimplemented",
  [Family.Emote] = "unimplemented",
  [Family.Shop] = "shop",
  [Family.Chair] = "unimplemented",
  [Family.Item] = "item",
  [Family.Locker] = "unimplemented",
  [Family.Attack] = "attack",
  [Family.Refresh] = "refresh",
  [Family.Skill] = "unimplemented",
  [Family.Barber] = "unimplemented",
  [Family.Bank] = "unimplemented",
}

function SessionHandlers:register(router)
  router:set_default(function(packet, context)
    return FamilyModules.default.handle(self, packet, context)
  end)

  for family, module_name in pairs(FamilyRoutes) do
    local module = FamilyModules[module_name] or FamilyModules.unimplemented
    router:register(family, function(packet, context)
      return module.handle(self, packet, context)
    end)
  end
end

return SessionHandlers
