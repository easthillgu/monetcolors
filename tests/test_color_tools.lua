-- test_color_tools.lua
-- Unit tests for the 1.2.0 Color Tools (LMC.ContrastRatio / LMC.AtLightness).
-- Run standalone outside WoW with: lua tests/test_color_tools.lua

-- ============================================================================
-- Mock WoW Environment
-- ============================================================================

_G.GetTime = _G.GetTime or function() return os.time() end
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function(self, msg) print("[WARN] " .. msg) end }
_G.C_Map = nil
_G.CreateFrame = nil

local libPath = (function()
    local scriptPath = arg and arg[0] or "tests/test_color_tools.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    for _, candidate in ipairs({ "LibMonetColor-1.0.lua", dir .. "/LibMonetColor-1.0.lua", dir .. "/../LibMonetColor-1.0.lua" }) do
        if io.open(candidate, "r") then return candidate end
    end
    return "LibMonetColor-1.0.lua"
end)()
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

local function assertColor(r, g, b, msg)
    assertInRange(r, 0, 1, (msg or "color") .. " R")
    assertInRange(g, 0, 1, (msg or "color") .. " G")
    assertInRange(b, 0, 1, (msg or "color") .. " B")
end

local function lightnessOf(r, g, b)
    return (LMC.RGBToLab(r, g, b))
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

-- A stand-in for a WoW secret number: touching it in any comparison throws.
local function secretValue()
    return setmetatable({}, {
        __lt = function() error("attempt to compare a secret number value") end,
        __tostring = function() error("attempt to use a secret value") end,
    })
end

-- ============================================================================
-- Test Suite: surface of the tools
-- ============================================================================

test("Tools: exposed as plain functions, not methods", function()
    assertEqual(type(LMC.ContrastRatio), "function", "ContrastRatio type")
    assertEqual(type(LMC.AtLightness), "function", "AtLightness type")
end)

test("Tools: pure -- they leave the cache and profile untouched", function()
    local before = LMC.activeProfile
    local cachedBefore = LMC.colorCache["x"]
    LMC.ContrastRatio(0, 0, 0, 1, 1, 1)
    LMC.AtLightness(0.2, 0.4, 0.6, 50)
    assertEqual(LMC.activeProfile, before, "profile untouched")
    assertEqual(LMC.colorCache["x"], cachedBefore, "cache entry untouched")
end)

-- ============================================================================
-- Test Suite: ContrastRatio
-- ============================================================================

test("ContrastRatio: black on white is 21", function()
    assertNear(LMC.ContrastRatio(0, 0, 0, 1, 1, 1), 21, 0.01, "black/white")
end)

test("ContrastRatio: a color against itself is 1", function()
    assertNear(LMC.ContrastRatio(0.31, 0.72, 0.05, 0.31, 0.72, 0.05), 1, 0.0001, "same color")
end)

test("ContrastRatio: order does not matter", function()
    local a = LMC.ContrastRatio(0.11, 0.22, 0.33, 0.9, 0.8, 0.7)
    local b = LMC.ContrastRatio(0.9, 0.8, 0.7, 0.11, 0.22, 0.33)
    assertNear(a, b, 0.0001, "symmetric")
end)

test("ContrastRatio: mid grey against black is 5.28 (WCAG relative luminance)", function()
    assertNear(LMC.ContrastRatio(0, 0, 0, 0.5, 0.5, 0.5), 5.281, 0.01, "grey/black")
end)

test("ContrastRatio: same-luminance different-hue colors do not read as contrast", function()
    -- The exact failure mode this whole layer exists for: equal lightness = invisible
    -- separation, no matter how different the hue is.
    local r = LMC.ContrastRatio(0.30, 0.10, 0.10, 0.10, 0.30, 0.10)
    assertInRange(r, 1, 2, "hue-only difference stays weak")
end)

test("ContrastRatio: components clamp out-of-range input", function()
    local clamped = LMC.ContrastRatio(-5, 0, 0, 7, 1, 1)
    local plain = LMC.ContrastRatio(0, 0, 0, 1, 1, 1)
    assertNear(clamped, plain, 0.0001, "clamped equals plain")
end)

test("ContrastRatio: monotone in lightness distance", function()
    local base = 0.20
    local near = LMC.ContrastRatio(base, base, base, 0.24, 0.24, 0.24)
    local far = LMC.ContrastRatio(base, base, base, 0.60, 0.60, 0.60)
    if not (far > near) then error("expected far > near, got " .. far .. " vs " .. near) end
    if not (near >= 1) then error("ratio must be >= 1, got " .. near) end
end)

test("ContrastRatio: nil argument answers 1 (the conservative conclusion)", function()
    assertEqual(LMC.ContrastRatio(nil, 0, 0, 1, 1, 1), 1, "nil R")
    assertEqual(LMC.ContrastRatio(0, 0, 0, 1, nil, 1), 1, "nil B of second color")
    assertEqual(LMC.ContrastRatio(0, 0, 0), 1, "missing triad")
end)

test("ContrastRatio: non-numeric and NaN arguments answer 1", function()
    assertEqual(LMC.ContrastRatio("abc", 0, 0, 1, 1, 1), 1, "string")
    local nan = 0 / 0
    assertEqual(LMC.ContrastRatio(nan, 0, 0, 1, 1, 1), 1, "NaN")
    assertEqual(LMC.ContrastRatio({}, 0, 0, 1, 1, 1), 1, "table")
end)

test("ContrastRatio: a secret value never escapes as an error", function()
    local ok, ratio = pcall(LMC.ContrastRatio, secretValue(), 0, 0, 1, 1, 1)
    if not ok then error("threw on secret input: " .. tostring(ratio)) end
    assertEqual(ratio, 1, "secret answers 1")
end)

-- ============================================================================
-- Test Suite: AtLightness
-- ============================================================================

test("AtLightness: black up to L*50", function()
    local r, g, b = LMC.AtLightness(0, 0, 0, 50)
    assertColor(r, g, b, "L50 from black")
    assertNear(lightnessOf(r, g, b), 50, 0.5, "reached L*50")
end)

test("AtLightness: white down to L*30", function()
    local r, g, b = LMC.AtLightness(1, 1, 1, 30)
    assertNear(lightnessOf(r, g, b), 30, 0.5, "reached L*30")
end)

test("AtLightness: already there returns the color untouched", function()
    local r, g, b = LMC.AtLightness(0.2, 0.4, 0.6, 45)
    local cur = lightnessOf(r, g, b)
    local r2, g2, b2 = LMC.AtLightness(r, g, b, cur)
    assertNear(r2, r, 0.0001, "idempotent R")
    assertNear(g2, g, 0.0001, "idempotent G")
    assertNear(b2, b, 0.0001, "idempotent B")
end)

test("AtLightness: hue preserved", function()
    local h0 = (LMC.RGBToHSL(0.72, 0.12, 0.20))
    local r, g, b = LMC.AtLightness(0.72, 0.12, 0.20, 40)
    local h1 = (LMC.RGBToHSL(r, g, b))
    assertNear(h1, h0, 0.6, "hue stable")
end)

test("AtLightness: saturation preserved", function()
    local _, s0 = LMC.RGBToHSL(0.72, 0.12, 0.20)
    local r, g, b = LMC.AtLightness(0.72, 0.12, 0.20, 55)
    local _, s1 = LMC.RGBToHSL(r, g, b)
    assertNear(s1, s0, 0.02, "saturation stable")
end)

test("AtLightness: monotone in the target", function()
    local lr, lg, lb = LMC.AtLightness(0.72, 0.12, 0.20, 25)
    local hr, hg, hb = LMC.AtLightness(0.72, 0.12, 0.20, 75)
    local low, high = lightnessOf(lr, lg, lb), lightnessOf(hr, hg, hb)
    if not (high > low) then error("expected L*(75) > L*(25), got " .. high .. " vs " .. low) end
end)

test("AtLightness: a ladder spreads contrast where fixed multipliers did not", function()
    -- Panel / empty slot / fill, 14 L* apart on one neutral family. This is the
    -- shape the consumer layer wants; the tools must actually deliver the gap.
    local pr, pg, pb = LMC.AtLightness(0.06, 0.09, 0.14, 12)
    local lr, lg, lb = LMC.AtLightness(0.06, 0.09, 0.14, 26)
    local fr, fg, fb = LMC.AtLightness(0.06, 0.09, 0.14, 40)
    local panelLost = LMC.ContrastRatio(pr, pg, pb, lr, lg, lb)
    local lostFill = LMC.ContrastRatio(lr, lg, lb, fr, fg, fb)
    if not (panelLost > 1.3) then error("panel/lost CR too weak: " .. panelLost) end
    if not (lostFill > 1.3) then error("lost/fill CR too weak: " .. lostFill) end
end)

test("AtLightness: out-of-gamut target returns the closest reachable color", function()
    -- Fully saturated yellow cannot get as dark as L*5 without losing saturation,
    -- which this function must not do silently. Answer: stay in range, keep the hue.
    local r, g, b = LMC.AtLightness(1, 1, 0, 5)
    assertColor(r, g, b, "out of gamut")
    local h0 = (LMC.RGBToHSL(1, 1, 0))
    local h1 = (LMC.RGBToHSL(r, g, b))
    assertNear(h1, h0, 1.0, "hue kept even when target unreachable")
    local reached = lightnessOf(r, g, b)
    if not (reached >= 0 and reached <= 100) then error("L* out of range: " .. reached) end
end)

test("AtLightness: target clamps below 0 and above 100", function()
    local dr, dg, db = LMC.AtLightness(0.5, 0.2, 0.8, -40)
    local ur, ug, ub = LMC.AtLightness(0.5, 0.2, 0.8, 180)
    local dark = lightnessOf(dr, dg, db)
    local bright = lightnessOf(ur, ug, ub)
    if not (dark <= 0.6) then error("expected near black, got L* " .. dark) end
    if not (bright >= 99.4) then error("expected near white, got L* " .. bright) end
end)

test("AtLightness: all outputs stay inside [0,1] across a sweep", function()
    local seeds = { { 0, 0, 0 }, { 1, 1, 1 }, { 0.72, 0.12, 0.20 }, { 0.05, 0.35, 0.9 }, { 0.4, 0.4, 0.4 } }
    for _, c in ipairs(seeds) do
        for target = 0, 100, 10 do
            local r, g, b = LMC.AtLightness(c[1], c[2], c[3], target)
            assertColor(r, g, b, string.format("seed %.2f/%.2f/%.2f @ L*%d", c[1], c[2], c[3], target))
        end
    end
end)

test("AtLightness: unreadable color falls back to the contract neutral grey", function()
    local r, g, b = LMC.AtLightness(nil, 0.2, 0.3, 50)
    assertNear(r, 0.5, 0.0001, "grey R")
    assertNear(g, 0.5, 0.0001, "grey G")
    assertNear(b, 0.5, 0.0001, "grey B")

    local ok, sr = pcall(LMC.AtLightness, secretValue(), 0.2, 0.3, 50)
    if not ok then error("threw on secret input: " .. tostring(sr)) end
    assertNear(sr, 0.5, 0.0001, "secret answers grey")
end)

test("AtLightness: unreadable target returns the color unchanged", function()
    local r, g, b = LMC.AtLightness(0.22, 0.44, 0.66, nil)
    assertNear(r, 0.22, 0.0001, "R kept")
    assertNear(g, 0.44, 0.0001, "G kept")
    assertNear(b, 0.66, 0.0001, "B kept")
end)

-- ============================================================================
-- Run All Tests
-- ============================================================================

print("=== LibMonetColor Color Tools Test Suite ===\n")
local allPassed = runTests()
if allPassed then
    print("\n=== ALL TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME TESTS FAILED ===")
    os.exit(1)
end
