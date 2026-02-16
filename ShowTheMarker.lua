local ADDON_NAME = "ShowTheMarker"

local HBDPins = LibStub("HereBeDragons-Pins-2.0")

local tintedWorldPins = {}
local minimapPins = {}
local worldQuestLocations = {}

local DEFAULT_COLOR = { r = 0.2, g = 1.0, b = 0.2 }
local db

local function GetColor()
    if db and db.color then
        return db.color.r, db.color.g, db.color.b
    end
    return DEFAULT_COLOR.r, DEFAULT_COLOR.g, DEFAULT_COLOR.b
end

local function ShouldFloatOnEdge()
    if db and db.minimapFloatOnEdge ~= nil then
        return db.minimapFloatOnEdge
    end
    return false
end

local function SetQuestBangTexture(tex)
    local ok = false
    if tex.SetAtlas then
        ok = pcall(tex.SetAtlas, tex, "QuestNormal")
    end
    if not ok then
        tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
    local r, g, b = GetColor()
    tex:SetVertexColor(r, g, b)
end

local function CreateQuestPin(size)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    SetQuestBangTexture(tex)
    f.texture = tex
    return f
end

local function IsLowLevelQuestByID(questID)
    local qLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
    local pLevel = UnitLevel("player")
    if qLevel and pLevel and pLevel > 0 then
        return qLevel <= (pLevel - 10)
    end
    return false
end

local function IsAvailableQuestID(questID, info)
    if not questID then return false end
    if C_QuestLog.IsOnQuest(questID) then
        return false
    end
    if info then
        if info.isComplete ~= nil and info.isComplete then
            return false
        end
        if info.isCompleted ~= nil and info.isCompleted then
            return false
        end
    end
    return true
end

local function ForEachQuestPin(fn)
    if not WorldMapFrame then return end
    local function enumerate(target, template)
        if target and target.EnumeratePinsByTemplate then
            for pin in target:EnumeratePinsByTemplate(template) do
                fn(pin, template)
            end
        end
    end
    enumerate(WorldMapFrame, "QuestPinTemplate")
    enumerate(WorldMapFrame, "QuestOfferPinTemplate")
    if WorldMapFrame.GetCanvas then
        local canvas = WorldMapFrame:GetCanvas()
        enumerate(canvas, "QuestPinTemplate")
        enumerate(canvas, "QuestOfferPinTemplate")
    end
end

local function GetPinTexture(pin)
    if not pin then return end
    if pin.texture then return pin.texture end
    if pin.icon then return pin.icon end
    if pin.Icon then return pin.Icon end
    if pin.GetRegions then
        for i = 1, select("#", pin:GetRegions()) do
            local region = select(i, pin:GetRegions())
            if region and region.SetVertexColor then
                return region
            end
        end
    end
end

local function GetQuestPinPosition(pin)
    if not pin then return end
    if pin.normalizedX and pin.normalizedY then
        return pin.normalizedX, pin.normalizedY
    end
    if pin.x and pin.y then
        return pin.x, pin.y
    end
    if pin.GetPosition then
        local x, y = pin:GetPosition()
        if x and y then
            return x, y
        end
    end
end

local function RefreshWorldMapPins(force)
    if not WorldMapFrame then return end
    if not force and not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local mapInfo = C_Map.GetMapInfo(mapID)
    if mapInfo and mapInfo.mapType then
        local mt = mapInfo.mapType
        if mt ~= Enum.UIMapType.Zone and mt ~= Enum.UIMapType.Micro and mt ~= Enum.UIMapType.Dungeon then
            return
        end
    end
    local r, g, b = GetColor()
    local keep = {}

    ForEachQuestPin(function(pin, template)
        local questID = pin and pin.questID
        if not questID then
            return
        end
        local x, y = GetQuestPinPosition(pin)
        if x and y and WorldMapFrame and WorldMapFrame.GetMapID then
            local mapID = WorldMapFrame:GetMapID()
            if mapID then
                worldQuestLocations[questID] = { mapID = mapID, x = x, y = y }
            end
        end
        local isLow = IsLowLevelQuestByID(questID)
        local isAvail = IsAvailableQuestID(questID)
        if isLow and isAvail then
            local tex = GetPinTexture(pin)
            if tex then
                tex:SetVertexColor(r, g, b)
                keep[pin] = true
            end
        end
    end)

    for pin in pairs(tintedWorldPins) do
        if not keep[pin] then
            local tex = GetPinTexture(pin)
            if tex then
                tex:SetVertexColor(1, 1, 1)
            end
            tintedWorldPins[pin] = nil
        end
    end

    for pin in pairs(keep) do
        tintedWorldPins[pin] = true
    end
end

local function BuildWorldMapCacheForCurrentZone()
    if not WorldMapFrame then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapID)
    end
    if WorldMapFrame.RefreshAllDataProviders then
        WorldMapFrame:RefreshAllDataProviders()
    end
    RefreshWorldMapPins(true)
end

local function IsLowLevelTrackingEnabled()
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        local total = C_Minimap.GetNumTrackingTypes()
        for i = 1, total do
            local name, _, active, _, _, trackingType = C_Minimap.GetTrackingInfo(i)
            if trackingType and Enum and Enum.MinimapTrackingType and trackingType == Enum.MinimapTrackingType.LowLevelQuests then
                return active
            end
            if name and MINIMAP_TRACKING_LOWLEVEL and name == MINIMAP_TRACKING_LOWLEVEL then
                return active
            end
        end
    end
    return true
end

local function RefreshMinimapPins()
    if not IsLowLevelTrackingEnabled() then
        for questID, pin in pairs(minimapPins) do
            HBDPins:RemoveMinimapIcon(ADDON_NAME, pin)
            minimapPins[questID] = nil
        end
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    local quests = C_QuestLog.GetQuestsOnMap(mapID)

    local keep = {}
    local tinted = 0
    if quests then
        for _, info in ipairs(quests) do
            if info and info.questID and info.x and info.y then
                local questID = info.questID
                local isLow = IsLowLevelQuestByID(questID)
                local isAvail = IsAvailableQuestID(questID, info)
                if isLow and isAvail then
                    local pin = minimapPins[questID]
                    if not pin then
                        pin = CreateQuestPin(16)
                        minimapPins[questID] = pin
                    else
                        SetQuestBangTexture(pin.texture)
                    end
                    HBDPins:AddMinimapIconMap(ADDON_NAME, pin, mapID, info.x, info.y, true, ShouldFloatOnEdge())
                    keep[questID] = true
                end
            end
        end
    end

    for questID, loc in pairs(worldQuestLocations) do
        if loc and loc.mapID == mapID and loc.x and loc.y and not keep[questID] then
            local isLow = IsLowLevelQuestByID(questID)
            local isAvail = IsAvailableQuestID(questID)
            if isLow and isAvail then
                local pin = minimapPins[questID]
                if not pin then
                    pin = CreateQuestPin(16)
                    minimapPins[questID] = pin
                else
                    SetQuestBangTexture(pin.texture)
                end
                HBDPins:AddMinimapIconMap(ADDON_NAME, pin, mapID, loc.x, loc.y, true, ShouldFloatOnEdge())
                keep[questID] = true
            end
        end
    end

    for questID, pin in pairs(minimapPins) do
        if not keep[questID] then
            HBDPins:RemoveMinimapIcon(ADDON_NAME, pin)
            minimapPins[questID] = nil
        end
    end

end

local function FullRefresh()
    RefreshWorldMapPins()
    RefreshMinimapPins()
end

local function ResetPins()
    for pin in pairs(tintedWorldPins) do
        local tex = GetPinTexture(pin)
        if tex then
            tex:SetVertexColor(1, 1, 1)
        end
        tintedWorldPins[pin] = nil
    end
    for questID, pin in pairs(minimapPins) do
        HBDPins:RemoveMinimapIcon(ADDON_NAME, pin)
        minimapPins[questID] = nil
    end
    worldQuestLocations = {}
end

local function InitDB()
    if not ShowTheMarkerDB then
        ShowTheMarkerDB = { color = { r = DEFAULT_COLOR.r, g = DEFAULT_COLOR.g, b = DEFAULT_COLOR.b }, minimapFloatOnEdge = false }
    elseif not ShowTheMarkerDB.color then
        ShowTheMarkerDB.color = { r = DEFAULT_COLOR.r, g = DEFAULT_COLOR.g, b = DEFAULT_COLOR.b }
    end
    if ShowTheMarkerDB.minimapFloatOnEdge == nil then
        ShowTheMarkerDB.minimapFloatOnEdge = false
    end
    db = ShowTheMarkerDB
end

local optionsPanel

local function CreateOptionsPanel()
    if optionsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "ShowTheMarker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ShowTheMarker")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Choose the color for low-level quest icons.")

    local swatch = CreateFrame("Button", nil, panel)
    swatch:SetSize(24, 24)
    swatch:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    local swatchTex = swatch:CreateTexture(nil, "OVERLAY")
    swatchTex:SetAllPoints()
    swatchTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    swatch.texture = swatchTex

    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    label:SetText("Low-level quest icon color")

    local function UpdateSwatch()
        local r, g, b = GetColor()
        swatch.texture:SetVertexColor(r, g, b)
    end

    local floatCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    floatCheck:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", 0, -10)
    floatCheck.Text:SetText("Track low-level quests for the entire zone")
    floatCheck:SetScript("OnClick", function(self)
        db.minimapFloatOnEdge = self:GetChecked() and true or false
        FullRefresh()
    end)

    swatch:SetScript("OnClick", function()
        local r, g, b = GetColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                db.color.r, db.color.g, db.color.b = nr, ng, nb
                UpdateSwatch()
                FullRefresh()
            end,
            cancelFunc = function(previousValues)
                if previousValues then
                    db.color.r, db.color.g, db.color.b = previousValues.r, previousValues.g, previousValues.b
                    UpdateSwatch()
                    FullRefresh()
                end
            end,
        })
    end)

    panel:SetScript("OnShow", function()
        UpdateSwatch()
        floatCheck:SetChecked(ShouldFloatOnEdge())
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._settingsCategory = category
    else
        InterfaceOptions_AddCategory(panel)
    end

    optionsPanel = panel
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("SUPER_TRACKING_CHANGED")
f:RegisterEvent("MINIMAP_UPDATE_TRACKING")

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        InitDB()
        CreateOptionsPanel()
        SLASH_SHOWTHEMARKER1 = "/stm"
        SlashCmdList.SHOWTHEMARKER = function(msg)
            local cmd = msg and msg:match("^%s*(.-)%s*$") or ""
            CreateOptionsPanel()
            if optionsPanel and optionsPanel._settingsCategory and Settings and Settings.OpenToCategory then
                local id = optionsPanel._settingsCategory.ID or optionsPanel._settingsCategory.id or optionsPanel._settingsCategory
                Settings.OpenToCategory(id)
            elseif optionsPanel and InterfaceOptionsFrame_OpenToCategory then
                InterfaceOptionsFrame_OpenToCategory(optionsPanel)
                InterfaceOptionsFrame_OpenToCategory(optionsPanel)
            end
        end
        if WorldMapFrame then
            if WorldMapFrame.HasScript and WorldMapFrame:HasScript("OnMapChanged") then
                WorldMapFrame:HookScript("OnMapChanged", RefreshWorldMapPins)
            end
            WorldMapFrame:HookScript("OnShow", RefreshWorldMapPins)
            if WorldMapFrame:IsShown() then
                RefreshWorldMapPins()
            end
        end
        ResetPins()
        BuildWorldMapCacheForCurrentZone()
        FullRefresh()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                BuildWorldMapCacheForCurrentZone()
                FullRefresh()
            end)
        end
        return
    end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        ResetPins()
        FullRefresh()
        return
    end
    FullRefresh()
end)
