local MongoshClient = require("scorpion.infrastructure.mongosh_client")

local AccountsMongo = {}
AccountsMongo.__index = AccountsMongo

local function lower(value)
  return string.lower(value or "")
end

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function copy_table(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[copy_table(k)] = copy_table(v)
  end
  return out
end

local function copy_character(row)
  return {
    id = row.id,
    name = row.name,
    level = row.level,
    sex = row.sex,
    hair_style = row.hair_style,
    hair_color = row.hair_color,
    race = row.race,
    admin = row.admin,
    map_id = row.map_id,
    x = row.x,
    y = row.y,
    direction = row.direction,
    inventory = copy_table(row.inventory),
    max_weight = row.max_weight,
    paperdoll = copy_table(row.paperdoll),
  }
end

local function resolve_spawn(settings)
  local cfg = settings or {}
  local arena = cfg.arena or {}
  local base_spawn = cfg.new_character or {
    spawn_direction = 0,
    spawn_map = 5,
    spawn_x = 12,
    spawn_y = 24,
  }

  local spawn = {
    spawn_direction = base_spawn.spawn_direction or 0,
    spawn_map = base_spawn.spawn_map or arena.map or 5,
    spawn_x = base_spawn.spawn_x or 12,
    spawn_y = base_spawn.spawn_y or 24,
  }

  local first_spawn = (arena.spawns or {})[1]
  if arena.only and first_spawn and first_spawn.from then
    spawn.spawn_map = arena.map or spawn.spawn_map
    spawn.spawn_x = first_spawn.from.x
    spawn.spawn_y = first_spawn.from.y
  end

  return spawn
end

local function mongo_config(settings)
  local root = (settings or {}).persistence or {}
  local cfg = root.mongodb or root.mongo or {}

  return {
    binary = cfg.mongosh_path or cfg.binary or "mongosh",
    database = cfg.database or "scorpion",
    uri = cfg.uri or "mongodb://127.0.0.1:27017",
  }
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

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end

  local count = 0
  local max_index = 0

  for key in pairs(tbl) do
    if type(key) ~= "number" then
      return false
    end

    local int_key = math.floor(key)
    if int_key ~= key or int_key < 1 then
      return false
    end

    if int_key > max_index then
      max_index = int_key
    end
    count = count + 1
  end

  return count == max_index
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  return keys
end

local function lua_to_js(value)
  local kind = type(value)

  if kind == "nil" then
    return "null"
  end

  if kind == "boolean" then
    return value and "true" or "false"
  end

  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "0"
    end
    return tostring(value)
  end

  if kind == "string" then
    return js_quote(value)
  end

  if kind ~= "table" then
    return "null"
  end

  local pieces = {}

  if is_array(value) then
    for index = 1, #value do
      pieces[#pieces + 1] = lua_to_js(value[index])
    end
    return "[" .. table.concat(pieces, ",") .. "]"
  end

  for _, key in ipairs(sorted_keys(value)) do
    local encoded_key = js_quote(tostring(key))
    local encoded_value = lua_to_js(value[key])
    pieces[#pieces + 1] = encoded_key .. ":" .. encoded_value
  end

  return "{" .. table.concat(pieces, ",") .. "}"
end

local function convert_numeric_keys(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, entry in pairs(value) do
    local numeric_key = tonumber(key)
    if numeric_key ~= nil and tostring(numeric_key) == tostring(key) then
      key = numeric_key
    end
    out[key] = convert_numeric_keys(entry)
  end
  return out
end

local function normalize_character(row, spawn)
  if type(row) ~= "table" then
    return nil
  end

  local normalized = {
    id = to_int(row.id, 0) or 0,
    name = lower(row.name),
    level = to_int(row.level, 0) or 0,
    sex = to_int(row.sex, 0) or 0,
    hair_style = to_int(row.hair_style, 1) or 1,
    hair_color = to_int(row.hair_color, 0) or 0,
    race = to_int(row.race, 0) or 0,
    admin = to_int(row.admin, 0) or 0,
    map_id = to_int(row.map_id, spawn.spawn_map) or spawn.spawn_map,
    x = to_int(row.x, spawn.spawn_x) or spawn.spawn_x,
    y = to_int(row.y, spawn.spawn_y) or spawn.spawn_y,
    direction = to_int(row.direction, spawn.spawn_direction) or spawn.spawn_direction,
    inventory = convert_numeric_keys(copy_table(row.inventory)),
    max_weight = row.max_weight ~= nil and to_int(row.max_weight, 0) or nil,
    paperdoll = convert_numeric_keys(copy_table(row.paperdoll)),
  }

  if normalized.id <= 0 or normalized.name == "" then
    return nil
  end

  return normalized
end

function AccountsMongo:_run(body)
  local result, err = self.client:run(body)
  if err then
    return nil, err
  end

  if type(result) == "table" and result.ok == false then
    return nil, tostring(result.error or "mongo_error")
  end

  return result
end

function AccountsMongo:_initialize()
  local result, err = self:_run([[
db.accounts.createIndex({ username: 1 }, { unique: true });
db.characters.createIndex({ name: 1 }, { unique: true });
db.characters.createIndex({ account: 1 });
db.meta.updateOne(
  { _id: "counters" },
  { $setOnInsert: { next_account_id: 0, next_character_id: 0 } },
  { upsert: true }
);
return { ok: true };
]])

  if not result then
    return nil, err
  end

  return true
end

function AccountsMongo.new(seed, settings)
  local out = setmetatable({
    client = MongoshClient.new(mongo_config(settings)),
    max_characters = (((settings or {}).account or {}).max_characters or 3),
    spawn = resolve_spawn(settings),
  }, AccountsMongo)

  local ok, err = out:_initialize()
  if not ok then
    error(("failed to initialize MongoDB backend: %s"):format(tostring(err or "unknown")))
  end

  for username, row in pairs(seed or {}) do
    local key = lower(username)
    if key ~= "" then
      local created, create_err = out:create_account(
        key,
        (row or {}).password or "",
        (row or {}).role or "player"
      )

      if not created and create_err ~= "exists" then
        error(("failed to seed account '%s': %s"):format(key, tostring(create_err or "unknown")))
      end
    end
  end

  return out
end

function AccountsMongo:find(username)
  local key = lower(username)
  if key == "" then
    return nil
  end

  local result, err = self:_run(string.format([[
const username = %s;
return db.accounts.findOne(
  { username: username },
  { _id: 0, id: 1, password: 1, role: 1, username: 1 }
);
]], js_quote(key)))

  if not result then
    return nil, err
  end

  if type(result) ~= "table" then
    return nil
  end

  return {
    id = to_int(result.id, 0) or 0,
    password = result.password or "",
    role = result.role or "player",
    username = key,
  }
end

function AccountsMongo:account_exists(username)
  return self:find(username) ~= nil
end

function AccountsMongo:create_account(username, password, role)
  local key = lower(username)
  if key == "" then
    return nil, "invalid"
  end

  local result, err = self:_run(string.format([[
const username = %s;
const password = %s;
const role = %s;

if (db.accounts.findOne({ username: username }, { _id: 1 })) {
  return { ok: false, error: "exists" };
}

const counter = db.meta.findOneAndUpdate(
  { _id: "counters" },
  { $inc: { next_account_id: 1 }, $setOnInsert: { next_character_id: 0 } },
  { upsert: true, returnDocument: "after" }
);

const id = (counter && counter.next_account_id) || 1;
db.accounts.insertOne({
  _id: username,
  id: id,
  username: username,
  password: password,
  role: role
});

return {
  ok: true,
  account: { id: id, username: username, password: password, role: role }
};
]], js_quote(key), js_quote(password or ""), js_quote(role or "player")))

  if not result then
    return nil, err
  end

  return result.account
end

function AccountsMongo:character_exists(name)
  local key = lower(name)
  if key == "" then
    return false
  end

  local result = self:_run(string.format([[
const name = %s;
return db.characters.findOne(
  { name: name },
  { _id: 1 }
) !== null;
]], js_quote(key)))

  return result == true
end

function AccountsMongo:character_count(username)
  local account = lower(username)
  if account == "" then
    return 0
  end

  local result = self:_run(string.format([[
const account = %s;
return db.characters.countDocuments({ account: account });
]], js_quote(account)))

  return to_int(result, 0) or 0
end

function AccountsMongo:list_characters(username)
  local account = lower(username)
  if account == "" then
    return {}
  end

  local result = self:_run(string.format([[
const account = %s;
return db.characters.find(
  { account: account },
  { _id: 0 }
).sort({ id: 1 }).toArray();
]], js_quote(account)))

  local out = {}
  if type(result) ~= "table" then
    return out
  end

  for _, row in ipairs(result) do
    local normalized = normalize_character(row, self.spawn)
    if normalized then
      out[#out + 1] = copy_character(normalized)
    end
  end

  return out
end

function AccountsMongo:get_character(username, character_id)
  local account = lower(username)
  local id = to_int(character_id, 0)
  if account == "" or id <= 0 then
    return nil
  end

  local result = self:_run(string.format([[
const account = %s;
const id = %d;
return db.characters.findOne(
  { account: account, id: id },
  { _id: 0 }
);
]], js_quote(account), id))

  local normalized = normalize_character(result, self.spawn)
  if not normalized then
    return nil
  end

  return copy_character(normalized)
end

function AccountsMongo:create_character(username, spec)
  local account = lower(username)
  if account == "" then
    return nil, "missing_account"
  end

  local normalized_spec = {
    name = lower((spec or {}).name),
    level = to_int((spec or {}).level, 0) or 0,
    sex = to_int((spec or {}).sex, 0) or 0,
    hair_style = to_int((spec or {}).hair_style, 1) or 1,
    hair_color = to_int((spec or {}).hair_color, 0) or 0,
    race = to_int((spec or {}).race, 0) or 0,
    admin = to_int((spec or {}).admin, 0) or 0,
    map_id = to_int((spec or {}).map_id, self.spawn.spawn_map) or self.spawn.spawn_map,
    x = to_int((spec or {}).x, self.spawn.spawn_x) or self.spawn.spawn_x,
    y = to_int((spec or {}).y, self.spawn.spawn_y) or self.spawn.spawn_y,
    direction = to_int((spec or {}).direction, self.spawn.spawn_direction) or self.spawn.spawn_direction,
    inventory = copy_table((spec or {}).inventory),
    max_weight = (spec or {}).max_weight ~= nil and to_int((spec or {}).max_weight, 0) or nil,
    paperdoll = copy_table((spec or {}).paperdoll),
  }

  if normalized_spec.name == "" then
    return nil, "invalid"
  end

  local result, err = self:_run(string.format([[
const account = %s;
const maxCharacters = %d;
const spec = %s;

if (!db.accounts.findOne({ username: account }, { _id: 1 })) {
  return { ok: false, error: "missing_account" };
}

const count = db.characters.countDocuments({ account: account });
if (count >= maxCharacters) {
  return { ok: false, error: "full" };
}

const name = String(spec.name || "").toLowerCase();
if (!name) {
  return { ok: false, error: "invalid" };
}

if (db.characters.findOne({ name: name }, { _id: 1 })) {
  return { ok: false, error: "exists" };
}

const counter = db.meta.findOneAndUpdate(
  { _id: "counters" },
  { $inc: { next_character_id: 1 }, $setOnInsert: { next_account_id: 0 } },
  { upsert: true, returnDocument: "after" }
);

const id = (counter && counter.next_character_id) || 1;
const character = {
  _id: id,
  id: id,
  account: account,
  name: name,
  level: Number(spec.level || 0),
  sex: Number(spec.sex || 0),
  hair_style: Number(spec.hair_style || 1),
  hair_color: Number(spec.hair_color || 0),
  race: Number(spec.race || 0),
  admin: Number(spec.admin || 0),
  map_id: Number(spec.map_id || 0),
  x: Number(spec.x || 0),
  y: Number(spec.y || 0),
  direction: Number(spec.direction || 0),
  inventory: spec.inventory || null,
  max_weight: spec.max_weight === undefined ? null : spec.max_weight,
  paperdoll: spec.paperdoll || null
};

db.characters.insertOne(character);
delete character._id;
return { ok: true, character: character };
]],
    js_quote(account),
    self.max_characters,
    lua_to_js(normalized_spec)
  ))

  if not result then
    return nil, err
  end

  local normalized = normalize_character(result.character, self.spawn)
  if not normalized then
    return nil, "create_failed"
  end

  return copy_character(normalized)
end

function AccountsMongo:update_character_state(username, character_id, state)
  local account = lower(username)
  local id = to_int(character_id, 0)
  if account == "" or id <= 0 then
    return nil, "not_found"
  end

  state = state or {}

  local result, err = self:_run(string.format([[
const account = %s;
const id = %d;
const state = %s;

const existing = db.characters.findOne(
  { account: account, id: id },
  { _id: 1 }
);

if (!existing) {
  return { ok: false, error: "not_found" };
}

const numeric = {
  level: true,
  sex: true,
  hair_style: true,
  hair_color: true,
  race: true,
  admin: true,
  map_id: true,
  x: true,
  y: true,
  direction: true
};

const updates = {};
for (const key of Object.keys(state)) {
  if (key === "inventory" || key === "paperdoll") {
    updates[key] = state[key];
    continue;
  }

  if (key === "max_weight") {
    updates[key] = state[key] === null ? null : Number(state[key]);
    continue;
  }

  if (numeric[key]) {
    updates[key] = Number(state[key]);
    continue;
  }

  updates[key] = state[key];
}

if (Object.keys(updates).length > 0) {
  db.characters.updateOne(
    { account: account, id: id },
    { $set: updates }
  );
}

return {
  ok: true,
  character: db.characters.findOne(
    { account: account, id: id },
    { _id: 0 }
  )
};
]], js_quote(account), id, lua_to_js(state)))

  if not result then
    return nil, err
  end

  local normalized = normalize_character(result.character, self.spawn)
  if not normalized then
    return nil, "not_found"
  end

  return copy_character(normalized)
end

function AccountsMongo:save_session(session)
  if not session then
    return nil, "missing_session"
  end

  local account = lower(session.account)
  local character_id = to_int(session.character_id, 0)
  if account == "" or character_id <= 0 then
    return nil, "missing_character"
  end

  local updated, err = self:update_character_state(account, character_id, {
    map_id = session.map_id,
    x = session.x,
    y = session.y,
    direction = session.direction,
    inventory = session.inventory,
    max_weight = session.max_weight,
    paperdoll = session.paperdoll,
  })

  if not updated then
    return nil, err
  end

  return true
end

function AccountsMongo:remove_character(username, character_id)
  local account = lower(username)
  local id = to_int(character_id, 0)
  if account == "" or id <= 0 then
    return nil, "not_found"
  end

  local result, err = self:_run(string.format([[
const account = %s;
const id = %d;

const existing = db.characters.findOne(
  { account: account, id: id },
  { _id: 1 }
);

if (!existing) {
  return { ok: false, error: "not_found" };
}

db.characters.deleteOne({ account: account, id: id });
return { ok: true };
]], js_quote(account), id))

  if not result then
    return nil, err
  end

  return true
end

function AccountsMongo:persist_now()
  return true
end

return AccountsMongo
