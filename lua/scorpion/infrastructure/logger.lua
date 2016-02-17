local Logger = {}
Logger.__index = Logger

local LEVEL_NUM = { debug = 0, info = 1, warn = 2, error = 3 }

-- ANSI colours (work in Windows Terminal and modern PowerShell)
local COLOUR = {
  debug = "\27[36m",
  info  = "\27[32m",
  warn  = "\27[33m",
  error = "\27[31m",
}
local RESET = "\27[0m"

local function ensure_dir(path)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir and dir ~= "" then
    os.execute(('mkdir "%s" >NUL 2>NUL'):format(dir))
  end
end

local function field_list(fields)
  if not fields then return "" end
  local keys = {}
  for k in pairs(fields) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = ("%s=%s"):format(k, tostring(fields[k]))
  end
  return #out > 0 and ("  " .. table.concat(out, "  ")) or ""
end

function Logger.new(settings)
  local cfg = (settings or {}).logging or {}

  local console_level = cfg.console_level or "info"
  local file_level    = cfg.file_level    or "info"

  local logger = setmetatable({
    colors            = cfg.colors ~= false,
    console           = cfg.console ~= false,
    console_level_num = LEVEL_NUM[console_level] or 1,
    file_enabled      = cfg.enabled ~= false,
    file_level_num    = LEVEL_NUM[file_level] or 1,
    path              = cfg.path or "logs/scorpion.log",
  }, Logger)

  if logger.file_enabled then
    ensure_dir(logger.path)
  end

  return logger
end

function Logger:write(level, message, fields)
  local num    = LEVEL_NUM[level] or 1
  local suffix = field_list(fields)
  local ts     = os.date("%H:%M:%S")
  local label  = string.upper(level)

  -- Console
  if self.console and num >= self.console_level_num then
    local c = self.colors and (COLOUR[level] or "") or ""
    local r = self.colors and RESET or ""
    io.write(("%s %s%5s%s  %s%s\n"):format(ts, c, label, r, message, suffix))
  end

  -- File
  if self.file_enabled and num >= self.file_level_num then
    local line = ("%s [%s] %s%s\n"):format(
      os.date("%Y-%m-%d %H:%M:%S"), label, message, suffix)
    local file = io.open(self.path, "ab")
    if file then
      file:write(line)
      file:close()
    end
  end
end

function Logger:debug(message, fields) self:write("debug", message, fields) end
function Logger:info(message, fields)  self:write("info",  message, fields) end
function Logger:warn(message, fields)  self:write("warn",  message, fields) end
function Logger:error(message, fields) self:write("error", message, fields) end

return Logger
