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
  local spawn = (self.settings.new_character or {}).spawn_map or 5

  if self.settings.arena and self.settings.arena.only then
    if not self.world:has_map(spawn) then
      self.world.arena_ready = false
      return nil, ("arena map %d missing"):format(spawn)
    end

    if self.settings.arena.enforce_pub then
      local p = self.world.pub.client or {}
      local missing = (not p.ecf) or (not p.eif) or (not p.enf) or (not p.esf)
      if missing then
        return nil, "required pub files missing (ECF/EIF/ENF/ESF)"
      end
    end
  end

  self.world.arena_ready = true
  return true
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
