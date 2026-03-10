local M = {}

function M.get_blob(world, key)
  return ((world.pub or {}).client or {})[key]
end

function M.add_rid(reply, data)
  if data == nil or #data < 7 then
    reply:add_byte(0)
    reply:add_byte(0)
    reply:add_byte(0)
    reply:add_byte(0)
    return
  end

  reply:add_byte(data:byte(4))
  reply:add_byte(data:byte(5))
  reply:add_byte(data:byte(6))
  reply:add_byte(data:byte(7))
end

function M.add_meta(reply, blob)
  local data = blob and blob.data or nil
  M.add_rid(reply, data)
  if data == nil or #data < 9 then
    reply:add_byte(0)
    reply:add_byte(0)
    return
  end

  reply:add_byte(data:byte(8))
  reply:add_byte(data:byte(9))
end

return M
