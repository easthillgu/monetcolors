-- LibMonetColor-1.0.lua
-- Monet Color Engine v1.0.0
-- A WoW dynamic environment color computation engine based on Impressionist color rules.
-- Provides adaptive "5+3" theme colors for UI plugins.
--
-- Dependencies: LibStub, CallbackHandler-1.0
-- License: MAJOR = "LibMonetColor-1.0", MINOR = 10000

local MAJOR, MINOR = "LibMonetColor-1.0", 10000

-- Safety: don't load twice
if _G[MAJOR] and _G[MAJOR].Version >= MINOR then return end

local LibStub = _G.LibStub
local CallbackHandler = LibStub and LibStub("CallbackHandler-1.0", true)

-- Forward declarations
local LMC
LMC = {
    Version = MINOR,
    -- Event registry
    events = nil,
    -- Color cache: mapID -> {edge={r,g,b}, ambient={r,g,b,a}, highlight={r,g,b}, neutral={r,g,b}, envH, envS, envL}
    colorCache = {},
    -- Active profile name
    activeProfile = "Monet",
    -- Custom profiles registered by producers
    customProfiles = {},
    -- Warning cooldown tracking
    lastWarnTime = 0,
    warnCooldown = 30, -- seconds between duplicate warnings
    -- Delta E threshold for event triggering
    deltaEThreshold = 5.0,
}

-- Use CallbackHandler or fallback to a simple registry
if CallbackHandler then
    LMC.events = CallbackHandler:New(LMC, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")
else
    -- Fallback event system (minimal, no dependencies)
    LMC.events = { _callbacks = {} }
    function LMC.events:RegisterCallback(target, cb) self._callbacks[target] = cb end
    function LMC.events:UnregisterCallback(target) self._callbacks[target] = nil end
    function LMC.events:UnregisterAllCallbacks() self._callbacks = {} end
    function LMC.events:Fire(event, ...)
        for _, cb in pairs(self._callbacks) do
            pcall(cb, event, ...)
        end
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
}

--- Find the matching domain for a given hue.
-- Handles multi-range domains like Red/Warm [0,30) U [330,360).
local function findDomain(hue, rules)
    for _, domain in ipairs(rules.domains) do
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
    return rules.domains[1]
end

--- Check complementary pairs for exact hue match.
local function findComplement(hue, rules)
    -- Allow small tolerance for "exact" match (within 2 degrees)
    local tolerance = 2
    for _, pair in ipairs(rules.complementaryPairs) do
        local diff = math.abs(((hue - pair.h) % 360 + 360) % 360)
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
    local complementHue
    local pairComplement = findComplement(envH, rules)
    if pairComplement then
        complementHue = pairComplement
    else
        local domain = findDomain(envH, rules)
        complementHue = envH + domain.hueShift
    end
    complementHue = ((complementHue % 360) + 360) % 360

    -- Apply saturation multiplier from domain (or default)
    local domain = findDomain(envH, rules)
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

    -- Alpha based on environment lightness (R-01: fixed for now, TBD in Phase 2)
    local alpha = 0.15 + (1 - envL) * 0.15  -- 0.15-0.30 range

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
-- SECTION 5: Cache & Debounce System
-- ============================================================================

--- Get the current map ID (WoW API).
local function getCurrentMapID()
    -- C_Map is available in modern WoW (8.0+)
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then return mapID end
    end
    -- Fallback
    return 0
end

--- Sample the current environment color.
-- In production this would sample the world's dominant color.
-- For Phase 1, we use a placeholder that can be replaced with actual sampling.
-- @return h, s, l
local function sampleEnvironmentColor()
    -- TODO: Phase 2 — replace with actual world color sampling
    -- For now, return a neutral mid-tone that exercises the engine
    -- This should be replaced with palette-based sampling from the current zone
    return 120, 0.15, 0.5  -- default: muted green, medium lightness
end

--- Compute all theme colors for a given map ID and cache them.
local function computeAndCache(mapID)
    mapID = mapID or getCurrentMapID()

    local envH, envS, envL = sampleEnvironmentColor()

    -- Check if we can use cached values (only skip if same map AND env hasn't changed)
    local cached = LMC.colorCache[mapID]
    if cached and cached.envH and cached.envS and cached.envL then
        local dH = math.abs(envH - cached.envH)
        if dH > 180 then dH = 360 - dH end
        if dH < 5 and math.abs(envS - cached.envS) < 0.05 and math.abs(envL - cached.envL) < 0.05 then
            return cached  -- no significant change
        end
    end

    -- Compute fresh colors
    local edgeR, edgeG, edgeB, edgeA = LMC.ComputeEdgeColor(envH, envS, envL)
    local ambR, ambG, ambB, ambA = LMC.ComputeAmbientTint(envH, envS, envL)
    local hlR, hlG, hlB = LMC.ComputeHighlightWash(envH, envS, envL)
    local neuR, neuG, neuB = LMC.ComputeNeutral(envH, envS, envL)

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
-- @param mapID WoW map ID
-- @return r, g, b, a
function LMC:GetEdgeColorForMap(mapID)
    mapID = tonumber(mapID) or getCurrentMapID()
    local ok, r, g, b, a = pcall(function()
        local envH, envS, envL = sampleEnvironmentColor()
        return LMC.ComputeEdgeColor(envH, envS, envL)
    end)
    if ok then return r, g, b, a end
    warn("GetEdgeColorForMap failed: " .. tostring(r))
    return 0.5, 0.5, 0.5, 0.8
end

--- Force refresh the color cache for the current map.
-- Call this when you know the environment has changed (e.g., zone transition).
function LMC:Refresh()
    local mapID = getCurrentMapID()
    local oldEntry = LMC.colorCache[mapID]
    LMC.colorCache[mapID] = nil  -- force recompute
    local newEntry = computeAndCache(mapID)
    if shouldFireEvent(oldEntry, newEntry) then
        LMC.events:Fire("OnThemeColorsChanged", newEntry)
    end
end

--- Set the Delta E threshold for event firing (default 5.0).
-- @param threshold Number
function LMC:SetDeltaEThreshold(threshold)
    LMC.deltaEThreshold = tonumber(threshold) or 5.0
end

--- Set the environment color sampler (for Phase 2 integration).
-- @param sampler function returning h, s, l
function LMC:SetEnvironmentSampler(sampler)
    if type(sampler) == "function" then
        sampleEnvironmentColor = sampler
    end
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

--- Access the raw rules table (for inspection/modification).
-- @return rules table (do not mutate directly — use RegisterProfile for custom rules)
function LMC:GetRules()
    if LMC.activeProfile == "Monet" then
        return DEFAULT_MONET_RULES
    end
    return LMC.customProfiles[LMC.activeProfile] or DEFAULT_MONET_RULES
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
            local mapID = getCurrentMapID()
            local oldEntry = LMC.colorCache[mapID]
            LMC.colorCache[mapID] = nil  -- force recompute
            local newEntry = computeAndCache(mapID)
            if shouldFireEvent(oldEntry, newEntry) then
                LMC.events:Fire("OnThemeColorsChanged", newEntry)
            end
        end)
        if not ok then
            warn("Event handler error: " .. tostring(err))
        end
    end)
end

-- ============================================================================
-- SECTION 10: LibStub Registration
-- ============================================================================

-- Initialize
ensureEventFrame()

-- Register with LibStub (or provide a mock if not in WoW)
if _G.LibStub then
    _G.LibStub:NewLibrary(MAJOR, MINOR)
else
    -- Mock LibStub for standalone usage / testing
    _G.LibStub = function(name, silent)
        if name == MAJOR then
            return LMC
        end
        return nil
    end
end

-- Global alias for convenience
_G.LibMonetColor = LMC
