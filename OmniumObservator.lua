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

OO.version = "1.0.4"

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
local RUNE_VOID_ORBS   = 1279596  -- Rune of Void-Touched Orbs; player aura stacks 0-5
local NEBULOUS_VOIDCORE = 3418    -- bonus-roll currency (confirmed in-game via /oo scan)
local ITEM_ASCENDANT_VOIDCORE  = 268552  -- gear-upgrade item
local ITEM_ASCENDANT_VOIDSHARD = 268650  -- collected, forged into a Voidcore
local QUEST_FEEDING_NILHAMMER  = 95269   -- weekly: catalyze the Hungering Oblivium
local NPC_DECIMUS              = 235697   -- Domanaar Decimus (for the 3D model)

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

-- Decimus voice-over FileDataIDs (Wowhead sound=NNNNN -> playable via PlaySoundFile).
-- Pattern: VO_120_Decimus_NN_M. Add more IDs from Wowhead's Decimus "Sounds" tab.
local DECIMUS_SOUNDS = { 327617 }

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
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Overload", RUNE_IDS.overload },
    } },
    { role = "Raid ST |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Echoes", RUNE_IDS.echoes },
    } },
    { role = "Raid DoT |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Residual Energy", RUNE_IDS.residual },
    } },
    { role = "PvP |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Def",  "Lynxlike Reflexes", RUNE_IDS.lynx },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "Versatility", nil },
        { "Cap",  "Overload", RUNE_IDS.overload },
    } },
    { role = "Casual |cFF888888· Guide|r", tiers = {
        { "Core", "Void-Touched Orbs", RUNE_IDS.orbs },
        { "Def",  "Self-Mending", RUNE_IDS.mend },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "Versatility", nil },
        { "Cap",  "Overload", RUNE_IDS.overload },
    } },
    { role = "DPS |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Overload", RUNE_IDS.overload },
    } },
    { role = "M+ |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Echoes", RUNE_IDS.echoes },
    } },
    { role = "Raid DoT |cFF54A3FF· Method.gg|r", tiers = {
        { "Core", "Unleashed Fire", RUNE_IDS.fire },
        { "Def",  "Void-Tainted Shell", RUNE_IDS.shell },
        { "Ling", "Lingering", RUNE_IDS.lingering },
        { "Stat", "spec priority", nil },
        { "Cap",  "Residual Energy", RUNE_IDS.residual },
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
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local DEFAULTS = {
    x            =  400,
    y            =  200,
    scale        = 1.0,
    locked       = false,
    alpha        = 0.9,
    weeklyQuestID = nil,
    minimapAngle = 225,
    minimapHide  = false,
    dockEnabled  = true,
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

-- Returns the current Void-Touched Orb count (0-5) if the rune's aura is up, else nil.
function OO:GetVoidOrbs()
    if not C_UnitAuras then return nil end
    -- aura.applications could be a secret value if execution is tainted; read it
    -- inside a pcall and only keep it once it survives a numeric compare (real
    -- number). On failure we return nil so the orb line is simply hidden.
    local n
    pcall(function()
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(RUNE_VOID_ORBS)
        if aura then
            local a = aura.applications or 0
            if a >= 0 then n = a end
        end
    end)
    return n
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

-- Builds a backdrop panel (branded) with a header (optional logo) + title, a
-- divider, and pooled line/separator widgets. Returns { frame, linePool, sepPool }.
-- Shared by the standalone panel and the two embedded folio panels.
function OO:CreatePanel(name, strata, titleText, showLogo)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    local headerH = showLogo and 52 or TITLE_H
    f:SetSize(FRAME_W, headerH + ROW_H * 9 + PAD * 2)
    f:SetFrameStrata(strata or "MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(unpack(PALETTE.bg))
    f:SetBackdropBorderColor(unpack(PALETTE.border))

    -- Faint mascot watermark embedded in the panel body (low alpha, corner).
    local mark = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    mark:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\mascot.png")
    mark:SetSize(96, 96)
    mark:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    mark:SetAlpha(0.07)
    f.watermark = mark

    local title = f:CreateFontString(nil, "OVERLAY", showLogo and "GameFontNormalLarge" or "GameFontNormalSmall")
    if showLogo then
        -- Larger mascot portrait (the high-res CurseForge art) in the header.
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetSize(44, 44)
        logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -4)
        logo:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\mascot.png")
        title:SetPoint("LEFT", logo, "RIGHT", 7, 0)
    else
        title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -5)
    end
    title:SetText(titleText or ("|c" .. PALETTE.title .. "OmniumObservator|r"))

    local divider = f:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(FRAME_W - 16, 1)
    divider:SetPoint("TOP", f, "TOP", 0, -(headerH - 2))
    divider:SetColorTexture(PALETTE.divider[1], PALETTE.divider[2], PALETTE.divider[3], PALETTE.divider[4])

    local panel = { frame = f, linePool = {}, sepPool = {}, headerH = headerH }
    for i = 1, 20 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -(headerH + (i - 1) * ROW_H + 4))
        fs:SetWidth(FRAME_W - PAD * 2 - 4)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        panel.linePool[i] = fs
    end
    for i = 1, 8 do
        local sep = f:CreateTexture(nil, "BACKGROUND")
        sep:SetSize(FRAME_W - 20, 1)
        sep:SetColorTexture(0.45, 0.25, 0.75, 0.45)
        sep:Hide()
        panel.sepPool[i] = sep
    end
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
    self.dockR = self:CreatePanel("OODockRight", "HIGH", "|c" .. PALETTE.title .. "Voidstorm|r", false)
    self.dockGuide = self:CreatePanel("OODockGuide", "HIGH", "|c" .. PALETTE.title .. "Decimus's Counsel|r", false)
    self:MakeDockDraggable(self.dockL, "dockLPos")
    self:MakeDockDraggable(self.dockR, "dockRPos")
    self:MakeDockDraggable(self.dockGuide, "dockGuidePos")
    self:AddCollapseButton(self.dockL)
    -- [>] role-cycle button on the Counsel panel
    local rb = CreateFrame("Button", nil, self.dockGuide.frame)
    rb:SetSize(20, 20)
    rb:SetPoint("TOPRIGHT", self.dockGuide.frame, "TOPRIGHT", -6, -3)
    rb:SetFrameLevel(self.dockGuide.frame:GetFrameLevel() + 5)
    local rt = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rt:SetAllPoints()
    rt:SetText(">")
    rb:SetScript("OnClick", function() OO:CycleGuideRole(1) end)
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

-- A small [+]/[-] in the header that collapses/expands the weekly list.
function OO:AddCollapseButton(panel)
    local b = CreateFrame("Button", nil, panel.frame)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -6, -3)
    b:SetFrameLevel(panel.frame:GetFrameLevel() + 5)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetAllPoints()
    t:SetText(OO.db.weeksCollapsed and "+" or "-")
    b.text = t
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
    rof:HookScript("OnShow", function() OO:OnFolioShown() end)
    rof:HookScript("OnHide", function() OO:OnFolioHidden() end)
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
    -- The embed is the single source of info while the folio is open — hide the
    -- standalone panel (if it was up) and restore it when the folio closes.
    if self.frame and self.frame:IsShown() then
        self._frameWasShown = true
        self.frame:Hide()
    end
    self:ApplyAppearance()
    self:Refresh()
    self:UpdateModel()
    -- let the model load, then Decimus greets you with a random line
    if self.db.showModel and C_Timer then
        C_Timer.After(0.8, function() OO:DecimusSpeak(false) end)
    end
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
    if self.model then self.model:Hide() end
    if self._frameWasShown then
        self._frameWasShown = false
        if self.frame then self.frame:Show() end
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
        m:SetSize(190, 270)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:EnableMouseWheel(true)
        m:RegisterForDrag("RightButton")
        m.facing, m.zoom = 0.45, 0

        -- Speech bubble above his head.
        local bubble = CreateFrame("Frame", nil, m, "BackdropTemplate")
        bubble:SetPoint("BOTTOM", m, "TOP", 0, -2)
        bubble:SetSize(200, 56)
        bubble:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        bubble:SetBackdropColor(0.05, 0.02, 0.10, 0.94)
        bubble:SetBackdropBorderColor(unpack(PALETTE.border))
        local bt = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bt:SetPoint("TOPLEFT", 7, -6)
        bt:SetPoint("BOTTOMRIGHT", -7, 6)
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
        m:SetScript("OnDragStart", function(s) s:StartMoving() end)
        m:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); OO:SaveModelPos() end)
        m:SetScript("OnModelLoaded", function(s)
            pcall(function() s:SetPortraitZoom(s.zoom or 0); s:SetFacing(s.facing or 0.45) end)
        end)
        self.model = m
    end
    local m = self.model
    local ms = self.db.modelScale or 1.0
    m:SetSize(190 * ms, 270 * ms)
    m:ClearAllPoints()
    local mp = self.db.modelPos
    if mp then m:SetPoint("BOTTOMLEFT", self.folioFrame, "BOTTOMLEFT", mp.x, mp.y)
    else m:SetPoint("BOTTOMLEFT", self.folioFrame, "BOTTOMLEFT", 36, 30) end
    pcall(function()
        m:SetCreature(creatureOverride or NPC_DECIMUS)
        m:SetPortraitZoom(m.zoom or 0)
        m:SetFacing(m.facing or 0.45)
    end)
    m:Show()
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
    local pool = rare and DECIMUS_RARE or DECIMUS_QUOTES
    local line = pool[math.random(#pool)]:gsub("<name>", UnitName("player") or "lightling")
    m.bubbleText:SetText(line)
    m.bubble:SetBackdropBorderColor(rare and 0.85 or PALETTE.border[1], rare and 0.20 or PALETTE.border[2], rare and 1.0 or PALETTE.border[3], 1)
    m.bubble:Show()
    pcall(function() m:SetAnimation(rare and 64 or 60) end)
    -- Play his actual voice-over (FileDataID via PlaySoundFile), if enabled.
    if self.db.decimusVoice ~= false and PlaySoundFile and #DECIMUS_SOUNDS > 0 then
        pcall(function() PlaySoundFile(DECIMUS_SOUNDS[math.random(#DECIMUS_SOUNDS)], "Dialog") end)
    end
    if self._speakTimer then self._speakTimer:Cancel() end
    self._speakTimer = C_Timer.NewTimer(rare and 8 or 5, function()
        if m.bubble then m.bubble:Hide() end
        pcall(function() m:SetAnimation(0) end)
    end)
end

-- Click handler with a hidden easter egg: 7 quick clicks unlocks a rare line.
function OO:DecimusClicked()
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

-- Standalone "detached" panel mirrors the embed: the left (weeks / tasks / reset)
-- and right (Voidstorm resources) content combined into one panel, same theme.
function OO:BuildLines()
    local lines = self:BuildLeftLines()
    lines[#lines + 1] = "sep"
    for _, l in ipairs(self:BuildRightLines()) do
        lines[#lines + 1] = l
    end
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
        for i, step in ipairs(weeks.steps) do
            local color = WEEK_COLORS[i] or "FFCCCCCC"
            lines[#lines + 1] = string.format("%s |c%s%s|r", Check(step.done), color, step.name)
        end
    end

    lines[#lines + 1] = "sep"
    if ws.allDone then
        lines[#lines + 1] = "|cFF66FF66Folio fully unlocked!|r"
    elseif ws.inLog then
        lines[#lines + 1] = string.format("|cFFFFDD88This week: %s — in progress|r", ws.name)
    elseif ws.nextReset then
        lines[#lines + 1] = string.format("|c" .. PALETTE.dim .. "Next: %s (next reset)|r", ws.name)
    else
        lines[#lines + 1] = string.format("|c" .. PALETTE.dim .. "Start: %s (Silvermoon)|r", ws.name)
    end

    -- Feeding the Nilhammer weekly (Voidforge progression)
    local nilDone = false
    pcall(function() nilDone = C_QuestLog.IsQuestFlaggedCompleted(QUEST_FEEDING_NILHAMMER) end)
    lines[#lines + 1] = string.format("%s |cFFCCCCCCFeeding the Nilhammer|r", Check(nilDone))

    if reset then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.dim .. "Weekly reset in|r |cFFFFFFFF%s|r", FmtDur(reset))
    end
    return lines
end

-- Right embedded panel: Voidstorm currencies, Ascendant items, and orbs.
function OO:BuildRightLines()
    local lines = {}
    local motes = self:GetMotes()
    lines[#lines + 1] = string.format(
        "|c" .. PALETTE.gold .. "Motes:|r |cFFFFFFFF%s|r", motes and tostring(motes) or "—")
    local neb, nebMax = self:GetCurrency(NEBULOUS_VOIDCORE)
    local nebStr = neb and tostring(neb) or "—"
    if neb and nebMax and nebMax > 0 then nebStr = neb .. "|c" .. PALETTE.dim .. "/" .. nebMax .. "|r" end
    lines[#lines + 1] = string.format(
        "%s|c" .. PALETTE.purple .. "Bonus rolls:|r |cFFFFFFFF%s|r |c" .. PALETTE.dim .. "(Nebulous)|r",
        IconTag(self:CurrencyIcon(NEBULOUS_VOIDCORE)), nebStr)

    lines[#lines + 1] = "sep"
    local cores = self:GetItem(ITEM_ASCENDANT_VOIDCORE)
    lines[#lines + 1] = string.format(
        "%s|c" .. PALETTE.purple .. "Ascendant Voidcores:|r |cFFFFFFFF%s|r",
        IconTag(self:ItemIcon(ITEM_ASCENDANT_VOIDCORE)), cores and tostring(cores) or "0")
    local shards = self:GetItem(ITEM_ASCENDANT_VOIDSHARD)
    lines[#lines + 1] = string.format(
        "%s|c" .. PALETTE.purple .. "Ascendant Voidshard:|r |cFFFFFFFF%s|r",
        IconTag(self:ItemIcon(ITEM_ASCENDANT_VOIDSHARD)), shards and tostring(shards) or "0")

    -- Void-Touched Orbs: only shown when the rune is actually active (its aura is
    -- present = you're specced into it). When the slotted-rune readout lands this
    -- becomes "whichever resource rune you've chosen in the tree".
    local orbs = self:GetVoidOrbs()
    if orbs then
        lines[#lines + 1] = "sep"
        lines[#lines + 1] = string.format(
            "%s|c" .. PALETTE.purple .. "Void-Touched Orbs:|r |cFFFFFFFF%d|r|c" .. PALETTE.dim .. "/5|r",
            IconTag(self:SpellIcon(RUNE_VOID_ORBS)), orbs)
    end
    return lines
end

-- "Decimus's Counsel" — role-based recommended build, click the header [>] to cycle.
function OO:BuildGuideLines()
    local b = ROLE_BUILDS[self.db.guideRole or 3] or ROLE_BUILDS[1]
    local lines = {}
    lines[#lines + 1] = string.format(
        "|c" .. PALETTE.gold .. "Best for:|r |cFFFFFFFF%s|r  |c" .. PALETTE.dim .. "[ > ]|r", b.role)
    lines[#lines + 1] = "sep"
    for _, t in ipairs(b.tiers) do
        local icon = t[3] and IconTag(self:SpellIcon(t[3])) or ""
        lines[#lines + 1] = string.format("%s|c" .. PALETTE.purple .. "%s:|r |cFFFFFFFF%s|r",
            icon, t[1], t[2])
    end
    return lines
end

function OO:CycleGuideRole(dir)
    local n = #ROLE_BUILDS
    self.db.guideRole = ((self.db.guideRole or 3) - 1 + (dir or 1)) % n + 1
    self:Refresh()
end

function OO:Refresh()
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
                sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, -(headerH + yOff + rowH / 2))
                sep:Show()
                sepIdx = sepIdx + 1
                yOff = yOff + rowH / 2
            end
        else
            lineIdx = lineIdx + 1
            local fs = panel.linePool[lineIdx]
            if fs then
                if fontPath then pcall(function() fs:SetFont(fontPath, fsize, "") end) end
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(headerH + yOff + 4))
                fs:SetText(entry)
                fs:Show()
                yOff = yOff + rowH
            end
        end
    end

    for i = lineIdx + 1, #panel.linePool do panel.linePool[i]:Hide() end
    for i = sepIdx, #panel.sepPool do panel.sepPool[i]:Hide() end

    frame:SetHeight(headerH + yOff + PAD * 2)
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
    local function apply(p)
        if not p or not p.frame then return end
        p.frame:SetAlpha(1)
        if p.frame.SetBackdropColor then p.frame:SetBackdropColor(r, g, b, bgA) end
        if p.frame.watermark then p.frame.watermark:SetAlpha(wmOn and (0.07 * bgA) or 0) end
    end
    apply(self.panel)
    apply(self.dockL)
    apply(self.dockR)
    apply(self.dockGuide)
    if self.frame then self.frame:SetScale(sc) end
end

local function OOConfigCheck(parent, label, x, y, checked, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetChecked(checked)
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(s) onClick(s:GetChecked() and true or false) end)
    return cb
end

local function OOConfigSlider(parent, name, label, lowTxt, highTxt, lo, hi, val, y, onChange)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(230)
    s:SetPoint("TOP", 0, y)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(0.05)
    s:SetObeyStepOnDrag(true)
    s:SetValue(val)
    -- Region names vary across client versions — guard so a missing one can't
    -- error out of BuildConfig (which left a half-built, unclosable frame).
    local low  = _G[name .. "Low"]  or s.Low
    local high = _G[name .. "High"] or s.High
    local text = _G[name .. "Text"] or s.Text
    if low  then low:SetText(lowTxt) end
    if high then high:SetText(highTxt) end
    if text then text:SetText(label) end
    s:SetScript("OnValueChanged", function(_, v) onChange(v) end)
    return s
end

-- Simple options panel (no Ace): opacity, scale, lock, dock + minimap toggles.
function OO:BuildConfig()
    if self.config then self.config:Show(); return end
    local f = CreateFrame("Frame", "OOConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(310, 430)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnHide", function(s) s:StopMovingOrSizing() end)
    -- Escape closes it (guaranteed close path — the old build could get stuck).
    tinsert(UISpecialFrames, "OOConfigFrame")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(unpack(PALETTE.bg))
    f:SetBackdropBorderColor(unpack(PALETTE.border))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|c" .. PALETTE.title .. "OmniumObservator|r options")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    OOConfigSlider(f, "OOConfigOpacity", "Background opacity", "0%", "100%", 0.0, 1.0, self.db.alpha or 0.9, -52,
        function(v) OO.db.alpha = v; OO:ApplyAppearance() end)
    OOConfigSlider(f, "OOConfigScale", "Scale (standalone)", "70%", "150%", 0.7, 1.5, self.db.scale or 1.0, -98,
        function(v) OO.db.scale = v; OO:ApplyAppearance() end)
    OOConfigSlider(f, "OOConfigModel", "Decimus size", "S", "L", 0.5, 2.0, self.db.modelScale or 1.0, -144,
        function(v) OO.db.modelScale = v; if OO.model then OO.model:SetSize(190 * v, 270 * v) end end)

    -- Reset Decimus to his default spot
    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(120, 18)
    reset:SetPoint("TOP", 0, -178)
    reset:SetText("Reset Decimus pos")
    reset:SetScript("OnClick", function()
        OO.db.modelPos = nil
        if OO.folioFrame and OO.folioFrame:IsShown() then OO:UpdateModel() end
    end)

    OOConfigCheck(f, "Lock position", 28, -206, self.db.locked, function(v) OO.db.locked = v end)
    OOConfigCheck(f, "Folio dock enabled", 28, -232, self.db.dockEnabled, function(v)
        OO.db.dockEnabled = v
        if not v then OO:OnFolioHidden()
        elseif OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end
    end)
    OOConfigCheck(f, "Show Decimus model", 28, -258, self.db.showModel, function(v)
        OO.db.showModel = v
        if OO.folioFrame and OO.folioFrame:IsShown() then OO:UpdateModel() end
    end)
    OOConfigCheck(f, "Decimus voice (plays his lines)", 28, -284, self.db.decimusVoice ~= false, function(v)
        OO.db.decimusVoice = v
    end)
    OOConfigCheck(f, "Show rune guide (Decimus's Counsel)", 28, -310, self.db.showGuide, function(v)
        OO.db.showGuide = v
        if OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end
    end)
    OOConfigCheck(f, "Body watermark", 28, -336, self.db.watermark ~= false, function(v)
        OO.db.watermark = v
        OO:ApplyAppearance()
    end)
    OOConfigCheck(f, "Show minimap button", 28, -362, not self.db.minimapHide, function(v)
        OO.db.minimapHide = not v
        if OO.minimapBtn then OO.minimapBtn:SetShown(v) end
    end)

    self.config = f
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
    icon:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\minimap.png")

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
            OO:BuildConfig()
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

local ef = CreateFrame("Frame", "OOEventFrame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "OmniumObservator" then
            if not OmniumObservatorDB then OmniumObservatorDB = CopyTable(DEFAULTS) end
            OO.db = OmniumObservatorDB
            for k, v in pairs(DEFAULTS) do
                if OO.db[k] == nil then OO.db[k] = v end
            end
            OO:BuildUI()
            OO:BuildMinimapButton()
            OO:ScheduleFolioHook()  -- in case the folio addon is already loaded
            OO:Refresh()
            self:RegisterEvent("ACHIEVEMENT_EARNED")
            self:RegisterEvent("CRITERIA_UPDATE")
            self:RegisterEvent("QUEST_LOG_UPDATE")
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("PLAYER_LOGOUT")
        elseif name == "Blizzard_ExpansionLandingPage" then
            OO:ScheduleFolioHook()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if OO.db then OO:ScheduleFolioHook() end
    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_UPDATE" or event == "QUEST_LOG_UPDATE" then
        OO:Refresh()
    elseif event == "UNIT_AURA" then
        if ... == "player" then
            local now = GetTime()
            if now - (OO.lastAuraRefresh or 0) > 0.2 then
                OO.lastAuraRefresh = now
                OO:Refresh()
            end
        end
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
        print(string.format("  Folio: hooked=%s configID=%s motes=%s reset=%s orbs=%s",
            tostring(OO.folioHooked), tostring(OO.folioConfigID),
            tostring(OO:GetMotes()), tostring(OO:GetResetSeconds()), tostring(OO:GetVoidOrbs())))
        print(string.format("  Icons: neb=%s core=%s shard=%s orb=%s",
            tostring(OO:CurrencyIcon(NEBULOUS_VOIDCORE)), tostring(OO:ItemIcon(ITEM_ASCENDANT_VOIDCORE)),
            tostring(OO:ItemIcon(ITEM_ASCENDANT_VOIDSHARD)), tostring(OO:SpellIcon(RUNE_VOID_ORBS))))
        for _, q in ipairs(WEEKLY_QUESTS) do
            print(string.format("    Quest %d (wk%d): completed=%s",
                q.id, q.week, tostring(C_QuestLog.IsQuestFlaggedCompleted(q.id))))
        end
    elseif cmd == "config" or cmd == "options" then
        OO:BuildConfig()
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
        if id then
            OO.db.showModel = true
            OO:UpdateModel(id)
            print("|cFFFFCC00OmniumObservator|r model -> creature " .. id .. " (open the folio; drag to rotate, scroll to zoom)")
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
    elseif cmd == "reset" then
        OO.db.x, OO.db.y = 400, 200
        OO.frame:ClearAllPoints()
        OO.frame:SetPoint("CENTER", UIParent, "CENTER", 400, 200)
    else
        OO.frame:SetShown(not OO.frame:IsShown())
    end
end
