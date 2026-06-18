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

## Roadmap (in design)
Integrate with Blizzard's **Omnium Folio frame** (opens from a minimap icon) — surface our tracked info (weekly quest, next step, Motes of Omnial Inquiry currency, orb count, rune build) as a single point inside/next to that frame instead of a separate panel. Need the folio frame's name/API (grab in-game via `/dump`/`/api` or `/fstack`).

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\OmniumObservator\`.
- Current version: **1.0.2** (Interface 120007).

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
