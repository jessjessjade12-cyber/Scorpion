local EOInt = require("scorpion.transport.eoint")

local Packet = {}
Packet.__index = Packet

function Packet.new(family, action, data)
  return setmetatable({
    family = family or 0,
    action = action or 0,
    data = data or "",
  }, Packet)
end

function Packet:discard(count)
  self.data = self.data:sub((count or 1) + 1)
end

function Packet:add_byte(v)
  self.data = self.data .. string.char(v)
end

function Packet:add_int1(v)
  self.data = self.data .. EOInt.unpack(v):sub(1, 1)
end

function Packet:add_int2(v)
  self.data = self.data .. EOInt.unpack(v):sub(1, 2)
end

function Packet:add_int3(v)
  self.data = self.data .. EOInt.unpack(v):sub(1, 3)
end

function Packet:add_int4(v)
  self.data = self.data .. EOInt.unpack(v)
end

function Packet:add_break_string(v)
  self.data = self.data .. (v or "") .. string.char(255)
end

function Packet:add_string(v)
  self.data = self.data .. (v or "")
end

function Packet:get_byte()
  if #self.data == 0 then
    return 0
  end

  local value = self.data:byte(1)
  self.data = self.data:sub(2)
  return value
end

function Packet:get_int1()
  if #self.data == 0 then
    return 0
  end

  return EOInt.pack(self:get_byte())
end

function Packet:get_int2()
  if #self.data == 0 then
    return 0
  end

  if #self.data < 2 then
    return self:get_int1()
  end

  local b1 = self.data:byte(1)
  local b2 = self.data:byte(2)
  self.data = self.data:sub(3)
  return EOInt.pack(b1, b2)
end

function Packet:get_int3()
  if #self.data == 0 then
    return 0
  end

  if #self.data < 2 then
    return self:get_int1()
  end

  if #self.data < 3 then
    return self:get_int2()
  end

  local b1 = self.data:byte(1)
  local b2 = self.data:byte(2)
  local b3 = self.data:byte(3)
  self.data = self.data:sub(4)
  return EOInt.pack(b1, b2, b3)
end

function Packet:get_int4()
  if #self.data == 0 then
    return 0
  end

  if #self.data < 2 then
    return self:get_int1()
  end

  if #self.data < 3 then
    return self:get_int2()
  end

  if #self.data < 4 then
    return self:get_int3()
  end

  local b1 = self.data:byte(1)
  local b2 = self.data:byte(2)
  local b3 = self.data:byte(3)
  local b4 = self.data:byte(4)
  self.data = self.data:sub(5)
  return EOInt.pack(b1, b2, b3, b4)
end

function Packet:get_break_string()
  local index = self.data:find(string.char(255), 1, true)

  if not index then
    local out = self.data
    self.data = ""
    return out
  end

  local out = self.data:sub(1, index - 1)
  self.data = self.data:sub(index + 1)
  return out
end

function Packet:get_string(length_or_nil)
  if length_or_nil == nil or length_or_nil == -1 then
    local out = self.data
    self.data = ""
    return out
  end

  local out = self.data:sub(1, length_or_nil)
  self.data = self.data:sub(length_or_nil + 1)
  return out
end

return Packet
