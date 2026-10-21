-- test_libstub_order.lua
-- Regression tests for the LibStub load-order hardening.
-- Run standalone: lua tests/test_libstub_order.lua
--
-- Covers the four ways the library meets (or misses) LibStub:
--   1. No LibStub at load  -> a standalone shim is published and the library
--      is reachable through it exactly like in WoW.
--   2. Reload without LibStub -> no error, and state is not split across two
--      tables (the double-load guard still applies).
--   3. A tooling-side minor bump -> the shim is re-bound to the new table.
--   4. LibStub appears AFTER the library -> it is adopted, so
--      LibStub("LibMonetColor-1.0") resolves instead of returning nil.

-- ============================================================================
-- Clean slate: this suite is specifically about the "no LibStub at load" path,
-- so every global the library touches is cleared first.
-- ============================================================================

_G.LibStub = nil
_G.LibMonetColor = nil
_G.LibMonetColorMapData = nil

_G.GetTime = _G.GetTime or function() return os.time() end
_G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function(_, msg) print("[WARN] " .. msg) end }
_G.C_Map = nil
_G.CreateFrame = nil

local function resolvePath(name)
    -- Tests live in tests/; the library files sit in the repository root.
    local scriptPath = arg and arg[0] or "tests/test_libstub_order.lua"
    local dir = scriptPath:match("^(.*)[\\/]") or "."
    for _, candidate in ipairs({ name, dir .. "/" .. name, dir .. "/../" .. name }) do
        if io.open(candidate, "r") then return candidate end
    end
    return name
end

local libPath = resolvePath("LibMonetColor-1.0.lua")
dofile(libPath)

-- ============================================================================
-- Test framework
-- ============================================================================

local tests = {}
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

local function assertTrue(cond, msg)
    if not cond then error(msg or "assertion failed", 2) end
end
local function assertEqual(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertEqual", tostring(expected), tostring(actual)))
    end
end

-- ============================================================================
-- 1. Standalone shim
-- ============================================================================

test("standalone: a shim is published and resolves the library", function()
    assertTrue(type(_G.LibStub) == "function", "expected the standalone shim, got " .. type(_G.LibStub))
    local lib = _G.LibMonetColor
    assertTrue(type(lib) == "table", "global alias missing")
    assertTrue(type(lib.GetCurrentEdgeColor) == "function", "library object is missing methods")
    assertEqual(_G.LibStub("LibMonetColor-1.0", true), lib, "shim should return the library")
    assertEqual(_G.LibStub("SomethingElse-9.9", true), nil, "shim should not invent other libraries")
end)

test("standalone: reload is a no-op and does not split state", function()
    local before = _G.LibMonetColor
    before:SetDeltaEThreshold(7.5)          -- a marker we can find again
    local ok, err = pcall(dofile, libPath)
    assertTrue(ok, "reloading without LibStub errored: " .. tostring(err))
    local after = _G.LibMonetColor
    assertEqual(after, before, "reload replaced the library table")
    assertEqual(_G.LibStub("LibMonetColor-1.0", true), before, "shim and alias diverged")
    assertEqual(before.deltaEThreshold, 7.5, "state lost across reload")
    before:SetDeltaEThreshold(5.0)
end)

test("standalone: a stale shim from an older minor is re-bound, not left behind", function()
    -- What a previous, older-minor load would have left in the global.
    local stale = {Version = 10000, GetCurrentEdgeColor = function() return 0.1, 0.1, 0.1, 0.8 end}
    _G.LibStub = function(name)
        if name == "LibMonetColor-1.0" then return stale end
        return nil
    end
    _G.LibMonetColor = stale

    dofile(libPath)

    local after = _G.LibMonetColor
    assertTrue(after ~= stale, "a newer minor must not keep the stale table")
    -- The minor is read from the source so a version bump does not have to
    -- touch this test.
    local source = io.open(libPath, "r"):read("*a")
    local minor = tonumber(source:match('local MAJOR, MINOR = "LibMonetColor%-1%.0", (%d+)'))
    assertTrue(minor ~= nil, "the minor could not be read from the source")
    assertEqual(after.Version, minor, "new table should carry the current minor")
    assertEqual(_G.LibStub("LibMonetColor-1.0", true), after, "shim must be re-bound to the new table")
    assertTrue(type(after.GetCurrentEdgeColor) == "function", "re-bound library is not functional")
end)

-- ============================================================================
-- 2. Late LibStub adoption
-- ============================================================================
test("adopt: a real LibStub loaded later wins and takes the library with it", function()
    local before = _G.LibMonetColor
    before:SetDeltaEThreshold(8.25)         -- state that must survive adoption

    -- A realistic LibStub, installed only now (after the library loaded).
    local registry, minors = {}, {}
    _G.LibStub = setmetatable({
        NewLibrary = function(_, major, minor)
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

    -- Any public call runs the deferred adoption.
    local r = _G.LibMonetColor:GetCurrentEdgeColor()
    assertTrue(type(r) == "number" and r >= 0 and r <= 1, "edge colour should still be valid")

    local after = _G.LibMonetColor
    assertTrue(after ~= before, "library table should have moved into LibStub's registry")
    assertEqual(_G.LibStub("LibMonetColor-1.0", true), after, "LibStub lookup must resolve the library")
    assertTrue(type(after.GetCurrentEdgeColor) == "function", "methods missing after adoption")
    assertEqual(after.deltaEThreshold, 8.25, "state lost across adoption")
    assertEqual(after.standaloneLibStub, nil, "standalone marker should be cleared")

    -- The adopted table must be fully functional, not just present.
    local er, eg, eb, ea = after:GetAllThemeColors()
    assertTrue(er >= 0 and er <= 1 and ea == 0.8, "adopted library returned bad values")
end)

-- ============================================================================
-- Run
-- ============================================================================

print("=== LibMonetColor LibStub load-order suite ===\n")
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
    print("\n=== ALL LIBSTUB LOAD-ORDER TESTS PASSED ===")
    os.exit(0)
else
    print("\n=== SOME LIBSTUB LOAD-ORDER TESTS FAILED ===")
    os.exit(1)
end
