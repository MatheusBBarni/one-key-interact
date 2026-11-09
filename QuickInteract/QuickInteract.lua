-- QuickInteract: binds one key to the client's Interact Key system.
--
-- Addons cannot choose an interaction target themselves (InteractUnit is
-- protected), so the game picks the target. This addon only turns that system
-- on and points a key at it. Auto loot is what makes repeated presses move on:
-- a looted corpse stops being a valid target, so the next press takes the next.

local ADDON_NAME = ...

local BINDING_COMMAND = "INTERACTTARGET"
local DISPLAY_NAME = "One Key Interact"
local PREFIX = "|cff33ccff" .. DISPLAY_NAME .. ":|r "

local DEFAULTS = {
    enabled = true,
    key = "F",
    autoLoot = true,
}

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
}

local SOFT_TARGET_UNIT = "softinteract"

local CATEGORIES = {
    { key = "corpses", label = "Corpses" },
    { key = "npcs", label = "NPCs" },
    { key = "ores", label = "Ores" },
    { key = "herbs", label = "Herbs" },
    { key = "objects", label = "Other objects" },
}

-- Node names are the only way to tell gathering nodes apart. They are English,
-- so on other client languages nodes count as "objects".
local HERB_NAMES = {
    ["Peacebloom"] = true, ["Silverleaf"] = true, ["Earthroot"] = true,
    ["Mageroyal"] = true, ["Briarthorn"] = true, ["Stranglekelp"] = true,
    ["Bruiseweed"] = true, ["Wild Steelbloom"] = true, ["Grave Moss"] = true,
    ["Kingsblood"] = true, ["Liferoot"] = true, ["Fadeleaf"] = true,
    ["Goldthorn"] = true, ["Khadgar's Whisker"] = true, ["Wintersbite"] = true,
    ["Firebloom"] = true, ["Purple Lotus"] = true, ["Arthas' Tears"] = true,
    ["Sungrass"] = true, ["Blindweed"] = true, ["Ghost Mushroom"] = true,
    ["Gromsblood"] = true, ["Golden Sansam"] = true, ["Dreamfoil"] = true,
    ["Mountain Silversage"] = true, ["Plaguebloom"] = true, ["Icecap"] = true,
    ["Black Lotus"] = true,
}

local db
local panel
local applyAfterCombat = false
local frame = CreateFrame("Frame")

-- Forever can hide some values from addons; those must not be inspected.
local function IsReadable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Returns the category key of the highlighted target, or nil if it is unknown.
local function GetTargetCategory()
    local guid = UnitGUID(SOFT_TARGET_UNIT)
    if not IsReadable(guid) then
        return nil
    end

    local guidType = strsplit("-", guid)
    if guidType == "GameObject" then
        local name = UnitName(SOFT_TARGET_UNIT)
        if not IsReadable(name) then
            return "objects"
        elseif name:match("Vein$") or name:match("Deposit$") then
            return "ores"
        elseif HERB_NAMES[name] then
            return "herbs"
        end
        return "objects"
    elseif guidType == "Creature" or guidType == "Vehicle" then
        local isDead = UnitIsDead(SOFT_TARGET_UNIT)
        if IsReadable(isDead) then
            return isDead and "corpses" or "npcs"
        end
    end
    return nil
end

-- Unknown targets stay allowed so the key never fails for no visible reason.
local function IsTargetAllowed()
    local category = GetTargetCategory()
    return category == nil or db.categories[category]
end

-- Bindings cannot change in combat, so filters are skipped when combat starts
-- rather than leaving the key stuck off for the whole fight.
local function UpdateKeyBinding(ignoreFilters)
    if InCombatLockdown() then
        return
    end
    -- An override binding is not saved, so the key's normal action returns as
    -- soon as this is cleared.
    ClearOverrideBindings(frame)
    if db.enabled and (ignoreFilters or IsTargetAllowed()) then
        SetOverrideBinding(frame, true, db.key, BINDING_COMMAND)
    end
end

local function Print(message)
    print(PREFIX .. message)
end

-- Returns the CVars this addon wants, given the current options.
local function GetWantedCVars()
    return {
        SoftTargetInteract = db.enabled and "3" or nil, -- always on, mouse and keyboard
        SoftTargetInteractArc = db.enabled and "2" or nil, -- anywhere around the player
        autoLootDefault = (db.enabled and db.autoLoot) and "1" or nil,
    }
end

-- Applies a wanted value, remembering the player's own value the first time so
-- it can be put back. A nil wanted value restores whatever was remembered.
local function SyncCVar(name, wanted)
    if wanted then
        local current = GetCVar(name)
        if current == nil then
            return
        end
        if db.savedCVars[name] == nil then
            db.savedCVars[name] = current
        end
        C_CVar.SetCVar(name, wanted)
    elseif db.savedCVars[name] ~= nil then
        C_CVar.SetCVar(name, db.savedCVars[name])
        db.savedCVars[name] = nil
    end
end

-- Returns false when combat delayed the change.
local function Apply()
    if InCombatLockdown() then
        applyAfterCombat = true
        return false
    end
    applyAfterCombat = false

    local wanted = GetWantedCVars()
    SyncCVar("SoftTargetInteract", wanted.SoftTargetInteract)
    SyncCVar("SoftTargetInteractArc", wanted.SoftTargetInteractArc)
    SyncCVar("autoLootDefault", wanted.autoLootDefault)

    UpdateKeyBinding()
    return true
end

local function ApplyAndReport(message)
    if Apply() then
        Print(message)
    else
        Print(message .. " (applies when combat ends)")
    end
    if panel then
        panel:Refresh()
    end
end

local function SetEnabled(enabled)
    db.enabled = enabled
    ApplyAndReport(enabled and "enabled." or "disabled, your settings are restored.")
end

local function SetAutoLoot(autoLoot)
    db.autoLoot = autoLoot
    ApplyAndReport("auto loot " .. (autoLoot and "on." or "off."))
end

local function SetKey(key)
    db.key = key
    ApplyAndReport("key set to " .. key .. ".")
end

local function SetCategory(category, allowed)
    db.categories[category.key] = allowed
    ApplyAndReport(category.label .. (allowed and " on." or " off."))
end

local function PrintTarget()
    local guid = UnitGUID(SOFT_TARGET_UNIT)
    if not IsReadable(guid) then
        Print("nothing readable is highlighted right now.")
        return
    end
    local name = UnitName(SOFT_TARGET_UNIT)
    Print(("%s, category: %s, type: %s"):format(
        IsReadable(name) and name or "unknown name",
        GetTargetCategory() or "none",
        (strsplit("-", guid))
    ))
end

local function PrintStatus()
    Print(("%s, key: %s, auto loot: %s"):format(
        db.enabled and "on" or "off",
        db.key,
        db.autoLoot and "on" or "off"
    ))
    Print("/qi opens the menu. Also: /qi key <key>, /qi autoloot, /qi on, /qi off, /qi status, /qi check")
end

-- Returns the name of what the key does when this addon is not overriding it.
local function GetReplacedActionName(key)
    local action = GetBindingAction(key)
    if action == "" or action == BINDING_COMMAND then
        return nil
    end
    return _G["BINDING_NAME_" .. action] or action
end

local function CreateCheckbox(parent, xOffset, yOffset, text, onToggle)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", xOffset, yOffset)
    checkbox:SetScript("OnClick", function(self)
        onToggle(self:GetChecked())
    end)

    local label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    label:SetText(text)
    return checkbox
end

local function CreatePanel()
    local window = CreateFrame("Frame", "QuickInteractPanel", UIParent, "DefaultPanelFlatTemplate")
    window:SetSize(300, 290)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    window.TitleContainer.TitleText:SetText(DISPLAY_NAME)
    CreateFrame("Button", nil, window, "UIPanelCloseButtonDefaultAnchors")
    tinsert(UISpecialFrames, window:GetName())

    local keyLabel = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keyLabel:SetPoint("TOPLEFT", 20, -44)
    keyLabel:SetText("Interact key")

    local keyButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    keyButton:SetSize(150, 24)
    keyButton:SetPoint("TOPRIGHT", -20, -38)

    local hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 20, -68)
    hint:SetPoint("TOPRIGHT", -20, -68)
    hint:SetJustifyH("LEFT")

    local enabledCheckbox = CreateCheckbox(window, 16, -90, "Enable " .. DISPLAY_NAME, SetEnabled)
    local autoLootCheckbox = CreateCheckbox(window, 16, -122, "Auto loot corpses", SetAutoLoot)

    local categoriesLabel = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    categoriesLabel:SetPoint("TOPLEFT", 20, -162)
    categoriesLabel:SetText("Interact with")

    local categoryCheckboxes = {}
    for index, category in ipairs(CATEGORIES) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        categoryCheckboxes[category.key] = CreateCheckbox(
            window, 16 + column * 135, -182 - row * 32, category.label,
            function(allowed)
                SetCategory(category, allowed)
            end
        )
    end

    local listening = false

    function window:Refresh()
        if listening then
            keyButton:SetText("Press a key...")
            hint:SetText("Hold Shift, Ctrl or Alt for a combination. Esc cancels.")
        else
            keyButton:SetText(db.key)
            local replaced = GetReplacedActionName(db.key)
            hint:SetText(replaced and ("Replaces " .. replaced .. " while enabled.") or "")
        end
        enabledCheckbox:SetChecked(db.enabled)
        autoLootCheckbox:SetChecked(db.autoLoot)
        for key, checkbox in pairs(categoryCheckboxes) do
            checkbox:SetChecked(db.categories[key])
        end
    end

    local function StopListening()
        listening = false
        keyButton:EnableKeyboard(false)
        window:Refresh()
    end

    keyButton:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then
            return
        end
        StopListening()
        if key == "ESCAPE" then
            return
        end
        if InCombatLockdown() then
            Print("you can't change the key in combat.")
            return
        end
        SetKey((IsAltKeyDown() and "ALT-" or "")
            .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "")
            .. key)
    end)
    -- Assigning OnKeyDown turns keyboard input on, which would swallow every key.
    keyButton:EnableKeyboard(false)

    keyButton:SetScript("OnClick", function()
        if listening then
            StopListening()
        elseif InCombatLockdown() then
            Print("you can't change the key in combat.")
        else
            listening = true
            keyButton:EnableKeyboard(true)
            keyButton:SetPropagateKeyboardInput(false)
            window:Refresh()
        end
    end)

    window:SetScript("OnShow", window.Refresh)
    window:SetScript("OnHide", StopListening)
    return window
end

local function TogglePanel()
    panel = panel or CreatePanel()
    panel:SetShown(not panel:IsShown())
end

SLASH_QUICKINTERACT1 = "/quickinteract"
SLASH_QUICKINTERACT2 = "/qi"
SlashCmdList.QUICKINTERACT = function(input)
    local command, argument = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    command = strlower(command)

    if command == "" then
        TogglePanel()
    elseif command == "on" or command == "off" then
        SetEnabled(command == "on")
    elseif command == "autoloot" then
        SetAutoLoot(not db.autoLoot)
    elseif command == "key" and argument:match("^%S+$") then
        SetKey(strupper(argument))
    elseif command == "check" then
        PrintTarget()
    else
        PrintStatus()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            QuickInteractDB = QuickInteractDB or {}
            db = QuickInteractDB
            for option, value in pairs(DEFAULTS) do
                if db[option] == nil then
                    db[option] = value
                end
            end
            db.savedCVars = db.savedCVars or {}
            db.categories = db.categories or {}
            for _, category in ipairs(CATEGORIES) do
                if db.categories[category.key] == nil then
                    db.categories[category.key] = true
                end
            end
            frame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Runs after saved CVars have loaded, so the player's real values are kept.
        Apply()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateKeyBinding(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if applyAfterCombat then
            Apply()
        else
            UpdateKeyBinding()
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        UpdateKeyBinding()
    end
end)
