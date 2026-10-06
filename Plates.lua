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
local own = {}    -- Blizzard unit frames we've made see-through
local frames = {} -- plate base -> our frame
local byUnit = {} -- nameplate unit token -> our frame
local busy        -- our own SetAlpha, which the hook below ignores

-- A path inside an add-on that isn't loaded (FrogUI's textures, without FrogUI) can't be used.
local Usable = FrogLib.Media.Usable

local function Texture()
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
    AlphaFrom(x.shield, shown, on and db.castShield)
end

-- Once per cast bar (they come with the pooled unit frames).
local function HookCast(uf)
    local cast = BlizzardCast(uf)
    if not cast then return end
    local x = CastParts(cast)
    if x.hooked then return end
    x.hooked = true
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
    local style = db.borderStyle
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
    if db.width > 0 then
        bar:SetPoint("CENTER", slot, "CENTER")
        bar:SetWidth(db.width)
    else
        -- As wide as the plate.
        bar:SetPoint("LEFT", slot, "LEFT")
        bar:SetPoint("RIGHT", slot, "RIGHT")
    end
    bar:SetHeight(db.height)
    bar:SetStatusBarTexture(Texture())
    local ex = db.colors.execute
    OverFill(f.execute, bar)
    f.execute:SetTexture(Texture())
    f.execute:SetVertexColor(ex.r, ex.g, ex.b)
    -- The game dims a plate whose enemy is behind terrain or far off (on the plate's base
    -- frame); without gameFade ours keeps its own opacity, like the cast bar and auras do.
    f:SetIgnoreParentAlpha(not db.gameFade)
    Plates:PlaceDragons(f)
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
            cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -db.castGap)
            cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -db.castGap)
            cast:SetHeight(db.castHeight)
        end
        -- Casts you can't interrupt: our fill in their colour, and the shield just left of the
        -- bar, a little taller than it, in a lighter shade of that colour.
        local x = CastParts(cast)
        local c = db.colors.uninterruptible
        OverFill(x.fill, cast)
        x.fill:SetTexture(Texture())
        x.fill:SetVertexColor(c.r, c.g, c.b)
        local sh = db.castHeight + 4
        x.shield:ClearAllPoints()
        x.shield:SetPoint("RIGHT", cast, "LEFT", -2, 0)
        x.shield:SetSize(sh, sh)
        x.shield:SetVertexColor(c.r + (1 - c.r) * 0.5, c.g + (1 - c.g) * 0.5, c.b + (1 - c.b) * 0.5)
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
            auras:ClearAllPoints()
            auras:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, db.nameSize + 6)
            auras:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, db.nameSize + 6)
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
    local art = d.shown and DRAGON_ART[Safe(UnitClassification(f.unit)) or ""]
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
            f.ringBorder:SetShown(isTarget and hl.outline)
            f.glow:SetShown(isTarget and hl.glow)
            local arrows = isTarget and hl.arrows
            if arrows ~= f.arrows:IsShown() then
                f.arrows:SetShown(arrows)
                if arrows then f.arrows.pulse:Play() else f.arrows.pulse:Stop() end
            end
            self:PlaceSides(f)
            f:SetScale(isTarget and hl.scale or 1)
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
            -- Blizzard's shield back, ours away.
            if cast.BorderShield then cast.BorderShield:SetAlpha(1) end
            local x = casts[cast]
            if x then
                x.fill:SetAlpha(0)
                x.shield:SetAlpha(0)
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
