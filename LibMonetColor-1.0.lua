-- LibMonetColor-1.0.lua
-- Monet Color Engine v1.0.1
-- A WoW dynamic environment color computation engine based on Impressionist color rules.
-- Provides adaptive "5+3" theme colors for UI plugins.
--
-- Dependencies: LibStub, CallbackHandler-1.0
-- Optional data: MonetColorMapData-1.0 (mapID -> environment color table)
-- License: MAJOR = "LibMonetColor-1.0", MINOR = 10001

local MAJOR, MINOR = "LibMonetColor-1.0", 10001

local LibStub = _G.LibStub
local CallbackHandler = LibStub and LibStub("CallbackHandler-1.0", true)

-- Obtain the library object the same way every other LibStub library does.
-- When LibStub is present we MUST use the table it hands back, otherwise
-- LibStub("LibMonetColor-1.0") would return an empty table and consumers
-- would see none of our methods. NewLibrary returns nil when an equal or
-- newer minor is already loaded — that is our double-load guard.
local LMC
if LibStub then
    LMC = LibStub:NewLibrary(MAJOR, MINOR)
    if not LMC then return end
else
    -- Not in WoW: run against a bare table (tests / tooling).
    LMC = {}
end

-- State. `or` keeps existing values when LibStub hands back a table from a
-- previously loaded (lower) minor.
LMC.Version = MINOR
-- Event registry (filled below)
LMC.events = nil
-- Color cache: mapID -> {edge={r,g,b,a}, ambient={r,g,b,a}, highlight={r,g,b}, neutral={r,g,b}, envH, envS, envL}
LMC.colorCache = LMC.colorCache or {}
-- Active profile name
LMC.activeProfile = LMC.activeProfile or "Monet"
-- Custom profiles registered by producers
LMC.customProfiles = LMC.customProfiles or {}
-- Normalized (defaults-filled) copy of each custom profile, cache
LMC.resolvedProfiles = {}
-- Warning cooldown tracking
LMC.lastWarnTime = LMC.lastWarnTime or 0
LMC.warnCooldown = 30 -- seconds between duplicate warnings
-- Delta E threshold for event triggering
LMC.deltaEThreshold = LMC.deltaEThreshold or 5.0
-- Runtime env overrides for individual maps (RegisterMapEnv)
LMC.overrideEnv = LMC.overrideEnv or {}
-- Env used when a map has no data at all (SetFallbackEnv). The default is
-- achromatic mid-grey so ComputeEdgeColor routes through its achromatic
-- injection path: unknown zones get a calm, readable tint instead of
-- pretending they all look like the same placeholder color.
LMC.fallbackEnv = LMC.fallbackEnv or { h = 0, s = 0, l = 0.5 }

-- Use CallbackHandler or fall back to a dependency-free registry that mirrors
-- the CallbackHandler public shape: RegisterCallback(event, fn).
if CallbackHandler then
    LMC.events = CallbackHandler:New(LMC, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")
else
    local registry = {}

    local function fallbackFire(_, event, ...)
        local bucket = registry[event]
        if not bucket then return end
        for cb in pairs(bucket) do
            pcall(cb, event, ...)
        end
    end

    LMC.events = { Fire = fallbackFire }

    LMC.RegisterCallback = function(_, event, fn)
        if type(fn) ~= "function" then return end
        local bucket = registry[event]
        if not bucket then
            bucket = {}
            registry[event] = bucket
        end
        bucket[fn] = true
    end

    LMC.UnregisterCallback = function(_, event, fn)
        local bucket = registry[event]
        if bucket then bucket[fn] = nil end
    end

    LMC.UnregisterAllCallbacks = function(_)
        registry = {}
    end
end

-- ============================================================================
-- SECTION 1: HSL <-> RGB Conversion
-- ============================================================================

--- Convert HSL to RGB. All inputs/outputs are in [0,1] range (h in [0,360]).
-- @param h Hue in degrees [0, 360]
-- @param s Saturation [0, 1]
-- @param l Lightness [0, 1]
-- @return r, g, b each in [0, 1]
function LMC.HSLToRGB(h, s, l)
    h = ((h or 0) % 360 + 360) % 360
    s = math.max(0, math.min(1, s or 0))
    l = math.max(0, math.min(1, l or 0.5))

    if s == 0 then
        return l, l, l
    end

    local c = (1 - math.abs(2 * l - 1)) * s
    local hp = h / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local m = l - c / 2
    local r, g, b

    if     hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else                 r, g, b = c, 0, x
    end

    return r + m, g + m, b + m
end

--- Convert RGB to HSL. All inputs/outputs are in [0,1] range (h in [0,360]).
-- @param r Red [0, 1]
-- @param g Green [0, 1]
-- @param b Blue [0, 1]
-- @return h [0,360], s [0,1], l [0,1]
function LMC.RGBToHSL(r, g, b)
    r = math.max(0, math.min(1, r or 0))
    g = math.max(0, math.min(1, g or 0))
    b = math.max(0, math.min(1, b or 0))

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local l = (max + min) / 2
    local h, s

    if max == min then
        h, s = 0, 0
    else
        local d = max - min
        s = l > 0.5 and d / (2 - max - min) or d / (max + min)
        if max == r then
            h = (g - b) / d
            if g < b then h = h + 6 end
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h * 60
    end

    return h, s, l
end

-- ============================================================================
-- SECTION 2: Color Science — Delta E (CIE76)
-- ============================================================================

--- Convert RGB to CIE XYZ (sRGB, D65).
local function RGBToXYZ(r, g, b)
    -- sRGB gamma decode
    local function decode(c)
        if c > 0.04045 then
            return ((c + 0.055) / 1.055) ^ 2.4
        else
            return c / 12.92
        end
    end
    r, g, b = decode(r), decode(g), decode(b)
    -- D65 illuminant
    local x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
    local y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
    local z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
    return x, y, z
end

--- Convert CIE XYZ to CIE L*a*b*.
local function XYZToLab(x, y, z)
    -- D65 reference white
    local xn, yn, zn = 0.95047, 1.0, 1.08883
    local function f(t)
        local delta = 6 / 29
        if t > delta * delta * delta then
            return t ^ (1 / 3)
        else
            return t / (3 * delta^2) + 4 / 29
        end
    end
    local fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    local L = 116 * fy - 16
    local a = 500 * (fx - fy)
    local b2 = 200 * (fy - fz)
    return L, a, b2
end

--- Convert RGB directly to CIE L*a*b*.
function LMC.RGBToLab(r, g, b)
    local x, y, z = RGBToXYZ(r, g, b)
    return XYZToLab(x, y, z)
end

--- Compute Delta E (CIE76) between two RGB colors.
-- Simple Euclidean distance in Lab space. Good enough for WoW performance budget.
function LMC.DeltaE(r1, g1, b1, r2, g2, b2)
    local L1, a1, b1v = LMC.RGBToLab(r1, g1, b1)
    local L2, a2, b2v = LMC.RGBToLab(r2, g2, b2)
    local dL = L2 - L1
    local da = a2 - a1
    local db = b2v - b1v
    return math.sqrt(dL * dL + da * da + db * db)
end

-- ============================================================================
-- SECTION 3: Monet Rule Engine
-- ============================================================================

-- Default rules from MonetColorBaseline.lua v3
local DEFAULT_MONET_RULES = {
    domains = {
        {name="Red/Warm",     range={0, 30, 330, 360}, hueShift=170, satMult=0.35, lBias=-0.03},
        {name="AmberGold",    range={30, 60},          hueShift=180, satMult=0.65, lBias=0.00},
        {name="OliveSage",    range={60, 90},          hueShift=180, satMult=0.80, lBias=0.02},
        {name="ForestGreen",  range={90, 150},         hueShift=180, satMult=0.90, lBias=0.00},
        {name="CyanMist",     range={150, 210},        hueShift=180, satMult=0.95, lBias=0.00},
        {name="IndigoShadow", range={210, 270},        hueShift=180, satMult=0.90, lBias=-0.02},
        {name="VioletRose",   range={270, 330},        hueShift=180, satMult=0.85, lBias=0.01},
    },

    -- Exact-hue overrides (take priority over domain rules)
    complementaryPairs = {
        {h=0,   complement=170},
        {h=30,  complement=200},
        {h=40,  complement=220},
        {h=60,  complement=240},
        {h=120, complement=300},
        {h=330, complement=140},
    },

    saturationCompensation = {
        factor = 1.05,
        minSaturation = 0.10,
    },

    -- Lightness clamp range for edge glow output
    lightnessMin = 0.18,
    lightnessMax = 0.82,

    -- Achromatic injection: when env S < threshold, inject subtle tint
    achromaticThreshold = 0.06,
    -- Warm-purple tint for warm-leaning achromatic, cool-blue for cool-leaning
    achromaticWarmHue = 300,  -- warm purple
    achromaticCoolHue = 210,  -- cool blue
    achromaticSat = 0.12,

    -- Ambient Tint alpha response (R-01 decision, 2026-10-15).
    -- alpha = alphaMin + (alphaMax - alphaMin) * (1 - envL) * (1 - saturationGuard * envS)
    -- Darker environments get a stronger mood wash; highly saturated environments
    -- get a subtler one so the UI is not double-saturated. Output stays within
    -- [alphaMin, alphaMax] = [0.15, 0.30] as promised by the API contract.
    ambient = {
        alphaMin = 0.15,
        alphaMax = 0.30,
        saturationGuard = 0.20,
    },
}

--- Fill missing top-level keys of a custom profile from the built-in defaults
--- so the compute functions never dereference nil. Explicitly provided keys
--- (including empty tables such as complementaryPairs = {}) are kept as-is.
local function resolveRules(rules)
    if not rules then return DEFAULT_MONET_RULES end
    local out = {}
    for k, v in pairs(DEFAULT_MONET_RULES) do out[k] = v end
    for k, v in pairs(rules) do out[k] = v end
    return out
end

--- Find the matching domain for a given hue.
-- Handles multi-range domains like Red/Warm [0,30) U [330,360).
local function findDomain(hue, rules)
    local domains = rules.domains or DEFAULT_MONET_RULES.domains
    for _, domain in ipairs(domains) do
        local range = domain.range
        -- range is flat array of numbers: {start1, end1, start2, end2, ...}
        for i = 1, #range, 2 do
            local start = range[i]
            local end_ = range[i + 1]
            if hue >= start and hue < end_ then
                return domain
            end
        end
    end
    -- Fallback: should not happen with full 360 coverage
    return domains[1]
end

--- Check complementary pairs for exact hue match.
local function findComplement(hue, rules)
    -- Allow small tolerance for "exact" match (within 2 degrees)
    local tolerance = 2
    for _, pair in ipairs(rules.complementaryPairs or {}) do
        -- Shortest signed distance on the hue wheel, already in [0, 360)
        local diff = ((hue - pair.h) % 360 + 360) % 360
        if diff <= tolerance or diff >= (360 - tolerance) then
            return pair.complement
        end
    end
    return nil
end

--- Compute the Edge Glow color from an environment color.
-- Core algorithm: complementary hue + saturation/lightness adjustment + clamping.
-- @param envH Environment hue [0, 360]
-- @param envS Environment saturation [0, 1]
-- @param envL Environment lightness [0, 1]
-- @param rules Rules table (uses active profile rules)
-- @return r, g, b, a  (a = alpha, default 0.8)
function LMC.ComputeEdgeColor(envH, envS, envL, rules)
    rules = rules or DEFAULT_MONET_RULES

    envH = ((envH or 0) % 360 + 360) % 360
    envS = math.max(0, math.min(1, envS or 0))
    envL = math.max(0, math.min(1, envL or 0.5))

    -- Apply saturation compensation
    local satComp = rules.saturationCompensation
    local compensatedS = envS
    if satComp and envS > (satComp.minSaturation or 0) then
        compensatedS = math.min(1, envS * (satComp.factor or 1))
    end

    -- Determine complementary hue
    local domain = findDomain(envH, rules)
    local pairComplement = findComplement(envH, rules)
    local complementHue
    if pairComplement then
        complementHue = pairComplement
    else
        complementHue = envH + domain.hueShift
    end
    complementHue = ((complementHue % 360) + 360) % 360

    -- Apply saturation multiplier from domain (or default)
    local satMult = domain and domain.satMult or 0.8
    local lBias = domain and domain.lBias or 0

    local edgeS = compensatedS * satMult
    edgeS = math.max(0, math.min(1, edgeS))

    -- Lightness: mirror around 0.5 + bias, then clamp
    local edgeL = 1 - envL + lBias
    edgeL = math.max(rules.lightnessMin or 0.18, math.min(rules.lightnessMax or 0.82, edgeL))

    -- Achromatic injection: if env is nearly gray, add subtle tint
    local isAchromatic = envS < (rules.achromaticThreshold or 0.06)
    if isAchromatic then
        -- Choose warm or cool based on which half of the hue wheel
        if envH < 60 or envH > 300 then
            -- Warm-leaning -> cool blue complement
            edgeS = math.max(edgeS, rules.achromaticSat or 0.12)
            -- Slightly shift toward cool
            complementHue = rules.achromaticCoolHue or 210
        else
            -- Cool-leaning -> warm purple complement
            edgeS = math.max(edgeS, rules.achromaticSat or 0.12)
            complementHue = rules.achromaticWarmHue or 300
        end
        -- Keep lightness readable
        edgeL = math.max(0.25, math.min(0.75, edgeL))
    end

    local r, g, b = LMC.HSLToRGB(complementHue, edgeS, edgeL)
    return r, g, b, 0.8
end

--- Compute Ambient Tint (soft background wash).
-- Lower saturation, lower alpha than edge glow.
function LMC.ComputeAmbientTint(envH, envS, envL, rules)
    rules = rules or DEFAULT_MONET_RULES

    envH = ((envH or 0) % 360 + 360) % 360
    envS = math.max(0, math.min(1, envS or 0))
    envL = math.max(0, math.min(1, envL or 0.5))

    -- Ambient uses a shifted hue (not full complementary)
    local ambientHue = (envH + 120) % 360  -- triadic shift
    local ambientS = envS * 0.25
    ambientS = math.max(0, math.min(1, ambientS))

    -- R-01 decision: alpha adapts to environment lightness with a saturation guard.
    --   alpha = alphaMin + (alphaMax - alphaMin) * (1 - envL) * (1 - saturationGuard * envS)
    -- Darker env -> stronger mood wash; more saturated env -> subtler wash.
    -- Result is clamped to the documented [alphaMin, alphaMax] band.
    local ambientRules = rules.ambient or DEFAULT_MONET_RULES.ambient
    local alphaMin = ambientRules.alphaMin or 0.15
    local alphaMax = ambientRules.alphaMax or 0.30
    local satGuard = ambientRules.saturationGuard or 0
    if alphaMax < alphaMin then alphaMin, alphaMax = alphaMax, alphaMin end
    local alpha = alphaMin + (alphaMax - alphaMin) * (1 - envL) * (1 - satGuard * envS)
    alpha = math.max(alphaMin, math.min(alphaMax, alpha))

    local r, g, b = LMC.HSLToRGB(ambientHue, ambientS, envL)
    return r, g, b, alpha
end

--- Compute Highlight Wash (subtle top-light/gradient overlay).
function LMC.ComputeHighlightWash(envH, envS, envL, rules)
    rules = rules or DEFAULT_MONET_RULES

    envH = ((envH or 0) % 360 + 360) % 360
    envS = math.max(0, math.min(1, envS or 0))
    envL = math.max(0, math.min(1, envL or 0.5))

    -- Highlight: shift hue slightly lighter, very low saturation
    local hlHue = (envH + 30) % 360
    local hlS = envS * 0.15
    local hlL = math.min(0.95, envL + 0.25)

    local r, g, b = LMC.HSLToRGB(hlHue, hlS, hlL)
    return r, g, b
end

--- Compute Neutral (Monet-style neutral gray for text/dividers).
function LMC.ComputeNeutral(envH, envS, envL, rules)
    rules = rules or DEFAULT_MONET_RULES

    envL = math.max(0, math.min(1, envL or 0.5))

    -- Very subtle warm/cool bias based on environment hue
    local neutralH = envH or 0
    local neutralS = 0.02  -- nearly gray
    local neutralL = 0.35 + envL * 0.3  -- 0.35-0.65 range, adapts to env

    local r, g, b = LMC.HSLToRGB(neutralH, neutralS, neutralL)
    return r, g, b
end

-- ============================================================================
-- SECTION 4: Warning System
-- ============================================================================

local function warn(msg)
    local now = GetTime and GetTime() or 0
    if now - LMC.lastWarnTime < LMC.warnCooldown then
        return  -- skip, still in cooldown
    end
    LMC.lastWarnTime = now
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF6B6B[LibMonetColor]|r " .. tostring(msg))
    end
end

-- ============================================================================
-- SECTION 5: Environment Sampling & Cache System
-- ============================================================================

--- Get the current map ID (WoW API).
local function getCurrentMapID()
    -- C_Map is available in modern WoW (8.0+)
    if C_Map and C_Map.GetBestMapForUnit then
        local localMapID = C_Map.GetBestMapForUnit("player")
        if localMapID then return localMapID end
    end
    -- Fallback
    return 0
end

-- Cached lookup of the MonetColorMapData-1.0 module. The data module may be
-- loaded after us (or not at all), so the lookup is retried until it hits.
local mapEnvData
local function getMapEnvData()
    if mapEnvData then return mapEnvData end
    local stub = _G.LibStub
    if type(stub) == "table" then
        local ok, data = pcall(stub, "MonetColorMapData-1.0", true)
        if ok and type(data) == "table" and type(data.MapEnv) == "table" then
            mapEnvData = data.MapEnv
            return mapEnvData
        end
    end
    local globalData = _G.LibMonetColorMapData
    if type(globalData) == "table" and type(globalData.MapEnv) == "table" then
        mapEnvData = globalData.MapEnv
        return mapEnvData
    end
    return nil
end

-- Walk the parent-map chain (WoW only) to find a known ancestor of a map.
-- Lets subzone/dungeon maps inherit their parent zone's environment.
-- @return parentMapID, source | nil
local function findParentEnv(mapID, data)
    if not (type(C_Map) == "table" and C_Map.GetMapInfo) then return nil end
    local current = mapID
    for _ = 1, 5 do  -- depth cap: no cycles, no deep chains
        local ok, info = pcall(C_Map.GetMapInfo, current)
        if not ok or type(info) ~= "table" then return nil end
        local parent = tonumber(info.parentMapID)
        if not parent or parent == 0 then return nil end
        if LMC.overrideEnv[parent] then return parent, "override" end
        if data and data[parent] then return parent, "data" end
        current = parent
    end
    return nil
end

--- Resolve the environment color (h, s, l) for a map.
-- Resolution order:
--   1. Runtime override registered via RegisterMapEnv
--   2. Exact hit in MonetColorMapData-1.0 (generated from game_palette)
--   3. Nearest known ancestor via C_Map parent chain (in-game only)
--   4. Fallback env (SetFallbackEnv; default achromatic mid-grey)
-- Never throws; all inputs are sanitized.
-- @param mapID number|nil WoW map ID
-- @return h, s, l, name|nil, source ("override"|"data"|"parent:override"|"parent:data"|"fallback")
function LMC:GetMapEnv(mapID)
    mapID = tonumber(mapID)
    local fb = LMC.fallbackEnv
    if not mapID or mapID == 0 then
        return fb.h, fb.s, fb.l, nil, "fallback"
    end

    local entry = LMC.overrideEnv[mapID]
    if entry then
        return entry.h, entry.s, entry.l, entry.name, "override"
    end

    local data = getMapEnvData()
    entry = data and data[mapID]
    if entry then
        return entry.h, entry.s, entry.l, entry.name, "data"
    end

    local parentID, parentSource = findParentEnv(mapID, data)
    if parentID then
        entry = LMC.overrideEnv[parentID] or data[parentID]
        return entry.h, entry.s, entry.l, entry.name, "parent:" .. parentSource
    end

    return fb.h, fb.s, fb.l, nil, "fallback"
end

-- The default environment sampler (T2.1): zone-data lookup keyed by mapID.
-- Integrating addons can still replace it wholesale via SetEnvironmentSampler.
-- The mapID argument is optional; nil resolves to the fallback env.
-- @param mapID number|nil WoW map ID
-- @return h, s, l
local function sampleEnvironmentColor(mapID)
    local h, s, l = LMC:GetMapEnv(mapID)
    return h, s, l
end

--- Compute all theme colors for a given map ID and cache them.
local function computeAndCache(mapID)
    mapID = mapID or getCurrentMapID()

    local envH, envS, envL = sampleEnvironmentColor(mapID)

    -- Cheap pre-filter: skip recompute when the same map's environment is
    -- effectively unchanged (keeps GetCurrent* O(1) between map switches).
    local cached = LMC.colorCache[mapID]
    if cached and cached.envH and cached.envS and cached.envL then
        local dH = math.abs(envH - cached.envH)
        if dH > 180 then dH = 360 - dH end
        if dH < 5 and math.abs(envS - cached.envS) < 0.05 and math.abs(envL - cached.envL) < 0.05 then
            return cached  -- no significant change
        end
    end

    -- Active profile rules drive every derived color.
    local rules = LMC:GetRules()

    local edgeR, edgeG, edgeB, edgeA = LMC.ComputeEdgeColor(envH, envS, envL, rules)
    local ambR, ambG, ambB, ambA = LMC.ComputeAmbientTint(envH, envS, envL, rules)
    local hlR, hlG, hlB = LMC.ComputeHighlightWash(envH, envS, envL, rules)
    local neuR, neuG, neuB = LMC.ComputeNeutral(envH, envS, envL, rules)

    local entry = {
        mapID = mapID,
        envH = envH, envS = envS, envL = envL,
        edge = {r = edgeR, g = edgeG, b = edgeB, a = edgeA},
        ambient = {r = ambR, g = ambG, b = ambB, a = ambA},
        highlight = {r = hlR, g = hlG, b = hlB},
        neutral = {r = neuR, g = neuG, b = neuB},
    }

    LMC.colorCache[mapID] = entry
    return entry
end

--- Check if the environment change exceeds the Delta E threshold.
local function shouldFireEvent(oldEntry, newEntry)
    if not oldEntry or not newEntry then return true end
    -- Compare edge color as the primary indicator
    local de = LMC.DeltaE(
        oldEntry.edge.r, oldEntry.edge.g, oldEntry.edge.b,
        newEntry.edge.r, newEntry.edge.g, newEntry.edge.b
    )
    return de > LMC.deltaEThreshold
end

--- Force a recompute for a map and fire OnThemeColorsChanged when significant.
-- Shared by Refresh() and the zone event handler.
local function recomputeAndFire(mapID)
    local oldEntry = LMC.colorCache[mapID]
    LMC.colorCache[mapID] = nil  -- force recompute
    local newEntry = computeAndCache(mapID)
    if shouldFireEvent(oldEntry, newEntry) then
        LMC.events:Fire("OnThemeColorsChanged", newEntry)
    end
    return newEntry
end

-- ============================================================================
-- SECTION 6: Public Consumer API
-- ============================================================================

--- Get the current edge glow color (cached, safe for frequent calls).
-- @return r, g, b, a  (nil if library not ready)
function LMC:GetCurrentEdgeColor()
    local ok, r, g, b, a = pcall(function()
        local entry = computeAndCache()
        return entry.edge.r, entry.edge.g, entry.edge.b, entry.edge.a
    end)
    if ok then return r, g, b, a end
    warn("GetCurrentEdgeColor failed: " .. tostring(r))
    return 0.5, 0.5, 0.5, 0.8
end

--- Get the current ambient tint color.
-- @return r, g, b, a
function LMC:GetCurrentAmbientTint()
    local ok, r, g, b, a = pcall(function()
        local entry = computeAndCache()
        return entry.ambient.r, entry.ambient.g, entry.ambient.b, entry.ambient.a
    end)
    if ok then return r, g, b, a end
    warn("GetCurrentAmbientTint failed: " .. tostring(r))
    return 0.5, 0.5, 0.5, 0.2
end

--- Get the current highlight wash color.
-- @return r, g, b
function LMC:GetCurrentHighlightWash()
    local ok, r, g, b = pcall(function()
        local entry = computeAndCache()
        return entry.highlight.r, entry.highlight.g, entry.highlight.b
    end)
    if ok then return r, g, b end
    warn("GetCurrentHighlightWash failed: " .. tostring(r))
    return 0.7, 0.7, 0.7
end

--- Get the current neutral color.
-- @return r, g, b
function LMC:GetCurrentNeutral()
    local ok, r, g, b = pcall(function()
        local entry = computeAndCache()
        return entry.neutral.r, entry.neutral.g, entry.neutral.b
    end)
    if ok then return r, g, b end
    warn("GetCurrentNeutral failed: " .. tostring(r))
    return 0.5, 0.5, 0.5
end

--- Get all current theme colors at once (efficient — single cache lookup).
-- @return edgeR, edgeG, edgeB, edgeA, ambR, ambG, ambB, ambA, hlR, hlG, hlB, neuR, neuG, neuB
function LMC:GetAllThemeColors()
    local ok, er, eg, eb, ea, ar, ag, ab, aa, hr, hg, hb, nr, ng, nb = pcall(function()
        local entry = computeAndCache()
        return
            entry.edge.r, entry.edge.g, entry.edge.b, entry.edge.a,
            entry.ambient.r, entry.ambient.g, entry.ambient.b, entry.ambient.a,
            entry.highlight.r, entry.highlight.g, entry.highlight.b,
            entry.neutral.r, entry.neutral.g, entry.neutral.b
    end)
    if ok then return er, eg, eb, ea, ar, ag, ab, aa, hr, hg, hb, nr, ng, nb end
    warn("GetAllThemeColors failed: " .. tostring(er))
    return 0.5, 0.5, 0.5, 0.8, 0.5, 0.5, 0.5, 0.2, 0.7, 0.7, 0.7, 0.5, 0.5, 0.5
end

--- Get edge color for a specific map ID (does not change active cache).
-- Uses the cached entry when present, otherwise samples that map on the fly
-- without touching the active cache.
-- @param mapID WoW map ID
-- @return r, g, b, a
function LMC:GetEdgeColorForMap(mapID)
    mapID = tonumber(mapID) or getCurrentMapID()
    local ok, r, g, b, a = pcall(function()
        local entry = LMC.colorCache[mapID]
        if entry then
            return entry.edge.r, entry.edge.g, entry.edge.b, entry.edge.a
        end
        local envH, envS, envL = sampleEnvironmentColor(mapID)
        return LMC.ComputeEdgeColor(envH, envS, envL, LMC:GetRules())
    end)
    if ok then return r, g, b, a end
    warn("GetEdgeColorForMap failed: " .. tostring(r))
    return 0.5, 0.5, 0.5, 0.8
end

--- Force refresh the color cache for the current map.
-- Call this when you know the environment has changed (e.g., zone transition).
function LMC:Refresh()
    return recomputeAndFire(getCurrentMapID())
end

--- Set the Delta E threshold for event firing (default 5.0).
-- @param threshold Number
function LMC:SetDeltaEThreshold(threshold)
    LMC.deltaEThreshold = tonumber(threshold) or 5.0
end

--- Set the environment color sampler (for Phase 2 integration).
-- The sampler may accept an optional mapID argument; it is ignored by
-- samplers that do not care about the map.
-- @param sampler function(mapID) returning h, s, l
-- @return boolean success
function LMC:SetEnvironmentSampler(sampler)
    if type(sampler) ~= "function" then
        warn("SetEnvironmentSampler: sampler must be a function")
        return false
    end
    sampleEnvironmentColor = sampler
    LMC:ClearCache()
    LMC:Refresh()
    return true
end

--- Register or override the environment color for a single map at runtime.
-- Runtime overrides take priority over the MonetColorMapData module, letting
-- addons extend coverage zone-by-zone without forking the data module.
-- @param mapID number WoW map ID (> 0)
-- @param h number Hue [0, 360]
-- @param s number Saturation [0, 1]
-- @param l number Lightness [0, 1]
-- @param name string|nil Optional zone name (for debugging /lmctest output)
-- @return boolean success
function LMC:RegisterMapEnv(mapID, h, s, l, name)
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 then
        warn("RegisterMapEnv: mapID must be a positive number")
        return false
    end
    h, s, l = tonumber(h), tonumber(s), tonumber(l)
    if not h or not s or not l then
        warn("RegisterMapEnv: h, s and l must be numbers")
        return false
    end
    LMC.overrideEnv[mapID] = {
        name = type(name) == "string" and name or nil,
        h = ((h % 360) + 360) % 360,
        s = math.max(0, math.min(1, s)),
        l = math.max(0, math.min(1, l)),
    }
    LMC:ClearCache()
    LMC:Refresh()
    return true
end

--- Set the fallback environment color used for maps with no data.
-- Default is achromatic mid-grey {h=0, s=0, l=0.5}, which the engine routes
-- through its achromatic injection path (calm cool-blue edge glow).
-- @param h, s, l numbers
-- @return boolean success
function LMC:SetFallbackEnv(h, s, l)
    h, s, l = tonumber(h), tonumber(s), tonumber(l)
    if not h or not s or not l then
        warn("SetFallbackEnv: h, s and l must be numbers")
        return false
    end
    LMC.fallbackEnv = {
        h = ((h % 360) + 360) % 360,
        s = math.max(0, math.min(1, s)),
        l = math.max(0, math.min(1, l)),
    }
    LMC:ClearCache()
    LMC:Refresh()
    return true
end

-- ============================================================================
-- SECTION 7: Producer API
-- ============================================================================

--- Register a custom color profile.
-- @param name string Profile name
-- @param rules table Rule structure (same format as DEFAULT_MONET_RULES)
-- @return boolean success
function LMC:RegisterProfile(name, rules)
    if type(name) ~= "string" or name == "" then
        warn("RegisterProfile: invalid name")
        return false
    end
    if type(rules) ~= "table" then
        warn("RegisterProfile: rules must be a table")
        return false
    end
    -- Minimal validation (R-03: trust caller for now, Phase 1)
    LMC.customProfiles[name] = rules
    LMC.resolvedProfiles[name] = nil  -- re-resolve against defaults on next use
    return true
end

--- Activate a registered profile.
-- @param name string
-- @return boolean success
function LMC:SetActiveProfile(name)
    if name == "Monet" then
        LMC.activeProfile = "Monet"
        LMC:Refresh()
        return true
    end
    if LMC.customProfiles[name] then
        LMC.activeProfile = name
        LMC:Refresh()
        return true
    end
    warn("SetActiveProfile: unknown profile '" .. tostring(name) .. "'")
    return false
end

--- Get the currently active profile name.
-- @return string
function LMC:GetActiveProfile()
    return LMC.activeProfile
end

-- ============================================================================
-- SECTION 8: Utility API (exposed for advanced users / testing)
-- ============================================================================

--- Access the active rules table (defaults-filled for custom profiles).
-- @return rules table (do not mutate directly — use RegisterProfile for custom rules)
function LMC:GetRules()
    if LMC.activeProfile == "Monet" then
        return DEFAULT_MONET_RULES
    end
    local profile = LMC.customProfiles[LMC.activeProfile]
    if not profile then return DEFAULT_MONET_RULES end
    local resolved = LMC.resolvedProfiles[LMC.activeProfile]
    if not resolved then
        resolved = resolveRules(profile)
        LMC.resolvedProfiles[LMC.activeProfile] = resolved
    end
    return resolved
end

--- Clear the color cache.
function LMC:ClearCache()
    if _G.wipe then
        wipe(LMC.colorCache)
    else
        for k in pairs(LMC.colorCache) do
            LMC.colorCache[k] = nil
        end
    end
end

-- ============================================================================
-- SECTION 9: Event Handling & Initialization
-- ============================================================================

-- Frame for event-driven updates
local eventFrame
local function ensureEventFrame()
    if eventFrame then return end
    if not _G.CreateFrame then
        -- Not in WoW environment, skip event frame creation
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        local ok, err = pcall(function()
            recomputeAndFire(getCurrentMapID())
        end)
        if not ok then
            warn("Event handler error: " .. tostring(err))
        end
    end)
end

-- ============================================================================
-- SECTION 10: Initialization
-- ============================================================================

-- Initialize
ensureEventFrame()

-- Standalone fallback: provide a minimal LibStub so tooling and tests can
-- fetch the library exactly like addons do in WoW. When the real LibStub is
-- present the library was already registered in the header (NewLibrary).
if not _G.LibStub then
    LMC.LibStubName = MAJOR
    _G.LibStub = function(name, silent)
        if name == MAJOR then return LMC end
        return nil
    end
end

-- Global alias for convenience
_G.LibMonetColor = LMC
