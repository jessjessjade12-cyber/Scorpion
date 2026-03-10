local util = require("scorpion.util")

local clamp = util.clamp

local M = {}

local MAX_ITEM_UID = 64008
local MAX_ITEM_ID = 64008
local MAX_ITEM_AMOUNT = 16194276
local MAX_COORD = 252

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp_uid(value)
  return clamp(to_int(value, 0), 0, MAX_ITEM_UID)
end

local function clamp_item_id(value)
  return clamp(to_int(value, 0), 0, MAX_ITEM_ID)
end

local function clamp_amount(value)
  return clamp(to_int(value, 0), 0, MAX_ITEM_AMOUNT)
end

local function clamp_coord(value)
  return clamp(to_int(value, 0), 0, MAX_COORD)
end

local function map_state(self, map_id, create_if_missing)
  local id = to_int(map_id, 0)
  if id <= 0 then
    return nil
  end

  local state = self.map_items[id]
  if state ~= nil or not create_if_missing then
    return state
  end

  state = {
    by_uid = {},
    next_uid = 1,
  }
  self.map_items[id] = state
  return state
end

local function next_uid(state)
  local start_uid = clamp_uid(state.next_uid or 1)
  if start_uid <= 0 then
    start_uid = 1
  end
  local uid = start_uid

  for _ = 1, MAX_ITEM_UID do
    if state.by_uid[uid] == nil then
      state.next_uid = uid + 1
      if state.next_uid > MAX_ITEM_UID then
        state.next_uid = 1
      end
      return uid
    end

    uid = uid + 1
    if uid > MAX_ITEM_UID then
      uid = 1
    end
  end

  return nil
end

function M.list_map_items(self, map_id)
  local state = map_state(self, map_id, false)
  if state == nil then
    return {}
  end

  local out = {}
  for _, item in pairs(state.by_uid) do
    out[#out + 1] = item
  end

  table.sort(out, function(a, b)
    return (a.uid or 0) < (b.uid or 0)
  end)

  return out
end

function M.find_map_item(self, map_id, uid)
  local state = map_state(self, map_id, false)
  if state == nil then
    return nil
  end

  uid = clamp_uid(uid)
  if uid <= 0 then
    return nil
  end

  return state.by_uid[uid]
end

function M.add_map_item(self, map_id, item_id, amount, x, y, owner_session_id)
  local state = map_state(self, map_id, true)
  if state == nil then
    return nil
  end

  local uid = next_uid(state)
  if uid == nil then
    return nil
  end

  local map_id_int = to_int(map_id, 0)
  local item = {
    map_id = map_id_int,
    uid = uid,
    id = clamp_item_id(item_id),
    amount = clamp_amount(amount),
    x = clamp_coord(x),
    y = clamp_coord(y),
    owner_session_id = to_int(owner_session_id, 0),
  }

  if item.id <= 0 or item.amount <= 0 then
    return nil
  end

  state.by_uid[uid] = item
  return item
end

function M.take_map_item(self, map_id, uid, amount)
  local state = map_state(self, map_id, false)
  if state == nil then
    return nil, 0
  end

  uid = clamp_uid(uid)
  if uid <= 0 then
    return nil, 0
  end

  local item = state.by_uid[uid]
  if item == nil then
    return nil, 0
  end

  local take_amount = clamp_amount(math.min(item.amount or 0, to_int(amount, 0)))
  if take_amount <= 0 then
    return nil, item.amount or 0
  end

  local taken = {
    map_id = item.map_id,
    uid = item.uid,
    id = item.id,
    amount = take_amount,
    x = item.x,
    y = item.y,
    owner_session_id = item.owner_session_id,
  }

  item.amount = (item.amount or 0) - take_amount
  if item.amount <= 0 then
    state.by_uid[uid] = nil
    item.amount = 0
  end

  return taken, item.amount
end

function M.remove_map_item(self, map_id, uid)
  local state = map_state(self, map_id, false)
  if state == nil then
    return nil
  end

  uid = clamp_uid(uid)
  if uid <= 0 then
    return nil
  end

  local removed = state.by_uid[uid]
  state.by_uid[uid] = nil
  return removed
end

function M.map_item_count(self)
  local total = 0
  for _, state in pairs(self.map_items or {}) do
    for _ in pairs(state.by_uid or {}) do
      total = total + 1
    end
  end
  return total
end

return M
