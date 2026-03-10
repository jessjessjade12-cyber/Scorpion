local util = require("scorpion.util")

local clamp = util.clamp

local M = {}

local MAX_INT4 = 4097152080
local DEFAULT_MAX_WEIGHT = 120
local DEFAULT_START_GOLD = 1000
local GOLD_ITEM_ID = 1

local ITEM_TYPE = {
  Weapon = 10,
  Shield = 11,
  Armor = 12,
  Hat = 13,
  Boots = 14,
  Gloves = 15,
  Accessory = 16,
  Belt = 17,
  Necklace = 18,
  Ring = 19,
  Armlet = 20,
  Bracer = 21,
}

local function to_int(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return math.floor(n)
end

local function clamp_int4(value)
  return clamp(to_int(value, 0), 0, MAX_INT4)
end

local function clamp_char(value)
  return clamp(to_int(value, 0), 0, 252)
end

local function default_equipment()
  return {
    boots = 0,
    accessory = 0,
    gloves = 0,
    belt = 0,
    armor = 0,
    necklace = 0,
    hat = 0,
    shield = 0,
    weapon = 0,
    ring = { 0, 0 },
    armlet = { 0, 0 },
    bracer = { 0, 0 },
  }
end

local function normalized_pair(values)
  return {
    clamp_int4((values or {})[1] or 0),
    clamp_int4((values or {})[2] or 0),
  }
end

local function normalize_equipment(existing)
  local base = default_equipment()
  existing = existing or {}
  base.boots = clamp_int4(existing.boots or 0)
  base.accessory = clamp_int4(existing.accessory or 0)
  base.gloves = clamp_int4(existing.gloves or 0)
  base.belt = clamp_int4(existing.belt or 0)
  base.armor = clamp_int4(existing.armor or 0)
  base.necklace = clamp_int4(existing.necklace or 0)
  base.hat = clamp_int4(existing.hat or 0)
  base.shield = clamp_int4(existing.shield or 0)
  base.weapon = clamp_int4(existing.weapon or 0)
  base.ring = normalized_pair(existing.ring)
  base.armlet = normalized_pair(existing.armlet)
  base.bracer = normalized_pair(existing.bracer)
  return base
end

local function sync_shop_compat(session)
  session.shop_items = session.inventory
  session.shop_gold = clamp_int4((session.inventory or {})[GOLD_ITEM_ID] or 0)
  session.shop_max_weight = clamp_char(session.max_weight or DEFAULT_MAX_WEIGHT)
end

function M.ensure(self, session)
  if session.inventory == nil then
    local inventory = {}

    for item_id, amount in pairs(session.shop_items or {}) do
      local id = to_int(item_id, 0)
      if id > 0 then
        inventory[id] = clamp_int4(amount)
      end
    end

    local legacy_gold = to_int(session.shop_gold, nil)
    if legacy_gold ~= nil then
      inventory[GOLD_ITEM_ID] = clamp_int4(legacy_gold)
    end

    if next(inventory) == nil then
      local start_gold = to_int(((self.settings.new_character or {}).start_gold), DEFAULT_START_GOLD)
      if start_gold > 0 then
        inventory[GOLD_ITEM_ID] = clamp_int4(start_gold)
      end
    end

    session.inventory = inventory
  end

  if session.max_weight == nil then
    local legacy_max = to_int(session.shop_max_weight, nil)
    if legacy_max ~= nil then
      session.max_weight = clamp_char(legacy_max)
    else
      session.max_weight = clamp_char(DEFAULT_MAX_WEIGHT)
    end
  end

  session.paperdoll = normalize_equipment(session.paperdoll)
  session.equipment_graphics = M.visible_equipment_graphics(self, session)
  sync_shop_compat(session)
end

function M.item_amount(session, item_id)
  local id = to_int(item_id, 0)
  if id <= 0 then
    return 0
  end
  return clamp_int4((session.inventory or {})[id] or 0)
end

function M.set_item_amount(session, item_id, amount)
  local id = to_int(item_id, 0)
  if id <= 0 then
    return 0
  end

  local next_amount = clamp_int4(amount)
  local inventory = session.inventory or {}
  if next_amount <= 0 then
    inventory[id] = nil
  else
    inventory[id] = next_amount
  end

  session.inventory = inventory
  sync_shop_compat(session)
  return next_amount
end

function M.add_item(session, item_id, amount)
  local current = M.item_amount(session, item_id)
  return M.set_item_amount(session, item_id, current + clamp_int4(amount))
end

function M.remove_item(session, item_id, amount)
  local current = M.item_amount(session, item_id)
  return M.set_item_amount(session, item_id, current - clamp_int4(amount))
end

function M.gold_amount(session)
  return M.item_amount(session, GOLD_ITEM_ID)
end

function M.set_gold_amount(session, amount)
  return M.set_item_amount(session, GOLD_ITEM_ID, amount)
end

function M.item_def(self, item_id)
  local eif_blob = self:get_pub_blob("eif")
  local eif = eif_blob and eif_blob.parsed or nil
  return eif and (eif.by_id or {})[to_int(item_id, 0)] or nil
end

function M.list_items(session)
  local out = {}
  for item_id, amount in pairs(session.inventory or {}) do
    local id = to_int(item_id, 0)
    local normalized = clamp_int4(amount)
    if id > 0 and normalized > 0 then
      out[#out + 1] = {
        item_id = id,
        amount = normalized,
      }
    end
  end

  table.sort(out, function(a, b)
    return a.item_id < b.item_id
  end)
  return out
end

local function item_weight(self, item_id)
  local def = M.item_def(self, item_id)
  if not def then
    return 1
  end
  return clamp_char(def.weight or 0)
end

function M.total_weight(self, session)
  local total = 0
  for _, item in ipairs(M.list_items(session)) do
    total = total + item_weight(self, item.item_id) * item.amount
    if total > MAX_INT4 then
      total = MAX_INT4
      break
    end
  end
  return clamp_char(total)
end

function M.add_weight(reply, self, session)
  reply:add_int1(M.total_weight(self, session))
  reply:add_int1(clamp_char(session.max_weight or DEFAULT_MAX_WEIGHT))
end

local function slot_array_index(sub_loc)
  return clamp(to_int(sub_loc, 0), 0, 1) + 1
end

function M.resolve_slot_for_item(self, item_id, sub_loc)
  local def = M.item_def(self, item_id)
  if not def then
    return nil
  end

  local item_type = to_int(def.type, -1)
  if item_type == ITEM_TYPE.Weapon then
    return { key = "weapon" }
  end
  if item_type == ITEM_TYPE.Shield then
    return { key = "shield" }
  end
  if item_type == ITEM_TYPE.Armor then
    return { key = "armor" }
  end
  if item_type == ITEM_TYPE.Hat then
    return { key = "hat" }
  end
  if item_type == ITEM_TYPE.Boots then
    return { key = "boots" }
  end
  if item_type == ITEM_TYPE.Gloves then
    return { key = "gloves" }
  end
  if item_type == ITEM_TYPE.Accessory then
    return { key = "accessory" }
  end
  if item_type == ITEM_TYPE.Belt then
    return { key = "belt" }
  end
  if item_type == ITEM_TYPE.Necklace then
    return { key = "necklace" }
  end
  if item_type == ITEM_TYPE.Ring then
    return { key = "ring", index = slot_array_index(sub_loc) }
  end
  if item_type == ITEM_TYPE.Armlet then
    return { key = "armlet", index = slot_array_index(sub_loc) }
  end
  if item_type == ITEM_TYPE.Bracer then
    return { key = "bracer", index = slot_array_index(sub_loc) }
  end

  return nil
end

local function get_slot_item(session, slot)
  local equipment = session.paperdoll or default_equipment()
  if slot.index then
    return clamp_int4((equipment[slot.key] or {})[slot.index] or 0)
  end
  return clamp_int4(equipment[slot.key] or 0)
end

local function set_slot_item(session, slot, item_id)
  local equipment = normalize_equipment(session.paperdoll)
  if slot.index then
    local values = equipment[slot.key] or { 0, 0 }
    values[slot.index] = clamp_int4(item_id)
    equipment[slot.key] = values
  else
    equipment[slot.key] = clamp_int4(item_id)
  end
  session.paperdoll = equipment
end

function M.equip_item(self, session, item_id, sub_loc)
  local id = to_int(item_id, 0)
  if id <= 0 then
    return nil, "invalid_item"
  end
  if M.item_amount(session, id) <= 0 then
    return nil, "missing_item"
  end

  local slot = M.resolve_slot_for_item(self, id, sub_loc)
  if not slot then
    return nil, "not_equippable"
  end
  if get_slot_item(session, slot) ~= 0 then
    return nil, "slot_occupied"
  end

  M.remove_item(session, id, 1)
  set_slot_item(session, slot, id)
  session.equipment_graphics = M.visible_equipment_graphics(self, session)

  return {
    item_id = id,
    sub_loc = clamp(to_int(sub_loc, 0), 0, 1),
    remaining_amount = M.item_amount(session, id),
  }
end

function M.unequip_item(self, session, item_id, sub_loc)
  local id = to_int(item_id, 0)
  if id <= 0 then
    return nil, "invalid_item"
  end

  local slot = M.resolve_slot_for_item(self, id, sub_loc)
  if not slot then
    return nil, "not_equippable"
  end
  if get_slot_item(session, slot) ~= id then
    return nil, "not_equipped"
  end

  set_slot_item(session, slot, 0)
  M.add_item(session, id, 1)
  session.equipment_graphics = M.visible_equipment_graphics(self, session)

  return {
    item_id = id,
    sub_loc = clamp(to_int(sub_loc, 0), 0, 1),
    remaining_amount = M.item_amount(session, id),
  }
end

function M.welcome_equipment_item_ids(session)
  local equipment = normalize_equipment(session.paperdoll)
  return {
    equipment.boots,
    equipment.gloves,
    equipment.accessory,
    equipment.armor,
    equipment.belt,
    equipment.necklace,
    equipment.hat,
    equipment.shield,
    equipment.weapon,
    equipment.ring[1],
    equipment.ring[2],
    equipment.armlet[1],
    equipment.armlet[2],
    equipment.bracer[1],
    equipment.bracer[2],
  }
end

function M.paperdoll_equipment_item_ids(session)
  local equipment = normalize_equipment(session.paperdoll)
  return {
    equipment.boots,
    equipment.accessory,
    equipment.gloves,
    equipment.belt,
    equipment.armor,
    equipment.necklace,
    equipment.hat,
    equipment.shield,
    equipment.weapon,
    equipment.ring[1],
    equipment.ring[2],
    equipment.armlet[1],
    equipment.armlet[2],
    equipment.bracer[1],
    equipment.bracer[2],
  }
end

local function graphic_id_for_item(self, item_id)
  if to_int(item_id, 0) <= 0 then
    return 0
  end
  local def = M.item_def(self, item_id)
  -- Visible equipment packets use EIF spec1 (doll graphic), not graphic_id.
  local doll_graphic = to_int(def and def.spec1, 0)
  if doll_graphic <= 0 then
    return 0
  end
  return clamp(doll_graphic, 0, 64008)
end

function M.visible_equipment_graphics(self, session)
  local equipment = normalize_equipment(session.paperdoll)
  return {
    boots = graphic_id_for_item(self, equipment.boots),
    armor = graphic_id_for_item(self, equipment.armor),
    hat = graphic_id_for_item(self, equipment.hat),
    weapon = graphic_id_for_item(self, equipment.weapon),
    shield = graphic_id_for_item(self, equipment.shield),
  }
end

M.GOLD_ITEM_ID = GOLD_ITEM_ID

return M
