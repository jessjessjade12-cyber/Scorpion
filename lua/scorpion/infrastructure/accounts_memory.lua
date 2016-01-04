local AccountsMemory = {}
AccountsMemory.__index = AccountsMemory

local function lower(value)
  return string.lower(value or "")
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
  }
end

function AccountsMemory.new(seed, settings)
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

  -- In arena-only mode, default new characters to the configured arena queue entry tile.
  local first_spawn = (arena.spawns or {})[1]
  if arena.only and first_spawn and first_spawn.from then
    spawn.spawn_map = arena.map or spawn.spawn_map
    spawn.spawn_x = first_spawn.from.x
    spawn.spawn_y = first_spawn.from.y
  end

  local out = setmetatable({
    accounts = {},
    characters = {},
    characters_by_account = {},
    characters_by_name = {},
    max_characters = (((settings or {}).account or {}).max_characters or 3),
    next_account_id = 1,
    next_character_id = 1,
    spawn = spawn,
  }, AccountsMemory)

  for username, row in pairs(seed or {}) do
    local key = lower(username)
    local account = {
      id = out.next_account_id,
      password = row.password,
      role = row.role or "player",
      username = key,
    }
    out.next_account_id = out.next_account_id + 1
    out.accounts[key] = account
    out.characters_by_account[key] = {}
  end

  return out
end

function AccountsMemory:find(username)
  local key = lower(username)
  local row = self.accounts[key]

  if not row then
    return nil
  end

  return {
    id = row.id,
    password = row.password,
    role = row.role,
    username = key,
  }
end

function AccountsMemory:account_exists(username)
  return self.accounts[lower(username)] ~= nil
end

function AccountsMemory:create_account(username, password, role)
  local key = lower(username)
  if key == "" then
    return nil, "invalid"
  end

  if self.accounts[key] ~= nil then
    return nil, "exists"
  end

  local account = {
    id = self.next_account_id,
    password = password or "",
    role = role or "player",
    username = key,
  }

  self.next_account_id = self.next_account_id + 1
  self.accounts[key] = account
  self.characters_by_account[key] = {}
  return self:find(key)
end

function AccountsMemory:character_exists(name)
  return self.characters_by_name[lower(name)] ~= nil
end

function AccountsMemory:character_count(username)
  local list = self.characters_by_account[lower(username)] or {}
  return #list
end

function AccountsMemory:list_characters(username)
  local out = {}
  local ids = self.characters_by_account[lower(username)] or {}

  for _, id in ipairs(ids) do
    local row = self.characters[id]
    if row then
      out[#out + 1] = copy_character(row)
    end
  end

  return out
end

function AccountsMemory:get_character(username, character_id)
  local row = self.characters[character_id]
  if not row or row.account ~= lower(username) then
    return nil
  end

  return copy_character(row)
end

function AccountsMemory:create_character(username, spec)
  local account = lower(username)
  if self.accounts[account] == nil then
    return nil, "missing_account"
  end

  local ids = self.characters_by_account[account] or {}
  if #ids >= self.max_characters then
    return nil, "full"
  end

  local name = lower((spec or {}).name)
  if name == "" then
    return nil, "invalid"
  end

  if self.characters_by_name[name] ~= nil then
    return nil, "exists"
  end

  local spawn = self.spawn
  local row = {
    id = self.next_character_id,
    account = account,
    name = name,
    level = (spec and spec.level) or 0,
    sex = (spec and spec.sex) or 0,
    hair_style = (spec and spec.hair_style) or 1,
    hair_color = (spec and spec.hair_color) or 0,
    race = (spec and spec.race) or 0,
    admin = (spec and spec.admin) or 0,
    map_id = (spec and spec.map_id) or spawn.spawn_map or 5,
    x = (spec and spec.x) or spawn.spawn_x or 0,
    y = (spec and spec.y) or spawn.spawn_y or 0,
    direction = (spec and spec.direction) or spawn.spawn_direction or 0,
  }

  self.next_character_id = self.next_character_id + 1
  self.characters[row.id] = row
  self.characters_by_name[name] = row.id
  ids[#ids + 1] = row.id
  self.characters_by_account[account] = ids
  return copy_character(row)
end

function AccountsMemory:remove_character(username, character_id)
  local account = lower(username)
  local row = self.characters[character_id]

  if not row or row.account ~= account then
    return nil, "not_found"
  end

  self.characters[character_id] = nil
  self.characters_by_name[row.name] = nil

  local ids = self.characters_by_account[account] or {}
  for index, id in ipairs(ids) do
    if id == character_id then
      table.remove(ids, index)
      break
    end
  end

  self.characters_by_account[account] = ids
  return true
end

return AccountsMemory
