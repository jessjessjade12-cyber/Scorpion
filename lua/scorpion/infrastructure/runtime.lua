local NetServer = require("scorpion.infrastructure.net_server")
local Protocol  = require("scorpion.transport.protocol")

local BANNER = [[
  ____    ____     ___    ____    ____   ___     ___   _   _      (        )
 / ___|  / ___|  / _ \  |  _ \  |  _ \ |_ _|  / _ \ | \ | |              O        O
 \___ \ | |     | | | | | |_) | | |_) | | |  | | | ||  \| |              ()      ()
  ___) || |___  | |_| | |  _ <  |  __/  | |  | |_| || |\  |               Oo.nn.oO
 |____/  \____|  \___/  |_| \_\ |_|    |___|  \___/ |_| \_|                _mmmm_
                                                                          \/_mmmm_\/
                                                                          \/_mmmm_\/
                                                                          \/_mmmm_\/
                                                                          \/ mmmm \/
                                                                              nn
                                                                              ()
                                                                              ()
                                                                               ()    /
                                                                           apc  ()__()
                                                                                 '--'
]]

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(deps)
  return setmetatable({
    codec    = deps.codec,
    logger   = deps.logger,
    server   = deps.server,
    settings = deps.server.settings,
  }, Runtime)
end

function Runtime:boot()
  return self.server:boot()
end

function Runtime:run()
  local settings = self.settings
  local net = NetServer.new({
    codec    = self.codec,
    logger   = self.logger,
    server   = self.server,
    settings = settings,
  })
  local ok, err = net:open()
  if not ok then
    error(("listen failed: %s"):format(err))
  end

  print(BANNER)

  local net_cfg = settings.net or {}
  local ws_port = net_cfg.websocket_port
  if ws_port then
    print(("  host    %s:%d  |  ws %d"):format(settings.host, settings.port, ws_port))
  else
    print(("  host    %s:%d"):format(settings.host, settings.port))
  end

  local state = self.server:snapshot()
  print(("  maps    %d loaded  |  arena map %d  |  ready %s"):format(
    state.maps,
    settings.arena.map or 0,
    tostring(state.arena_ready)
  ))

  local family_names = {}
  for name, id in pairs(Protocol.Family) do
    family_names[id] = name
  end
  local handler_names = {}
  for family_id in pairs(self.server:registered_families()) do
    handler_names[#handler_names + 1] = family_names[family_id] or tostring(family_id)
  end
  table.sort(handler_names)
  print(("  packets %s"):format(table.concat(handler_names, "  ")))
  print()

  if self.logger then
    self.logger:info("listener active", {
      host      = settings.host,
      port      = settings.port,
      maps      = state.maps,
      arena_map = settings.arena.map or 0,
    })
  end

  local ok_loop, loop_err = xpcall(function()
    return net:run_forever()
  end, debug.traceback)

  local err_text = tostring(loop_err or "")
  local interrupted = err_text:find("interrupted", 1, true) ~= nil

  if interrupted then
    net:shutdown("interrupt")
    print("stopped (Ctrl+C)")
    return
  end

  if not ok_loop then
    net:shutdown("runtime error")
    error(loop_err)
  end

  net:shutdown("normal stop")
end

return Runtime
