-- mGBA socket client (TCP)

local socket_module = rawget(_G, "socket")
if not socket_module then
  local ok, mod = pcall(require, "socket")
  if ok then socket_module = mod end
end

if not socket_module then
  error("PokeScan: socket module not available (mGBA build may lack sockets)")
end

local SocketClient = {}
SocketClient.__index = SocketClient

local function log(msg)
  if console and console.log then
    console:log(msg)
  else
    print(msg)
  end
end

local function error_name(code)
  if socket_module.ERRORS then
    for name, value in pairs(socket_module.ERRORS) do
      if value == code then
        return name
      end
    end
  end
  return tostring(code)
end

local frameCounter = 0
local FRAMES_PER_SECOND = 60

function SocketClient.new(opts)
  local self = setmetatable({}, SocketClient)
  self.host = opts.host or "127.0.0.1"
  self.port = opts.port or 9876
  self.reconnectIntervalFrames = (opts.reconnectInterval or 2) * FRAMES_PER_SECOND
  self.json = opts.json
  self.sock = nil
  self.connected = false
  self.lastConnectFrame = -9999
  self.errorCallbackId = nil
  return self
end

local function open_connection(host, port)
  if socket_module.connect then
    return socket_module.connect(host, port)
  end
  if socket_module.tcp then
    local s, err = socket_module.tcp()
    if not s then return nil, err end
    local result, connErr = s:connect(host, port)
    if result == nil then
      return nil, connErr
    end
    return s, nil
  end
  return nil, "NO_CONNECT_API"
end

function SocketClient:connect()
  if self.sock then
    self.sock:close()
    self.sock = nil
    self.connected = false
  end

  local sock, err = open_connection(self.host, self.port)
  if not sock then
    log("PokeScan: connect failed - " .. error_name(err))
    return false
  end

  self.sock = sock
  self.connected = true
  log("PokeScan: Connected to overlay at " .. self.host .. ":" .. self.port)

  if self.sock.add then
    self.errorCallbackId = self.sock:add("error", function(code)
      log("PokeScan: Socket error - " .. error_name(code))
      self.connected = false
      if self.sock then
        pcall(function() self.sock:close() end)
      end
      self.sock = nil
    end)
  end

  return true
end

function SocketClient:tick()
  frameCounter = frameCounter + 1
  if self.sock and self.sock.poll then
    self.sock:poll()
  end
end

function SocketClient:ensureConnected()
  if self.connected and self.sock then
    return true
  end

  if frameCounter - self.lastConnectFrame >= self.reconnectIntervalFrames then
    self.lastConnectFrame = frameCounter
    return self:connect()
  end
  return false
end

function SocketClient:sendTable(tbl)
  if not self:ensureConnected() then
    return false
  end

  local payload = self.json.encode(tbl) .. "\n"
  local result = self.sock:send(payload)
  if type(result) == "number" and result < 0 then
    log("PokeScan: send failed - " .. error_name(result))
    self.connected = false
    if self.sock then
      pcall(function() self.sock:close() end)
      self.sock = nil
    end
    return false
  end
  return true
end

return SocketClient
