-- test_anim_runtime.lua
-- Runtime tests for LibMonetColor-Anim-1.0: sink registry, shared ticker,
-- event wiring and error isolation.
-- Run standalone: lua tests/test_anim_runtime.lua
--
-- Covers:
--   1. Sink registration, immediate paint, payload
--   2. Combat / rest / health events repaint the sinks
--   3. The shared ticker: created, driven, stopped
--   4. Sinks without pulse are never repainted by the ticker
--   5. The colour engine's OnThemeRefreshed repaints the sinks
--   6. Unregistering the last sink stops the event tracking
--   7. A broken consumer never stops the other consumers
--   8. The public callback registry

-- ============================================================================
-- Mock environment
-- ============================================================================

local NOW = 5000
local MOCK = {
    health = 100, healthMax = 100,
    inCombat = false, resting = false, dead = false,
    pvp = false, ffaPvp = false, vehicle = false,
}

_G.GetTime = function() return NOW end
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function(self, msg) print("[WARN] " .. msg) end }
_G.C_Map = nil

-- Frame mock: the library creates one event frame and one ticker frame.
local createdFrames = {}

local function CreateFrameMock()
    local frame = { __scripts = {}, __events = {}, __shown = false }

    function frame:SetScript(name, fn) self.__scripts[name] = fn end
    function frame:GetScript(name) return self.__scripts[name] end
    function frame:Show() self.__shown = true end
    function frame:Hide() self.__shown = false end
    function frame:IsShown() return self.__shown end
    function frame:IsVisible() return self.__shown end
    function frame:RegisterEvent(event) self.__events[event] = true end
    function frame:UnregisterEvent(event) self.__events[event] = nil end
    function frame:UnregisterAllEvents() self.__events = {} end

    function frame:Dispatch(event, ...)
        local script = self.__scripts.OnEvent
        if script then script(self, event, ...) end
    end

    function frame:Drive(elapsed)
        local script = self.__scripts.OnUpdate
        if script then script(self, elapsed) end
    end

    createdFrames[#createdFrames + 1] = frame
    return frame
end

_G.CreateFrame = CreateFrameMock

function UnitHealth(unit) return MOCK.health end
function UnitHealthMax(unit) return MOCK.healthMax end
function UnitAffectingCombat(unit) return MOCK.inCombat end
function IsResting() return MOCK.resting end
function UnitIsDeadOrGhost(unit) return MOCK.dead end
function UnitIsGhost(unit) return false end
function UnitIsPVP(unit) return MOCK.pvp end
function UnitIsPVPFreeForAll(unit) return MOCK.ffaPvp end
function UnitInVehicle(unit) return MOCK.vehicle end
function UnitUsingVehicle(unit) return false end
function UnitHasVehicleUI(unit) return false end
function UnitIsAFK(unit) return false end
function UnitIsCharmed(unit) return false end

do
    local registry, minors = {}, {}
    _G.LibStub = setmetatable({
        NewLibrary = function(self, major, minor)
            if minors[major] and minors[major] >= minor then return nil end
            minors[major] = minor
            registry[major] = registry[major] or {}
            return registry[major]
        end,
    }, {
        __call = function(_, major, silent)
            local lib = registry[major]
            if lib then return lib end
            if not silent then error("Library " .. tostring(major) .. " not found", 2) end
            return nil
        end,
    })
end

local function resolvePath(name)
    -- Tests live in tests/; the library files sit in the repository root.
    local scriptPath = arg and arg[0] or "tests/test_anim_runtime.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    for _, candidate in ipairs({ name, dir .. "/" .. name, dir .. "/../" .. name }) do
        if io.open(candidate, "r") then return candidate end
    end
    return name
end

dofile(resolvePath("LibMonetColor-1.0.lua"))
dofile(resolvePath("LibMonetColor-Anim-1.0.lua"))

local LMC = _G.LibMonetColor
local ANIM = _G.LibMonetColorAnim
assert(LMC and ANIM, "libraries did not load")

-- ============================================================================
-- Helpers
-- ============================================================================

local eventFrameRef  -- the layer's event frame, kept for the state reset

local function findFrame(kind)
    if kind == "event" then
        -- The colour engine creates an event frame of its own; the anim layer's
        -- frame is the one that listens for the combat events.
        for _, frame in ipairs(createdFrames) do
            if frame.__scripts.OnEvent and frame.__events["PLAYER_REGEN_DISABLED"] then
                eventFrameRef = frame
                return frame
            end
        end
        return eventFrameRef
    end
    for _, frame in ipairs(createdFrames) do
        if frame.__scripts.OnUpdate then return frame end
    end
    return nil
end

local function eventCount(frame)
    local n = 0
    for _ in pairs(frame.__events) do n = n + 1 end
    return n
end

--- Move the clock and drive the ticker with it.
local function tick(dt)
    dt = dt or 0.1
    NOW = NOW + dt
    local ticker = findFrame("ticker")
    if ticker then ticker:Drive(dt) end
end

local function dispatch(event, ...)
    local frame = findFrame("event")
    assert(frame, "no event frame was created")
    frame:Dispatch(event, ...)
end

local function resetMock()
    MOCK.health = 100; MOCK.healthMax = 100
    MOCK.inCombat = false; MOCK.resting = false; MOCK.dead = false
    MOCK.pvp = false; MOCK.ffaPvp = false; MOCK.vehicle = false
    NOW = NOW + 0.2
    -- The layer is a singleton: clear its combat state between the tests so
    -- a stale combatStart cannot swallow the next test's flash.
    local frame = findFrame("event")
    if frame then
        frame:Dispatch("PLAYER_REGEN_ENABLED", nil)
    end
end

-- ============================================================================
-- Test framework
-- ============================================================================

local tests = {}
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

-- Every sink opened during a test is closed again after it, so a failing
-- assertion cannot leak a registration into the next test.
local openHandles = {}
local function registerSink(apply, opts)
    local handle = ANIM["RegisterColorSink"](ANIM, apply, opts)
    if handle then openHandles[#openHandles + 1] = handle end
    return handle
end
local function closeOpenSinks()
    for _, handle in ipairs(openHandles) do
        pcall(function() handle:Unregister() end)
    end
    openHandles = {}
end

local function assertNear(actual, expected, tol, msg)
    tol = tol or 0.001
    if math.abs(actual - expected) > tol then
        error(string.format("%s: expected %.4f, got %.4f", msg or "assertNear", expected, actual))
    end
end
local function assertTrue(cond, msg)
    if not cond then error(msg or "assertion failed", 2) end
end
local function assertFalse(cond, msg)
    if cond then error(msg or "assertion failed", 2) end
end

-- ============================================================================
-- 1. Registration
-- ============================================================================

test("Sink: registering paints the consumer immediately", function()
    resetMock()
    local calls = 0
    local r, g, b, a
    local handle = registerSink(function(cr, cg, cb, ca)
        calls = calls + 1
        r, g, b, a = cr, cg, cb, ca
    end, { base = "edge" })
    assertTrue(handle ~= nil, "no handle returned")
    assertTrue(calls == 1, "the consumer must be painted once, got " .. calls)
    assertTrue(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1, "colour out of range")
    assertTrue(a >= 0 and a <= 1, "alpha out of range")
    handle:Unregister()
end)

test("Sink: the payload carries the state and the base key", function()
    resetMock()
    local state, base
    local handle = registerSink(function(_, _, _, _, s, b)
        state, base = s, b
    end, { base = "ambient" })
    assertTrue(state ~= nil, "no state in the payload")
    assertTrue(state.inCombat ~= nil and state.healthPct ~= nil, "the state is incomplete")
    assertTrue(base == "ambient", "the base key is missing, got " .. tostring(base))
    handle:Unregister()
end)

test("Sink: a non function is rejected", function()
    assertTrue(ANIM:RegisterColorSink("nope") == nil, "a string must not be accepted")
    assertTrue(ANIM:RegisterColorSink(nil) == nil, "nil must not be accepted")
end)

-- ============================================================================
-- 2. Events repaint the sinks
-- ============================================================================

test("Events: entering combat repaints the consumer", function()
    resetMock()
    local colors = {}
    local handle = registerSink(function(r, g, b, a)
        colors[#colors + 1] = { r = r, g = g, b = b, a = a }
    end, { base = "edge" })
    local before = colors[#colors]
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local after = colors[#colors]
    assertTrue(#colors >= 2, "the consumer was not repainted")
    assertTrue(after.a > before.a, "the combat alpha must be higher")
    handle:Unregister()
end)

test("Events: a health change repaints the consumer", function()
    resetMock()
    local colors = {}
    local handle = registerSink(function(r, g, b, a)
        colors[#colors + 1] = { r = r, g = g, b = b, a = a }
    end, { base = "edge" })
    local before = colors[#colors]
    MOCK.health = 10
    dispatch("UNIT_HEALTH", "player")
    local after = colors[#colors]
    assertTrue(#colors >= 2, "the consumer was not repainted")
    assertTrue(after.r > before.r, "the low health red must be stronger")
    assertTrue(after.g < before.g, "the low health green must be weaker")
    handle:Unregister()
end)

test("Events: a health change of another unit is ignored", function()
    resetMock()
    local calls = 0
    local handle = registerSink(function() calls = calls + 1 end, { base = "edge" })
    local before = calls
    dispatch("UNIT_HEALTH", "party1")
    assertTrue(calls == before, "a foreign unit must not trigger a repaint")
    handle:Unregister()
end)

test("Events: the resting state repaints the consumer", function()
    resetMock()
    local colors = {}
    local handle = registerSink(function(r, g, b, a)
        colors[#colors + 1] = { r = r, g = g, b = b, a = a }
    end, { base = "edge" })
    local before = colors[#colors]
    MOCK.resting = true
    dispatch("PLAYER_UPDATE_RESTING")
    local after = colors[#colors]
    assertTrue(#colors >= 2, "the consumer was not repainted")
    assertTrue(math.abs(after.r - before.r) > 0.0005 or math.abs(after.g - before.g) > 0.0005,
        "the rest tint must change the colour")
    handle:Unregister()
end)

-- ============================================================================
-- 3. The shared ticker
-- ============================================================================

test("Ticker: it is created and shown while a pulse source runs", function()
    resetMock()
    local handle = registerSink(function() end, { base = "edge", pulse = true })
    local idle = findFrame("ticker")
    assertTrue(idle == nil or not idle:IsShown(), "the ticker must not run while nothing pulses")
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local ticker = findFrame("ticker")
    assertTrue(ticker ~= nil, "the ticker was not created")
    assertTrue(ticker:IsShown(), "the ticker must run while the pulse is active")
    handle:Unregister()
end)

test("Ticker: it changes the alpha of the consumer", function()
    resetMock()
    local alphas = {}
    local handle = registerSink(function(r, g, b, a)
        alphas[#alphas + 1] = a
    end, { base = "edge", pulse = true })
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local before = alphas[#alphas]
    tick(0.1)
    assertTrue(#alphas >= 2, "the ticker did not repaint the consumer")
    assertTrue(alphas[#alphas] > before, "the enter flash must raise the alpha")
    handle:Unregister()
end)

test("Ticker: a consumer without pulse is never repainted by the ticker", function()
    resetMock()
    local calls = 0
    local handle = registerSink(function() calls = calls + 1 end,
        { base = "edge", pulse = false })
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local before = calls
    tick(0.1)
    tick(0.1)
    tick(0.1)
    assertTrue(calls == before, "a consumer without pulse must not be repainted by the ticker")
    handle:Unregister()
end)

test("Ticker: it stops when the pulse source is gone", function()
    resetMock()
    local handle = registerSink(function() end, { base = "edge", pulse = true })
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local ticker = findFrame("ticker")
    assertTrue(ticker:IsShown(), "the ticker must run in combat")
    MOCK.inCombat = false
    dispatch("PLAYER_REGEN_ENABLED")
    tick(0.1)
    assertFalse(ticker:IsShown(), "the ticker must stop out of combat")
    handle:Unregister()
end)

test("Ticker: one ticker serves every consumer", function()
    resetMock()
    local a, b = 0, 0
    local handleA = registerSink(function() a = a + 1 end, { base = "edge", pulse = true })
    local handleB = registerSink(function() b = b + 1 end, { base = "edge", pulse = true })
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    local tickers = 0
    for _, frame in ipairs(createdFrames) do
        if frame.__scripts.OnUpdate then tickers = tickers + 1 end
    end
    assertTrue(tickers == 1, "there must be exactly one ticker, got " .. tickers)
    local beforeA, beforeB = a, b
    tick(0.1)
    assertTrue(a > beforeA and b > beforeB, "both consumers must be repainted")
    handleA:Unregister()
    handleB:Unregister()
end)

-- ============================================================================
-- 4. Theme wiring
-- ============================================================================

test("Theme: the colour engine's refresh repaints the consumers", function()
    resetMock()
    local colors = {}
    local handle = registerSink(function(r, g, b, a)
        colors[#colors + 1] = { r = r, g = g, b = b, a = a }
    end, { base = "edge" })
    local before = colors[#colors]
    LMC:SetEnvironmentSampler(function() return 200, 0.6, 0.5 end)
    local after = colors[#colors]
    assertTrue(#colors >= 2, "the consumer was not repainted after the theme change")
    assertTrue(math.abs(after.b - before.b) > 0.01, "the new base colour must be visible")
    handle:Unregister()
end)

-- ============================================================================
-- 5. Registry lifecycle
-- ============================================================================

test("Registry: unregistering the last sink stops the event tracking", function()
    resetMock()
    local handle = registerSink(function() end, { base = "edge" })
    local frame = findFrame("event")
    assertTrue(frame ~= nil, "no event frame")
    assertTrue(eventCount(frame) > 0, "no events are registered")
    handle:Unregister()
    assertTrue(eventCount(frame) == 0, "the events must be unregistered again")
end)

test("Registry: a disabled sink is not repainted", function()
    resetMock()
    local calls = 0
    local handle = registerSink(function() calls = calls + 1 end, { base = "edge" })
    handle:SetEnabled(false)
    local before = calls
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    assertTrue(calls == before, "a disabled sink must not be repainted")
    handle:SetEnabled(true)
    assertTrue(calls > before, "re-enabling must repaint the sink")
    handle:Unregister()
end)

test("Registry: a broken consumer never stops the others", function()
    resetMock()
    local good = 0
    local bad = registerSink(function() error("boom") end, { base = "edge" })
    local goodHandle = registerSink(function() good = good + 1 end, { base = "edge" })
    local before = good
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    assertTrue(good > before, "the healthy consumer must still be repainted")
    bad:Unregister()
    goodHandle:Unregister()
end)

-- ============================================================================
-- 6. Callbacks
-- ============================================================================

test("Callbacks: the combat state change is announced", function()
    resetMock()
    local seen
    ANIM:RegisterCallback("OnCombatStateChanged", function(_, inCombat) seen = inCombat end)
    MOCK.inCombat = true
    dispatch("PLAYER_REGEN_DISABLED")
    assertTrue(seen == true, "the combat start was not announced")
    MOCK.inCombat = false
    dispatch("PLAYER_REGEN_ENABLED")
    assertTrue(seen == false, "the combat end was not announced")
    ANIM:UnregisterAllCallbacks()
end)

test("Callbacks: the player state change is announced", function()
    resetMock()
    local seen = 0
    ANIM:RegisterCallback("OnPlayerStateChanged", function() seen = seen + 1 end)
    MOCK.health = 50
    dispatch("UNIT_HEALTH", "player")
    assertTrue(seen >= 1, "the state change was not announced")
    ANIM:UnregisterAllCallbacks()
end)

test("Callbacks: unregistering stops the delivery", function()
    resetMock()
    local seen = 0
    local function handler() seen = seen + 1 end
    ANIM:RegisterCallback("OnPlayerStateChanged", handler)
    local frame = findFrame("event")
    assertTrue(frame ~= nil, "no event frame was created")
    ANIM:UnregisterCallback("OnPlayerStateChanged", handler)
    MOCK.health = 50
    frame:Dispatch("UNIT_HEALTH", "player")
    assertTrue(seen == 0, "the callback fired after UnregisterCallback")
    ANIM:UnregisterAllCallbacks()
end)

-- ============================================================================
-- Run
-- ============================================================================

print("=== LibMonetColor-Anim runtime suite ===\n")
local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    closeOpenSinks()
    if ok then
        passed = passed + 1
        print(string.format("  PASS: %s", t.name))
    else
        failed = failed + 1
        print(string.format("  FAIL: %s -- %s", t.name, err))
    end
end
print(string.format("\n%d passed, %d failed, %d total", passed, failed, #tests))
if failed == 0 then
    print("\n=== ALL ANIM RUNTIME TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME ANIM RUNTIME TESTS FAILED ===")
    os.exit(1)
end
