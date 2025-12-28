-- Test mGBA socket API availability

local function log(msg)
  if console and console.log then
    console:log(msg)
  else
    print(msg)
  end
end

log("Testing mGBA socket API...")

if not socket then
  log("ERROR: 'socket' global is not available")
  log("Make sure socket scripting is enabled in mGBA settings")
  return
end

log("socket global exists, type: " .. type(socket))

-- List available methods
log("Available socket methods:")
for k, v in pairs(socket) do
  log("  " .. k .. " = " .. type(v))
end

-- Try to create a TCP socket
log("\nTrying socket:tcp()...")
local ok, result = pcall(function()
  return socket:tcp()
end)

if ok then
  log("socket:tcp() succeeded, type: " .. type(result))
  if result then
    for k, v in pairs(result) do
      log("  " .. k .. " = " .. type(v))
    end
  end
else
  log("socket:tcp() failed: " .. tostring(result))
end

-- Try bind directly
log("\nTrying socket:bind('127.0.0.1', 9877)...")
local ok2, result2 = pcall(function()
  return socket:bind("127.0.0.1", 9877)
end)

if ok2 then
  log("socket:bind() succeeded!")
  if result2 then
    log("Result type: " .. type(result2))
    result2:close()
  end
else
  log("socket:bind() failed: " .. tostring(result2))
end

log("\nTest complete")
