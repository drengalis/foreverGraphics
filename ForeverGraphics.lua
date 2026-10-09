-- Forever Graphics - World of Warcraft: Forever (Camelot, interface 16001)
-- Fixed reset values are from https://warcraft.wiki.gg/wiki/Console_variables
-- The sliders use practical UI ranges; client/engine limits can differ.

local ADDON_NAME = ...
local wikiSettings = {
    {
        name = "Ground Effect Density", cvar = "groundEffectDensity",
        default = 16, suggested = 256, min = 16, max = 256, step = 1,
        description = "Controls how densely grass, small plants, and other ground clutter appear. Higher values place more foliage on the terrain.",
        impact = "Higher density can reduce FPS in vegetation-heavy areas.",
    },
    {
        name = "Ground Effect Fade", cvar = "groundEffectFade",
        default = 70, suggested = 370, min = 0, max = 500, step = 5,
        description = "Controls how ground clutter fades in or out with distance. Higher values can make the transition to distant grass less noticeable.",
        impact = "Works together with Ground Effect Distance. Visual results depend on the zone and client.",
    },
    {
        name = "Ground Effect Distance", cvar = "groundEffectDist",
        default = 70, suggested = 500, min = 40, max = 500, step = 5,
        description = "Controls how far away ground clutter such as grass and flowers is rendered. Higher values keep vegetation visible farther away.",
        impact = "Higher distances can increase the rendering workload.",
    },
    {
        name = "Object LOD Fade Scale", cvar = "lodObjectFadeScale",
        default = 100, suggested = 200, min = 50, max = 300, step = 5,
        description = "Changes the distance at which world objects transition between levels of detail. Increasing it can preserve detailed trees and objects farther away.",
        impact = "Higher values may use more GPU resources.",
    },
    {
        name = "Object Cull Size", cvar = "lodObjectCullSize",
        default = 15, suggested = 8, min = 1, max = 100, step = 1,
        description = "Sets the approximate on-screen size below which distant objects can be culled (not drawn). Lower values keep smaller distant objects visible.",
        impact = "Unlike most quality sliders, LOWER means more objects and can cost FPS.",
    },
    {
        name = "Terrain LOD Distance", cvar = "terrainLodDist",
        default = 400, suggested = 1000, min = 100, max = 2000, step = 10,
        description = "Controls how far detailed terrain remains visible before distant terrain meshes switch to lower detail. Higher values can improve distant hills and ridges.",
        impact = "Long distances can affect performance. Reset uses 400; some Forever clients may use 500 as their native default.",
    },
    {
        name = "Always Sharpen", cvar = "ResampleAlwaysSharpen",
        default = 0, suggested = 1, min = 0, max = 1, step = 1,
        description = "0 = Off; 1 = On. Runs the image-sharpening pass even when AMD FSR upscaling is not in use.",
        impact = "May sharpen fine detail, but can also exaggerate edges or image noise.",
    },
    {
        name = "Reflection Mode", cvar = "reflectionMode",
        default = 3, suggested = 3, min = 0, max = 3, step = 1,
        description = "Sets the water and scene reflection rendering mode, from 0 to 3. Higher modes generally allow more detailed reflections.",
        impact = "More detailed reflections can increase GPU workload; available effects vary by scene.",
    },
}

local mainFrame
local rows = {}
local statusText

local function CurrentCVar(name)
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        return C_CVar.GetCVar(name)
    elseif type(GetCVar) == "function" then
        return GetCVar(name)
    end
    return nil
end

local function WriteCVar(name, value)
    local stringValue = tostring(value)
    if C_CVar and type(C_CVar.SetCVar) == "function" then
        return C_CVar.SetCVar(name, stringValue)
    elseif type(SetCVar) == "function" then
        return SetCVar(name, stringValue)
    end
    error("CVar setting API is unavailable in this client")
end

local function Message(message, isError)
    if not statusText then return end
    statusText:SetText(message)
    if isError then
        statusText:SetTextColor(1.0, 0.48, 0.43)
    else
        statusText:SetTextColor(0.54, 0.88, 0.65)
    end
end

local function ReadBack(setting)
    local value = CurrentCVar(setting.cvar)
    if value == nil or value == "" then return nil end
    return tostring(value)
end

local function RoundToStep(setting, number)
    local rounded = setting.min + math.floor((number - setting.min) / setting.step + 0.5) * setting.step
    if rounded < setting.min then return setting.min end
    if rounded > setting.max then return setting.max end
    return rounded
end

local function SetSliderValue(row, number)
    row.ignoreSliderChange = true
    row.slider:SetValue(RoundToStep(row.setting, number))
    row.ignoreSliderChange = false
end

local function RefreshRow(row, discardPending)
    local current = ReadBack(row.setting)
    local numeric = current and tonumber(current) or nil
    local available = numeric ~= nil

    row.current:SetText(current or "N/A")
    row.apply:SetEnabled(available)
    row.reset:SetEnabled(available)
    if available then
        row.slider:Enable()
    else
        row.slider:Disable()
    end

    if discardPending or not row.dirty then
        row.dirty = false
        if available then
            row.selectedValue = RoundToStep(row.setting, numeric)
            SetSliderValue(row, numeric)
            row.selection:SetText(tostring(row.selectedValue))
            row.dirty = row.selectedValue ~= numeric
        else
            row.selectedValue = nil
            row.selection:SetText("N/A")
        end
    end

    if not available then
        row.current:SetTextColor(1.0, 0.48, 0.43)
    elseif numeric == row.setting.default then
        row.current:SetTextColor(0.54, 0.88, 0.65)
    else
        row.current:SetTextColor(1.0, 0.85, 0.45)
    end

    if row.dirty then
        row.selection:SetTextColor(1.0, 0.85, 0.45)
    else
        row.selection:SetTextColor(0.91, 0.94, 1.0)
    end
end

local function RefreshAll(discardPending)
    for _, row in ipairs(rows) do
        RefreshRow(row, discardPending)
    end
end

local function ApplyValue(setting, number)
    local ok, result = pcall(WriteCVar, setting.cvar, number)
    if not ok then return false, tostring(result) end
    if result == false then return false, "The client rejected the change" end

    local actual = ReadBack(setting)
    if actual == nil then return false, "This CVar cannot be read on this client" end
    if tonumber(actual) ~= number then
        return false, "Requested " .. number .. ", client reports " .. actual
    end
    return true, actual
end

local function ApplyRow(row, numberOverride)
    local value = numberOverride or row.selectedValue
    if not value then
        Message(row.setting.cvar .. ": no valid value is available.", true)
        return
    end
    local ok, details = ApplyValue(row.setting, value)
    row.dirty = false
    RefreshRow(row, true)
    if ok then
        Message(row.setting.cvar .. " set to " .. details .. ".", false)
    else
        Message(row.setting.cvar .. ": " .. details .. ".", true)
    end
end

local function ApplyGroup(useSuggested)
    local successes, failures, firstError = 0, 0, nil
    for _, setting in ipairs(wikiSettings) do
        local target = useSuggested and setting.suggested or setting.default
        if ReadBack(setting) ~= nil then
            local ok, details = ApplyValue(setting, target)
            if ok then
                successes = successes + 1
            else
                failures = failures + 1
                if not firstError then firstError = setting.cvar .. ": " .. details end
            end
        else
            failures = failures + 1
            if not firstError then firstError = setting.cvar .. ": not available" end
        end
    end
    RefreshAll(true)
    local action = useSuggested and "Suggested values" or "Defaults"
    if failures > 0 then
        Message(action .. ": " .. successes .. "/8 applied. " .. firstError, true)
    else
        Message(action .. ": all 8 values applied.", false)
    end
end

local function MakeLabel(parent, text, font, x, y, width, alignment)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH(alignment or "LEFT")
    label:SetText(text)
    return label
end

local function MakeButton(parent, text, width, height, x, y, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function MakeRowLabel(parent, text, font, x, width, alignment)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("LEFT", parent, "LEFT", x, 0)
    label:SetWidth(width)
    label:SetJustifyH(alignment or "LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetText(text)
    return label
end

local function MakeRowButton(parent, text, width, height, x, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint("LEFT", parent, "LEFT", x, 0)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function MakeInfoIcon(parent, setting, x)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(17, 17)
    button:SetPoint("LEFT", parent, "LEFT", x, 0)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.19, 0.34, 0.49, 0.95)
    local textIcon = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
    textIcon:SetText("i")
    textIcon:SetTextColor(0.78, 0.91, 1.0)

    local function ShowHelp(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText(setting.name, 1.0, 0.83, 0.25)
        GameTooltip:AddLine(setting.description, 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(setting.impact, 0.77, 0.88, 1.0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("CVar", setting.cvar, 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Slider range", setting.min .. " - " .. setting.max, 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Default", tostring(setting.default), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Suggested", tostring(setting.suggested), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:Show()
    end
    button:SetScript("OnEnter", ShowHelp)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        else
            ShowHelp(self)
        end
    end)
    return button
end

local function SaveFramePosition(frame)
    ForeverGraphicsDB = ForeverGraphicsDB or {}
    local x, y = frame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if x and y and cx and cy then
        ForeverGraphicsDB.x = x - cx
        ForeverGraphicsDB.y = y - cy
    end
end

local function CreateUI()
    local frame = CreateFrame("Frame", "ForeverGraphicsPanel", UIParent, "BackdropTemplate")
    mainFrame = frame
    frame:SetSize(1030, 634)
    frame:SetPoint("CENTER", UIParent, "CENTER",
        (ForeverGraphicsDB and ForeverGraphicsDB.x) or 0,
        (ForeverGraphicsDB and ForeverGraphicsDB.y) or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self)
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.07, 0.1, 0.98)
    frame:SetBackdropBorderColor(0.3, 0.43, 0.54, 1)
    frame:Hide()

    MakeLabel(frame, "Forever Graphics", "GameFontNormalLarge", 24, -23, 420)
    local subtitle = MakeLabel(frame,
        "Move a slider to choose a value, then click Apply. Reset immediately applies the listed default.",
        "GameFontHighlightSmall", 24, -55, 975)
    subtitle:SetTextColor(0.72, 0.77, 0.85)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.34, 0.43, 0.53, 0.6)
    line:SetSize(982, 1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -91)

    MakeLabel(frame, "SETTING", "GameFontNormalSmall", 29, -109, 225)
    MakeLabel(frame, "CURRENT", "GameFontNormalSmall", 275, -109, 82, "CENTER")
    MakeLabel(frame, "SLIDER", "GameFontNormalSmall", 405, -109, 300, "CENTER")
    MakeLabel(frame, "DEFAULT", "GameFontNormalSmall", 753, -109, 90, "CENTER")
    MakeLabel(frame, "ACTION", "GameFontNormalSmall", 865, -109, 130, "CENTER")

    for index, setting in ipairs(wikiSettings) do
        local top = -133 - (index - 1) * 47
        local rowFrame = CreateFrame("Frame", nil, frame)
        rowFrame:SetSize(998, 45)
        rowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, top)

        local stripe = rowFrame:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        if index % 2 == 0 then
            stripe:SetColorTexture(0.17, 0.21, 0.28, 0.55)
        else
            stripe:SetColorTexture(0.10, 0.14, 0.20, 0.65)
        end

        local row = { setting = setting, dirty = false, ignoreSliderChange = false }
        rows[#rows + 1] = row

        MakeRowLabel(rowFrame, setting.name, "GameFontNormal", 13, 213)
        MakeInfoIcon(rowFrame, setting, 228)

        row.current = MakeRowLabel(rowFrame, "", "GameFontHighlight", 259, 82, "CENTER")
        MakeRowLabel(rowFrame, tostring(setting.default), "GameFontHighlight", 744, 76, "CENTER")

        local slider = CreateFrame("Slider", nil, rowFrame, "OptionsSliderTemplate")
        row.slider = slider
        slider:SetSize(300, 16)
        slider:SetPoint("CENTER", rowFrame, "LEFT", 539, 0)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(setting.min, setting.max)
        slider:SetValueStep(setting.step)
        if type(slider.SetObeyStepOnDrag) == "function" then
            slider:SetObeyStepOnDrag(true)
        end

        row.selection = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.selection:SetPoint("BOTTOM", slider, "TOP", 0, -3)
        row.selection:SetWidth(76)
        row.selection:SetJustifyH("CENTER")

        slider:SetValue(setting.default)
        if slider.Low and type(slider.Low) ~= "function" then slider.Low:Hide() end
        if slider.High and type(slider.High) ~= "function" then slider.High:Hide() end
        if type(slider.GetRegions) == "function" then
            local regions = { slider:GetRegions() }
            for _, region in ipairs(regions) do
                if region and region.IsObjectType and region:IsObjectType("FontString") then
                    region:Hide()
                end
            end
        end

        slider:SetScript("OnValueChanged", function(self, value)
            if row.ignoreSliderChange then return end
            local snapped = RoundToStep(setting, value)
            row.selectedValue = snapped
            row.dirty = tonumber(ReadBack(setting)) ~= snapped
            row.selection:SetText(tostring(snapped))
            if row.dirty then
                row.selection:SetTextColor(1.0, 0.85, 0.45)
            else
                row.selection:SetTextColor(0.91, 0.94, 1.0)
            end
            if value ~= snapped then SetSliderValue(row, snapped) end
        end)

        local low = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        low:SetWidth(33)
        low:SetJustifyH("RIGHT")
        low:SetPoint("RIGHT", slider, "LEFT", -6, 0)
        low:SetText(tostring(setting.min))
        low:SetTextColor(0.75, 0.81, 0.91)

        local high = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        high:SetWidth(34)
        high:SetJustifyH("LEFT")
        high:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        high:SetText(tostring(setting.max))
        high:SetTextColor(0.75, 0.81, 0.91)

        row.apply = MakeRowButton(rowFrame, "Apply", 74, 25, 826, function()
            ApplyRow(row)
        end)
        row.reset = MakeRowButton(rowFrame, "Reset", 83, 25, 909, function()
            ApplyRow(row, setting.default)
        end)
    end

    local bottomLine = frame:CreateTexture(nil, "ARTWORK")
    bottomLine:SetColorTexture(0.34, 0.43, 0.53, 0.6)
    bottomLine:SetSize(982, 1)
    bottomLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -517)

    local note = MakeLabel(frame,
        "Hover over an i icon for details. Values above sliders remain pending until Apply. Reset uses the listed default.",
        "GameFontHighlightSmall", 24, -529, 970)
    note:SetTextColor(0.7, 0.76, 0.84)

    MakeButton(frame, "Apply Suggested (8)", 181, 29, 24, -552, function()
        ApplyGroup(true)
    end)
    MakeButton(frame, "Reset All to Default", 163, 29, 216, -552, function()
        StaticPopup_Show("FOREVER_GRAPHICS_RESET_ALL")
    end)
    MakeButton(frame, "Refresh Values", 139, 29, 390, -552, function()
        RefreshAll(true)
        Message("Current values reloaded; pending slider edits discarded.", false)
    end)
    MakeButton(frame, "Close", 100, 29, 904, -552, function()
        frame:Hide()
    end)

    statusText = MakeLabel(frame, "", "GameFontHighlightSmall", 24, -591, 979)
    statusText:SetTextColor(0.54, 0.88, 0.65)

    frame:RegisterEvent("CVAR_UPDATE")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then RefreshAll(false) end
    end)
    frame:SetScript("OnShow", function()
        RefreshAll(false)
    end)
    RefreshAll(true)
    return frame
end

StaticPopupDialogs["FOREVER_GRAPHICS_RESET_ALL"] = {
    text = "Restore all eight settings to their listed defaults?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ApplyGroup(false) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

SLASH_FOREVERGRAPHICS1 = "/fgfx"
SLASH_FOREVERGRAPHICS2 = "/forevergraphics"
SlashCmdList["FOREVERGRAPHICS"] = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if not mainFrame then CreateUI() end
    if message == "max" or message == "suggested" then
        mainFrame:Show()
        ApplyGroup(true)
    elseif message == "reset" then
        mainFrame:Show()
        StaticPopup_Show("FOREVER_GRAPHICS_RESET_ALL")
    elseif message == "refresh" then
        mainFrame:Show()
        RefreshAll(true)
    elseif message == "" then
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    else
        print("Forever Graphics: /fgfx to toggle, /fgfx max for suggested values, /fgfx reset to defaults, /fgfx refresh to reread CVars.")
    end
end

local startup = CreateFrame("Frame")
startup:RegisterEvent("ADDON_LOADED")
startup:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    if type(ForeverGraphicsDB) ~= "table" then ForeverGraphicsDB = {} end
    self:UnregisterEvent("ADDON_LOADED")
end)