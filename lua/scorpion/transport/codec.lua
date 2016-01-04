local EOInt = require("scorpion.transport.eoint")
local Packet = require("scorpion.transport.packet")
local bit = require("bit")

local Codec = {}
local bxor = bit.bxor

local function fold_data(str, key)
  if key == nil or key == 0 then
    return str
  end

  local out = {}
  local buffer = {}

  for i = 1, #str do
    local byte = str:byte(i)
    if (byte % key) == 0 then
      buffer[#buffer + 1] = string.char(byte)
    else
      for j = #buffer, 1, -1 do
        out[#out + 1] = buffer[j]
      end

      buffer = {}
      out[#out + 1] = string.char(byte)
    end
  end

  for j = #buffer, 1, -1 do
    out[#out + 1] = buffer[j]
  end

  return table.concat(out)
end

local function swap_0_128(str)
  local out = {}

  for i = 1, #str do
    local byte = str:byte(i)
    if byte == 128 then
      byte = 0
    elseif byte == 0 then
      byte = 128
    end

    out[i] = string.char(byte)
  end

  return table.concat(out)
end

local function obfuscate(str)
  local size = #str
  if size == 0 then
    return str
  end

  local out = {}
  out[1] = str:sub(1, 1)
  out[2] = str:sub(2, 2)

  local i = 2
  local j = 2

  while i < size do
    out[i + 1] = string.char(bxor((str:byte(j + 1) or 0), 128))
    j = j + 1
    i = i + 2
  end

  i = size - 1
  if (size % 2) == 1 then
    i = i - 1
  end

  while i >= 2 do
    out[i + 1] = string.char(bxor((str:byte(j + 1) or 0), 128))
    j = j + 1
    i = i - 2
  end

  if size >= 3 then
    local tail = table.concat(out, "", 3, size)
    tail = swap_0_128(tail)
    for k = 1, #tail do
      out[k + 2] = tail:sub(k, k)
    end
  end

  return table.concat(out)
end

local function deobfuscate(str)
  local out = {}
  local i = 1

  while i <= #str do
    out[#out + 1] = string.char(bxor(str:byte(i), 128))
    i = i + 2
  end

  i = i - 1
  if (#str % 2) == 1 then
    i = i - 2
  end

  while i > 0 do
    out[#out + 1] = string.char(bxor(str:byte(i), 128))
    i = i - 2
  end

  local decoded = table.concat(out)
  if #decoded >= 3 then
    decoded = decoded:sub(1, 2) .. swap_0_128(decoded:sub(3))
  end

  return decoded
end

function Codec.decode(wire, state)
  if #wire < 2 then
    return nil, "packet header too short"
  end

  local size = EOInt.pack(wire:byte(1), wire:byte(2))
  if #wire < (size + 2) then
    return nil, "incomplete packet"
  end

  local payload = wire:sub(3, size + 2)
  local rest = wire:sub(size + 3)

  if state and state.initialized then
    payload = fold_data(deobfuscate(payload), state.receive_key or 0)
  end

  if #payload < 2 then
    return nil, "packet payload too short"
  end

  local packet = Packet.new(
    payload:byte(2),
    payload:byte(1),
    payload:sub(3)
  )

  return packet, rest
end

function Codec.encode(packet, state, force_raw)
  local encoded = EOInt.unpack(#packet.data + 2):sub(1, 2) ..
    string.char(packet.action, packet.family) ..
    packet.data

  local no_obfuscate = force_raw or (packet and packet.force_raw)
  if state and state.initialized and (not state.raw) and (not no_obfuscate) then
    encoded = obfuscate(fold_data(encoded, state.send_key or 0))
  end

  return encoded
end

return Codec
