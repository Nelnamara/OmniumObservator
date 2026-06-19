# OmniumObservator — CLAUDE.md

**Omnium Folio tracker** for WoW Midnight 12.0.7. Author: Nelnamara.
Shows weekly unlock progress (weeks 1–5), the auto-detected current "Seeking
Knowledge" weekly quest, a live Void-Touched Orbs counter, Motes + weekly reset
timer, a minimap button, and (v1.0.3) a companion panel that docks to the in-game
Omnium Folio frame.

## Files
- `OmniumObservator.lua` — single-file addon.

## Key data / APIs
- Weekly quest IDs (one-time **permanent** unlocks, not repeatable): `96410` (w1), `96441` (w2), `96442` (w3), `96443` (w4), `96444` (w5). Progress is inferred: highest completed week + 1 = next available (`IsQuestFlaggedCompleted` is permanent).
- Achievement-driven week rows via `GetAchievementData()` (criteria).
- **Void-Touched Orbs**: rune spell `1279596`. Read live stack count via `C_UnitAuras.GetPlayerAuraBySpellID(1279596).applications` (0–5). ⚠️ Unconfirmed whether `1279596` carries the stacks or is the passive — verify in-game; swap ID if the counter never shows. Updated on a **throttled** `UNIT_AURA` (player) handler.
- Aura spellIds are SECRET; only `GetPlayerAuraBySpellID(knownID)` is safe.

## Slash
`/oo` (toggle standalone panel) · `dock` (toggle folio dock) · `debug` (dump state incl. folio hook/configID/motes) · `questid` (legacy override) · `lock`/`unlock` · `reset`

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

### Next (roadmap)
Decimus Voidstorm dashboard (bonus rolls: Voidforge/Nebulous Voidcores; Ascendant Nilhammer "Voidhammer" upgrades); slotted-rune readout via `C_Traits` node/entry info; optionally open the folio from the minimap button if a non-protected path exists.

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\OmniumObservator\`.
- Current version: **1.0.3** (Interface 120007) — released to CurseForge (tag `v1.0.3`). Dock verified in-game: folio path resolves, hooked, configID `55669420`, Motes display, dock renders beside the folio.

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
