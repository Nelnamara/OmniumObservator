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

function OO:GetWeeklyQuest()
    local qid = self.db.weeklyQuestID
    if not qid then return nil, nil end
    local done = C_QuestLog.IsQuestFlaggedCompleted(qid)
    return done, "Seeking Knowledge"
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

    local achData             = self:GetAchievementData()
    local weeklyDone, wqName  = self:GetWeeklyQuest()

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

    -- 5 weekly rows
    for i, step in ipairs(achData.steps) do
        lines[#lines + 1] = string.format("%s |cFFCCCCCC%s|r", Check(step.done), step.name)
    end

    -- Weekly quest
    lines[#lines + 1] = "sep"
    if weeklyDone ~= nil then
        lines[#lines + 1] = string.format("%s |cFFAADDFF%s|r", Check(weeklyDone), wqName)
    elseif self.db.weeklyQuestID then
        lines[#lines + 1] = "|cFF888888Checking weekly quest...|r"
    else
        lines[#lines + 1] = "|cFF888888/oo questid <id>  to track weekly|r"
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
        local qid = tonumber(arg)
        if qid then
            OO.db.weeklyQuestID = qid
            print("|cFFFFCC00OmniumObservator|r weekly quest ID set to " .. qid)
            OO:Refresh()
        else
            print("|cFFFFCC00OmniumObservator|r Usage: /oo questid <number>")
            print("  Discover ID in-game:")
            print("  /run print(C_QuestLog.GetQuestIDByName(\"Seeking Knowledge\"))")
        end
    elseif cmd == "debug" then
        print("|cFFFFCC00OmniumObservator|r " .. OO.version)
        print("  Weekly quest ID:", tostring(OO.db.weeklyQuestID))
        local achData = OO:GetAchievementData()
        print("  Achievement " .. ACH_OMNIUM_FOLIO .. " complete:", tostring(achData.overall))
        for i, step in ipairs(achData.steps) do
            print(string.format("  Week %d [%s] %s", i, step.done and "✓" or " ", step.name))
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
