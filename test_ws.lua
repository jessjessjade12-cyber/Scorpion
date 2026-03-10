-- Test WebSocket SHA-1 + base64 against RFC 6455 test vector (Lua 5.1 / BitOp)
local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local function rol32(x, n)
  return bor(lshift(x, n), rshift(band(x, 0xFFFFFFFF), 32 - n))
end

local function sha1(msg)
  local h0 = 0x67452301
  local h1 = 0xEFCDAB89
  local h2 = 0x98BADCFE
  local h3 = 0x10325476
  local h4 = 0xC3D2E1F0

  local bits = #msg * 8
  msg = msg .. "\x80"
  while (#msg % 64) ~= 56 do
    msg = msg .. "\x00"
  end
  msg = msg .. "\x00\x00\x00\x00" .. string.char(
    band(rshift(bits, 24), 0xFF),
    band(rshift(bits, 16), 0xFF),
    band(rshift(bits,  8), 0xFF),
    band(bits,             0xFF)
  )

  for i = 1, #msg, 64 do
    local w = {}
    for j = 0, 15 do
      local o = i + j * 4
      w[j] = bor(
        lshift(msg:byte(o)     or 0, 24),
        lshift(msg:byte(o + 1) or 0, 16),
        lshift(msg:byte(o + 2) or 0,  8),
               msg:byte(o + 3) or 0
      )
    end
    for j = 16, 79 do
      w[j] = rol32(bxor(w[j-3], w[j-8], w[j-14], w[j-16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for j = 0, 79 do
      local f, k
      if j < 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif j < 40 then
        f = bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif j < 60 then
        f = bor(band(b, c), band(b, d), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(b, c, d)
        k = 0xCA62C1D6
      end
      local t = band(rol32(a, 5) + f + e + k + w[j], 0xFFFFFFFF)
      e = d; d = c; c = rol32(b, 30); b = a; a = t
    end

    h0 = band(h0 + a, 0xFFFFFFFF)
    h1 = band(h1 + b, 0xFFFFFFFF)
    h2 = band(h2 + c, 0xFFFFFFFF)
    h3 = band(h3 + d, 0xFFFFFFFF)
    h4 = band(h4 + e, 0xFFFFFFFF)
  end

  local function w32(n)
    return string.char(
      band(rshift(n, 24), 0xFF),
      band(rshift(n, 16), 0xFF),
      band(rshift(n,  8), 0xFF),
      band(n,             0xFF)
    )
  end
  return w32(h0) .. w32(h1) .. w32(h2) .. w32(h3) .. w32(h4)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64enc(data)
  local out = {}
  local i = 1
  while i <= #data do
    local b1 = data:byte(i)     or 0
    local b2 = data:byte(i + 1) or 0
    local b3 = data:byte(i + 2) or 0
    local n  = lshift(b1, 16) + lshift(b2, 8) + b3
    local function ch(v) return B64:sub(v + 1, v + 1) end
    out[#out + 1] = ch(band(rshift(n, 18), 0x3F))
    out[#out + 1] = ch(band(rshift(n, 12), 0x3F))
    out[#out + 1] = (i + 1 <= #data) and ch(band(rshift(n, 6), 0x3F)) or "="
    out[#out + 1] = (i + 2 <= #data) and ch(band(n, 0x3F))            or "="
    i = i + 3
  end
  return table.concat(out)
end

local KEY    = "dGhlIHNhbXBsZSBub25jZQ=="
local GUID   = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local EXPECT = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

local result = b64enc(sha1(KEY .. GUID))

print("Result : " .. result)
print("Expect : " .. EXPECT)
if result == EXPECT then
  print("PASS - SHA-1 and base64 are correct")
else
  print("FAIL - SHA-1 or base64 is wrong!")
  local digest = sha1(KEY .. GUID)
  local hex = ""
  for i = 1, #digest do hex = hex .. string.format("%02X", digest:byte(i)) end
  print("SHA1 hex : " .. hex)
  print("Expected : B37A4F2CC0624F1690F64606CF385945B2BEC4EA")
end
