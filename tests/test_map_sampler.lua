-- test_map_sampler.lua
-- T2.1 tests: environment sampling from MonetColorMapData-1.0 zone data.
-- Run standalone: lua tests/test_map_sampler.lua
--
-- Covers:
--   1. Data module loading (LibStub + global alias, double-load guard)
--   2. GetMapEnv resolution: override -> data -> parent chain -> fallback
--   3. Fallback behavior for unknown maps and invalid inputs
--   4. Runtime extension: RegisterMapEnv / SetFallbackEnv
--   5. End-to-end wiring: default sampler feeds ComputeEdgeColor per map

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

local function resolvePath(name)
    -- Tests live in tests/; the library files sit in the repository root.
    local scriptPath = arg and arg[0] or "tests/test_map_sampler.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    for _, candidate in ipairs({ name, dir .. "/" .. name, dir .. "/../" .. name }) do
        if io.open(candidate, "r") then return candidate end
    end
    return name
end

dofile(resolvePath("LibMonetColor-1.0.lua"))
local LMC = _G.LibMonetColor

-- Probe the no-data-module state BEFORE loading the data module. The library
-- must resolve unknown maps to its fallback env without erroring.
local preDataH, preDataS, preDataL, _, preDataSource = LMC:GetMapEnv(1413)

local libPath = resolvePath("LibMonetColor-1.0.lua")
local dataPath = resolvePath("MonetColorMapData-1.0.lua")
dofile(dataPath)

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
-- 1. Data module loading
-- ============================================================================

test("Data module: registers via LibStub and sets global alias", function()
    local MDM = LibStub("MonetColorMapData-1.0", true)
    assertTrue(MDM ~= nil, "LibStub lookup returned nil")
    assertTrue(type(MDM.MapEnv) == "table", "MapEnv table missing")
    assertTrue(_G.LibMonetColorMapData == MDM, "global alias differs from LibStub object")
    assertTrue(type(MDM.Source) == "string", "Source annotation missing")
end)

test("Data module: double-load is a no-op (minor guard)", function()
    local before = LibStub("MonetColorMapData-1.0", true)
    dofile(dataPath)
    local after = LibStub("MonetColorMapData-1.0", true)
    assertTrue(after == before, "reload replaced the registered data module")
end)

test("Fallback before data load: probed state resolved to fallback env", function()
    assertTrue(preDataSource == "fallback", "expected source 'fallback' without data module")
    assertNear(preDataH, 0, 0.001, "pre-data h")
    assertNear(preDataS, 0, 0.001, "pre-data s")
    assertNear(preDataL, 0.5, 0.001, "pre-data l")
end)

-- ============================================================================
-- 2. GetMapEnv: exact data hits
-- ============================================================================

test("GetMapEnv: every data zone resolves with sane values", function()
    local MDM = LibStub("MonetColorMapData-1.0")
    local count = 0
    for mapID, entry in pairs(MDM.MapEnv) do
        local h, s, l, name, source = LMC:GetMapEnv(mapID)
        assertNear(h, entry.h, 0.001, "h for " .. mapID)
        assertNear(s, entry.s, 0.001, "s for " .. mapID)
        assertNear(l, entry.l, 0.001, "l for " .. mapID)
        assertTrue(source == "data", "source should be 'data' for " .. tostring(mapID))
        assertTrue(h >= 0 and h < 360, "h out of range for " .. tostring(mapID))
        assertTrue(s >= 0 and s <= 1, "s out of range for " .. tostring(mapID))
        assertTrue(l >= 0 and l <= 1, "l out of range for " .. tostring(mapID))
        assertTrue(type(name) == "string" and name ~= "", "name missing for " .. tostring(mapID))
        count = count + 1
    end
    assertTrue(count >= 14, "expected at least 14 zones, got " .. count)
end)

test("GetMapEnv: spot-checks match game_palette_v1.json", function()
    local h, s, l, name = LMC:GetMapEnv(1454)  -- Orgrimmar: dark red rock
    assertNear(h, 11.5, 0.01, "Orgrimmar h")
    assertNear(s, 0.582, 0.001, "Orgrimmar s")
    assertNear(l, 0.234, 0.001, "Orgrimmar l")
    assertTrue(name == "奥格瑞玛", "Orgrimmar name mismatch")

    h, s, l = LMC:GetMapEnv(2521)  -- Zephra's Isle: misty mauve
    assertNear(h, 331.8, 0.01, "Zephra h")
    assertNear(s, 0.139, 0.001, "Zephra s")

    h = LMC:GetMapEnv(1440)  -- Ashenvale: saturated green
    assertNear(h, 149.4, 0.01, "Ashenvale h")
end)

-- ============================================================================
-- 3. Fallback for unknown maps / invalid inputs
-- ============================================================================

test("GetMapEnv: unknown map falls back to neutral achromatic env", function()
    local h, s, l, name, source = LMC:GetMapEnv(1234567)
    assertNear(h, 0, 0.001, "fallback h")
    assertNear(s, 0, 0.001, "fallback s")
    assertNear(l, 0.5, 0.001, "fallback l")
    assertTrue(name == nil, "fallback should carry no zone name")
    assertTrue(source == "fallback", "source should be 'fallback'")
end)

test("GetMapEnv: invalid inputs never throw and resolve to fallback", function()
    for _, bad in ipairs({nil, 0, -5, "abc", {}, true}) do
        local ok, h, s, l, _, source = pcall(function() return LMC:GetMapEnv(bad) end)
        assertTrue(ok, "GetMapEnv threw for input " .. tostring(bad))
        assertNear(h, 0, 0.001, "invalid-input h")
        assertNear(s, 0, 0.001, "invalid-input s")
        assertNear(l, 0.5, 0.001, "invalid-input l")
        assertTrue(source == "fallback", "invalid input should hit fallback")
    end
end)

test("GetMapEnv: string mapID is coerced (tolerant input)", function()
    local h, _, _, _, source = LMC:GetMapEnv("1454")
    assertNear(h, 11.5, 0.01, "string mapID lookup")
    assertTrue(source == "data", "string mapID should resolve via data")
end)

-- ============================================================================
-- 4. Runtime extension API
-- ============================================================================

test("SetFallbackEnv: changes the fallback resolution", function()
    assertTrue(LMC:SetFallbackEnv(200, 0.3, 0.4), "SetFallbackEnv failed")
    local h, s, l, _, source = LMC:GetMapEnv(7654321)
    assertNear(h, 200, 0.001, "custom fallback h")
    assertNear(s, 0.3, 0.001, "custom fallback s")
    assertNear(l, 0.4, 0.001, "custom fallback l")
    assertTrue(source == "fallback", "source should remain 'fallback'")
    -- invalid args rejected, state kept
    assertTrue(LMC:SetFallbackEnv(nil, 1, 1) == false, "SetFallbackEnv accepted nil h")
    h = LMC:GetMapEnv(7654321)
    assertNear(h, 200, 0.001, "fallback kept after rejected update")
    -- restore default
    assertTrue(LMC:SetFallbackEnv(0, 0, 0.5), "fallback restore failed")
end)

test("RegisterMapEnv: override wins over data module", function()
    assertTrue(LMC:RegisterMapEnv(1454, 300, 0.5, 0.5, "Orgrimmar Override"),
        "RegisterMapEnv failed")
    local h, s, l, name, source = LMC:GetMapEnv(1454)
    assertNear(h, 300, 0.001, "override h")
    assertTrue(name == "Orgrimmar Override", "override name mismatch")
    assertTrue(source == "override", "source should be 'override'")
    -- invalid args rejected
    assertTrue(LMC:RegisterMapEnv(0, 10, 0.1, 0.1) == false, "accepted mapID 0")
    assertTrue(LMC:RegisterMapEnv(9999, nil, 0.1, 0.1) == false, "accepted nil h")
    LMC.overrideEnv[1454] = nil  -- restore data-module lookup
    local backH, _, _, _, backSource = LMC:GetMapEnv(1454)
    assertNear(backH, 11.5, 0.01, "data lookup restored")
    assertTrue(backSource == "data", "source restored to 'data'")
end)

test("RegisterMapEnv: numeric sanitization (hue wrap, s/l clamp)", function()
    assertTrue(LMC:RegisterMapEnv(999997, 720, 5, -1), "register failed")
    local h, s, l = LMC:GetMapEnv(999997)
    assertNear(h, 0, 0.001, "hue wrapped to [0,360)")
    assertNear(s, 1, 0.001, "s clamped to 1")
    assertNear(l, 0, 0.001, "l clamped to 0")
    LMC.overrideEnv[999997] = nil
end)

-- ============================================================================
-- 5. Parent-map chain (mocked C_Map)
-- ============================================================================

test("GetMapEnv: subzone map inherits parent zone env via C_Map", function()
    _G.C_Map = {
        GetMapInfo = function(mapID)
            if mapID == 90001 then return { parentMapID = 1429 } end  -- -> Elwynn Forest
            return { parentMapID = 0 }
        end,
    }
    local h, s, l, name, source = LMC:GetMapEnv(90001)
    assertNear(h, 77.2, 0.01, "parent h")
    assertTrue(name == "艾尔文森林", "parent zone name mismatch")
    assertTrue(source == "parent:data", "source should be 'parent:data'")
    _G.C_Map = nil
end)

-- ============================================================================
-- 6. End-to-end wiring
-- ============================================================================

test("Default sampler: known map edge color matches ComputeEdgeColor(env)", function()
    local envH, envS, envL = LMC:GetMapEnv(1413)
    local er, eg, eb, ea = LMC:GetEdgeColorForMap(1413)
    local cr, cg, cb, ca = LMC.ComputeEdgeColor(envH, envS, envL, LMC:GetRules())
    assertNear(er, cr, 0.0001, "edge r wiring")
    assertNear(eg, cg, 0.0001, "edge g wiring")
    assertNear(eb, cb, 0.0001, "edge b wiring")
    assertNear(ea, ca, 0.0001, "edge a wiring")
end)

test("Default sampler: known vs unknown maps yield different edge colors", function()
    local r1, g1, b1 = LMC:GetEdgeColorForMap(1440)  -- Ashenvale (green env)
    local r2, g2, b2 = LMC:GetEdgeColorForMap(999999)  -- fallback (achromatic)
    local diff = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
    assertTrue(diff > 0.05, "known and fallback maps must differ")
end)

test("Default sampler: fallback env routes through achromatic injection", function()
    local fr, fg, fb = LMC:GetEdgeColorForMap(888888)
    local cr, cg, cb = LMC.ComputeEdgeColor(0, 0, 0.5, LMC:GetRules())
    assertNear(fr, cr, 0.0001, "fallback edge r")
    assertNear(fg, cg, 0.0001, "fallback edge g")
    assertNear(fb, cb, 0.0001, "fallback edge b")
end)

test("AllThemeColors: works for every data zone without errors", function()
    for mapID in pairs(LibStub("MonetColorMapData-1.0").MapEnv) do
        local ok, er, eg, eb, ea, ar, ag, ab, aa, hr, hg, hb, nr, ng, nb =
            pcall(function() return LMC:GetAllThemeColors() end)
        -- GetAllThemeColors samples the CURRENT map (0 here), so it cannot see
        -- per-map data; instead verify per-map edge via GetEdgeColorForMap.
        assertTrue(ok, "GetAllThemeColors threw: " .. tostring(er))
        assertTrue(er >= 0 and er <= 1, "theme color out of range")
        local r, g, b, a = LMC:GetEdgeColorForMap(mapID)
        assertTrue(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1,
            "edge RGB out of range for map " .. mapID)
        assertTrue(a == 0.8, "edge alpha contract broken for map " .. mapID)
    end
end)

-- ============================================================================
-- Run
-- ============================================================================

print("=== LibMonetColor T2.1 map sampler suite ===\n")
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
    print("\n=== ALL T2.1 MAP SAMPLER TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME T2.1 MAP SAMPLER TESTS FAILED ===")
    os.exit(1)
end
