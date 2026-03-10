package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./lua/?/?.lua",
  "./tests/?.lua",
  "./tests/?/init.lua",
  package.path,
}, ";")

local T = require("tests.lib.test_helper")

require("tests.test_session_support")
require("tests.test_nearby")

local failed = T.run()
if failed > 0 then
  os.exit(1)
end
