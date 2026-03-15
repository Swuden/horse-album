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
local FOOTER_HEIGHT = 16
local DETAIL_PANEL_WIDTH = 440
local SCROLLBAR_WIDTH = 20
local SCROLLBAR_OFFSET = 6
local SCROLLBAR_TO_PANEL_GAP = 12

local RefreshCards
local UpdateDetailsPanel
local SetSelectedMount

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff89dcebHorseAlbum|r: " .. msg)
end

local function CreateCard(parent, index)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(CARD_WIDTH, CARD_HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

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
    activeTag:SetPoint("BOTTOM", 0, 10)
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
        GameTooltip:SetMountBySpellID(self.spellID)
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
        PickupSpell(self.spellID)
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
            local displayID, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)
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

local function TrySetModel(card, mount)
    card.fallback:Hide()
    card.model:Show()

    card.model:ClearModel()
    card.model:SetCamDistanceScale(1.3)
    card.model:SetPortraitZoom(0)
    card.model:SetPosition(0, 0, 0)
    card.model:SetFacing(0.5)

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
    panel.model:SetCamDistanceScale(1.0)
    panel.model:SetPortraitZoom(0)
    panel.model:SetPosition(0, 0, 0)
    panel.model:SetFacing(0.45)

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
        panel.summonButton:Disable()
        return
    end

    panel.nameText:SetText(mount.name or "Unknown Mount")
    panel.sourceText:SetText(mount.sourceText or "")
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
        local desiredWidth = math.max(900, math.floor(parentWidth * 0.8))
        local desiredHeight = math.max(600, math.floor(parentHeight * 0.8))

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
    title:SetText("Horse Album")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Preview and summon your collected mounts")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -8, -8)

    local detailsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailsPanel:SetPoint("TOPRIGHT", -EDGE_PADDING, -HEADER_HEIGHT - EDGE_PADDING)
    detailsPanel:SetPoint("BOTTOMRIGHT", -EDGE_PADDING, EDGE_PADDING + FOOTER_HEIGHT)
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

    local detailsSource = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsSource:SetPoint("TOPLEFT", detailsName, "BOTTOMLEFT", 0, -8)
    detailsSource:SetPoint("TOPRIGHT", detailsName, "BOTTOMRIGHT", 0, -8)
    detailsSource:SetPoint("BOTTOMLEFT", 14, 54)
    detailsSource:SetPoint("BOTTOMRIGHT", -14, 54)
    detailsSource:SetJustifyH("CENTER")
    detailsSource:SetJustifyV("TOP")
    detailsSource:SetText("Click any card to preview it here.")

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

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", EDGE_PADDING, -HEADER_HEIGHT - EDGE_PADDING)
    content:SetPoint("BOTTOMLEFT", EDGE_PADDING, EDGE_PADDING + FOOTER_HEIGHT)

    local scroll = CreateFrame("ScrollFrame", "HorseAlbumScrollFrame", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPRIGHT", detailsPanel, "TOPLEFT", -SCROLLBAR_TO_PANEL_GAP, 0)
    scroll:SetPoint("BOTTOMRIGHT", detailsPanel, "BOTTOMLEFT", -SCROLLBAR_TO_PANEL_GAP, 0)
    scroll:SetWidth(SCROLLBAR_WIDTH)

    content:SetPoint("TOPRIGHT", scroll, "TOPLEFT", -SCROLLBAR_OFFSET, 0)
    content:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMLEFT", -SCROLLBAR_OFFSET, 0)

    frame.title = title
    frame.content = content
    frame.scroll = scroll
    frame.detailsPanel = detailsPanel

    detailsPanel.model = detailsModel
    detailsPanel.modelFallback = detailsFallback
    detailsPanel.nameText = detailsName
    detailsPanel.sourceText = detailsSource
    detailsPanel.summonButton = summonButton

    table.insert(UISpecialFrames, "HorseAlbumFrame")

    HorseAlbum.frame = frame
end

local function GetColumns(frame)
    local width = frame.content:GetWidth()
    local columns = math.max(1, math.floor(((width + CARD_SPACING) / (CARD_WIDTH + CARD_SPACING)) + 0.5))
    return columns
end

local function GetVisibleRows(frame)
    local height = frame.content:GetHeight()
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
        card:SetPoint("TOPLEFT", col * (CARD_WIDTH + CARD_SPACING), -row * (CARD_HEIGHT + CARD_SPACING))

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
    HorseAlbum.mounts = GetCollectedMounts()

    if HorseAlbum.selectedMountID then
        local selectedMount
        for _, mount in ipairs(HorseAlbum.mounts) do
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

    UpdateDetailsPanel()
    RefreshCards()

    if HorseAlbum.frame and HorseAlbum.frame:IsShown() and #HorseAlbum.mounts == 0 then
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
