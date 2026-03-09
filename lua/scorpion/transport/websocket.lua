local bit    = require("bit")
local sha1lib = require("scorpion.transport.sha1")
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift  = bit.lshift, bit.rshift

local WebSocket = {}

local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

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

-- Attempt HTTP/1.1 upgrade handshake.
-- Returns:
--   nil             — incomplete request, need more data
--   nil, err        — malformed request (close connection)
--   response, rest  — HTTP 101 response to send; rest is any bytes after the headers
function WebSocket.handshake(buffer)
  local eoh = buffer:find("\r\n\r\n", 1, true)
  if not eoh then
    return nil
  end

  local key = buffer:match("Sec%-WebSocket%-Key:%s*([^\r\n]+)")
  if not key then
    return nil, "missing Sec-WebSocket-Key"
  end
  key = key:match("^%s*(.-)%s*$")

  local accept   = b64enc(sha1lib.binary(key .. WS_GUID))
  local response = table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. accept,
    "", "",
  }, "\r\n")

  return response, buffer:sub(eoh + 4)
end

-- Decode one WebSocket frame from buffer.
-- Returns:
--   nil, "incomplete" — not enough data yet
--   nil, "closed"     — received a close frame
--   payload, rest     — binary payload bytes and remaining buffer
function WebSocket.decode_frame(buffer)
  if #buffer < 2 then
    return nil, "incomplete"
  end

  local b0     = buffer:byte(1)
  local b1     = buffer:byte(2)
  local opcode = band(b0, 0x0F)
  local masked = band(rshift(b1, 7), 1) == 1
  local plen7  = band(b1, 0x7F)

  if opcode == 8 then
    return nil, "closed"
  end

  -- Compute extended payload length
  local payload_len
  local after_len  -- 1-indexed position immediately after the length field
  if plen7 <= 125 then
    if #buffer < 2 then return nil, "incomplete" end
    payload_len = plen7
    after_len   = 3
  elseif plen7 == 126 then
    if #buffer < 4 then return nil, "incomplete" end
    payload_len = bor(lshift(buffer:byte(3), 8), buffer:byte(4))
    after_len   = 5
  else -- 127
    if #buffer < 10 then return nil, "incomplete" end
    payload_len = bor(
      lshift(buffer:byte(7), 24),
      lshift(buffer:byte(8), 16),
      lshift(buffer:byte(9),  8),
             buffer:byte(10)
    )
    after_len = 11
  end

  local data_start = after_len + (masked and 4 or 0)
  local data_end   = data_start - 1 + payload_len

  if #buffer < data_end then
    return nil, "incomplete"
  end

  local rest    = buffer:sub(data_end + 1)
  local payload = buffer:sub(data_start, data_end)

  if masked then
    local m = { buffer:byte(after_len, after_len + 3) }
    local unm = {}
    for j = 1, #payload do
      unm[j] = string.char(bxor(payload:byte(j), m[((j - 1) % 4) + 1]))
    end
    payload = table.concat(unm)
  end

  -- Skip non-binary/continuation frames (ping, pong, text) without error
  if opcode ~= 2 and opcode ~= 0 then
    return "", rest
  end

  return payload, rest
end

-- Encode data as a WebSocket binary frame (server-to-client, unmasked).
function WebSocket.encode_frame(data)
  local len = #data
  if len <= 125 then
    return string.char(0x82, len) .. data
  elseif len <= 65535 then
    return string.char(0x82, 126, rshift(len, 8), band(len, 0xFF)) .. data
  else
    return string.char(
      0x82, 127, 0, 0, 0, 0,
      band(rshift(len, 24), 0xFF),
      band(rshift(len, 16), 0xFF),
      band(rshift(len,  8), 0xFF),
      band(len,             0xFF)
    ) .. data
  end
end

return WebSocket
