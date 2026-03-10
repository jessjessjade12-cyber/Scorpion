local M = {}

local function empty_shop_db()
  return {
    by_behavior_id = {},
    shops = {},
  }
end

function M.attach_shop_db(self, shop_db)
  self.shop_db = type(shop_db) == "table" and shop_db or empty_shop_db()
end

function M.find_shop_by_behavior_id(self, behavior_id)
  local id = tonumber(behavior_id)
  local db = self.shop_db or empty_shop_db()
  local index = db.by_behavior_id or {}
  if id == nil then
    return nil
  end
  return index[id]
end

function M.list_shops(self)
  local db = self.shop_db or empty_shop_db()
  return db.shops or {}
end

function M.shop_count(self)
  return #self:list_shops()
end

return M
