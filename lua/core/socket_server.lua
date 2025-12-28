-- PokeScan Socket Server for mGBA
-- Uses socket.bind() as FUNCTION (not method) per mGBA API

local SocketServer = {}
SocketServer.__index = SocketServer

-- File logging for automated testing
local LOG_FILE = nil
local function initLogFile()
  if LOG_FILE then return end
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == '@' then source = source:sub(2) end
  local scriptDir = source:match("(.*/)") or "./"
  local logPath = scriptDir .. "../../dev/logs/lua.log"
  LOG_FILE = io.open(logPath, "w")
  if LOG_FILE then
    LOG_FILE:setvbuf("line")  -- Line buffered for real-time reading
  end
end

local function log(msg)
  local timestamp = os.date("%H:%M:%S")
  local formatted = string.format("[%s] %s", timestamp, msg)

  -- Console output
  if console and console.log then
    console:log(msg)
  else
    print(msg)
  end

  -- File output
  initLogFile()
  if LOG_FILE then
    LOG_FILE:write(formatted .. "\n")
    LOG_FILE:flush()
  end
end

function SocketServer.new(opts)
  local self = setmetatable({}, SocketServer)
  self.port = opts.port or 9876
  self.json = opts.json
  self.server = nil
  self.client = nil
  self.started = false
  self.failed = false
  self.retryCount = 0
  self.maxRetries = 10
  self.justConnected = false  -- Flag to trigger resend on new connection
  return self
end

function SocketServer:start()
  if self.started or self.failed then
    return self.started
  end

  -- socket.bind() is a FUNCTION that creates AND binds a socket
  -- Pass nil for address to bind to all interfaces (0.0.0.0)
  local server, err = socket.bind(nil, self.port)

  if not server then
    if err == socket.ERRORS.ADDRESS_IN_USE then
      self.retryCount = self.retryCount + 1
      if self.retryCount <= self.maxRetries then
        log("PokeScan: Port " .. self.port .. " in use, trying " .. (self.port + 1))
        self.port = self.port + 1
        return self:start()
      else
        log("PokeScan: Max retries reached, giving up")
        self.failed = true
        return false
      end
    end
    log("PokeScan: Failed to bind - " .. tostring(err))
    self.failed = true
    return false
  end

  self.server = server

  -- Start listening for connections (backlog of 1)
  local listenResult = self.server:listen(1)
  if listenResult and listenResult < 0 then
    log("PokeScan: Failed to listen")
    self.failed = true
    return false
  end

  log("PokeScan: Server listening on port " .. self.port)
  self.started = true

  -- Write port to file for Swift client to read
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == '@' then source = source:sub(2) end
  local scriptDir = source:match("(.*/)") or "./"
  local portFile = io.open(scriptDir .. "../../dev/logs/port", "w")
  if portFile then
    portFile:write(tostring(self.port))
    portFile:close()
    log("PokeScan: Port written to file")
  end

  -- Register callback for incoming connections
  -- When "received" fires on a listening socket, it means a client wants to connect
  self.server:add("received", function()
    self:acceptConnection()
  end)

  -- Register error callback
  self.server:add("error", function()
    log("PokeScan: Server socket error")
  end)

  return true
end

function SocketServer:acceptConnection()
  if self.client then
    -- Already have a client, ignore new connections
    return
  end

  local client, err = self.server:accept()
  if client then
    self.client = client
    self.justConnected = true  -- Signal to resend current data
    log("PokeScan: Overlay connected!")

    -- Register error handler on client to detect disconnection
    self.client:add("error", function()
      log("PokeScan: Client disconnected")
      self.client = nil
    end)
  end
end

function SocketServer:didJustConnect()
  if self.justConnected then
    self.justConnected = false
    return true
  end
  return false
end

function SocketServer:tick()
  if self.failed then
    return
  end

  if not self.started then
    self:start()
    return
  end

  -- No need to manually poll - callbacks handle it
  -- But we can poll to ensure events are processed
  if self.server then
    self.server:poll()
  end
  if self.client then
    self.client:poll()
  end
end

function SocketServer:sendTable(tbl)
  if self.failed or not self.started or not self.client then
    return false
  end

  local payload = self.json.encode(tbl) .. "\n"
  local result = self.client:send(payload)

  if not result or result < 0 then
    log("PokeScan: Send failed, client disconnected")
    self.client = nil
    return false
  end

  -- Log what we're sending
  log(string.format("PokeScan: SENT species_id=%s pid=%s shiny=%s",
    tostring(tbl.species_id),
    tostring(tbl.pid),
    tostring(tbl.shiny)))
  return true
end

function SocketServer:isConnected()
  return self.client ~= nil
end

return SocketServer
