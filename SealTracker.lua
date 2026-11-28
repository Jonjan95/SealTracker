-- Seal Tracker: a small Unsealed Wrath tracker for WoW Forever.
--
-- WoW Forever hides seal and Echo buffs from addon code in combat. So every
-- value on the icon (seal icon, countdown, Echo stacks, glow at 3) is drawn by
-- Blizzard's AuraContainer display, which fills in the real values itself,
-- in or out of combat. The addon only says which buff goes where.
--
-- What you see:
--   * One icon: whatever seal is up right now, with its seconds left.
--     No seal: the last seal's icon greyed out with a red "!".
--   * Below the icon: your current seal's Echo stacks as 3 pips, and a glow
--     around the icon at 3 stacks (= swap).
--   * Above the icon: small pips for the seal you swapped off, while its Echo
--     stacks are still on you.
--
-- "Current seal" for the pips = the last seal you cast. Casts are readable in
-- combat, and out of combat the addon double-checks against your real buffs.

local ADDON, ns = ...

-- Seal ranks per seal (spell IDs; seal ID data: talentsforever.com).
-- Echo IDs: built in where known, the rest are found by name at login or
-- learned from your buffs out of combat.
local SEALS = {
    { key = "Command",       color = { 1.00, 0.84, 0.30 }, echo = 1311703,
      ranks = { 20375, 20915, 20918, 20919, 20920 } },
    { key = "Righteousness", color = { 0.45, 0.75, 1.00 }, echo = 1311704,
      ranks = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    { key = "Wisdom",        color = { 0.40, 0.90, 0.85 }, echo = 1328206,
      ranks = { 20166, 20356, 20357 } },
    { key = "Fury",          color = { 1.00, 0.35, 0.25 },
      ranks = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },
    { key = "Justice",       color = { 0.75, 0.55, 1.00 },
      ranks = { 20164 } },
    { key = "Light",         color = { 1.00, 0.95, 0.55 },
      ranks = { 20165, 20347, 20348, 20349 } },
    { key = "the Crusader",  color = { 1.00, 0.80, 0.40 },
      ranks = { 21082, 20162, 20305, 20306, 20307, 20308 } },
}
local BY_KEY = {}
for _, s in ipairs(SEALS) do BY_KEY[s.key] = s end

-- Spell ID ranges scanned by name at login for "Seal of X" / "Echo of X"
local SCAN_RANGES = { { 1311600, 1311800 }, { 1328100, 1328300 } }

local UNSEALED_WRATH = 1310735
local ICON = 48
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- A white circle: used as the round mask, the round timer swipe, the pips and the glow
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NO_SEAL_ICON = "Interface\\Icons\\ClassIcon_Paladin"

local defaults = {
    point = "CENTER", relativePoint = "CENTER", x = 0, y = -160, scale = 1,
    locked = false, showLeftover = true, hideNoSeal = false,
    minimap = { hide = false, angle = 215 },
    echoIDs = {}, sealIDs = {}, lastSeal = nil,
}

local db, frame
local rankToKey = {}
local containers, wraps = {}, {}     -- Blizzard containers, our per-seal wrappers
local built, buildPending = false, false
local status = "not built"
local activeKey = nil

local function Print(msg) print("|cffffd200Seal Tracker:|r " .. msg) end
local function InCombat() return InCombatLockdown() end
local function Secret(v) return issecretvalue and issecretvalue(v) end
ns.Print = Print

---------------------------------------------------------------------------
-- Spell ID tables
---------------------------------------------------------------------------
local function EchoID(key) return (db.echoIDs and db.echoIDs[key]) or BY_KEY[key].echo end

local function RebuildRankLookup()
    wipe(rankToKey)
    for _, s in ipairs(SEALS) do
        for _, id in ipairs(s.ranks) do rankToKey[id] = s.key end
        for _, id in ipairs(db.sealIDs[s.key] or {}) do rankToKey[id] = s.key end
    end
end

local function AddSealID(key, id)
    if not BY_KEY[key] or rankToKey[id] then return false end
    db.sealIDs[key] = db.sealIDs[key] or {}
    table.insert(db.sealIDs[key], id)
    rankToKey[id] = key
    return true
end

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    if Secret(name) or type(name) ~= "string" then return nil end
    return name
end

-- Look through nearby spell IDs for seals and Echoes we don't know yet
local function ScanSpellNames()
    local changed = false
    for _, r in ipairs(SCAN_RANGES) do
        for id = r[1], r[2] do
            local name = SpellName(id)
            if name then
                local seal = name:match("^Seal of (.+)$")
                local echo = name:match("^Echo of (.+)$")
                if seal and AddSealID(seal, id) then changed = true end
                if echo and BY_KEY[echo] and not EchoID(echo) then
                    db.echoIDs[echo] = id
                    changed = true
                end
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Formatter(breakpoints)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local ok, f = pcall(function()
        local fmt = C_StringUtil.CreateNumericRuleFormatter()
        fmt:SetBreakpoints(breakpoints)
        return fmt
    end)
    return ok and f or nil
end

-- "n of 3" pips as one string of small coloured squares
local function Pips(n, color, size, onlyFilled)
    local parts = {}
    for i = 1, 3 do
        if i <= n or not onlyFilled then
            local r, g, b = 70, 70, 70
            if i <= n then r, g, b = math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255) end
            parts[#parts + 1] = ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(CIRCLE, size, size, r, g, b)
        end
    end
    return table.concat(parts, " ")
end

-- Clip a texture to a circle
local function MakeRound(owner, tex)
    local ok = pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end)
    return ok
end

local function SealIcon(key)
    local s = key and BY_KEY[key]
    if not s then return NO_SEAL_ICON end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.ranks[1])
    if Secret(tex) then tex = nil end
    return tex or NO_SEAL_ICON
end

-- Shown on every Paladin, any spec: seals are tracked with or without Unsealed
-- Wrath (without it there are simply no Echo stacks to show).
function ns.IsRelevant()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

local function HasUnsealedWrath()
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }) do
        if type(fn) == "function" then
            local ok, known = pcall(fn, UNSEALED_WRATH)
            if ok and known == true then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Which seal is current: show its Echo below, every other seal's above
---------------------------------------------------------------------------
local function ApplyActive()
    for key, w in pairs(wraps) do
        w.below:SetAlpha(key == activeKey and 1 or 0)
        w.above:SetAlpha((key ~= activeKey and db.showLeftover) and 0.9 or 0)
    end
    local s = activeKey and BY_KEY[activeKey]
    frame.placeholder:SetTexture(SealIcon(activeKey))
    frame.emptyPips:SetText((s and EchoID(activeKey)) and Pips(0, s.color, 10) or "")
    -- "Hide when no seal": drop our own grey stand-ins. What's left is drawn by
    -- Blizzard and only exists while a seal / Echo is really on you (also in combat).
    -- While unlocked they stay visible so there's something to drag.
    local ours = (db.hideNoSeal and db.locked) and 0 or 1
    frame.placeholder:SetAlpha(0.4 * ours)
    frame.bang:SetAlpha(ours)
    frame.emptyPips:SetAlpha(ours)
end
ns.ApplyActive = function() if frame then ApplyActive() end end

local function SetActive(key)
    if key == activeKey then return end
    activeKey = key
    db.lastSeal = key
    ApplyActive()
end

---------------------------------------------------------------------------
-- Our own frame
---------------------------------------------------------------------------
local function CreateUI()
    frame = CreateFrame("Frame", "SealTrackerFrame", UIParent)
    frame:SetSize(ICON + 20, ICON + 40)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        db.point, db.relativePoint, db.x, db.y = p, rp, x, y
    end)

    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(ICON, ICON)
    holder:SetPoint("CENTER")
    frame.holder = holder

    -- No seal: dim round icon + red "!". Blizzard's live seal icon covers both.
    local ph = holder:CreateTexture(nil, "ARTWORK")
    ph:SetAllPoints()
    ph:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ph:SetDesaturated(true)
    ph:SetAlpha(0.4)
    MakeRound(holder, ph)
    frame.placeholder = ph

    local bang = holder:CreateFontString(nil, "OVERLAY")
    bang:SetFont(FONT, 30, "OUTLINE")
    bang:SetPoint("CENTER")
    bang:SetTextColor(1, 0.25, 0.15)
    bang:SetText("!")
    frame.bang = bang

    -- Empty pips under the icon; Blizzard's live pips draw over these
    local empty = frame:CreateFontString(nil, "OVERLAY")
    empty:SetFont(FONT, 10, "")
    empty:SetPoint("TOP", holder, "BOTTOM", 0, -5)
    frame.emptyPips = empty
end

function ns.ApplySettings()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    frame:SetScale(db.scale)
    frame:EnableMouse(not db.locked)
    ApplyActive()
end

function ns.UpdateVisibility()
    if not frame or InCombat() then return end   -- our frame only changes out of combat
    frame:SetShown(ns.IsRelevant() or not db.locked)
end

---------------------------------------------------------------------------
-- Blizzard-drawn parts (built out of combat; Blizzard owns them after)
---------------------------------------------------------------------------
local function NewContainer(parent)
    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    c:SetEnabled(false)
    c:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
    c:SetPoint("TOPLEFT", frame.holder, "TOPLEFT")
    c:SetUnit("player")
    containers[#containers + 1] = c
    return c
end

local function Slot(container, name, ids, init)
    container:AddAuraSlot(name, "HELPFUL", { candidateFilters = { includeSpellIDs = ids }, initializeFrame = init })
    container:SetAuraSlotEnabled(name, true)
    container:SetEnabled(true)
end

local function PrepButton(button, level)
    local holder = frame.holder
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetAllPoints(holder)
    button:SetFrameLevel(holder:GetFrameLevel() + level)
end

-- The seal icon with timer swipe and countdown
local function InitSealButton(button)
    PrepButton(button, 3)
    local holder = frame.holder
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(holder)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    MakeRound(button, icon)
    button:SetIcon(icon)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(holder)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    pcall(cd.SetSwipeTexture, cd, CIRCLE)        -- round timer shading
    pcall(cd.SetUseCircularEdge, cd, true)
    cd:SetSwipeColor(0, 0, 0, 0.45)
    button:SetDurationCooldown(cd)
    pcall(cd.SetSwipeTexture, cd, CIRCLE)        -- again, in case Blizzard restyled it
    cd:SetSwipeColor(0, 0, 0, 0.45)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(holder)
    overlay:SetFrameLevel(cd:GetFrameLevel() + 1)
    local timer = overlay:CreateFontString(nil, "OVERLAY")
    timer:SetFont(FONT, 20, "OUTLINE")
    timer:SetPoint("CENTER", holder, "CENTER")
    timer:SetTextColor(1, 1, 1)

    local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    local fmt = Formatter({ { threshold = 0, format = "%d", step = 1, rounding = up } })
    if not (fmt and pcall(button.SetDurationText, button, timer, { textFormatter = fmt })) then
        button:SetDurationText(timer, {})
    end
end

-- Current seal's Echo: pips below the icon + glow around it at 3 stacks
local function InitEchoBelow(button, seal)
    PrepButton(button, 6)
    local holder = frame.holder
    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetFont(FONT, 10, "")
    count:SetPoint("TOP", holder, "BOTTOM", 0, -5)
    local pips = Formatter({
        { threshold = 0, format = Pips(0, seal.color, 10) },
        { threshold = 1, format = Pips(1, seal.color, 10) },
        { threshold = 2, format = Pips(2, seal.color, 10) },
        { threshold = 3, format = Pips(3, seal.color, 10) },
    })
    if not (pips and pcall(button.SetApplicationCount, button, count, { formatter = pips })) then
        count:SetFont(FONT, 14, "OUTLINE")
        count:SetTextColor(seal.color[1], seal.color[2], seal.color[3])
        button:SetApplicationCount(count, {})
    end

    -- A status bar whose fill is the glow image. Range 2..3: empty at 2, full at 3.
    -- A coloured disc just bigger than the icon, drawn under the live seal icon,
    -- so it shows as a round ring around it.
    local glow = CreateFrame("StatusBar", nil, button)
    glow:SetPoint("CENTER", holder, "CENTER")
    glow:SetSize(ICON * 1.25, ICON * 1.25)
    glow:SetFrameLevel(holder:GetFrameLevel() + 1)
    glow:SetStatusBarTexture(CIRCLE)
    local tex = glow:GetStatusBarTexture()
    if tex then
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(seal.color[1], seal.color[2], seal.color[3])
    end
    if not pcall(button.SetApplicationBar, button, glow, { minApplications = 2, maxApplications = 3 }) then
        glow:SetOrientation("VERTICAL")
        pcall(button.SetApplicationBar, button, glow, { maxApplications = 3 })
    end
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.4)
    ag:Play()
end

-- A seal you swapped off: small filled pips above the icon while its Echo lasts
local function InitEchoAbove(button, seal)
    PrepButton(button, 6)
    local fs = button:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 8, "")
    fs:SetPoint("BOTTOM", frame.holder, "TOP", 0, 5)
    local pips = Formatter({
        { threshold = 0, format = "" },
        { threshold = 1, format = Pips(1, seal.color, 8, true) },
        { threshold = 2, format = Pips(2, seal.color, 8, true) },
        { threshold = 3, format = Pips(3, seal.color, 8, true) },
    })
    if not (pips and pcall(button.SetApplicationCount, button, fs, { formatter = pips })) then
        fs:SetFont(FONT, 11, "OUTLINE")
        fs:SetTextColor(seal.color[1], seal.color[2], seal.color[3])
        button:SetApplicationCount(fs, {})
    end
end

local function Build()
    if InCombat() then buildPending = true; return end
    buildPending = false
    if not (CustomAuraContainerAuraProcessingPolicy and C_AuraContainerUtil) then
        status = "this client has no AuraContainer API"
        return
    end

    -- Retire the old display (Blizzard owns its buttons; we just switch it off)
    for _, c in ipairs(containers) do pcall(c.SetEnabled, c, false); pcall(c.Hide, c) end
    for _, w in pairs(wraps) do w.below:SetAlpha(0); w.above:SetAlpha(0) end
    wipe(containers); wipe(wraps)

    local errs = {}
    local ok, err = pcall(function()
        local ids = {}
        for id in pairs(rankToKey) do ids[id] = true end
        Slot(NewContainer(frame), "Seal", ids, InitSealButton)
    end)
    if not ok then errs[#errs + 1] = "seal: " .. tostring(err) end

    local echoes = 0
    for _, seal in ipairs(SEALS) do
        local id = EchoID(seal.key)
        if id then
            local okE, errE = pcall(function()
                local below = CreateFrame("Frame", nil, frame)
                below:SetAllPoints(frame)
                below:SetFrameLevel(frame.holder:GetFrameLevel() + 2)
                local above = CreateFrame("Frame", nil, frame)
                above:SetAllPoints(frame)
                above:SetFrameLevel(frame.holder:GetFrameLevel() + 2)
                wraps[seal.key] = { below = below, above = above }
                Slot(NewContainer(below), "Echo", { [id] = true }, function(b) InitEchoBelow(b, seal) end)
                Slot(NewContainer(above), "Echo", { [id] = true }, function(b) InitEchoAbove(b, seal) end)
            end)
            if okE then echoes = echoes + 1 else errs[#errs + 1] = seal.key .. ": " .. tostring(errE) end
        end
    end
    built = ok
    status = (#errs == 0) and ("active, Echo for " .. echoes .. " seals") or ("problems: " .. table.concat(errs, "; "))
    if #errs > 0 then Print("display problem (" .. status .. ").") end
    ApplyActive()
end

local function RequestBuild()
    buildPending = true
    if InCombat() then return end
    C_Timer.After(0.2, function() if buildPending then Build() end end)
end

---------------------------------------------------------------------------
-- Out of combat: read real buffs to correct the current seal and learn IDs
---------------------------------------------------------------------------
local function ScanBuffs()
    if InCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local learned, sealFound = false, nil
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if not Secret(a) and type(a) == "table" and not Secret(a.name) and not Secret(a.spellId) then
            local name, id = a.name, a.spellId
            if type(name) == "string" and type(id) == "number" then
                local key = rankToKey[id] or name:match("^Seal of (.+)$")
                if key and BY_KEY[key] then
                    if AddSealID(key, id) then learned = true end
                    sealFound = key
                end
                local echo = name:match("^Echo of (.+)$")
                if echo and BY_KEY[echo] and EchoID(echo) ~= id then
                    db.echoIDs[echo] = id
                    learned = true
                    Print("learned Echo of " .. echo .. " (" .. id .. ").")
                end
            end
        end
    end
    if sealFound then SetActive(sealFound) end
    if learned then RequestBuild() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    pcall(events.RegisterEvent, events, ev)
end

local scannedNames = false
events:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        SealTrackerDB = SealTrackerDB or {}
        db = SealTrackerDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = (type(v) == "table") and CopyTable(v) or v end
        end
        ns.db = db
        RebuildRankLookup()
        activeKey = BY_KEY[db.lastSeal or ""] and db.lastSeal or nil
        CreateUI()
        ns.ApplySettings()
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not scannedNames then
            scannedNames = true
            ScanSpellNames()
        end
        ScanBuffs()
        if not built then Build() end   -- once; loading screens don't need a rebuild
        ns.UpdateVisibility()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Seal casts are readable in combat; this is what picks the current seal
        local id = arg3
        if not Secret(id) and rankToKey[id] then SetActive(rankToKey[id]) end
    elseif event == "UNIT_AURA" then
        ScanBuffs()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ScanBuffs()
        if buildPending then Build() end
        ns.UpdateVisibility()
    else
        ns.UpdateVisibility()
    end
end)

function ns.Status()
    local known = {}
    for _, s in ipairs(SEALS) do
        if EchoID(s.key) then known[#known + 1] = s.key end
    end
    Print("display " .. status .. ".")
    Print("Echo known for: " .. table.concat(known, ", "))
    Print("current seal: " .. tostring(activeKey) .. ", Unsealed Wrath known: " .. tostring(HasUnsealedWrath()))
end

function ns.ResetPosition()
    db.point, db.relativePoint, db.x, db.y, db.scale = defaults.point, defaults.relativePoint, defaults.x, defaults.y, defaults.scale
    ns.ApplySettings()
end
