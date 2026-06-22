# OmniumObservator

> **WoW:** 12.0.7+ (Midnight) · **Maintainer:** Nelnamara

OmniumObservator embeds **inside the Omnium Folio frame** — the 12.0.7 weekly rune system — and tracks everything around it: your weekly rune unlocks, the Decimus Voidstorm economy (Motes, bonus rolls, Ascendant Voidcores/Voidshard, Void Assaults), recommended rune builds, the Nilhammer forge, and the weekly reset. It brings Decimus himself into the frame as an interactive, voiced 3D model — and the more you use it, the more of the Void's cast you unlock. A standalone glance panel is available too, for an at-a-glance read without opening the folio.

---

## Features

- **In-folio embed** — open the Omnium Folio and OmniumObservator anchors draggable panels inside it, flanking the rune tree:
  - **This Week** — folio progress, the 5 weekly runes (colored by loot rarity), the current/next *Seeking Knowledge* quest, the **Nilhammer forge** bar, the **weekly-quest gem bar**, and the weekly reset countdown
  - **Devouring Watch** — the full Voidstorm economy: Motes of Omnial Inquiry, Nebulous bonus rolls (held / weekly cap), Ascendant Voidcores + Voidshard, and **live Void Assaults** (Eversong / Zul'Aman) with their weekly status
  - **Omnium Counsel** *(optional)* — recommended rune builds with real rune icons, plus your **Void Favor** standing
- **Rarity-colored weeks** — the weekly list reads at a glance: **completed** weeks glow in their loot-rarity color (white → green → blue → purple → orange), the week **up next** matches the amber "Next:" line, and the rest stay gray
- **The Nilhammer forge** — a forge-progress bar tracks your one-time Voidforge build, then repurposes to your live Nebulous Voidcore cap once the Ascendant Nilhammer is forged
- **Decimus, in person** — an interactive 3D model you can summon into the folio: **left-drag** to rotate, **scroll** to zoom, **right-drag** to move him. He greets you with his real in-game voice line (and a text bubble) when the folio opens and when you click him
- **Void Favor & the Void's cast** — every bit of folio progress earns **Void Favor**, and favor unlocks new advisors to summon in Decimus's place: **Terminas**, **Riko**, and eventually **yourself**. And if you've drawn the wrong kind of attention... someone else may show up uninvited
- **Rune advisor** — Omnium Counsel cycles recommended builds from two sources: the **Omnium Folio guide** (M+ / Raid ST / Raid DoT / PvP / Casual) and **Method.gg** (DPS / M+ / Raid DoT), so you can compare the core-rune choices side by side
- **Hover tooltips everywhere** — mouse a resource row for its native game tooltip, or a progress gem for that week's quest info — without changing the clean panel layout
- **Standalone glance panel** — the same info in a movable, lockable window, with its **own opacity and frame style** independent of the docked panels
- **Deep appearance control** — per-panel width/height, per-edge background fill, frame style/size/thickness/offset, banners, glowing dividers, forge-fill color/glow, gem size/glow, mascot show/undock, watermark opacity, and a panel title color — all live in `/oo config`
- **Per-character profiles** — every setting saves per character by default, with profile copy/reset and shareable **import/export** strings
- **Minimap button** — left-click toggles the standalone panel, right-click opens options

---

## Void Favor & advisors

OmniumObservator keeps a running **Void Favor** count — a little easter-egg standing that grows as you engage with the folio:

- Opening the folio (once per day) and clicking Decimus (a few times per day, with diminishing returns) earn favor
- Each newly unlocked week, forging the Ascendant Nilhammer, and completing the *Omnium Folio Studies* achievement give larger one-time boosts

As your favor climbs, you unlock alternate advisors to summon in Decimus's place — each a fully posed 3D model with its own voice. And once you're deep enough into the folio, **Xal'atath** takes a passing interest: she'll occasionally hijack the model frame to insult you — and once you've filled all five weeks, she's been known to shove a couple of your panels out of place for fun. (A quick *Reset all panel positions* puts them right back.)

---

## Requirements

- WoW Midnight 12.0.7+
- No external dependencies (all libraries are bundled)

---

## Installation

Drop the `OmniumObservator` folder into `World of Warcraft\_retail_\Interface\AddOns\`, or install via the CurseForge app.

---

## Usage

No setup needed. OmniumObservator auto-detects which of the five *Seeking Knowledge* weeks is current (they're permanent one-time unlocks, so progress is inferred from completed quests). Log in, open the **Omnium Folio**, and the panels appear. `/oo` toggles the standalone glance panel.

### Slash commands

| Command | What it does |
| --- | --- |
| `/oo` | Toggle the standalone glance panel |
| `/oo config` *(or `options`)* | Open the options window |
| `/oo dock` | Toggle the in-folio docked panels |
| `/oo build [role]` | Cycle the recommended rune build, or set one: `m+`, `raid`, `dot`, `pvp`, `casual`, `method` |
| `/oo model` | Toggle the Decimus 3D model |
| `/oo voice` | Toggle advisor voice lines |
| `/oo font <8–20>` | Set the panel font size |
| `/oo frame <1–5>` | Switch the ornate frame style |
| `/oo banner <1–6>` | Switch the panel banner style |
| `/oo lock` / `/oo unlock` | Lock or unlock frame dragging |
| `/oo reset` | Reset all panel positions |

### Options

Everything lives in **`/oo config`** (or right-click the minimap button), organized into tabs:

- **General** — what the addon does, command help, and FAQ
- **Panels** — show/size each panel (Folio · Devouring Watch · Omnium Counsel · Standalone), per-edge background fill, mascot, and text controls
- **Appearance** — ornate frame style/size/thickness/opacity, dividers, the Nilhammer forge bar, the weekly-quest gem bar, and banners
- **Omnium Advisors** — pick & size the advisor model, lock its position, toggle voice, and view your Void Favor
- **Settings** — minimap button, changelog, and **profiles** (copy / reset / import / export)

The same options table also appears under **Escape → Options → AddOns → OmniumObservator**.

---

## Compatibility / Midnight notes

OmniumObservator reads the folio via `C_Traits` (tree 1186), currencies via `C_CurrencyInfo`, items via `C_Item`, and auras via `C_UnitAuras`. It **never modifies the Blizzard folio frame** — the panels overlay it (parented to `UIParent`) and only post-hook the folio's show/hide, so the protected frame is never tainted.

---

## Changelog

### v1.0.5

**Devouring Watch (the old DevouringWatch addon, merged in)**
- The Voidstorm panel is now **Devouring Watch** and carries a live **Void Assault** scan (Eversong / Zul'Aman) with weekly status, alongside the full economy readout. The standalone DevouringWatch addon is retired — everything it did now lives here.

**The Nilhammer forge**
- A **forge-progress bar** tracks the one-time Voidforge build, then repurposes to your live Nebulous Voidcore cap once the Ascendant Nilhammer is forged. Tunable fill texture, color, height, inset, and glow.

**Void Favor, advisors & Xal'atath**
- A **Void Favor** counter that grows as you progress the folio, unlocking alternate advisor models (Terminas, Riko, and eventually yourself) to summon in Decimus's place.
- **Xal'atath** occasionally crashes the party once you're several weeks in — and gets up to real mischief once all five weeks are done.

**Appearance & layout**
- Rewritten options on **AceConfig** with real dropdowns, media pickers, and clean tabs (mirrored into the Blizzard AddOns settings).
- **Per-character profiles** with copy/reset and shareable import/export strings.
- A pile of new fit controls: **per-panel width/height**, **per-edge background fill**, **frame size/thickness/offset**, divider thickness, panel title color, **weekly-quest gem bar**, banners, and a standalone panel with its **own opacity and frame style**.
- Weekly list recolored: **done = rarity color, next = amber, future = gray**.
- **Hover tooltips** on resource rows and progress gems.

### v1.0.4
- In-folio embed (three draggable panels), the Decimus Voidstorm economy, an interactive voiced 3D Decimus model, role-based rune Counsel (Folio guide + Method.gg), rarity-colored weeks, the first options panel, collapsible weeks, and font/opacity controls.

### v1.0.3
- Omnium Folio dock; Motes of Omnial Inquiry (live from the trait tree); weekly reset timer; suite restyle.

### v1.0.2
- Live Void-Touched Orbs counter; minimap button and AddOns-list icon.

### v1.0.1
- Auto-detect the current *Seeking Knowledge* week; Interface 120007.

### v1.0.0
- Initial release: weekly unlock tracker, achievement display, weekly quest tracking.

---

## Roadmap

<details>
<summary>Planned</summary>

- **Slotted-rune readout** — show the runes you've actually specced (via `C_Traits`) beside the recommended build
- **Per-class/spec builds** — spec-specific rune recommendations (Icy Veins / Wowhead / Method.gg), with the base builds always available and tooltips explaining each pick
- **Per-race advisor voice** — let the "You" advisor speak, drawn from WoW's generic per-race voice sets
- **Great Vault progress** — weekly reward slots at a glance, plus a one-click open
- **Spark & catalyst tracking** — crafting/upgrade currency and catalyst charge timer
- **More forge data** — a weekly Voidcore catalyze counter

</details>

---

## Feature requests

<details>
<summary>How to request</summary>

Open an issue on [GitHub](https://github.com/Nelnamara/OmniumObservator/issues) or leave a CurseForge comment — include your spec and what you'd like tracked.

</details>

---

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/omniumobservator) · [GitHub](https://github.com/Nelnamara/OmniumObservator)
