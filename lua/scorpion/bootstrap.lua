local AccountsMongo = require("scorpion.infrastructure.accounts_mongo")
local AssetLoader = require("scorpion.infrastructure.asset_loader")
local ArenaScriptRunner = require("scorpion.application.services.arena_script_runner")
local Codec = require("scorpion.transport.codec")
local Logger = require("scorpion.infrastructure.logger")
local Server = require("scorpion.application.server")
local SessionHandlers = require("scorpion.application.handlers.session_handlers")
local Settings = require("scorpion.infrastructure.settings")
local Runtime = require("scorpion.infrastructure.runtime")
local Router = require("scorpion.transport.router")
local World = require("scorpion.domain.world")

local Bootstrap = {}

function Bootstrap.build()
  local settings = Settings.load()
  local logger = Logger.new(settings)
  local accounts = AccountsMongo.new(settings.accounts, settings)
  local world = World.new()
  local assets = AssetLoader.load(settings)

  world:attach_assets(assets)
  world:configure_arena(settings)
  world:configure_npc_movement(settings)
  world:attach_arena_script_runner(ArenaScriptRunner.new({
    accounts = accounts,
    logger = logger,
    settings = settings,
    world = world,
  }))

  local router = Router.new()
  local server = Server.new({
    accounts = accounts,
    logger = logger,
    settings = settings,
    router = router,
    world = world,
  })
  local handlers = SessionHandlers.new({
    accounts = accounts,
    logger = logger,
    server = server,
    settings = settings,
    world = world,
  })

  handlers:register(router)

  return Runtime.new({
    codec  = Codec,
    logger = logger,
    server = server,
  })
end

return Bootstrap
