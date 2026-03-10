local MongoshClient = {}
MongoshClient.__index = MongoshClient
local temp_counter = 0

local function quote_cmd_arg(value)
  local s = tostring(value or "")
  s = s:gsub('"', '\\"')
  return '"' .. s .. '"'
end

local function js_quote(value)
  local s = tostring(value or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\r", "\\r")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local function last_non_empty_line(text)
  local last = nil
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      last = trimmed
    end
  end
  return last
end

local function decode_lua_value(text)
  if type(text) ~= "string" or text == "" then
    return nil, "empty value"
  end

  local chunk, load_err = loadstring("return " .. text)
  if not chunk then
    return nil, load_err or "decode load failed"
  end

  local ok, value = pcall(chunk)
  if not ok then
    return nil, value or "decode execute failed"
  end

  return value
end

local function build_script(database_name, body)
  return ([[
(function () {
  function luaQuote(value) {
    return '"' + String(value)
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
      .replace(/\t/g, '\\t') + '"';
  }

  function toLua(value) {
    if (value === null || value === undefined) {
      return "nil";
    }

    if (typeof value === "boolean") {
      return value ? "true" : "false";
    }

    if (typeof value === "number") {
      if (!isFinite(value)) {
        return "0";
      }
      return String(value);
    }

    if (typeof value === "string") {
      return luaQuote(value);
    }

    if (Array.isArray(value)) {
      return "{" + value.map(function (entry, index) {
        return "[" + (index + 1) + "]=" + toLua(entry);
      }).join(",") + "}";
    }

    if (typeof value === "object") {
      var keys = Object.keys(value).sort();
      return "{" + keys.map(function (key) {
        return "[" + luaQuote(key) + "]=" + toLua(value[key]);
      }).join(",") + "}";
    }

    return "nil";
  }

  try {
    const __db = db.getSiblingDB(__DB_NAME__);
    const __result = (function (db) {
__BODY__
    })(__db);

    const __normalized = __result === undefined
      ? null
      : JSON.parse(EJSON.stringify(__result, { relaxed: true }));

    print(toLua(__normalized));
  } catch (err) {
    print(toLua({ ok: false, error: String(err) }));
  }
})();
]]):gsub("__DB_NAME__", js_quote(database_name)):gsub("__BODY__", body or "return nil;")
end

local function join_path(dir, name)
  local d = tostring(dir or "")
  if d == "" then
    return name
  end

  local last = d:sub(-1)
  if last == "\\" or last == "/" then
    return d .. name
  end

  return d .. "\\" .. name
end

local function make_temp_script_path()
  local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "."
  temp_counter = temp_counter + 1

  local stamp = tostring(os.time())
  local random_piece = tostring(math.random(100000, 999999))
  local name = ("scorpion_mongosh_%s_%s_%d.js"):format(stamp, random_piece, temp_counter)

  return join_path(temp_dir, name)
end

function MongoshClient.new(config)
  local cfg = config or {}
  return setmetatable({
    binary = cfg.binary or "mongosh",
    database = cfg.database or "scorpion",
    uri = cfg.uri or "mongodb://127.0.0.1:27017",
  }, MongoshClient)
end

function MongoshClient:run(body)
  local script_path = make_temp_script_path()
  local script = build_script(self.database, body)

  local file, file_err = io.open(script_path, "wb")
  if not file then
    return nil, ("cannot write temporary mongosh script: %s"):format(tostring(file_err or "unknown"))
  end

  file:write(script)
  file:close()

  local inner = table.concat({
    quote_cmd_arg(self.binary),
    "--quiet",
    "--norc",
    quote_cmd_arg(self.uri),
    quote_cmd_arg(script_path),
  }, " ")

  local command
  if package.config:sub(1, 1) == "\\" then
    -- cmd.exe needs an extra quoting layer when the executable path has spaces.
    command = 'cmd /c "' .. inner .. ' 2>&1"'
  else
    command = inner .. " 2>&1"
  end

  local handle, open_err = io.popen(command, "r")
  if not handle then
    os.remove(script_path)
    return nil, ("cannot start mongosh: %s"):format(tostring(open_err or "unknown"))
  end

  local output = handle:read("*a") or ""
  handle:close()
  os.remove(script_path)

  local line = last_non_empty_line(output)
  if not line then
    return nil, ("mongosh returned no output; command=%s"):format(command)
  end

  local value, decode_err = decode_lua_value(line)
  if decode_err then
    return nil, ("mongosh decode failed: %s | raw=%s"):format(tostring(decode_err), output)
  end

  return value
end

return MongoshClient
