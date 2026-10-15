-- test_hardening.lua
-- Regression tests for the Phase 1 hardening pass.
-- Run standalone: lua test_hardening.lua
--
-- These cover gaps the original suite missed:
--   1. Real LibStub registration (consumers must receive the library object)
--   2. Active profile rules actually affect output
--   3. GetEdgeColorForMap honours mapID via the sampler
--   4. R-01 ambient alpha formula
--   5. Fallback callback registry (LMC:RegisterCallback outside WoW)

-- ============================================================================
-- Mock environment: REALISTIC LibStub, no CallbackHandler, no WoW frames
-- ============================================================================

_G.GetTime = _G.GetTime or function() return os.time() end
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

local libPath = "LibMonetColor-1.0.lua"
if not io.open(libPath, "r") then
    local scriptPath = arg and arg[0] or "test_hardening.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    libPath = dir .. "/LibMonetColor-1.0.lua"
end
dofile(libPath)

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

-- ============================================================================
-- 1. LibStub registration
-- ============================================================================

test("LibStub: consumer receives the library object", function()
    local L = LibStub("LibMonetColor-1.0", true)
    assertTrue(L ~= nil, "LibStub lookup returned nil")
    assertTrue(type(L.GetCurrentEdgeColor) == "function", "library object is missing methods")
    assertTrue(L == _G.LibMonetColor, "LibStub object differs from global alias")
end)

test("LibStub: double-load is a no-op (minor guard)", function()
    local before = LibStub("LibMonetColor-1.0", true)
    dofile(libPath)  -- reload: NewLibrary must return nil and abort
    local after = LibStub("LibMonetColor-1.0", true)
    assertTrue(after == before, "reload replaced the registered library")
end)

-- ============================================================================
-- 2. Active profile must affect output
-- ============================================================================

test("Profile: active rules change the computed edge hue", function()
    local LMC = _G.LibMonetColor
    -- Deterministic environment: pure red, mid saturation/lightness.
    LMC:SetEnvironmentSampler(function() return 0, 0.6, 0.5 end)

    LMC:SetActiveProfile("Monet")
    local mr, mg, mb = LMC:GetCurrentEdgeColor()
    local mh = LMC.RGBToHSL(mr, mg, mb)

    -- hueShift=90, no complementary pairs -> complement of 0 is 90.
    LMC:RegisterProfile("HardeningHue", {
        domains = {{name = "All", range = {0, 360}, hueShift = 90, satMult = 0.5, lBias = 0}},
        complementaryPairs = {},
        saturationCompensation = {factor = 1.0, minSaturation = 0},
        lightnessMin = 0.2, lightnessMax = 0.8,
    })
    assertTrue(LMC:SetActiveProfile("HardeningHue"), "activation failed")
    local cr, cg, cb = LMC:GetCurrentEdgeColor()
    local ch = LMC.RGBToHSL(cr, cg, cb)

    assertNear(ch, 90, 5.0, "custom profile hue should be ~90")
    assertTrue(math.abs(ch - mh) > 20, "Monet and custom profiles must differ")
    LMC:SetActiveProfile("Monet")
end)

test("Profile: minimal rules (missing keys) fall back to defaults, no crash", function()
    local LMC = _G.LibMonetColor
    LMC:RegisterProfile("Minimal", {
        domains = {{name = "All", range = {0, 360}, hueShift = 180, satMult = 0.8, lBias = 0}},
    })
    LMC:SetActiveProfile("Minimal")
    local r, g, b = LMC:GetCurrentEdgeColor()
    assertTrue(r >= 0 and r <= 1, "edge R out of range")
    assertTrue(g >= 0 and g <= 1, "edge G out of range")
    assertTrue(b >= 0 and b <= 1, "edge B out of range")
    LMC:SetActiveProfile("Monet")
end)

-- ============================================================================
-- 3. GetEdgeColorForMap honours mapID
-- ============================================================================

test("GetEdgeColorForMap: per-map sampler produces different colors", function()
    local LMC = _G.LibMonetColor
    LMC:SetEnvironmentSampler(function(mapID)
        if mapID == 1 then return 0, 0.6, 0.5 end     -- red env
        if mapID == 2 then return 210, 0.6, 0.5 end   -- indigo env
        return 120, 0.15, 0.5
    end)

    local r1, g1, b1 = LMC:GetEdgeColorForMap(1)
    local r2, g2, b2 = LMC:GetEdgeColorForMap(2)
    local diff = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
    assertTrue(diff > 0.1, "different maps should yield different edge colors")

    -- Must not have polluted the active cache.
    assertTrue(LMC.colorCache[1] == nil and LMC.colorCache[2] == nil,
        "GetEdgeColorForMap must not write the active cache")
end)

test("GetEdgeColorForMap: uses a cached entry when available", function()
    local LMC = _G.LibMonetColor
    LMC.colorCache[42] = {
        envH = 0, envS = 0.5, envL = 0.5,
        edge = {r = 0.1, g = 0.2, b = 0.3, a = 0.8},
    }
    local r, g, b = LMC:GetEdgeColorForMap(42)
    assertNear(r, 0.1, 0.001, "cached r")
    assertNear(g, 0.2, 0.001, "cached g")
    assertNear(b, 0.3, 0.001, "cached b")
    LMC.colorCache[42] = nil
end)

-- ============================================================================
-- 4. R-01 ambient alpha formula
-- ============================================================================

test("Ambient alpha: bounded to [0.15, 0.30]", function()
    local LMC = _G.LibMonetColor
    for _, l in ipairs({0, 0.25, 0.5, 0.75, 1}) do
        for _, s in ipairs({0, 0.5, 1}) do
            local _, _, _, a = LMC.ComputeAmbientTint(120, s, l)
            assertTrue(a >= 0.15 - 1e-9 and a <= 0.30 + 1e-9,
                string.format("alpha %.4f out of [0.15,0.30] (L=%.2f S=%.2f)", a, l, s))
        end
    end
end)

test("Ambient alpha: darker env -> stronger tint; saturation guard applies", function()
    local LMC = _G.LibMonetColor
    local _, _, _, aDark   = LMC.ComputeAmbientTint(120, 0, 0.0)   -- 0.30
    local _, _, _, aBright = LMC.ComputeAmbientTint(120, 0, 1.0)   -- 0.15
    local _, _, _, aSat    = LMC.ComputeAmbientTint(120, 1.0, 0.0) -- 0.27
    assertNear(aDark, 0.30, 0.001, "darkest gray")
    assertNear(aBright, 0.15, 0.001, "brightest")
    assertNear(aSat, 0.27, 0.001, "dark + saturated")
    assertTrue(aDark > aSat and aSat > aBright, "alpha monotonicity broken")
end)

test("Ambient alpha: respects custom rule overrides", function()
    local LMC = _G.LibMonetColor
    local _, _, _, a = LMC.ComputeAmbientTint(120, 0, 0.0, {ambient = {alphaMin = 0.2, alphaMax = 0.2}})
    assertNear(a, 0.2, 0.001, "custom flat alpha")
end)

-- ============================================================================
-- 5. Fallback callback registry
-- ============================================================================

test("Callbacks: RegisterCallback + Refresh fires OnThemeColorsChanged", function()
    local LMC = _G.LibMonetColor
    LMC:SetEnvironmentSampler(function() return 30, 0.4, 0.5 end)
    LMC:ClearCache()  -- no prior entry, so the forced refresh is significant
    local fired, gotEntry = 0, nil
    LMC:RegisterCallback("OnThemeColorsChanged", function(event, entry)
        fired = fired + 1
        gotEntry = entry
    end)
    LMC:Refresh()
    assertTrue(fired == 1, "callback should fire exactly once on forced refresh")
    assertTrue(gotEntry ~= nil and gotEntry.edge ~= nil, "callback entry payload missing")
end)

test("Callbacks: UnregisterAllCallbacks stops delivery", function()
    local LMC = _G.LibMonetColor
    LMC:UnregisterAllCallbacks()
    local fired = 0
    LMC:RegisterCallback("OnThemeColorsChanged", function() fired = fired + 1 end)
    LMC:UnregisterAllCallbacks()
    LMC:Refresh()
    assertTrue(fired == 0, "callback fired after UnregisterAllCallbacks")
end)

-- ============================================================================
-- Run
-- ============================================================================

print("=== LibMonetColor hardening regression suite ===\n")
local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        print(string.format("  PASS: %s", t.name))
    else
        failed = failed + 1
        print(string.format("  FAIL: %s — %s", t.name, err))
    end
end
print(string.format("\n%d passed, %d failed, %d total", passed, failed, #tests))
if failed == 0 then
    print("\n=== ALL HARDENING TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME HARDENING TESTS FAILED ===")
    os.exit(1)
end
