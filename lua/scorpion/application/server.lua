local ServerBoot = require("scorpion.application.services.server_boot")

local Server = {}
Server.__index = Server

function Server.new(deps)
  return setmetatable({
    settings = deps.settings,
    router = deps.router,
    world = deps.world,
  }, Server)
end

function Server:boot()
  local ok, err = ServerBoot.validate(self.settings, self.world)
  self.world.arena_ready = (ok == true)
  if not ok then
    return nil, err
  end
  return ok
end

function Server:dispatch(packet, context)
  return self.router:dispatch(packet, context)
end

function Server:snapshot()
  return self.world:snapshot()
end

function Server:registered_families()
  return self.router.handlers
end

return Server
