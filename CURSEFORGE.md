# CurseForge project copy — LibMonetColor-1.0

Version 1.3.0 · Interface 16001 · Lua 5.1 · MIT · <https://github.com/easthillgu/monetcolors>

## 1. Summary (paste into the Summary field, one line)

A LibStub library that turns the player's current zone into adaptive, Monet-inspired UI theme colors, with an optional layer that tints frames by combat, rest and health state.

## 2. Description — BBCode (paste into the CurseForge Description field)

```text
[b]LibMonetColor-1.0[/b] is a small, dependency-free LibStub library that gives an addon a colour theme derived from where the player actually is. It samples the ambient colour of the current zone and derives four coordinated, Impressionist-style colours — [i]Edge Glow[/i], [i]Ambient Tint[/i], [i]Highlight Wash[/i] and a [i]Monet Neutral[/i] — so borders, backgrounds and highlights follow the world instead of one fixed palette.

[b]This is a library, not a standalone UI.[/b] Nothing is drawn on screen until an addon consumes the colours. It is built for addon authors.

[b]Why it is different[/b]
[list]
[*] Not a lookup table of fixed themes: colours are computed from the zone's environment colour through a Monet-style rule engine (complementary hue, S-curve lightness clamp, hue domains, achromatic fallback).
[*] Zone data for 25 areas is included, generated from in-game screenshots and travel photography. Resolution order: runtime override -> zone data -> parent map chain -> neutral fallback. Extend any zone at runtime with [code]RegisterMapEnv[/code]; no fork needed.
[*] A strict "5+3" model: functional colours (primary, health, resource, danger, neutral) stay with the addon and are [b]never[/b] stylised. The library only supplies the neutral plus three signature colours. Readability wins over art.
[*] Debounced events: [code]OnThemeColorsChanged[/code] fires only when Delta E > 5.0, so zone changes do not cause redraw storms. [code]OnThemeRefreshed[/code] fires on every recompute.
[/list]

[b]Optional state layer — LibMonetColor-Anim-1.0[/b]
An optional companion layer translates player state (combat, out of combat, resting, low health, PvP, vehicle, death) into colour modifiers. Consumers register a colour sink and just paint the RGBA they receive — no event registration, no health math, no OnUpdate. All pulsing runs on [b]one shared ticker[/b] with a 64-point waveform lookup, 15 fps, and it hides itself when idle. 1.3.0 adds [code]SetBaseColorProvider()[/code]: a consumer can inject its own palette (for example one that has been contrast-corrected) so state-tinted borders share one source of truth with the rest of its UI; without a provider the layer behaves exactly as 1.2.x. Do not load this file if you only need environment colours.

[b]Colour tools[/b]
[code]ContrastRatio()[/code] (WCAG 2.x) and [code]AtLightness()[/code] (CIE L* relocation, preserving hue and saturation) are pure functions for building readable lightness ladders. They are computed on theme refresh and cached by the consumer — never call them per frame.

[b]For addon authors[/b]
[code]
local LMC = LibStub("LibMonetColor-1.0", true)
if LMC then
    local r, g, b, a = LMC:GetCurrentEdgeColor()
    MyFrame:SetBackdropBorderColor(r, g, b, a)
else
    MyFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8) -- graceful fallback
end

LMC:RegisterCallback("OnThemeColorsChanged", function(_, entry)
    MyFrame:ApplyTheme(entry) -- edge, ambient, highlight, neutral
end)
[/code]

[b]Installation[/b]
[list]
[*] [b]Standalone:[/b] install this addon as [code]Interface/AddOns/LibMonetColor-1.0[/code]. It is [code]LoadOnDemand[/code]; consumers pull it in with [code]## OptionalDeps: LibMonetColor-1.0[/code] or [code]LoadAddOn[/code]. LibStub is embedded, so no other addon is required.
[*] [b]Vendored:[/b] copy the four Lua files and [code]Libs/LibStub/LibStub.lua[/code] into your own addon's [code]Libs/[/code] and list them in your TOC in the documented order.
[*] [b]Use one or the other, never both[/b] on the same client: two copies register the same LibStub major version and the second one exits, wasting a cache and an event frame.
[/list]

[b]Contracts[/b]
[list]
[*] Never throws: on error, public APIs return neutral grey [code](0.5, 0.5, 0.5)[/code] with a 30-second warning cooldown.
[*] Every returned component is clamped to [code][0, 1][/code].
[*] Consumer isolation: one broken callback cannot break the others.
[*] Secret-value safe: when health is restricted, only the low-health effect is disabled; nothing is guessed and nothing raises.
[*] Zero idle cost: without sinks or callbacks the state layer registers no events and runs no ticker.
[*] Public API is backwards compatible throughout 1.x.
[/list]

[b]Compatibility & dependencies[/b]
Interface 16001, Lua 5.1, no hard dependencies. LibStub is embedded (public domain). CallbackHandler-1.0 is optional — a built-in callback registry is used when it is absent. The library creates no frames and registers no game events (the optional state layer's ticker is the only exception). 163 unit tests pass outside the game client.

[b]Documentation & source[/b]
Full API contract: [url=https://github.com/easthillgu/monetcolors/blob/main/LibMonetColor-1.0-API.md]LibMonetColor-1.0-API.md[/url]
Source, issues and changelog: [url=https://github.com/easthillgu/monetcolors]github.com/easthillgu/monetcolors[/url]

[b]Credits & license[/b]
MIT © 2026 EastHillGu. Embedded LibStub is public domain. The Monet painting samples used to derive the colour rules come from Wikimedia Commons (public domain); the images themselves are not distributed. No in-game assets from Blizzard are shipped.
```

## 3. Description — Markdown (GitHub / Wago / other portals)

````markdown
**LibMonetColor-1.0** is a small, dependency-free LibStub library that gives an addon a colour theme derived from where the player actually is. It samples the ambient colour of the current zone and derives four coordinated, Impressionist-style colours — *Edge Glow*, *Ambient Tint*, *Highlight Wash* and a *Monet Neutral* — so borders, backgrounds and highlights follow the world instead of one fixed palette.

**This is a library, not a standalone UI.** Nothing is drawn on screen until an addon consumes the colours. It is built for addon authors.

### Why it is different

- Not a lookup table of fixed themes: colours are computed from the zone's environment colour through a Monet-style rule engine (complementary hue, S-curve lightness clamp, hue domains, achromatic fallback).
- Zone data for 25 areas is included, generated from in-game screenshots and travel photography. Resolution order: runtime override → zone data → parent map chain → neutral fallback. Extend any zone at runtime with `RegisterMapEnv`; no fork needed.
- A strict **5+3** model: functional colours (primary, health, resource, danger, neutral) stay with the addon and are **never** stylised. The library only supplies the neutral plus three signature colours. Readability wins over art.
- Debounced events: `OnThemeColorsChanged` fires only when Delta E > 5.0; `OnThemeRefreshed` fires on every recompute.

### Optional state layer — LibMonetColor-Anim-1.0

An optional companion layer translates player state (combat, out of combat, resting, low health, PvP, vehicle, death) into colour modifiers. Consumers register a colour sink and just paint the RGBA they receive — no event registration, no health math, no `OnUpdate`. All pulsing runs on **one shared ticker** with a 64-point waveform lookup, 15 fps, and it hides itself when idle. Do not load this file if you only need environment colours.

### Colour tools

`ContrastRatio()` (WCAG 2.x) and `AtLightness()` (CIE L* relocation, preserving hue and saturation) are pure functions for building readable lightness ladders. Compute them on theme refresh and cache the result — never call them per frame.

### For addon authors

```lua
local LMC = LibStub("LibMonetColor-1.0", true)
if LMC then
    local r, g, b, a = LMC:GetCurrentEdgeColor()
    MyFrame:SetBackdropBorderColor(r, g, b, a)
else
    MyFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8) -- graceful fallback
end

LMC:RegisterCallback("OnThemeColorsChanged", function(_, entry)
    MyFrame:ApplyTheme(entry) -- edge, ambient, highlight, neutral
end)
```

### Installation

| Mode | How |
| :--- | :--- |
| Standalone | Install as `Interface/AddOns/LibMonetColor-1.0`. It is `LoadOnDemand`; consumers use `## OptionalDeps: LibMonetColor-1.0` or `LoadAddOn`. LibStub is embedded. |
| Vendored | Copy the four Lua files plus `Libs/LibStub/LibStub.lua` into your addon's `Libs/` and list them in TOC order. |

Use one mode or the other, never both on the same client: two copies register the same LibStub major version and the second one exits.

### Contracts

- **Never throws** — on error, public APIs return neutral grey `(0.5, 0.5, 0.5)` with a 30-second warning cooldown.
- Every returned component is clamped to `[0, 1]`.
- **Consumer isolation** — one broken callback cannot break the others.
- **Secret-value safe** — when health is restricted, only the low-health effect is disabled.
- **Zero idle cost** — without sinks or callbacks the state layer registers no events and runs no ticker.
- Public API is backwards compatible throughout 1.x.

### Compatibility & dependencies

Interface 16001, Lua 5.1, no hard dependencies. Embedded LibStub is public domain; CallbackHandler-1.0 is optional (a built-in registry is used when absent). The library creates no frames and registers no game events — the optional state layer's ticker is the only exception. 163 unit tests pass outside the game client.

### Documentation & source

- [Full API contract](https://github.com/easthillgu/monetcolors/blob/main/LibMonetColor-1.0-API.md)
- [Source, issues, changelog](https://github.com/easthillgu/monetcolors)

### Credits & license

MIT © 2026 EastHillGu. Embedded LibStub is public domain. Monet painting samples used to derive the colour rules come from Wikimedia Commons (public domain); the images are not distributed. No Blizzard in-game assets are shipped.
````

## 4. Form fields

| Field | Value |
| :--- | :--- |
| Name | lib_MonetColors |
| CurseForge project ID | 1801984 |
| Summary | See section 1 (one line, English) |
| Category | Library / Plugin Libraries |
| Game | World of Warcraft |
| Game version | Match the `-g` value in `.github/workflows/release.yml` (currently `1.60.1`) |
| License | MIT |
| Source / project URL | <https://github.com/easthillgu/monetcolors> |
| Primary file | `LibMonetColor-1.0.zip` (see section 5) |

The project is live: **CF project 1801984 (`lib_MonetColors`)**, first file `LibMonetColor-1.0-1.2.0.zip` uploaded manually on 2026-11-13. `.github/workflows/release.yml` pins `-p 1801984`; the only per-repository setting left is the Actions secret `CF_API_TOKEN` (or `CF_API_KEY`). A guard step now fails the job when that secret is missing, because packager @v2 otherwise skips the upload while still reporting success (this happened for tag 1.3.0). See section 6 for the two-repo / two-project release order.

## 5. Upload package

`release/LibMonetColor-1.0-1.3.0.zip`, top-level folder `LibMonetColor-1.0/` (folder name must match the TOC name). Contents follow `.pkgmeta` (`package-as: LibMonetColor-1.0`):

| Path in zip | Purpose |
| :--- | :--- |
| `LibMonetColor-1.0.toc` | Addon declaration, `LoadOnDemand: 1` |
| `Libs/LibStub/LibStub.lua` | Embedded LibStub (public domain) |
| `LibMonetColor-1.0.lua` | Core colour engine |
| `MonetColorMapData-1.0.lua` | Generated zone environment data (25 areas) |
| `LibMonetColor-Anim-1.0.lua` | Optional state layer + shared ticker |
| `MonetColorBaseline.lua` | v3 rule baseline snapshot (not loaded at runtime; kept in line with the `.pkgmeta` shipping set) |
| `LibMonetColor-1.0-API.md` | Full API contract |
| `README.md` / `CHANGELOG.md` / `LICENSE` | Documentation and license |

Excluded as development-only (never in a release zip): `Gamepics/` (69 MB of screenshots), `Monet_Paintings/` (62 MB of paintings + manifest), `GamePalette_v1.html` / `.png` (5.3 MB rendered output), the five intermediate palette JSONs, `data/`, `tools/*.ps1`, `tests/`, `.dev/`, `.github/`, `.vscode/`, `.opencode/`, `AGENTS.md`, `.pkgmeta`, `opencode.json`, all `*.zip`.

## 6. Release topology (two repos, two CurseForge projects)

Local development is kept together: MonetUI vendors the library into `MonetUI/Libs/LibMonetColor-1.0/` and `MonetUI/Libs/LibMonetColor-Anim-1.0/`, so one client reload tests both sides. Remote repositories and CurseForge projects stay separate, and are published in sync:

| | Remote repo | CurseForge project | Package |
| :--- | :--- | :--- | :--- |
| Standalone library | `easthillgu/monetcolors` | **1801984** — lib_MonetColors | `LibMonetColor-1.0-<lib version>-forever.zip` |
| Consumer UI | `easthillgu/MonetUI` | **1791156** — MonetUI | `MonetUI-<UI version>-forever.zip` (contains the vendored library) |

Order for a library change:

1. Change the library here, bump `## Version` and `MINOR` (must exceed every vendored copy), run the 7 test groups.
2. Push `main`, then push the plain numeric tag. `.github/workflows/release.yml` uploads to 1801984 and creates the GitHub Release.
3. Copy the two updated Lua files into `MonetUI/Libs/`, verify their `MINOR` matches the source repo, run `node tools/sync-check.js`, commit in the MonetUI repo.
4. Bump MonetUI's TOC + CHANGELOG, push, then tag the MonetUI version; that workflow uploads to 1791156.

Never publish only one side. Version numbers stay independent (library `1.x`, UI `0.13.x`); they are aligned by belonging to the same change, not by sharing a number. A green Actions job is not proof of an upload — check the Files page of the matching project (approval takes about 6h). Never re-tag or manually re-upload the same version.

The library remains vendored inside the MonetUI zip: separate CF projects do **not** mean removing `Libs/`. Installing MonetUI does not require the standalone library; the standalone project serves other consumers. Do not install both on the same client (two copies register the same LibStub major version).

State on 2026-11-15: monetcolors tag `1.3.0` and its GitHub Release exist, and the standalone zip was uploaded to project 1801984 (CurseForge file id 9625084; approval takes about 6h — never re-upload the same version). Project 1791156 is on `0.13.8`; the matching vendored `1.3.0` copies ship with the next MonetUI tag.
