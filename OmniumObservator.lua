-- OmniumObservator
-- Omnium Folio power system tracker for WoW Midnight 12.0.7+
-- Author: Nelnamara
--
-- Tracks weekly progress through the Omnium Folio achievement chain (63325),
-- monitors the "Seeking Knowledge" weekly quest, and displays which of the 5 rune
-- rows have been unlocked. Use /oo questid <id> once you know the weekly quest ID.

OmniumObservator = {}
local OO = OmniumObservator

OO.version = "1.0.1"

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

local DEFAULTS = {
    x            =  400,
    y            =  200,
    scale        = 1.0,
    locked       = false,
    alpha        = 0.9,
    weeklyQuestID = nil,
}

local function Check(done)
    return done and "|cFF66FF66[✓]|r" or "|cFF666666[ ]|r"
end

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
        local next = WEEKLY_QUESTS[highestDone + 1]
        return { week = next.week, name = next.name, done = false, inLog = false, nextReset = true }
    else
        return { week = 1, name = "The Omnium Folio", done = false, inLog = false, nextReset = false }
    end
end

local ROW_H   = 18
local FRAME_W = 265
local TITLE_H = 20
local PAD     = 6

function OO:BuildUI()
    local db = self.db

    local frame = CreateFrame("Frame", "OOMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, TITLE_H + ROW_H * 9 + PAD * 2)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    frame:SetScale(db.scale)
    frame:SetAlpha(db.alpha)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.06, 0.05, 0.02, 0.88)
    frame:SetBackdropBorderColor(0.70, 0.60, 0.15, 0.85)

    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not OO.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        OO:SavePosition()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetText("|cFFFFCC00OmniumObservator|r  |cFF888888" .. OO.version .. "|r")

    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(FRAME_W - 16, 1)
    divider:SetPoint("TOP", frame, "TOP", 0, -(TITLE_H - 2))
    divider:SetColorTexture(0.60, 0.50, 0.10, 0.6)

    self.linePool = {}
    for i = 1, 20 do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(TITLE_H + (i - 1) * ROW_H + 4))
        fs:SetWidth(FRAME_W - PAD * 2 - 4)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Hide()
        self.linePool[i] = fs
    end

    self.sepPool = {}
    for i = 1, 4 do
        local sep = frame:CreateTexture(nil, "BACKGROUND")
        sep:SetSize(FRAME_W - 20, 1)
        sep:SetColorTexture(0.50, 0.40, 0.10, 0.4)
        sep:Hide()
        self.sepPool[i] = sep
    end

    frame:Show()
    self.frame = frame
end

function OO:Refresh()
    if not self.frame then return end

    local achData  = self:GetAchievementData()
    local ws       = self:GetWeeklyState()

    local lines = {}

    -- Overall achievement header
    local unlockedCount = 0
    for _, step in ipairs(achData.steps) do
        if step.done then unlockedCount = unlockedCount + 1 end
    end

    if achData.overall then
        lines[#lines + 1] = "|cFFFFD700Omnium Folio Studies: |cFF66FF66COMPLETE|r"
    else
        lines[#lines + 1] = string.format(
            "|cFFFFD700Omnium Folio:|r |cFFCCCCCC%d/5 weeks unlocked|r", unlockedCount)
    end

    lines[#lines + 1] = "sep"

    -- 5 weekly rows (driven by achievement criteria)
    for i, step in ipairs(achData.steps) do
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
            "|cFF888888Week %d: %s — available next reset|r", ws.week, ws.name)
    else
        lines[#lines + 1] = string.format(
            "|cFF888888Week 1: %s — pick up quest in Silvermoon|r", ws.name)
    end

    self:RenderLines(lines)
end

function OO:RenderLines(lines)
    local sepIdx  = 1
    local lineIdx = 0
    local yOff    = 0

    for _, entry in ipairs(lines) do
        if entry == "sep" then
            local sep = self.sepPool[sepIdx]
            if sep then
                sep:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD + 4,
                    -(TITLE_H + yOff + ROW_H / 2))
                sep:Show()
                sepIdx = sepIdx + 1
                yOff = yOff + ROW_H / 2
            end
        else
            lineIdx = lineIdx + 1
            local fs = self.linePool[lineIdx]
            if fs then
                fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD + 2,
                    -(TITLE_H + yOff + 4))
                fs:SetText(entry)
                fs:Show()
                yOff = yOff + ROW_H
            end
        end
    end

    for i = lineIdx + 1, #self.linePool do self.linePool[i]:Hide() end
    for i = sepIdx, #self.sepPool do self.sepPool[i]:Hide() end

    self.frame:SetHeight(TITLE_H + yOff + PAD * 2)
end

function OO:SavePosition()
    if not self.frame then return end
    local x, y   = self.frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.x, self.db.y = x - ux, y - uy
    end
end

local ef = CreateFrame("Frame", "OOEventFrame")
ef:RegisterEvent("ADDON_LOADED")
ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "OmniumObservator" then
        if not OmniumObservatorDB then OmniumObservatorDB = CopyTable(DEFAULTS) end
        OO.db = OmniumObservatorDB
        for k, v in pairs(DEFAULTS) do
            if OO.db[k] == nil then OO.db[k] = v end
        end
        OO:BuildUI()
        OO:Refresh()
        self:RegisterEvent("ACHIEVEMENT_EARNED")
        self:RegisterEvent("CRITERIA_UPDATE")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("PLAYER_LOGOUT")
    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_UPDATE" or event == "QUEST_LOG_UPDATE" then
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
