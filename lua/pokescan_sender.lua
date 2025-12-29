-- PokeScan sender entrypoint for mGBA Lua
-- mGBA acts as TCP SERVER, Swift overlay connects as CLIENT

local function script_dir()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  return source:match("(.*/)") or "./"
end

local root = script_dir()

local json = dofile(root .. "core/json.lua")
local SocketServer = dofile(root .. "core/socket_server.lua")

dofile(root .. "adapters/emerald_us_eu.lua")

local server = SocketServer.new({
  port = 9876,
  json = json
})

local lastPID = 0
local lastHadPokemon = false
local lastSendAt = 0
local MIN_SEND_INTERVAL = 0.25  -- Minimum seconds between sends (real-time throttle)
local pending = nil
local seq = 0

local function debugEnabled()
  if os and os.getenv and os.getenv("POKESCAN_DEBUG") == "1" then
    return true
  end
  local f = io.open(root .. "../dev/logs/debug", "r")
  if f then
    f:close()
    return true
  end
  return false
end

local DEBUG = debugEnabled()

-- Test mode: force shiny and/or perfect IVs for UI testing
local TEST_SHINY = false
local TEST_PERFECT_IVS = false

local LOG_FILE = nil
local LOG_PATH = root .. "../dev/logs/lua_sender.log"
local function logToFile(msg)
  if not LOG_FILE then
    LOG_FILE = io.open(LOG_PATH, "a")
    if LOG_FILE then
      LOG_FILE:setvbuf("line")
    end
  end
  if LOG_FILE then
    local timestamp = os.date("%H:%M:%S")
    LOG_FILE:write(string.format("[%s] %s\n", timestamp, msg))
  end
end

local function log(msg)
  if console and console.log then
    console:log(msg)
  else
    print(msg)
  end
  logToFile(msg)
end

local function maybeScanBattleFlag()
  local scanPath = root .. "../dev/logs/scan"
  local f = io.open(scanPath, "r")
  if not f then return end
  f:close()

  if not emu or not emu.loadStateFile or not emu.readRange then
    log("PokeScan: scan unavailable (missing emu APIs)")
    return
  end

  local outState = root .. "../dev/emerald.ss1"
  local inState = root .. "../dev/emerald.ss2"
  log("PokeScan: scan starting (ss1=out, ss2=in)")

  local ranges = {
    { 0x02000000, 0x40000 }, -- EWRAM 256KB
    { 0x03000000, 0x8000 },  -- IWRAM 32KB
  }

  local candidates = {}
  for _, r in ipairs(ranges) do
    local base = r[1]
    local size = r[2]

    emu:loadStateFile(outState)
    local bufOut = emu:readRange(base, size)

    emu:loadStateFile(inState)
    local bufIn = emu:readRange(base, size)

    for i = 1, size do
      local a = bufOut:byte(i)
      local b = bufIn:byte(i)
      if a ~= b then
        -- Prefer small flag-like values
        if (a == 0 and b <= 8) or (b == 0 and a <= 8) then
          local addr = base + (i - 1)
          table.insert(candidates, string.format("0x%08X: %d -> %d", addr, a, b))
          if #candidates >= 50 then break end
        end
      end
    end

    if #candidates >= 50 then break end
  end

  if #candidates == 0 then
    log("PokeScan: scan found no small flag candidates")
  else
    log("PokeScan: scan candidates (first 50):")
    for _, line in ipairs(candidates) do
      log("  " .. line)
    end
  end

  -- Reload active state (ss0)
  emu:loadStateFile(root .. "../dev/emerald.ss0")
end

if DEBUG then
  local dbg = getBattleDebug and "available" or "missing"
  log("PokeScan: getBattleDebug " .. dbg)
end

maybeScanBattleFlag()

local frameCount = 0
local lastDebugFrame = -1
local lastPidLogFrame = -1
local function debugBattleState(hasData)
  if not DEBUG then return end
  local frame = frameCount
  if (frame - lastDebugFrame) < 60 then return end  -- ~1s at 60fps
  lastDebugFrame = frame
  if getBattleDebug then
    local ok, d = pcall(getBattleDebug)
    if not ok then
      log("PokeScan: getBattleDebug error: " .. tostring(d))
      return
    end
    if not d then
      log("PokeScan: getBattleDebug returned nil")
      return
    end
    log(string.format(
      "PokeScan: battle data=%s type=%d turns=%d saw=%s map=%d pid=%08X in=%s fA=%d fB=%d fC=%d fD=%d fE=%d",
      tostring(hasData),
      d.battleType or -1,
      d.turns or -1,
      tostring(d.sawBattleTurn),
      d.mapType or -1,
      d.pid or 0,
      tostring(d.mainInBattle),
      d.flagA or -1,
      d.flagB or -1,
      d.flagC or -1,
      d.flagD or -1,
      d.flagE or -1
    ))
  end
end

local function now()
  if os and os.clock then
    return os.clock()
  end
  return 0
end

local function queue(payload)
  pending = payload
end

local function trySend()
  if not pending or not server:isConnected() then
    return
  end

  local t = now()
  if (not pending.clear) and (t - lastSendAt) < MIN_SEND_INTERVAL then
    return
  end

  seq = seq + 1
  pending.seq = seq
  if emu and emu.currentFrame then
    pending.frame = emu:currentFrame()
  end

  if server:sendTable(pending) then
    lastSendAt = t
    pending = nil
  end
end

local function onFrame()
  server:tick()
  frameCount = frameCount + 1

  if not readWildPokemon then
    return
  end

  -- Capture connect events even when not in battle
  local justConnected = server:didJustConnect()

  local data = readWildPokemon()
  if not data then
    -- Send clear message if we previously had a Pokemon
    if lastHadPokemon or justConnected then
      queue({ clear = true })
      lastHadPokemon = false
      lastPID = 0
    end
    debugBattleState(false)
    trySend()
    return
  end

  -- Detect state transition: entering battle (no Pokemon -> has Pokemon)
  local enteringBattle = not lastHadPokemon
  lastHadPokemon = true

  -- Apply test mode overrides
  if TEST_SHINY then
    data.shiny = true
  end
  if TEST_PERFECT_IVS then
    data.ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 }
  end

  -- Check if client just connected - if so, always send current data
  local forceResend = justConnected

  -- Queue on battle entry, client connect, or PID change
  local shouldQueue = forceResend or enteringBattle or (data.pid and data.pid ~= lastPID)
  if shouldQueue then
    lastPID = data.pid or lastPID
    queue(data)
  end

  if DEBUG then
    local frame = frameCount
    if (frame - lastPidLogFrame) >= 60 then
      lastPidLogFrame = frame
      log(string.format(
        "PokeScan: PID=%08X species=%d shiny=%s%s",
        data.pid or 0,
        data.species_id or 0,
        tostring(data.shiny),
        forceResend and " (resend)" or ""
      ))
    end
  end

  debugBattleState(true)
  trySend()
end

if callbacks and callbacks.add then
  callbacks:add("frame", onFrame)
else
  console:log("PokeScan: callbacks API not available")
end

console:log("PokeScan: sender loaded - waiting for overlay connection on port 9876")
