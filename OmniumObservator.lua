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

-- Suite branding palette (purple / gold / black)
local PALETTE = {
    bg     = { 0.04, 0.02, 0.07, 0.92 },  -- near-black with a faint purple cast
    border = { 1.00, 0.82, 0.00, 0.90 },  -- gold
    title  = "FFFFD200",                   -- gold (title text colour code)
    gold   = "FFFFD700",
    purple = "FFBB66FF",
    dim    = "FF888888",
}

-- The 5 weeks light up in WoW loot-rarity colours as they're unlocked:
-- common(white) → uncommon(green) → rare(blue) → epic(purple) → legendary(orange).
local WEEK_COLORS = { "FFFFFFFF", "FF1EFF00", "FF0070DD", "FFA335EE", "FFFF8000" }
local WEEK_DIM    = "FF555555"

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

-- Generic currency quantity by ID (pcall-guarded). Used for Nebulous Voidcore etc.
function OO:GetCurrency(id)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local q
    pcall(function()
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.quantity then q = info.quantity end
    end)
    return q
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

-- Inline texture escape for a fileID (real game icon in a font string).
local function IconTag(fid, sz)
    if not fid then return "" end
    sz = sz or 14
    return string.format("|T%s:%d:%d:0:0|t ", tostring(fid), sz, sz)
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
local FRAME_W = 265
local TITLE_H = 22
local PAD     = 6

-- Builds a backdrop panel (branded) with a header (optional logo) + title, a
-- divider, and pooled line/separator widgets. Returns { frame, linePool, sepPool }.
-- Shared by the standalone panel and the two embedded folio panels.
function OO:CreatePanel(name, strata, titleText, showLogo)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    local headerH = showLogo and 46 or TITLE_H
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

    local title = f:CreateFontString(nil, "OVERLAY", showLogo and "GameFontNormal" or "GameFontNormalSmall")
    if showLogo then
        -- Larger mascot portrait (the high-res CurseForge art) in the header.
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetSize(38, 38)
        logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -4)
        logo:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\mascot.png")
        title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    else
        title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -5)
    end
    title:SetText(titleText or ("|c" .. PALETTE.title .. "OmniumObservator|r"))

    local divider = f:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(FRAME_W - 16, 1)
    divider:SetPoint("TOP", f, "TOP", 0, -(headerH - 2))
    divider:SetColorTexture(1.0, 0.82, 0.0, 0.5)

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
        sep:SetColorTexture(0.60, 0.50, 0.10, 0.4)
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
    frame:SetAlpha(db.alpha)
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
end

-- Lazily create the two embedded panels (anchored INSIDE the folio's empty
-- columns when it opens). Parented to UIParent so we never taint the Traits frame.
function OO:BuildDock()
    if self.dockL then return end
    self.dockL = self:CreatePanel("OODockLeft",  "HIGH", "|c" .. PALETTE.title .. "This week|r", false)
    self.dockR = self:CreatePanel("OODockRight", "HIGH", "|c" .. PALETTE.title .. "Voidstorm|r", false)
    self.dockL.frame:Hide()
    self.dockR.frame:Hide()
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
    -- Embed: anchor the two panels INSIDE the folio's empty columns, flanking the
    -- rune tree. Offsets are a first pass — tune here if they overlap the tree/title.
    local lf, rf = self.dockL.frame, self.dockR.frame
    lf:ClearAllPoints()
    lf:SetPoint("TOPLEFT", self.folioFrame, "TOPLEFT", 28, -96)
    rf:ClearAllPoints()
    rf:SetPoint("TOPRIGHT", self.folioFrame, "TOPRIGHT", -28, -96)
    lf:Show()
    rf:Show()
    -- The embed is the single source of info while the folio is open — hide the
    -- standalone panel (if it was up) and restore it when the folio closes.
    if self.frame and self.frame:IsShown() then
        self._frameWasShown = true
        self.frame:Hide()
    end
    self:ApplyAppearance()
    self:Refresh()
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
    if self._frameWasShown then
        self._frameWasShown = false
        if self.frame then self.frame:Show() end
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
    -- check vs bullet shows progress. Locked weeks are name-coloured but marked.
    for i, step in ipairs(weeks.steps) do
        local color = WEEK_COLORS[i] or "FFCCCCCC"
        lines[#lines + 1] = string.format("%s |c%s%s|r", Check(step.done), color, step.name)
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
    local neb = self:GetCurrency(NEBULOUS_VOIDCORE)
    lines[#lines + 1] = string.format(
        "%s|c" .. PALETTE.purple .. "Bonus rolls:|r |cFFFFFFFF%s|r |c" .. PALETTE.dim .. "(Nebulous)|r",
        IconTag(self:CurrencyIcon(NEBULOUS_VOIDCORE)), neb and tostring(neb) or "—")

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
end

function OO:RenderLines(panel, lines)
    local frame   = panel.frame
    local headerH = panel.headerH or TITLE_H
    local sepIdx  = 1
    local lineIdx = 0
    local yOff    = 0

    for _, entry in ipairs(lines) do
        if entry == "sep" then
            local sep = panel.sepPool[sepIdx]
            if sep then
                sep:ClearAllPoints()
                sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, -(headerH + yOff + ROW_H / 2))
                sep:Show()
                sepIdx = sepIdx + 1
                yOff = yOff + ROW_H / 2
            end
        else
            lineIdx = lineIdx + 1
            local fs = panel.linePool[lineIdx]
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(headerH + yOff + 4))
                fs:SetText(entry)
                fs:Show()
                yOff = yOff + ROW_H
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

-- Push saved opacity/scale onto the standalone panel and the two embedded panels.
function OO:ApplyAppearance()
    local a  = self.db.alpha or 0.9
    local sc = self.db.scale or 1.0
    if self.frame then self.frame:SetAlpha(a); self.frame:SetScale(sc) end
    if self.dockL then self.dockL.frame:SetAlpha(a) end
    if self.dockR then self.dockR.frame:SetAlpha(a) end
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
    f:SetSize(290, 250)
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

    OOConfigSlider(f, "OOConfigOpacity", "Opacity", "30%", "100%", 0.3, 1.0, self.db.alpha or 0.9, -52,
        function(v) OO.db.alpha = v; OO:ApplyAppearance() end)
    OOConfigSlider(f, "OOConfigScale", "Scale (standalone)", "70%", "150%", 0.7, 1.5, self.db.scale or 1.0, -98,
        function(v) OO.db.scale = v; OO:ApplyAppearance() end)

    OOConfigCheck(f, "Lock position", 28, -136, self.db.locked, function(v) OO.db.locked = v end)
    OOConfigCheck(f, "Folio dock enabled", 28, -164, self.db.dockEnabled, function(v)
        OO.db.dockEnabled = v
        if not v then OO:OnFolioHidden()
        elseif OO.folioFrame and OO.folioFrame:IsShown() then OO:OnFolioShown() end
    end)
    OOConfigCheck(f, "Show minimap button", 28, -192, not self.db.minimapHide, function(v)
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
        GameTooltip:AddLine("Right-click: Dump state", 1, 1, 1)
        GameTooltip:AddLine("Drag: Reposition", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Tip: open the Omnium Folio to see the dock", 0.6, 0.9, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SlashCmdList["OMNIUMOBSERVATOR"]("debug")
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
        for _, q in ipairs(WEEKLY_QUESTS) do
            print(string.format("    Quest %d (wk%d): completed=%s",
                q.id, q.week, tostring(C_QuestLog.IsQuestFlaggedCompleted(q.id))))
        end
    elseif cmd == "config" or cmd == "options" then
        OO:BuildConfig()
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
