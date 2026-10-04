local _, ns = ...

-- Minimal dark nameplates for enemies (hostile and neutral; friendly ones stay Blizzard's).
--
-- Blizzard's plate keeps working underneath, made see-through (opacity 0, not hidden): clicking a
-- plate is hit-tested against its health bar, so it has to stay laid out. Ours sits on the plate's
-- base frame, over that health bar. Two of Blizzard's parts are kept, shown through the
-- see-through plate and moved round ours: its cast bar and its auras (your debuffs, and buffs you
-- can steal). Both run on Blizzard's own code, which copes with values the game keeps secret in
-- combat; ours only hands such values straight to widgets.
--
-- Blizzard pools the inner unit frames (base.UnitFrame) and gives them to any plate, friendly
-- ones too, so a unit frame we've made see-through gets its opacity back when it's next used
-- for something friendly.

local Plates = {}
ns.Plates = Plates

local issecret = issecretvalue or function() return false end
local function Safe(v)
    if issecret(v) then return nil end
    return v
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local own = {}    -- Blizzard unit frames we've made see-through
local frames = {} -- plate base -> our frame
local byUnit = {} -- nameplate unit token -> our frame
local busy        -- our own SetAlpha, which the hook below ignores

local function Loaded(addon)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded and isLoaded(addon)
end

-- A path inside an add-on that isn't loaded (FrogUI's textures, without FrogUI) can't be used.
local function Usable(path)
    local addon = path:match("^[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^\\/]+)")
    return not addon or Loaded(addon)
end

local function Texture()
    return Usable(ns.db.texture) and ns.db.texture or WHITE
end

-- One screen pixel in `frame`'s units.
local function Pixel(frame)
    return 768 / select(2, GetPhysicalScreenSize()) / frame:GetEffectiveScale()
end

------------------------------------------------------------------------------
-- Colour: threat first (when you're on its threat list), then tapped, players' class, reaction.
------------------------------------------------------------------------------

-- Tanking: from the setting, or (auto) a tanking stance, form or aura.
local TANK_FORMS = { [18] = true, [5] = true, [8] = true } -- Defensive Stance, Bear, Dire Bear
local RIGHTEOUS_FURY = 25780

local function Tanking()
    local role = ns.db.role
    if role ~= "auto" then return role == "tank" end
    local form = GetShapeshiftFormID and GetShapeshiftFormID()
    if form and TANK_FORMS[form] then return true end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RIGHTEOUS_FURY)
        if ok and aura then return true end
    end
    if GetSpecialization and GetSpecializationRole then
        local spec = GetSpecialization()
        if spec and GetSpecializationRole(spec) == "TANK" then return true end
    end
    return false
end

local function Colour(unit)
    local c = ns.db.colors
    local situation = ns.db.threat and Safe(UnitThreatSituation("player", unit))
    if situation then
        -- 3: it's on you, safely; 2: on you, but someone's close; 1: someone else is about to
        -- take it; 0: it's on someone else.
        if Tanking() then
            if situation == 3 then return c.safe end
            if situation == 2 then return c.warn end
            return c.danger
        end
        if situation >= 2 then return c.danger end
        if situation == 1 then return c.warn end
    end
    if Safe(UnitIsTapDenied(unit)) then return c.tapped end
    if Safe(UnitIsPlayer(unit)) then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then return cc end
    end
    local reaction = Safe(UnitReaction(unit, "player"))
    if reaction and reaction >= 4 then return c.neutral end
    return c.hostile
end

------------------------------------------------------------------------------
-- Threat gap: your lead over the next highest on its threat list (or how far behind you are),
-- the same as EnmityList's.
------------------------------------------------------------------------------

local function Short(n)
    local a = math.abs(n)
    if a >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if a >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function ThreatGap(unit)
    local _, _, _, _, mine = UnitDetailedThreatSituation("player", unit)
    if mine == nil or issecret(mine) then return nil end
    local best
    local function Consider(who)
        if not UnitExists(who) or Safe(UnitIsUnit(who, "player")) ~= false then return end
        local _, _, _, _, v = UnitDetailedThreatSituation(who, unit)
        if v ~= nil and not issecret(v) and v > 0 and (not best or v > best) then best = v end
    end
    Consider("pet")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            Consider("raid" .. i)
            Consider("raidpet" .. i)
        end
    else
        for i = 1, 4 do
            Consider("party" .. i)
            Consider("partypet" .. i)
        end
    end
    return best and (mine - best) or nil
end

------------------------------------------------------------------------------
-- Our frame
------------------------------------------------------------------------------

-- Four edges round `bar`, `size` pixels thick, outside it.
local function Border(frame, bar, layer)
    local b = { frame = frame, bar = bar }
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, layer or "BORDER")
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        b[key] = t
    end
    return b
end

-- `size` pixels thick, starting `out` pixels outside the bar.
local function PlaceBorder(b, size, out, c)
    local p = Pixel(b.frame)
    local t, o = p * size, p * out
    local bar = b.bar
    b.top:ClearAllPoints()
    b.top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -(o + t), o)
    b.top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", o + t, o)
    b.top:SetHeight(t)
    b.bottom:ClearAllPoints()
    b.bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -(o + t), -o)
    b.bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", o + t, -o)
    b.bottom:SetHeight(t)
    b.left:ClearAllPoints()
    b.left:SetPoint("TOPRIGHT", bar, "TOPLEFT", -o, o)
    b.left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -o, -o)
    b.left:SetWidth(t)
    b.right:ClearAllPoints()
    b.right:SetPoint("TOPLEFT", bar, "TOPRIGHT", o, o)
    b.right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", o, -o)
    b.right:SetWidth(t)
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do b[key]:SetColorTexture(c.r, c.g, c.b, c.a or 1) end
end

-- The Forever frame: our own (Media\ForeverFrame.tga, 16x16), in the style of Forever's bar
-- frames: a dark outline, a light metallic rim brighter along the top, and a dark inner line,
-- each one screen pixel wide, with the corners cut. Nine-sliced at one texel per screen pixel, so
-- it's crisp at any bar size and nothing stretches but its straight edges. It sits 2 pixels out
-- from the bar, its inner line over the fill's edge, so the fill sits inside it.
local FRAME_FILE = "Interface\\AddOns\\FrogPlates\\Media\\ForeverFrame.tga"
local FRAME_SIZE, FRAME_SLICE, FRAME_OUT = 16, 3, 2
local FRAME_KEYS = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }

local function FrameArt(bar)
    local p = {}
    for _, key in ipairs(FRAME_KEYS) do
        local t = bar:CreateTexture(nil, "OVERLAY", nil, 5)
        t:SetTexture(FRAME_FILE, nil, nil, "NEAREST")
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        p[key] = t
    end
    return p
end

-- thickness: screen pixels per texel (1 to 3), a whole number so it stays crisp.
local function PlaceFrameArt(p, bar, thickness)
    local px = (thickness or 1) * 768 / select(2, GetPhysicalScreenSize()) / bar:GetEffectiveScale()
    local m, out = FRAME_SLICE * px, FRAME_OUT * px
    local a, b = FRAME_SLICE / FRAME_SIZE, (FRAME_SIZE - FRAME_SLICE) / FRAME_SIZE
    p.tl:SetTexCoord(0, a, 0, a)
    p.t:SetTexCoord(a, b, 0, a)
    p.tr:SetTexCoord(b, 1, 0, a)
    p.l:SetTexCoord(0, a, a, b)
    p.r:SetTexCoord(b, 1, a, b)
    p.bl:SetTexCoord(0, a, b, 1)
    p.b:SetTexCoord(a, b, b, 1)
    p.br:SetTexCoord(b, 1, b, 1)
    for _, t in pairs(p) do t:ClearAllPoints() end
    p.tl:SetPoint("TOPLEFT", bar, "TOPLEFT", -out, out)
    p.tr:SetPoint("TOPRIGHT", bar, "TOPRIGHT", out, out)
    p.bl:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -out, -out)
    p.br:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", out, -out)
    for _, key in ipairs({ "tl", "tr", "bl", "br" }) do p[key]:SetSize(m, m) end
    p.t:SetPoint("TOPLEFT", p.tl, "TOPRIGHT")
    p.t:SetPoint("BOTTOMRIGHT", p.tr, "BOTTOMLEFT")
    p.b:SetPoint("TOPLEFT", p.bl, "TOPRIGHT")
    p.b:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.l:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT")
    p.l:SetPoint("BOTTOMRIGHT", p.bl, "TOPRIGHT")
    p.r:SetPoint("TOPLEFT", p.tr, "BOTTOMLEFT")
    p.r:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")
end

-- The classic look's border: the grey stone tooltips and old frames use.
local STONE = "Interface\\Tooltips\\UI-Tooltip-Border"

local function ShowBorder(b, shown)
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do b[key]:SetShown(shown) end
end

local function Create(base)
    local f = CreateFrame("Frame", nil, base)
    f:SetAllPoints(base)
    f.base = base

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    f.bar = bar
    f.bg = bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.06, 0.06, 0.07, 0.85)
    -- The border, in one of three styles (ns.db.borderStyle): a pixel edge, the classic stone,
    -- or our Forever frame.
    f.border = Border(f, bar, "BORDER")
    f.stone = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    f.stone:SetFrameLevel(bar:GetFrameLevel() + 1)
    f.frameArt = FrameArt(bar)
    -- Your target: a second, coloured ring round the black one.
    f.ring = CreateFrame("Frame", nil, f)
    f.ring:SetAllPoints(bar)
    f.ringBorder = Border(f.ring, bar, "OVERLAY")

    local text = CreateFrame("Frame", nil, bar)
    text:SetAllPoints()
    text:SetFrameLevel(bar:GetFrameLevel() + 2)
    f.name = text:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 3)
    f.name:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 3)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.name:SetShadowOffset(1, -1)
    -- Text inside the bar: left, centre and right, each from its own template (ns.db.text).
    f.texts = {}
    for _, slot in ipairs({ "left", "center", "right" }) do
        local fs = text:CreateFontString(nil, "OVERLAY")
        fs:SetShadowOffset(1, -1)
        fs:SetWordWrap(false)
        f.texts[slot] = fs
    end
    f.texts.left:SetPoint("LEFT", bar, "LEFT", 3, 0)
    f.texts.left:SetJustifyH("LEFT")
    f.texts.center:SetPoint("CENTER", bar, "CENTER", 0, 0)
    f.texts.right:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    f.texts.right:SetJustifyH("RIGHT")
    f.threat = text:CreateFontString(nil, "OVERLAY")
    f.threat:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    f.threat:SetShadowOffset(1, -1)
    f.mark = text:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(16, 16)
    f.mark:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    f.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.mark:Hide()

    -- A black shadow under all the text (all there is with the outline set to "None").
    for _, fs in ipairs({ f.name, f.threat, f.texts.left, f.texts.center, f.texts.right }) do
        fs:SetShadowColor(0, 0, 0, 1)
    end

    -- Plates move and scale smoothly, landing between screen pixels, which drops 1px edges and
    -- blurs text: snap everything to whole pixels, as Blizzard's own plates do.
    if PixelUtil and PixelUtil.SetRoundLayoutToNearestPixelRecursively then
        PixelUtil.SetRoundLayoutToNearestPixelRecursively(f, true)
    end
    frames[base] = f
    return f
end

-- Blizzard's health bar inside the plate: ours goes over it, since that's where clicks land.
local function BlizzardBar(uf)
    return uf and ((uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf.healthBar)
end

-- The black edge, and your target's ring in the target colour just outside it. Sized in screen
-- pixels, so placed again whenever the plate's scale changes (it grows as enemies come closer).
function Plates:PlaceBorders(f)
    local db = ns.db
    local style = db.borderStyle
    f.placedScale = f:GetEffectiveScale()
    PlaceBorder(f.border, 1, 0, { r = 0, g = 0, b = 0 })
    ShowBorder(f.border, style == "pixel")
    if style == "classic" then
        f.stone:ClearAllPoints()
        f.stone:SetPoint("TOPLEFT", f.bar, "TOPLEFT", -3, 3)
        f.stone:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 3, -3)
        f.stone:SetBackdrop({ edgeFile = STONE, edgeSize = 12 })
        f.stone:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
    end
    f.stone:SetShown(style == "classic")
    if style == "forever" then PlaceFrameArt(f.frameArt, f.bar, db.frameThickness) end
    for _, t in pairs(f.frameArt) do t:SetShown(style == "forever") end
    -- The target ring goes just outside whichever border it is.
    local out = (style == "classic" and 3) or (style == "forever" and 2 * (db.frameThickness or 1)) or 1
    PlaceBorder(f.ringBorder, 1, out, db.colors.target)
end

function Plates:Layout(f)
    local db, uf = ns.db, f.uf
    local anchor = BlizzardBar(uf) or f.base
    local bar = f.bar
    bar:ClearAllPoints()
    if db.width > 0 then
        bar:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        bar:SetWidth(db.width)
    else
        bar:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        bar:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
    end
    bar:SetHeight(db.height)
    bar:SetStatusBarTexture(Texture())
    -- The game dims a plate whose enemy is behind terrain or far off (on the plate's base
    -- frame); without gameFade ours keeps its own opacity, like the cast bar and auras do.
    f:SetIgnoreParentAlpha(not db.gameFade)
    Plates:PlaceBorders(f)

    ns.Media:SetFont(f.name, db.font, db.nameSize, db.outline)
    for _, fs in pairs(f.texts) do ns.Media:SetFont(fs, db.font, db.textSize, db.outline) end
    ns.Media:SetFont(f.threat, db.font, db.textSize, db.outline)

    -- Blizzard's cast bar, under ours.
    local cast = uf and uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if cast then
        cast:SetIgnoreParentAlpha(db.castBar)
        if db.castBar then
            cast:ClearAllPoints()
            cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -db.castGap)
            cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -db.castGap)
            cast:SetHeight(db.castHeight)
        end
    end
    -- Blizzard's auras (your debuffs; buffs you can steal; crowd control), above the name.
    local auras = uf and uf.AurasFrame
    if auras then
        auras:SetIgnoreParentAlpha(db.auras)
        if db.auras then
            auras:ClearAllPoints()
            auras:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, db.nameSize + 6)
            auras:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, db.nameSize + 6)
        end
    end
end

------------------------------------------------------------------------------
-- Filling it in
------------------------------------------------------------------------------

-- A unit's name as the game's own frames show it: on Forever that includes the surname
-- (GetUnitName's second argument), where UnitName gives only the first name.
local function FullName(unit)
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        if ok and name then return name end
    end
    return UnitName(unit)
end

local function HealthPercent(unit)
    if UnitHealthPercent and CurveConstants then
        return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    end
    local h, m = UnitHealth(unit), UnitHealthMax(unit)
    if issecret(h) or issecret(m) or m == 0 then return 0 end
    return h / m * 100
end

function Plates:UpdateHealth(f)
    local unit = f.unit
    f.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    f.bar:SetValue(UnitHealth(unit))
    -- Health may be secret: the values only ever go to SetFormattedText.
    local level = Safe(UnitLevel(unit))
    local vals = { value = UnitHealth(unit), max = UnitHealthMax(unit), percent = HealthPercent(unit),
        name = FullName(unit) or "", level = level and (level > 0 and tostring(level) or "??") or "" }
    for slot, fs in pairs(f.texts) do
        ns.UI.SetTemplateText(fs, ns.db.text[slot], vals, { "name", "level" })
    end
end

function Plates:UpdateName(f)
    local unit, db = f.unit, ns.db
    local name = FullName(unit)
    local level = db.showLevel and Safe(UnitLevel(unit))
    if level then
        local text = level > 0 and tostring(level) or "??"
        local class = Safe(UnitClassification(unit))
        if class == "elite" or class == "rareelite" or class == "worldboss" then text = text .. "+" end
        local c = (level > 0 and GetCreatureDifficultyColor) and GetCreatureDifficultyColor(level) or { r = 1, g = 0.2, b = 0.2 }
        pcall(f.name.SetFormattedText, f.name, "|cff%02x%02x%02x%s|r %s",
            c.r * 255, c.g * 255, c.b * 255, text, name or "")
    else
        pcall(f.name.SetText, f.name, name or "")
    end
end

function Plates:UpdateColour(f)
    local c = Colour(f.unit)
    f.bar:SetStatusBarColor(c.r, c.g, c.b)
end

function Plates:UpdateThreat(f)
    local unit, db = f.unit, ns.db
    local situation = Safe(UnitThreatSituation("player", unit))
    if not (db.threatText and situation ~= nil) then
        f.threat:Hide()
        return
    end
    f.threat:Show()
    local gap = ThreatGap(unit)
    local c = db.colors
    if gap then
        local col = gap >= 0 and c.safe or c.danger
        f.threat:SetTextColor(col.r, col.g, col.b)
        f.threat:SetText((gap >= 0 and "+" or "") .. Short(gap))
    else
        local _, _, percent = UnitDetailedThreatSituation("player", unit)
        f.threat:SetTextColor(1, 1, 1)
        pcall(f.threat.SetFormattedText, f.threat, "%d%%", percent)
    end
end

function Plates:UpdateMark(f)
    local index = Safe(GetRaidTargetIndex(f.unit))
    if index then
        SetRaidTargetIconTexture(f.mark, index)
        f.mark:Show()
    else
        f.mark:Hide()
    end
end

function Plates:UpdateTarget()
    local target = C_NamePlate.GetNamePlateForUnit("target")
    for base, f in pairs(frames) do
        if f.unit then
            local isTarget = target == base
            ShowBorder(f.ringBorder, isTarget)
            f:SetAlpha((target and not isTarget) and ns.db.otherAlpha or 1)
        end
    end
end

function Plates:UpdateAll(f)
    self:UpdateHealth(f)
    self:UpdateName(f)
    self:UpdateColour(f)
    self:UpdateThreat(f)
    self:UpdateMark(f)
end

------------------------------------------------------------------------------
-- Taking plates over, and giving them back
------------------------------------------------------------------------------

local function SeeThrough(uf, on)
    busy = true
    uf:SetAlpha(on and 0 or 1)
    busy = false
    if uf.selectionHighlight then uf.selectionHighlight:SetAlpha(on and 0 or 0.25) end
    if not on then
        local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
        if cast then cast:SetIgnoreParentAlpha(false) end
        if uf.AurasFrame then uf.AurasFrame:SetIgnoreParentAlpha(false) end
    end
end

-- Once per unit frame: keep it see-through while it's ours, and put our layout back after
-- Blizzard re-lays it out (a new unit, or a nameplate setting changed).
local hooked = {}
local function Hook(uf)
    if hooked[uf] then return end
    hooked[uf] = true
    hooksecurefunc(uf, "SetAlpha", function(self, alpha)
        if busy or not own[self] then return end
        if issecret(alpha) or alpha ~= 0 then
            busy = true
            self:SetAlpha(0)
            busy = false
        end
    end)
    local function Relayout(self)
        local f = own[self] and frames[self:GetParent()]
        if f and f.uf == self then Plates:Layout(f) end
    end
    for _, method in ipairs({ "ApplyFrameOptions", "UpdateAnchors" }) do
        if type(uf[method]) == "function" then hooksecurefunc(uf, method, Relayout) end
    end
end

local function Release(uf)
    if uf and own[uf] then
        own[uf] = nil
        SeeThrough(uf, false)
    end
end

function Plates:Add(unit)
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base or base:IsForbidden() then return end
    local uf = base.UnitFrame
    local enemy = ns.db.enabled and Safe(UnitCanAttack("player", unit)) and Safe(UnitIsUnit(unit, "player")) == false
    if not enemy then
        Release(uf)
        if frames[base] then frames[base]:Hide() end
        return
    end
    if uf then
        own[uf] = true
        Hook(uf)
        SeeThrough(uf, true)
    end
    local f = frames[base] or Create(base)
    f.unit, f.uf = unit, uf
    byUnit[unit] = f
    self:Layout(f)
    self:UpdateAll(f)
    f:Show()
    self:UpdateTarget()
end

function Plates:Remove(unit)
    local f = byUnit[unit]
    if not f then return end
    byUnit[unit] = nil
    f.unit = nil
    f:Hide()
end

-- Blizzard's aura row (which ours moves) shows only the debuffs on its own list unless the
-- game's "show all personal auras" setting is on, and only if the enemy aura setting includes
-- debuffs; both are game settings, set here from ours (out of combat: settings can't change in it).
function Plates:AuraSettings()
    local db = ns.db
    if not (db.enabled and db.auras) or InCombatLockdown() then return end
    -- Their size: the game's own debuff scale, which also decides how many fit on a row.
    if db.auraScale and C_CVar.GetCVar("nameplateAuraScale") then
        SetCVar("nameplateAuraScale", string.format("%.2f", db.auraScale))
    end
    if C_CVar.GetCVar("nameplateShowAllPersonalAuras") then
        SetCVar("nameplateShowAllPersonalAuras", db.allDebuffs and "1" or "0")
    end
    if C_CVar.SetCVarBitfield then
        if Enum.NamePlateEnemyNpcAuraDisplay and C_CVar.GetCVar("nameplateEnemyNpcAuraDisplay") then
            pcall(C_CVar.SetCVarBitfield, "nameplateEnemyNpcAuraDisplay", Enum.NamePlateEnemyNpcAuraDisplay.Debuffs, true)
        end
        if Enum.NamePlateEnemyPlayerAuraDisplay and C_CVar.GetCVar("nameplateEnemyPlayerAuraDisplay") then
            pcall(C_CVar.SetCVarBitfield, "nameplateEnemyPlayerAuraDisplay", Enum.NamePlateEnemyPlayerAuraDisplay.Debuffs, true)
        end
    end
end

-- Every plate again (after a settings change, or turning it on or off).
function Plates:Refresh()
    self:AuraSettings()
    for unit in pairs(byUnit) do self:Remove(unit) end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then self:Add(unit) end
    end
end

function Plates:Init()
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) Plates:Add(unit) end)
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) Plates:Remove(unit) end)

    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
        "UNIT_FLAGS", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED",
        "RAID_TARGET_UPDATE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, event)
    end
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            Plates:UpdateTarget()
            return
        elseif event == "RAID_TARGET_UPDATE" then
            for _, f in pairs(byUnit) do Plates:UpdateMark(f) end
            return
        elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_REGEN_ENABLED" then
            for _, f in pairs(byUnit) do Plates:UpdateColour(f) end
            return
        end
        local f = unit and byUnit[unit]
        if not f then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            Plates:UpdateHealth(f)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            Plates:UpdateName(f)
        else
            Plates:UpdateColour(f)
            Plates:UpdateThreat(f)
        end
    end)
    -- The threat gap drifts with every hit, without its own event for each plate.
    local elapsed = 0
    ev:SetScript("OnUpdate", function(_, dt)
        for _, f in pairs(byUnit) do
            if f:GetEffectiveScale() ~= f.placedScale then Plates:PlaceBorders(f) end
        end
        elapsed = elapsed + dt
        if elapsed < 0.3 then return end
        elapsed = 0
        for _, f in pairs(byUnit) do
            Plates:UpdateColour(f)
            Plates:UpdateThreat(f)
        end
    end)
    self:Refresh()
end
