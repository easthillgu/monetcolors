-- MonetColorBaseline.lua
-- Monet Color Baseline Configuration v3
-- Generated: 2026-10-12
-- Source: 15 paintings (Wikimedia Commons high-res)
-- Extraction: 100xN sampling, step=16, L filter 0.08-0.94

local M = {}

-- 7 hue domains with edge glow parameters
-- hueShift: degrees to shift for complementary edge glow
-- satMult: saturation multiplier for edge glow (0-1)
-- lBias: lightness adjustment for edge glow
-- range: half-open interval [start, end), e.g. {30, 60} = [30, 60)
--         h=60 belongs to OliveSage, not AmberGold
--         Red/Warm range={0,30,330,360} = [0,30) ∪ [330,360)
--         h=330 belongs to Red/Warm, not VioletRose
M.DEFAULT_MONET_RULES = {
    domains = {
        {name="Red/Warm",     range={0, 30, 330, 360}, hueShift=170, satMult=0.35, lBias=-0.03},
        {name="AmberGold",    range={30, 60},          hueShift=180, satMult=0.65, lBias=0.00},
        {name="OliveSage",    range={60, 90},          hueShift=180, satMult=0.80, lBias=0.02},
        {name="ForestGreen",  range={90, 150},         hueShift=180, satMult=0.90, lBias=0.00},
        {name="CyanMist",     range={150, 210},        hueShift=180, satMult=0.95, lBias=0.00},
        {name="IndigoShadow", range={210, 270},        hueShift=180, satMult=0.90, lBias=-0.02},
        {name="VioletRose",   range={270, 330},        hueShift=180, satMult=0.85, lBias=0.01},
    },

    -- 6 complementary color pairs — exact hue overrides, takes priority over domain hueShift
    -- Match logic: check complementaryPairs first (exact h match), fall back to domain range
    -- Red/Warm domain uses hueShift=170 (not 180) for warmer cyan-green glow
    -- h=30 is a Red/Warm override point (AmberGold domain rule [30,60) superseded)
    complementaryPairs = {
        {h=0,   complement=170},  -- Red -> Cyan-Green (hueShift=170)
        {h=30,  complement=200},  -- Orange -> Blue-Cyan (hueShift=170, overrides AmberGold 180)
        {h=40,  complement=220},  -- Amber -> Indigo (hueShift=180)
        {h=60,  complement=240},  -- Yellow -> Blue-Violet (hueShift=180)
        {h=120, complement=300},  -- Green -> Magenta (hueShift=180)
        {h=330, complement=140},  -- Magenta-Red -> Green (hueShift=170)
    },

    -- Dominant hues — core Monet style colors (Top8 in >=2 paintings)
    -- v3 review: removed H=300 (only 1 painting — not style-defining)
    dominantHues = {0, 30, 40, 60, 90, 120, 180, 200, 210, 220, 240},

    -- Scarcity hues — absent or rare in Monet palette (<=1 painting)
    -- v3: removed H=330 (present in red domain data)
    -- v3: removed H=240 (7 swatches in 3 paintings — style-defining, not scarce)
    scarcityHues = {270, 280, 300},

    -- Saturation compensation
    -- v2: 1.25 (Met JPEG caused 35% saturation loss)
    -- v3: 1.05 (Wikimedia high-res, ~5% residual JPEG gap)
    -- Based on PaletteInspiration same-method comparison: median dS=0.054
    saturationCompensation = {
        factor = 1.05,
        minSaturation = 0.10,  -- only apply when S > 0.10
        v2factor = 1.25,
        description = "Applied to extracted S before matching. v3 high-res reduces gap.",
    },
}

return M
