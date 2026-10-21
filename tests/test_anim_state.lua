-- test_anim_state.lua
-- State sampling + colour resolution tests for LibMonetColor-Anim-1.0.
-- Run standalone: lua tests/test_anim_state.lua
--
-- Covers:
--   1. Base colour resolution (edge / ambient / highlight / neutral / custom)
--   2. Combat brightness, out-of-combat dimming
--   3. Low health tint (threshold, severity, critical red, modifier opt-out)
--   4. Rest / PvP / vehicle tints, dead short circuit
--   5. Pulse amplitudes and determinism
--   6. Secret value degradation
--   7. Style merge, clamping, reset

-- ============================================================================
-- Mock environment: REALISTIC LibStub, no CallbackHandler, no WoW frames
-- ============================================================================

local NOW = 1000
local MOCK = {
    health = 100, healthMax = 100,
    inCombat = false, resting = false,
    dead = false, ghost = false,
    pvp = false, ffaPvp = false,
    vehicle = false, afk = false, charmed = false,
    healthReads = 0,
}

_G.GetTime = function() return NOW end
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function(self, msg) print("[WARN] " .. msg) end }
_G.C_Map = nil
_G.CreateFrame = nil

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

-- Mock unit APIs.  They are plain globals so the library can find them.
function UnitHealth(unit)
    MOCK.healthReads = MOCK.healthReads + 1
    return MOCK.health
end
function UnitHealthMax(unit) return MOCK.healthMax end
function UnitAffectingCombat(unit) return MOCK.inCombat end
function IsResting() return MOCK.resting end
function UnitIsDeadOrGhost(unit) return MOCK.dead end
function UnitIsGhost(unit) return MOCK.ghost end
function UnitIsPVP(unit) return MOCK.pvp end
function UnitIsPVPFreeForAll(unit) return MOCK.ffaPvp end
function UnitInVehicle(unit) return MOCK.vehicle end
function UnitUsingVehicle(unit) return false end
function UnitHasVehicleUI(unit) return false end
function UnitIsAFK(unit) return MOCK.afk end
function UnitIsCharmed(unit) return MOCK.charmed end

local function resolvePath(name)
    -- Tests live in tests/; the library files sit in the repository root.
    local scriptPath = arg and arg[0] or "tests/test_anim_state.lua"
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
assert(LMC, "colour engine did not load")
assert(ANIM, "anim layer did not load")
assert(LMC.Anim == ANIM, "core alias missing")

-- ============================================================================
-- Test framework
-- ============================================================================

local tests = {}
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

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

local function hueOf(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    if max == min then return 0 end
    local d = max - min
    local h
    if max == r then
        h = (g - b) / d
        if g < b then h = h + 6 end
    elseif max == g then
        h = (b - r) / d + 2
    else
        h = (r - g) / d + 4
    end
    return h * 60
end

local function hueDist(a, b)
    return math.abs(((a - b + 180) % 360) - 180)
end

local function luminance(r, g, b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

--- Change the mocked player state and move the clock past the state TTL.
local function setState(changes, dt)
    for k, v in pairs(changes or {}) do MOCK[k] = v end
    NOW = NOW + (dt or 0.2)
end

local function resetState()
    setState({
        health = 100, healthMax = 100,
        inCombat = false, resting = false,
        dead = false, ghost = false,
        pvp = false, ffaPvp = false,
        vehicle = false, afk = false, charmed = false,
    }, 0.2)
end

-- ============================================================================
-- 1. Base colour resolution
-- ============================================================================

test("Base: edge slot matches the colour engine's edge colour", function()
    resetState()
    local er, eg, eb, ea = LMC:GetCurrentEdgeColor()
    -- With the state modifiers switched off the slot must be the engine's
    -- colour, bit for bit.
    local r, g, b, a = ANIM:GetColor("edge", nil, { ooc = false })
    assertNear(r, er, 0.001, "edge red")
    assertNear(g, eg, 0.001, "edge green")
    assertNear(b, eb, 0.001, "edge blue")
    assertNear(a, ea, 0.001, "edge alpha")
    -- Out of combat the alpha is scaled down by the ooc factor.
    local _, _, _, dimmed = ANIM:GetColor("edge")
    assertTrue(dimmed < ea, "out of combat must dim the alpha")
    assertNear(dimmed, ea * ANIM:GetStyle().ooc.alphaScale, 0.001, "ooc alpha scale")
end)

test("Base: ambient / highlight / neutral resolve to their own slots", function()
    resetState()
    local ar, ag, ab, aa = LMC:GetCurrentAmbientTint()
    local r, g, b, a = ANIM:GetColor("ambient", nil, { ooc = false })
    assertNear(r, ar, 0.001, "ambient red")
    assertNear(g, ag, 0.001, "ambient green")
    assertNear(b, ab, 0.001, "ambient blue")
    assertNear(a, aa, 0.001, "ambient alpha")
    -- Out of combat the ambient alpha is scaled down as well.
    local _, _, _, dimmed = ANIM:GetColor("ambient")
    assertNear(dimmed, aa * ANIM:GetStyle().ooc.alphaScale, 0.001, "ambient alpha scale")

    local hr, hg, hb = LMC:GetCurrentHighlightWash()
    r, g, b = ANIM:GetColor("highlight", nil, { ooc = false })
    assertNear(r, hr, 0.001, "highlight red")
    assertNear(g, hg, 0.001, "highlight green")
    assertNear(b, hb, 0.001, "highlight blue")

    local nr, ng, nb = LMC:GetCurrentNeutral()
    r, g, b = ANIM:GetColor("neutral", nil, { ooc = false })
    assertNear(r, nr, 0.001, "neutral red")
    assertNear(g, ng, 0.001, "neutral green")
    assertNear(b, nb, 0.001, "neutral blue")
end)

test("Base: a custom {r,g,b,a} table is accepted", function()
    resetState()
    local r, g, b, a = ANIM:GetColor({ r = 0.2, g = 0.4, b = 0.6, a = 0.9 })
    assertTrue(r ~= nil and g ~= nil and b ~= nil and a ~= nil, "custom base returned nil")
    assertTrue(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1, "custom base out of range")
    assertTrue(a > 0 and a <= 1, "custom alpha out of range")
end)

test("Base: an unknown slot falls back to the edge colour", function()
    resetState()
    local er, eg, eb = LMC:GetCurrentEdgeColor()
    local r, g, b = ANIM:GetColor("nonsense", nil, { ooc = false })
    assertNear(r, er, 0.001, "fallback red")
    assertNear(g, eg, 0.001, "fallback green")
    assertNear(b, eb, 0.001, "fallback blue")
end)

-- ============================================================================
-- 2. Combat / out of combat
-- ============================================================================

test("Combat: the border is brighter and stronger in combat", function()
    resetState()
    local oocR, oocG, oocB = ANIM:GetColor("edge")
    local oocLum = luminance(oocR, oocG, oocB)

    setState({ inCombat = true })
    local r, g, b = ANIM:GetColor("edge")
    local combatLum = luminance(r, g, b)
    assertTrue(combatLum > oocLum, "combat must be brighter than out of combat")
end)

test("Combat: the alpha is boosted in combat and lowered out of it", function()
    resetState()
    local oocA = ANIM:GetColor("edge")
    setState({ inCombat = true })
    local combatA = ANIM:GetColor("edge")
    assertTrue(combatA > oocA, "combat alpha must exceed the out of combat alpha")
end)

test("Combat: the combat modifier can be switched off per call", function()
    resetState()
    setState({ inCombat = true })
    local fullR = ANIM:GetColor("edge")
    local plainR = ANIM:GetColor("edge", nil, { combat = false, ooc = false })
    assertTrue(math.abs(fullR - plainR) > 0.001, "combat modifier had no effect")
end)

-- ============================================================================
-- 3. Low health
-- ============================================================================

test("Low health: nothing happens above the threshold", function()
    resetState()
    local before = ANIM:GetColor("edge")
    setState({ health = 50, healthMax = 100 })   -- 50% is above 35%
    local after = ANIM:GetColor("edge")
    assertNear(after, before, 0.001, "healthy player must not be tinted")
    assertFalse(ANIM:GetPlayerState().lowHealth, "state should not be lowHealth")
end)

test("Low health: below the threshold the state reports low and the tier", function()
    resetState()
    setState({ health = 30, healthMax = 100 })   -- 30% is below 35%
    local state = ANIM:GetPlayerState()
    assertTrue(state.lowHealth, "state should be lowHealth")
    assertTrue(state.tier == "low", "tier should be low, got " .. tostring(state.tier))
    assertNear(state.healthPct, 0.3, 0.001, "health percent")
end)

test("Low health: at critical the colour is a plain danger red", function()
    resetState()
    setState({ health = 10, healthMax = 100 })   -- 10% is below the 20% critical line
    local state = ANIM:GetPlayerState()
    assertTrue(state.tier == "critical", "tier should be critical")
    local r, g, b = ANIM:GetColor("edge")
    assertTrue(r > 0.8, "critical red channel should dominate, got " .. tostring(r))
    assertTrue(g < 0.35, "critical green should be low, got " .. tostring(g))
    assertTrue(b < 0.35, "critical blue should be low, got " .. tostring(b))
end)

test("Low health: the lowHealth modifier can be switched off", function()
    resetState()
    setState({ health = 10, healthMax = 100 })
    local r, g, b = ANIM:GetColor("edge")
    local pr, pg, pb = ANIM:GetColor("edge", nil, { lowHealth = false })
    assertTrue(r > 0.8, "default must be red")
    assertTrue(not (pr > 0.8 and pg < 0.35), "opted out colour must not be red")
end)

test("Low health: the alpha is boosted with the severity", function()
    resetState()
    setState({ health = 34, healthMax = 100 })   -- just below the threshold
    local lowA = ANIM:GetColor("edge")
    setState({ health = 10, healthMax = 100 })
    local critA = ANIM:GetColor("edge")
    assertTrue(critA > lowA, "critical alpha must exceed the low alpha")
end)

-- ============================================================================
-- 4. Rest / PvP / vehicle / dead
-- ============================================================================

test("Rest: the hue moves towards the rest colour", function()
    resetState()
    local base = { r = 1, g = 0, b = 0 }
    local plainHue = hueOf(ANIM:GetColor(base))
    setState({ resting = true })
    local restHue = hueOf(ANIM:GetColor(base))
    assertTrue(hueDist(restHue, 210) < hueDist(plainHue, 210),
        "rest must move the hue towards 210 (plain " .. plainHue .. ", rest " .. restHue .. ")")
end)

test("PvP: the hue moves towards the danger red", function()
    resetState()
    local base = { r = 0, g = 1, b = 0 }
    local plainHue = hueOf(ANIM:GetColor(base))
    setState({ pvp = true })
    local pvpHue = hueOf(ANIM:GetColor(base))
    assertTrue(hueDist(pvpHue, 0) < hueDist(plainHue, 0),
        "pvp must move the hue towards 0 (plain " .. plainHue .. ", pvp " .. pvpHue .. ")")
end)

test("Vehicle: the hue moves towards the amber", function()
    resetState()
    local base = { r = 0, g = 1, b = 0 }
    local plainHue = hueOf(ANIM:GetColor(base))
    setState({ vehicle = true })
    local vehicleHue = hueOf(ANIM:GetColor(base))
    assertTrue(hueDist(vehicleHue, 42) < hueDist(plainHue, 42),
        "vehicle must move the hue towards 42 (plain " .. plainHue .. ", vehicle " .. vehicleHue .. ")")
end)

test("Dead: grey, dim and without any other tint", function()
    resetState()
    setState({ dead = true, resting = true, pvp = true })
    local r, g, b, a = ANIM:GetColor("edge")
    assertNear(r, g, 0.01, "dead colour must be grey (r vs g)")
    assertNear(g, b, 0.01, "dead colour must be grey (g vs b)")
    assertNear(a, ANIM:GetStyle().dead.alpha, 0.001, "dead alpha")
end)

test("Dead: the dead modifier can be switched off", function()
    resetState()
    setState({ dead = true })
    local r = ANIM:GetColor("edge")
    local pr = ANIM:GetColor("edge", nil, { dead = false })
    assertTrue(math.abs(r - pr) > 0.001, "the dead modifier had no effect")
end)

-- ============================================================================
-- 5. Pulse
-- ============================================================================

test("Pulse: the alpha never leaves [0,1]", function()
    resetState()
    setState({ inCombat = true, health = 5, healthMax = 100 })
    for t = 0, 40 do
        local r, g, b, a = ANIM:GetColor("edge", NOW + t * 0.05)
        assertTrue(a >= 0 and a <= 1, "alpha out of range: " .. tostring(a))
        assertTrue(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1, "colour out of range")
    end
end)

test("Pulse: the enter flash is stronger right after combat starts", function()
    resetState()
    setState({ inCombat = true })
    local start = NOW
    local _, _, _, flashA = ANIM:GetColor("edge", start + 0.1)
    local _, _, _, laterA = ANIM:GetColor("edge", start + 1.2)
    assertTrue(flashA > laterA, "the flash must decay (flash " .. flashA .. ", later " .. laterA .. ")")
end)

test("Pulse: the sustained breath varies over the combat period", function()
    resetState()
    setState({ inCombat = true })
    local start = NOW
    local _, _, _, a1 = ANIM:GetColor("edge", start + 0.8)
    local _, _, _, a2 = ANIM:GetColor("edge", start + 1.6)
    assertTrue(math.abs(a1 - a2) > 0.001, "the breath must change the alpha")
end)

test("Pulse: the same timestamp always yields the same colour", function()
    resetState()
    setState({ inCombat = true, health = 20, healthMax = 100 })
    local r1, g1, b1, a1 = ANIM:GetColor("edge", NOW + 0.33)
    local r2, g2, b2, a2 = ANIM:GetColor("edge", NOW + 0.33)
    assertNear(r1, r2, 0.000001, "determinism red")
    assertNear(g1, g2, 0.000001, "determinism green")
    assertNear(b1, b2, 0.000001, "determinism blue")
    assertNear(a1, a2, 0.000001, "determinism alpha")
end)

test("Pulse: no pulse without a source (out of combat, healthy)", function()
    resetState()
    local _, _, _, a = ANIM:GetColor("edge", NOW + 0.2)
    local _, _, _, b = ANIM:GetColor("edge", NOW + 0.7)
    assertNear(a, b, 0.000001, "a healthy player must not pulse")
end)

-- ============================================================================
-- 6. Secret values
-- ============================================================================

test("Secrets: a hidden health disables the low health effect without erroring", function()
    resetState()
    _G.C_Secrets = {
        HasSecretRestrictions = function() return true end,
        ShouldUnitHealthMaxBeSecret = function() return true end,
    }
    setState({ health = 5, healthMax = 100 })
    local ok, r, g, b, a = pcall(ANIM.GetColor, ANIM, "edge")
    assertTrue(ok, "GetColor raised with a secret health value")
    assertTrue(r >= 0 and r <= 1, "colour out of range under restrictions")
    local state = ANIM:GetPlayerState()
    assertFalse(state.healthKnown, "the health must be reported as unknown")
    assertFalse(state.lowHealth, "an unknown health must not trigger the low health effect")
    _G.C_Secrets = nil
end)

test("Secrets: a readable health still works while restrictions are on", function()
    resetState()
    _G.C_Secrets = {
        HasSecretRestrictions = function() return true end,
        ShouldUnitHealthMaxBeSecret = function() return false end,
    }
    setState({ health = 5, healthMax = 100 })
    local state = ANIM:GetPlayerState()
    assertTrue(state.healthKnown, "the health must be known")
    assertTrue(state.lowHealth, "the low health effect must be active")
    _G.C_Secrets = nil
end)

-- ============================================================================
-- 7. Style handling
-- ============================================================================

test("Style: SetStyle merges without dropping the other fields", function()
    resetState()
    local style = ANIM:GetStyle()
    local before = style.lowHealth.color.h
    assertTrue(ANIM:SetStyle({ lowHealth = { threshold = 0.5 } }), "SetStyle failed")
    style = ANIM:GetStyle()
    assertNear(style.lowHealth.threshold, 0.5, 0.0001, "threshold")
    assertNear(style.lowHealth.color.h, before, 0.0001, "the colour must survive the merge")
    assertNear(style.combat.pulseAmplitude, 0.10, 0.0001, "another section must survive")
    ANIM:ResetStyle()
end)

test("Style: out of range values are clamped", function()
    resetState()
    ANIM:SetStyle({ combat = { lightnessBoost = 5 }, lowHealth = { threshold = -3 } })
    local style = ANIM:GetStyle()
    assertNear(style.combat.lightnessBoost, 0.5, 0.0001, "lightnessBoost clamp")
    assertNear(style.lowHealth.threshold, 0.01, 0.0001, "threshold clamp")
    ANIM:ResetStyle()
end)

test("Style: a colour may be given as RGB", function()
    resetState()
    ANIM:SetStyle({ rest = { color = { r = 0, g = 0, b = 1 } } })
    local hue = ANIM:GetStyle().rest.color.h
    assertTrue(math.abs(hue - 240) < 1, "the blue must land on hue 240, got " .. tostring(hue))
    ANIM:ResetStyle()
end)

test("Style: the critical threshold can never exceed the low threshold", function()
    resetState()
    ANIM:SetStyle({ lowHealth = { threshold = 0.2, critical = 0.8 } })
    local style = ANIM:GetStyle()
    assertTrue(style.lowHealth.critical <= style.lowHealth.threshold, "critical must be clamped")
    ANIM:ResetStyle()
end)

test("Style: ResetStyle restores the built-in values", function()
    resetState()
    ANIM:SetStyle({ combat = { lightnessBoost = 0.4 } })
    ANIM:ResetStyle()
    assertNear(ANIM:GetStyle().combat.lightnessBoost, 0.08, 0.0001, "reset lightnessBoost")
    assertNear(ANIM:GetStyle().lowHealth.threshold, 0.35, 0.0001, "reset threshold")
end)

test("Style: a non table is rejected", function()
    assertFalse(ANIM:SetStyle("nope"), "SetStyle must reject a string")
    assertFalse(ANIM:SetStyle(nil), "SetStyle must reject nil")
end)

-- ============================================================================
-- 8. State sampling
-- ============================================================================

test("State: the state is cached for the TTL and resampled afterwards", function()
    resetState()
    MOCK.healthReads = 0
    ANIM:GetColor("edge")
    local first = MOCK.healthReads
    assertTrue(first > 0, "the health must be read at least once")
    ANIM:GetColor("edge")
    assertTrue(MOCK.healthReads == first, "the health must not be read again inside the TTL")
    NOW = NOW + 0.3
    ANIM:GetColor("edge")
    assertTrue(MOCK.healthReads > first, "the health must be read again after the TTL")
end)

test("State: the tier is reported for every band", function()
    resetState()
    setState({ health = 90, healthMax = 100 })
    assertTrue(ANIM:GetPlayerState().tier == "healthy", "healthy band")
    setState({ health = 30, healthMax = 100 })
    assertTrue(ANIM:GetPlayerState().tier == "low", "low band")
    setState({ health = 10, healthMax = 100 })
    assertTrue(ANIM:GetPlayerState().tier == "critical", "critical band")
end)

test("State: GetPlayerState exposes the whole state set", function()
    resetState()
    local state = ANIM:GetPlayerState()
    for _, key in ipairs({ "inCombat", "resting", "healthPct", "healthKnown", "tier",
                           "lowHealth", "dead", "ghost", "pvp", "ffaPvp", "vehicle",
                           "afk", "charmed", "updatedAt" }) do
        assertTrue(state[key] ~= nil, "state field missing: " .. key)
    end
end)

-- ============================================================================
-- Run
-- ============================================================================

print("=== LibMonetColor-Anim state suite ===\n")
local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
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
    print("\n=== ALL ANIM STATE TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME ANIM STATE TESTS FAILED ===")
    os.exit(1)
end
