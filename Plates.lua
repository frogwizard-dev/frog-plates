local _, ns = ...

-- Minimal dark nameplates for enemies (hostile and neutral; friendly ones stay Blizzard's).
--
-- FrogLib's Plates engine takes the plates over (Blizzard's made see-through underneath, its cast
-- bar and auras kept and moved round ours) and tells this skin when to build, lay out and fill in
-- each one; XIVPlates is another skin on the same engine. Values the game keeps secret in combat
-- only ever go straight to widgets.
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

local Engine = FrogLib.Plates
local BlizzardCast, OverFill, AlphaFrom = Engine.BlizzardCast, Engine.OverFill, Engine.AlphaFrom

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

-- After threat, FrogLib.Color's rules: tapped, players' class, then neutral (or friendly) and
-- hostile; hostile when the game won't say.
local rules = { class = true }

local function Colour(unit)
    local c = ns.db.colors
    if ns.db.threat then
        local r, g, b = Engine.ThreatColour(unit, c, ns.db.role)
        if r then return r, g, b end
    end
    -- The classic look: Classic's own pure red, yellow and grey.
    if Classic() then c = CLASSIC_COLORS end
    rules.tapped, rules.hostile, rules.fallback = c.tapped, c.hostile, c.hostile
    rules.neutral, rules.friendly = c.neutral, c.neutral
    return Color.Unit(unit, rules)
end

------------------------------------------------------------------------------
-- Our frame (f: the engine's frame over the plate, with f.base and f.slot)
------------------------------------------------------------------------------

local function Create(f)
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
end

------------------------------------------------------------------------------
-- Casts you can't interrupt. Blizzard's cast bar already knows (the cast's notInterruptible,
-- secret for enemies in combat) and shows or hides its own shield to match; the engine passes
-- that on. Our fill over Blizzard's in the uninterruptible colour, and our small shield beside
-- the bar, follow it (SetAlphaFromBoolean takes secrets). Blizzard's shield is hidden on our
-- plates (its art doesn't fit our bar).
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
local CAST_EXTRAS = Engine.CAST_EXTRAS

local casts = {} -- Blizzard cast bar -> our parts on it: fill, shield, the classic frame and shield

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

function Plates:CastShield(uf, cast, shown, ours)
    local x = CastParts(cast)
    local db = ns.db
    local on = ours and db.enabled and db.castBar
    if cast.BorderShield then cast.BorderShield:SetAlpha(on and 0 or 1) end
    AlphaFrom(x.fill, shown, on and db.castColor)
    local classic = Classic()
    AlphaFrom(x.shield, shown, on and db.castShield and not classic)
    x.classic:SetAlpha((on and classic) and 1 or 0)
    AlphaFrom(x.classicShield, shown, on and classic and db.castShield)
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
    local bar = f.bar
    bar:ClearAllPoints()
    -- Centred on the plate (which the game keeps over the enemy), at the height of Blizzard's bar:
    -- the engine's slot is the plate's width there.
    Engine.PlaceSlot(f)
    local slot = f.slot
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
        local time = Engine.CastParts(cast).time
        if time then
            time:SetShown(db.castTime and true or false)
            -- Its own size (castTimeSize; 0: the small text's) and nudge (castTimeX, castTimeY).
            local size = (db.castTimeSize or 0) > 0 and db.castTimeSize or db.textSize
            ns.Media:SetFont(time, db.font, size, db.outline)
            time:ClearAllPoints()
            local dx, dy = db.castTimeX or 0, db.castTimeY or 0
            if Classic() then
                time:SetPoint("RIGHT", cast, "RIGHT", -2 + dx, dy)
            else
                time:SetPoint("LEFT", cast, "RIGHT", 3 + dx, dy)
            end
        end
        -- Blizzard's own border, the cast's target's name and its "aimed at you" outline: out of
        -- sight in the classic look (1.x had none of them).
        for _, key in ipairs(CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(Classic() and 0 or 1) end
        end
        -- Put the last shield state Blizzard set back, now the plate is ours (or the settings
        -- changed). It may be secret, so it's never tested here.
        local seen = Engine.CastParts(cast)
        if seen.seen then
            self:CastShield(uf, cast, seen.last, true)
        else
            self:CastShield(uf, cast, false, true)
        end
    end
    -- Blizzard's auras (your debuffs; buffs you can steal; crowd control), over the name (higher
    -- in the classic look, whose name sits above its border; centred there, as its name is), in
    -- their own (unscaled) units over our scaled name; crowd control just past the bar's end.
    local up = db.nameSize + 6
    if Classic() then up = up + 2.5 * f.barHeight / CLASSIC_BAR_H end
    local side = (f.classicReach and Classic() and f.classicReach or 0) * scale + 5
    Engine.PlaceAuras(uf, bar, db.auras and true or false, up * scale, Classic(), side)
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

-- The execute overlay: the engine's 1 under your execute's line, 0 above (may be secret).
function Plates:UpdateExecute(f)
    local below = ns.db.execute and Engine.ExecuteBelow()
    if not below then
        f.execute:Hide()
        return
    end
    f.execute:SetAlpha(Engine.ExecuteAlpha(f.unit, below))
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

-- The "!" sits just before the name, which moves along to make room for it (the engine's
-- OnQuest says whether your quests still need this enemy).
function Plates:UpdateQuest(f)
    local db = ns.db
    local shown = db.questMarker and Engine.OnQuest(f.unit) or false
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

function Plates:UpdateThreat(f)
    local db = ns.db
    local shown = db.threatText and Engine.ThreatText(f.threat, f.unit, db.colors)
    f.threat:SetShown(shown and true or false)
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
    Engine.Each(function(f)
        local isTarget = target == f.base
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
    end)
end

------------------------------------------------------------------------------
-- The skin the engine drives
------------------------------------------------------------------------------

local UPDATES = {
    all = function(f)
        Plates:UpdateHealth(f)
        Plates:UpdateName(f)
        Plates:UpdateColour(f)
        Plates:UpdateThreat(f)
        Plates:UpdateMark(f)
        Plates:UpdateDragon(f)
        Plates:UpdateQuest(f)
    end,
    health = function(f) Plates:UpdateHealth(f) end,
    name = function(f) Plates:UpdateName(f) end,
    class = function(f)
        Plates:UpdateName(f)
        Plates:UpdateDragon(f)
    end,
    threat = function(f)
        Plates:UpdateColour(f)
        Plates:UpdateThreat(f)
    end,
    mark = function(f) Plates:UpdateMark(f) end,
    quest = function(f) Plates:UpdateQuest(f) end,
    execute = function(f)
        Plates:UpdateColour(f)
        Plates:UpdateExecute(f)
    end,
}

local skin = {
    owner = "FrogPlates",
    enabled = function() return ns.db.enabled end,
    create = Create,
    layout = function(f) Plates:Layout(f) end,
    update = function(f, what)
        local fn = UPDATES[what]
        if fn then fn(f) end
    end,
    target = function() Plates:UpdateTarget() end,
    -- The borders are sized in screen pixels: placed again when the plate's scale changes (it
    -- grows as enemies come closer).
    tick = function(f)
        if f:GetEffectiveScale() ~= f.placedScale then Plates:PlaceBorders(f) end
    end,
    castShield = function(uf, cast, shown, ours) Plates:CastShield(uf, cast, shown, ours) end,
    -- Blizzard may swap its fill texture as the cast changes state.
    castFill = function(cast) OverFill(CastParts(cast).fill, cast) end,
    -- An interrupted cast turns red, which ours mustn't cover; the next cast sets it again.
    castInterrupted = function(cast) CastParts(cast).fill:SetAlpha(0) end,
    release = function(_, cast)
        local x = casts[cast]
        if x then
            x.fill:SetAlpha(0)
            x.shield:SetAlpha(0)
            x.classic:SetAlpha(0)
            x.classicShield:SetAlpha(0)
        end
    end,
}

-- Every plate again (after a settings change, or turning it on or off).
function Plates:Refresh()
    local db = ns.db
    Engine.AuraSettings({ auras = db.enabled and db.auras, allDebuffs = db.allDebuffs, auraScale = db.auraScale })
    Engine.Refresh()
end

-- /fp threat: live while you're fighting your target, otherwise the last fight's snapshot.
function Plates:ThreatReport()
    Engine.ThreatReport(ns.Print)
end

function Plates:Init()
    local ok, other = Engine.Register(skin)
    if not ok then
        ns.Print(other .. " is already styling the nameplates; turn one of the two off.")
        return
    end
    self:Refresh()
end
