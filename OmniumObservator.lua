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

OO.version = "1.0.3"

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

-- Suite branding palette (purple / gold / black)
local PALETTE = {
    bg     = { 0.04, 0.02, 0.07, 0.92 },  -- near-black with a faint purple cast
    border = { 1.00, 0.82, 0.00, 0.90 },  -- gold
    title  = "FFFFD200",                   -- gold (title text colour code)
    gold   = "FFFFD700",
    purple = "FFBB66FF",
    dim    = "FF888888",
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

function OO:GetAchievementData()
    local _, _, _, overallDone, _, _, _, _, _, _, alreadyEarned =
        GetAchievementInfo(ACH_OMNIUM_FOLIO)
    local numCriteria = GetAchievementNumCriteria(ACH_OMNIUM_FOLIO)

    local steps = {}
    for i = 1, numCriteria do
        local label, _, done = GetAchievementCriteriaInfo(ACH_OMNIUM_FOLIO, i)
        steps[i] = {
            name = (label ~= "" and label) or WEEK_NAMES[i] or ("Week " .. i),
            done = done,
        }
    end

    -- Fill missing steps with fallback names
    for i = #steps + 1, 5 do
        steps[i] = { name = WEEK_NAMES[i] or ("Week " .. i), done = false }
    end

    return {
        overall   = overallDone or alreadyEarned,
        steps     = steps,
    }
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

local ROW_H   = 18
local FRAME_W = 265
local TITLE_H = 22
local PAD     = 6

-- Builds a backdrop panel (branded) with a header logo + title, a divider, and
-- pooled line/separator widgets. Returns { frame, linePool, sepPool }. Shared by
-- the standalone panel and the folio dock.
function OO:CreatePanel(name, strata)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, TITLE_H + ROW_H * 9 + PAD * 2)
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

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(16, 16)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -3)
    logo:SetTexture("Interface\\AddOns\\OmniumObservator\\Media\\icon.png")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", logo, "RIGHT", 4, 0)
    title:SetText("|c" .. PALETTE.title .. "OmniumObservator|r  |c" .. PALETTE.dim .. OO.version .. "|r")

    local divider = f:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(FRAME_W - 16, 1)
    divider:SetPoint("TOP", f, "TOP", 0, -(TITLE_H - 2))
    divider:SetColorTexture(1.0, 0.82, 0.0, 0.5)

    local panel = { frame = f, linePool = {}, sepPool = {} }
    for i = 1, 20 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -(TITLE_H + (i - 1) * ROW_H + 4))
        fs:SetWidth(FRAME_W - PAD * 2 - 4)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        panel.linePool[i] = fs
    end
    for i = 1, 5 do
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
    local panel = self:CreatePanel("OOMainFrame", "MEDIUM")
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

-- Lazily create the dock panel (anchored to the folio frame when it opens).
function OO:BuildDock()
    if self.dock then return end
    local panel = self:CreatePanel("OODockFrame", "HIGH")
    panel.frame:Hide()
    self.dock = panel
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

function OO:OnFolioShown()
    if not self.db.dockEnabled or not self.dock then return end
    -- capture the live configID (it can change between sessions)
    pcall(function()
        if self.folioFrame and self.folioFrame.GetConfigID then
            local id = self.folioFrame:GetConfigID()
            if id and id > 0 then self.folioConfigID = id end
        end
    end)
    local d = self.dock.frame
    d:ClearAllPoints()
    -- Dock to the right edge of the folio. If it renders behind the folio in
    -- testing, raise the strata in BuildDock.
    d:SetPoint("TOPLEFT", self.folioFrame, "TOPRIGHT", 8, 0)
    d:Show()
    self:Refresh()
    -- keep the reset timer / Mote count fresh while the folio is open
    d:SetScript("OnUpdate", function(s, elapsed)
        s._t = (s._t or 0) + elapsed
        if s._t > 5 then s._t = 0; OO:Refresh() end
    end)
end

function OO:OnFolioHidden()
    if self.dock then
        self.dock.frame:SetScript("OnUpdate", nil)
        self.dock.frame:Hide()
    end
end

-- Shared content builder — both panels render the same line list.
function OO:BuildLines()
    local achData = self:GetAchievementData()
    local ws      = self:GetWeeklyState()
    local lines   = {}

    -- Folio resources (shown when the values are known)
    local motes = self:GetMotes()
    local orbs  = self:GetVoidOrbs()
    local reset = self:GetResetSeconds()
    if motes then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.gold .. "Motes of Omnial Inquiry:|r |cFFFFFFFF%d|r", motes)
    end
    if orbs then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.purple .. "Void-Touched Orbs:|r |cFFFFFFFF%d|r|c" .. PALETTE.dim .. "/5|r", orbs)
    end
    if reset then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.dim .. "Weekly reset in|r |cFFFFFFFF%s|r", FmtDur(reset))
    end
    if motes or orbs or reset then lines[#lines + 1] = "sep" end

    -- Overall achievement header + week progress
    local unlocked = 0
    for _, step in ipairs(achData.steps) do
        if step.done then unlocked = unlocked + 1 end
    end
    if achData.overall then
        lines[#lines + 1] = "|c" .. PALETTE.gold .. "Omnium Folio Studies: |cFF66FF66COMPLETE|r"
    else
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.gold .. "Omnium Folio|r  |cFFFFFFFF%d|r|c" .. PALETTE.dim .. "/5 weeks|r", unlocked)
    end
    lines[#lines + 1] = "sep"

    -- 5 weekly rows (driven by achievement criteria), with check/bullet visuals
    for _, step in ipairs(achData.steps) do
        lines[#lines + 1] = string.format("%s |cFFCCCCCC%s|r", Check(step.done), step.name)
    end

    -- Current week's "Seeking Knowledge" quest state (auto-detected)
    lines[#lines + 1] = "sep"
    if ws.allDone then
        lines[#lines + 1] = "|cFF66FF66All 5 weeks complete — Folio fully unlocked!|r"
    elseif ws.inLog then
        lines[#lines + 1] = string.format(
            "|cFFFFDD88Week %d: %s — In progress|r", ws.week, ws.name)
    elseif ws.nextReset then
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.dim .. "Week %d: %s — available next reset|r", ws.week, ws.name)
    else
        lines[#lines + 1] = string.format(
            "|c" .. PALETTE.dim .. "Week 1: %s — pick up quest in Silvermoon|r", ws.name)
    end

    return lines
end

function OO:Refresh()
    local lines = self:BuildLines()
    if self.panel and self.frame and self.frame:IsShown() then
        self:RenderLines(self.panel, lines)
    end
    if self.dock and self.dock.frame:IsShown() then
        self:RenderLines(self.dock, lines)
    end
end

function OO:RenderLines(panel, lines)
    local frame   = panel.frame
    local sepIdx  = 1
    local lineIdx = 0
    local yOff    = 0

    for _, entry in ipairs(lines) do
        if entry == "sep" then
            local sep = panel.sepPool[sepIdx]
            if sep then
                sep:ClearAllPoints()
                sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, -(TITLE_H + yOff + ROW_H / 2))
                sep:Show()
                sepIdx = sepIdx + 1
                yOff = yOff + ROW_H / 2
            end
        else
            lineIdx = lineIdx + 1
            local fs = panel.linePool[lineIdx]
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(TITLE_H + yOff + 4))
                fs:SetText(entry)
                fs:Show()
                yOff = yOff + ROW_H
            end
        end
    end

    for i = lineIdx + 1, #panel.linePool do panel.linePool[i]:Hide() end
    for i = sepIdx, #panel.sepPool do panel.sepPool[i]:Hide() end

    frame:SetHeight(TITLE_H + yOff + PAD * 2)
end

function OO:SavePosition()
    if not self.frame then return end
    local x, y   = self.frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.x, self.db.y = x - ux, y - uy
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
            OO:TryHookFolio()  -- in case the folio addon is already loaded
            OO:Refresh()
            self:RegisterEvent("ACHIEVEMENT_EARNED")
            self:RegisterEvent("CRITERIA_UPDATE")
            self:RegisterEvent("QUEST_LOG_UPDATE")
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("PLAYER_LOGOUT")
        elseif name == "Blizzard_ExpansionLandingPage" then
            OO:TryHookFolio()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if OO.db then OO:TryHookFolio() end
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
        if not OO.db.dockEnabled and OO.dock then
            OO:OnFolioHidden()
        elseif OO.db.dockEnabled and OO.folioFrame and OO.folioFrame:IsShown() then
            OO:OnFolioShown()
        end
    elseif cmd == "debug" then
        print("|cFFFFCC00OmniumObservator|r " .. OO.version)
        local achData = OO:GetAchievementData()
        print("  Achievement " .. ACH_OMNIUM_FOLIO .. " complete:", tostring(achData.overall))
        for i, step in ipairs(achData.steps) do
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
