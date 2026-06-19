# OmniumObservator

Omnium Folio power system tracker for World of Warcraft: Midnight 12.0.7+.

OmniumObservator keeps track of your Omnium Folio progress — the new 5-tier weekly power system introduced in patch 12.0.7. It shows which of the five rune rows you've unlocked, tracks the Seeking Knowledge weekly quest, and displays your overall Omnium Folio Studies achievement completion.

## Features

- **Weekly unlock tracker** — shows all 5 Omnium Folio tiers with checkmarks as you complete each week:
  - The Sunstrider Omnium
  - Leyline Assaults
  - Off-World Magic
  - Ritualized Arcana
  - Magical Primessence
- **Achievement display** — live status of the Omnium Folio Studies meta-achievement (ID 63325) and its 5 sub-criteria
- **Weekly quest tracking** — auto-detects the current "Seeking Knowledge" week and shows whether it's done; no manual setup
- **Void-Touched Orbs counter** — live 0–5 orb stack readout (the Omnium Folio core rune resource)
- **Compact panel** — auto-resizes to content, draggable and lockable
- **Minimap button** — quick toggle from the minimap, with a matching AddOns-list icon

## Setup

None required. OmniumObservator auto-detects which of the five "Seeking Knowledge" weeks is current — the weeks are permanent one-time unlocks, so it infers your progress from completed quests. Just log in and `/oo`.

> The legacy `/oo questid <id>` command remains as a manual override if you ever need to pin a specific quest ID.

## Slash Commands

| Command | Effect |
|---|---|
| `/oo` | Toggle panel visibility |
| `/oo questid <id>` | Legacy override — manually pin the weekly quest ID (auto-detected by default) |
| `/oo debug` | Print achievement criteria and quest status to chat |
| `/oo lock` / `/oo unlock` | Lock or unlock frame position |
| `/oo reset` | Reset to default position |

## Compatibility

- WoW Midnight 12.0.7+
- No library dependencies
- Uses `GetAchievementCriteriaInfo`, `C_QuestLog.IsQuestFlaggedCompleted` — both accessible in Midnight

## Changelog

### v1.0.3 (in testing)
- **Omnium Folio dock** — a companion panel that anchors to the in-game Omnium Folio frame when you open it, showing Motes, Void-Touched Orbs, the weekly reset countdown, and week progress. Toggle with `/oo dock`
- **Motes of Omnial Inquiry** — live count read from the folio trait tree (`C_Traits`, tree 1186 / currency 4230)
- **Weekly reset timer** in both the dock and the standalone panel
- **Suite branding + restyle** — purple/gold/black palette, gold border, and the addon icon as a header logo
- **Week-progress visuals** — green-check icons for unlocked weeks, dim bullets for pending
- Hardened the orb counter against a secret `applications` value (pcall guard)

### v1.0.2
- Live Void-Touched Orbs counter (Omnium Folio rune `1279596`), read via `GetPlayerAuraBySpellID` on a throttled `UNIT_AURA` and hardened against a secret `applications` value
- Minimap button and AddOns-list icon (addon artwork, standard 24px)

### v1.0.1
- Auto-detect the current "Seeking Knowledge" week — no manual `/oo questid` needed
- Interface bumped to 120007

### v1.0.0
- Initial release: weekly unlock tracker, achievement display, weekly quest tracking

## Roadmap

Phase 1 — the dock + Motes + weekly reset timer — landed in v1.0.3. Still to come:

- [ ] **Decimus Voidstorm dashboard** — surface the broader weekly economy in the dock: bonus rolls (Voidforge / Nebulous Voidcores) for raid/Delves/M+, and the Ascendant Nilhammer ("Voidhammer") weapon/trinket upgrade track
- [ ] **Slotted-rune readout** — show which runes are active via `C_Traits` node/entry info
- [ ] **Open the folio from the minimap button** — if a safe (non-protected) path exists

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/omniumobservator) · [GitHub](https://github.com/Nelnamara/OmniumObservator)
