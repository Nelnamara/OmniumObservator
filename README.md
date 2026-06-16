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
- **Weekly quest tracking** — once you set your weekly quest ID, shows whether Seeking Knowledge is done this week
- **Compact panel** — auto-resizes to content, draggable and lockable

## Setup

On patch launch day, run the following in-game to find your weekly quest ID:

```
/run print(C_QuestLog.GetQuestIDByName("Seeking Knowledge"))
```

Then register it with OmniumObservator:

```
/oo questid <the number it printed>
```

This is a one-time setup — the ID is saved across sessions.

## Slash Commands

| Command | Effect |
|---|---|
| `/oo` | Toggle panel visibility |
| `/oo questid <id>` | Set the weekly quest ID for tracking |
| `/oo debug` | Print achievement criteria and quest status to chat |
| `/oo lock` / `/oo unlock` | Lock or unlock frame position |
| `/oo reset` | Reset to default position |

## Compatibility

- WoW Midnight 12.0.7+
- No library dependencies
- Uses `GetAchievementCriteriaInfo`, `C_QuestLog.IsQuestFlaggedCompleted` — both accessible in Midnight

## Author

Nelnamara — [CurseForge](https://www.curseforge.com/wow/addons/omniumobservator) · [GitHub](https://github.com/Nelnamara/OmniumObservator)
