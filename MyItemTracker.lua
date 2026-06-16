-- MyItemTracker.lua
-- Retail addon: tracks items by ID, searchable UI, goals/notes, tooltips,
-- and automatic source detection for vendor/craft/quest/loot.
-- luacheck: globals CreateFrame GetTime GetItemCount C_Timer GetItemInfo BuyMerchantItem GetMerchantItemLink C_TradeSkillUI GameTooltip SlashCmdList

---@type any
local WoW = _G

local CreateFrame, GetTime, GetItemCount, GetItemInfo = WoW.CreateFrame, WoW.GetTime, WoW.GetItemCount, WoW.GetItemInfo
local C_Timer, C_TradeSkillUI, GameTooltip, UIParent = WoW.C_Timer, WoW.C_TradeSkillUI, WoW.GameTooltip, WoW.UIParent
local BuyMerchantItem, GetMerchantItemLink, hooksecurefunc = WoW.BuyMerchantItem, WoW.GetMerchantItemLink, WoW.hooksecurefunc
local SlashCmdList, TooltipDataProcessor, Enum = WoW.SlashCmdList, WoW.TooltipDataProcessor, WoW.Enum
local print, format = WoW.print, WoW.string.format
local table, pairs, ipairs, tonumber, tostring = WoW.table, WoW.pairs, WoW.ipairs, WoW.tonumber, WoW.tostring

print("|cff00ff00MyItemTracker loaded|r")

WoW.MyItemTrackerDB = WoW.MyItemTrackerDB or {}
WoW.MyItemTrackerDB.tracked = WoW.MyItemTrackerDB.tracked or {}

local frame = CreateFrame("Frame", "MIT_MainFrame")
local tracked, lastCounts, recentContext = WoW.MyItemTrackerDB.tracked, {}, nil
local backdrop = { bgFile = "Interface/Tooltips/UI-Tooltip-Background" }
local popoutBackdrop = { bgFile = backdrop.bgFile, edgeFile = "", tile = true, tileSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

local function RefreshFrame(f) if f and f.Refresh then f:Refresh() end end
local function RefreshUI() RefreshFrame(WoW.MIT_Popout); RefreshFrame(WoW.MIT_ConfigFrame) end
local function ParseItemIDFromLink(link) return link and tonumber(link:match("item:(%d+):")) end
local function FirstTrackedId() for id in pairs(tracked) do return id end end

local function MakeDraggable(f)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
end

local function SetDarkBackdrop(f, alpha, customBackdrop)
    f:SetBackdrop(customBackdrop or backdrop); f:SetBackdropColor(0, 0, 0, alpha)
end

local function NewButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height); button:SetText(text)
    return button
end

local function NewEditBox(parent, width, height, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, height); box:SetAutoFocus(false)
    if numeric then box:SetNumeric(true) end
    return box
end

local function EnsureTracked(id)
    local item = tracked[id] or {}
    tracked[id] = item
    item.count, item.goal = item.count or 0, item.goal or 1
    item.notes, item.sources = item.notes or "", item.sources or {}
    return item
end

local function ItemDisplay(id)
    local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(id)
    return name or ("Item " .. id), texture
end

local function SourcesToString(srcTable)
    if not srcTable then return "" end
    local out = {}
    for source in pairs(srcTable) do table.insert(out, source) end
    table.sort(out)
    return table.concat(out, ", ")
end

local function UpdateCount(id, deferRefresh)
    id = tonumber(id)
    if not id then return end

    local item = EnsureTracked(id)
    item.count = GetItemCount(id, true) or 0
    lastCounts[id] = lastCounts[id] or item.count
    if not deferRefresh then RefreshUI() end
end

local function AddSource(id, source)
    if id and source then EnsureTracked(id).sources[source] = true end
end

local function RecordContext(ctx)
    recentContext = { type = ctx, time = GetTime() }
end

local function DetermineAndRecordSource(id, source)
    if not id then return end
    if not source and recentContext and (GetTime() - recentContext.time) < 6 then source = recentContext.type end
    AddSource(id, source or "unknown")
end

local function AddItem(id)
    id = tonumber(id)
    if not id then print("MyItemTracker: invalid id"); return end
    EnsureTracked(id); UpdateCount(id)
    print(format("MyItemTracker: now tracking item %d", id))
end

local function RemoveItem(id)
    id = tonumber(id)
    if not id or not tracked[id] then return end
    tracked[id], lastCounts[id] = nil, nil
    print(format("MyItemTracker: stopped tracking item %d", id))
    RefreshUI()
end

WoW.MIT_AddItem, WoW.MIT_RemoveItem = AddItem, RemoveItem

local contextEvents = { MERCHANT_SHOW = "vendor", QUEST_COMPLETE = "quest", TRADE_SKILL_SHOW = "craft", TRADE_SKILL_LIST_UPDATE = "craft" }
for _, event in ipairs({
    "PLAYER_LOGIN", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "BAG_UPDATE_DELAYED",
    "MERCHANT_SHOW", "QUEST_COMPLETE", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "UNIT_SPELLCAST_SUCCEEDED",
}) do frame:RegisterEvent(event) end

local function UpdateAllCounts()
    for id in pairs(tracked) do UpdateCount(id, true) end
    RefreshUI()
end

local function HandleLootMessage(msg)
    local id = ParseItemIDFromLink(msg)
    if not (id and tracked[id]) then return end
    C_Timer.After(0.1, function() DetermineAndRecordSource(id, "loot"); UpdateCount(id) end)
end

local function SyncBagCounts()
    for id in pairs(tracked) do
        local item, newCount = EnsureTracked(id), GetItemCount(id, true) or 0
        if newCount > (lastCounts[id] or item.count or 0) then DetermineAndRecordSource(id) end
        if newCount ~= item.count then item.count = newCount end
        lastCounts[id] = newCount
    end
    RefreshUI()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        UpdateAllCounts()
    elseif event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM" then
        HandleLootMessage(...)
    elseif event == "BAG_UPDATE_DELAYED" then
        SyncBagCounts()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" then RecordContext("craft") end
    elseif contextEvents[event] then
        RecordContext(contextEvents[event])
    end
end)

local function ToggleFrame(f)
    if f:IsShown() then f:Hide(); return end
    f:Show(); RefreshFrame(f)
end

local function CreatePopout()
    if WoW.MIT_Popout then return WoW.MIT_Popout end

    local f = CreateFrame("Frame", "MIT_PopoutFrame", UIParent, "BackdropTemplate")
    f:SetSize(260, 64); f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    SetDarkBackdrop(f, 0.6, popoutBackdrop); MakeDraggable(f)

    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(36, 36); f.icon:SetPoint("LEFT", 6, 0)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 48, -6); f.title:SetText("MyItemTracker")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("LEFT", 48, 4); f.body:SetPoint("RIGHT", -8, 0); f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -4)

    function f:Refresh()
        local id = FirstTrackedId()
        if not id then
            self.icon:SetTexture(nil); self.body:SetText("No items tracked. Use /mit add <id>")
            return
        end

        local item = EnsureTracked(id)
        local name, texture = ItemDisplay(id)
        self.icon:SetTexture(texture)
        self.body:SetText(format("%s - %d / %d\nSources: %s", name, item.count, item.goal, SourcesToString(item.sources)))
    end

    f:Refresh(); WoW.MIT_Popout = f
    return f
end

local function TogglePopout() ToggleFrame(WoW.MIT_Popout or CreatePopout()) end
WoW.MIT_TogglePopout = TogglePopout

local function CreateConfig()
    if WoW.MIT_ConfigFrame then return WoW.MIT_ConfigFrame end

    local f = CreateFrame("Frame", "MIT_ConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 480); f:SetPoint("CENTER")
    SetDarkBackdrop(f, 0.85); MakeDraggable(f)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -8); f.title:SetText("MyItemTracker - Config")

    local function AddFromBox()
        local id = tonumber(f.addBox:GetText())
        if id then AddItem(id); f.addBox:SetText("") end
    end

    f.addBox = NewEditBox(f, 140, 24, true); f.addBox:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -12); f.addBox:SetScript("OnEnterPressed", AddFromBox)
    f.addBtn = NewButton(f, 80, 24, "Add"); f.addBtn:SetPoint("LEFT", f.addBox, "RIGHT", 8, 0); f.addBtn:SetScript("OnClick", AddFromBox)
    f.searchBox = NewEditBox(f, 180, 24); f.searchBox:SetPoint("TOPRIGHT", -12, -36); f.searchBox:SetText("")
    f.searchBox:SetScript("OnTextChanged", function() f:Refresh() end)
    f.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    f.searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.searchLabel:SetPoint("RIGHT", f.searchBox, "LEFT", -8, 0); f.searchLabel:SetText("Search:")

    f.list = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.list:SetPoint("TOPLEFT", f.addBox, "BOTTOMLEFT", 0, -12); f.list:SetSize(480, 360)
    f.content = CreateFrame("Frame", nil, f.list); f.content:SetSize(480, 360); f.list:SetScrollChild(f.content)

    local notesPopup, currentNotesId = CreateFrame("Frame", "MIT_NotesPopup", UIParent, "BackdropTemplate"), nil
    notesPopup:SetSize(360, 200); SetDarkBackdrop(notesPopup, 0.9); notesPopup:Hide()
    notesPopup.editor = NewEditBox(notesPopup, 330, 140); notesPopup.editor:SetMultiLine(true); notesPopup.editor:SetPoint("TOPLEFT", 10, -10)
    notesPopup.save = NewButton(notesPopup, 80, 24, "Save"); notesPopup.save:SetPoint("BOTTOMRIGHT", -10, 10)

    local function ShowNotes(id)
        currentNotesId = id
        notesPopup.editor:SetText(tracked[id].notes or "")
        notesPopup:Show()
    end

    notesPopup.save:SetScript("OnClick", function()
        if currentNotesId then tracked[currentNotesId].notes = notesPopup.editor:GetText() end
        notesPopup:Hide(); RefreshFrame(WoW.MIT_ConfigFrame)
    end)

    f.rows = {}
    local function CreateRow()
        local row = CreateFrame("Frame", nil, f.content)
        row:SetSize(460, 40)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(32, 32); row.icon:SetPoint("LEFT", 4, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("LEFT", 44, 6)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.sub:SetPoint("LEFT", 44, -8)
        row.goalBox = NewEditBox(row, 60, 20, true); row.goalBox:SetPoint("RIGHT", -120, 0)
        row.notesBtn = NewButton(row, 60, 20, "Notes"); row.notesBtn:SetPoint("RIGHT", -56, 0)
        row.remove = NewButton(row, 60, 20, "Remove"); row.remove:SetPoint("RIGHT", -4, 0)

        row.goalBox:SetScript("OnEnterPressed", function(self)
            local item, goal = tracked[row.itemId], tonumber(self:GetText())
            if item and goal then item.goal = goal end
            f:Refresh()
        end)
        row.notesBtn:SetScript("OnClick", function() ShowNotes(row.itemId) end)
        row.remove:SetScript("OnClick", function() RemoveItem(row.itemId) end)
        return row
    end

    function f:Refresh()
        for _, row in ipairs(self.rows) do row:Hide() end

        local index, term = 1, (self.searchBox:GetText() or ""):lower()
        for id in pairs(tracked) do
            local item = EnsureTracked(id)
            local name, texture = ItemDisplay(id)
            local haystack = (name .. " " .. tostring(id) .. " " .. item.notes):lower()

            if term == "" or haystack:find(term, 1, true) then
                local row = self.rows[index] or CreateRow()
                self.rows[index], row.itemId = row, id
                row.icon:SetTexture(texture); row.name:SetText(name); row.goalBox:SetText(item.goal)
                row.sub:SetText(format("%d / %d - Sources: %s", item.count, item.goal, SourcesToString(item.sources)))
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 8, -((index - 1) * 44)); row:Show()
                index = index + 1
            end
        end
    end

    f:Hide(); WoW.MIT_ConfigFrame = f
    return f
end

local function ShowConfig() ToggleFrame(WoW.MIT_ConfigFrame or CreateConfig()) end
WoW.MIT_ShowConfig = ShowConfig

WoW.SLASH_MIT1 = "/mit"
SlashCmdList.MIT = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    local id = tonumber(rest)
    if cmd == "config" then
        ShowConfig()
    elseif cmd == "show" then
        TogglePopout()
    elseif cmd == "add" and id then
        AddItem(id)
    elseif cmd == "remove" and id then
        RemoveItem(id)
    else
        print("MyItemTracker: /mit config | add <id> | remove <id> | show")
    end
end

if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index)
        RecordContext("vendor")
        local id = ParseItemIDFromLink(GetMerchantItemLink(index))
        if id then AddSource(id, "vendor:buy"); C_Timer.After(0.2, function() UpdateCount(id) end) end
    end)
end

if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function() RecordContext("craft") end)
end

local function ApplyTooltip(self)
    local _, link = self:GetItem()
    local id = ParseItemIDFromLink(link)
    if not (id and tracked[id]) then return end

    local item = EnsureTracked(id)
    local sources = SourcesToString(item.sources)
    self:AddLine(" ")
    self:AddLine(format("MyItemTracker: %d / %d", item.count, item.goal), 0.2, 1, 0.2)
    if item.notes ~= "" then self:AddLine("Notes: " .. item.notes, 0.8, 0.8, 0.8, 1) end
    if sources ~= "" then self:AddLine("Sources: " .. sources, 0.6, 0.8, 1) end
    self:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ApplyTooltip)
elseif GameTooltip and GameTooltip.HookScript and GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", ApplyTooltip)
end
