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
        GameTooltip:AddLine("Left-click: Summon mount", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Drop on action bar", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if not self.mountID then
            return
        end
        if InCombatLockdown() then
            Print("Cannot summon mounts while in combat.")
            return
        end
        C_MountJournal.SummonByID(self.mountID)
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

local function EnsureFrame()
    if HorseAlbum.frame then
        return
    end

    local frame = CreateFrame("Frame", "HorseAlbumFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetAllPoints(UIParent)
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

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", EDGE_PADDING, -HEADER_HEIGHT - EDGE_PADDING)
    content:SetPoint("BOTTOMRIGHT", -EDGE_PADDING - 26, EDGE_PADDING + FOOTER_HEIGHT)

    local scroll = CreateFrame("ScrollFrame", "HorseAlbumScrollFrame", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", content, "TOPRIGHT", 6, 0)
    scroll:SetPoint("BOTTOMLEFT", content, "BOTTOMRIGHT", 6, 0)
    scroll:SetWidth(20)

    frame.title = title
    frame.content = content
    frame.scroll = scroll

    table.insert(UISpecialFrames, "HorseAlbumFrame")

    HorseAlbum.frame = frame
end

local function GetColumns(frame)
    local width = frame.content:GetWidth()
    local columns = math.max(1, math.floor((width + CARD_SPACING) / (CARD_WIDTH + CARD_SPACING)))
    return columns
end

local function GetVisibleRows(frame)
    local height = frame.content:GetHeight()
    local rows = math.max(1, math.floor((height + CARD_SPACING) / (CARD_HEIGHT + CARD_SPACING)))
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

local function RefreshCards()
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
            card.nameText:SetText(mount.name or "Unknown Mount")
            card.sourceText:SetText(mount.sourceText or "")
            card.activeTag:SetShown(mount.isActive)
            TrySetModel(card, mount)
            card:Show()
        else
            card.mountID = nil
            card.spellID = nil
            card:Hide()
        end
    end

    for i = cardsNeeded + 1, #HorseAlbum.cards do
        HorseAlbum.cards[i]:Hide()
    end
end

local function RefreshData()
    HorseAlbum.mounts = GetCollectedMounts()
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
