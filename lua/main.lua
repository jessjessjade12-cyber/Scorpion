package.path = table.concat({
  "lua/?.lua",
  "lua/?/init.lua",
  package.path,
}, ";")

local Bootstrap = require("scorpion.bootstrap")

math.randomseed(os.time())

local app = Bootstrap.build()
local ok, err = app:boot()

if not ok then
  io.stderr:write(("boot failed: %s\n"):format(err))
  os.exit(1)
end

app:run()
