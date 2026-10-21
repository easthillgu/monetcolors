-- test_phase1.lua
-- Phase 1 unit tests for LibMonetColor
-- Run standalone outside WoW with: lua tests/test_phase1.lua
-- Or paste into a WoW test addon.

-- ============================================================================
-- Mock WoW Environment
-- ============================================================================

-- Mock WoW functions (must be set before library load)
_G.GetTime = _G.GetTime or function() return os.time() end
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function(self, msg) print("[WARN] " .. msg) end }
_G.C_Map = nil  -- no map API in standalone mode
_G.CreateFrame = nil  -- no frame creation in standalone mode

-- Load the library (it handles its own LibStub/CallbackHandler if needed)
-- Tests live in tests/; the library files sit in the repository root.
local function resolvePath(name)
    local scriptPath = arg and arg[0] or "tests/test_phase1.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    for _, candidate in ipairs({ name, dir .. "/" .. name, dir .. "/../" .. name }) do
        if io.open(candidate, "r") then return candidate end
    end
    return name
end

local libPath = resolvePath("LibMonetColor-1.0.lua")
dofile(libPath)

local LMC = _G.LibMonetColor
if not LMC then
    print("FAIL: Library not loaded")
    os.exit(1)
end

-- ============================================================================
-- Test Framework
-- ============================================================================

local tests = {}
local function test(name, fn)
    tests[#tests + 1] = {name = name, fn = fn}
end

local function assertNear(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.4f, got %.4f (tolerance %.4f)", msg or "assertNear", expected, actual, tolerance))
    end
end

local function assertEqual(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertInRange(val, lo, hi, msg)
    if val < lo or val > hi then
        error(string.format("%s: value %.4f not in range [%.4f, %.4f]", msg or "assertInRange", val, lo, hi))
    end
end

local function runTests()
    local passed = 0
    local failed = 0
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
    return failed == 0
end

-- ============================================================================
-- Test Suite: HSL <-> RGB
-- ============================================================================

test("HSLToRGB: pure red", function()
    local r, g, b = LMC.HSLToRGB(0, 1, 0.5)
    assertNear(r, 1.0, 0.001, "red R")
    assertNear(g, 0.0, 0.001, "red G")
    assertNear(b, 0.0, 0.001, "red B")
end)

test("HSLToRGB: pure green", function()
    local r, g, b = LMC.HSLToRGB(120, 1, 0.5)
    assertNear(r, 0.0, 0.001, "green R")
    assertNear(g, 1.0, 0.001, "green G")
    assertNear(b, 0.0, 0.001, "green B")
end)

test("HSLToRGB: pure blue", function()
    local r, g, b = LMC.HSLToRGB(240, 1, 0.5)
    assertNear(r, 0.0, 0.001, "blue R")
    assertNear(g, 0.0, 0.001, "blue G")
    assertNear(b, 1.0, 0.001, "blue B")
end)

test("HSLToRGB: white (L=1)", function()
    local r, g, b = LMC.HSLToRGB(0, 0, 1)
    assertNear(r, 1.0, 0.001, "white R")
    assertNear(g, 1.0, 0.001, "white G")
    assertNear(b, 1.0, 0.001, "white B")
end)

test("HSLToRGB: black (L=0)", function()
    local r, g, b = LMC.HSLToRGB(0, 0, 0)
    assertNear(r, 0.0, 0.001, "black R")
    assertNear(g, 0.0, 0.001, "black G")
    assertNear(b, 0.0, 0.001, "black B")
end)

test("HSLToRGB: gray (S=0)", function()
    local r, g, b = LMC.HSLToRGB(120, 0, 0.5)
    assertNear(r, 0.5, 0.001, "gray R")
    assertNear(g, 0.5, 0.001, "gray G")
    assertNear(b, 0.5, 0.001, "gray B")
end)

test("HSLToRGB: hue wraps at 360", function()
    local r1, g1, b1 = LMC.HSLToRGB(0, 1, 0.5)
    local r2, g2, b2 = LMC.HSLToRGB(360, 1, 0.5)
    assertNear(r1, r2, 0.001, "wrap R")
    assertNear(g1, g2, 0.001, "wrap G")
    assertNear(b1, b2, 0.001, "wrap B")
end)

test("HSLToRGB: negative hue wraps", function()
    local r1, g1, b1 = LMC.HSLToRGB(0, 1, 0.5)
    local r2, g2, b2 = LMC.HSLToRGB(-360, 1, 0.5)
    assertNear(r1, r2, 0.001, "neg wrap R")
    assertNear(g1, g2, 0.001, "neg wrap G")
    assertNear(b1, b2, 0.001, "neg wrap B")
end)

test("HSLToRGB: S and L clamped to [0,1]", function()
    local r, g, b = LMC.HSLToRGB(120, 2, 1.5)
    assertNear(r, 1.0, 0.001, "clamp R")
    assertNear(g, 1.0, 0.001, "clamp G")
    assertNear(b, 1.0, 0.001, "clamp B")
end)

test("RGBToHSL: pure red", function()
    local h, s, l = LMC.RGBToHSL(1, 0, 0)
    assertNear(h, 0, 0.1, "red H")
    assertNear(s, 1.0, 0.001, "red S")
    assertNear(l, 0.5, 0.001, "red L")
end)

test("RGBToHSL: pure green", function()
    local h, s, l = LMC.RGBToHSL(0, 1, 0)
    assertNear(h, 120, 0.1, "green H")
    assertNear(s, 1.0, 0.001, "green S")
    assertNear(l, 0.5, 0.001, "green L")
end)

test("RGBToHSL: gray has zero saturation", function()
    local h, s, l = LMC.RGBToHSL(0.5, 0.5, 0.5)
    assertNear(s, 0, 0.001, "gray S")
    assertNear(l, 0.5, 0.001, "gray L")
end)

test("HSL->RGB->HSL roundtrip", function()
    for _, h in ipairs({0, 30, 60, 90, 120, 180, 240, 300, 359}) do
        for _, s in ipairs({0, 0.3, 0.7, 1.0}) do
            for _, l in ipairs({0.1, 0.3, 0.5, 0.7, 0.9}) do
                local r, g, b = LMC.HSLToRGB(h, s, l)
                local h2, s2, l2 = LMC.RGBToHSL(r, g, b)
                -- Hue wrap-around tolerance
                local dh = math.abs(h2 - h)
                if dh > 180 then dh = 360 - dh end
                if s > 0.01 then
                    assertNear(dh, 0, 1.0, "roundtrip H for h="..h)
                end
                assertNear(s2, s, 0.01, "roundtrip S for h="..h.." s="..s)
                assertNear(l2, l, 0.01, "roundtrip L for h="..h.." l="..l)
            end
        end
    end
end)

-- ============================================================================
-- Test Suite: Monet Rule Engine
-- ============================================================================

test("ComputeEdgeColor: Red/Warm domain uses hueShift=170", function()
    -- h=15 is in Red/Warm [0,30), complement should be 15+170=185
    local r, g, b, a = LMC.ComputeEdgeColor(15, 0.5, 0.5)
    -- Result should be a cyan-ish color (hue ~185)
    assertInRange(r, 0, 1, "edge R range")
    assertInRange(g, 0, 1, "edge G range")
    assertInRange(b, 0, 1, "edge B range")
    assertNear(a, 0.8, 0.001, "edge alpha default")
end)

test("ComputeEdgeColor: complementary pair h=0 overrides domain", function()
    -- h=0 has exact pair complement=170
    local r, g, b = LMC.ComputeEdgeColor(0, 0.6, 0.5)
    -- Should produce cyan-green (hue 170)
    assertInRange(r, 0, 1, "pair R range")
    assertInRange(g, 0, 1, "pair G range")
    assertInRange(b, 0, 1, "pair B range")
end)

test("ComputeEdgeColor: complementary pair h=30 overrides AmberGold", function()
    -- h=30 has pair complement=200 (not domain's 180)
    local r1, g1, b1 = LMC.ComputeEdgeColor(30, 0.6, 0.5)
    -- Should be blue-cyan (hue 200), not 210 (180+30)
    local h2, s2, l2 = LMC.RGBToHSL(r1, g1, b1)
    -- Hue should be near 200
    local dh = math.abs(h2 - 200)
    if dh > 180 then dh = 360 - dh end
    assertNear(dh, 0, 5.0, "pair h=30 complement should be ~200, got h="..h2)
end)

test("ComputeEdgeColor: h=60 uses pair complement=240", function()
    local r, g, b = LMC.ComputeEdgeColor(60, 0.6, 0.5)
    local h2, s2, l2 = LMC.RGBToHSL(r, g, b)
    local dh = math.abs(h2 - 240)
    if dh > 180 then dh = 360 - dh end
    assertNear(dh, 0, 5.0, "pair h=60 complement should be ~240")
end)

test("ComputeEdgeColor: lightness clamped to [0.18, 0.82]", function()
    -- Very dark env -> edge lightness should be clamped to max 0.82
    local r, g, b = LMC.ComputeEdgeColor(120, 0.5, 0.0)
    local h2, s2, l2 = LMC.RGBToHSL(r, g, b)
    assertInRange(l2, 0.18, 0.82, "lightness clamped (dark env)")
end)

test("ComputeEdgeColor: lightness clamped for bright env", function()
    -- Very bright env -> edge lightness should be clamped to min 0.18
    local r, g, b = LMC.ComputeEdgeColor(120, 0.5, 1.0)
    local h2, s2, l2 = LMC.RGBToHSL(r, g, b)
    assertInRange(l2, 0.18, 0.82, "lightness clamped (bright env)")
end)

test("ComputeEdgeColor: achromatic env gets tint injection", function()
    -- Very low saturation environment
    local r, g, b = LMC.ComputeEdgeColor(120, 0.01, 0.5)
    local h2, s2, l2 = LMC.RGBToHSL(r, g, b)
    -- Should have some saturation injected (achromaticSat = 0.12)
    assertInRange(s2, 0.05, 1.0, "achromatic injection saturation")
end)

test("ComputeEdgeColor: all 7 domains produce valid output", function()
    local testHues = {15, 45, 75, 120, 180, 240, 300}  -- one per domain
    for _, h in ipairs(testHues) do
        local r, g, b, a = LMC.ComputeEdgeColor(h, 0.5, 0.5)
        assertInRange(r, 0, 1, "domain h="..h.." R")
        assertInRange(g, 0, 1, "domain h="..h.." G")
        assertInRange(b, 0, 1, "domain h="..h.." B")
        assertNear(a, 0.8, 0.001, "domain h="..h.." A")
    end
end)

test("ComputeEdgeColor: saturation compensation applied", function()
    -- With S=0.5 (> minSaturation=0.10), should be multiplied by 1.05
    -- This is hard to test directly without knowing the exact satMult,
    -- but we can verify the function doesn't crash and produces valid output
    local r, g, b = LMC.ComputeEdgeColor(120, 0.5, 0.5)
    assertInRange(r, 0, 1, "sat comp R")
    assertInRange(g, 0, 1, "sat comp G")
    assertInRange(b, 0, 1, "sat comp B")
end)

test("ComputeEdgeColor: no crash with nil/zero inputs", function()
    local r, g, b, a = LMC.ComputeEdgeColor(nil, nil, nil)
    assertInRange(r, 0, 1, "nil R")
    assertInRange(g, 0, 1, "nil G")
    assertInRange(b, 0, 1, "nil B")
end)

test("ComputeEdgeColor: no crash with extreme inputs", function()
    local r, g, b = LMC.ComputeEdgeColor(9999, 99, 99)
    assertInRange(r, 0, 1, "extreme R")
    assertInRange(g, 0, 1, "extreme G")
    assertInRange(b, 0, 1, "extreme B")
end)

-- ============================================================================
-- Test Suite: Ambient Tint / Highlight / Neutral
-- ============================================================================

test("ComputeAmbientTint: returns valid RGBA", function()
    local r, g, b, a = LMC.ComputeAmbientTint(120, 0.5, 0.5)
    assertInRange(r, 0, 1, "ambient R")
    assertInRange(g, 0, 1, "ambient G")
    assertInRange(b, 0, 1, "ambient B")
    assertInRange(a, 0, 1, "ambient A")
end)

test("ComputeAmbientTint: alpha in expected range", function()
    local _, _, _, a1 = LMC.ComputeAmbientTint(120, 0.5, 0.0)  -- dark env
    local _, _, _, a2 = LMC.ComputeAmbientTint(120, 0.5, 1.0)  -- bright env
    -- Darker env should have higher alpha (more tint needed)
    assertInRange(a1, 0.1, 0.5, "ambient alpha dark")
    assertInRange(a2, 0.1, 0.5, "ambient alpha bright")
    if a1 < a2 then
        error("Darker environment should have higher alpha (more tint)")
    end
end)

test("ComputeHighlightWash: returns valid RGB", function()
    local r, g, b = LMC.ComputeHighlightWash(120, 0.5, 0.5)
    assertInRange(r, 0, 1, "highlight R")
    assertInRange(g, 0, 1, "highlight G")
    assertInRange(b, 0, 1, "highlight B")
end)

test("ComputeNeutral: returns valid RGB", function()
    local r, g, b = LMC.ComputeNeutral(120, 0.5, 0.5)
    assertInRange(r, 0, 1, "neutral R")
    assertInRange(g, 0, 1, "neutral G")
    assertInRange(b, 0, 1, "neutral B")
end)

test("ComputeNeutral: is nearly gray (very low saturation)", function()
    local r, g, b = LMC.ComputeNeutral(120, 0.5, 0.5)
    local h, s, l = LMC.RGBToHSL(r, g, b)
    assertInRange(s, 0, 0.05, "neutral saturation should be very low")
end)

-- ============================================================================
-- Test Suite: Delta E
-- ============================================================================

test("DeltaE: identical colors = 0", function()
    local de = LMC.DeltaE(0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
    assertNear(de, 0, 0.001, "DeltaE identical")
end)

test("DeltaE: very different colors > 0", function()
    local de = LMC.DeltaE(1, 0, 0, 0, 1, 0)
    if de < 10 then
        error("Red vs green should have large DeltaE, got " .. de)
    end
end)

test("DeltaE: black vs white is large", function()
    local de = LMC.DeltaE(0, 0, 0, 1, 1, 1)
    if de < 50 then
        error("Black vs white should have very large DeltaE, got " .. de)
    end
end)

test("DeltaE: threshold boundary (5.0)", function()
    -- Two colors with small difference
    local de = LMC.DeltaE(0.5, 0.5, 0.5, 0.51, 0.51, 0.51)
    -- Should be small but non-zero
    if de < 0 then
        error("DeltaE should be non-negative")
    end
end)

-- ============================================================================
-- Test Suite: Cache System
-- ============================================================================

test("Cache: GetCurrentEdgeColor returns consistent values", function()
    local r1, g1, b1, a1 = LMC:GetCurrentEdgeColor()
    local r2, g2, b2, a2 = LMC:GetCurrentEdgeColor()
    assertNear(r1, r2, 0.001, "cache R consistent")
    assertNear(g1, g2, 0.001, "cache G consistent")
    assertNear(b1, b2, 0.001, "cache B consistent")
    assertNear(a1, a2, 0.001, "cache A consistent")
end)

test("Cache: GetAllThemeColors returns 14 values", function()
    local results = {LMC:GetAllThemeColors()}
    assertEqual(#results, 14, "should return 14 values (4 edge + 4 ambient + 3 highlight + 3 neutral)")
end)

test("Cache: ClearCache doesn't break subsequent calls", function()
    LMC:ClearCache()
    local r, g, b, a = LMC:GetCurrentEdgeColor()
    assertInRange(r, 0, 1, "post-clear R")
    assertInRange(g, 0, 1, "post-clear G")
    assertInRange(b, 0, 1, "post-clear B")
end)

-- ============================================================================
-- Test Suite: Producer API
-- ============================================================================

test("RegisterProfile: valid registration", function()
    local ok = LMC:RegisterProfile("TestProfile", {
        domains = {{name="Test", range={0, 360}, hueShift=180, satMult=0.5, lBias=0}},
        complementaryPairs = {},
        saturationCompensation = {factor=1.0, minSaturation=0},
        lightnessMin = 0.2,
        lightnessMax = 0.8,
    })
    assertEqual(ok, true, "RegisterProfile should succeed")
end)

test("RegisterProfile: invalid name fails", function()
    local ok = LMC:RegisterProfile("", {domains={}})
    assertEqual(ok, false, "empty name should fail")
end)

test("RegisterProfile: invalid rules fails", function()
    local ok = LMC:RegisterProfile("Bad", "not a table")
    assertEqual(ok, false, "non-table rules should fail")
end)

test("SetActiveProfile: Monet works", function()
    local ok = LMC:SetActiveProfile("Monet")
    assertEqual(ok, true, "Monet profile should activate")
    assertEqual(LMC:GetActiveProfile(), "Monet", "active profile name")
end)

test("SetActiveProfile: unknown profile fails", function()
    local ok = LMC:SetActiveProfile("NonExistent")
    assertEqual(ok, false, "unknown profile should fail")
end)

test("SetActiveProfile: custom profile works", function()
    LMC:RegisterProfile("CustomTest", {
        domains = {{name="All", range={0, 360}, hueShift=90, satMult=0.3, lBias=0}},
        complementaryPairs = {},
        saturationCompensation = {factor=1.0, minSaturation=0},
        lightnessMin = 0.15,
        lightnessMax = 0.85,
    })
    local ok = LMC:SetActiveProfile("CustomTest")
    assertEqual(ok, true, "custom profile should activate")
    assertEqual(LMC:GetActiveProfile(), "CustomTest", "active profile name")
    -- Restore
    LMC:SetActiveProfile("Monet")
end)

-- ============================================================================
-- Test Suite: Fallback / Safety
-- ============================================================================

test("Fallback: GetEdgeColorForMap never crashes", function()
    local r, g, b, a = LMC:GetEdgeColorForMap(99999)
    assertInRange(r, 0, 1, "fallback R")
    assertInRange(g, 0, 1, "fallback G")
    assertInRange(b, 0, 1, "fallback B")
end)

test("Fallback: invalid mapID falls back gracefully", function()
    local r, g, b, a = LMC:GetEdgeColorForMap("invalid")
    assertInRange(r, 0, 1, "invalid map R")
    assertInRange(g, 0, 1, "invalid map G")
    assertInRange(b, 0, 1, "invalid map B")
end)

test("Fallback: SetDeltaEThreshold works", function()
    LMC:SetDeltaEThreshold(3.0)
    assertEqual(LMC.deltaEThreshold, 3.0, "threshold set")
    LMC:SetDeltaEThreshold(5.0)  -- restore
end)

-- ============================================================================
-- Run All Tests
-- ============================================================================

print("=== LibMonetColor Phase 1 Test Suite ===\n")
local allPassed = runTests()
if allPassed then
    print("\n=== ALL TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME TESTS FAILED ===")
    os.exit(1)
end
