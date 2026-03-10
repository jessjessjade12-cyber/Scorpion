local MongoshClient = require("scorpion.infrastructure.mongosh_client")
local Codec = require("scorpion.infrastructure.accounts_mongo_codec")

local AccountsMongo = {}
AccountsMongo.__index = AccountsMongo

local lower = Codec.lower
local to_int = Codec.to_int
local copy_table = Codec.copy_table
local copy_character = Codec.copy_character
local resolve_spawn = Codec.resolve_spawn
local mongo_config = Codec.mongo_config
local js_quote = Codec.js_quote
local lua_to_js = Codec.lua_to_js
local normalize_character = Codec.normalize_character

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
