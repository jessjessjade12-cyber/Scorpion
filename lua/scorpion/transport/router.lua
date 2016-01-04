local Router = {}
Router.__index = Router

function Router.new()
  return setmetatable({
    default_handler = nil,
    handlers = {},
  }, Router)
end

function Router:register(family, handler)
  self.handlers[family] = handler
end

function Router:set_default(handler)
  self.default_handler = handler
end

function Router:dispatch(packet, context)
  local handler = self.handlers[packet.family] or self.default_handler

  if not handler then
    return nil, ("handler missing for family %d"):format(packet.family)
  end

  return handler(packet, context)
end

return Router
