local socket    = require("socket")
local Packet    = require("scorpion.transport.packet")
local Protocol  = require("scorpion.transport.protocol")
local WebSocket = require("scorpion.transport.websocket")

local Family = Protocol.Family
local Action = Protocol.Action

local NetServer = {}
NetServer.__index = NetServer

local function make_addr(ip, port)
  return ("%s:%s"):format(ip or "unknown", tostring(port or "0"))
end

function NetServer.new(deps)
  local settings = deps.settings

  return setmetatable({
    clients            = {},
    codec              = deps.codec,
    host               = settings.host,
    logger             = deps.logger,
    next_connection_id = 1,
    packet_flow        = ((settings.logging or {}).packet_flow ~= false),
    ping_seconds       = settings.net.ping_seconds,
    repeat_max         = settings.net.sequence_repeat_max,
    running            = false,
    server             = deps.server,
    sleep_seconds      = (settings.net.tick_sleep_ms or 20) / 1000,
    next_arena_tick    = 0,
    tcp                = nil,
    ws_tcp             = nil,
    ws_port            = (settings.net or {}).websocket_port,
  }, NetServer)
end

function NetServer:log(level, message, fields)
  if not self.logger then
    return
  end

  if level == "error" then
    self.logger:error(message, fields)
  elseif level == "warn" then
    self.logger:warn(message, fields)
  else
    self.logger:info(message, fields)
  end
end

function NetServer:open()
  local tcp, err = socket.bind(self.host, self.server.settings.port)
  if not tcp then
    return nil, err
  end
  tcp:settimeout(0)
  self.tcp = tcp

  if self.ws_port then
    local ws_tcp, ws_err = socket.bind(self.host, self.ws_port)
    if not ws_tcp then
      pcall(tcp.close, tcp)
      self.tcp = nil
      return nil, ("websocket bind failed: %s"):format(ws_err)
    end
    ws_tcp:settimeout(0)
    self.ws_tcp = ws_tcp
    self:log("info", "websocket listener ready", { host = self.host, port = self.ws_port })
  end

  self.running = true
  return true
end

function NetServer:shutdown(reason)
  self.running = false

  local keys = {}
  for key in pairs(self.clients) do
    keys[#keys + 1] = key
  end

  for _, key in ipairs(keys) do
    local client = self.clients[key]
    if client then
      self:close_client(client, reason or "server shutdown")
    end
  end

  if self.tcp ~= nil then
    pcall(self.tcp.close, self.tcp)
    self.tcp = nil
  end

  if self.ws_tcp ~= nil then
    pcall(self.ws_tcp.close, self.ws_tcp)
    self.ws_tcp = nil
  end

  self:log("info", "listener stopped", { reason = reason or "shutdown" })
end

function NetServer:close_client(client, reason)
  local session = self.server.world:find_session_by_address(client.context.address)
  if session then
    if self.server.save_session then
      self.server:save_session(session, "disconnect")
    end

    local runner = self.server.world.arena_script_runner
    if runner and runner.clear_session_proxy then
      local ok_clear, clear_err = pcall(runner.clear_session_proxy, runner, session, "disconnect")
      if not ok_clear then
        self:log("warn", "arena script proxy clear failed", {
          address = client.context.address,
          error = tostring(clear_err),
          session_id = session.id or 0,
        })
      end
    end
    session.connected = false
    self.server.world:remove_session(session.id)
  end

  self:log("warn", "client disconnected", {
    address    = client.context.address,
    reason     = reason or "closed",
    session_id = session and session.id or 0,
  })

  pcall(client.sock.close, client.sock)
  self.clients[client.context.address] = nil
end

function NetServer:send_packet(client, packet)
  local wire = self.codec.encode(packet, client.context, packet and packet.force_raw)

  if client.context.ws_ready then
    wire = WebSocket.encode_frame(wire)
  end

  local index = 1
  while index <= #wire do
    local sent, err, partial = client.sock:send(wire, index)
    if sent then
      index = sent + 1
    elseif err == "timeout" and partial and partial >= index then
      index = partial + 1
    else
      return nil, err
    end
  end

  return true
end

function NetServer:flush_world_pending()
  local pending = self.server.world:flush_pending()
  for _, entry in ipairs(pending) do
    local target = self.clients[entry.address]
    if target then
      if self.packet_flow then
        self:log("info", "packet send pending", {
          address = entry.address,
          family = entry.packet and entry.packet.family or 0,
          action = entry.packet and entry.packet.action or 0,
          size = entry.packet and #entry.packet.data or 0,
        })
      end
      self:send_packet(target, entry.packet)
    end
  end
end

function NetServer:dispatch_packet(client, packet)
  if self.packet_flow then
    self:log("info", "packet recv", {
      address     = client.context.address,
      family      = packet.family,
      action      = packet.action,
      size        = #packet.data,
      initialized = tostring(client.context.initialized),
    })
  end

  local response, err = self.server:dispatch(packet, client.context)
  if not response then
    self:log("warn", "dispatch rejected", {
      address = client.context.address,
      family  = packet.family,
      action  = packet.action,
      error   = err or "unknown",
    })
    return nil, err
  end

  local sent, send_err
  if getmetatable(response) == Packet then
    if self.packet_flow then
      self:log("info", "packet send", {
        address = client.context.address,
        family  = response.family,
        action  = response.action,
        size    = #response.data,
      })
    end
    sent, send_err = self:send_packet(client, response)
  else
    sent = true
  end

  self:flush_world_pending()

  return sent, send_err
end

function NetServer:handle_sequence(client, packet)
  if packet.family == Family.Raw then
    return true
  end

  local seq = packet:get_byte()
  if not client.context.initialized then
    return true
  end

  if seq == client.context.sequence_last then
    client.context.sequence_count = (client.context.sequence_count or 0) + 1
    if client.context.sequence_count > self.repeat_max then
      return nil, "sequence repeat limit"
    end
  else
    client.context.sequence_count = 0
  end

  client.context.sequence_last  = seq
  return true
end

function NetServer:tick_ping(client, now)
  -- Don't ping WS clients until the HTTP upgrade is complete
  if client.context.ws and not client.context.ws_ready then
    return true
  end

  if now < (client.context.ping_due or 0) then
    return true
  end

  if not client.context.ping_replied then
    return nil, "ping timeout"
  end

  client.context.ping_replied = false
  client.context.ping_due     = now + self.ping_seconds

  -- Keep ping sequence start in one-byte range because handle_sequence currently
  -- consumes a single sequence byte from incoming packets.
  local ping_sequence_start = math.random(0, 240)
  local seq2 = math.random(0, 252)
  local seq1 = ping_sequence_start + seq2
  client.context.sequence_start = ping_sequence_start

  local ping = Packet.new(Family.Connection, Action.Player)
  ping:add_int2(seq1)
  ping:add_int1(seq2)
  return self:send_packet(client, ping)
end

function NetServer:process_buffer(client)
  while #client.buffer >= 2 do
    local packet, rest = self.codec.decode(client.buffer, client.context)
    if not packet then
      if rest == "incomplete packet" then
        return true
      end
      return nil, ("decode failed: %s"):format(rest or "unknown")
    end

    client.buffer = rest or ""

    local ok, seq_err = self:handle_sequence(client, packet)
    if not ok then
      return nil, seq_err
    end

    local sent, dispatch_err = self:dispatch_packet(client, packet)
    if not sent then
      return nil, dispatch_err
    end

    if packet.family == Family.Raw and packet.action == Action.Raw then
      client.context.raw = false
    end
  end

  return true
end

-- Complete the WebSocket HTTP upgrade handshake.
function NetServer:ws_do_handshake(client)
  local response, rest = WebSocket.handshake(client.buffer)

  if response == nil and rest == nil then
    return true  -- incomplete request, keep buffering
  end

  if response == nil then
    return nil, ("ws handshake failed: %s"):format(rest or "unknown")
  end

  local _, send_err = client.sock:send(response)
  if send_err then
    return nil, ("ws handshake send failed: %s"):format(send_err)
  end

  client.context.ws_ready = true
  -- Keep any bytes that arrived after the HTTP headers
  client.buffer    = rest or ""
  client.ws_eo_buf = ""
  self:log("info", "websocket upgraded", { address = client.context.address })
  return true
end

-- Strip WebSocket frames from client.buffer, accumulate EO payload in
-- client.ws_eo_buf, then run those bytes through the normal EO codec.
function NetServer:ws_process(client)
  while #client.buffer >= 2 do
    local payload, rest = WebSocket.decode_frame(client.buffer)

    if payload == nil then
      if rest == "incomplete" then
        break
      end
      return nil, ("ws frame error: %s"):format(rest or "unknown")
    end

    client.ws_eo_buf = client.ws_eo_buf .. payload
    client.buffer    = rest
  end

  if #client.ws_eo_buf < 2 then
    return true
  end

  -- Swap in the decoded EO bytes, run through the codec, then restore
  local ws_remainder   = client.buffer
  client.buffer        = client.ws_eo_buf
  local ok, err        = self:process_buffer(client)
  client.ws_eo_buf     = client.buffer  -- any partial EO packet leftover
  client.buffer        = ws_remainder
  return ok, err
end

function NetServer:read_client(client)
  local data, err, partial = client.sock:receive(8192)
  local chunk = data or partial

  if chunk and #chunk > 0 then
    client.buffer = client.buffer .. chunk

    if client.context.ws then
      if not client.context.ws_ready then
        return self:ws_do_handshake(client)
      end
      return self:ws_process(client)
    end

    return self:process_buffer(client)
  end

  if err == "closed" then
    return nil, "closed"
  end

  return true
end

local function make_client(sock, addr, connection_id, ping_due, ws)
  return {
    buffer   = "",
    ws_eo_buf = ws and "" or nil,
    sock     = sock,
    context  = {
      address          = addr,
      connection_id    = connection_id,
      initialized      = false,
      ping_due         = ping_due,
      ping_replied     = true,
      raw              = true,
      receive_key      = 10,
      send_key         = 10,
      sequence_count   = 0,
      sequence_last    = 0,
      sequence_start   = 0,
      ws               = ws or false,
      ws_ready         = false,
    },
  }
end

function NetServer:accept_new()
  local now = socket.gettime()

  -- Standard TCP
  local sock = self.tcp:accept()
  if sock then
    sock:settimeout(0)
    local ip, port = sock:getpeername()
    local addr = make_addr(ip, port)
    self.clients[addr] = make_client(sock, addr, self.next_connection_id, now + self.ping_seconds, false)
    self:log("info", "client accepted", { address = addr, connection_id = self.next_connection_id })
    self.next_connection_id = self.next_connection_id + 1
  end

  -- WebSocket TCP (HTTP upgrade pending)
  if self.ws_tcp then
    local ws_sock = self.ws_tcp:accept()
    if ws_sock then
      ws_sock:settimeout(0)
      local ip, port = ws_sock:getpeername()
      local addr = make_addr(ip, port)
      self.clients[addr] = make_client(ws_sock, addr, self.next_connection_id, now + self.ping_seconds, true)
      self:log("info", "ws client accepted", { address = addr, connection_id = self.next_connection_id })
      self.next_connection_id = self.next_connection_id + 1
    end
  end
end

function NetServer:run_forever()
  while self.running do
    local arena_now = socket.gettime()
    if arena_now >= (self.next_arena_tick or 0) then
      self.next_arena_tick = arena_now + 1
      local winner = self.server.world:tick_arena()
      if winner then
        self:log("info", "arena round over", {
          winner = winner.account or "unknown",
          kills  = winner.arena_kills or 0,
        })
      end

      local runner = self.server.world.arena_script_runner
      if runner and runner.tick then
        local ok_tick, tick_err = pcall(runner.tick, runner)
        if not ok_tick then
          self:log("warn", "arena script tick failed", { error = tostring(tick_err) })
        end
      end
    end

    local ok_npc, npc_err = pcall(self.server.world.tick_npcs, self.server.world, arena_now)
    if not ok_npc then
      self:log("warn", "npc movement tick failed", { error = tostring(npc_err) })
    end

    -- Build the select read list: listener sockets + all client sockets
    local read_list = { self.tcp }
    if self.ws_tcp then
      read_list[#read_list + 1] = self.ws_tcp
    end
    local sock_to_addr = {}
    for addr, client in pairs(self.clients) do
      read_list[#read_list + 1] = client.sock
      sock_to_addr[client.sock] = addr
    end

    -- Block until a socket is readable (up to one tick)
    local readable = socket.select(read_list, nil, self.sleep_seconds)

    local now = socket.gettime()

    for _, sock in ipairs(readable) do
      if sock == self.tcp or sock == self.ws_tcp then
        self:accept_new()
      else
        local addr   = sock_to_addr[sock]
        local client = addr and self.clients[addr]
        if client then
          local ok_read, read_err = self:read_client(client)
          if not ok_read then
            self:close_client(client, read_err or "read failed")
          end
        end
      end
    end

    -- Ping check runs for all clients every tick regardless of select
    local keys = {}
    for key in pairs(self.clients) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
      local client = self.clients[key]
      if client then
        local ok_ping, ping_err = self:tick_ping(client, now)
        if not ok_ping then
          self:close_client(client, ping_err or "ping failed")
        end
      end
    end

    self:flush_world_pending()
  end

  return true
end

return NetServer
