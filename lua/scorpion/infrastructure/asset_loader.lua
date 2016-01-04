local AssetLoader = {}
local EmfParser = require("scorpion.infrastructure.emf_parser")

local CLIENT_PUB_FILES = {
  { key = "ecf", name = "dat001.ecf", sig = "ECF" },
  { key = "eif", name = "dat001.eif", sig = "EIF" },
  { key = "enf", name = "dtn001.enf", sig = "ENF" },
  { key = "esf", name = "dsl001.esf", sig = "ESF" },
}

local SERVER_PUB_FILES = {
  { key = "drops", name = "serv_drops.epf" },
  { key = "inns", name = "serv_inns.epf" },
  { key = "shops", name = "serv_shops.epf" },
  { key = "talk", name = "serv_chats.epf" },
  { key = "trainers", name = "serv_trainers.epf" },
}

local function join_path(dir, file)
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
    return dir .. file
  end

  return dir .. "/" .. file
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end

  local data = file:read("*a")
  file:close()
  return data
end

local function powershell_escape(text)
  return (text or ""):gsub("'", "''")
end

local function list_files(dir, mask)
  local cmd = ("powershell -NoProfile -Command \"Get-ChildItem -Path '%s' -File -Filter '%s' -Name -ErrorAction SilentlyContinue\"")
    :format(powershell_escape(dir), powershell_escape(mask))
  local pipe = io.popen(cmd)
  if not pipe then
    return {}
  end

  local out = {}
  for line in pipe:lines() do
    if #line > 0 then
      out[#out + 1] = line
    end
  end

  pipe:close()
  table.sort(out)
  return out
end

local function load_maps(map_dirs)
  local maps = {}

  for _, map_dir in ipairs(map_dirs or {}) do
    for _, filename in ipairs(list_files(map_dir, "*.emf")) do
      local id = tonumber(filename:match("^(%d+)%.emf$"))
      if id then
        local path = join_path(map_dir, filename)
        local data = read_file(path)

        if data and data:sub(1, 3) == "EMF" then
          local meta, parse_error = EmfParser.parse(data)
          maps[id] = {
            id = id,
            path = path,
            data = data,
            meta = meta,
            parse_error = parse_error,
          }
        end
      end
    end
  end

  return maps
end

local function load_pub_set(pub_dirs, files)
  local out = {}

  for _, pub_dir in ipairs(pub_dirs or {}) do
    for _, pub_file in ipairs(files) do
      if out[pub_file.key] == nil then
        local path = join_path(pub_dir, pub_file.name)
        local data = read_file(path)
        local sig_ok = (pub_file.sig == nil) or (data and data:sub(1, 3) == pub_file.sig)

        if data and sig_ok then
          out[pub_file.key] = { name = pub_file.name, path = path, data = data }
        end
      end
    end
  end

  return out
end

function AssetLoader.load(settings)
  local data = settings.data or {}
  local maps = load_maps(data.map_dirs or {})
  local client_pub = load_pub_set(data.pub_dirs or {}, CLIENT_PUB_FILES)
  local server_pub = load_pub_set(data.pub_dirs or {}, SERVER_PUB_FILES)

  return {
    maps = maps,
    pub = {
      client = client_pub,
      server = server_pub,
    },
  }
end

return AssetLoader
