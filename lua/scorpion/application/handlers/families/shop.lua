local Packet = require("scorpion.transport.packet")
local Protocol = require("scorpion.transport.protocol")
local InventoryState = require("scorpion.application.handlers.support.inventory_state")
local util = require("scorpion.util")

local Family = Protocol.Family
local Action = Protocol.Action
local clamp = util.clamp

local MAX_INT4 = 4097152080
local NPC_TYPE_SHOP = 6

local M = {}

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

local function ensure_shop_state(self, session)
  InventoryState.ensure(self, session)
end

local function item_amount(session, item_id)
  return InventoryState.item_amount(session, item_id)
end

local function add_item(session, item_id, amount)
  return InventoryState.add_item(session, item_id, amount)
end

local function remove_item(session, item_id, amount)
  return InventoryState.remove_item(session, item_id, amount)
end

local function add_weight(reply, self, session)
  InventoryState.add_weight(reply, self, session)
end

local function find_trade(shop, item_id)
  for _, trade in ipairs((shop and shop.trades) or {}) do
    if to_int(trade.item_id, 0) == item_id then
      return trade
    end
  end
  return nil
end

local function get_map_npc(world, map_id, npc_index)
  local map = world:get_map_meta(map_id)
  if map == nil then
    return nil
  end
  local npcs = map.npcs or {}
  return npcs[npc_index]
end

local function get_npc_def(self, npc_id)
  local enf_blob = self:get_pub_blob("enf")
  local enf = enf_blob and enf_blob.parsed or nil
  return enf and (enf.by_id or {})[npc_id] or nil
end

local function resolve_shop_for_open(self, session, npc_index)
  local map_npc = get_map_npc(self.world, session.map_id, npc_index)
  if not map_npc then
    return nil
  end

  local npc_def = get_npc_def(self, map_npc.id)
  local behavior_id = nil

  if npc_def then
    if to_int(npc_def.type, -1) ~= NPC_TYPE_SHOP then
      return nil
    end
    behavior_id = to_int(npc_def.behavior_id, 0)
  else
    -- Fallback for malformed/missing ENF: treat map NPC id as behavior id.
    behavior_id = to_int(map_npc.id, 0)
  end

  if behavior_id <= 0 then
    return nil
  end

  local shop = self.world:find_shop_by_behavior_id(behavior_id)
  if not shop then
    -- Compatibility with legacy text shop DBs keyed by NPC id.
    local legacy_id = to_int(map_npc.id, 0)
    if legacy_id > 0 then
      shop = self.world:find_shop_by_behavior_id(legacy_id)
      if shop then
        behavior_id = legacy_id
      end
    end
  end
  if not shop then
    return nil
  end

  return {
    behavior_id = behavior_id,
    npc_index = npc_index,
    shop = shop,
  }
end

local function build_open_reply(shop_session_id, shop)
  local reply = Packet.new(Family.Shop, Action.Open)
  reply:add_int2(shop_session_id)
  reply:add_string(shop.name or "")
  reply:add_byte(255)

  for _, trade in ipairs(shop.trades or {}) do
    reply:add_int2(to_int(trade.item_id, 0))
    reply:add_int3(clamp_int4(trade.buy_price))
    reply:add_int3(clamp_int4(trade.sell_price))
    reply:add_int1(clamp_char(trade.max_amount))
  end

  -- Empty craft list for now: open/buy/sell only.
  reply:add_byte(255)
  return reply
end

local function clear_shop_context(session)
  session.shop_context = nil
end

local function valid_shop_session(session, session_id)
  local context = session.shop_context
  if context == nil then
    return false
  end
  if to_int(context.session_id, -1) ~= to_int(session_id, -2) then
    return false
  end
  if to_int(context.map_id, -1) ~= to_int(session.map_id, -2) then
    return false
  end
  return true
end

function M.handle(self, packet, context)
  local session = self:get_session(context)
  if not session then
    return nil, "shop before login"
  end
  if not (session.character_id and session.character_id > 0) then
    return true
  end

  ensure_shop_state(self, session)

  if packet.action == Action.Open then
    local npc_index = to_int(packet:get_int2(), 0)
    if npc_index <= 0 then
      clear_shop_context(session)
      return true
    end

    local resolved = resolve_shop_for_open(self, session, npc_index)
    if not resolved then
      clear_shop_context(session)
      return true
    end

    local shop_session_id = math.random(10, 64008)
    session.shop_context = {
      behavior_id = resolved.behavior_id,
      map_id = session.map_id,
      npc_index = resolved.npc_index,
      session_id = shop_session_id,
    }

    return build_open_reply(shop_session_id, resolved.shop)
  end

  if packet.action == Action.Buy then
    local item_id = to_int(packet:get_int2(), 0)
    local amount = clamp_int4(packet:get_int4())
    local shop_session_id = packet:get_int4()
    if item_id <= 0 or amount <= 0 then
      return true
    end
    if not valid_shop_session(session, shop_session_id) then
      return true
    end

    local context_data = session.shop_context or {}
    local shop = self.world:find_shop_by_behavior_id(context_data.behavior_id)
    if not shop then
      clear_shop_context(session)
      return true
    end

    local trade = find_trade(shop, item_id)
    if not trade then
      return true
    end

    local buy_price = clamp_int4(trade.buy_price)
    local max_amount = clamp_char(trade.max_amount)
    if buy_price <= 0 or max_amount <= 0 then
      return true
    end

    amount = math.min(amount, max_amount)
    local total_cost = clamp_int4(buy_price * amount)
    local gold = InventoryState.gold_amount(session)
    if gold < total_cost then
      return true
    end

    InventoryState.set_gold_amount(session, gold - total_cost)
    add_item(session, item_id, amount)

    local reply = Packet.new(Family.Shop, Action.Buy)
    reply:add_int4(InventoryState.gold_amount(session))
    reply:add_int2(item_id)
    reply:add_int4(amount)
    add_weight(reply, self, session)
    return reply
  end

  if packet.action == Action.Sell then
    local item_id = to_int(packet:get_int2(), 0)
    local amount = clamp_int4(packet:get_int4())
    local shop_session_id = packet:get_int4()
    if item_id <= 0 or amount <= 0 then
      return true
    end
    if not valid_shop_session(session, shop_session_id) then
      return true
    end

    local context_data = session.shop_context or {}
    local shop = self.world:find_shop_by_behavior_id(context_data.behavior_id)
    if not shop then
      clear_shop_context(session)
      return true
    end

    local trade = find_trade(shop, item_id)
    if not trade then
      return true
    end

    local sell_price = clamp_int4(trade.sell_price)
    if sell_price <= 0 then
      return true
    end

    local owned = item_amount(session, item_id)
    if owned <= 0 then
      return true
    end

    amount = math.min(amount, owned)
    if amount <= 0 then
      return true
    end

    remove_item(session, item_id, amount)
    local total_value = clamp_int4(sell_price * amount)
    InventoryState.set_gold_amount(session, InventoryState.gold_amount(session) + total_value)

    local reply = Packet.new(Family.Shop, Action.Sell)
    reply:add_int4(amount)
    reply:add_int2(item_id)
    reply:add_int4(InventoryState.gold_amount(session))
    add_weight(reply, self, session)
    return reply
  end

  return true
end

return M
