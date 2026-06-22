-- OmniumObservator
-- Omnium Folio power system tracker for WoW Midnight 12.0.7+
-- Author: Nelnamara
--
-- Tracks weekly progress through the Omnium Folio achievement chain (63325),
-- auto-detects the current "Seeking Knowledge" weekly quest, shows the live
-- Void-Touched Orb count, and (v1.0.3) docks a companion panel to the in-game
-- Omnium Folio frame showing Motes, orbs, the weekly reset timer, and week
-- progress. Standalone panel remains available via /oo or the minimap button.

OmniumObservator = {}
local OO = OmniumObservator

OO.version = "1.0.5"

-- Achievement IDs (confirmed from 12.0.7 PTR datamine)
local ACH_OMNIUM_FOLIO   = 63325

-- Five-week questline — one quest per weekly reset, permanent unlock (not repeatable).
-- Quest IDs confirmed from Wowhead live database (June 2026).
local WEEKLY_QUESTS = {
    { id = 96410, week = 1, name = "The Omnium Folio"   },
    { id = 96441, week = 2, name = "Leyline Assaults"   },
    { id = 96442, week = 3, name = "Off-World Magic"    },
    { id = 96443, week = 4, name = "Ritualized Arcana"  },
    { id = 96444, week = 5, name = "Magical Primessence" },
}

-- Fallback sub-achievement names in display order (week 1 → 5)
local WEEK_NAMES = {
    "The Sunstrider Omnium",
    "Leyline Assaults",
    "Off-World Magic",
    "Ritualized Arcana",
    "Magical Primessence",
}

-- Omnium Folio frame (Traits tree) — confirmed in-game:
--   ExpansionLandingPage.Overlay.MidnightLandingOverlay.RunesOfPowerFrame
-- treeID 1186, Motes of Omnial Inquiry = trait currency 4230 (NOT a C_CurrencyInfo currency).
local FOLIO_TREE_ID    = 1186
local MOTES_CURRENCY   = 4230
local NEBULOUS_VOIDCORE = 3418    -- bonus-roll currency (confirmed in-game via /oo scan)
local ITEM_ASCENDANT_VOIDCORE  = 268552  -- gear-upgrade item
local ITEM_ASCENDANT_VOIDSHARD = 268650  -- collected, forged into a Voidcore
local QUEST_FEEDING_NILHAMMER  = 95269   -- repeatable catalyze step (does NOT set a lasting flag)
local QUEST_ASCENDANT_NILHAMMER = 95271  -- permanent flag once the Ascendant Nilhammer is forged
local CUR_VOIDFORGE_UNLOCK  = 3409       -- [DNT] Voidforge unlock turn-in tracker (/6)
local CUR_NILHAMMER_UPGRADE = 3419       -- [DNT] Voidforge upgrade = Ascendant Nilhammer (/4)
-- DevouringWatch merge: Void Assault world content (POI events, weekly assault, currencies)
local CURRENCY_FIELD_ACCOLADE = 3405
local CURRENCY_VOIDLIGHT_MARL = 3316
local VA_INTRO_QUEST = 96080
local VA_WEEKLY_QUESTS = { { id = 94385, zone = "Eversong Woods" }, { id = 94386, zone = "Zul'Aman" } }
local NPC_DECIMUS              = 235697   -- Domanaar Decimus (for the 3D model)
local NPC_TERMINAS            = 235767   -- "Lord" Terminas (Decimus's rival)
-- Easter egg: extra models unlocked after enough Decimus interactions OR the
-- Omnium Folio Studies achievement. Cycle with /oo model next. Extensible.
-- Decimus's bonus model roster (easter egg). Each unlocks at a favor threshold;
-- name is colored by WoW rarity. Xal'atath is the special random "mock" appearance.
local RARITY_COLOR = { legendary = "FFFF8000", epic = "FFA335EE", rare = "FF0070DD", uncommon = "FF1EFF00", artifact = "FFE6CC80" }
local MODELS = {
    { name = "Decimus",  id = NPC_DECIMUS,  rarity = "uncommon",  unlock = 0  },
    { name = "Terminas", id = NPC_TERMINAS, rarity = "rare",      unlock = 8  },
    { name = "Riko",     id = 229749,       rarity = "legendary", unlock = 18 },
    { name = "You",      player = true,     rarity = "legendary", unlock = 30 },
}
local XALATATH_ID = 242457
-- Xal'atath's real voice lines (FileDataID + whisper transcript) so the bubble matches the
-- audio. VO_815_Xalatath_Blade_of_the_Black_Empire (greetings + farewells).
local XAL_VO = {
    { id = 2530796, text = "What do you seek?" },
    { id = 2530797, text = "So many possibilities." },
    { id = 2530798, text = "Tell me what you want." },
    { id = 2530793, text = "Such magnificence awaits us." },
    { id = 2530794, text = "Open your mind to the whispers." },
    { id = 2530795, text = "The time comes soon." },
}
local XAL_PORTAL = 6986382   -- her portal-in cast SFX (plays as she arrives, before the voice line)

-- Suite branding palette (void purple / gold accents / black)
local PALETTE = {
    bg     = { 0.04, 0.02, 0.07, 0.92 },  -- near-black with a faint purple cast
    border = { 0.64, 0.21, 0.93, 0.95 },  -- void purple (epic-rarity hue)
    divider= { 0.55, 0.30, 0.90, 0.55 },  -- purple divider
    title  = "FFFFD200",                   -- gold (title text colour code)
    gold   = "FFFFD700",
    purple = "FFC58CFF",
    dim    = "FF8A8A8A",
}

-- The 5 weeks light up in WoW loot-rarity colours as they're unlocked:
-- common(white) → uncommon(green) → rare(blue) → epic(purple) → legendary(orange).
local WEEK_COLORS = { "FFFFFFFF", "FF1EFF00", "FF0070DD", "FFA335EE", "FFFF8000" }
local WEEK_DIM    = "FF555555"

-- Decimus's in-game lines (verbatim from Wowhead) — he speaks one on folio open
-- and when clicked. The rare set is reserved for the easter egg.
local DECIMUS_QUOTES = {
    "I am a creature of passion.",
    "The cosmos is a feast, lightling. Why not enjoy it?",
    "I need no master. We should all obey our own appetites.",
    "Come, <name>. I have so much to show you.",
    "Watching your struggles blaze bright against an uncaring cosmos -- it's delicious.",
    "Make yourself at home. Then we can discuss weakening the storm.",
    "Borrow my pet's sight. I'll tell you how to weaken the storm.",
    "She would leave nothing but an empty abyss. Can you imagine anything more dull?",
    "The key to weakening the storm is the Mantle of Predation.",
}
local DECIMUS_RARE = {
    "Xal'atath would devour your world. All worlds. Even the stars.",
    "Steal the Mantle of Predation, enter a Nexus-Point, and weaken the storm. Terminas will be humiliated.",
}

-- Decimus voice-over FileDataIDs (the "Copy ID" value on Wowhead's Sounds tab,
-- NOT the sound=NNNNN entry id). Pattern VO_120_Decimus_NN_M; line NN noted below.
-- Add more from the Sounds tab as transcribed. /oo voice <id> appends one live.
local DECIMUS_SOUNDS = {
    7248472,  -- VO_120_Decimus_22_M
    7303103,  -- VO_120_Decimus_61_M
    7303106,  -- VO_120_Decimus_62_M
    7325673,  -- VO_120_Decimus_64_M
    7325674,  -- VO_120_Decimus_65_M
    7325675,  -- VO_120_Decimus_66_M
    7325676,  -- VO_120_Decimus_67_M
    7325677,  -- VO_120_Decimus_68_M
    7329680,  -- VO_120_Decimus_69_M
}

-- Paired VO lines: FileDataID + its transcript, so the speech bubble shows the line
-- he actually speaks (used for normal greetings when voice is on). yell = red text.
local DECIMUS_VO = {
    { id = 7248472, text = "Just the Azerothian I've been looking for..." },     -- 22
    { id = 7303103, text = "And... if you come across anything interesting..." }, -- 61
    { id = 7303106, text = "Always a pleasure." },                                -- 62
    { id = 7325673, text = "Be careful not to have too much fun without me..." }, -- 64
    { id = 7325674, text = "I'll be waiting for our next meeting..." },           -- 65
    { id = 7325675, text = "Oh, what pleasure will you bring me today?" },        -- 66
    { id = 7325676, text = "Oh, and it's you again..." },                         -- 67
    { id = 7325677, text = "Well, if it isn't my favorite little monster..." },   -- 68
    { id = 7329680, text = "WHY DO YOU CONTINUE TO DO SO MUCH NEEDLESS CHATTERING?!", yell = true }, -- 69
}

-- Per-advisor voice for the favor-unlocked roster. Decimus keeps his richer paired tables
-- above; these cover the rest. Riko has real VO (greet/farewell/pissed); Terminas and "You"
-- are silent by design — text-only bubbles (the player taglines are deliberately generic to
-- Midnight events/raids, no race or class). bubble text is placeholder until transcribed.
local ADVISOR_VO = {
    Riko = {   -- real VO + whisper transcripts (light cleanup; a few hozen-isms may read off — correct from audio)
        greet = {
            { id = 636054, text = "Riko never grew up wikkit. Well... almost never." },
            { id = 636056, text = "Riko can speak like wikkit! Some Hozen call Riko a traitor." },
            { id = 636058, text = "We gotta watch out for Jinyu! Jinyu hit back!" },
            { id = 636060, text = "Riko is lover and fighter and dooker." },
            { id = 636062, text = "Riko feel happy that Wikkit is here." },
        },
        bye = {
            { id = 636046, text = "That was good talk. Riko feel better now." },
            { id = 636048, text = "Next time, bring Slickies to Riko." },
            { id = 636050, text = "Grookin'! Ookin'! Dookin'! Aww yeah!" },
            { id = 636052, text = "It's okay. Riko gotta make dook anyways." },
        },
        mad = { { id = 636064, text = "Alas, must true love ever remain out of Riko's reach?" } },
    },
    Terminas = {
        silent = true,
        lines = {
            "*Terminas watches you with ancient, patient eyes.*",
            "*A low rumble — Terminas approves.*",
            "*Terminas tilts its head, considering you.*",
        },
    },
    You = {
        silent = true,
        lines = {
            "These runes will NOT unlock themselves, off with you.",
            "Another reset, another shot at the Great Vault.",
            "Void Assaults won't clear themselves, <name>.",
            { text = "Xal'atath is not resting. Get back out there and let's make it count!", yell = true },
            "Runes slotted. Time to raid.",
            "The Devouring host stirs — good thing we're ready.",
        },
    },
}

-- Omnium Folio rune spell IDs (for real icons in the Counsel panel).
local RUNE_IDS = {
    orbs = 1279596, fire = 1279599, shell = 1279604, mend = 1279603, lynx = 1279605,
    lingering = 1287555, overload = 1279614, residual = 1279615, echoes = 1279616,
}

-- Role-based recommended builds (5 rows: Core / Defensive / Lingering / Stat / Capstone),
-- from two sources. Folio-guide builds open with Void-Touched Orbs (safe core); Method.gg
-- (raiding/DPS authority) leans Unleashed Fire as the core. Cycle with [>] or /oo build.
local ROLE_BUILDS = {
    { role = "M+ |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Overload", RUNE_IDS.overload },
    } },
    { role = "Raid ST |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Echoes", RUNE_IDS.echoes },
    } },
    { role = "Raid DoT |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Residual Energy", RUNE_IDS.residual },
    } },
    { role = "PvP |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Defensive", "Lynxlike Reflexes", RUNE_IDS.lynx },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "Versatility", nil },
        { "Capstone", "Overload", RUNE_IDS.overload },
    } },
    { role = "Casual |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Defensive", "Self-Mending", RUNE_IDS.mend },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "Versatility", nil },
        { "Capstone", "Overload", RUNE_IDS.overload },
    } },
    { role = "DPS |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Overload", RUNE_IDS.overload },
    } },
    { role = "M+ |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Echoes", RUNE_IDS.echoes },
    } },
    { role = "Raid DoT |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Defensive", "Void-Tainted Shell", RUNE_IDS.shell },
        { "Lingering", "fixed (no choice)", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Capstone", "Residual Energy", RUNE_IDS.residual },
    } },
}

local CHECK_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local function Check(done)
    if done then return CHECK_DONE end
    return "|c" .. PALETTE.dim .. "\226\128\162|r"  -- dim bullet (•) for pending weeks
end

local function FmtDur(sec)
    if not sec or sec <= 0 then return "now" end
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- WoW rarity-coloured hex by progress fraction (green → blue → purple → orange).
local function RarityFracColor(f)
    f = f or 0
    if f >= 0.9 then return "FFFF8000"       -- legendary orange
    elseif f >= 0.6 then return "FFA335EE"   -- epic purple
    elseif f >= 0.33 then return "FF0070DD"  -- rare blue
    else return "FF1EFF00" end               -- uncommon green
end

local DEFAULTS = {   -- fit/appearance values baked from the dialed-in profile (2026-06-21)
    x            =  400,
    y            =  200,
    scale        = 0.9,
    locked       = false,
    alpha        = 1.0,
    weeklyQuestID = nil,
    minimapAngle = 225,
    minimapHide  = false,
    dockEnabled  = true,
    -- Themed art selections (texture-picker menus, like CDTL3).
    frameSkin    = true,
    frameTex     = 2,      -- border1..5.tga
    bannerTex    = 5,      -- banner1..5.tga
    bannerW      = 1.5,    -- banner width as a fraction of the panel
    bannerX      = 0,
    bannerY      = 12,     -- banner overhang above the frame top
    forgeTex     = 4,      -- forge holder 1..10 (default = a green-window holder so the fill shows)
    dividerTex   = 3,      -- divider1..5.tga
    forgeBar     = true,
    dividerArt   = true,
    frameAlpha   = 1.0,
    gemSize      = 40,
    gemGlow      = 0.65,
    logoSize     = 110,    -- header mascot emblem size
    watermarkScale = 0.62,
    watermarkAlpha = 0.32,
    showMascot     = false,
    mascotUndocked = true,
    skinMargin   = 80,     -- 9-slice corner size
    skinOutset   = 26,
    skinOffsetX  = 2,
    skinOffsetY  = 1,
    titleColor   = { 1, 1, 1 },
    fontSize     = 14,
    bannerH      = 70,
    mainWidth = 288, dockLWidth = 252, dockRWidth = 300, dockGuideWidth = 300,
    mainAlpha = 0.9, mainFrameSkin = true, mainFrameTex = 1, mainFrameAlpha = 1.0,   -- standalone's own opacity + frame (separate from docks)
    mainHeight = 0, dockLHeight = 275, dockRHeight = 0, dockGuideHeight = 180,   -- 0 = auto-fit to content
    bgInsetL = -6, bgInsetR = 9, bgInsetT = 12, bgInsetB = 19,   -- per-edge background fill reach (under the ornate frame)
    textX        = -5,     -- horizontal nudge for the content text + dividers
    dividerH     = 18,     -- divider art thickness
    dividerY     = 13,     -- vertical nudge for dividers (separate from text)
    dividerX     = -13,    -- horizontal nudge for dividers (relative to the text)
    forgeInset   = 80,     -- forge fill horizontal inset (mask the meter to the holder art)
    forgeFillH   = 15,     -- forge fill height
    forgeFillY   = 0,      -- forge fill vertical offset
    forgeGlow    = 1.0,    -- pulsing glow on the forge fill (0 = off)
    forgeScale   = 1.0,    -- overall size of the Nilhammer forge bar
    forgeFillColor = { 0.443, 0, 0.82 },   -- void-purple forge fill
    forgeFillTex = "Blizzard",             -- LSM statusbar for the forge fill
    -- explicit so the AceConfig toggles read their real state
    showMotes = true, showRolls = true, showVoidcores = true, showVoidshard = true,
    showAssaults = true, showNilhammer = true, showReset = true,
    gemBar = true, watermark = true, headerBanner = false, decimusVoice = true,
    showGuide = true, weeksCollapsed = false, showModel = true, modelLocked = false,
    modelScale = 1.1, modelChoice = 1,
}

-- Week unlock state is driven by the permanent quest-completion flags. The
-- achievement 63325's criteria are NOT the five weekly unlocks (its first
-- criterion is "Mote of Omnial Inquiry"), so we don't use them for the rows.
function OO:GetWeeks()
    local steps, unlocked = {}, 0
    for i, q in ipairs(WEEKLY_QUESTS) do
        local done = C_QuestLog.IsQuestFlaggedCompleted(q.id) and true or false
        steps[i] = { name = q.name, done = done }
        if done then unlocked = unlocked + 1 end
    end
    return { steps = steps, unlocked = unlocked, allDone = (unlocked >= 5) }
end

-- Auto-detects which of the 5 Seeking Knowledge weeks is current without any
-- manual /oo questid input. Weeks are permanent one-time unlocks, so completed
-- quests stay flagged forever and we can infer progress from that.
function OO:GetWeeklyState()
    -- First: is any weekly actively in the quest log right now?
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            for _, q in ipairs(WEEKLY_QUESTS) do
                if info.questID == q.id then
                    return { week = q.week, name = q.name, inLog = true, done = false }
                end
            end
        end
    end

    -- No active quest — determine progress from permanent completion flags
    local highestDone = 0
    for _, q in ipairs(WEEKLY_QUESTS) do
        if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
            if q.week > highestDone then highestDone = q.week end
        end
    end

    if highestDone >= 5 then
        return { week = 5, name = "Magical Primessence", done = true, allDone = true }
    elseif highestDone > 0 then
        local nextQ = WEEKLY_QUESTS[highestDone + 1]
        return { week = nextQ.week, name = nextQ.name, done = false, inLog = false, nextReset = true }
    else
        return { week = 1, name = "The Omnium Folio", done = false, inLog = false, nextReset = false }
    end
end

-- Motes of Omnial Inquiry — the folio Traits-tree currency. Needs the folio
-- frame's live configID (captured when the folio is opened). pcall-guarded; the
-- C_Traits values can be secret/unavailable depending on context.
function OO:GetMotes()
    if not (C_Traits and self.folioConfigID) then return nil end
    local q
    pcall(function()
        local info = C_Traits.GetTreeCurrencyInfo(self.folioConfigID, FOLIO_TREE_ID, false)
        if type(info) == "table" then
            for _, c in ipairs(info) do
                if c.traitCurrencyID == MOTES_CURRENCY then q = c.quantity end
            end
            if q == nil and info[1] then q = info[1].quantity end
        end
    end)
    return q
end

function OO:GetResetSeconds()
    if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then return nil end
    local s
    pcall(function() s = C_DateAndTime.GetSecondsUntilWeeklyReset() end)
    return s
end

-- Currency quantity + weekly cap by ID (pcall-guarded). Used for Nebulous Voidcore.
function OO:GetCurrency(id)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local q, m
    pcall(function()
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if info then q = info.quantity; m = info.maxQuantity end
    end)
    return q, m
end

-- Item count across bags + bank + reagent bank + warband bank (pcall-guarded).
-- Used for Ascendant Voidcores / Voidshard (they're items, not currencies).
function OO:GetItem(id)
    local n
    pcall(function()
        if C_Item and C_Item.GetItemCount then
            n = C_Item.GetItemCount(id, true, false, true, true)
        elseif GetItemCount then
            n = GetItemCount(id, true)
        end
    end)
    return n
end

-- Inline texture escape for a fileID (real game icon in a font string). The
-- :64:64 crop trims the default icon border so the art reads clearly at size.
local function IconTag(fid, sz)
    if not fid then return "" end
    sz = sz or 18
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", tostring(fid), sz, sz)
end

function OO:CurrencyIcon(id)
    local fid
    pcall(function()
        local i = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
        if i then fid = i.iconFileID end
    end)
    return fid
end

function OO:ItemIcon(id)
    local fid
    pcall(function()
        if C_Item and C_Item.GetItemIconByID then fid = C_Item.GetItemIconByID(id)
        elseif GetItemIcon then fid = GetItemIcon(id) end
    end)
    return fid
end

function OO:SpellIcon(id)
    local fid
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then fid = C_Spell.GetSpellTexture(id) end
    end)
    return fid
end

local ROW_H   = 18
local FRAME_W = 300
local TITLE_H = 22
local PAD     = 6
local LINE_INSET = 22   -- content left/right inset so the ornate border never clips the text

-- Builds a backdrop panel (branded) with a header (optional logo) + title, a
-- divider, and pooled line/separator widgets. Returns { frame, linePool, sepPool }.
-- Shared by the standalone panel and the two embedded folio panels.
-- Themed-art path helpers. Each picker stores a 1..5 index in the db and we map
-- it to Media\<name><N>.tga so the dropdowns can swap textures live.
local MEDIA = "Interface\\AddOns\\OmniumObservator\\Media\\"
function OO:FrameTexPath(tex) return MEDIA .. "border"  .. (tex or (self.db and self.db.frameTex) or 1) .. ".tga" end
function OO:ForgeTexPath()   return MEDIA .. "forge"   .. (self.db and self.db.forgeTex   or 1) .. ".tga" end
function OO:DividerTexPath() return MEDIA .. "divider" .. (self.db and self.db.dividerTex or 1) .. ".tga" end
function OO:BannerTexPath()  return MEDIA .. "banner"  .. (self.db and self.db.bannerTex  or 1) .. ".tga" end

-- Position + 9-slice the void-skin texture on a panel. Pulled out so /oo border
-- can re-tune margin/outset live. Outset makes the frame's window line up with
-- the panel's content area; 9-slice keeps the corners crisp at any size.
function OO:ApplySkinGeometry(frame, skin)
    local m = (self.db and self.db.skinMargin) or 48
    local o = (self.db and self.db.skinOutset) or 14
    local ox = (self.db and self.db.skinOffsetX) or 0
    local oy = (self.db and self.db.skinOffsetY) or 0
    skin:ClearAllPoints()
    skin:SetPoint("TOPLEFT", frame, "TOPLEFT", -o + ox, o + oy)
    skin:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o + ox, -o + oy)
    pcall(function()
        if skin.SetTextureSliceMargins then
            skin:SetTextureSliceMargins(m, m, m, m)
            if Enum and Enum.UITextureSliceMode then
                skin:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
            end
        end
    end)
end

-- Per-panel custom sizing. Each panel maps to its own width/height db keys: width
-- reflows the content, height acts as a minimum (0 = auto-fit to the content).
local PANEL_SIZE_KEYS = {
    OOMainFrame = { w = "mainWidth",      h = "mainHeight" },
    OODockLeft  = { w = "dockLWidth",     h = "dockLHeight" },
    OODockRight = { w = "dockRWidth",     h = "dockRHeight" },
    OODockGuide = { w = "dockGuideWidth", h = "dockGuideHeight" },
}
function OO:PanelW(frame)
    local k = frame and frame.sizeKey
    return (k and self.db and self.db[k.w]) or FRAME_W
end
function OO:PanelMinH(frame)
    local k = frame and frame.sizeKey
    return (k and self.db and self.db[k.h]) or 0
end

function OO:CreatePanel(name, strata, titleText, showLogo)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f.sizeKey = PANEL_SIZE_KEYS[name]
    local pw = (OO.db and f.sizeKey and OO.db[f.sizeKey.w]) or FRAME_W
    f.panelW = pw
    local headerH = 40   -- shorter: the banner now overhangs ABOVE the frame, so content starts high
    f:SetSize(pw, headerH + ROW_H * 9 + PAD * 2)
    f:SetFrameStrata(strata or "MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    -- Old backdrop kept (template gives us SetClampedToScreen etc.) but made
    -- invisible; the void-skin below is the real art and acts as a fallback bg
    -- if a client lacks the 9-slice API.
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(unpack(PALETTE.border))   -- purple edge (solid-bg + border fallback while the 9-slice skin is off)

    -- Void panel skin: one opaque texture = void background + rounded purple
    -- frame, 9-sliced so corners stay crisp at any panel size. db.alpha fades it
    -- (background-only; text/icons stay opaque).
    -- Real background fill as its OWN texture, BELOW the skin, so it can extend
    -- UNDER the ornate frame bar. The rectangular backdrop fill couldn't reach past
    -- the frame edge, which left the off-centre box / gap-ring inside the ornate
    -- opening once background opacity was turned up.
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetColorTexture(0, 0, 0, 0)
    f.bg = bg

    local skin = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    skin:SetTexture(OO:FrameTexPath())   -- chosen frame style (border1..5.tga)
    OO:ApplySkinGeometry(f, skin)
    skin:SetShown(OO.db ~= nil and OO.db.frameSkin ~= false)   -- on by default (clean thin frames)
    f.skin = skin

    -- Ornate title plate as its OWN frame (high frame level so it renders ABOVE
    -- neighbouring panels) overhanging the panel top. Holds the banner art, the
    -- white title, and (main panels) the mascot emblem on its left.
    local bf = CreateFrame("Frame", nil, f)
    bf:SetFrameLevel(f:GetFrameLevel() + 30)
    bf:SetSize(pw * ((OO.db and OO.db.bannerW) or 1.0), (OO.db and OO.db.bannerH) or 62)
    bf:SetPoint("BOTTOM", f, "TOP", (OO.db and OO.db.bannerX) or 0, (OO.db and OO.db.bannerY) or -18)
    local hb = bf:CreateTexture(nil, "BACKGROUND", nil, 2)
    hb:SetTexture(OO:BannerTexPath())
    hb:SetAllPoints(bf)
    pcall(function()
        if hb.SetTextureSliceMargins then
            hb:SetTextureSliceMargins(110, 24, 110, 24)
            if Enum and Enum.UITextureSliceMode then hb:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end
        end
    end)
    local btitle = bf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btitle:SetPoint("CENTER", bf, "CENTER", 0, 0)
    btitle:SetTextColor(1, 1, 1, 1)
    btitle:SetShadowColor(0, 0, 0, 1); btitle:SetShadowOffset(1.5, -1.5)
    btitle:SetText(((titleText or "OmniumObservator"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    if showLogo then
        -- Mascot lives on its OWN frame (child of the panel, not the banner) so it shows with or
        -- without the banner, and can be dragged freely when undocked.
        local mf = CreateFrame("Frame", nil, f)
        mf:SetSize((OO.db and OO.db.logoSize) or 74, (OO.db and OO.db.logoSize) or 74)
        mf:SetFrameLevel(f:GetFrameLevel() + 32)
        mf:SetMovable(true); mf:RegisterForDrag("LeftButton")
        mf:SetScript("OnDragStart", function(s) if OO.db.mascotUndocked and not OO.db.locked then s:StartMoving() end end)
        mf:SetScript("OnDragStop", function(s)
            s:StopMovingOrSizing()
            local fl, ft, pl, pt = s:GetLeft(), s:GetTop(), f:GetLeft(), f:GetTop()
            if fl and pl and ft and pt then OO.db.mascotPos = { x = fl - pl, y = ft - pt } end
        end)
        local logo = mf:CreateTexture(nil, "ARTWORK")
        logo:SetAllPoints(mf)
        logo:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\heroine.tga")
        f.logo, f.mascotFrame = logo, mf
    end
    bf:SetShown(OO.db == nil or OO.db.headerBanner ~= false)
    f.headerBanner, f.bannerFrame, f.bannerTitle = hb, bf, btitle

    -- Faint void-sorceress watermark — MAIN (logo) panels only, not Voidstorm/Counsel.
    if showLogo then
        local mark = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        mark:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\heroine.tga")
        do local ws = ((OO.db and OO.db.watermarkScale) or 0.42) * pw; mark:SetSize(ws, ws) end
        mark:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
        mark:SetAlpha(0.10)
        f.watermark = mark
    end

    -- Fallback title on the panel itself, shown only when the banner is hidden.
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -5)   -- centered (only shown when the banner is off)
    title:SetJustifyH("CENTER")
    title:SetText(((titleText or "OmniumObservator"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    f.title = title

    local divider = f:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(pw - LINE_INSET * 2, 1)   -- match the text inset so it doesn't stick out past the content
    divider:SetPoint("TOP", f, "TOP", 0, -(headerH - 2))
    divider:SetColorTexture(PALETTE.divider[1], PALETTE.divider[2], PALETTE.divider[3], PALETTE.divider[4])

    local panel = { frame = f, linePool = {}, sepPool = {}, hotPool = {}, headerH = headerH }
    for i = 1, 20 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", LINE_INSET, -(headerH + (i - 1) * ROW_H + 4))
        fs:SetWidth(pw - LINE_INSET * 2)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        panel.linePool[i] = fs
        -- invisible hover hotspot per row → tooltips; clicks pass through so the panel still drags.
        local hot = CreateFrame("Button", nil, f)
        hot:EnableMouse(true)
        pcall(function() hot:SetMouseClickEnabled(false) end)
        hot:SetFrameLevel(f:GetFrameLevel() + 6)
        hot:Hide()
        hot:SetScript("OnEnter", function(s)
            if s.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); pcall(s.tip, GameTooltip); GameTooltip:Show() end
        end)
        hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.hotPool[i] = hot
    end
    for i = 1, 8 do
        local sep = f:CreateTexture(nil, "BACKGROUND")
        sep:SetSize(pw - 20, 1)
        sep:SetColorTexture(0.45, 0.25, 0.75, 0.45)
        sep:Hide()
        panel.sepPool[i] = sep
    end
    OO:StyleSeps(panel)   -- apply the chosen divider art / plain rule
    return panel
end

function OO:BuildUI()
    local db = self.db
    local panel = self:CreatePanel("OOMainFrame", "MEDIUM",
        "|c" .. PALETTE.title .. "OmniumObservator|r  |c" .. PALETTE.dim .. OO.version .. "|r", true)
    local frame = panel.frame
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    frame:SetScale(db.scale)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not OO.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        OO:SavePosition()
    end)
    frame:SetScript("OnShow", function() OO:Refresh() end)

    frame:Show()
    self.panel = panel
    self.frame = frame
    self:AddCollapseButton(panel)
    self:ApplyAppearance()
end

-- Lazily create the two embedded panels (anchored INSIDE the folio's empty
-- columns when it opens). Parented to UIParent so we never taint the Traits frame.
-- The left panel's title is the addon name (no version); the right is "Voidstorm".
function OO:BuildDock()
    if self.dockL then return end
    self.dockL = self:CreatePanel("OODockLeft",  "HIGH", "|c" .. PALETTE.title .. "OmniumObservator|r", true)
    self.dockR = self:CreatePanel("OODockRight", "HIGH", "|c" .. PALETTE.title .. "Devouring Watch|r", false)
    self.dockGuide = self:CreatePanel("OODockGuide", "HIGH", "|c" .. PALETTE.title .. "Decimus's Counsel|r", false)
    self:MakeDockDraggable(self.dockL, "dockLPos")
    self:MakeDockDraggable(self.dockR, "dockRPos")
    self:MakeDockDraggable(self.dockGuide, "dockGuidePos")
    self:AddCollapseButton(self.dockL)
    -- Real WoW next-page arrow button to cycle the Counsel build (replaces the old "[ > ]" text)
    local rb = CreateFrame("Button", nil, self.dockGuide.frame)
    rb:SetSize(26, 26)
    rb:SetPoint("TOPRIGHT", self.dockGuide.frame, "TOPRIGHT", -6, -3)
    rb:SetFrameLevel(self.dockGuide.frame:GetFrameLevel() + 5)
    rb:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    rb:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    rb:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    rb:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    rb:SetScript("OnClick", function() OO:CycleGuideRole(1) end)
    rb:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Next build")
        GameTooltip:AddLine("Cycle the recommended Counsel build.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.dockL.frame:Hide()
    self.dockR.frame:Hide()
    self.dockGuide.frame:Hide()
end

-- Drag a folio panel and remember where it was dropped (offset from the folio's
-- top-left). Respects the lock toggle.
function OO:MakeDockDraggable(panel, key)
    local f = panel.frame
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not OO.db.locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        OO:SaveDockPos(panel, key)
    end)
end

function OO:SaveDockPos(panel, key)
    local f, folio = panel.frame, self.folioFrame
    if not folio then return end
    local fl, ft = f:GetLeft(), f:GetTop()
    local gl, gt = folio:GetLeft(), folio:GetTop()
    if fl and gl and ft and gt then
        local dx, dy = fl - gl, ft - gt
        self.db[key] = { x = dx, y = dy }
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", folio, "TOPLEFT", dx, dy)
    end
end

-- A [+]/[-] in the header that collapses/expands the weekly list. Given its own
-- dark plate so it stays legible sitting on top of the ornate banner.
function OO:AddCollapseButton(panel)
    local b = CreateFrame("Button", nil, panel.frame, "BackdropTemplate")
    b:SetSize(22, 22)
    b:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -8, -6)
    b:SetFrameLevel(panel.frame:GetFrameLevel() + 8)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.05, 0.02, 0.12, 0.9)
    b:SetBackdropBorderColor(unpack(PALETTE.border))
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("CENTER", 0, 1)
    t:SetText(OO.db.weeksCollapsed and "+" or "-")
    b.text = t
    b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(1, 0.85, 0.2) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpack(PALETTE.border)) end)
    b:SetScript("OnClick", function()
        OO.db.weeksCollapsed = not OO.db.weeksCollapsed
        OO:UpdateCollapseButtons()
        OO:Refresh()
    end)
    panel.collapseBtn = b
end

function OO:UpdateCollapseButtons()
    local txt = OO.db.weeksCollapsed and "+" or "-"
    if self.panel and self.panel.collapseBtn then self.panel.collapseBtn.text:SetText(txt) end
    if self.dockL and self.dockL.collapseBtn then self.dockL.collapseBtn.text:SetText(txt) end
end

-- Locate the Omnium Folio frame (only present once Blizzard_ExpansionLandingPage
-- has loaded — it is LoadOnDemand, opened from the Midnight landing button).
function OO:GetFolioFrame()
    local elp = _G.ExpansionLandingPage
    local ov  = elp and elp.Overlay
    local mlo = ov and ov.MidnightLandingOverlay
    return mlo and mlo.RunesOfPowerFrame or nil
end

function OO:TryHookFolio()
    if self.folioHooked then return end
    local rof = self:GetFolioFrame()
    if not rof then return end
    self.folioFrame = rof
    self:BuildDock()
    rof:HookScript("OnShow", function()
        OO:OnFolioShown()
        OO:GainDailyFavor("folio", 1)   -- a little favor for visiting the folio (once/day)
        -- Greeting fires ONLY on a real folio OnShow (not on the many refresh/config re-calls of OnFolioShown).
        if OO.db.showModel and OO._ready and C_Timer then
            C_Timer.After(0.8, function()
                if not OO:MaybeXalatath() then OO:DecimusSpeak(false) end
            end)
        end
    end)
    rof:HookScript("OnHide", function() OO:AdvisorFarewell(); OO:OnFolioHidden() end)
    self.folioHooked = true
    if rof:IsShown() then self:OnFolioShown() end
end

-- The folio is LoadOnDemand and its RunesOfPowerFrame may be built a beat after
-- the addon loads (or only on first open), so poll briefly until we catch it.
function OO:ScheduleFolioHook()
    if self.folioHooked then return end
    self:TryHookFolio()
    if self.folioHooked or self._folioPolling or not C_Timer then return end
    self._folioPolling = true
    local attempts = 0
    local function poll()
        attempts = attempts + 1
        OO:TryHookFolio()
        if OO.folioHooked or attempts >= 30 then
            OO._folioPolling = false
            return
        end
        C_Timer.After(1, poll)
    end
    C_Timer.After(1, poll)
end

function OO:OnFolioShown()
    if not self.db.dockEnabled or not self.dockL then return end
    -- capture the live configID (it can change between sessions)
    pcall(function()
        if self.folioFrame and self.folioFrame.GetConfigID then
            local id = self.folioFrame:GetConfigID()
            if id and id > 0 then self.folioConfigID = id end
        end
    end)
    -- Embed: anchor inside the folio's empty columns (or wherever you dragged them).
    local lf, rf = self.dockL.frame, self.dockR.frame
    local folio = self.folioFrame
    local lp, rp = self.db.dockLPos, self.db.dockRPos
    lf:ClearAllPoints()
    if lp then lf:SetPoint("TOPLEFT", folio, "TOPLEFT", lp.x, lp.y)
    else lf:SetPoint("TOPLEFT", folio, "TOPLEFT", 28, -96) end
    rf:ClearAllPoints()
    if rp then rf:SetPoint("TOPLEFT", folio, "TOPLEFT", rp.x, rp.y)
    else rf:SetPoint("TOPRIGHT", folio, "TOPRIGHT", -28, -96) end
    lf:Show()
    rf:Show()
    -- Optional "Decimus's Counsel" rune-guide panel (left, below the This-week panel)
    local gf = self.dockGuide.frame
    gf:ClearAllPoints()
    local gp = self.db.dockGuidePos
    if gp then gf:SetPoint("TOPLEFT", folio, "TOPLEFT", gp.x, gp.y)
    else gf:SetPoint("TOPLEFT", folio, "TOPLEFT", 28, -300) end
    gf:SetShown(self.db.showGuide == true)
    -- Nilhammer forge bar, docked to the folio like the panels (default: lower-right).
    if self.db.forgeBar ~= false and self.db.showNilhammer ~= false then
        if not self.forgeFrame then self:BuildForgeFrame() end
        local ff = self.forgeFrame
        ff:ClearAllPoints()
        local fp = self.db.forgeDockPos
        if fp then ff:SetPoint("TOPLEFT", folio, "TOPLEFT", fp.x, fp.y)
        else ff:SetPoint("TOPRIGHT", folio, "TOPRIGHT", -28, -540) end
        ff:Show()
    elseif self.forgeFrame then
        self.forgeFrame:Hide()
    end
    -- The embed is the single source of info while the folio is open — hide the
    -- standalone panel (if it was up) and restore it when the folio closes.
    if self.frame and self.frame:IsShown() then
        self._frameWasShown = true
        self.frame:Hide()
    end
    self:ApplyAppearance()
    self:Refresh()
    self:UpdateModel()
    -- (Decimus's greeting lives on the folio's OnShow hook now, so re-anchoring/refreshing
    --  via config toggles no longer makes him talk.)
    -- keep the reset timer / currency counts fresh while the folio is open
    lf:SetScript("OnUpdate", function(s, elapsed)
        s._t = (s._t or 0) + elapsed
        if s._t > 5 then s._t = 0; OO:Refresh() end
    end)
end

function OO:OnFolioHidden()
    if self.dockL then
        self.dockL.frame:SetScript("OnUpdate", nil)
        self.dockL.frame:Hide()
    end
    if self.dockR then self.dockR.frame:Hide() end
    if self.dockGuide then self.dockGuide.frame:Hide() end
    if self.forgeFrame then self.forgeFrame:Hide() end
    if self.model then self.model:Hide() end
    if self._frameWasShown then
        self._frameWasShown = false
        if self.frame then self.frame:Show() end
    end
end

-- Real folio close → the active advisor's farewell VO (only advisors with a farewell set,
-- e.g. Riko; gated by the voice toggle). Hung on the genuine OnHide, not config-driven hides.
function OO:AdvisorFarewell()
    if not (self.model and self.model:IsShown()) then return end
    if self.db.decimusVoice == false or not PlaySoundFile then return end
    local idx = self.db.modelChoice or 1
    if not OO:ModelUnlocked(idx) then idx = 1 end
    local vo = ADVISOR_VO[(MODELS[idx] or MODELS[1]).name]
    if vo and not vo.silent and vo.bye and #vo.bye > 0 then
        local e = vo.bye[math.random(#vo.bye)]
        if e.id then pcall(function() PlaySoundFile(e.id, "Dialog") end) end
    end
end

-- Decimus 3D creature model in the folio's lower-left empty space (opt-in via
-- config). Parented to UIParent + anchored to the folio so the Traits frame is
-- never touched. Interactive like WoW's native model frames: left-drag to rotate,
-- scroll to zoom. Heavily guarded — a bad creature ID just shows nothing.
function OO:UpdateModel(creatureOverride)
    if not self.folioFrame then return end
    if not self.db.showModel then
        if self.model then self.model:Hide() end
        return
    end
    if not self.model then
        local m = CreateFrame("PlayerModel", "OODecimusModel", UIParent)
        m:SetFrameStrata("FULLSCREEN_DIALOG")  -- floats over everything (movable)
        m:SetSize(240, 340)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:EnableMouseWheel(true)
        m:RegisterForDrag("RightButton")
        m.facing, m.zoom = 0.45, 0

        -- Speech bubble near his head (pulled down from the frame's top edge, which
        -- sits well above the model — the old -2 floated it too high).
        local bubble = CreateFrame("Frame", nil, m, "BackdropTemplate")
        bubble:SetPoint("BOTTOM", m, "TOP", 0, -48)
        bubble:SetSize(220, 72)
        -- Authentic WoW chat-bubble artwork (rounded speech-bubble look).
        bubble:SetBackdrop({
            bgFile = "Interface\\Tooltips\\CHATBUBBLE-BACKGROUND",
            edgeFile = "Interface\\Tooltips\\CHATBUBBLE-BACKDROP",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 16, right = 16, top = 16, bottom = 16 },
        })
        bubble:SetBackdropColor(0.06, 0.03, 0.12, 0.95)
        bubble:SetBackdropBorderColor(unpack(PALETTE.border))
        local bt = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bt:SetPoint("TOPLEFT", 15, -13)
        bt:SetPoint("BOTTOMRIGHT", -15, 13)
        bt:SetJustifyH("LEFT")
        bt:SetWordWrap(true)
        bubble:Hide()
        m.bubble, m.bubbleText = bubble, bt

        -- Left = rotate (drag) / speak (click). Right-drag = move. Scroll = zoom.
        m:SetScript("OnMouseDown", function(s, btn)
            if btn == "LeftButton" then s.rotating = true; s.moved = false; s.lastX = GetCursorPosition() end
        end)
        m:SetScript("OnMouseUp", function(s, btn)
            if btn == "LeftButton" then
                s.rotating = false
                if not s.moved then OO:DecimusClicked() end
            end
        end)
        m:SetScript("OnUpdate", function(s)
            if s.rotating then
                local x = GetCursorPosition()
                local dx = x - (s.lastX or x)
                if math.abs(dx) > 1 then s.moved = true end
                s.facing = (s.facing or 0) + dx * 0.012
                s.lastX = x
                pcall(function() s:SetFacing(s.facing) end)
            end
        end)
        m:SetScript("OnMouseWheel", function(s, delta)
            s.zoom = math.max(0, math.min(0.9, (s.zoom or 0) + delta * 0.1))
            pcall(function() s:SetPortraitZoom(s.zoom) end)
        end)
        m:SetScript("OnDragStart", function(s) if not OO.db.modelLocked then s:StartMoving() end end)
        m:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); OO:SaveModelPos() end)
        m:SetScript("OnModelLoaded", function(s)
            pcall(function() s:SetPortraitZoom(s.zoom or 0); s:SetFacing(s.facing or 0.45) end)
        end)
        self.model = m
    end
    local m = self.model
    local ms = self.db.modelScale or 1.0
    m:SetSize(240 * ms, 340 * ms)
    m:ClearAllPoints()
    local mp = self.db.modelPos
    if mp then m:SetPoint("BOTTOMLEFT", self.folioFrame, "BOTTOMLEFT", mp.x, mp.y)
    else m:SetPoint("BOTTOMLEFT", self.folioFrame, "BOTTOMLEFT", 36, 30) end
    pcall(function()
        if creatureOverride then
            m:SetCreature(creatureOverride)
        else
            local idx = self.db.modelChoice or 1
            if not OO:ModelUnlocked(idx) then idx = 1 end
            local e = MODELS[idx] or MODELS[1]
            if e.player then m:SetUnit("player") else m:SetCreature(e.id) end
        end
        m:SetPortraitZoom(m.zoom or 0)
        m:SetFacing(m.facing or 0.45)
    end)
    m:Show()
end

-- Point a model frame at the player's chosen / highest-unlocked advisor (Decimus by default).
-- Used by the General-tab 3D preview widget.
function OO:SetPreviewModel(m)
    local idx = (self.db and self.db.modelChoice) or 1
    if not self:ModelUnlocked(idx) then idx = 1 end
    local e = MODELS[idx] or MODELS[1]
    if e.player then pcall(function() m:SetUnit("player") end) else pcall(function() m:SetCreature(e.id) end) end
end

function OO:SaveModelPos()
    local m, folio = self.model, self.folioFrame
    if not (m and folio) then return end
    local ml, mb = m:GetLeft(), m:GetBottom()
    local fl, fb = folio:GetLeft(), folio:GetBottom()
    if ml and fl and mb and fb then
        self.db.modelPos = { x = ml - fl, y = mb - fb }
    end
end

-- Decimus speaks a random line (rare set = easter egg) + a talk animation.
function OO:DecimusSpeak(rare)
    local m = self.model
    if not (m and m:IsShown() and m.bubbleText) then return end
    local nm = UnitName("player") or "lightling"
    local voiceOn = (self.db.decimusVoice ~= false) and PlaySoundFile and true or false
    local idx = self.db.modelChoice or 1
    if not OO:ModelUnlocked(idx) then idx = 1 end
    local who = (MODELS[idx] or MODELS[1]).name
    local line, soundID, yell
    if who == "Decimus" then
        if rare then
            line = DECIMUS_RARE[math.random(#DECIMUS_RARE)]:gsub("<name>", nm)
            if voiceOn and #DECIMUS_SOUNDS > 0 then soundID = DECIMUS_SOUNDS[math.random(#DECIMUS_SOUNDS)] end
        elseif voiceOn and #DECIMUS_VO > 0 then
            local e = DECIMUS_VO[math.random(#DECIMUS_VO)]   -- pair the spoken line to its transcript
            line, soundID, yell = e.text:gsub("<name>", nm), e.id, e.yell
        else
            line = DECIMUS_QUOTES[math.random(#DECIMUS_QUOTES)]:gsub("<name>", nm)
        end
    else
        -- favor-unlocked advisors: voiced ones (Riko) use paired { id, text } pools so the bubble
        -- matches the audio; silent ones (Terminas / You) use text-only `lines`.
        local vo = ADVISOR_VO[who]
        if vo then
            local pool  = (rare and vo.mad) or vo.greet           -- { id =, text = } entries
            local lines = (rare and vo.madLines) or vo.lines      -- strings or { text =, yell = }
            if pool and #pool > 0 then
                local e = pool[math.random(#pool)]
                if voiceOn and not vo.silent and e.id then soundID = e.id end
                line, yell = e.text, e.yell
            elseif lines and #lines > 0 then
                local pick = lines[math.random(#lines)]
                if type(pick) == "table" then line, yell = pick.text, pick.yell else line = pick end
            end
            if line then line = line:gsub("<name>", nm) end
        end
        if not line then line = DECIMUS_QUOTES[math.random(#DECIMUS_QUOTES)]:gsub("<name>", nm) end
    end
    if yell then line = "|cFFFF2020" .. line .. "|r" end   -- (#69) a yell renders in red
    m.bubbleText:SetText(line)
    if yell then
        m.bubble:SetBackdropBorderColor(0.9, 0.12, 0.12, 1)
    else
        m.bubble:SetBackdropBorderColor(rare and 0.85 or PALETTE.border[1], rare and 0.20 or PALETTE.border[2], rare and 1.0 or PALETTE.border[3], 1)
    end
    m.bubble:Show()
    pcall(function() m:SetAnimation(rare and 64 or 60) end)
    if soundID then pcall(function() PlaySoundFile(soundID, "Dialog") end) end
    if self._speakTimer then self._speakTimer:Cancel() end
    self._speakTimer = C_Timer.NewTimer(rare and 8 or 5, function()
        if m.bubble then m.bubble:Hide() end
        pcall(function() m:SetAnimation(0) end)
    end)
end

-- Click handler with a hidden easter egg: 7 quick clicks unlocks a rare line.
function OO:DecimusClicked()
    self:GainClickFavor()
    local now = GetTime()
    if now - (self._decClickAt or 0) > 2 then self._decClicks = 0 end
    self._decClicks = (self._decClicks or 0) + 1
    self._decClickAt = now
    if self._decClicks >= 7 then
        self._decClicks = 0
        self:DecimusSpeak(true)
    else
        self:DecimusSpeak(false)
    end
end

-- Earn "favor" by clicking Decimus / tabbing rune builds. Enough favor — or the
-- Omnium Folio Studies achievement — unlocks the bonus model roster (egg).
function OO:ModelUnlocked(idx)
    local e = MODELS[idx]
    if not e then return false end
    if e.wip then return false end   -- unlock mechanic still TBD: hide from the menu entirely (no preview)
    return (self.db.decimusFavor or 0) >= (e.unlock or 0)
end

-- Display name for a model entry — the player's own character name for the "You" slot.
function OO:ModelName(e)
    return (e and e.player and (UnitName("player") or "You")) or (e and e.name) or "?"
end

function OO:GainFavor(n)
    local before = self.db.decimusFavor or 0
    self.db.decimusFavor = before + (n or 1)
    -- announce when favor just crossed a model's unlock threshold
    for _, e in ipairs(MODELS) do
        if e.unlock > 0 and before < e.unlock and self.db.decimusFavor >= e.unlock then
            local col = RARITY_COLOR[e.rarity] or "FFFFFFFF"
            print("|cFFFFCC00OmniumObservator|r The void yields a new servant: |c" .. col .. OO:ModelName(e) ..
                "|r unlocked! Pick it in the Decimus options, or |cFFFFFFFF/oo model next|r.")
            if self.model and self.model:IsShown() then self:DecimusSpeak(true) end
        end
    end
    self:Refresh()   -- live update of the favor counter
end

-- Favor day key (server-aligned) for the daily/diminishing sources.
local function FavorDay() return math.floor((GetServerTime and GetServerTime() or time()) / 86400) end

-- One daily award per key (e.g. opening the folio).
function OO:GainDailyFavor(key, amount)
    self.db.favorDaily = self.db.favorDaily or {}
    if self.db.favorDaily[key] ~= FavorDay() then
        self.db.favorDaily[key] = FavorDay()
        self:GainFavor(amount or 1)
    end
end

-- Clicking Decimus has diminishing returns: at most 3 favor per day from clicks.
function OO:GainClickFavor()
    local day = FavorDay()
    if self.db.favorClickDay ~= day then self.db.favorClickDay = day; self.db.favorClickN = 0 end
    if (self.db.favorClickN or 0) < 3 then
        self.db.favorClickN = (self.db.favorClickN or 0) + 1
        self:GainFavor(1)
    end
end

-- Activity-based favor: +2 per newly unlocked week, +5 first Nilhammer forge, +3 folio achievement.
function OO:CheckFavorSources()
    if not self.db then return end
    local unlocked = self:GetWeeks().unlocked or 0
    if self.db.favorWeeksCounted == nil then
        self.db.favorWeeksCounted = unlocked              -- baseline; no retroactive award
    elseif unlocked > self.db.favorWeeksCounted then
        local g = (unlocked - self.db.favorWeeksCounted) * 2
        self.db.favorWeeksCounted = unlocked
        self:GainFavor(g)
    end
    if not self.db.favorNilhammer and self:GetNilhammerState().done then
        self.db.favorNilhammer = true; self:GainFavor(5)
    end
    if not self.db.favorAchievement then
        local earned = false
        pcall(function() earned = select(4, GetAchievementInfo(ACH_OMNIUM_FOLIO)) end)
        if earned then self.db.favorAchievement = true; self:GainFavor(3) end
    end
end

-- The Void favor counter row — shared by the Counsel panel and the standalone glance panel.
function OO:FavorLine()
    local fav = self.db.decimusFavor or 0
    return {
        text = string.format("|T" .. MEDIA .. "favor.tga:18:18:0:0|t |c" .. PALETTE.purple .. "Void favor:|r |c%s%d|r", RarityFracColor(fav / 30), fav),
        tip = function(tt)
            tt:AddLine("|cFFC58CFFVoid favor|r")
            tt:AddLine("Earned from the folio — opening it daily, unlocking weeks, forging the Nilhammer, the folio achievement, and the odd word with Decimus. Unlocks new servants as it grows.", 0.8, 0.8, 0.8, true)
            tt:AddLine(" ")
            tt:AddLine("Favor: |cFFFFFFFF" .. fav .. "|r")
        end,
    }
end

-- Easter egg: once enough folio weeks are open, Xal'atath has a small chance to
-- hijack the model frame and mock you, then it reverts to your chosen model.
function OO:MaybeXalatath()
    local m = self.model
    if not (m and m:IsShown() and self._ready) then return false end
    local weeks = self:GetWeeks().unlocked or 0
    if weeks < 3 then return false end
    local allDone = weeks >= 5
    if math.random() > (allDone and 0.20 or 0.15) then return false end   -- 15% at 3+ weeks, 20% once all 5 are done
    -- She portals in, hijacks the model, and whispers one of her real lines (bubble matches audio).
    pcall(function() m:SetCreature(XALATATH_ID); m:SetFacing(0.5) end)
    local e = XAL_VO[math.random(#XAL_VO)]
    if m.bubbleText then
        m.bubbleText:SetText(e.text)
        m.bubble:SetBackdropBorderColor(0.9, 0.12, 0.12, 1)   -- artifact red
        m.bubble:Show()
        pcall(function() m:SetAnimation(60) end)
    end
    if self.db.decimusVoice ~= false and PlaySoundFile then
        pcall(function() PlaySoundFile(XAL_PORTAL, "Dialog") end)        -- portal-in whoosh as she arrives
        C_Timer.After(0.9, function() pcall(function() PlaySoundFile(e.id, "Dialog") end) end)   -- then her line
    end
    if allDone then self:XalatathPrank() end   -- end-game: she also shoves a couple of your frames around
    if self._xalTimer then self._xalTimer:Cancel() end
    self._xalTimer = C_Timer.NewTimer(6, function()
        if m.bubble then m.bubble:Hide() end
        pcall(function() m:SetAnimation(0) end)
        OO:UpdateModel()   -- revert to the chosen model
    end)
    return true
end

-- End-game mischief: once all 5 weeks are done, Xal'atath randomly displaces two of your
-- visible frames (saved, so you find them moved). "Reset all panel positions" undoes it.
function OO:XalatathPrank()
    local cands = {}
    if self.dockL and self.dockL.frame:IsShown() then cands[#cands + 1] = "dockLPos" end
    if self.dockR and self.dockR.frame:IsShown() then cands[#cands + 1] = "dockRPos" end
    if self.dockGuide and self.dockGuide.frame:IsShown() then cands[#cands + 1] = "dockGuidePos" end
    if self.frame and self.frame:IsShown() then cands[#cands + 1] = "main" end
    local folio = self.folioFrame
    local map = { dockLPos = self.dockL, dockRPos = self.dockR, dockGuidePos = self.dockGuide }
    for _ = 1, 2 do
        if #cands == 0 then break end
        local key = table.remove(cands, math.random(#cands))
        local dx, dy = math.random(-140, 140), math.random(-110, 110)
        if key == "main" and self.frame then
            self.db.x = (self.db.x or 400) + dx
            self.db.y = (self.db.y or 200) + dy
            self.frame:ClearAllPoints(); self.frame:SetPoint("CENTER", UIParent, "CENTER", self.db.x, self.db.y)
        elseif folio and map[key] then
            local cur = self.db[key] or { x = 28, y = -96 }
            cur = { x = cur.x + dx, y = cur.y + dy }
            self.db[key] = cur
            map[key].frame:ClearAllPoints(); map[key].frame:SetPoint("TOPLEFT", folio, "TOPLEFT", cur.x, cur.y)
        end
    end
end

-- Standalone "detached" panel mirrors the embed: the left (weeks / tasks / reset)
-- and right (Voidstorm resources) content combined into one panel, same theme.
function OO:BuildLines()
    local lines = self:BuildLeftLines()
    lines[#lines + 1] = "sep"
    for _, l in ipairs(self:BuildRightLines()) do
        lines[#lines + 1] = l
    end
    lines[#lines + 1] = "sep"
    lines[#lines + 1] = self:FavorLine()
    return lines
end

-- Left embedded panel: this week's folio progress + reset countdown.
function OO:BuildLeftLines()
    local weeks = self:GetWeeks()
    local ws    = self:GetWeeklyState()
    local reset = self:GetResetSeconds()
    local lines = {}

    if weeks.allDone then
        lines[#lines + 1] = "|c" .. PALETTE.gold .. "Omnium Folio: |cFF66FF66COMPLETE|r"
    else
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.gold .. "Omnium Folio|r  |cFFFFFFFF%d|r|c" .. PALETTE.dim .. "/5 weeks|r", weeks.unlocked)
    end
    lines[#lines + 1] = "sep"

    -- Each week shows its loot-rarity colour (the full ladder is visible); the
    -- check vs bullet shows progress. Collapsible via the header [+]/[-] button.
    if self.db.weeksCollapsed then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.dim .. "%d/5 weeks — [ + ] to expand|r", weeks.unlocked)
    else
        local nextIdx = (weeks.unlocked or 0) + 1   -- the first incomplete week is the one "up next"
        for i, step in ipairs(weeks.steps) do
            local color
            if step.done then color = WEEK_COLORS[i] or "FFCCCCCC"   -- complete → its loot-rarity colour
            elseif i == nextIdx then color = "FFC8A45C"              -- up next → matches the "Next:" line
            else color = WEEK_DIM end                                 -- future/locked → gray
            lines[#lines + 1] = string.format("%s |c%s%s|r", Check(step.done), color, step.name)
        end
    end

    lines[#lines + 1] = "sep"
    if ws.allDone then
        lines[#lines + 1] = "|cFF66FF66Folio fully unlocked!|r"
    elseif ws.inLog then
        lines[#lines + 1] = string.format("|cFFFFDD88This week: %s — in progress|r", ws.name)
    elseif ws.nextReset then
        lines[#lines + 1] = string.format("|cFFC8A45CNext: %s (next reset)|r", ws.name)
    else
        lines[#lines + 1] = string.format("|c" .. PALETTE.dim .. "Start: %s (Silvermoon)|r", ws.name)
    end

    -- Ascendant Nilhammer / Voidforge progression (one-time build, not weekly)
    if self.db.showNilhammer ~= false then
        local st = self:GetNilhammerState()
        if st.done then
            lines[#lines + 1] = string.format("%s |cFFCCCCCCAscendant Nilhammer|r |cFF54E08Aforged|r", Check(true))
        elseif st.hasObj then
            lines[#lines + 1] = string.format("%s |cFFCCCCCC%s|r |cFFFFFFFF%d/%d|r", Check(false), st.label or "Nilhammer", st.cur or 0, st.max or 1)
        else
            lines[#lines + 1] = string.format("%s |cFFCCCCCCFeed the Nilhammer|r", Check(false))
        end
    end

    if reset and self.db.showReset ~= false then
        lines[#lines + 1] = string.format(
            "|cFFC58CFFWeekly reset in|r |cFFFFD200%s|r", FmtDur(reset))
    end
    return lines
end

-- DevouringWatch merge — Void Assault world data (POI scan + weekly assault).
local function VAFormatCountdown(secs)
    if not secs or secs <= 0 then return "" end
    local h = math.floor(secs / 3600); local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("|cFFFFCC00%dh %dm|r", h, m) end
    return string.format("|cFFFFCC00%dm|r", m)
end
function OO:GetMapEvents()
    local events = {}
    pcall(function()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID or not C_AreaPoiInfo or not C_AreaPoiInfo.GetEventsForMap then return end
        for _, poiID in ipairs(C_AreaPoiInfo.GetEventsForMap(mapID) or {}) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.name then
                events[#events + 1] = { name = info.name, secsLeft = C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID) }
            end
        end
    end)
    return events
end
function OO:GetWeeklyAssault()
    local res = { locked = true }
    pcall(function()
        if not C_QuestLog.IsQuestFlaggedCompleted(VA_INTRO_QUEST) then return end
        res = { none = true }
        local n = C_QuestLog.GetNumQuestLogEntries()
        for _, q in ipairs(VA_WEEKLY_QUESTS) do
            for i = 1, n do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID == q.id then
                    res = { zone = q.zone, inLog = true, pct = GetQuestProgressBarPercent(q.id) or 0 }
                    return
                end
            end
            if C_QuestLog.IsQuestFlaggedCompleted(q.id) then res = { zone = q.zone, done = true }; return end
        end
    end)
    return res
end

-- Right embedded panel ("Devouring Watch"): Voidstorm economy + Void Assault world data.
function OO:BuildRightLines()
    local lines = {}
    local db = self.db
    local function sep() if #lines > 0 and lines[#lines] ~= "sep" then lines[#lines + 1] = "sep" end end

    if db.showMotes ~= false then
        local motes = self:GetMotes()
        lines[#lines + 1] = {
            text = string.format("|c" .. PALETTE.gold .. "Motes:|r |cFFFFFFFF%s|r", motes and tostring(motes) or "—"),
            tip = function(tt) tt:AddLine("Motes of Omnial Inquiry"); tt:AddLine("Folio trait currency — spent unlocking the weekly runes.", 0.8, 0.8, 0.8, true) end,
        }
    end
    if db.showRolls ~= false then
        local neb, nebMax = self:GetCurrency(NEBULOUS_VOIDCORE)
        local nebStr = neb and tostring(neb) or "—"
        if neb and nebMax and nebMax > 0 then
            nebStr = "|c" .. RarityFracColor(neb / nebMax) .. neb .. "/" .. nebMax .. "|r"
        end
        lines[#lines + 1] = {
            text = string.format("%s|c" .. PALETTE.purple .. "Bonus rolls:|r %s",
                IconTag(self:CurrencyIcon(NEBULOUS_VOIDCORE)), nebStr),
            tip = function(tt) tt:SetCurrencyByID(NEBULOUS_VOIDCORE) end,
        }
    end

    if db.showVoidcores ~= false or db.showVoidshard ~= false then sep() end
    if db.showVoidcores ~= false then
        local cores = self:GetItem(ITEM_ASCENDANT_VOIDCORE)
        lines[#lines + 1] = {
            text = string.format("%s|c" .. PALETTE.purple .. "Ascendant Voidcores:|r |cFFFFFFFF%s|r",
                IconTag(self:ItemIcon(ITEM_ASCENDANT_VOIDCORE)), cores and tostring(cores) or "0"),
            tip = function(tt) tt:SetItemByID(ITEM_ASCENDANT_VOIDCORE) end,
        }
    end
    if db.showVoidshard ~= false then
        local shards = self:GetItem(ITEM_ASCENDANT_VOIDSHARD)
        lines[#lines + 1] = {
            text = string.format("%s|c" .. PALETTE.purple .. "Ascendant Voidshard:|r |cFFFFFFFF%s|r",
                IconTag(self:ItemIcon(ITEM_ASCENDANT_VOIDSHARD)), shards and tostring(shards) or "0"),
            tip = function(tt) tt:SetItemByID(ITEM_ASCENDANT_VOIDSHARD) end,
        }
    end

    -- Void Assaults (DevouringWatch merge): live zone events, weekly assault, currencies
    if db.showAssaults ~= false then
        sep()
        for _, ev in ipairs(self:GetMapEvents()) do
            local t = VAFormatCountdown(ev.secsLeft)
            lines[#lines + 1] = "|c" .. PALETTE.purple .. ev.name .. "|r" .. (t ~= "" and ("  " .. t) or "")
        end
        local wa = self:GetWeeklyAssault()
        if wa.locked then
            lines[#lines + 1] = "|c" .. PALETTE.dim .. "Void Assaults locked (intro in Silvermoon)|r"
        elseif wa.done then
            lines[#lines + 1] = "|cFF66FF66Weekly Assault: " .. wa.zone .. " - done|r"
        elseif wa.inLog then
            local p = wa.pct > 0 and string.format(" |cFFFFDD88%.0f%%|r", wa.pct) or ""
            lines[#lines + 1] = "|c" .. PALETTE.purple .. "Weekly Assault: " .. wa.zone .. "|r" .. p
        end
        local acc = self:GetCurrency(CURRENCY_FIELD_ACCOLADE)
        local marl = self:GetCurrency(CURRENCY_VOIDLIGHT_MARL)
        lines[#lines + 1] = {
            text = string.format("%s|c" .. PALETTE.gold .. "Field Accolade:|r |cFFFFFFFF%s|r",
                IconTag(self:CurrencyIcon(CURRENCY_FIELD_ACCOLADE)), tostring(acc or 0)),
            tip = function(tt) tt:SetCurrencyByID(CURRENCY_FIELD_ACCOLADE) end,
        }
        lines[#lines + 1] = {
            text = string.format("%s|c" .. PALETTE.purple .. "Voidlight Marl:|r |cFFFFFFFF%s|r",
                IconTag(self:CurrencyIcon(CURRENCY_VOIDLIGHT_MARL)), tostring(marl or 0)),
            tip = function(tt) tt:SetCurrencyByID(CURRENCY_VOIDLIGHT_MARL) end,
        }
    end

    if #lines == 0 then lines[#lines + 1] = "|c" .. PALETTE.dim .. "(rows hidden in options)|r" end
    return lines
end

-- "Decimus's Counsel" — role-based recommended build, click the header [>] to cycle.
function OO:BuildGuideLines()
    local b = ROLE_BUILDS[self.db.guideRole or 3] or ROLE_BUILDS[1]
    local lines = {}
    lines[#lines + 1] = string.format(
        "|c" .. PALETTE.gold .. "Best for:|r |cFFFFFFFF%s|r", b.role)
    lines[#lines + 1] = "sep"
    for _, t in ipairs(b.tiers) do
        local spellID = t[3]
        local icon = spellID and IconTag(self:SpellIcon(spellID)) or ""
        local row = string.format("%s|c" .. PALETTE.purple .. "%s:|r |cFFFFFFFF%s|r", icon, t[1], t[2])
        if spellID then
            lines[#lines + 1] = { text = row, tip = function(tt) tt:SetSpellByID(spellID) end }
        else
            lines[#lines + 1] = row
        end
    end
    -- Void favor counter (drives the Decimus model unlocks); shared with the standalone panel.
    lines[#lines + 1] = "sep"
    lines[#lines + 1] = self:FavorLine()
    return lines
end

function OO:CycleGuideRole(dir)
    local n = #ROLE_BUILDS
    self.db.guideRole = ((self.db.guideRole or 3) - 1 + (dir or 1)) % n + 1
    self:Refresh()
    self:GainFavor(1)
end

-- Weekly-unlock gem bar: the five rarity gems (common -> legendary) light up as
-- the five Seeking Knowledge weeks unlock; locked weeks show desaturated + dim.
-- Anchored along the panel's bottom edge. Built lazily on first update.
local GEM_NAMES = { "common", "uncommon", "rare", "epic", "legendary" }
function OO:BuildGemBar(panel)
    if not panel or not panel.frame or panel.gems then return end
    local gems, glows, hots = {}, {}, {}
    for i = 1, 5 do
        -- (#5) pulsing additive glow behind each lit gem
        local glow = panel.frame:CreateTexture(nil, "ARTWORK", nil, 1)
        glow:SetTexture("Interface\\Cooldown\\star4")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1.0, 0.92, 0.45)
        glow:Hide()
        local ag = glow:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0.3); a:SetToAlpha(1.0); a:SetDuration(0.9)
        glow.ag, glow.aAnim = ag, a
        glows[i] = glow
        local t = panel.frame:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\gem_" .. GEM_NAMES[i] .. ".tga")
        gems[i] = t
        -- hover hotspot → this week's unlock tooltip (clicks pass through so the panel still drags)
        local hot = CreateFrame("Button", nil, panel.frame)
        hot.week = i
        hot:EnableMouse(true)
        pcall(function() hot:SetMouseClickEnabled(false) end)
        hot:SetFrameLevel(panel.frame:GetFrameLevel() + 6)
        hot:Hide()
        hot:SetScript("OnEnter", function(s)
            local q = WEEKLY_QUESTS[s.week]
            if not q then return end
            local st = OO:GetWeeks().steps[s.week]
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:AddLine("|c" .. (WEEK_COLORS[s.week] or "FFFFFFFF") .. (q.name or ("Week " .. s.week)) .. "|r")
            GameTooltip:AddLine("Folio week " .. s.week .. " of 5", 0.7, 0.7, 0.7)
            if st and st.done then GameTooltip:AddLine("Unlocked", 0.3, 0.9, 0.3)
            else GameTooltip:AddLine("Not yet unlocked", 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hots[i] = hot
    end
    panel.gems, panel.gemGlows, panel.gemHots = gems, glows, hots
end

function OO:UpdateGemBar(panel, unlocked)
    if not panel or not panel.frame then return end
    if not panel.gems then self:BuildGemBar(panel) end
    local show = self.db.gemBar ~= false
    local sz, gap = self.db.gemSize or 26, 5
    local totalW = 5 * sz + 4 * gap
    local glowAmt = self.db.gemGlow or 0
    for i = 1, 5 do
        local t = panel.gems[i]
        t:SetShown(show)
        t:SetSize(sz, sz)
        t:ClearAllPoints()
        t:SetPoint("BOTTOM", panel.frame, "BOTTOM", -totalW / 2 + (sz / 2) + (i - 1) * (sz + gap), 7)
        local lit = i <= (unlocked or 0)
        t:SetDesaturated(not lit)
        t:SetAlpha(lit and 1.0 or 0.28)
        local hot = panel.gemHots and panel.gemHots[i]
        if hot then
            hot:ClearAllPoints(); hot:SetPoint("CENTER", t, "CENTER", 0, 0)
            hot:SetSize(sz + 4, sz + 4); hot:SetShown(show)
        end
        local g = panel.gemGlows and panel.gemGlows[i]
        if g then
            if show and lit and glowAmt > 0 then
                local amt = math.min(1, glowAmt)
                g:ClearAllPoints(); g:SetPoint("CENTER", t, "CENTER", 0, 0)
                g:SetSize(sz * (2.4 + glowAmt), sz * (2.4 + glowAmt))   -- bigger, and grows as you crank it
                g.aAnim:SetFromAlpha(0.45 * amt); g.aAnim:SetToAlpha(amt)
                g:Show()
                if not g.ag:IsPlaying() then g.ag:Play() end
            else
                if g.ag:IsPlaying() then g.ag:Stop() end
                g:Hide()
            end
        end
    end
end

-- Nilhammer / Voidforge progression. Confirmed via /oo nilscan: it's a ONE-TIME
-- build, not a weekly. Progress lives in two hidden turn-in trackers — Voidforge
-- unlock (3409, /6) then the Ascendant Nilhammer upgrade (3419, /4) — and quest
-- 95271 flags it permanently once forged. All pcall-guarded with a quest fallback
-- in case Blizzard retires the [DNT] trackers.
function OO:GetNilhammerState(repurpose)
    local function cur(id)
        local c
        pcall(function() c = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id) end)
        if c and (c.maxQuantity or 0) > 0 then return c.quantity or 0, c.maxQuantity end
    end
    local upC, upMax = cur(CUR_NILHAMMER_UPGRADE)   -- /4
    local unC, unMax = cur(CUR_VOIDFORGE_UNLOCK)    -- /6
    local forged = false
    pcall(function() forged = C_QuestLog.IsQuestFlaggedCompleted(QUEST_ASCENDANT_NILHAMMER) end)

    if forged or (upMax and upC >= upMax) then
        -- Only the BAR (repurpose=true) re-purposes to the live Nebulous Voidcore cap; the panel
        -- row shows the plain "forged" status so it doesn't duplicate Devouring Watch's bonus-rolls.
        if repurpose then
            local nbC, nbMax = cur(NEBULOUS_VOIDCORE)
            if nbMax and nbMax > 0 then
                return { done = false, cur = nbC, max = nbMax, frac = nbC / nbMax, hasObj = true, label = "Nebulous Voidcores", color = { 0.62, 0.28, 0.98, 0.62 } }
            end
        end
        return { done = true, cur = upMax or 1, max = upMax or 1, frac = 1, hasObj = (upMax ~= nil), label = "Ascendant Nilhammer forged", color = { 0.62, 0.28, 0.98, 0.62 } }
    end
    if upMax and upC > 0 then   -- upgrade stage in progress
        return { done = false, cur = upC, max = upMax, frac = upC / upMax, hasObj = true, label = "Forging the Nilhammer", color = { 0.98, 0.58, 0.16, 0.62 } }
    end
    if unMax and unC < unMax then   -- still building the Voidforge
        return { done = false, cur = unC, max = unMax, frac = unC / unMax, hasObj = true, label = "Building the Voidforge", color = { 0.32, 0.60, 0.98, 0.62 } }
    end
    if unMax and unC >= unMax then   -- forge built, upgrade not started
        return { done = false, cur = 0, max = upMax or 4, frac = 0, hasObj = true, label = "Forge the Nilhammer", color = { 0.85, 0.50, 0.18, 0.4 } }
    end
    -- Fallback (no tracker data): old permanent-quest behaviour
    local doneOld = false
    pcall(function() doneOld = C_QuestLog.IsQuestFlaggedCompleted(QUEST_ASCENDANT_NILHAMMER) end)
    if doneOld then return { done = true, cur = 1, max = 1, frac = 1, hasObj = false, label = "Ascendant Nilhammer forged", color = { 0.62, 0.28, 0.98, 0.62 } } end
    return { done = false, cur = 0, max = 1, frac = 0, hasObj = false, label = "Feed the Nilhammer", color = { 0.45, 0.20, 0.85, 0.5 } }
end

-- Ornate Voidhammer forge bar: a fill statusbar behind the chosen forge frame
-- art (forge1..5.tga), sitting at the panel bottom above the gem bar. Shows the
-- weekly Nilhammer feed. Built lazily, mirroring the gem bar.
-- (#2) Standalone, movable Nilhammer forge bar — its own draggable HUD frame
-- (left-drag to move unless locked; position saved in db.forgePos).
function OO:BuildForgeFrame()
    if self.forgeFrame then return end
    local W = 520
    local f = CreateFrame("Frame", "OOForgeFrame", UIParent)
    f:SetSize(W, 52)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not OO.db.locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)   -- save a folio-relative offset, like the docks
        s:StopMovingOrSizing()
        local folio = OO.folioFrame
        if folio then
            local fl, ft, gl, gt = s:GetLeft(), s:GetTop(), folio:GetLeft(), folio:GetTop()
            if fl and gl and ft and gt then
                OO.db.forgeDockPos = { x = fl - gl, y = ft - gt }
                s:ClearAllPoints(); s:SetPoint("TOPLEFT", folio, "TOPLEFT", fl - gl, ft - gt)
            end
        end
    end)
    -- Fill sits ABOVE the ornate frame art (sublevel 3 > 2) so the colored progress
    -- shows — the forge texture has an opaque centre, so a fill behind it is invisible.
    -- Translucent so the ornate texture still reads through the tint.
    -- Meter sits BEHIND the frame art (sublevels -1/0/1 < the frame's 2) so a frame with a
    -- proper transparent (masked) window reveals it. trough = dark backing, fill = colour, glow = pulse.
    local trough = f:CreateTexture(nil, "ARTWORK", nil, -1)
    trough:SetColorTexture(0.04, 0.02, 0.08, 0.55)
    f.trough = trough
    local fill = f:CreateTexture(nil, "ARTWORK", nil, 0)
    fill:SetColorTexture(0.45, 0.18, 0.85, 0.88)
    fill:SetPoint("LEFT", f, "LEFT", 24, 2)
    fill:SetHeight(24)
    -- pulsing additive glow over the fill (energy charge); coloured + sized in UpdateForge
    local glow = f:CreateTexture(nil, "ARTWORK", nil, 1)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetBlendMode("ADD")
    glow:Hide()
    local gag = glow:CreateAnimationGroup(); gag:SetLooping("BOUNCE")
    local ga = gag:CreateAnimation("Alpha"); ga:SetFromAlpha(0.1); ga:SetToAlpha(0.5); ga:SetDuration(0.85)
    glow.ag, glow.aAnim = gag, ga
    f.glow = glow
    local frame = f:CreateTexture(nil, "ARTWORK", nil, 2)
    frame:SetTexture(OO:ForgeTexPath())
    frame:SetAllPoints(f)
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    do local fp, _, fl = label:GetFont(); if fp then pcall(function() label:SetFont(fp, 14, fl) end) end end
    label:SetPoint("CENTER", f, "CENTER", 0, 1)
    f.fill, f.frameTex, f.label, f.W, f.inset = fill, frame, label, W, 24
    f:Hide()   -- shown/anchored by OnFolioShown (docked to the folio)
    self.forgeFrame = f
end

function OO:UpdateForge()
    if not self.forgeFrame or not self.forgeFrame:IsShown() then return end
    local fb = self.forgeFrame
    fb:SetScale(self.db.forgeScale or 1.0)
    fb.frameTex:SetTexture(OO:ForgeTexPath())
    local st = self:GetNilhammerState(true)   -- bar may repurpose to Nebulous once forged
    -- fill region is tunable so the coloured meter can be masked to any holder art
    local inset = self.db.forgeInset or 24
    fb.fill:ClearAllPoints()
    fb.fill:SetPoint("LEFT", fb, "LEFT", inset, self.db.forgeFillY or 2)
    fb.fill:SetHeight(self.db.forgeFillH or 24)
    local usable = fb.W - inset * 2
    fb.fill:SetWidth(math.max(1, usable * (st.frac or 0)))
    local txt, col = nil, (self.db.forgeFillColor and { self.db.forgeFillColor[1], self.db.forgeFillColor[2], self.db.forgeFillColor[3], 0.62 }) or st.color
    if st.done then
        txt = "|cFFFFD200" .. (st.label or "Nilhammer forged") .. "|r"
        col = col or { 0.62, 0.28, 0.98, 0.62 }
    elseif st.hasObj then
        txt = string.format("|cFFCCCCCC%s|r |cFFFFFFFF%d/%d|r", st.label or "Nilhammer", st.cur or 0, st.max or 1)
        col = col or { 0.42, 0.16, 0.82, 0.85 }
    else
        txt = "|cFFCCCCCC" .. (st.label or "Feed the Nilhammer") .. "|r"
        col = col or { 0.30, 0.12, 0.60, 0.7 }
    end
    local cr, cg, cb = col[1], col[2], col[3]
    -- (LSM) if a LibSharedMedia statusbar texture is chosen and LSM is loaded, use it; else solid fill.
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if self.db.forgeFillTex and lsm then
        fb.fill:SetTexture(lsm:Fetch("statusbar", self.db.forgeFillTex)); fb.fill:SetVertexColor(cr, cg, cb, 0.88)
    else
        fb.fill:SetColorTexture(cr, cg, cb, 0.88)
    end
    if fb.trough then   -- dark backing spanning the whole channel
        fb.trough:ClearAllPoints()
        fb.trough:SetPoint("LEFT", fb, "LEFT", inset, self.db.forgeFillY or 2)
        fb.trough:SetHeight(self.db.forgeFillH or 28)
        fb.trough:SetWidth(usable)
    end
    fb.label:SetText(txt)
    -- pulsing glow over the fill, coloured to match and sized to the fill
    local fg = self.db.forgeGlow or 0
    if fb.glow then
        if fg > 0 and (st.frac or 0) > 0 then
            fb.glow:ClearAllPoints()
            fb.glow:SetPoint("CENTER", fb.fill, "CENTER", 0, 0)
            fb.glow:SetSize(fb.fill:GetWidth() + 14, (self.db.forgeFillH or 28) + 14)
            fb.glow:SetVertexColor(cr, cg, cb)
            fb.glow.aAnim:SetFromAlpha(0.10 * fg); fb.glow.aAnim:SetToAlpha(0.55 * fg)
            fb.glow:Show()
            if not fb.glow.ag:IsPlaying() then fb.glow.ag:Play() end
        else
            if fb.glow.ag:IsPlaying() then fb.glow.ag:Stop() end
            fb.glow:Hide()
        end
    end
end

-- Style the pooled separators: glowing void-line art (divider1..5.tga) or, when
-- the art toggle is off, the original thin purple rule.
function OO:StyleSeps(panel)
    if not panel or not panel.sepPool then return end
    local art = self.db.dividerArt ~= false
    local pw = OO:PanelW(panel.frame)
    for _, sep in ipairs(panel.sepPool) do
        if art then
            sep:SetTexture(OO:DividerTexPath())
            sep:SetVertexColor(1, 1, 1, 1)
            sep:SetSize(pw - 24, self.db.dividerH or 10)
        else
            sep:SetColorTexture(0.45, 0.25, 0.75, 0.45)
            sep:SetSize(pw - 20, 1)
        end
    end
end

function OO:Refresh()
    local unlocked = self:GetWeeks().unlocked
    self:UpdateGemBar(self.panel, unlocked)
    self:UpdateGemBar(self.dockL, unlocked)
    self:UpdateForge()
    if self.panel and self.frame and self.frame:IsShown() then
        self:RenderLines(self.panel, self:BuildLines())
    end
    if self.dockL and self.dockL.frame:IsShown() then
        self:RenderLines(self.dockL, self:BuildLeftLines())
    end
    if self.dockR and self.dockR.frame:IsShown() then
        self:RenderLines(self.dockR, self:BuildRightLines())
    end
    if self.dockGuide and self.dockGuide.frame:IsShown() then
        self:RenderLines(self.dockGuide, self:BuildGuideLines())
    end
end

function OO:RenderLines(panel, lines)
    local frame   = panel.frame
    local headerH = panel.headerH or TITLE_H
    local fsize   = self.db.fontSize or 12
    local rowH    = fsize + 6
    local fontPath = select(1, GameFontHighlightSmall:GetFont())
    local sepIdx  = 1
    local lineIdx = 0
    local yOff    = 0

    for _, entry in ipairs(lines) do
        if entry == "sep" then
            local sep = panel.sepPool[sepIdx]
            if sep then
                sep:ClearAllPoints()
                sep:SetPoint("TOPLEFT", frame, "TOPLEFT", LINE_INSET + (self.db.textX or 0) + (self.db.dividerX or 0), -(headerH + yOff + rowH / 2) + (self.db.dividerY or 0))
                sep:Show()
                sepIdx = sepIdx + 1
                yOff = yOff + rowH / 2
            end
        else
            lineIdx = lineIdx + 1
            local text, tip = entry, nil
            if type(entry) == "table" then text, tip = entry.text, entry.tip end
            local fs = panel.linePool[lineIdx]
            if fs then
                if fontPath then pcall(function() fs:SetFont(fontPath, fsize, "") end) end
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", LINE_INSET + (self.db.textX or 0), -(headerH + yOff + 4))
                fs:SetText(text)
                fs:Show()
            end
            local hot = panel.hotPool and panel.hotPool[lineIdx]
            if hot then
                if tip then
                    hot:ClearAllPoints()
                    hot:SetPoint("TOPLEFT", frame, "TOPLEFT", LINE_INSET, -(headerH + yOff + 2))
                    hot:SetSize(math.max(10, (frame:GetWidth() or 100) - LINE_INSET * 2), rowH)
                    hot.tip = tip
                    hot:Show()
                else
                    hot.tip = nil; hot:Hide()
                end
            end
            yOff = yOff + rowH
        end
    end

    for i = lineIdx + 1, #panel.linePool do panel.linePool[i]:Hide() end
    if panel.hotPool then for i = lineIdx + 1, #panel.hotPool do panel.hotPool[i].tip = nil; panel.hotPool[i]:Hide() end end
    for i = sepIdx, #panel.sepPool do panel.sepPool[i]:Hide() end

    -- Reserve space at the bottom for the gem bar and/or forge bar so they never
    -- overlap the last content row (both anchor to the panel's bottom edge).
    local reserve = 0
    if panel.gems and self.db.gemBar ~= false then reserve = reserve + (self.db.gemSize or 26) + 6 end
    if reserve > 0 then reserve = reserve + 4 end

    local minH = OO:PanelMinH(frame)
    frame:SetHeight(math.max(headerH + yOff + PAD * 2 + reserve, minH))
end

function OO:SavePosition()
    if not self.frame then return end
    local x, y   = self.frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.x, self.db.y = x - ux, y - uy
    end
end

-- Opacity now affects ONLY the panel background (and watermark), so text and
-- icons stay fully crisp. Scale applies to the standalone panel.
function OO:ApplyAppearance()
    local bgA = self.db.alpha or 0.9
    local sc  = self.db.scale or 1.0
    local r, g, b = PALETTE.bg[1], PALETTE.bg[2], PALETTE.bg[3]
    local wmOn = self.db.watermark ~= false
    local skinOn = self.db.frameSkin ~= false   -- on by default (clean thin frames)
    local bannerOn = self.db.headerBanner ~= false
    local function apply(p)
        if not p or not p.frame then return end
        p.frame:SetAlpha(1)
        -- the standalone panel can carry its own opacity + frame settings, separate from the docks
        local isMain = (p == self.panel)
        local pAlpha = (isMain and self.db.mainAlpha) or self.db.alpha or 0.9
        local pSkinOn, pTex, pFrameA
        if isMain then
            pSkinOn = self.db.mainFrameSkin ~= false
            pTex = self.db.mainFrameTex or self.db.frameTex or 1
            pFrameA = self.db.mainFrameAlpha or self.db.frameAlpha or 1.0
        else
            pSkinOn, pTex, pFrameA = skinOn, (self.db.frameTex or 1), (self.db.frameAlpha or 1.0)
        end
        local pw = OO:PanelW(p.frame)
        p.frame.panelW = pw
        p.frame:SetWidth(pw)
        if p.linePool then for _, fs in ipairs(p.linePool) do fs:SetWidth(pw - LINE_INSET * 2) end end
        local tc = self.db.titleColor or { 1, 1, 1 }
        if p.frame.bannerTitle then p.frame.bannerTitle:SetTextColor(tc[1], tc[2], tc[3]) end
        if p.frame.title then p.frame.title:SetTextColor(tc[1], tc[2], tc[3]) end
        if p.frame.SetBackdropColor then p.frame:SetBackdropColor(0, 0, 0, 0) end   -- backdrop bg invisible; f.bg below is the real fill
        if p.frame.bg then
            -- per-edge fill: each side independently tucks UNDER the ornate bar (skin on),
            -- so an off-centre frame can be filled on one edge without spilling out another.
            local L, R, T, B = self.db.bgInsetL or 12, self.db.bgInsetR or 12, self.db.bgInsetT or 12, self.db.bgInsetB or 12
            if not pSkinOn then L, R, T, B = -3, -3, -3, -3 end
            p.frame.bg:ClearAllPoints()
            p.frame.bg:SetPoint("TOPLEFT", p.frame, "TOPLEFT", -L, T)
            p.frame.bg:SetPoint("BOTTOMRIGHT", p.frame, "BOTTOMRIGHT", R, -B)
            p.frame.bg:SetColorTexture(r, g, b, pAlpha)
        end
        if p.frame.skin then
            p.frame.skin:SetTexture(OO:FrameTexPath(pTex))   -- live frame-style swap (standalone can differ)
            OO:ApplySkinGeometry(p.frame, p.frame.skin)
            p.frame.skin:SetShown(pSkinOn)
            p.frame.skin:SetAlpha(pFrameA or 1.0)   -- frame/outline opacity, independent of bg
        end
        if p.frame.SetBackdropBorderColor then
            -- (#3) hide the plain tooltip border line when the ornate skin is on — it doubled
            -- up inside the frame and crowded the content; the skin becomes the sole border.
            local ba = pSkinOn and 0 or (pFrameA or 1.0)
            p.frame:SetBackdropBorderColor(PALETTE.border[1], PALETTE.border[2], PALETTE.border[3], ba)
        end
        if p.frame.mascotFrame then
            local mf = p.frame.mascotFrame
            local sz = self.db.logoSize or 74
            mf:SetSize(sz, sz)
            mf:SetShown(self.db.showMascot ~= false)
            mf:EnableMouse(self.db.mascotUndocked == true)
            mf:ClearAllPoints()
            if self.db.mascotUndocked and self.db.mascotPos then
                mf:SetPoint("TOPLEFT", p.frame, "TOPLEFT", self.db.mascotPos.x, self.db.mascotPos.y)
            else
                mf:SetPoint("BOTTOMLEFT", p.frame, "TOPLEFT", -6, 6)   -- top-left overhang; shows with or without the banner
            end
        end
        if p.frame.bannerFrame then
            local bf = p.frame.bannerFrame
            bf:SetSize(pw * (self.db.bannerW or 1.0), self.db.bannerH or 62)
            bf:ClearAllPoints()
            bf:SetPoint("BOTTOM", p.frame, "TOP", self.db.bannerX or 0, self.db.bannerY or -18)
            bf:SetShown(bannerOn)
            bf:SetAlpha(math.max(0.65, bgA))
            if p.frame.headerBanner then p.frame.headerBanner:SetTexture(OO:BannerTexPath()) end
        end
        if p.frame.title then p.frame.title:SetShown(not bannerOn) end   -- fallback title only when banner is off
        if p.frame.watermark then
            local ws = (self.db.watermarkScale or 0.42) * pw
            p.frame.watermark:SetSize(ws, ws)
            p.frame.watermark:SetAlpha(wmOn and (self.db.watermarkAlpha or 0.11) or 0)
        end
        OO:StyleSeps(p)
    end
    apply(self.panel)
    apply(self.dockL)
    apply(self.dockR)
    apply(self.dockGuide)
    if self.frame then self.frame:SetScale(sc) end
end

-- AceConfig options table (modelled on CDTL3): real dropdowns, LSM media pickers,
-- and clean tabbed groups, rendered by AceConfigDialog. Replaces the hand-rolled config.
-- Profile import/export via AceSerializer + LibDeflate (compact, shareable print-safe string).
function OO:ExportProfile()
    local Ser = LibStub("AceSerializer-3.0", true)
    local LD = LibStub("LibDeflate", true)
    if not (Ser and LD and self.dbObj) then return "" end
    local data = {}
    for k, v in pairs(self.dbObj.profile) do data[k] = v end
    return LD:EncodeForPrint(LD:CompressDeflate(Ser:Serialize(data), { level = 9 })) or ""
end

function OO:ImportProfile(str)
    local Ser = LibStub("AceSerializer-3.0", true)
    local LD = LibStub("LibDeflate", true)
    if not (Ser and LD) or type(str) ~= "string" or str:gsub("%s", "") == "" then return end
    local raw = LD:DecodeForPrint((str:gsub("%s", "")))
    raw = raw and LD:DecompressDeflate(raw)
    local ok, tbl = false, nil
    if raw then ok, tbl = Ser:Deserialize(raw) end
    if not ok or type(tbl) ~= "table" then
        print("|cFFFFCC00OmniumObservator|r import failed — check the copied string.")
        return
    end
    for k, v in pairs(tbl) do self.db[k] = v end
    self:ApplyAppearance(); self:Refresh()
    local ACR = LibStub("AceConfigRegistry-3.0", true)
    if ACR then ACR:NotifyChange("OmniumObservator") end
    print("|cFFFFCC00OmniumObservator|r profile imported.")
end

-- Custom AceGUI widget: a live, slowly-rotating 3D advisor model. AceConfig descriptions
-- honour `dialogControl`, so a General-tab option of type="description" + dialogControl=
-- "OOAdvisorModel" renders this 3D model (your chosen advisor) instead of a text label.
do
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if AceGUI then
        local Type, Version = "OOAdvisorModel", 1
        local function Constructor()
            local frame = CreateFrame("Frame", nil, UIParent)
            frame:Hide()
            local model = CreateFrame("PlayerModel", nil, frame)
            model:SetPoint("TOP", frame, "TOP", 0, -2)
            model:SetSize(200, 188)
            model:SetScript("OnUpdate", function(s, e)
                s._r = ((s._r or 0.4) + e * 0.35) % (math.pi * 2)
                pcall(function() s:SetFacing(s._r) end)
            end)
            local widget = { frame = frame, model = model, type = Type }
            widget.OnAcquire = function(self)
                self.frame:Show()
                self:SetHeight(196)
                pcall(function()
                    local m = self.model
                    m:ClearModel()
                    if OO.SetPreviewModel then OO:SetPreviewModel(m) end
                    m:SetPortraitZoom(0.06); m:SetFacing(0.4); m._r = 0.4
                end)
            end
            widget.OnRelease = function(self) self.frame:ClearAllPoints(); self.frame:Hide() end
            -- no-ops for whatever AceConfigDialog calls on a description-slot widget
            widget.SetText = function() end
            widget.SetImage = function() end
            widget.SetImageSize = function() end
            widget.SetFontObject = function() end
            widget.SetColor = function() end
            return AceGUI:RegisterAsWidget(widget)
        end
        AceGUI:RegisterWidgetType(Type, Constructor, Version)
    end
end

function OO:GetOptions()
    local db = OO.db
    local function get(info) return OO.db[info[#info]] end
    local function set(info, val) OO.db[info[#info]] = val; if info.arg then info.arg() end end
    local appear  = function() OO:ApplyAppearance() end
    local refresh = function() OO:ApplyAppearance(); OO:Refresh() end
    local folio   = function() OO:ApplyAppearance(); if OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end; OO:Refresh() end
    local styles  = { "Style 1", "Style 2", "Style 3", "Style 4", "Style 5" }
    local forgeStyles = { "Style 1", "Style 2", "Style 3", "Style 4", "Style 5", "Style 6", "Style 7", "Style 8", "Style 9", "Style 10" }
    -- texture-set pickers: set value, apply, then NotifyChange so the live preview image refreshes
    local function setTex(info, val) OO.db[info[#info]] = val; if info.arg then info.arg() end
        local ACR = LibStub("AceConfigRegistry-3.0", true); if ACR then ACR:NotifyChange("OmniumObservator") end end

    -- Profiles UI: AceDBOptions (select / new / copy / delete / reset) + import-export, inline in General.
    local profilesGroup
    do
        local ADBO = LibStub("AceDBOptions-3.0", true)
        if ADBO and OO.dbObj then
            profilesGroup = ADBO:GetOptionsTable(OO.dbObj)
            profilesGroup.inline = true
            profilesGroup.order = 90
            profilesGroup.name = "Profiles"
            profilesGroup.args.iohdr = { type = "header", order = 200, name = "Import / Export" }
            profilesGroup.args.export = { type = "input", order = 201, width = "full", multiline = 5,
                name = "Export this profile (copy the text)",
                get = function() return OO:ExportProfile() end, set = function() end }
            profilesGroup.args.import = { type = "input", order = 202, width = "full", multiline = 5,
                name = "Import a profile (paste, then accept)",
                get = function() return "" end, set = function(_, v) OO:ImportProfile(v) end }
        end
    end

    return {
        type = "group", name = "|cFFFFD200OmniumObservator|r", childGroups = "tab",
        args = {
            general = {
                type = "group", order = 1, name = "General",
                args = {
                    portrait = { type = "description", order = 0, name = "", width = "full", dialogControl = "OOAdvisorModel" },
                    thanks = { type = "description", order = 0.5, fontSize = "medium",
                        name = "|cFFFFD700Thank you for installing OmniumObservator!|r\nMade for fellow folio-delvers by |cFFC58CFFNelnamara|r — may your runes slot true and the storm weaken before you.\n" },
                    introH = { type = "header", order = 1, name = "Intro" },
                    intro = { type = "description", order = 2, fontSize = "medium",
                        name = "OmniumObservator embeds inside the Omnium Folio and tracks everything around it — your weekly rune unlocks, the Decimus Voidstorm economy (Motes, bonus rolls, Voidcores, live Void Assaults), the Nilhammer forge, recommended rune builds, and the weekly reset. It brings Decimus into the frame as a voiced 3D advisor, and the more you use it the more of the Void's cast you unlock. A standalone glance panel is there too, for a quick look without opening the folio.\n" },
                    cmdH = { type = "header", order = 3, name = "Commands" },
                    cmd = { type = "description", order = 4, fontSize = "medium",
                        name = "|cFFFFD200/oo|r  toggle the standalone glance panel\n|cFFFFD200/oo config|r  open these options\n|cFFFFD200/oo dock|r  toggle the in-folio docked panels\n|cFFFFD200/oo build <m+ | raid | dot | pvp | casual | method>|r  set the Counsel build\n|cFFFFD200/oo model|r · |cFFFFD200/oo voice|r  toggle the advisor model / its voice\n|cFFFFD200/oo font <8-20>|r · |cFFFFD200/oo frame <1-5>|r · |cFFFFD200/oo banner <1-6>|r  appearance shortcuts\n|cFFFFD200/oo lock|r · |cFFFFD200/oo unlock|r · |cFFFFD200/oo reset|r  frame dragging / reset positions\n" },
                    faqH = { type = "header", order = 5, name = "FAQ" },
                    faq = { type = "description", order = 6, fontSize = "medium",
                        name = "|cFFC58CFFPanels not showing?|r  Open the Omnium Folio — the panels embed inside it.\n|cFFC58CFFForge bar empty?|r  It fills as you build the Voidforge and forge the Ascendant Nilhammer.\n|cFFC58CFFWhere are the other advisors?|r  Earn Void favor (open the folio, progress weeks, forge the Nilhammer) to unlock them, then pick one under Omnium Advisors.\n|cFFC58CFFSettings per character?|r  Yes — each character keeps its own profile (Settings → Profiles), with import/export." },
                },
            },
            panels = {
                type = "group", order = 2, name = "Panels",
                args = {
                    locked = { type = "toggle", order = 1, name = "Lock panel positions", get = get, set = set },
                    dockEnabled = { type = "toggle", order = 2, name = "Embed panels in the folio", get = get, set = set, arg = folio },
                    resetPos = { type = "execute", order = 3, name = "Reset all panel positions", func = function()
                        db.x, db.y = 400, 200
                        db.dockLPos, db.dockRPos, db.dockGuidePos, db.forgeDockPos = nil, nil, nil, nil
                        if OO.frame then OO.frame:ClearAllPoints(); OO.frame:SetPoint("CENTER", UIParent, "CENTER", 400, 200) end
                        if OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end
                    end },
                    folioH = { type = "header", order = 4, name = "Folio" },
                    dockLWidth = { type = "range", order = 5, name = "Folio width", min = 200, max = 480, step = 2, get = get, set = set, arg = refresh },
                    dockLHeight = { type = "range", order = 6, name = "Folio height", desc = "0 = auto-fit content; higher pads the panel taller.", min = 0, max = 520, step = 5, get = get, set = set, arg = refresh },
                    weeksCollapsed = { type = "toggle", order = 7, name = "Collapse the weekly quest list", get = get, set = set, arg = refresh },
                    showMascot = { type = "toggle", order = 7.5, name = "Show mascot", get = get, set = set, arg = appear },
                    logoSize = { type = "range", order = 8, name = "Mascot size", min = 48, max = 110, step = 1, get = get, set = set, arg = appear },
                    mascotUndocked = { type = "toggle", order = 8.5, name = "Undock mascot (drag freely)", desc = "Detach the mascot from the banner so you can drag it; otherwise it sits at the panel's top-left.", get = get, set = set, arg = appear },
                    watermark = { type = "toggle", order = 9, name = "Watermark mascot", get = get, set = set, arg = appear },
                    watermarkScale = { type = "range", order = 10, name = "Watermark size", min = 0.12, max = 0.62, step = 0.01, get = get, set = set, arg = appear },
                    watermarkAlpha = { type = "range", order = 10.5, name = "Watermark opacity", min = 0, max = 0.5, step = 0.01, isPercent = true, get = get, set = set, arg = appear },
                    showNilhammer = { type = "toggle", order = 11, name = "Feeding the Nilhammer", get = get, set = set, arg = refresh },
                    showReset = { type = "toggle", order = 12, name = "Weekly reset timer", get = get, set = set, arg = refresh },
                    dwH = { type = "header", order = 13, name = "Devouring Watch" },
                    dockRWidth = { type = "range", order = 14, name = "Devouring Watch width", min = 200, max = 480, step = 2, get = get, set = set, arg = refresh },
                    dockRHeight = { type = "range", order = 15, name = "Devouring Watch height", min = 0, max = 520, step = 5, get = get, set = set, arg = refresh },
                    showMotes = { type = "toggle", order = 16, name = "Motes of Omnial Inquiry", get = get, set = set, arg = refresh },
                    showRolls = { type = "toggle", order = 17, name = "Nebulous bonus rolls", get = get, set = set, arg = refresh },
                    showVoidcores = { type = "toggle", order = 18, name = "Ascendant Voidcores", get = get, set = set, arg = refresh },
                    showVoidshard = { type = "toggle", order = 19, name = "Ascendant Voidshard", get = get, set = set, arg = refresh },
                    showAssaults = { type = "toggle", order = 20, name = "Void Assaults", get = get, set = set, arg = refresh },
                    counselH = { type = "header", order = 21, name = "Omnium Counsel" },
                    showGuide = { type = "toggle", order = 22, name = "Show Omnium Counsel panel", get = get, set = set, arg = folio },
                    dockGuideWidth = { type = "range", order = 23, name = "Counsel width", min = 200, max = 480, step = 2, get = get, set = set, arg = refresh },
                    dockGuideHeight = { type = "range", order = 24, name = "Counsel height", min = 0, max = 520, step = 5, get = get, set = set, arg = refresh },
                    standaloneH = { type = "header", order = 25, name = "Standalone Panel" },
                    showStandalone = { type = "toggle", order = 25.5, name = "Show standalone panel",
                        get = function() return OO.frame and OO.frame:IsShown() end,
                        set = function(_, v) if OO.frame then OO.frame:SetShown(v) end end },
                    scale = { type = "range", order = 26, name = "Standalone panel scale", min = 0.5, max = 2, step = 0.05, get = get, set = set, arg = appear },
                    mainWidth = { type = "range", order = 26.5, name = "Standalone width", min = 200, max = 480, step = 2, get = get, set = set, arg = refresh },
                    mainAlpha = { type = "range", order = 26.6, name = "Standalone opacity", desc = "Background opacity of the standalone panel (separate from the docks).", min = 0, max = 1, step = 0.01, isPercent = true, get = get, set = set, arg = appear },
                    mainFrameSkin = { type = "toggle", order = 26.7, name = "Standalone ornate frame", get = get, set = set, arg = appear },
                    mainFrameTex = { type = "select", order = 26.8, name = "Standalone frame style", values = styles, get = get, set = set, arg = appear },
                    mainFrameAlpha = { type = "range", order = 26.9, name = "Standalone frame opacity", min = 0, max = 1, step = 0.01, isPercent = true, get = get, set = set, arg = appear },
                    bgH = { type = "header", order = 27, name = "Background fill — per edge" },
                    alpha = { type = "range", order = 28, name = "Background opacity", desc = "Opacity of the panel background; text and icons stay solid.", min = 0, max = 1, step = 0.01, isPercent = true, get = get, set = set, arg = appear },
                    bgInsetL = { type = "range", order = 29, name = "Fill left", min = -24, max = 24, step = 1, get = get, set = set, arg = appear },
                    bgInsetR = { type = "range", order = 30, name = "Fill right", min = -24, max = 24, step = 1, get = get, set = set, arg = appear },
                    bgInsetT = { type = "range", order = 31, name = "Fill top", min = -24, max = 24, step = 1, get = get, set = set, arg = appear },
                    bgInsetB = { type = "range", order = 32, name = "Fill bottom", min = -24, max = 24, step = 1, get = get, set = set, arg = appear },
                    textH = { type = "header", order = 33, name = "Text" },
                    textX = { type = "range", order = 34, name = "Text offset (left / right)", desc = "Nudge the content text and dividers horizontally inside the panel.", min = -16, max = 40, step = 1, get = get, set = set, arg = refresh },
                    titleColor = { type = "color", order = 35, name = "Panel title colour", hasAlpha = false,
                        get = function() local c = db.titleColor or { 1, 1, 1 }; return c[1], c[2], c[3] end,
                        set = function(_, rr, gg, bb) db.titleColor = { rr, gg, bb }; OO:ApplyAppearance() end },
                    fontSize = { type = "range", order = 36, name = "Font size", min = 8, max = 20, step = 1, get = get, set = set, arg = refresh },
                },
            },
            appearance = {
                type = "group", order = 3, name = "Appearance",
                args = {
                    framesH = { type = "header", order = 1, name = "Custom panel frames" },
                    frameSkin = { type = "toggle", order = 2, name = "Ornate panel frames", get = get, set = set, arg = appear },
                    frameTex  = { type = "select", order = 3, name = "Frame style", values = styles, get = get, set = setTex, arg = appear },
                    framePrev = { type = "description", order = 3.5, name = "", width = "full", image = function() return OO:FrameTexPath(), 150, 150 end },
                    frameAlpha = { type = "range", order = 4, name = "Frame opacity", min = 0, max = 1, step = 0.01, isPercent = true, get = get, set = set, arg = appear },
                    skinOutset = { type = "range", order = 5, name = "Frame size", desc = "How far the ornate frame extends past the panel.", min = 0, max = 40, step = 1, get = get, set = set, arg = appear },
                    skinMargin = { type = "range", order = 6, name = "Frame thickness", desc = "9-slice corner size — higher for a chunkier border, lower for a thinner one.", min = 1, max = 128, step = 1, get = get, set = set, arg = appear },
                    skinOffsetY = { type = "range", order = 7, name = "Frame offset (up / down)", desc = "Nudge the frame art vertically to re-center an off-centre border.", min = -30, max = 30, step = 1, get = get, set = set, arg = appear },
                    skinOffsetX = { type = "range", order = 8, name = "Frame offset (left / right)", min = -30, max = 30, step = 1, get = get, set = set, arg = appear },
                    divsH = { type = "header", order = 9, name = "Dividers" },
                    dividerArt = { type = "toggle", order = 10, name = "Glowing dividers", get = get, set = set, arg = refresh },
                    dividerTex = { type = "select", order = 11, name = "Divider style", values = styles, get = get, set = setTex, arg = appear },
                    dividerPrev = { type = "description", order = 11.5, name = "", width = "full", image = function() return OO:DividerTexPath(), 320, 26 end },
                    dividerH = { type = "range", order = 12, name = "Divider thickness", min = 2, max = 40, step = 1, get = get, set = set, arg = appear },
                    dividerX = { type = "range", order = 13, name = "Divider offset (left/right)", min = -40, max = 40, step = 1, get = get, set = set, arg = refresh },
                    dividerY = { type = "range", order = 14, name = "Divider offset (up/down)", desc = "Nudge the dividers vertically, separate from the text.", min = -40, max = 40, step = 1, get = get, set = set, arg = refresh },
                    forgeH = { type = "header", order = 15, name = "Forge progress" },
                    forgeBar = { type = "toggle", order = 16, name = "Nilhammer/Voidcore forge bar", get = get, set = set, arg = folio },
                    forgeScale = { type = "range", order = 16.5, name = "Forge bar size", min = 0.5, max = 2.0, step = 0.05, isPercent = true, get = get, set = set, arg = refresh },
                    forgeTex = { type = "select", order = 17, name = "Forge bar style", values = forgeStyles, get = get, set = setTex, arg = refresh },
                    forgePrev = { type = "description", order = 17.6, name = "", width = "full", image = function() return OO:ForgeTexPath(), 340, 85 end },
                    forgeFillTex = { type = "select", order = 17.2, name = "Forge progress fill texture", desc = "A LibSharedMedia status-bar texture (blank = solid).",
                        dialogControl = "LSM30_Statusbar",
                        values = function() return (AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.statusbar) or {} end,
                        get = function() return db.forgeFillTex end,
                        set = function(_, v) db.forgeFillTex = v; OO:Refresh() end },
                    forgeFillColor = { type = "color", order = 19, name = "Forge progress fill colour", desc = "Overrides the per-stage fill colour.", hasAlpha = false,
                        get = function() local c = db.forgeFillColor or { 0.62, 0.28, 0.98 }; return c[1], c[2], c[3] end,
                        set = function(_, rr, gg, bb) db.forgeFillColor = { rr, gg, bb }; OO:Refresh() end },
                    forgeFillH = { type = "range", order = 20, name = "Forge progress fill height", min = 6, max = 60, step = 1, get = get, set = set, arg = refresh },
                    forgeFillY = { type = "range", order = 21, name = "Forge progress fill offset (up/down)", min = -24, max = 24, step = 1, get = get, set = set, arg = refresh },
                    forgeInset = { type = "range", order = 22, name = "Forge progress fill inset", desc = "Mask the coloured meter to your holder art's window.", min = 8, max = 80, step = 1, get = get, set = set, arg = refresh },
                    forgeGlow = { type = "range", order = 23, name = "Forge progress fill glow", min = 0, max = 1, step = 0.01, get = get, set = set, arg = refresh },
                    gemsH = { type = "header", order = 24, name = "Weekly quest progress" },
                    gemBar = { type = "toggle", order = 25, name = "Weekly quest progress gem bar", get = get, set = set, arg = refresh },
                    gemSize = { type = "range", order = 26, name = "Gem size", min = 14, max = 40, step = 1, get = get, set = set, arg = refresh },
                    gemGlow = { type = "range", order = 27, name = "Gem glow", min = 0, max = 1.5, step = 0.01, get = get, set = set, arg = refresh },
                    bannersH = { type = "header", order = 28, name = "Banners" },
                    headerBanner = { type = "toggle", order = 29, name = "Panel banners", get = get, set = set, arg = appear },
                    bannerTex = { type = "select", order = 30, name = "Banner style", values = styles, get = get, set = setTex, arg = appear },
                    bannerPrev = { type = "description", order = 30.5, name = "", width = "full", image = function() return OO:BannerTexPath(), 340, 64 end },
                    bannerH = { type = "range", order = 31, name = "Banner size", min = 44, max = 70, step = 1, get = get, set = set, arg = appear },
                    bannerW = { type = "range", order = 32, name = "Banner width", min = 0.5, max = 1.5, step = 0.01, get = get, set = set, arg = appear },
                    bannerY = { type = "range", order = 33, name = "Banner height offset", min = -40, max = 12, step = 1, get = get, set = set, arg = appear },
                },
            },
            advisors = {
                type = "group", order = 4, name = "Omnium Advisors",
                args = {
                    advisorH = { type = "header", order = 1, name = "Void Advisor" },
                    model = { type = "select", order = 2, name = "Available advisors  (use the addon to unlock more!)", width = "double",
                        values = function()
                            local t = {}
                            for i, e in ipairs(MODELS) do
                                if OO:ModelUnlocked(i) then t[i] = "|c" .. (RARITY_COLOR[e.rarity] or "FFFFFFFF") .. OO:ModelName(e) .. "|r" end
                            end
                            return t
                        end,
                        get = function() local i = db.modelChoice or 1; if not OO:ModelUnlocked(i) then i = 1 end; return i end,
                        set = function(_, v) if OO:ModelUnlocked(v) then db.modelChoice = v; OO:UpdateModel() end end },
                    showModel = { type = "toggle", order = 3, name = "Show advisor model",
                        get = get, set = function(_, v) db.showModel = v; if OO.folioFrame and OO.folioFrame:IsShown() then OO:UpdateModel() end end },
                    modelScale = { type = "range", order = 4, name = "Advisor size", min = 0.5, max = 2, step = 0.05,
                        get = get, set = function(_, v) db.modelScale = v; if OO.model then OO.model:SetSize(240 * v, 340 * v) end end },
                    decimusVoice = { type = "toggle", order = 5, name = "Decimus voice", get = get, set = set },
                    modelLocked = { type = "toggle", order = 6, name = "Lock advisor position", get = get, set = set },
                    resetModel = { type = "execute", order = 7, name = "Reset advisor position", func = function()
                        db.modelPos = nil; if OO.folioFrame and OO.folioFrame:IsShown() then OO:UpdateModel() end end },
                    favorH = { type = "header", order = 8, name = "Void Favor" },
                    favor = { type = "description", order = 9, fontSize = "medium", name = function()
                        return "|cFF8A8A8AVoid favor:|r |cFFFFD200" .. (db.decimusFavor or 0) .. "|r" end },
                    favorAboutH = { type = "header", order = 10, name = "What's Void favor?" },
                    favorAbout = { type = "description", order = 11, fontSize = "medium",
                        name = "Void favor is Decimus's regard for you — it unlocks new advisor models as it grows. Earn it by |cFFFFFFFFopening the folio daily|r, |cFFFFFFFFunlocking weekly runes|r, |cFFFFFFFFforging the Ascendant Nilhammer|r, the |cFFFFFFFFOmnium Folio Studies|r achievement, and the odd word with Decimus (capped per day). New servants appear in the dropdown above as you cross each threshold." },
                },
            },
            settings = {
                type = "group", order = 5, name = "Settings",
                args = {
                    minimap = { type = "toggle", order = 1, name = "Show minimap button",
                        get = function() return not db.minimapHide end,
                        set = function(_, v) db.minimapHide = not v; if OO.minimapBtn then OO.minimapBtn:SetShown(v) end end },
                    changelogH = { type = "header", order = 2, name = "Changelog" },
                    changelog = { type = "description", order = 3, fontSize = "medium",
                        name = "|cFFFFD200" .. (OO.version or "1.0.5") .. "|r — CDTL3-style AceConfig options · per-character profiles (with import / export) · themed art (frame / banner / divider / forge styles) · per-panel sizing · row & gem tooltips · Devouring Watch merge · favor-unlocked Decimus models · Ascendant Nilhammer / Voidforge tracking." },
                    profiles = profilesGroup,
                },
            },
        },
    }
end

-- Register the options table with AceConfig once the libs + db are ready.
function OO:SetupConfig()
    if self._configRegistered then return end
    local AC  = LibStub and LibStub("AceConfig-3.0", true)
    local ACD = LibStub and LibStub("AceConfigDialog-3.0", true)
    if not (AC and ACD) then return end
    AC:RegisterOptionsTable("OmniumObservator", function() return OO:GetOptions() end)
    self._blizCat = ACD:AddToBlizOptions("OmniumObservator", "OmniumObservator")   -- Esc > Options > AddOns
    ACD:SetDefaultSize("OmniumObservator", 640, 600)
    self._acd = ACD
    self._configRegistered = true
end

function OO:OpenConfig(blizzard)
    self:SetupConfig()
    if not self._acd then
        print("|cFFFF5555OmniumObservator|r: options UI unavailable (Ace3 libraries failed to load).")
        return
    end
    if blizzard and self._blizCat and Settings and Settings.OpenToCategory then
        local id = self._blizCat.GetID and self._blizCat:GetID() or self._blizCat
        if pcall(Settings.OpenToCategory, id) then return end
    end
    if self._acd.OpenFrames and self._acd.OpenFrames["OmniumObservator"] then
        self._acd:Close("OmniumObservator")
    else
        self._acd:Open("OmniumObservator")
    end
end

-- Minimap button — left-click toggles the panel, right-click dumps state, drag repositions.
local MM_RADIUS = 80
local function OOAngleOffset(a)
    return MM_RADIUS * math.cos(math.rad(a)), MM_RADIUS * math.sin(math.rad(a))
end

function OO:BuildMinimapButton()
    if self.minimapBtn then return end
    local db = self.db
    local btn = CreateFrame("Button", "OOMinimapButton", Minimap)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("AnyUp")

    -- Self-contained round icon (gold ring baked in) — SetAllPoints centers it cleanly.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\minimap.tga")

    btn:SetPoint("CENTER", Minimap, "CENTER", OOAngleOffset(db.minimapAngle or 225))

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFFFFCC00OmniumObservator|r " .. (OO.version or ""))
        GameTooltip:AddLine("Left-click: Toggle panel", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Options", 1, 1, 1)
        GameTooltip:AddLine("Drag: Reposition", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Tip: open the Omnium Folio to see the dock", 0.6, 0.9, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OO:OpenConfig()
        elseif OO.frame then
            OO.frame:SetShown(not OO.frame:IsShown())
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local angle = math.deg(math.atan2(py / s - my, px / s - mx))
            OO.db.minimapAngle = angle
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", OOAngleOffset(angle))
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    if db.minimapHide then btn:Hide() end
    self.minimapBtn = btn
end

-- (#6) Right-click the Blizzard "Omnium Folio" landing button to open our config.
-- Post-hook on OnMouseUp (fires for any button, no RegisterForClicks change), so it
-- never taints the protected landing button; left-click still opens the folio normally.
function OO:HookLandingButton()
    if self._landingHooked then return end
    local lb = _G.ExpansionLandingPageMinimapButton
    if not lb then return end
    self._landingHooked = true
    lb:HookScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then OO:OpenConfig() end
    end)
end

local ef = CreateFrame("Frame", "OOEventFrame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "OmniumObservator" then
            -- AceDB-backed settings: per-character profiles by default, with select/copy/delete and
            -- import/export. One-time per-character migration of tuned settings into the active profile.
            OO.dbObj = LibStub("AceDB-3.0"):New("OmniumObservatorDB", { profile = DEFAULTS })
            OO.db = OO.dbObj.profile
            if not OO.dbObj.char._migrated then
                local src = (OmniumObservatorCharDB and next(OmniumObservatorCharDB)) and OmniumObservatorCharDB or OmniumObservatorDB
                if type(src) == "table" then
                    local aceKeys = { profiles = true, profileKeys = true, global = true, char = true, namespaces = true, callbacks = true }
                    for k, v in pairs(src) do
                        if type(k) == "string" and k:sub(1, 1) ~= "_" and not aceKeys[k] then OO.db[k] = v end
                    end
                end
                OO.dbObj.char._migrated = true
            end
            local function onProfile()
                OO.db = OO.dbObj.profile
                OO:ApplyAppearance(); OO:Refresh()
                local ACR = LibStub("AceConfigRegistry-3.0", true)
                if ACR then ACR:NotifyChange("OmniumObservator") end
            end
            OO.dbObj.RegisterCallback(OO, "OnProfileChanged", onProfile)
            OO.dbObj.RegisterCallback(OO, "OnProfileCopied", onProfile)
            OO.dbObj.RegisterCallback(OO, "OnProfileReset", onProfile)
            OO:BuildUI()
            OO:BuildMinimapButton()
            OO:SetupConfig()    -- register the AceConfig options table (CDTL3-style)
            OO:ScheduleFolioHook()  -- in case the folio addon is already loaded
            OO:Refresh()
            self:RegisterEvent("ACHIEVEMENT_EARNED")
            self:RegisterEvent("CRITERIA_UPDATE")
            self:RegisterEvent("QUEST_LOG_UPDATE")
            self:RegisterEvent("PLAYER_LOGOUT")
        elseif name == "Blizzard_ExpansionLandingPage" then
            OO:ScheduleFolioHook()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if OO.db then OO:ScheduleFolioHook(); OO:HookLandingButton() end
        if C_Timer then C_Timer.After(4, function() OO._ready = true end) end   -- gate Decimus's greeting past login
    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_UPDATE" or event == "QUEST_LOG_UPDATE" then
        OO:CheckFavorSources()
        OO:Refresh()
    elseif event == "PLAYER_LOGOUT" then
        OO:SavePosition()
    end
end)

SLASH_OMNIUMOBSERVATOR1 = "/oo"
SlashCmdList["OMNIUMOBSERVATOR"] = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.*)")
    cmd = cmd:lower()
    if cmd == "questid" then
        -- Legacy override — the addon now auto-detects all 5 weekly quest IDs.
        -- This command is kept for troubleshooting only.
        local qid = tonumber(arg)
        if qid then
            OO.db.weeklyQuestID = qid
            print("|cFFFFCC00OmniumObservator|r manual quest ID override set to " .. qid)
            print("  Note: auto-detection is active. Override only needed if auto-detect fails.")
            OO:Refresh()
        else
            print("|cFFFFCC00OmniumObservator|r The addon auto-detects weekly quest progress.")
            print("  Known IDs: 96410 (wk1) 96441 (wk2) 96442 (wk3) 96443 (wk4) 96444 (wk5)")
        end
    elseif cmd == "dock" then
        OO.db.dockEnabled = not OO.db.dockEnabled
        print("|cFFFFCC00OmniumObservator|r folio dock " .. (OO.db.dockEnabled and "|cFF66FF66enabled|r" or "|cFFFF6666disabled|r"))
        if not OO.db.dockEnabled and OO.dockL then
            OO:OnFolioHidden()
        elseif OO.db.dockEnabled and OO.folioFrame and OO.folioFrame:IsShown() then
            OO:OnFolioShown()
        end
    elseif cmd == "folio" then
        print("|cFFFFCC00OmniumObservator|r folio frame path:")
        local elp = _G.ExpansionLandingPage
        print("  ExpansionLandingPage:", tostring(elp))
        local ov  = elp and elp.Overlay
        print("  .Overlay:", tostring(ov))
        local mlo = ov and ov.MidnightLandingOverlay
        print("  .MidnightLandingOverlay:", tostring(mlo))
        local rof = mlo and mlo.RunesOfPowerFrame
        print("  .RunesOfPowerFrame:", tostring(rof))
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            print("  Blizzard_ExpansionLandingPage loaded:", tostring(C_AddOns.IsAddOnLoaded("Blizzard_ExpansionLandingPage")))
        end
        OO:ScheduleFolioHook()
        print("  -> hooked:", tostring(OO.folioHooked), "configID:", tostring(OO.folioConfigID))
    elseif cmd == "runes" then
        -- Dump the purchased folio tree nodes -> rune spell IDs. Feeds the future
        -- "track whichever rune you've specced" readout. Open the folio once first.
        if not OO.folioConfigID then
            print("|cFFFFCC00OmniumObservator|r open the Omnium Folio once, then /oo runes")
            return
        end
        print(string.format("|cFFFFCC00OmniumObservator|r folio runes (config %s, tree %d):",
            tostring(OO.folioConfigID), FOLIO_TREE_ID))
        local ok = pcall(function()
            local nodes = C_Traits.GetTreeNodes(FOLIO_TREE_ID)
            for _, nodeID in ipairs(nodes) do
                local n = C_Traits.GetNodeInfo(OO.folioConfigID, nodeID)
                if n and (n.ranksPurchased or 0) > 0 then
                    local spellID, name
                    local entryID = n.activeEntry and n.activeEntry.entryID
                    if entryID then
                        local e = C_Traits.GetEntryInfo(OO.folioConfigID, entryID)
                        local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                        spellID = def and (def.overriddenSpellID or def.spellID)
                        local si = spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                        name = si and si.name
                    end
                    print(string.format("  node %s x%d -> spell %s %s",
                        tostring(nodeID), n.ranksPurchased, tostring(spellID), name or ""))
                end
            end
        end)
        if not ok then print("  (trait read failed)") end
    elseif cmd == "iconid" then
        local kind, idStr = (arg or ""):lower():match("^(%a+)%s+(%d+)$")
        local id = tonumber(idStr)
        if not (kind and id) then
            print("|cFFFFCC00OmniumObservator|r usage: /oo iconid <spell|item> <id>")
        else
            local tex
            if kind == "spell" and C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
            elseif kind == "item" and C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(id) end
            if tex then
                print(string.format("|cFFFFCC00OmniumObservator|r %s %d icon FileDataID = |cFFFFFFFF%s|r  |T%s:22|t",
                    kind, id, tostring(tex), tostring(tex)))
            else
                print("|cFFFFCC00OmniumObservator|r no icon for " .. kind .. " " .. id .. " (not cached yet? run it once more)")
            end
        end
    elseif cmd == "nilscan" then
        print("|cFFFFCC00OmniumObservator|r Nilhammer scan (paste this back):")
        local function objs(q)
            local o = C_QuestLog.GetQuestObjectives(q)
            if o then for _, b in ipairs(o) do
                print(string.format("      [%s/%s] %s  finished=%s type=%s",
                    tostring(b.numFulfilled), tostring(b.numRequired), tostring(b.text),
                    tostring(b.finished), tostring(b.type)))
            end end
        end
        for _, q in ipairs({ 95268, QUEST_FEEDING_NILHAMMER, QUEST_ASCENDANT_NILHAMMER }) do
            print(string.format("  Quest %d: done=%s logIdx=%s onQuest=%s", q,
                tostring(C_QuestLog.IsQuestFlaggedCompleted(q)),
                tostring(C_QuestLog.GetLogIndexForQuestID(q)),
                tostring(C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q))))
            objs(q)
        end
        print("  -- quest-log title matches --")
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local n = C_QuestLog.GetInfo(i)
            if n and not n.isHeader and n.title then
                local t = n.title:lower()
                if t:find("nilham") or t:find("obliv") or t:find("forg") or t:find("hunger") or t:find("ascend") then
                    print(string.format("    Q%d  %s", n.questID, n.title)); objs(n.questID)
                end
            end
        end
        print("  -- currency matches --")
        for id = 1, 3600 do
            local c = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
            if c and c.name and c.name ~= "" then
                local nm = c.name:lower()
                if nm:find("obliv") or nm:find("nilham") or nm:find("hunger") or nm:find("ascend") or nm:find("forg") then
                    print(string.format("    Cur %d  %s  qty=%s/%s thisWeek=%s",
                        id, c.name, tostring(c.quantity), tostring(c.maxQuantity),
                        tostring(c.quantityEarnedThisWeek)))
                end
            end
        end
        local hungering = 0
        pcall(function() hungering = C_Item.GetItemCount(269668, true, false, true, true) or 0 end)
        print(string.format("  Hungering Oblivium (item 269668) count = %d", hungering))
        if C_Spell and C_Spell.IsSpellKnown then
            print(string.format("  Weave/Transmute (spell 1283781) known = %s", tostring(C_Spell.IsSpellKnown(1283781))))
        end
        local st = OO:GetNilhammerState()
        print(string.format("  GetNilhammerState -> done=%s cur=%s max=%s frac=%.2f hasObj=%s",
            tostring(st.done), tostring(st.cur), tostring(st.max), st.frac or 0, tostring(st.hasObj)))
    elseif cmd == "debug" then
        print("|cFFFFCC00OmniumObservator|r " .. OO.version)
        local _, achName, _, achDone = GetAchievementInfo(ACH_OMNIUM_FOLIO)
        print(string.format("  Achievement %d (%s) completed=%s",
            ACH_OMNIUM_FOLIO, tostring(achName), tostring(achDone)))
        local weeks = OO:GetWeeks()
        print(string.format("  Weeks unlocked: %d/5  allDone=%s", weeks.unlocked, tostring(weeks.allDone)))
        for i, step in ipairs(weeks.steps) do
            print(string.format("  Week %d [%s] %s", i, step.done and "✓" or " ", step.name))
        end
        local ws = OO:GetWeeklyState()
        print(string.format("  Weekly state: week=%d name=%s inLog=%s done=%s allDone=%s nextReset=%s",
            ws.week or 0, ws.name or "?",
            tostring(ws.inLog), tostring(ws.done),
            tostring(ws.allDone), tostring(ws.nextReset)))
        print(string.format("  Folio: hooked=%s configID=%s motes=%s reset=%s",
            tostring(OO.folioHooked), tostring(OO.folioConfigID),
            tostring(OO:GetMotes()), tostring(OO:GetResetSeconds())))
        print(string.format("  Icons: neb=%s core=%s shard=%s",
            tostring(OO:CurrencyIcon(NEBULOUS_VOIDCORE)), tostring(OO:ItemIcon(ITEM_ASCENDANT_VOIDCORE)),
            tostring(OO:ItemIcon(ITEM_ASCENDANT_VOIDSHARD))))
        for _, q in ipairs(WEEKLY_QUESTS) do
            print(string.format("    Quest %d (wk%d): completed=%s",
                q.id, q.week, tostring(C_QuestLog.IsQuestFlaggedCompleted(q.id))))
        end
    elseif cmd == "config" or cmd == "options" then
        OO:OpenConfig((arg or ""):lower() == "blizzard")
    elseif cmd == "font" then
        local n = tonumber(arg)
        if n then
            OO.db.fontSize = math.max(8, math.min(20, math.floor(n)))
            OO:Refresh()
            print("|cFFFFCC00OmniumObservator|r font size " .. OO.db.fontSize)
        else
            print("|cFFFFCC00OmniumObservator|r usage: /oo font <8-20> (current " .. (OO.db.fontSize or 12) .. ")")
        end
    elseif cmd == "build" then
        if arg and arg ~= "" then
            local a = arg:lower()
            for i, b in ipairs(ROLE_BUILDS) do
                if b.role:lower():find(a, 1, true) then OO.db.guideRole = i end
            end
        else
            OO:CycleGuideRole(1)
        end
        OO:Refresh()
        OO.db.showGuide = true
        if OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end
        print("|cFFFFCC00OmniumObservator|r Counsel build: " .. (ROLE_BUILDS[OO.db.guideRole or 3].role))
    elseif cmd == "model" then
        local id = tonumber(arg)
        if (arg or ""):lower() == "next" then
            local idx = OO.db.modelChoice or 1
            for _ = 1, #MODELS do
                idx = idx % #MODELS + 1
                if OO:ModelUnlocked(idx) then break end
            end
            OO.db.modelChoice = idx
            OO.db.showModel = true
            OO:UpdateModel()
            local e = MODELS[idx]
            print("|cFFFFCC00OmniumObservator|r model -> |c" .. (RARITY_COLOR[e.rarity] or "FFFFFFFF") .. e.name .. "|r")
        elseif id then
            OO.db.showModel = true
            OO:UpdateModel(id)   -- temporary preview of a raw creature ID (dev/test)
            print("|cFFFFCC00OmniumObservator|r model -> creature " .. id .. " (temp preview; open the folio)")
        else
            OO.db.showModel = not OO.db.showModel
            OO:UpdateModel()
            print("|cFFFFCC00OmniumObservator|r Decimus model " .. (OO.db.showModel and "on (open folio: drag to rotate, scroll to zoom)" or "off"))
        end
    elseif cmd == "voice" then
        local id = tonumber(arg)
        if id then
            local willPlay = false
            pcall(function() willPlay = PlaySoundFile(id, "Dialog") end)
            print(string.format("|cFFFFCC00OmniumObservator|r sound %d willPlay=%s", id, tostring(willPlay)))
            if willPlay then
                local exists = false
                for _, s in ipairs(DECIMUS_SOUNDS) do if s == id then exists = true end end
                if not exists then DECIMUS_SOUNDS[#DECIMUS_SOUNDS + 1] = id end
                print("  added to Decimus's voice rotation (" .. #DECIMUS_SOUNDS .. " lines)")
            end
        else
            OO.db.decimusVoice = (OO.db.decimusVoice == false)
            print("|cFFFFCC00OmniumObservator|r Decimus voice " .. (OO.db.decimusVoice ~= false and "on" or "off"))
        end
    elseif cmd == "lock" then
        OO.db.locked = true
        print("|cFFFFCC00OmniumObservator|r locked.")
    elseif cmd == "unlock" then
        OO.db.locked = false
        print("|cFFFFCC00OmniumObservator|r unlocked.")
    elseif cmd == "border" or cmd == "skin" then
        -- Live-tune the void frame skin: /oo border <margin> <outset> | on | off
        local a1, a2 = (arg or ""):match("^(%S*)%s*(%S*)")
        if a1 == "off" then
            OO.db.frameSkin = false
            print("|cFFFFCC00OmniumObservator|r void frame skin OFF")
        elseif a1 == "on" or a1 == "" then
            OO.db.frameSkin = true
            print(string.format("|cFFFFCC00OmniumObservator|r void frame skin ON (margin=%d outset=%d). Tune: /oo border 60 18",
                OO.db.skinMargin or 48, OO.db.skinOutset or 14))
        else
            local m, o = tonumber(a1), tonumber(a2)
            if m then OO.db.skinMargin = m end
            if o then OO.db.skinOutset = o end
            OO.db.frameSkin = true
            print(string.format("|cFFFFCC00OmniumObservator|r skin margin=%d outset=%d", OO.db.skinMargin or 48, OO.db.skinOutset or 14))
        end
        for _, p in ipairs({ OO.panel, OO.dockL, OO.dockR, OO.dockGuide }) do
            if p and p.frame and p.frame.skin then OO:ApplySkinGeometry(p.frame, p.frame.skin) end
        end
        OO:ApplyAppearance()
    elseif cmd == "frame" then
        -- /oo frame <1-5>: switch the void frame style (border1..5.tga)
        local n = tonumber(arg)
        if n and n >= 1 and n <= 5 then
            OO.db.frameTex = math.floor(n); OO.db.frameSkin = true
            OO:ApplyAppearance()
            print("|cFFFFCC00OmniumObservator|r frame style " .. OO.db.frameTex .. "/5")
        else
            print("|cFFFFCC00OmniumObservator|r usage: /oo frame <1-5>")
        end
    elseif cmd == "banner" then
        OO.db.headerBanner = ((arg or ""):lower() ~= "off")
        OO:ApplyAppearance()
        print("|cFFFFCC00OmniumObservator|r header banner " .. (OO.db.headerBanner and "on" or "off"))
    elseif cmd == "reset" then
        OO.db.x, OO.db.y = 400, 200
        OO.frame:ClearAllPoints()
        OO.frame:SetPoint("CENTER", UIParent, "CENTER", 400, 200)
    else
        OO.frame:SetShown(not OO.frame:IsShown())
    end
end
