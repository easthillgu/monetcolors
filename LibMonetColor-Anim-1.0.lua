-- LibMonetColor-Anim-1.0.lua
-- Monet Animation & State Layer v1.0.0
--
-- A companion library for LibMonetColor-1.0.  It turns the *player's* runtime
-- state (combat / resting / health / PvP / vehicle) into colour modifiers and
-- runs a single shared pulse ticker for every consumer.
--
-- Design goals
--   * Consumers judge nothing themselves: they ask for a colour (or register
--     a sink) and the layer decides what "in combat" or "low health" means.
--   * The layer is not border specific: the same modifiers work for a unit
--     frame border, an action bar background or a decorative line.
--   * Cheap when idle: one ticker for everybody, a precomputed wave table, no
--     trigonometry and no allocation inside the tick.
--
-- Dependencies: LibMonetColor-1.0 (colour engine)
-- Optional: CallbackHandler-1.0 (a built-in registry is used when absent)
-- License: MIT

local MAJOR, MINOR = "LibMonetColor-Anim-1.0", 10000

-- ============================================================================
-- SECTION 1: Bootstrap
-- ============================================================================

local LibStub = _G.LibStub
local hasLibStub = type(LibStub) == "table" and type(LibStub.NewLibrary) == "function"

local ANIM
if hasLibStub then
    -- NewLibrary returns nil when an equal or newer minor is already loaded:
    -- that is the double-load guard.
    ANIM = LibStub:NewLibrary(MAJOR, MINOR)
    if not ANIM then return end
else
    -- Not in WoW (tests / tooling): run on a private table.  The library is
    -- still reachable through LibMonetColor.Anim and _G.LibMonetColorAnim.
    if type(LibStub) == "function" then
        local existing = LibStub(MAJOR, true)
        if type(existing) == "table" and (existing.Version or 0) >= MINOR then
            return
        end
    end
    ANIM = {}
end

ANIM.Version = MINOR

-- The colour engine.  It may load after us, so the lookup is lazy.
local function getCore()
    if ANIM.core then return ANIM.core end
    if hasLibStub then
        local ok, core = pcall(LibStub, "LibMonetColor-1.0", true)
        if ok and type(core) == "table" then ANIM.core = core end
    end
    if not ANIM.core then
        local global = _G.LibMonetColor
        if type(global) == "table" then ANIM.core = global end
    end
    -- Publish the alias so a consumer only needs the core handle.
    if ANIM.core then ANIM.core.Anim = ANIM end
    return ANIM.core
end

-- Runtime state shared by the sections below.  They are declared up front so
-- the functions below can reference each other in any order.
local sinks = {}
local sinkCount = 0
local callbackCount = 0
local ticker
local tickerAcc = 0
local eventFrame
local tracking = false
local coreSubscribed = false
local coreHandler
local refreshAll
local ensureTicker
local subscribeCore
local unsubscribeCore
local callSink
local ensureEventFrame
local setEventTracking
local updateTracking

-- ============================================================================
-- SECTION 2: Math helpers
-- ============================================================================

local function clamp(v, lo, hi)
    v = tonumber(v)
    if not v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function hslToRgb(h, s, l)
    h = ((h or 0) % 360 + 360) % 360
    s = clamp(s, 0, 1)
    l = clamp(l, 0, 1)
    if s == 0 then return l, l, l end
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

local function rgbToHsl(r, g, b)
    r = clamp(r, 0, 1); g = clamp(g, 0, 1); b = clamp(b, 0, 1)
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

--- Interpolate two hues along the shortest arc of the colour wheel.
local function lerpHue(h1, h2, t)
    local d = ((h2 - h1 + 180) % 360) - 180
    return (h1 + d * t) % 360
end

-- The wave table: 64 samples of a raised cosine (0 -> 1 -> 0).  A cosine is
-- used instead of a sine so the wave starts at 0: a pulse that begins while
-- the combat state flips must not jump to mid amplitude on the first frame.
local LUT_SIZE = 64
local BREATH_LUT = {}
for i = 1, LUT_SIZE do
    local phase = (i - 1) / LUT_SIZE
    BREATH_LUT[i] = 0.5 - 0.5 * math.cos(2 * math.pi * phase)
end

--- Sample the wave table.  No trigonometry at runtime.
-- @param t seconds
-- @param period seconds
-- @return amplitude 0..1
local function breathAt(t, period)
    if not period or period <= 0 then return 0 end
    t = t or 0
    local phase = (t % period) / period
    local index = math.floor(phase * LUT_SIZE) + 1
    if index > LUT_SIZE then index = LUT_SIZE end
    if index < 1 then index = 1 end
    return BREATH_LUT[index]
end

--- Smallest alpha change that still counts as a repaint.
local ALPHA_EPS = 1 / 128

--- The current clock.  Returns nil when no timer is available (pure Lua).
local function getNow()
    local getter = _G.GetTime
    if type(getter) == "function" then
        local ok, t = pcall(getter)
        if ok and type(t) == "number" then return t end
    end
    return nil
end

-- ============================================================================
-- SECTION 3: Warning system
-- ============================================================================

local warnTimes = {}
local WARN_COOLDOWN = 30

local function warn(msg)
    msg = tostring(msg)
    local now = getNow()
    local last = warnTimes[msg]
    if last then
        if not now then return end
        if now - last < WARN_COOLDOWN then return end
    end
    warnTimes[msg] = now or true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF6B6B[LibMonetColor-Anim]|r " .. msg)
    end
end

-- ============================================================================
-- SECTION 4: Secret value guards
-- ============================================================================

--- Is the value a secret (the client hides it under restrictions)?
local function isSecret(value)
    if value == nil then return false end
    local is = _G.issecretvalue
    if type(is) == "function" then
        local ok, res = pcall(is, value)
        if ok and res then return true end
    end
    return false
end

--- Read a number that is safe to do arithmetic on.  nil when it is secret.
local function safeNumber(value)
    if value == nil then return nil end
    if isSecret(value) then return nil end
    local ok, n = pcall(function() return value + 0 end)
    if ok and type(n) == "number" and n == n then return n end
    return nil
end

--- Read a boolean that is safe to compare.  nil when it is secret / unknown.
local function safeBool(value)
    if value == nil then return nil end
    if isSecret(value) then return nil end
    if type(value) == "boolean" then return value end
    local ok, res = pcall(function() return value and true or false end)
    if ok then return res end
    return nil
end

--- Call a game API without ever raising.  Up to four return values are
--- forwarded (the colour getters answer r,g,b,a).
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

--- Does the client hide this unit's maximum health right now?
-- An unknown query is treated as "secret": a wrong guess would raise on the
-- comparison that follows, a conservative guess only disables the effect.
local function healthIsSecret()
    local secrets = _G.C_Secrets
    if type(secrets) ~= "table" then return false end
    local ok, restricted = pcall(secrets.HasSecretRestrictions)
    if not ok or not restricted then return false end
    local query = secrets.ShouldUnitHealthMaxBeSecret
    if type(query) ~= "function" then return true end
    local ok2, isSecretHealth = pcall(query, "player")
    if not ok2 then return true end
    return isSecretHealth and true or false
end

-- ============================================================================
-- SECTION 5: Style
-- ============================================================================

local DEFAULT_STYLE = {
    -- Fallback base colours, used when the colour engine is unavailable.
    base = {
        edge      = { r = 0.5, g = 0.5, b = 0.5, a = 0.8 },
        ambient   = { r = 0.5, g = 0.5, b = 0.5, a = 0.2 },
        highlight = { r = 0.7, g = 0.7, b = 0.7, a = 1.0 },
        neutral   = { r = 0.5, g = 0.5, b = 0.5, a = 1.0 },
    },

    -- Combat: a short flash on entering, a brighter border while fighting and
    -- an optional slow breath for the whole combat.
    combat = {
        enabled = true,
        lightnessBoost = 0.08,
        saturationBoost = 0.10,
        alphaScale = 1.10,
        enterFlash = true,
        flashDuration = 0.7,
        flashWavePeriod = 0.2,
        flashAmplitude = 0.28,
        pulse = true,
        pulseAmplitude = 0.10,
        pulsePeriod = 1.6,
    },

    -- Out of combat: everything is a little calmer.
    ooc = {
        enabled = true,
        lightnessScale = 0.88,
        alphaScale = 0.85,
    },

    -- Low health: the only modifier that owns the hue (a plain danger red,
    -- never a Monet complement -- readability wins over the palette).
    lowHealth = {
        enabled = true,
        threshold = 0.35,
        critical = 0.20,
        color = { h = 0, s = 0.85, l = 0.52 },
        blend = 0.55,
        blendCritical = 1.0,
        alphaBoost = 0.15,
        pulse = true,
        pulseAmplitude = 0.22,
        pulsePeriod = 0.75,
        criticalPeriod = 0.45,
    },

    -- Resting: a cool, calm wash.
    rest = {
        enabled = true,
        color = { h = 210, s = 0.45, l = 0.55 },
        blend = 0.30,
        alphaScale = 0.95,
    },

    -- PvP flagged: a hint of the danger red.
    pvp = {
        enabled = true,
        color = { h = 0, s = 0.70, l = 0.52 },
        blend = 0.20,
    },

    -- Sitting in a vehicle: a warm amber hint.
    vehicle = {
        enabled = true,
        color = { h = 42, s = 0.60, l = 0.55 },
        blend = 0.20,
    },

    -- Dead: grey, dim and never pulsing.
    dead = {
        enabled = true,
        lightness = 0.35,
        alpha = 0.30,
    },

    -- Ticker: frames per second.  The wave table is built once at load.
    pulse = {
        fps = 15,
    },
}

-- Value ranges for the numeric style fields.  Anything outside is clamped
-- instead of rejected: a consumer typo must not break the colours.
local STYLE_RANGES = {
    combat = {
        lightnessBoost = { -0.5, 0.5 },
        saturationBoost = { -0.5, 0.5 },
        alphaScale = { 0, 2 },
        flashDuration = { 0, 5 },
        flashWavePeriod = { 0.05, 2 },
        flashAmplitude = { 0, 1 },
        pulseAmplitude = { 0, 1 },
        pulsePeriod = { 0.1, 10 },
    },
    ooc = {
        lightnessScale = { 0, 1.5 },
        alphaScale = { 0, 2 },
    },
    lowHealth = {
        threshold = { 0.01, 1 },
        critical = { 0, 1 },
        blend = { 0, 1 },
        blendCritical = { 0, 1 },
        alphaBoost = { 0, 1 },
        pulseAmplitude = { 0, 1 },
        pulsePeriod = { 0.1, 10 },
        criticalPeriod = { 0.1, 10 },
    },
    rest = {
        blend = { 0, 1 },
        alphaScale = { 0, 2 },
    },
    pvp = { blend = { 0, 1 } },
    vehicle = { blend = { 0, 1 } },
    dead = {
        lightness = { 0, 1 },
        alpha = { 0, 1 },
    },
    pulse = {
        fps = { 1, 60 },
    },
}

local COLOR_FIELDS = {
    { "lowHealth", "color" },
    { "rest", "color" },
    { "pvp", "color" },
    { "vehicle", "color" },
}

local function copyTable(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then out[k] = copyTable(v) else out[k] = v end
    end
    return out
end

local function mergeInto(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            mergeInto(dst[k], v)
        elseif type(v) == "table" then
            dst[k] = copyTable(v)
        else
            dst[k] = v
        end
    end
    return dst
end

--- Accept {h,s,l} or {r,g,b} and return the internal HSL form.
local function normalizeColor(c, fallback)
    if type(c) ~= "table" then return copyTable(fallback) end
    if c.h ~= nil then
        return {
            h = ((tonumber(c.h) or fallback.h) % 360 + 360) % 360,
            s = clamp(c.s, 0, 1),
            l = clamp(c.l, 0, 1),
        }
    end
    if c.r ~= nil then
        local h, s, l = rgbToHsl(clamp(c.r, 0, 1), clamp(c.g, 0, 1), clamp(c.b, 0, 1))
        return { h = h, s = s, l = l }
    end
    return copyTable(fallback)
end

--- Clamp every known numeric field and normalise the colours.
local function sanitizeStyle(style)
    for section, fields in pairs(STYLE_RANGES) do
        local values = style[section]
        if type(values) == "table" then
            for field, range in pairs(fields) do
                if values[field] ~= nil then
                    values[field] = clamp(values[field], range[1], range[2])
                end
            end
        end
    end
    for _, entry in ipairs(COLOR_FIELDS) do
        local section, field = entry[1], entry[2]
        local values = style[section]
        if type(values) == "table" then
            values[field] = normalizeColor(values[field], DEFAULT_STYLE[section][field])
        end
    end
    -- The critical threshold can never be above the low-health threshold.
    local lh = style.lowHealth
    if lh.critical > lh.threshold then lh.critical = lh.threshold end
    return style
end

ANIM.style = copyTable(DEFAULT_STYLE)

-- ============================================================================
-- SECTION 6: Public event registry
-- ============================================================================

-- The colour engine has its own registry; keeping the two apart means the
-- libraries never fight over an event name.
local registry = {}

local function fireEvent(event, ...)
    local bucket = registry[event]
    if not bucket then return end
    for callback in pairs(bucket) do
        pcall(callback, event, ...)
    end
end

ANIM.events = { Fire = fireEvent }

function ANIM:RegisterCallback(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    local bucket = registry[event]
    if not bucket then
        bucket = {}
        registry[event] = bucket
    end
    if bucket[fn] then return true end
    bucket[fn] = true
    callbackCount = callbackCount + 1
    -- A consumer that only listens for events (and never registers a sink)
    -- still needs the game events, so the tracking follows the callbacks too.
    ensureEventFrame()
    updateTracking()
    return true
end

function ANIM:UnregisterCallback(event, fn)
    local bucket = registry[event]
    if bucket and bucket[fn] then
        bucket[fn] = nil
        callbackCount = callbackCount - 1
        updateTracking()
    end
    return true
end

function ANIM:UnregisterAllCallbacks()
    registry = {}
    callbackCount = 0
    updateTracking()
    return true
end

-- ============================================================================
-- SECTION 7: Player state
-- ============================================================================

-- Everything the layer knows about the player.  Read-only for consumers.
local STATE = {
    inCombat = false,
    resting = false,
    healthPct = 1,
    healthKnown = false,
    tier = "unknown",
    lowHealth = false,
    dead = false,
    ghost = false,
    pvp = false,
    ffaPvp = false,
    vehicle = false,
    afk = false,
    charmed = false,
    combatStart = 0,
    updatedAt = -1,
}

-- The combat state is authoritative once the client told us about it; the
-- API is only consulted before the first event arrives.
STATE.combatOverride = nil

-- How long a sampled state stays valid.  Sampling is cheap but not free, and
-- a consumer may pull the colour every frame.
local STATE_TTL = 0.1

local function sampleHealth()
    if healthIsSecret() then return nil, false end
    local current = safeNumber(safeCall(UnitHealth, "player"))
    local maximum = safeNumber(safeCall(UnitHealthMax, "player"))
    if not current or not maximum or maximum <= 0 then return nil, false end
    return current / maximum, true
end

--- Resample the player state.
-- @param force boolean ignore the TTL
-- @return state table
local function sampleState(force)
    local now = getNow()
    if not force and now and STATE.updatedAt >= 0 and (now - STATE.updatedAt) < STATE_TTL then
        return STATE
    end

    local style = ANIM.style

    -- Combat: the event wins, the API is the fallback.
    local combat
    if STATE.combatOverride ~= nil then
        combat = STATE.combatOverride
    else
        combat = safeBool(safeCall(UnitAffectingCombat, "player"))
    end
    if combat == nil then combat = STATE.inCombat end
    if combat ~= STATE.inCombat then
        STATE.inCombat = combat
        if combat then
            if not STATE.combatStart or STATE.combatStart <= 0 then
                STATE.combatStart = now or 0
            end
        else
            STATE.combatStart = 0
        end
        fireEvent("OnCombatStateChanged", combat)
    end

    STATE.resting = safeBool(safeCall(IsResting)) or false

    local pct, known = sampleHealth()
    STATE.healthKnown = known
    STATE.healthPct = pct or 1
    if not known then
        STATE.tier = "unknown"
        STATE.lowHealth = false
    else
        STATE.lowHealth = pct < style.lowHealth.threshold
        if pct < style.lowHealth.critical then
            STATE.tier = "critical"
        elseif STATE.lowHealth then
            STATE.tier = "low"
        else
            STATE.tier = "healthy"
        end
    end

    STATE.dead = safeBool(safeCall(UnitIsDeadOrGhost, "player")) or false
    STATE.ghost = safeBool(safeCall(UnitIsGhost, "player")) or false
    STATE.pvp = safeBool(safeCall(UnitIsPVP, "player")) or false
    STATE.ffaPvp = safeBool(safeCall(UnitIsPVPFreeForAll, "player")) or false
    STATE.vehicle = (
        safeBool(safeCall(UnitInVehicle, "player"))
        or safeBool(safeCall(UnitUsingVehicle, "player"))
        or safeBool(safeCall(UnitHasVehicleUI, "player"))
    ) or false
    STATE.afk = safeBool(safeCall(UnitIsAFK, "player")) or false
    STATE.charmed = safeBool(safeCall(UnitIsCharmed, "player")) or false

    STATE.updatedAt = now or 0
    return STATE
end

--- How deep the player is inside the low-health band (0..1).
local function severityOf(pct, lowHealth)
    if not pct or not lowHealth then return 0 end
    local threshold = lowHealth.threshold
    local critical = lowHealth.critical
    if pct >= threshold then return 0 end
    if critical >= threshold then return 1 end
    if pct <= critical then return 1 end
    return (threshold - pct) / (threshold - critical)
end

-- ============================================================================
-- SECTION 8: Colour resolution
-- ============================================================================

-- The modifiers a consumer can switch off per sink.
local ALL_MODIFIERS = {
    combat = true,
    ooc = true,
    rest = true,
    lowHealth = true,
    pvp = true,
    vehicle = true,
    dead = true,
}

--- The base of a consumer may be a slot name, a colour table or a function
--- returning either one (a consumer whose slot depends on the theme passes a
--- function, e.g. "the slot the user picked").
local function resolveBase(base)
    if type(base) == "function" then
        local ok, value = pcall(base)
        if not ok then return "edge" end
        base = value
    end
    if type(base) == "table" then return base end
    if type(base) == "string" then return base end
    return "edge"
end

--- Resolve the base colour of a slot ("edge" / "ambient" / "highlight" /
--- "neutral") or of a caller supplied {r,g,b,a} table.
local function getBaseColor(base)
    base = resolveBase(base)
    if type(base) == "table" then
        return clamp(base.r, 0, 1),
               clamp(base.g, 0, 1),
               clamp(base.b, 0, 1),
               clamp(base.a == nil and 1 or base.a, 0, 1)
    end
    local key = (type(base) == "string" and base) or "edge"
    local core = getCore()
    if core then
        if key == "ambient" then
            local r, g, b, a = safeCall(core.GetCurrentAmbientTint, core)
            if r then return r, g, b, a end
        elseif key == "highlight" then
            local r, g, b = safeCall(core.GetCurrentHighlightWash, core)
            if r then return r, g, b, 1 end
        elseif key == "neutral" then
            local r, g, b = safeCall(core.GetCurrentNeutral, core)
            if r then return r, g, b, 1 end
        else
            local r, g, b, a = safeCall(core.GetCurrentEdgeColor, core)
            if r then return r, g, b, a or 0.8 end
        end
    end
    local fallback = DEFAULT_STYLE.base[key] or DEFAULT_STYLE.base.edge
    return fallback.r, fallback.g, fallback.b, fallback.a
end

--- Apply the state modifiers to a base colour.
-- @return r, g, b, a (all in [0,1])
local function computeColor(r, g, b, a, state, style, mods)
    local h, s, l = rgbToHsl(r, g, b)

    if state.dead and mods.dead and style.dead.enabled then
        -- Dead: grey and dim.  No pulse, no other tint.
        s = 0
        l = style.dead.lightness
        a = style.dead.alpha
    else
        if mods.rest and state.resting and style.rest.enabled then
            local c = style.rest.color
            h = lerpHue(h, c.h, style.rest.blend)
            s = s + (c.s - s) * style.rest.blend
            l = l + (c.l - l) * style.rest.blend
            a = a * style.rest.alphaScale
        end
        if mods.pvp and (state.pvp or state.ffaPvp) and style.pvp.enabled then
            local c = style.pvp.color
            h = lerpHue(h, c.h, style.pvp.blend)
            s = s + (c.s - s) * style.pvp.blend
            l = l + (c.l - l) * style.pvp.blend
        end
        if mods.vehicle and state.vehicle and style.vehicle.enabled then
            local c = style.vehicle.color
            h = lerpHue(h, c.h, style.vehicle.blend)
            s = s + (c.s - s) * style.vehicle.blend
            l = l + (c.l - l) * style.vehicle.blend
        end

        if state.inCombat then
            if mods.combat and style.combat.enabled then
                l = l + style.combat.lightnessBoost
                s = s + style.combat.saturationBoost
                a = a * style.combat.alphaScale
            end
        elseif mods.ooc and style.ooc.enabled then
            l = l * style.ooc.lightnessScale
            a = a * style.ooc.alphaScale
        end
    end

    h = h % 360
    s = clamp(s, 0, 1)
    l = clamp(l, 0, 1)
    a = clamp(a, 0, 1)
    r, g, b = hslToRgb(h, s, l)

    -- Low health owns the hue: the base is mixed towards a plain danger red
    -- in RGB, so the result is a real red and never a Monet complement.
    if state.lowHealth and mods.lowHealth and style.lowHealth.enabled then
        local severity = severityOf(state.healthPct, style.lowHealth)
        if severity > 0 then
            local lh = style.lowHealth
            local t = lh.blend + (lh.blendCritical - lh.blend) * severity
            local c = lh.color
            local lr, lg, lb = hslToRgb(c.h, c.s, c.l)
            r = r + (lr - r) * t
            g = g + (lg - g) * t
            b = b + (lb - b) * t
            a = a + lh.alphaBoost * severity
        end
    end

    return clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), clamp(a, 0, 1)
end

-- ============================================================================
-- SECTION 9: Pulse
-- ============================================================================

--- The three wave values of the current moment.  Computed once per tick and
--- shared by every sink: the wave is a property of the moment, not of the
--- consumer.
-- @return combatBreath, combatFlash, lowHealthBreath
local function computeWaves(now, state, style)
    local combatBreath, combatFlash, lowHealthBreath = 0, 0, 0
    local combat = style.combat
    if state.inCombat then
        local t = now - (state.combatStart or now)
        if t < 0 then t = 0 end
        if combat.pulse and combat.pulseAmplitude > 0 then
            combatBreath = breathAt(t, combat.pulsePeriod)
        end
        if combat.enterFlash and combat.flashAmplitude > 0
            and combat.flashDuration > 0 and t < combat.flashDuration then
            local p = t / combat.flashDuration
            combatFlash = (1 - p) * (1 - p) * breathAt(t, combat.flashWavePeriod)
        end
    end
    local lh = style.lowHealth
    if state.lowHealth and lh.pulse and lh.pulseAmplitude > 0 then
        local severity = severityOf(state.healthPct, lh)
        local period = severity >= 1 and lh.criticalPeriod or lh.pulsePeriod
        lowHealthBreath = breathAt(now, period) * (0.5 + 0.5 * severity)
    end
    return combatBreath, combatFlash, lowHealthBreath
end

--- The alpha offset a sink gets from the pulse sources.
local function amplitudeFor(mods, state, style, combatBreath, combatFlash, lowHealthBreath)
    local amp = 0
    local combat = style.combat
    if mods.combat and state.inCombat and combat.enabled then
        if combat.pulse and combat.pulseAmplitude > 0 then
            amp = math.max(amp, combat.pulseAmplitude * combatBreath)
        end
        if combat.enterFlash and combat.flashAmplitude > 0 then
            amp = math.max(amp, combat.flashAmplitude * combatFlash)
        end
    end
    local lh = style.lowHealth
    if mods.lowHealth and state.lowHealth and lh.enabled and lh.pulse then
        amp = math.max(amp, lh.pulseAmplitude * lowHealthBreath)
    end
    return amp
end

--- Does this sink have a running pulse source?  (The wave can be at zero
--- right now and still have to be advanced by the ticker.)
local function sinkPulseActive(sink, state, style)
    local combat = style.combat
    if sink.mods.combat and state.inCombat and combat.enabled
        and (combat.pulse or combat.enterFlash) then
        return true
    end
    local lh = style.lowHealth
    if sink.mods.lowHealth and state.lowHealth and lh.enabled and lh.pulse then
        return true
    end
    return false
end

-- ============================================================================
-- SECTION 10: Core (colour engine) subscription
-- ============================================================================

-- The colour engine announces every recompute through "OnThemeRefreshed"
-- (the debounced "OnThemeColorsChanged" would miss silent profile switches).
subscribeCore = function()
    if coreSubscribed then return end
    local core = getCore()
    if not core or type(core.RegisterCallback) ~= "function" then return end
    coreHandler = function()
        refreshAll(false)
    end
    if pcall(core.RegisterCallback, core, "OnThemeRefreshed", coreHandler) then
        coreSubscribed = true
    end
end

unsubscribeCore = function()
    if not coreSubscribed then return end
    coreSubscribed = false
    local core = getCore()
    if core and type(core.UnregisterCallback) == "function" and coreHandler then
        pcall(core.UnregisterCallback, core, "OnThemeRefreshed", coreHandler)
    end
    coreHandler = nil
end

-- ============================================================================
-- SECTION 11: Ticker
-- ============================================================================

--- One tick: the waves are computed once, then every pulsing sink gets its
--- alpha.  No trigonometry, no allocation, no repaint when the alpha did not
--- move by a visible amount.
local function tickPulse()
    local now = getNow() or 0
    local state = sampleState(false)
    local style = ANIM.style
    local combatBreath, combatFlash, lowHealthBreath = computeWaves(now, state, style)

    local anyActive = false
    for i = 1, sinkCount do
        local sink = sinks[i]
        if sink.enabled and sink.pulse and sinkPulseActive(sink, state, style) then
            anyActive = true
            local amp = amplitudeFor(sink.mods, state, style, combatBreath, combatFlash, lowHealthBreath)
            local a = clamp(sink.staticA + amp, 0, 1)
            if sink.lastA == nil or math.abs(a - sink.lastA) > ALPHA_EPS then
                sink.lastA = a
                callSink(sink, sink.staticR, sink.staticG, sink.staticB, a)
            end
        end
    end

    if not anyActive and ticker then
        ticker:Hide()
        tickerAcc = 0
    end
end

ensureTicker = function()
    if ticker then
        if not ticker:IsShown() then ticker:Show() end
        return ticker
    end
    if not _G.CreateFrame then return nil end
    ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, elapsed)
        tickerAcc = tickerAcc + (elapsed or 0)
        local interval = 1 / clamp(ANIM.style.pulse.fps, 1, 60)
        if tickerAcc < interval then return end
        tickerAcc = tickerAcc - interval
        if tickerAcc > interval then tickerAcc = 0 end
        tickPulse()
    end)
    -- A fresh ticker starts running right away: it was asked for because a
    -- pulse source is active.
    ticker:Show()
    return ticker
end

-- ============================================================================
-- SECTION 12: Sink registry
-- ============================================================================

--- Call a consumer callback.  A broken consumer must never stop the others,
--- so the call is isolated and the failure is reported once.
callSink = function(sink, r, g, b, a)
    local ok, err = pcall(sink.apply, r, g, b, a, sink.state, sink.resolvedBase or sink.base)
    if not ok and not sink.warned then
        sink.warned = true
        warn("colour sink error: " .. tostring(err))
    end
end

--- Recompute the static part of a sink and repaint it.
local function refreshSink(sink, now, force)
    if not sink.enabled then return end
    local style = ANIM.style
    local state = sampleState(force)
    local base = resolveBase(sink.base)
    sink.resolvedBase = base
    local br, bg, bb, ba = getBaseColor(base)
    local r, g, b, a = computeColor(br, bg, bb, ba, state, style, sink.mods)

    sink.staticR, sink.staticG, sink.staticB, sink.staticA = r, g, b, a
    sink.state = state

    local combatBreath, combatFlash, lowHealthBreath = computeWaves(now or 0, state, style)
    local amp = amplitudeFor(sink.mods, state, style, combatBreath, combatFlash, lowHealthBreath)
    local finalA = clamp(a + amp, 0, 1)

    if sink.lastR ~= r or sink.lastG ~= g or sink.lastB ~= b
        or sink.lastA == nil or math.abs(finalA - sink.lastA) > ALPHA_EPS then
        sink.lastR, sink.lastG, sink.lastB, sink.lastA = r, g, b, finalA
        callSink(sink, r, g, b, finalA)
        fireEvent("OnStateColorChanged", sink.base, r, g, b, finalA, state)
    end

    if sink.pulse and sinkPulseActive(sink, state, style) then
        ensureTicker()
    end
end

--- Repaint every registered sink.
refreshAll = function(force)
    -- The colour engine may have appeared after we subscribed; retry once it
    -- is there (the flag makes this a single boolean test).
    if not coreSubscribed then subscribeCore() end
    local now = getNow() or 0
    for i = 1, sinkCount do
        refreshSink(sinks[i], now, force)
    end
end

-- ============================================================================
-- SECTION 13: WoW events
-- ============================================================================

-- The event frame only exists while at least one sink is registered, so a
-- consumer that never registers a sink costs nothing.
local WOW_EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_FLAGS_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_FACTION",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
}

local function isPlayerUnit(unit)
    return unit == nil or unit == "player"
end

local function handleWoWEvent(event, arg1)
    if event == "PLAYER_REGEN_DISABLED" then
        STATE.combatOverride = true
        if not STATE.combatStart or STATE.combatStart <= 0 then
            STATE.combatStart = getNow() or 0
        end
        if not STATE.inCombat then
            STATE.inCombat = true
            fireEvent("OnCombatStateChanged", true)
        end
        sampleState(true)
        refreshAll(false)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        STATE.combatOverride = false
        if STATE.inCombat then
            STATE.inCombat = false
            STATE.combatStart = 0
            fireEvent("OnCombatStateChanged", false)
        end
        sampleState(true)
        refreshAll(false)
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if not isPlayerUnit(arg1) then return end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FACTION"
        or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if not isPlayerUnit(arg1) then return end
    end
    sampleState(true)
    refreshAll(false)
    fireEvent("OnPlayerStateChanged", STATE)
end

setEventTracking = function(enabled)
    if not eventFrame then return end
    if enabled then
        if tracking then return end
        tracking = true
        for _, event in ipairs(WOW_EVENTS) do
            eventFrame:RegisterEvent(event)
        end
    else
        if not tracking then return end
        tracking = false
        eventFrame:UnregisterAllEvents()
    end
end

ensureEventFrame = function()
    if eventFrame then return true end
    if not _G.CreateFrame then return false end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        local ok, err = pcall(handleWoWEvent, event, arg1)
        if not ok then
            warn("event handler error: " .. tostring(err))
        end
    end)
    return true
end

--- The game events are only needed while somebody listens: either a sink is
--- registered or a callback is waiting for an event.
updateTracking = function()
    setEventTracking(sinkCount > 0 or callbackCount > 0)
end

-- ============================================================================
-- SECTION 14: Public API
-- ============================================================================

--- Get the current colour of a slot with the player state applied.
-- @param base string|table "edge" (default) / "ambient" / "highlight" /
--        "neutral", or a {r,g,b,a} table
-- @param atTime number|nil timestamp for the pulse (defaults to now)
-- @param modifiers table|nil per call modifier switches
-- @return r, g, b, a
function ANIM:GetColor(base, atTime, modifiers)
    local ok, r, g, b, a = pcall(function()
        local style = ANIM.style
        local state = sampleState(false)
        local mods
        if type(modifiers) ~= "table" then
            mods = ALL_MODIFIERS
        else
            mods = {}
            for key, value in pairs(ALL_MODIFIERS) do mods[key] = value end
            for key, value in pairs(modifiers) do
                if ALL_MODIFIERS[key] ~= nil then mods[key] = value and true or false end
            end
        end
        local br, bg, bb, ba = getBaseColor(base)
        local cr, cg, cb, ca = computeColor(br, bg, bb, ba, state, style, mods)
        local now = atTime or getNow() or 0
        local combatBreath, combatFlash, lowHealthBreath = computeWaves(now, state, style)
        local amp = amplitudeFor(mods, state, style, combatBreath, combatFlash, lowHealthBreath)
        return cr, cg, cb, clamp(ca + amp, 0, 1)
    end)
    if ok then return r, g, b, a end
    warn("GetColor failed: " .. tostring(r))
    return 0.5, 0.5, 0.5, 0.8
end

--- The current player state (read-only).
function ANIM:GetPlayerState()
    sampleState(false)
    return STATE
end

--- The active style table (read-only).
function ANIM:GetStyle()
    return ANIM.style
end

--- Merge a partial style into the active one and repaint everything.
-- @param partial table
-- @return boolean success
function ANIM:SetStyle(partial)
    if type(partial) ~= "table" then
        warn("SetStyle: expected a table")
        return false
    end
    local incoming = copyTable(partial)
    -- Colours may arrive as RGB; convert them before they are merged into
    -- the HSL form the layer stores.
    for _, entry in ipairs(COLOR_FIELDS) do
        local section, field = entry[1], entry[2]
        if type(incoming[section]) == "table" and incoming[section][field] ~= nil then
            incoming[section][field] = normalizeColor(incoming[section][field], DEFAULT_STYLE[section][field])
        end
    end
    mergeInto(ANIM.style, incoming)
    sanitizeStyle(ANIM.style)
    refreshAll(true)
    return true
end

--- Restore the built-in style.
function ANIM:ResetStyle()
    ANIM.style = copyTable(DEFAULT_STYLE)
    refreshAll(true)
    return true
end

--- Register a colour sink.  The callback receives the final colour.
-- @param apply function(r, g, b, a, state, base)
-- @param opts table { base = "edge", pulse = false, modifiers = {...}, enabled = true }
-- @return handle|nil
function ANIM:RegisterColorSink(apply, opts)
    if type(apply) ~= "function" then
        warn("RegisterColorSink: apply must be a function")
        return nil
    end
    opts = type(opts) == "table" and opts or {}

    local sink = {
        apply = apply,
        base = opts.base or "edge",
        pulse = opts.pulse and true or false,
        mods = {},
        enabled = opts.enabled ~= false,
        lastR = nil, lastG = nil, lastB = nil, lastA = nil,
        staticR = 0, staticG = 0, staticB = 0, staticA = 0,
        state = nil,
        resolvedBase = nil,
        warned = false,
    }
    for key, value in pairs(ALL_MODIFIERS) do sink.mods[key] = value end
    if type(opts.modifiers) == "table" then
        for key, value in pairs(opts.modifiers) do
            if ALL_MODIFIERS[key] ~= nil then
                sink.mods[key] = value and true or false
            end
        end
    end

    sinkCount = sinkCount + 1
    sinks[sinkCount] = sink

    ensureEventFrame()
    updateTracking()
    subscribeCore()
    refreshSink(sink, getNow() or 0, true)

    local handle = {}
    function handle:Refresh()
        refreshSink(sink, getNow() or 0, true)
        return self
    end
    function handle:SetEnabled(enabled)
        sink.enabled = enabled and true or false
        if sink.enabled then
            refreshSink(sink, getNow() or 0, true)
        end
        return self
    end
    function handle:GetState()
        return sink.state
    end
    function handle:GetColor()
        local now = getNow() or 0
        local state = sink.state or STATE
        local combatBreath, combatFlash, lowHealthBreath = computeWaves(now, state, ANIM.style)
        local amp = amplitudeFor(sink.mods, state, ANIM.style, combatBreath, combatFlash, lowHealthBreath)
        return sink.staticR, sink.staticG, sink.staticB, clamp(sink.staticA + amp, 0, 1)
    end
    function handle:Unregister()
        for i = 1, sinkCount do
            if sinks[i] == sink then
                sinks[i] = sinks[sinkCount]
                sinks[sinkCount] = nil
                sinkCount = sinkCount - 1
                break
            end
        end
        if sinkCount == 0 then
            if ticker then ticker:Hide() end
            unsubscribeCore()
        end
        updateTracking()
        return self
    end
    sink.handle = handle
    return handle
end

--- Repaint every registered sink.
function ANIM:RefreshAll()
    refreshAll(true)
    return true
end

-- ============================================================================
-- SECTION 15: Initialisation
-- ============================================================================

-- Publish the aliases.  The colour engine may load after us; getBaseColor
-- resolves it lazily, so a late engine is picked up on the next call.
getCore()
_G.LibMonetColorAnim = ANIM
