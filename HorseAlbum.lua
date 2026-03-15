local ADDON_NAME = ...

local HorseAlbum = CreateFrame("Frame")
HorseAlbum.cards = {}
HorseAlbum.mounts = {}
HorseAlbumDB = HorseAlbumDB or {}

local CARD_WIDTH = 280
local CARD_HEIGHT = 260
local CARD_SPACING = 18
local EDGE_PADDING = 24
local HEADER_HEIGHT = 56
local FILTER_BAR_HEIGHT = 28
local FILTER_BAR_GAP = 10
local FOOTER_HEIGHT = 16
local DETAIL_PANEL_WIDTH = 440
local SCROLLBAR_WIDTH = 20
local SCROLLBAR_OFFSET = 6
local SCROLLBAR_TO_PANEL_GAP = 12
local INFO_PANEL_HEIGHT = 250
local MODEL_DEFAULT_FACING = 0.45
local MODEL_ROTATE_SENSITIVITY = 0.02
local MODEL_DEFAULT_ZOOM = 1.0
local MODEL_ZOOM_STEP = 0.08
local MODEL_MIN_ZOOM = 0.55
local MODEL_MAX_ZOOM = 2.2

local RefreshCards
local UpdateDetailsPanel
local SetSelectedMount
local ScrollListByWheel
local ApplyMountFilter
local SetActiveFilter
local UpdateFilterButtons

local FILTER_KEYS = {
    ALL = "ALL",
    FLYING = "FLYING",
    GROUND = "GROUND",
    AQUATIC = "AQUATIC",
}

local FILTER_DEFINITIONS = {
    { key = FILTER_KEYS.ALL,     label = "All" },
    { key = FILTER_KEYS.FLYING,  label = "Flying" },
    { key = FILTER_KEYS.GROUND,  label = "Ground" },
    { key = FILTER_KEYS.AQUATIC, label = "Aquatic" },
}

local FLYING_MOUNT_TYPE_IDS = {
    [242] = true,
    [248] = true,
    [402] = true,
    [424] = true,
}

local GROUND_MOUNT_TYPE_IDS = {
    [230] = true,
    [241] = true,
    [247] = true,
    [269] = true,
    [284] = true,
    [398] = true,
}

local AQUATIC_MOUNT_TYPE_IDS = {
    [231] = true,
    [232] = true,
    [254] = true,
    [269] = true,
    [407] = true,
    [408] = true,
    [412] = true,
}

HorseAlbum.modelFacing = MODEL_DEFAULT_FACING
HorseAlbum.modelZoom = MODEL_DEFAULT_ZOOM
HorseAlbum.allMounts = {}
HorseAlbum.activeFilterKey = FILTER_KEYS.ALL
HorseAlbum.filterButtons = {}

local function MountMatchesFilter(mount, filterKey)
    if filterKey == FILTER_KEYS.ALL then
        return true
    end

    local mountTypeID = mount and mount.mountTypeID
    if not mountTypeID then
        return false
    end

    if filterKey == FILTER_KEYS.FLYING then
        return FLYING_MOUNT_TYPE_IDS[mountTypeID] == true
    elseif filterKey == FILTER_KEYS.GROUND then
        return GROUND_MOUNT_TYPE_IDS[mountTypeID] == true
    elseif filterKey == FILTER_KEYS.AQUATIC then
        return AQUATIC_MOUNT_TYPE_IDS[mountTypeID] == true
    end

    return true
end

local function ClampZoom(zoom)
    return math.max(MODEL_MIN_ZOOM, math.min(MODEL_MAX_ZOOM, zoom))
end

local function GetPanelCamDistanceScale()
    return ClampZoom(HorseAlbum.modelZoom or MODEL_DEFAULT_ZOOM)
end

local function GetCardCamDistanceScale()
    return 1.3 * ClampZoom(HorseAlbum.modelZoom or MODEL_DEFAULT_ZOOM)
end

local function ApplyModelFacing(facing)
    HorseAlbum.modelFacing = facing

    local frame = HorseAlbum.frame
    if not frame then
        return
    end

    if frame.detailsPanel and frame.detailsPanel.model and frame.detailsPanel.model:IsShown() then
        frame.detailsPanel.model:SetFacing(facing)
    end

    for _, card in ipairs(HorseAlbum.cards) do
        if card and card:IsShown() and card.model and card.model:IsShown() then
            card.model:SetFacing(facing)
        end
    end
end

local function ApplyModelZoom(zoom)
    HorseAlbum.modelZoom = ClampZoom(zoom)

    local frame = HorseAlbum.frame
    if not frame then
        return
    end

    if frame.detailsPanel and frame.detailsPanel.model and frame.detailsPanel.model:IsShown() then
        frame.detailsPanel.model:SetCamDistanceScale(GetPanelCamDistanceScale())
    end

    for _, card in ipairs(HorseAlbum.cards) do
        if card and card:IsShown() and card.model and card.model:IsShown() then
            card.model:SetCamDistanceScale(GetCardCamDistanceScale())
        end
    end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff89dcebHorseAlbum|r: " .. msg)
end

local function PickupMountSpell(mountID, spellID)
    local legacyPickupSpell = _G and rawget(_G, "PickupSpell")

    if C_Spell and C_Spell.PickupSpell and spellID then
        C_Spell.PickupSpell(spellID)
        return true
    end

    if legacyPickupSpell and spellID then
        legacyPickupSpell(spellID)
        return true
    end

    if C_MountJournal and C_MountJournal.Pickup and mountID then
        C_MountJournal.Pickup(mountID)
        return true
    end

    return false
end

local function CreateCard(parent, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(CARD_WIDTH, CARD_HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:EnableMouseWheel(true)

    button:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.07, 0.08, 0.10, 0.95)
    button:SetBackdropBorderColor(0.25, 0.27, 0.32, 1)
    button.defaultBorderColor = { 0.25, 0.27, 0.32, 1 }
    button.selectedBorderColor = { 0.66, 0.95, 0.66, 1 }

    local model = CreateFrame("PlayerModel", nil, button)
    model:SetPoint("TOPLEFT", 8, -8)
    model:SetPoint("TOPRIGHT", -8, -8)
    model:SetHeight(185)
    model:SetKeepModelOnHide(true)
    model:EnableMouse(false)

    local fallback = button:CreateTexture(nil, "ARTWORK")
    fallback:SetPoint("TOPLEFT", model, "TOPLEFT")
    fallback:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT")
    fallback:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    fallback:Hide()

    local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 0, -8)
    nameText:SetPoint("TOPRIGHT", model, "BOTTOMRIGHT", 0, -8)
    nameText:SetJustifyH("CENTER")

    local sourceText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
    sourceText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -6)
    sourceText:SetMaxLines(2)
    sourceText:SetJustifyH("CENTER")

    local activeTag = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeTag:SetPoint("BOTTOM", 0, 6)
    activeTag:SetTextColor(0.45, 0.95, 0.55)
    activeTag:SetText("SUMMONED")
    activeTag:Hide()

    button.index = index
    button.model = model
    button.fallback = fallback
    button.nameText = nameText
    button.sourceText = sourceText
    button.activeTag = activeTag

    button:SetScript("OnEnter", function(self)
        if not self.mountID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: Select mount", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Use Summon button in right panel", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Drop on action bar", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if not self.mountData then
            return
        end
        SetSelectedMount(self.mountData)
    end)

    button:SetScript("OnDragStart", function(self)
        if not self.spellID then
            return
        end
        if InCombatLockdown() then
            Print("Cannot drag mount spells while in combat.")
            return
        end
        if not PickupMountSpell(self.mountID, self.spellID) then
            Print("Unable to place this mount on your action bar on this client build.")
        end
    end)

    button:SetScript("OnMouseWheel", function(_, delta)
        ScrollListByWheel(delta)
    end)

    return button
end

local function GetCollectedMounts()
    local mounts = {}
    local mountIDs = C_MountJournal.GetMountIDs()

    for _, mountID in ipairs(mountIDs) do
        local name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
        isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)

        if isCollected then
            local displayID, description, sourceText, isSelfMount, mountTypeID = C_MountJournal.GetMountInfoExtraByID(
                mountID)
            mounts[#mounts + 1] = {
                mountID = mountID,
                name = name,
                spellID = spellID,
                icon = icon,
                isActive = isActive,
                isUsable = isUsable,
                sourceText = sourceText,
                description = description,
                displayID = displayID,
                mountTypeID = mountTypeID,
                favorite = isFavorite,
            }
        end
    end

    table.sort(mounts, function(a, b)
        local aFav = a.favorite and 0 or 1
        local bFav = b.favorite and 0 or 1
        if aFav ~= bFav then
            return aFav < bFav
        end
        if a.name == b.name then
            return a.mountID < b.mountID
        end
        return a.name < b.name
    end)

    return mounts
end

UpdateFilterButtons = function()
    for _, button in ipairs(HorseAlbum.filterButtons) do
        local isSelected = button.filterKey == HorseAlbum.activeFilterKey
        if isSelected then
            button:SetBackdropColor(0.16, 0.24, 0.34, 1)
            button:SetBackdropBorderColor(0.46, 0.74, 1, 1)
            button.text:SetTextColor(0.95, 0.97, 1)
        else
            button:SetBackdropColor(0.08, 0.10, 0.12, 0.95)
            button:SetBackdropBorderColor(0.26, 0.29, 0.33, 1)
            button.text:SetTextColor(0.74, 0.79, 0.85)
        end
    end
end

ApplyMountFilter = function(resetScroll)
    local filteredMounts = {}

    for _, mount in ipairs(HorseAlbum.allMounts or {}) do
        if MountMatchesFilter(mount, HorseAlbum.activeFilterKey) then
            filteredMounts[#filteredMounts + 1] = mount
        end
    end

    HorseAlbum.mounts = filteredMounts

    if HorseAlbum.frame and HorseAlbum.frame.scroll and resetScroll then
        HorseAlbum.frame.scroll.offset = 0
    end
end

SetActiveFilter = function(filterKey)
    if not filterKey or HorseAlbum.activeFilterKey == filterKey then
        return
    end

    HorseAlbum.activeFilterKey = filterKey
    ApplyMountFilter(true)
    UpdateFilterButtons()
    RefreshCards()
end

local function TrySetModel(card, mount)
    card.fallback:Hide()
    card.model:Show()

    card.model:ClearModel()
    card.model:SetCamDistanceScale(GetCardCamDistanceScale())
    card.model:SetPortraitZoom(0)
    card.model:SetPosition(0, 0, 0)
    card.model:SetFacing(HorseAlbum.modelFacing or MODEL_DEFAULT_FACING)

    if not mount.displayID or mount.displayID <= 0 then
        card.model:Hide()
        card.fallback:SetTexture(mount.icon)
        card.fallback:Show()
        return
    end

    local ok = false
    if card.model.SetDisplayInfo then
        ok = pcall(card.model.SetDisplayInfo, card.model, mount.displayID)
    elseif card.model.SetCreature then
        ok = pcall(card.model.SetCreature, card.model, mount.displayID)
    end

    if not ok then
        card.model:Hide()
        card.fallback:SetTexture(mount.icon)
        card.fallback:Show()
    end
end

local function TrySetPanelModel(panel, mount)
    panel.modelFallback:Hide()
    panel.model:Show()

    panel.model:ClearModel()
    panel.model:SetCamDistanceScale(GetPanelCamDistanceScale())
    panel.model:SetPortraitZoom(0)
    panel.model:SetPosition(0, 0, 0)
    panel.model:SetFacing(HorseAlbum.modelFacing or MODEL_DEFAULT_FACING)

    if not mount.displayID or mount.displayID <= 0 then
        panel.model:Hide()
        panel.modelFallback:SetTexture(mount.icon)
        panel.modelFallback:Show()
        return
    end

    local ok = false
    if panel.model.SetDisplayInfo then
        ok = pcall(panel.model.SetDisplayInfo, panel.model, mount.displayID)
    elseif panel.model.SetCreature then
        ok = pcall(panel.model.SetCreature, panel.model, mount.displayID)
    end

    if not ok then
        panel.model:Hide()
        panel.modelFallback:SetTexture(mount.icon)
        panel.modelFallback:Show()
    end
end

UpdateDetailsPanel = function()
    local frame = HorseAlbum.frame
    if not frame then
        return
    end

    local panel = frame.detailsPanel
    local mount = HorseAlbum.selectedMount

    if not mount then
        panel.model:Hide()
        panel.modelFallback:Hide()
        panel.nameText:SetText("Select a mount")
        panel.sourceText:SetText("Click any card to preview it here.")
        panel.descriptionText:SetText("")
        panel.summonButton:Disable()
        return
    end

    panel.nameText:SetText(mount.name or "Unknown Mount")
    panel.sourceText:SetText(mount.sourceText or "")
    panel.descriptionText:SetText(mount.description or "")
    panel.summonButton:Enable()
    TrySetPanelModel(panel, mount)
end

SetSelectedMount = function(mount)
    HorseAlbum.selectedMount = mount
    HorseAlbum.selectedMountID = mount and mount.mountID or nil
    UpdateDetailsPanel()
    RefreshCards()
end

local function EnsureFrame()
    if HorseAlbum.frame then
        return
    end

    local frame = CreateFrame("Frame", "HorseAlbumFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    local function ApplyWindowSize()
        local parentWidth = UIParent:GetWidth() or 0
        local parentHeight = UIParent:GetHeight() or 0
        local desiredWidth = math.max(1000, math.floor(parentWidth * 0.84))
        local desiredHeight = math.max(660, math.floor(parentHeight * 0.84))

        local horizontalChrome =
            (EDGE_PADDING * 2) + SCROLLBAR_OFFSET + SCROLLBAR_WIDTH + SCROLLBAR_TO_PANEL_GAP + DETAIL_PANEL_WIDTH
        local colStride = CARD_WIDTH + CARD_SPACING
        local desiredContentWidth = math.max(CARD_WIDTH, desiredWidth - horizontalChrome)

        -- Snap width to an integer number of columns to avoid large empty space on the right.
        local columns = math.max(1, math.floor(((desiredContentWidth + CARD_SPACING) / colStride) + 0.5))
        local snappedContentWidth = (columns * colStride) - CARD_SPACING
        local width = snappedContentWidth + horizontalChrome

        local verticalChrome = HEADER_HEIGHT + (EDGE_PADDING * 2) + FOOTER_HEIGHT
        local rowStride = CARD_HEIGHT + CARD_SPACING
        local desiredContentHeight = math.max(CARD_HEIGHT, desiredHeight - verticalChrome)

        -- Snap height to an integer number of rows to avoid large empty space at the bottom.
        local rows = math.max(1, math.floor(((desiredContentHeight + CARD_SPACING) / rowStride) + 0.5))
        local snappedContentHeight = (rows * rowStride) - CARD_SPACING
        local height = snappedContentHeight + verticalChrome

        frame:SetSize(width, height)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
    end

    ApplyWindowSize()
    frame:SetScript("OnShow", ApplyWindowSize)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.03, 0.04, 0.05, 0.96)
    frame:SetBackdropBorderColor(0.18, 0.20, 0.24, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("HorseAlbum")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Preview and summon your collected mounts")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -8, -8)

    local detailsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailsPanel:SetPoint("TOPRIGHT", -EDGE_PADDING, -HEADER_HEIGHT - EDGE_PADDING)
    detailsPanel:SetPoint("BOTTOMRIGHT", -EDGE_PADDING, EDGE_PADDING + FOOTER_HEIGHT + INFO_PANEL_HEIGHT + CARD_SPACING)
    detailsPanel:SetWidth(DETAIL_PANEL_WIDTH)
    detailsPanel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    detailsPanel:SetBackdropColor(0.06, 0.08, 0.10, 0.96)
    detailsPanel:SetBackdropBorderColor(0.2, 0.25, 0.3, 1)

    local detailsTitle = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailsTitle:SetPoint("TOPLEFT", 12, -12)
    detailsTitle:SetPoint("TOPRIGHT", -12, -12)
    detailsTitle:SetJustifyH("CENTER")
    detailsTitle:SetText("Selected Mount")

    local detailsModel = CreateFrame("PlayerModel", nil, detailsPanel)
    detailsModel:SetPoint("TOPLEFT", 12, -42)
    detailsModel:SetPoint("TOPRIGHT", -12, -42)
    detailsModel:SetHeight(320)
    detailsModel:SetKeepModelOnHide(true)

    local rotateOverlay = CreateFrame("Frame", nil, detailsPanel)
    rotateOverlay:SetPoint("TOPLEFT", detailsModel, "TOPLEFT")
    rotateOverlay:SetPoint("BOTTOMRIGHT", detailsModel, "BOTTOMRIGHT")
    rotateOverlay:EnableMouse(true)
    rotateOverlay:EnableMouseWheel(true)

    rotateOverlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end

        local x = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        HorseAlbum.isModelRotating = true
        HorseAlbum.lastRotateCursorX = x / scale
    end)

    rotateOverlay:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            HorseAlbum.isModelRotating = false
        end
    end)

    rotateOverlay:SetScript("OnHide", function()
        HorseAlbum.isModelRotating = false
    end)

    rotateOverlay:SetScript("OnUpdate", function()
        if not HorseAlbum.isModelRotating then
            return
        end

        if not IsMouseButtonDown("LeftButton") then
            HorseAlbum.isModelRotating = false
            return
        end

        local x = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        local cursorX = x / scale
        local deltaX = cursorX - (HorseAlbum.lastRotateCursorX or cursorX)
        HorseAlbum.lastRotateCursorX = cursorX

        if deltaX ~= 0 then
            local facing = (HorseAlbum.modelFacing or MODEL_DEFAULT_FACING) + (deltaX * MODEL_ROTATE_SENSITIVITY)
            ApplyModelFacing(facing)
        end
    end)

    rotateOverlay:SetScript("OnMouseWheel", function(_, delta)
        if delta == 0 then
            return
        end

        local zoom = (HorseAlbum.modelZoom or MODEL_DEFAULT_ZOOM) - (delta * MODEL_ZOOM_STEP)
        ApplyModelZoom(zoom)
    end)

    local detailsFallback = detailsPanel:CreateTexture(nil, "ARTWORK")
    detailsFallback:SetPoint("TOPLEFT", detailsModel, "TOPLEFT")
    detailsFallback:SetPoint("BOTTOMRIGHT", detailsModel, "BOTTOMRIGHT")
    detailsFallback:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    detailsFallback:Hide()

    local detailsName = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailsName:SetPoint("TOPLEFT", detailsModel, "BOTTOMLEFT", 0, -12)
    detailsName:SetPoint("TOPRIGHT", detailsModel, "BOTTOMRIGHT", 0, -12)
    detailsName:SetJustifyH("CENTER")
    detailsName:SetText("Select a mount")

    local summonButton = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    summonButton:SetSize(160, 28)
    summonButton:SetPoint("BOTTOM", 0, 16)
    summonButton:SetText("Summon")
    summonButton:Disable()
    summonButton:SetScript("OnClick", function()
        local mount = HorseAlbum.selectedMount
        if not mount or not mount.mountID then
            return
        end
        if InCombatLockdown() then
            Print("Cannot summon mounts while in combat.")
            return
        end
        C_MountJournal.SummonByID(mount.mountID)
    end)

    local detailsSource = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsSource:SetPoint("TOPLEFT", detailsName, "BOTTOMLEFT", 0, -8)
    detailsSource:SetPoint("TOPRIGHT", detailsName, "BOTTOMRIGHT", 0, -8)
    detailsSource:SetPoint("LEFT", 14, 0)
    detailsSource:SetPoint("RIGHT", -14, 0)
    detailsSource:SetJustifyH("CENTER")
    detailsSource:SetJustifyV("TOP")
    detailsSource:SetMaxLines(2)
    detailsSource:SetText("Click any card to preview it here.")

    local detailsDescription = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsDescription:SetPoint("TOPLEFT", detailsSource, "BOTTOMLEFT", 0, -8)
    detailsDescription:SetPoint("TOPRIGHT", detailsSource, "BOTTOMRIGHT", 0, -8)
    detailsDescription:SetPoint("BOTTOMLEFT", 14, 52)
    detailsDescription:SetPoint("BOTTOMRIGHT", -14, 52)
    detailsDescription:SetJustifyH("CENTER")
    detailsDescription:SetJustifyV("TOP")
    detailsDescription:SetText("")

    local infoPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    infoPanel:SetPoint("TOPLEFT", detailsPanel, "BOTTOMLEFT", 0, -CARD_SPACING)
    infoPanel:SetPoint("TOPRIGHT", detailsPanel, "BOTTOMRIGHT", 0, -CARD_SPACING)
    infoPanel:SetHeight(INFO_PANEL_HEIGHT)
    infoPanel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    infoPanel:SetBackdropColor(0.06, 0.08, 0.10, 0.96)
    infoPanel:SetBackdropBorderColor(0.2, 0.25, 0.3, 1)

    local infoTitle = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    infoTitle:SetPoint("TOPLEFT", 12, -18)
    infoTitle:SetPoint("TOPRIGHT", -12, -18)
    infoTitle:SetJustifyH("CENTER")
    infoTitle:SetJustifyV("TOP")
    infoTitle:SetText("HorseAlbum")

    local infoBody = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoBody:SetPoint("TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -8)
    infoBody:SetPoint("TOPRIGHT", infoTitle, "BOTTOMRIGHT", 0, -8)
    infoBody:SetPoint("BOTTOMLEFT", 12, 14)
    infoBody:SetPoint("BOTTOMRIGHT", -12, 14)
    infoBody:SetJustifyH("CENTER")
    infoBody:SetJustifyV("TOP")
    infoBody:SetTextColor(1, 1, 1)
    infoBody:SetText(
        "by Veinlash of Karazhan-EU\n\nFeatures\n- Browse all collected mounts with 3D cards\n- Filter by All, Flying, Ground, and Aquatic\n- View detailed mount source and description\n- Summon directly from the right panel\n- Drag mounts to your action bars\n- Rotate and zoom mount models\n\nHow to use\n1. Open HorseAlbum and click any card to select a mount.\n2. Use filter buttons at the top to narrow your list.\n3. Rotate with mouse drag and zoom with mouse wheel.\n4. Click Summon in the details panel to call the mount.\n5. Drag a mount card to an action bar for quick access.")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", EDGE_PADDING, -HEADER_HEIGHT - EDGE_PADDING)
    content:SetPoint("BOTTOMLEFT", EDGE_PADDING, EDGE_PADDING + FOOTER_HEIGHT)
    content:EnableMouse(true)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        ScrollListByWheel(delta)
    end)

    local scroll = CreateFrame("ScrollFrame", "HorseAlbumScrollFrame", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPRIGHT", detailsPanel, "TOPLEFT", -SCROLLBAR_TO_PANEL_GAP, 0)
    scroll:SetPoint("BOTTOMRIGHT", detailsPanel, "BOTTOMLEFT", -SCROLLBAR_TO_PANEL_GAP, 0)
    scroll:SetWidth(SCROLLBAR_WIDTH)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        ScrollListByWheel(delta)
    end)

    content:SetPoint("TOPRIGHT", scroll, "TOPLEFT", -SCROLLBAR_OFFSET, 0)
    content:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMLEFT", -SCROLLBAR_OFFSET, 0)

    local filterBar = CreateFrame("Frame", nil, content)
    filterBar:SetPoint("TOPLEFT", 0, 0)
    filterBar:SetPoint("TOPRIGHT", 0, 0)
    filterBar:SetHeight(FILTER_BAR_HEIGHT)

    local buttonWidth = 102
    local buttonGap = 8
    local previousButton
    for _, filterDef in ipairs(FILTER_DEFINITIONS) do
        local button = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
        button:SetSize(buttonWidth, FILTER_BAR_HEIGHT)
        button:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })

        if previousButton then
            button:SetPoint("LEFT", previousButton, "RIGHT", buttonGap, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end

        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(filterDef.label)

        button.text = text
        button.filterKey = filterDef.key
        button:SetScript("OnClick", function(self)
            SetActiveFilter(self.filterKey)
        end)

        HorseAlbum.filterButtons[#HorseAlbum.filterButtons + 1] = button
        previousButton = button
    end

    frame.title = title
    frame.content = content
    frame.scroll = scroll
    frame.filterBar = filterBar
    frame.detailsPanel = detailsPanel
    frame.infoPanel = infoPanel

    detailsPanel.model = detailsModel
    detailsPanel.rotateOverlay = rotateOverlay
    detailsPanel.modelFallback = detailsFallback
    detailsPanel.nameText = detailsName
    detailsPanel.sourceText = detailsSource
    detailsPanel.descriptionText = detailsDescription
    detailsPanel.summonButton = summonButton

    table.insert(UISpecialFrames, "HorseAlbumFrame")

    HorseAlbum.frame = frame
    UpdateFilterButtons()
end

local function GetColumns(frame)
    local width = frame.content:GetWidth()
    local columns = math.max(1, math.floor(((width + CARD_SPACING) / (CARD_WIDTH + CARD_SPACING)) + 0.5))
    return columns
end

local function GetVisibleRows(frame)
    local reservedHeight = FILTER_BAR_HEIGHT + FILTER_BAR_GAP
    local height = math.max(CARD_HEIGHT, frame.content:GetHeight() - reservedHeight)
    local rows = math.max(1, math.floor(((height + CARD_SPACING) / (CARD_HEIGHT + CARD_SPACING)) + 0.5))
    return rows
end

local function AcquireCard(index)
    local card = HorseAlbum.cards[index]
    if card then
        return card
    end

    card = CreateCard(HorseAlbum.frame.content, index)
    HorseAlbum.cards[index] = card
    return card
end

ScrollListByWheel = function(delta)
    local frame = HorseAlbum.frame
    if not frame or not frame:IsShown() then
        return
    end

    local columns = GetColumns(frame)
    local visibleRows = GetVisibleRows(frame)
    local totalRows = math.ceil(#HorseAlbum.mounts / columns)
    local maxOffset = math.max(0, totalRows - visibleRows)
    local currentOffset = FauxScrollFrame_GetOffset(frame.scroll)
    local newOffset = math.max(0, math.min(maxOffset, currentOffset - delta))

    if newOffset == currentOffset then
        return
    end

    local step = CARD_HEIGHT + CARD_SPACING
    FauxScrollFrame_OnVerticalScroll(frame.scroll, newOffset * step, step, RefreshCards)
end

RefreshCards = function()
    local frame = HorseAlbum.frame
    if not frame or not frame:IsShown() then
        return
    end

    local mounts = HorseAlbum.mounts
    local columns = GetColumns(frame)
    local rows = GetVisibleRows(frame)
    local cardsNeeded = rows * columns

    local totalRows = math.ceil(#mounts / columns)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)

    FauxScrollFrame_Update(frame.scroll, totalRows, rows, CARD_HEIGHT + CARD_SPACING)

    for i = 1, cardsNeeded do
        local card = AcquireCard(i)
        local row = math.floor((i - 1) / columns)
        local col = (i - 1) % columns
        local dataIndex = (offset + row) * columns + col + 1
        local mount = mounts[dataIndex]

        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", col * (CARD_WIDTH + CARD_SPACING),
            -(FILTER_BAR_HEIGHT + FILTER_BAR_GAP) - (row * (CARD_HEIGHT + CARD_SPACING)))

        if mount then
            card.mountID = mount.mountID
            card.spellID = mount.spellID
            card.mountData = mount
            card.nameText:SetText(mount.name or "Unknown Mount")
            card.sourceText:SetText(mount.sourceText or "")
            card.activeTag:SetShown(mount.isActive)
            if HorseAlbum.selectedMountID and mount.mountID == HorseAlbum.selectedMountID then
                card:SetBackdropBorderColor(unpack(card.selectedBorderColor))
            else
                card:SetBackdropBorderColor(unpack(card.defaultBorderColor))
            end
            TrySetModel(card, mount)
            card:Show()
        else
            card.mountID = nil
            card.spellID = nil
            card.mountData = nil
            card:Hide()
        end
    end

    for i = cardsNeeded + 1, #HorseAlbum.cards do
        local hiddenCard = HorseAlbum.cards[i]
        hiddenCard.mountData = nil
        hiddenCard:SetBackdropBorderColor(unpack(hiddenCard.defaultBorderColor))
        hiddenCard:Hide()
    end
end

local function RefreshData()
    HorseAlbum.allMounts = GetCollectedMounts()

    if HorseAlbum.selectedMountID then
        local selectedMount
        for _, mount in ipairs(HorseAlbum.allMounts) do
            if mount.mountID == HorseAlbum.selectedMountID then
                selectedMount = mount
                break
            end
        end
        HorseAlbum.selectedMount = selectedMount
        if not selectedMount then
            HorseAlbum.selectedMountID = nil
        end
    end

    ApplyMountFilter(false)

    UpdateDetailsPanel()
    RefreshCards()

    if HorseAlbum.frame and HorseAlbum.frame:IsShown() and #HorseAlbum.allMounts == 0 then
        Print("No collected mounts found.")
    end
end

local function ToggleFrame()
    EnsureFrame()

    if HorseAlbum.frame:IsShown() then
        HorseAlbum.frame:Hide()
        return
    end

    RefreshData()
    HorseAlbum.frame:Show()
    RefreshCards()
end

local function RegisterSlashCommands()
    SLASH_HORSEALBUM1 = "/horsealbum"
    SLASH_HORSEALBUM2 = "/ha"
    SlashCmdList.HORSEALBUM = function()
        ToggleFrame()
    end
end

HorseAlbum:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then
            return
        end

        EnsureFrame()
        RegisterSlashCommands()
        RefreshData()

        HorseAlbum.frame.scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, CARD_HEIGHT + CARD_SPACING, RefreshCards)
        end)

        HorseAlbum.frame:SetScript("OnSizeChanged", function()
            RefreshCards()
        end)

        Print("Loaded. Type /horsealbum or /ha")
    elseif event == "COMPANION_UPDATE" then
        local companionType = ...
        if companionType == "MOUNT" then
            RefreshData()
        end
    elseif event == "NEW_MOUNT_ADDED" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "MOUNT_JOURNAL_USABILITY_CHANGED" then
        RefreshData()
    end
end)

HorseAlbum:RegisterEvent("ADDON_LOADED")
HorseAlbum:RegisterEvent("COMPANION_UPDATE")
HorseAlbum:RegisterEvent("NEW_MOUNT_ADDED")
HorseAlbum:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
HorseAlbum:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
