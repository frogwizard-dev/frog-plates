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
--
-- Extras round the bar, each its own setting: casts you can't interrupt in their own colour with
-- a small shield (following Blizzard's cast bar, which knows even when the game keeps it secret);
-- the bar in the execute colour once the enemy is in range of your class's execute (worked out
-- by the game from the health, so it works while that's secret); gold and silver dragons round
-- elite and rare plates; and a "!" before the name of enemies your quests still need.
--
-- Two looks (ns.db.look): ours, and "classic": Classic's own nameplate art, still in the game's
-- files (see CLASSIC below), round the same bar and Blizzard's cast bar.

local Plates = {}
ns.Plates = Plates

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Borders, Threat, Color, Unit = FrogLib.Borders, FrogLib.Threat, FrogLib.Color, FrogLib.Unit
local Icons = FrogLib.Icons

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\FrogPlates\\Media\\"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon" -- the yellow "!"

-- The dragons (Media\Dragon*.tga, 128x128 texels, cut from the classic target frame's art by
-- _tools\make_dragon_art.py): where the portrait's hole is in them, which goes round the bar's
-- end, and how far right the art reaches.
local DRAGON = { size = 128, holeX = 51.5, holeY = 58.5, holeR = 27.5, right = 125 }
local DRAGON_ART = { elite = "DragonElite", worldboss = "DragonElite", rare = "DragonRare", rareelite = "DragonRareElite" }
-- Classic's nameplate art (Interface\Tooltips), measured in texels of each file:
--   border (256 x 32): the bar's opening x 5-106, rows 20-27; the level box x 107-134, its middle at
--     x 121; cut in three (left cap 0-8, a middle that stretches 8-100, the end with the box
--     100-136), rows 16-31. Forever's copy is gold: tinted to Classic's grey stone (classicGrey).
--   cast bar border (128 x 32, Forever's Classic one): the health border mirrored, its icon slot on
--     the left; drawn 128 x 16 (its lower half) round a cast bar 20.75 in from its left, 3.5 from
--     its right, as Blizzard's own Classic style lays it out; the spell's icon (14) 11.5 in from its
--     left; casts you can't interrupt in Classic's small shield.
--   glow (128 x 32): over the bar's opening exactly (x 5-106, rows 20-27), added on.
--   elite dragon (64 x 32): a C round x 8-22, rows 6-17, its art 37 x 27.
local CLASSIC = {
    border = "Interface\\Tooltips\\Nameplate-Border",
    cast = "Interface\\Tooltips\\Nameplate-Border-Castbar",
    shield = "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
    glow = "Interface\\Tooltips\\Nameplate-Glow",
    elite = "Interface\\Tooltips\\EliteNameplateIcon",
    skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    bar = "Interface\\TargetingFrame\\UI-StatusBar",
}
local function Classic() return ns.db.look == "classic" end
local CLASSIC_COLORS = { hostile = { r = 1, g = 0, b = 0 }, neutral = { r = 1, g = 1, b = 0 },
    tapped = { r = 0.5, g = 0.5, b = 0.5 } }

local own = {}    -- Blizzard unit frames we've made see-through
local frames = {} -- plate base -> our frame
local byUnit = {} -- nameplate unit token -> our frame
local busy        -- our own SetAlpha, which the hook below ignores

-- A path inside an add-on that isn't loaded (FrogUI's textures, without FrogUI) can't be used.
local Usable = FrogLib.Media.Usable

local function Texture()
    if Classic() then return CLASSIC.bar end
    return Usable(ns.db.texture) and ns.db.texture or WHITE
end

local Pixel = FrogLib.Pixel

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

-- After threat, FrogLib.Color's rules: tapped, players' class, then neutral (or friendly) and
-- hostile; hostile when the game won't say.
local rules = { class = true }

local function Colour(unit)
    local c = ns.db.colors
    local situation = ns.db.threat and Safe(UnitThreatSituation("player", unit))
    if situation then
        -- 3: it's on you, safely; 2: on you, but someone's close; 1: someone else is about to
        -- take it; 0: it's on someone else.
        local t
        if Tanking() then
            t = (situation == 3 and c.safe) or (situation == 2 and c.warn) or c.danger
        elseif situation >= 2 then
            t = c.danger
        elseif situation == 1 then
            t = c.warn
        end
        if t then return t.r, t.g, t.b end
    end
    -- The classic look: Classic's own pure red, yellow and grey.
    if Classic() then c = CLASSIC_COLORS end
    rules.tapped, rules.hostile, rules.fallback = c.tapped, c.hostile, c.hostile
    rules.neutral, rules.friendly = c.neutral, c.neutral
    return Color.Unit(unit, rules)
end

------------------------------------------------------------------------------
-- Execute range: the bar in the execute colour once the enemy is low enough for your class's
-- execute, if you know it (any rank) and, for warriors, are in a stance that can use it.
------------------------------------------------------------------------------

local EXECUTES = {
    -- Execute, in Battle Stance (form 17, or the first stance) or Berserker Stance (19, the third).
    WARRIOR = { spells = { 5308, 20658, 20660, 20661, 20662 }, below = 0.2,
        forms = { [17] = true, [19] = true }, stances = { [1] = true, [3] = true } },
    -- Hammer of Wrath.
    PALADIN = { spells = { 24275, 24274, 24239 }, below = 0.2 },
}

local KNOWS = {} -- the ways this game has of asking whether you know a spell
if C_SpellBook and C_SpellBook.IsSpellKnown then KNOWS[#KNOWS + 1] = C_SpellBook.IsSpellKnown end
if IsPlayerSpell then KNOWS[#KNOWS + 1] = IsPlayerSpell end
if IsSpellKnown then KNOWS[#KNOWS + 1] = IsSpellKnown end

local function Knows(id)
    for _, check in ipairs(KNOWS) do
        local ok, known = pcall(check, id)
        if ok and Safe(known) == true then return true end
    end
    return false
end

local executeBelow = false -- the health fraction your execute works under, or false (ExecuteCheck)

function Plates:ExecuteCheck()
    local _, class = UnitClass("player")
    local e = EXECUTES[class]
    local usable = false
    if e then
        for _, id in ipairs(e.spells) do
            if Knows(id) then
                usable = true
                break
            end
        end
        if usable and e.forms then
            local form = GetShapeshiftFormID and GetShapeshiftFormID()
            if form then
                usable = e.forms[form] or false
            else
                local index = GetShapeshiftForm and GetShapeshiftForm()
                usable = (index and e.stances[index]) or false
            end
        end
    end
    executeBelow = usable and e.below or false
end

-- 1 under the line and 0 from it up, for the overlay's opacity (FrogLib's step curve). The game
-- evaluates it against the health fraction (UnitHealthPercent), so the answer may be secret,
-- which SetAlpha takes. nil when the client has no curves.
local function ExecuteCurve(below)
    if not UnitHealthPercent then return nil end
    return FrogLib.Curve.Below(below, 1, 0)
end

------------------------------------------------------------------------------
-- Threat gap: your lead over the next highest on its threat list (or how far behind you are),
-- worked out by FrogLib's Threat.Gap and written by its SetGapText, as EnmityList's is.
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Our frame
------------------------------------------------------------------------------

local function Create(base)
    local f = CreateFrame("Frame", nil, base)
    f:SetAllPoints(base)
    f.base = base

    -- Where the bar goes: centred on the plate at the health bar's height (see Layout).
    f.slot = CreateFrame("Frame", nil, f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    f.bar = bar
    f.bg = bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.06, 0.06, 0.07, 0.85)
    -- Execute range: the fill again in the execute colour, over it (see UpdateExecute).
    f.execute = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    f.execute:SetAllPoints(bar:GetStatusBarTexture())
    f.execute:Hide()
    -- The border, in one of three styles (ns.db.borderStyle): a pixel edge, the classic stone,
    -- or our Forever frame.
    f.border = Borders.Edges(f, bar, "BORDER")
    f.stone = Borders.Stone(bar, 1)
    f.frameArt = Borders.Forever(bar)
    -- Elite and rare: a dragon round the bar's right end (and a mirrored one round its left, if
    -- set), over the borders but under the text.
    f.dragons = CreateFrame("Frame", nil, f)
    f.dragons:SetAllPoints(bar)
    f.dragons:SetFrameLevel(bar:GetFrameLevel() + 2)
    f.dragonRight = f.dragons:CreateTexture(nil, "ARTWORK")
    f.dragonLeft = f.dragons:CreateTexture(nil, "ARTWORK")
    f.dragonLeft:SetTexCoord(1, 0, 0, 1)
    f.dragons:Hide()
    -- The classic look: its border round the bar (in three pieces, the middle stretching), the
    -- elite dragon round the level box, and the glow over your target's bar.
    f.classic = CreateFrame("Frame", nil, f)
    f.classic:SetAllPoints(bar)
    f.classic:SetFrameLevel(bar:GetFrameLevel() + 1)
    f.classicParts = {}
    for i = 1, 3 do
        local t = f.classic:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CLASSIC.border)
        f.classicParts[i] = t
    end
    f.elite = f.classic:CreateTexture(nil, "OVERLAY")
    f.elite:SetTexture(CLASSIC.elite)
    f.elite:SetTexCoord(0, 1, 0, 1)
    f.elite:Hide()
    f.classicGlow = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    f.classicGlow:SetTexture(CLASSIC.glow)
    f.classicGlow:SetTexCoord(5 / 128, 106 / 128, 20 / 32, 27 / 32)
    f.classicGlow:SetBlendMode("ADD")
    f.classicGlow:SetAllPoints(bar)
    f.classicGlow:Hide()
    f.classic:Hide()
    -- Your target: a second, coloured ring round the black one.
    f.ring = CreateFrame("Frame", nil, f)
    f.ring:SetAllPoints(bar)
    f.ringBorder = Borders.Edges(f.ring, bar, "OVERLAY")
    -- Or arrows either side ("> bar <"), gently pointing in, and a soft glow behind the bar.
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.glow:SetTexture(MEDIA .. "Glow.tga")
    -- Nine-sliced where the game can, so the glow keeps its width on long bars.
    if f.glow.SetTextureSliceMargins then
        pcall(f.glow.SetTextureSliceMargins, f.glow, 16, 16, 16, 16)
        if Enum.UITextureSliceMode then pcall(f.glow.SetTextureSliceMode, f.glow, Enum.UITextureSliceMode.Stretched) end
    end
    f.glow:SetBlendMode("ADD")
    f.glow:Hide()
    f.arrows = CreateFrame("Frame", nil, f)
    f.arrows:SetAllPoints(bar)
    f.arrowLeft = f.arrows:CreateTexture(nil, "OVERLAY")
    f.arrowLeft:SetTexture(MEDIA .. "Arrow.tga")
    f.arrowRight = f.arrows:CreateTexture(nil, "OVERLAY")
    f.arrowRight:SetTexture(MEDIA .. "Arrow.tga")
    f.arrowRight:SetTexCoord(1, 0, 0, 1) -- "<"
    local bounce = f.arrows:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local nudge = bounce:CreateAnimation("Alpha")
    nudge:SetFromAlpha(1)
    nudge:SetToAlpha(0.55)
    nudge:SetDuration(0.7)
    nudge:SetSmoothing("IN_OUT")
    f.arrows.pulse = bounce
    f.arrows:Hide()

    local text = CreateFrame("Frame", nil, bar)
    text:SetAllPoints()
    text:SetFrameLevel(bar:GetFrameLevel() + 3)
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
    -- The raid mark: an icon written into text (see UpdateMark), since which mark it is can be
    -- secret in combat.
    f.mark = text:CreateFontString(nil, "OVERLAY")
    f.mark:SetFont(STANDARD_TEXT_FONT, 12, "")
    f.mark:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    f.mark:Hide()
    -- The classic look's level, in its box (and the skull for ??).
    f.level = text:CreateFontString(nil, "OVERLAY")
    f.level:SetShadowOffset(1, -1)
    f.level:SetShadowColor(0, 0, 0, 1)
    f.skull = text:CreateTexture(nil, "OVERLAY")
    f.skull:SetTexture(CLASSIC.skull)
    f.skull:Hide()
    -- Wanted by your quests: a "!" before the name (see UpdateQuest).
    f.quest = text:CreateTexture(nil, "OVERLAY")
    f.quest:SetTexture(QUEST_ICON)
    f.quest:Hide()

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

local function BlizzardCast(uf)
    return uf and uf.CastBarsContainer and uf.CastBarsContainer.castBar
end

------------------------------------------------------------------------------
-- Casts you can't interrupt. Blizzard's cast bar already knows (the cast's notInterruptible,
-- secret for enemies in combat) and shows or hides its own shield to match (UpdateIconShown).
-- We follow that shield, handing what it's given straight to SetAlphaFromBoolean, which takes
-- secrets: our fill over Blizzard's, in the uninterruptible colour, and our small shield beside
-- the bar. Blizzard's shield is hidden on our plates (its art doesn't fit our bar).
------------------------------------------------------------------------------

-- A classic frame in three pieces round `region`, from its file's measurements (in texels):
-- cuts = { left, mid, end, right } (the pieces' edges), open = { x0, x1, y0 } (the opening's left
-- and right, and its top row), rows = { top, bottom } (the pieces' rows), size = { w, h } (the
-- file's). k: units per texel. The middle stretches with the region's width. rightW: the right piece
-- drawn this many texels wide (squeezed), if not its own.
local function PlaceThree(parts, region, k, cuts, open, rows, size, rightW)
    local l, m, e, r = cuts[1], cuts[2], cuts[3], cuts[4]
    local top, bottom = rows[1], rows[2]
    local h = (bottom - top) * k
    local v0, v1 = top / size[2], bottom / size[2]
    local left, mid, right = parts[1], parts[2], parts[3]
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", region, "TOPLEFT", -(open[1] - l) * k, (open[3] - top) * k)
    left:SetSize((m - l) * k, h)
    left:SetTexCoord(l / size[1], m / size[1], v0, v1)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", region, "TOPRIGHT", (e - open[2]) * k, (open[3] - top) * k)
    right:SetSize((rightW or (r - e)) * k, h)
    right:SetTexCoord(e / size[1], r / size[1], v0, v1)
    mid:ClearAllPoints()
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetTexCoord(m / size[1], e / size[1], v0, v1)
end

-- Classic's plate: its border (the 128 x 32 original's lower half) drawn 128 x 16 round a 103.75 x 10
-- health bar, the bar 3.5 in from its left, 20.75 from its right, 2.5 from its top (so the fill runs
-- under the border's inner bevel, as it did). Forever's copy is the same but for a wider level box:
-- its end (100-136) is drawn squeezed to the original's (100-128).
local BORDER_CUTS, BORDER_OPEN, BORDER_ROWS, BORDER_SIZE = { 0, 8, 100, 136 }, { 3.5, 107.25, 18.5 }, { 16, 32 }, { 256, 32 }
local BORDER_END = 28
local CLASSIC_BAR_W, CLASSIC_BAR_H = 103.75, 10
-- The classic cast bar, from its border's left (20.75) and right (3.5) ends, 2.5 below its top
-- and 3.5 above its bottom, 10 tall; its border lined up under the health bar's, 2 below it.
local CAST_IN_L, CAST_IN_R, CAST_IN_T, CAST_IN_B = 20.75, 3.5, 2.5, 3.5
local CAST_BORDER_GAP = 2
local CAST_EXTRAS = { "Border", "CastTargetNameText", "CastTargetIndicator" }

local casts = {} -- Blizzard cast bar -> our parts on it: fill, shield, and the last shield state

local function CastParts(cast)
    local x = casts[cast]
    if x then return x end
    x = {}
    x.fill = cast:CreateTexture(nil, "ARTWORK", nil, 7)
    x.fill:SetAlpha(0)
    x.shield = cast:CreateTexture(nil, "OVERLAY", nil, 7)
    x.shield:SetTexture(MEDIA .. "Shield.tga")
    x.shield:SetAlpha(0)
    -- The classic look's cast bar frame, and its shielded one over it for casts you can't interrupt.
    x.classic = cast:CreateTexture(nil, "OVERLAY", nil, 5)
    x.classic:SetTexture(CLASSIC.cast)
    x.classic:SetTexCoord(0, 1, 0.5, 1)
    x.classic:SetAlpha(0)
    x.classicShield = cast:CreateTexture(nil, "OVERLAY", nil, 6)
    x.classicShield:SetTexture(CLASSIC.shield)
    x.classicShield:SetAlpha(0)
    casts[cast] = x
    return x
end

-- A texture over a status bar's fill exactly (shrinking and growing with it). It stays on the top
-- sublevel of ARTWORK, where CastParts made it: the fill's own draw layer can be secret on enemy
-- cast bars, so it isn't read.
local function OverFill(region, bar)
    local tex = bar:GetStatusBarTexture()
    if not tex then return end
    region:ClearAllPoints()
    region:SetAllPoints(tex)
end

-- Fully shown when `shown` (which may be secret) is true, hidden when it's false: the game's
-- defaults for SetAlphaFromBoolean.
local function AlphaFrom(region, shown, on)
    if not on then
        region:SetAlpha(0)
    elseif region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(shown)
    elseif not issecret(shown) then
        region:SetAlpha(shown and 1 or 0)
    else
        region:SetAlpha(0)
    end
end

function Plates:CastShield(uf, cast, shown)
    local x = CastParts(cast)
    if not issecret(shown) then shown = shown and true or false end
    x.last, x.seen = shown, true
    local db = ns.db
    local on = own[uf] and db.enabled and db.castBar
    if cast.BorderShield then cast.BorderShield:SetAlpha(on and 0 or 1) end
    AlphaFrom(x.fill, shown, on and db.castColor)
    local classic = Classic()
    AlphaFrom(x.shield, shown, on and db.castShield and not classic)
    x.classic:SetAlpha((on and classic) and 1 or 0)
    AlphaFrom(x.classicShield, shown, on and classic and db.castShield)
end

-- Once per cast bar (they come with the pooled unit frames).
-- The time left on a cast or channel, from the game's own timer for it: its remaining time can be
-- secret in combat, so it only ever goes straight into the text. Nothing when there's no timer
-- (between casts, or an interrupted cast held in red).
local function CastTimer(unit)
    for _, fn in ipairs({ UnitCastingDuration, UnitChannelDuration }) do
        local ok, d = pcall(fn, unit)
        if ok and (issecret(d) or d ~= nil) then return d end
    end
end

local function WriteCastTime(fs, unit)
    local d = unit and CastTimer(unit)
    if d then
        fs:SetFormattedText("%.1f", d:GetRemainingDuration())
    else
        fs:SetText("")
    end
end

local function HookCast(uf)
    local cast = BlizzardCast(uf)
    if not cast then return end
    local x = CastParts(cast)
    if x.hooked then return end
    x.hooked = true
    -- The time left (castTime), at the bar's right end, ten times a second while it shows.
    x.time = cast:CreateFontString(nil, "OVERLAY", nil, 7)
    x.time:SetShadowOffset(1, -1)
    x.time:SetShadowColor(0, 0, 0, 1)
    x.time:Hide()
    local since = 0
    cast:HookScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.1 or not x.time:IsShown() then return end
        since = 0
        if not pcall(WriteCastTime, x.time, cast.unit) then x.time:SetText("") end
    end)
    if cast.BorderShield and type(cast.BorderShield.SetShown) == "function" then
        hooksecurefunc(cast.BorderShield, "SetShown", function(_, shown) Plates:CastShield(uf, cast, shown) end)
    end
    -- Blizzard may swap its fill texture as the cast changes state.
    if type(cast.UpdateBarFillTexture) == "function" then
        hooksecurefunc(cast, "UpdateBarFillTexture", function() OverFill(x.fill, cast) end)
    end
    -- An interrupted cast turns red, which ours mustn't cover; the next cast sets it again.
    if type(cast.PlayInterruptAnims) == "function" then
        hooksecurefunc(cast, "PlayInterruptAnims", function() x.fill:SetAlpha(0) end)
    end
end

-- The black edge, and your target's ring in the target colour just outside it. Sized in screen
-- pixels, so placed again whenever the plate's scale changes (it grows as enemies come closer).
function Plates:PlaceBorders(f)
    local db = ns.db
    local style = Classic() and "none" or db.borderStyle
    f.placedScale = f:GetEffectiveScale()
    Borders.Show({ edges = f.border, stone = f.stone, forever = f.frameArt }, style,
        { size = 1, color = { r = 0, g = 0, b = 0 }, thickness = db.frameThickness })
    -- The target ring goes just outside whichever border it is.
    local out = (style == "classic" and 3) or (style == "forever" and 2 * (db.frameThickness or 1)) or 1
    f.ringBorder:Place(1, out, db.colors.target)
    local c = db.colors.target
    -- Arrows: a little taller than the bar, half as wide as tall, just clear of the border.
    local ah = db.height + 8
    local gap = out + 4
    for _, a in ipairs({ f.arrowLeft, f.arrowRight }) do
        a:SetSize(ah / 2, ah)
        a:SetVertexColor(c.r, c.g, c.b)
    end
    -- The glow: 10 out from the bar all round.
    f.glow:ClearAllPoints()
    f.glow:SetPoint("TOPLEFT", f.bar, "TOPLEFT", -10, 10)
    f.glow:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 10, -10)
    f.glow:SetVertexColor(c.r, c.g, c.b, 0.55)
    -- The raid mark and threat text move out past the arrows when they show.
    f.arrowGap = gap
    f.arrowRoom = gap + ah / 2
    self:PlaceSides(f)
end

-- What sits beside the bar (arrows, raid mark, threat text) keeps clear of the dragons, and the
-- raid mark and threat text of the arrows too.
function Plates:PlaceSides(f)
    local reach = f.hasDragon and f.dragonReach or 0
    local right, left = reach, ns.db.dragons.both and reach or 0
    -- The classic look: clear of its level box (and the elite dragon round it).
    if Classic() then right, left = f.classicReach or 0, 0 end
    local gap = f.arrowGap or 5
    f.arrowLeft:ClearAllPoints()
    f.arrowLeft:SetPoint("RIGHT", f.bar, "LEFT", -gap - left, 0)
    f.arrowRight:ClearAllPoints()
    f.arrowRight:SetPoint("LEFT", f.bar, "RIGHT", gap + right, 0)
    local room = f.arrows:IsShown() and (f.arrowRoom or 0) or 0
    f.mark:ClearAllPoints()
    f.mark:SetPoint("RIGHT", f.bar, "LEFT", -4 - left - room, 0)
    f.threat:ClearAllPoints()
    f.threat:SetPoint("LEFT", f.bar, "RIGHT", 4 + right + room, 0)
end

-- The dragons: the hole in the art (see DRAGON) a little taller than the bar, its middle just
-- inside the bar's end, so the head sits over the bar and the tail curls under it. Sized from the
-- bar's height (in plate units, so they scale with the plate).
function Plates:PlaceDragons(f)
    local db = ns.db
    local s = (db.height + 12) / (2 * DRAGON.holeR) * (db.dragons.size or 1) -- per texel
    local inset = 2 * s
    local dx, dy = (DRAGON.size / 2 - DRAGON.holeX) * s, (DRAGON.size / 2 - DRAGON.holeY) * s
    local size = DRAGON.size * s
    f.dragonRight:ClearAllPoints()
    f.dragonRight:SetPoint("CENTER", f.bar, "RIGHT", dx - inset, -dy)
    f.dragonRight:SetSize(size, size)
    f.dragonLeft:ClearAllPoints()
    f.dragonLeft:SetPoint("CENTER", f.bar, "LEFT", inset - dx, -dy)
    f.dragonLeft:SetSize(size, size)
    -- How far past the bar's end they reach.
    f.dragonReach = (DRAGON.right - DRAGON.holeX) * s - inset
end

-- The classic look's border round the bar, its level box (the level, or the skull), the elite
-- dragon round that box, and the name centred above. As 1.x drew them (k: units per texel, 1 at
-- Classic's own size): the level's middle 11.5 in from the border's right end, at its middle; the
-- dragon (its whole 64 x 32 art at 57.5 x 29) from 12.5 left of and 12 above the level.
local LEVEL_X = 128 - 11.5 - 107.25 -- past the bar's end
local BORDER_RIGHT = 128 - 107.25

function Plates:PlaceClassic(f)
    local db = ns.db
    local on = Classic()
    f.classic:SetShown(on)
    f.name:SetJustifyH(on and "CENTER" or "LEFT")
    if not on then
        f.level:Hide()
        f.skull:Hide()
        f.elite:Hide()
        return
    end
    local k = (f.barHeight or db.height) / CLASSIC_BAR_H
    PlaceThree(f.classicParts, f.bar, k, BORDER_CUTS, BORDER_OPEN, BORDER_ROWS, BORDER_SIZE, BORDER_END)
    for _, t in ipairs(f.classicParts) do t:SetDesaturated(db.classicGrey and true or false) end
    local bx, by = LEVEL_X * k, -0.5 * k
    -- The level (and the skull in its place) nudged by levelX / levelY; the dragon stays put.
    local lx, ly = bx + (db.levelX or 0), by + (db.levelY or 0)
    f.level:ClearAllPoints()
    f.level:SetPoint("CENTER", f.bar, "RIGHT", lx, ly)
    ns.Media:SetFont(f.level, db.font, db.textSize, db.outline)
    f.skull:ClearAllPoints()
    f.skull:SetPoint("CENTER", f.bar, "RIGHT", lx, ly)
    f.skull:SetSize(12 * k, 12 * k)
    f.elite:ClearAllPoints()
    f.elite:SetPoint("TOPLEFT", f.bar, "RIGHT", bx - 12.5 * k, by + 12 * k)
    f.elite:SetSize(57.5 * k, 29 * k)
    f.boxReach = BORDER_RIGHT * k
    f.eliteReach = math.max(f.boxReach, bx - 12.5 * k + 57.5 * k * 37 / 64)
    f.classicReach = f.elite:IsShown() and f.eliteReach or f.boxReach
    -- Your target's glow over the bar, in the target colour.
    local c = db.colors.target
    f.classicGlow:SetVertexColor(c.r, c.g, c.b, db.highlight.classicGlow or 0.5)
end

function Plates:Layout(f)
    local db, uf = ns.db, f.uf
    local anchor = BlizzardBar(uf) or f.base
    local bar = f.bar
    bar:ClearAllPoints()
    -- Centred on the plate (which the game keeps over the enemy), at the height of Blizzard's bar.
    -- That bar starts at the plate's left but stops short on the right, for the level badge, and
    -- nameplates can't be measured; so a slot is anchored from its top left to the top right of
    -- the cast bar area below it (the plate's full width, evenly inset), raised by the gap
    -- between the two: the plate's width at the health bar's height.
    local hc, cc = uf and uf.HealthBarsContainer, uf and uf.CastBarsContainer
    local slot = f.slot
    slot:ClearAllPoints()
    if hc and cc then
        local gap = NamePlateSetupOptions and NamePlateSetupOptions.castBarToHealthBarSpacing or 0
        slot:SetPoint("TOPLEFT", hc, "TOPLEFT")
        slot:SetPoint("BOTTOMRIGHT", cc, "TOPRIGHT", 0, gap)
    else
        slot:SetAllPoints(anchor)
    end
    -- The classic look at Classic's own size (classicSize): its bar, and a cast bar as wide with its
    -- frame's proportions.
    local classicSize = Classic() and db.classicSize
    local width = classicSize and CLASSIC_BAR_W or db.width
    f.barHeight = classicSize and CLASSIC_BAR_H or db.height
    -- Blizzard's cast bar isn't ours, so our scale (db.scale) is put on its height and gap.
    local scale = db.scale or 1
    local k = f.barHeight / CLASSIC_BAR_H -- the classic look's units per texel
    local castHeight = (Classic() and CLASSIC_BAR_H * k or db.castHeight) * scale
    if width > 0 then
        bar:SetPoint("CENTER", slot, "CENTER")
        bar:SetWidth(width)
    else
        -- As wide as the plate.
        bar:SetPoint("LEFT", slot, "LEFT")
        bar:SetPoint("RIGHT", slot, "RIGHT")
    end
    bar:SetHeight(f.barHeight)
    bar:SetStatusBarTexture(Texture())
    local ex = db.colors.execute
    OverFill(f.execute, bar)
    f.execute:SetTexture(Texture())
    f.execute:SetVertexColor(ex.r, ex.g, ex.b)
    -- The game dims a plate whose enemy is behind terrain or far off (on the plate's base
    -- frame); without gameFade ours keeps its own opacity, like the cast bar and auras do.
    f:SetIgnoreParentAlpha(not db.gameFade)
    Plates:PlaceDragons(f)
    Plates:PlaceClassic(f)
    Plates:PlaceBorders(f)

    ns.Media:SetFont(f.name, db.font, db.nameSize, db.outline)
    for _, fs in pairs(f.texts) do ns.Media:SetFont(fs, db.font, db.textSize, db.outline) end
    ns.Media:SetFont(f.threat, db.font, db.textSize, db.outline)

    -- Blizzard's cast bar, under ours.
    local cast = BlizzardCast(uf)
    if cast then
        cast:SetIgnoreParentAlpha(db.castBar)
        if db.castBar then
            cast:ClearAllPoints()
            if Classic() then
                -- Its border lined up under the health bar's, so the bar itself sits further right.
                local dx = (CAST_IN_L - BORDER_OPEN[1]) * k * scale
                local below = BORDER_ROWS[2] - BORDER_OPEN[3] - CLASSIC_BAR_H -- the health border under its bar
                local dy = -(below + CAST_BORDER_GAP + CAST_IN_T) * k * scale
                cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", dx, dy)
                cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", dx, dy)
            else
                cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -db.castGap * scale)
                cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -db.castGap * scale)
            end
            cast:SetHeight(castHeight)
        end
        -- Casts you can't interrupt: our fill in their colour, and the shield just left of the
        -- bar, a little taller than it, in a lighter shade of that colour.
        local x = CastParts(cast)
        local c = db.colors.uninterruptible
        OverFill(x.fill, cast)
        x.fill:SetTexture(Texture())
        x.fill:SetVertexColor(c.r, c.g, c.b)
        local sh = castHeight + 4
        x.shield:ClearAllPoints()
        x.shield:SetPoint("RIGHT", cast, "LEFT", -2, 0)
        x.shield:SetSize(sh, sh)
        x.shield:SetVertexColor(c.r + (1 - c.r) * 0.5, c.g + (1 - c.g) * 0.5, c.b + (1 - c.b) * 0.5)
        -- The classic look: its border round the cast bar, the spell's icon in its slot, Classic's
        -- small shield round casts you can't interrupt (as Blizzard's own Classic style has them).
        if Classic() then
            local u = k * scale
            x.classic:ClearAllPoints()
            x.classic:SetPoint("TOPLEFT", cast, "TOPLEFT", -CAST_IN_L * u, CAST_IN_T * u)
            x.classic:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", CAST_IN_R * u, -CAST_IN_B * u)
            x.classicShield:ClearAllPoints()
            x.classicShield:SetPoint("TOPLEFT", cast, "TOPLEFT", -20 * u, 11 * u)
            x.classicShield:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 13 * u, -13 * u)
            if cast.Icon then
                cast.Icon:ClearAllPoints()
                cast.Icon:SetPoint("CENTER", cast, "LEFT", (11.5 - CAST_IN_L) * u, 0)
                cast.Icon:SetSize(14 * u, 14 * u)
                -- Over the border's slot (the border is on OVERLAY 5, the shield 6).
                cast.Icon:SetDrawLayer("OVERLAY", 7)
            end
        end
        -- The spell's name (Blizzard's text on its bar) in our font and outline, at its own size
        -- (castNameSize; 0: the small text's), from the bar's left end nudged by castNameX / Y.
        if cast.Text then
            local size = (db.castNameSize or 0) > 0 and db.castNameSize or db.textSize
            ns.Media:SetFont(cast.Text, db.font, size, db.outline)
            cast.Text:ClearAllPoints()
            cast.Text:SetPoint("LEFT", cast, "LEFT", 2 + (db.castNameX or 0), db.castNameY or 0)
            cast.Text:SetJustifyH("LEFT")
        end
        -- The time left, in our font: inside the bar's right end in the classic look (which hides
        -- the cast's target's name there), just past it in ours (where that name stays).
        if x.time then
            x.time:SetShown(db.castTime and true or false)
            -- Its own size (castTimeSize; 0: the small text's) and nudge (castTimeX, castTimeY).
            local size = (db.castTimeSize or 0) > 0 and db.castTimeSize or db.textSize
            ns.Media:SetFont(x.time, db.font, size, db.outline)
            x.time:ClearAllPoints()
            local dx, dy = db.castTimeX or 0, db.castTimeY or 0
            if Classic() then
                x.time:SetPoint("RIGHT", cast, "RIGHT", -2 + dx, dy)
            else
                x.time:SetPoint("LEFT", cast, "RIGHT", 3 + dx, dy)
            end
        end
        -- Blizzard's own border, the cast's target's name and its "aimed at you" outline: out of
        -- sight in the classic look (1.x had none of them).
        for _, key in ipairs(CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(Classic() and 0 or 1) end
        end
        -- Put the last shield state Blizzard set back, now the plate is ours (or the settings
        -- changed). It may be secret, so it's never tested here.
        if x.seen then
            self:CastShield(uf, cast, x.last)
        else
            self:CastShield(uf, cast, false)
        end
    end
    -- Blizzard's auras (your debuffs; buffs you can steal; crowd control), above the name.
    local auras = uf and uf.AurasFrame
    if auras then
        auras:SetIgnoreParentAlpha(db.auras)
        if db.auras then
            -- Over the name (higher in the classic look, whose name sits above its border).
            local up = db.nameSize + 6
            if Classic() then up = up + 2.5 * f.barHeight / CLASSIC_BAR_H end
            up = up * scale -- in its own (unscaled) units, over our scaled name
            auras:ClearAllPoints()
            auras:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, up)
            auras:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, up)
            -- Blizzard pins its rows to its own health bar and name (UpdateAnchors, after which
            -- this runs again): pinned to ours instead. Your debuffs over the name (centred in the
            -- classic look, as its name is; from the bar's left end in ours), stealable buffs over
            -- its right end, crowd control and loss of control just past it.
            local debuffs = auras.DebuffListFrame
            if debuffs then
                debuffs:ClearAllPoints()
                if Classic() then
                    debuffs:SetPoint("BOTTOM", bar, "TOP", 0, up)
                else
                    debuffs:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, up)
                end
            end
            if auras.BuffListFrame then
                auras.BuffListFrame:ClearAllPoints()
                auras.BuffListFrame:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, up)
            end
            local side = (f.classicReach and Classic() and f.classicReach or 0) * scale + 5
            for _, key in ipairs({ "CrowdControlListFrame", "LossOfControlFrame" }) do
                if auras[key] then
                    auras[key]:ClearAllPoints()
                    auras[key]:SetPoint("LEFT", bar, "RIGHT", side, 0)
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- Filling it in
------------------------------------------------------------------------------

function Plates:UpdateHealth(f)
    local unit = f.unit
    f.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    f.bar:SetValue(UnitHealth(unit))
    -- Health, the name and the level may be secret: FrogLib.Unit's words only ever go to
    -- SetFormattedText.
    for slot, fs in pairs(f.texts) do
        Unit.SetText(fs, ns.db.text[slot], unit)
    end
    self:UpdateExecute(f)
    self:UpdateDead(f)
end

-- A dead enemy's plate goes (the game can keep the plate itself for a while).
function Plates:UpdateDead(f)
    f:SetShown(Safe(UnitIsDead(f.unit)) ~= true)
end

-- The execute overlay's opacity: from the game's curve where it has one (health may be secret),
-- otherwise worked out here while health isn't secret.
function Plates:UpdateExecute(f)
    local below = ns.db.execute and executeBelow
    if not below then
        f.execute:Hide()
        return
    end
    local alpha = 0
    local curve = ExecuteCurve(below)
    if curve then
        local a = FrogLib.Curve.Health(f.unit, curve)
        if issecret(a) or a ~= nil then alpha = a end
    else
        local h, m = Safe(UnitHealth(f.unit)), Safe(UnitHealthMax(f.unit))
        if h and m and m > 0 and h / m < below then alpha = 1 end
    end
    f.execute:SetAlpha(alpha)
    f.execute:Show()
end

-- Elite (gold), rare (silver) or rare elite (silver, winged); world bosses get the gold one.
function Plates:UpdateDragon(f)
    local d = ns.db.dragons
    local class = Safe(UnitClassification(f.unit)) or ""
    -- The classic look: Classic's own little dragon round the level box, for elites only.
    if Classic() then
        f.hasDragon = false
        f.dragons:Hide()
        f.elite:SetShown(d.shown and (class == "elite" or class == "rareelite" or class == "worldboss"))
        f.classicReach = f.elite:IsShown() and f.eliteReach or f.boxReach
        self:PlaceSides(f)
        return
    end
    f.elite:Hide()
    local art = d.shown and DRAGON_ART[class]
    f.hasDragon = art and true or false
    if art then
        f.dragonRight:SetTexture(MEDIA .. art .. ".tga")
        f.dragonLeft:SetTexture(MEDIA .. art .. ".tga")
        f.dragonLeft:SetShown(d.both)
    end
    f.dragons:SetShown(f.hasDragon)
    self:PlaceSides(f)
end

------------------------------------------------------------------------------
-- Quest marker: whether your quests still need this enemy. The unit's tooltip, as the game builds
-- it, lists your objectives for it with whether each is done; failing that (no objective lines, or
-- the game withholding the tooltip), the game's own C_QuestLog.UnitIsRelatedToActiveQuest.
------------------------------------------------------------------------------

local QUEST_LINE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

-- The unit's quest objective lines, and how many aren't done; nothing if the game won't say.
local function QuestLines(unit)
    if not (QUEST_LINE and C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local data = Safe(C_TooltipInfo.GetUnit(unit))
    local lines = type(data) == "table" and Safe(data.lines)
    if type(lines) ~= "table" then return end
    local total, open = 0, 0
    for _, line in ipairs(lines) do
        if type(line) == "table" and Safe(line.type) == QUEST_LINE then
            total = total + 1
            if Safe(line.completed) ~= true then open = open + 1 end
        end
    end
    return total, open
end

local function OnQuest(unit)
    if Safe(UnitIsPlayer(unit)) ~= false then return false end
    local ok, total, open = pcall(QuestLines, unit)
    if ok and total and total > 0 then return open > 0 end
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok2, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        return ok2 and Safe(related) == true
    end
    return false
end

-- The "!" sits just before the name, which moves along to make room for it.
function Plates:UpdateQuest(f)
    local db = ns.db
    local shown = db.questMarker and OnQuest(f.unit) or false
    local q = db.nameSize + 4
    f.quest:SetSize(q, q)
    f.quest:ClearAllPoints()
    -- The classic look: the name centred over the plate as wide as it needs (as 1.x had it), 2
    -- above the border, the "!" just before it.
    if Classic() then
        local k = (f.barHeight or db.height) / CLASSIC_BAR_H
        f.name:ClearAllPoints()
        f.name:SetPoint("BOTTOM", f.bar, "TOP", shown and math.floor(q * 0.25 + 0.5) or 0, 2.5 * k + 2)
        f.quest:SetPoint("RIGHT", f.name, "LEFT", math.floor(q * 0.3 + 0.5), 0)
        f.quest:SetShown(shown)
        return
    end
    -- The "!" is the middle third or so of its square: its left edge on the bar's.
    f.quest:SetPoint("BOTTOMLEFT", f.bar, "TOPLEFT", -math.floor(q * 0.3 + 0.5), 1)
    f.quest:SetShown(shown)
    f.name:ClearAllPoints()
    f.name:SetPoint("BOTTOMLEFT", f.bar, "TOPLEFT", shown and math.floor(q * 0.45 + 0.5) or 0, 3)
    f.name:SetPoint("BOTTOMRIGHT", f.bar, "TOPRIGHT", 0, 3)
end

function Plates:UpdateName(f)
    local unit, db = f.unit, ns.db
    -- The name may be secret: never tested, only written.
    local name = Unit.Name(unit)
    if not issecret(name) and name == nil then name = "" end
    -- The classic look: the name alone, the level in its box (the skull for ??, nothing while the
    -- game keeps it secret).
    if Classic() then
        pcall(f.name.SetText, f.name, name)
        local lv = Safe(UnitLevel(unit))
        local skull = lv ~= nil and lv <= 0
        f.skull:SetShown(skull)
        f.level:SetShown(lv ~= nil and not skull)
        if lv and lv > 0 then
            local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lv) or { r = 1, g = 1, b = 1 }
            f.level:SetText(lv)
            f.level:SetTextColor(c.r, c.g, c.b)
        end
        return
    end
    local level = db.showLevel and Safe(UnitLevel(unit))
    if level then
        local text = level > 0 and tostring(level) or "??"
        local class = Safe(UnitClassification(unit))
        if class == "elite" or class == "rareelite" or class == "worldboss" then text = text .. "+" end
        local c = (level > 0 and GetCreatureDifficultyColor) and GetCreatureDifficultyColor(level) or { r = 1, g = 0.2, b = 0.2 }
        pcall(f.name.SetFormattedText, f.name, "%s %s", Color.Wrap(text, c.r, c.g, c.b), name)
    else
        pcall(f.name.SetText, f.name, name)
    end
end

function Plates:UpdateColour(f)
    f.bar:SetStatusBarColor(Colour(f.unit))
end

local STATUS = {
    [1] = { "Pulling!", "danger" },
    [2] = { "Slipping", "danger" },
    [3] = { "Tanking", "safe" },
}

function Plates:UpdateThreat(f)
    local unit, db = f.unit, ns.db
    local situation = Safe(UnitThreatSituation("player", unit))
    if not (db.threatText and situation ~= nil) then
        f.threat:Hide()
        return
    end
    f.threat:Show()
    self:NoteThreat(unit)
    local gap = Threat.Gap(unit)
    local c = db.colors
    if gap then
        Threat.SetGapText(f.threat, gap, c.safe, c.danger)
    elseif situation >= 1 then
        -- The numbers are hidden (in dungeons the game keeps them from addons), so no lead: the
        -- game's own verdict instead. 3: it's on you and staying; 2: it's on you but someone has
        -- more and it's about to go; 1: it's on someone else but you have more, it's coming to you.
        local word, col = STATUS[situation][1], STATUS[situation][2] == "safe" and c.safe or c.danger
        f.threat:SetTextColor(col.r, col.g, col.b)
        f.threat:SetText(word)
    else
        -- Not on you: your threat as a share of what would pull it (may be secret).
        local _, _, percent = UnitDetailedThreatSituation("player", unit)
        f.threat:SetTextColor(1, 1, 1)
        pcall(f.threat.SetFormattedText, f.threat, "%d%%", percent)
    end
end

-- Which mark a unit has can be secret in combat, so the number is never looked at: FrogLib.Icons
-- writes it into the icon's file name inside the text, filled in engine-side. A secret "no mark"
-- fails to format, and hides it.
function Plates:UpdateMark(f)
    local shown = ns.db.raidMarks and Icons.RaidMark(f.mark, f.unit, ns.db.markSize) or false
    f.mark:SetShown(shown)
end

function Plates:UpdateTarget()
    local target = C_NamePlate.GetNamePlateForUnit("target")
    for base, f in pairs(frames) do
        if f.unit then
            local isTarget = target == base
            local hl = ns.db.highlight
            -- The classic look's own target glow over the bar, for either the outline or the glow.
            local classic = Classic()
            f.ringBorder:SetShown(isTarget and hl.outline and not classic)
            f.glow:SetShown(isTarget and hl.glow and not classic)
            f.classicGlow:SetShown(isTarget and classic and (hl.outline or hl.glow))
            local arrows = isTarget and hl.arrows
            if arrows ~= f.arrows:IsShown() then
                f.arrows:SetShown(arrows)
                if arrows then f.arrows.pulse:Play() else f.arrows.pulse:Stop() end
            end
            self:PlaceSides(f)
            f:SetScale((isTarget and hl.scale or 1) * (ns.db.scale or 1))
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
    self:UpdateDragon(f)
    self:UpdateQuest(f)
end

-- Quest progress comes in bursts of events: look again once they settle.
local questPending
function Plates:QuestsChanged()
    if questPending then return end
    questPending = true
    C_Timer.After(0.3, function()
        questPending = nil
        for _, f in pairs(byUnit) do Plates:UpdateQuest(f) end
    end)
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
        local cast = BlizzardCast(uf)
        if cast then
            cast:SetIgnoreParentAlpha(false)
            -- Blizzard's shield and border back, ours away.
            if cast.BorderShield then cast.BorderShield:SetAlpha(1) end
            for _, key in ipairs(CAST_EXTRAS) do
                if cast[key] then cast[key]:SetAlpha(1) end
            end
            local x = casts[cast]
            if x then
                x.fill:SetAlpha(0)
                x.shield:SetAlpha(0)
                if x.time then x.time:Hide() end
                x.classic:SetAlpha(0)
                x.classicShield:SetAlpha(0)
            end
        end
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
    HookCast(uf)
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
    self:UpdateDead(f)
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
    self:ExecuteCheck()
    for unit in pairs(byUnit) do self:Remove(unit) end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then self:Add(unit) end
    end
end

-- The last snapshot of your target taken in combat, so /fp threat can show it after the fight.
local lastSeen, lastSeenAt = nil, 0

function Plates:NoteThreat(unit)
    if not (Safe(UnitAffectingCombat("player")) and Safe(UnitIsUnit(unit, "target"))) then return end
    local now = GetTime()
    if now - lastSeenAt < 1 then return end
    lastSeenAt = now
    lastSeen = Threat.Snapshot(unit)
end

-- /fp threat: live while you're fighting your target, otherwise the last fight's snapshot.
function Plates:ThreatReport()
    local live = UnitExists("target") and Safe(UnitAffectingCombat("player"))
    local lines = live and Threat.Snapshot("target") or lastSeen
    if not lines then
        ns.Print("nothing seen yet: fight something with it targeted, then try again.")
        return
    end
    ns.Print(live and "threat now:" or string.format("threat as last seen in combat (%ds ago):", math.floor(GetTime() - lastSeenAt)))
    for _, line in ipairs(lines) do print(line) end
end

function Plates:Init()
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) Plates:Add(unit) end)
    hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) Plates:Remove(unit) end)

    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
        "UNIT_FLAGS", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED",
        "RAID_TARGET_UPDATE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
        "UNIT_CLASSIFICATION_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, event)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_QUEST_LOG_CHANGED", "player")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            Plates:UpdateTarget()
            return
        elseif event == "RAID_TARGET_UPDATE" then
            for _, f in pairs(byUnit) do Plates:UpdateMark(f) end
            return
        elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_REGEN_ENABLED" or event == "SPELLS_CHANGED" then
            -- A new stance or spell can change your execute too.
            Plates:ExecuteCheck()
            for _, f in pairs(byUnit) do
                Plates:UpdateColour(f)
                Plates:UpdateExecute(f)
            end
            return
        elseif event:match("^QUEST_") or event == "UNIT_QUEST_LOG_CHANGED" then
            Plates:QuestsChanged()
            return
        end
        local f = unit and byUnit[unit]
        if not f then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            Plates:UpdateHealth(f)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            Plates:UpdateName(f)
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            Plates:UpdateName(f)
            Plates:UpdateDragon(f)
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
