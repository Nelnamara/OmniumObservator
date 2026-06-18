# OmniumObservator — CLAUDE.md

**Omnium Folio tracker** for WoW Midnight 12.0.7. Author: Nelnamara.
Shows weekly unlock progress (weeks 1–5), the auto-detected current "Seeking
Knowledge" weekly quest, a live Void-Touched Orbs counter, and a minimap button.

## Files
- `OmniumObservator.lua` — single-file addon.

## Key data / APIs
- Weekly quest IDs (one-time **permanent** unlocks, not repeatable): `96410` (w1), `96441` (w2), `96442` (w3), `96443` (w4), `96444` (w5). Progress is inferred: highest completed week + 1 = next available (`IsQuestFlaggedCompleted` is permanent).
- Achievement-driven week rows via `GetAchievementData()` (criteria).
- **Void-Touched Orbs**: rune spell `1279596`. Read live stack count via `C_UnitAuras.GetPlayerAuraBySpellID(1279596).applications` (0–5). ⚠️ Unconfirmed whether `1279596` carries the stacks or is the passive — verify in-game; swap ID if the counter never shows. Updated on a **throttled** `UNIT_AURA` (player) handler.
- Aura spellIds are SECRET; only `GetPlayerAuraBySpellID(knownID)` is safe.

## Slash
`/oo` (toggle) · `debug` (dump state) · `questid` (legacy override) · `lock`/`unlock` · `reset`

## Roadmap (in design) — dock to the Omnium Folio frame
Pivot OO from a standalone panel into a companion docked to the folio (single point of info, no extra clutter). Findings from `/fstack`:
- Folio frame = **`ExpansionLandingPage.Overlay.MidnightLandingOverlay.RunesOfPowerFrame`**, built on `Blizzard_SharedTalentUI` (AutoCommitTraitFrame) — **it is a Traits tree**. Opens from the minimap's Midnight expansion-landing button; lives in the LoadOnDemand `Blizzard_ExpansionLandingPage` (hook after that addon loads).
- Runes (slotted / empowered) are therefore readable via **`C_Traits`**.
- **Motes of Omnial Inquiry are the trait-tree currency** (`C_Traits.GetTreeCurrencyInfo`), NOT a `C_CurrencyInfo` currency — that's why they don't show in the currency tab.
- **Phase 1:** hook `RunesOfPowerFrame`'s OnShow, anchor a non-secure dock showing: weekly Seeking Knowledge line + next step, Mote count, weekly reset timer (`C_DateAndTime.GetSecondsUntilWeeklyReset`), week progress, and the live orb counter. Minimap button opens the folio. Refresh out of combat / on events; never taint the folio frame.
- **Need (in-game):** folio `configID`/`treeID` — with the folio open: `/dump ExpansionLandingPage.Overlay.MidnightLandingOverlay.RunesOfPowerFrame:GetConfigID()` then `C_Traits.GetConfigInfo(<id>)`.

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\OmniumObservator\`.
- Current version: **1.0.2** (Interface 120007).

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
