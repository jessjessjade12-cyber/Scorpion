local ShopDb = require("scorpion.infrastructure.shop_db")

local M = {}

function M.attach_shop_db(self, shop_db)
  self.shop_db = shop_db or ShopDb.empty()
end

function M.find_shop_by_behavior_id(self, behavior_id)
  return ShopDb.find_by_behavior_id(self.shop_db, behavior_id)
end

function M.list_shops(self)
  local db = self.shop_db or ShopDb.empty()
  return db.shops or {}
end

function M.shop_count(self)
  return #self:list_shops()
end

return M
