-- Options window, minimap button and slash commands.
local ADDON, ns = ...

local panel

local function Checkbox(parent, label, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function(self) self:SetChecked(get()) end
    return cb
end

local function CreatePanel()
    panel = CreateFrame("Frame", "SealTrackerOptions", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(300, 296)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()
    tinsert(UISpecialFrames, "SealTrackerOptions")   -- Esc closes it

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.title:SetPoint("TOP", 0, -5)
    panel.title:SetText("Seal Tracker")

    local db = ns.db
    local function Changed() ns.ApplySettings(); ns.UpdateVisibility() end
    panel.checks = {
        Checkbox(panel, "Lock position", -34,
            function() return db.locked end, function(v) db.locked = v; Changed() end),
        Checkbox(panel, "Only show with Unsealed Wrath", -62,
            function() return db.talentOnly end, function(v) db.talentOnly = v; Changed() end),
        Checkbox(panel, "Show leftover Echo pips above icon", -90,
            function() return db.showLeftover end, function(v) db.showLeftover = v; Changed() end),
        Checkbox(panel, "Hide when no seal is up (once locked)", -118,
            function() return db.hideNoSeal end, function(v) db.hideNoSeal = v; Changed() end),
        Checkbox(panel, "Show minimap button", -146,
            function() return not db.minimap.hide end,
            function(v) db.minimap.hide = not v; ns.UpdateMinimapButton() end),
    }

    -- Older slider template first; a plain slider if this client dropped it
    local ok, slider = pcall(CreateFrame, "Slider", "SealTrackerScaleSlider", panel, "OptionsSliderTemplate")
    if not ok or not slider then
        slider = CreateFrame("Slider", "SealTrackerScaleSlider2", panel)
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(16)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
        track:SetColorTexture(0.3, 0.3, 0.3, 1)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local label = slider:CreateFontString(slider:GetName() .. "Text", "OVERLAY", "GameFontHighlight")
        label:SetPoint("BOTTOM", slider, "TOP", 0, 2)
    end
    slider:SetPoint("TOPLEFT", 24, -196)
    slider:SetWidth(250)
    slider:SetMinMaxValues(0.5, 2.5)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    local low, high, text = _G[slider:GetName() .. "Low"], _G[slider:GetName() .. "High"], _G[slider:GetName() .. "Text"]
    if low then low:SetText("0.5") end
    if high then high:SetText("2.5") end
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v * 20 + 0.5) / 20
        if text then text:SetText(("Size: %.2f"):format(v)) end
        if v ~= db.scale then db.scale = v; ns.ApplySettings() end
    end)
    panel.slider = slider

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("BOTTOMLEFT", 16, 14)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function() ns.ResetPosition(); panel:Refresh() end)

    local st = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    st:SetSize(120, 22)
    st:SetPoint("BOTTOMRIGHT", -16, 14)
    st:SetText("Print status")
    st:SetScript("OnClick", function() ns.Status() end)

    function panel:Refresh()
        for _, cb in ipairs(self.checks) do cb:Refresh() end
        self.slider:SetValue(db.scale)
    end
    panel:SetScript("OnShow", panel.Refresh)

    -- Close when combat starts: the tracker can't be resized in combat
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:SetScript("OnEvent", function(self) self:Hide() end)
end

function ns.ToggleOptions()
    -- The tracker can only be moved/resized out of combat
    if InCombatLockdown() then ns.Print("options open after combat."); return end
    if not panel then CreatePanel() end
    panel:SetShown(not panel:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button: click = options, drag = move around the minimap
---------------------------------------------------------------------------
local button

local function PlaceButton()
    local a = math.rad(ns.db.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns.CreateMinimapButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "SealTrackerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(20375) or "Interface\\Icons\\ClassIcon_Paladin")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function() ns.ToggleOptions() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Seal Tracker")
        GameTooltip:AddLine("Click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.UpdateMinimapButton()
end

function ns.UpdateMinimapButton()
    if not button then return end
    PlaceButton()
    button:SetShown(not ns.db.minimap.hide)
end

-- Addon list button by the minimap (AddonCompartmentFunc in the .toc)
function SealTracker_OnAddonCompartmentClick() ns.ToggleOptions() end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_SEALTRACKER1 = "/st"
SLASH_SEALTRACKER2 = "/sealtracker"
SlashCmdList.SEALTRACKER = function(msg)
    local cmd = (msg or ""):lower():match("^(%S*)")
    if cmd == "status" then ns.Status(); return end
    if cmd == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        ns.UpdateMinimapButton()
        return
    end
    if cmd == "reset" then
        if InCombatLockdown() then ns.Print("leave combat first."); return end
        ns.ResetPosition()
        ns.Print("position and size reset.")
        return
    end
    ns.ToggleOptions()
end
