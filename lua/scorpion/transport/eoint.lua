local EOInt = {}

local INT1_MAX = 253
local INT2_MAX = 64009
local INT3_MAX = 16194277

function EOInt.pack(b1, b2, b3, b4)
  b1 = b1 or 0
  b2 = b2 or 0
  b3 = b3 or 0
  b4 = b4 or 0

  if b1 == 254 then b1 = 0 elseif b1 > 0 then b1 = b1 - 1 end
  if b2 == 254 then b2 = 0 elseif b2 > 0 then b2 = b2 - 1 end
  if b3 == 254 then b3 = 0 elseif b3 > 0 then b3 = b3 - 1 end
  if b4 == 254 then b4 = 0 elseif b4 > 0 then b4 = b4 - 1 end

  return (b4 * INT3_MAX) + (b3 * INT2_MAX) + (b2 * INT1_MAX) + b1
end

function EOInt.unpack(num)
  local out = { 254, 254, 254, 254 }
  local value = num or 0
  local original = value

  if original >= INT3_MAX then
    out[4] = math.floor(value / INT3_MAX) + 1
    value = value % INT3_MAX
  end

  if original >= INT2_MAX then
    out[3] = math.floor(value / INT2_MAX) + 1
    value = value % INT2_MAX
  end

  if original >= INT1_MAX then
    out[2] = math.floor(value / INT1_MAX) + 1
    value = value % INT1_MAX
  end

  out[1] = value + 1
  return string.char(out[1], out[2], out[3], out[4])
end

return EOInt
