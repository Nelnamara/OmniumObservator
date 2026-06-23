# OmniumObservator — CLAUDE.md

**Omnium Folio companion** for WoW Midnight 12.0.7. Author: Nelnamara.
Embeds draggable panels **inside** the Omnium Folio frame (This Week / **Devouring Watch** /
**Omnium Counsel**), tracks the full Voidstorm economy + live **Void Assaults** (merged from
the retired DevouringWatch addon), shows rarity-colored weekly runes, an interactive
**voiced 3D advisor model** (Decimus + favor-unlocked advisors), a role-based rune advisor
(Folio guide + Method.gg), an **AceConfig** options panel with per-character profiles, and a
standalone glance panel + minimap button.

## Files
- `OmniumObservator.lua` — single-file addon.

## v1.0.4 architecture (panels, Decimus, guide)
- **Three embed panels** + a standalone: `self.dockL` (This week), `self.dockR` (Voidstorm), `self.dockGuide` (Counsel), `self.panel`/`self.frame` (standalone). All built by `CreatePanel(name, strata, titleText, showLogo)` (per-panel `headerH`, pooled line/sep widgets, `RenderLines(panel, lines)`). All embed panels are `MakeDockDraggable` (left-drag, save folio-relative offset in `db.dock*Pos`). `OnFolioShown` anchors/show them; standalone hides while folio open.
- **Builders:** `BuildLeftLines` (weeks+rarity+Nilhammer+reset, collapsible via `db.weeksCollapsed`), `BuildRightLines` (Motes/Nebulous/Voidcores/Voidshard/orbs, real icons via `IconTag(fileID)`), `BuildGuideLines` (role build from `ROLE_BUILDS`), `BuildLines` (standalone = left+right combined).
- **Decimus model:** `UpdateModel()` — `PlayerModel` parented to UIParent, `SetCreature(NPC_DECIMUS=235697)`, left-drag rotate / scroll zoom / **right-drag move** / click→`DecimusClicked` (7 quick clicks = rare-line easter egg). `DecimusSpeak(rare)` shows bubble + `SetAnimation` + `PlaySoundFile(DECIMUS_SOUNDS[..], "Dialog")` (VO FileDataIDs; seeded `327617`). `db.showModel`/`db.decimusVoice`/`db.modelScale`/`db.modelPos`.
- **Appearance:** `ApplyAppearance()` — `db.alpha` is **background-only** opacity (SetBackdropColor alpha, 0–1), text/icons stay opaque; watermark = mascot at low alpha; `db.scale` (standalone); `db.fontSize` (dynamic rowH in RenderLines). Palette border = void purple.
- **Config (v1.0.5 — AceConfig rewrite):** an **AceConfig** options table (`RegisterOptionsTable("OmniumObservator", ...)`, opened via AceConfigDialog and mirrored into Blizzard Settings → AddOns), modelled on CDTL3 — real dropdowns, LSM media pickers, tabbed groups (General / Panels / Appearance / Omnium Advisors / Settings). The DB is now **AceDB** (`OO.dbObj`, profile at `OO.dbObj.profile`), with per-character profiles via **AceDBOptions** and shareable **import/export** (`OO:ExportProfile`/`OO:ImportProfile` = AceSerializer + LibDeflate). This replaced the old hand-rolled `BuildConfig`/`UISpecialFrames` panel. A custom AceGUI widget renders the live rotating 3D advisor model inside the options.

## Key data / APIs
- Weekly quest IDs (one-time **permanent** unlocks, not repeatable): `96410` (w1), `96441` (w2), `96442` (w3), `96443` (w4), `96444` (w5). Progress is inferred: highest completed week + 1 = next available (`IsQuestFlaggedCompleted` is permanent).
- Achievement-driven week rows via `GetAchievementData()` (criteria).
- **Void-Touched Orbs**: rune spell `1279596`. Read live stack count via `C_UnitAuras.GetPlayerAuraBySpellID(1279596).applications` (0–5). ⚠️ Unconfirmed whether `1279596` carries the stacks or is the passive — verify in-game; swap ID if the counter never shows. Updated on a **throttled** `UNIT_AURA` (player) handler.
- Aura spellIds are SECRET; only `GetPlayerAuraBySpellID(knownID)` is safe.

## Slash
- **User-facing (in README):** `/oo` (toggle standalone) · `config`/`options` · `dock` · `build [m+|raid|dot|pvp|casual|method]` (cycle/set Counsel build) · `font <8-20>` · `model` (toggle Decimus) · `voice` (toggle VO) · `lock`/`unlock` · `reset`.
- **Dev/test only (NOT in README):** `debug` (dump folio hook/configID/motes/icons) · `runes` (dump purchased tree nodes → spell IDs, for the slotted-rune readout) · `model <id>` (test a creatureID) · `voice <id>` (test a sound FileDataID + add to rotation) · `questid <id>` (legacy quest override).

## Folio dock (built in v1.0.3)
The dock is implemented: a branded companion panel anchored to the folio frame on open. Architecture in `OmniumObservator.lua`:
- `CreatePanel(name, strata)` builds a branded backdrop panel (purple/gold/black, icon logo) with pooled line/sep widgets + a shared `RenderLines(panel, lines)`. Used by **both** the standalone panel (`self.panel`/`self.frame`) and the dock (`self.dock`).
- `GetFolioFrame()` walks **`ExpansionLandingPage.Overlay.MidnightLandingOverlay.RunesOfPowerFrame`** (guarded). `TryHookFolio()` is called on our `ADDON_LOADED`, on `ADDON_LOADED == "Blizzard_ExpansionLandingPage"` (it's LoadOnDemand), and on `PLAYER_ENTERING_WORLD`. It `HookScript`s the folio's OnShow/OnHide (post-hook, read-only — **never taint the folio frame**). The dock is parented to UIParent and only `SetPoint`-ed to the folio.
- `OnFolioShown()` captures `self.folioConfigID = RunesOfPowerFrame:GetConfigID()` (pcall; live, can change per session), anchors `dock TOPLEFT → folio TOPRIGHT (+8,0)`, shows it, and runs a 5s `OnUpdate` to refresh the reset timer / Mote count while open. **If the dock renders behind the folio, raise the dock strata in `BuildDock` (currently "HIGH").**
- `GetMotes()` → `C_Traits.GetTreeCurrencyInfo(folioConfigID, 1186, false)`, find `traitCurrencyID == 4230` (Motes), `.quantity`. pcall-guarded. `GetResetSeconds()` → `C_DateAndTime.GetSecondsUntilWeeklyReset()`.
- `BuildLines()` is the single shared content builder (Motes / orbs / reset / week progress / current step); `Refresh()` renders it into whichever panels are shown.

### Confirmed in-game data (keep)
- Folio frame is a **Traits tree** (built on `Blizzard_SharedTalentUI`); runes readable via **`C_Traits`**. Motes are the **trait-tree currency**, not a `C_CurrencyInfo` currency.
- `treeID` = **`1186`**; Motes `traitCurrencyID` = **`4230`** (`{ quantity, spent, maxQuantity }`).
- **Rune spell IDs:** Unleashed Fire `1279599`, Void-Touched Orbs `1279596`, Void-Tainted Shell `1279604`, Self-Mending `1279603`, Lynxlike Reflexes `1279605`, Lingering `1287555`, Overload `1279614`, Residual Energy `1279615`, Echoes `1279616`.
- **Orb counter:** `C_UnitAuras.GetPlayerAuraBySpellID(1279596).applications` = live 0–5 (not secret; pcall-guarded anyway).

### Voidforge economy IDs (wired in v1.0.4 embed)
- Nebulous Voidcore = currency `3418` (`GetCurrency`). Ascendant Voidcore = ITEM `268552`, Ascendant Voidshard = ITEM `268650` (`GetItem` → `C_Item.GetItemCount(id,true,false,true,true)`). Feeding the Nilhammer = weekly quest `95269` (`IsQuestFlaggedCompleted`). The Ascendant Nilhammer = `95271`. Full list in the [[ref-midnight-ids]] memory.

### Next (roadmap)
Nilhammer weekly *progress* (currently just done/not — the "3/3" needs the quest in log or an objective read); slotted-rune readout via `C_Traits` node/entry info; optionally open the folio from the minimap button if a non-protected path exists.

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\OmniumObservator\`.
- **1.0.4** (released, tag `v1.0.4`): in-folio embed (3 panels), Voidforge economy, voiced/movable Decimus model, role-based rune Counsel, rarity weeks, options panel, collapsible weeks, font/opacity controls.
- Current version: **1.0.5** (Interface 120007), **released**. Major release, four headline systems:
  1. **DevouringWatch merged in** — the old "Voidstorm" panel is now **Devouring Watch**, carrying a live Void Assault POI scan (`C_AreaPoiInfo.GetEventsForMap`), the Eversong/Zul'Aman weekly assault quests, and Field Accolade / Voidlight Marl currencies, on top of the economy readout. The **standalone DevouringWatch addon is retired** — all of it lives here now.
  2. **AceConfig / AceDB rewrite** (see Config above) — real options UI, per-character profiles, import/export. Replaced the hand-rolled panel.
  3. **Void Favor & advisors** — a favor counter grows with folio engagement (open folio/click model daily; bigger one-time boosts for new weeks, forging the Ascendant Nilhammer, and the *Omnium Folio Studies* achievement) and unlocks alternate summonable advisor models: Decimus (default), **Terminas** `235767` (favor 8), **Riko** `229749` (favor 18), eventually "You" — each with real VO. **Xal'atath** randomly hijacks the model frame to mock you, and at 5/5 weeks nudges panels out of place (a *Reset all panel positions* fixes it).
  4. **Nilhammer forge bar** + themed-art **texture pickers** (frame/forge/divider/banner `*.tga`; `/oo frame|banner <1-5>`). Nilhammer quests: feed `95269` (repeatable, no lasting flag), Ascendant `95271` (permanent flag once forged).

### Themed-art picker architecture (v1.0.5)
- `OO:FrameTexPath/ForgeTexPath/DividerTexPath()` map `db.frameTex/forgeTex/dividerTex` (1..5) → `Media\<name><N>.tga`. `MEDIA` local constant near `ApplySkinGeometry`.
- Panel skin (`CreatePanel`) `SetTexture(OO:FrameTexPath())`; `ApplyAppearance` re-applies texture + `ApplySkinGeometry` on every refresh so dropdowns swap live. `db.frameSkin ~= false` (default on).
- Forge bar: `BuildForgeBar`/`UpdateForgeBar` (mirrors gem bar), bottom-anchored on `self.panel` + `dockL`, fill from `GetNilhammerState()` (done flag, or live quest-objective fraction if in log). `RenderLines` reserves bottom space for gem + forge bars.
- Dividers: `StyleSeps(panel)` textures the pooled `sepPool` with `DividerTexPath()` (or the plain rule if `db.dividerArt == false`); called in `CreatePanel` + `ApplyAppearance`.
- Config: `layout().selector(label, count, cur, onChange)` = taint-free `< N / count >` cycler (not UIDropDownMenu). Theme tab holds all art toggles + the 3 selectors.

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
