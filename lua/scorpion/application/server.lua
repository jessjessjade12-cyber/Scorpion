local ServerBoot = require("scorpion.application.services.server_boot")

local Server = {}
Server.__index = Server

function Server.new(deps)
  return setmetatable({
    accounts = deps.accounts,
    logger = deps.logger,
    scheduler = deps.scheduler,
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

function Server:tick(now)
  if not self.scheduler or not self.scheduler.tick then
    return
  end
  self.scheduler:tick(now)
end

function Server:save_session(session, source)
  if not session then
    return nil, "missing_session"
  end

  if not self.accounts or not self.accounts.save_session then
    return true
  end

  local ok, err = self.accounts:save_session(session)
  if not ok and self.logger then
    self.logger:warn("session persistence failed", {
      account = session.account or "unknown",
      error = tostring(err or "unknown"),
      session_id = session.id or 0,
      source = source or "unknown",
    })
  end

  return ok, err
end

return Server
