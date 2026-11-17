local _, ns = ...

-- Minimal dark nameplates for enemies (friendly ones stay Blizzard's): a skin on FrogLib's Plates
-- engine, which takes the plates over and keeps Blizzard's cast bar and auras, moved round ours.
-- Values the game keeps secret in combat only ever go straight to widgets. Two looks (ns.db.look):
-- ours, and "classic", Classic's own nameplate art still in the game's files (see CLASSIC below).

local Plates = {}
ns.Plates = Plates

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Borders, Color, Unit = FrogLib.Borders, FrogLib.Color, FrogLib.Unit
local Icons = FrogLib.Icons

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\FrogPlates\\Media\\"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon" -- the yellow "!"

-- The dragons (Media\Dragon*.tga, 128x128 texels, cut from the classic target frame by
-- _tools\make_dragon_art.py): the portrait's hole, which goes round the bar's end, and their reach.
local DRAGON = { size = 128, holeX = 51.5, holeY = 58.5, holeR = 27.5, right = 125 }
local DRAGON_ART = { elite = "DragonElite", worldboss = "DragonElite", rare = "DragonRare", rareelite = "DragonRareElite" }
-- Classic's nameplate art, its sizes in texels of each file. Forever's copy of the border is gold:
-- classicGrey tints it to Classic's grey stone.
local CLASSIC = {
    border = "Interface\\Tooltips\\Nameplate-Border",         -- 256 x 32; see BORDER_CUTS
    cast = "Interface\\Tooltips\\Nameplate-Border-Castbar",   -- 128 x 32, the border mirrored; see CAST_INSET_LEFT
    shield = "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
    glow = "Interface\\Tooltips\\Nameplate-Glow",             -- 128 x 32, over the opening (x 5-106, rows 20-27)
    elite = "Interface\\Tooltips\\EliteNameplateIcon",        -- 64 x 32, a C round x 8-22, rows 6-17; art 37 x 27
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

------------------------------------------------------------------------------
-- Colour: threat first (when you're on its threat list), then tapped, players' class, reaction.
------------------------------------------------------------------------------

-- After threat, FrogLib.Color's rules: tapped, players' class, then neutral (or friendly) and
-- hostile; hostile when the game won't say.
local rules = { class = true }

local function Colour(unit)
    local colors = ns.db.colors
    if ns.db.threat then
        local r, g, b = Engine.ThreatColour(unit, colors, ns.db.role)
        if r then return r, g, b end
    end
    -- The classic look: Classic's own pure red, yellow and grey.
    if Classic() then colors = CLASSIC_COLORS end
    rules.tapped, rules.hostile, rules.fallback = colors.tapped, colors.hostile, colors.hostile
    rules.neutral, rules.friendly = colors.neutral, colors.neutral
    return Color.Unit(unit, rules)
end

------------------------------------------------------------------------------
-- Our frame (plate: the engine's frame over Blizzard's plate, with plate.base and plate.slot)
------------------------------------------------------------------------------

local function Create(plate)
    local bar = CreateFrame("StatusBar", nil, plate)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    plate.bar = bar
    plate.bg = bar:CreateTexture(nil, "BACKGROUND")
    plate.bg:SetAllPoints()
    plate.bg:SetColorTexture(0.06, 0.06, 0.07, 0.85)
    -- Execute range: the fill again in the execute colour, over it (see UpdateExecute).
    plate.execute = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.execute:SetAllPoints(bar:GetStatusBarTexture())
    plate.execute:Hide()
    -- The border, in one of three styles (ns.db.borderStyle): a pixel edge, the classic stone,
    -- or our Forever frame.
    -- The pixel edge on a holder that ignores the plate's scale: it stays one screen pixel thick however the plate
    -- grows with distance or for your target, so it needn't be placed again (as EllesmereUI keeps its borders).
    local edgeHolder = CreateFrame("Frame", nil, plate)
    edgeHolder:SetIgnoreParentScale(true)
    edgeHolder:SetAllPoints(plate)
    plate.border = Borders.Edges(edgeHolder, bar, "BORDER")
    plate.stone = Borders.Stone(bar, 1)
    -- The Forever frame likewise (over the bar's fill, under the dragons and text, as on the bar).
    local frameHolder = CreateFrame("Frame", nil, bar)
    frameHolder:SetIgnoreParentScale(true)
    frameHolder:SetAllPoints(bar)
    plate.frameArt = Borders.Forever(bar, nil, nil, frameHolder)
    -- Elite and rare: a dragon round the bar's right end (and a mirrored one round its left, if
    -- set), over the borders but under the text.
    plate.dragons = CreateFrame("Frame", nil, plate)
    plate.dragons:SetAllPoints(bar)
    plate.dragons:SetFrameLevel(bar:GetFrameLevel() + 2)
    plate.dragonRight = plate.dragons:CreateTexture(nil, "ARTWORK")
    plate.dragonLeft = plate.dragons:CreateTexture(nil, "ARTWORK")
    plate.dragonLeft:SetTexCoord(1, 0, 0, 1)
    plate.dragons:Hide()
    -- The classic look: its border round the bar (in three pieces, the middle stretching), the
    -- elite dragon round the level box, and the glow over your target's bar.
    plate.classic = CreateFrame("Frame", nil, plate)
    plate.classic:SetAllPoints(bar)
    plate.classic:SetFrameLevel(bar:GetFrameLevel() + 1)
    plate.classicParts = {}
    for i = 1, 3 do
        local piece = plate.classic:CreateTexture(nil, "ARTWORK")
        piece:SetTexture(CLASSIC.border)
        plate.classicParts[i] = piece
    end
    plate.elite = plate.classic:CreateTexture(nil, "OVERLAY")
    plate.elite:SetTexture(CLASSIC.elite)
    plate.elite:SetTexCoord(0, 1, 0, 1)
    plate.elite:Hide()
    plate.classicGlow = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    plate.classicGlow:SetTexture(CLASSIC.glow)
    plate.classicGlow:SetTexCoord(5 / 128, 106 / 128, 20 / 32, 27 / 32)
    plate.classicGlow:SetBlendMode("ADD")
    plate.classicGlow:SetAllPoints(bar)
    plate.classicGlow:Hide()
    plate.classic:Hide()
    -- Your target: a second, coloured ring round the black one.
    plate.ring = CreateFrame("Frame", nil, plate)
    plate.ring:SetAllPoints(bar)
    local ringHolder = CreateFrame("Frame", nil, plate.ring)
    ringHolder:SetIgnoreParentScale(true)
    ringHolder:SetAllPoints(plate.ring)
    plate.ringBorder = Borders.Edges(ringHolder, bar, "OVERLAY")
    -- Or arrows either side ("> bar <"), gently pointing in, and a soft glow behind the bar.
    plate.glow = plate:CreateTexture(nil, "BACKGROUND", nil, -8)
    plate.glow:SetTexture(MEDIA .. "Glow.tga")
    -- Nine-sliced where the game can, so the glow keeps its width on long bars.
    if plate.glow.SetTextureSliceMargins then
        pcall(plate.glow.SetTextureSliceMargins, plate.glow, 16, 16, 16, 16)
        if Enum.UITextureSliceMode then pcall(plate.glow.SetTextureSliceMode, plate.glow, Enum.UITextureSliceMode.Stretched) end
    end
    plate.glow:SetBlendMode("ADD")
    plate.glow:Hide()
    plate.arrows = CreateFrame("Frame", nil, plate)
    plate.arrows:SetAllPoints(bar)
    plate.arrowLeft = plate.arrows:CreateTexture(nil, "OVERLAY")
    plate.arrowLeft:SetTexture(MEDIA .. "Arrow.tga")
    plate.arrowRight = plate.arrows:CreateTexture(nil, "OVERLAY")
    plate.arrowRight:SetTexture(MEDIA .. "Arrow.tga")
    plate.arrowRight:SetTexCoord(1, 0, 0, 1) -- "<"
    local bounce = plate.arrows:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local nudge = bounce:CreateAnimation("Alpha")
    nudge:SetFromAlpha(1)
    nudge:SetToAlpha(0.55)
    nudge:SetDuration(0.7)
    nudge:SetSmoothing("IN_OUT")
    plate.arrows.pulse = bounce
    plate.arrows:Hide()

    local textLayer = CreateFrame("Frame", nil, bar)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 3)
    plate.name = textLayer:CreateFontString(nil, "OVERLAY")
    plate.name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 3)
    plate.name:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 3)
    plate.name:SetJustifyH("LEFT")
    plate.name:SetWordWrap(false)
    plate.name:SetShadowOffset(1, -1)
    -- Text inside the bar: left, centre and right, each from its own template (ns.db.text).
    plate.texts = {}
    for _, slot in ipairs({ "left", "center", "right" }) do
        local text = textLayer:CreateFontString(nil, "OVERLAY")
        text:SetShadowOffset(1, -1)
        text:SetWordWrap(false)
        plate.texts[slot] = text
    end
    plate.texts.left:SetPoint("LEFT", bar, "LEFT", 3, 0)
    plate.texts.left:SetJustifyH("LEFT")
    plate.texts.center:SetPoint("CENTER", bar, "CENTER", 0, 0)
    plate.texts.right:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    plate.texts.right:SetJustifyH("RIGHT")
    plate.threat = textLayer:CreateFontString(nil, "OVERLAY")
    plate.threat:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    plate.threat:SetShadowOffset(1, -1)
    -- The raid mark: an icon written into text (see UpdateMark), since which mark it is can be
    -- secret in combat.
    plate.mark = textLayer:CreateFontString(nil, "OVERLAY")
    plate.mark:SetFont(STANDARD_TEXT_FONT, 12, "")
    plate.mark:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    plate.mark:Hide()
    -- The classic look's level, in its box (and the skull for ??).
    plate.level = textLayer:CreateFontString(nil, "OVERLAY")
    plate.level:SetShadowOffset(1, -1)
    plate.level:SetShadowColor(0, 0, 0, 1)
    plate.skull = textLayer:CreateTexture(nil, "OVERLAY")
    plate.skull:SetTexture(CLASSIC.skull)
    plate.skull:Hide()
    -- Wanted by your quests: a "!" before the name (see UpdateQuest).
    plate.quest = textLayer:CreateTexture(nil, "OVERLAY")
    plate.quest:SetTexture(QUEST_ICON)
    plate.quest:Hide()

    -- A black shadow under all the text (all there is with the outline set to "None").
    for _, text in ipairs({ plate.name, plate.threat, plate.texts.left, plate.texts.center, plate.texts.right }) do
        text:SetShadowColor(0, 0, 0, 1)
    end
end

------------------------------------------------------------------------------
-- The classic look's measurements
------------------------------------------------------------------------------

-- A classic frame in three pieces round `region`, measured in texels of its file and drawn at
-- `perTexel` units each; the middle stretches with the region, and `rightWidth` squeezes the end.
local function PlaceThree(parts, region, perTexel, cuts, opening, rows, size, rightWidth)
    local leftCut, midCut, endCut, rightCut = cuts[1], cuts[2], cuts[3], cuts[4]
    local openLeft, openRight, openTop = opening[1], opening[2], opening[3]
    local top, bottom = rows[1], rows[2]
    local fileWidth, fileHeight = size[1], size[2]
    local height = (bottom - top) * perTexel
    local topCoord, bottomCoord = top / fileHeight, bottom / fileHeight
    local left, mid, right = parts[1], parts[2], parts[3]
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", region, "TOPLEFT", -(openLeft - leftCut) * perTexel, (openTop - top) * perTexel)
    left:SetSize((midCut - leftCut) * perTexel, height)
    left:SetTexCoord(leftCut / fileWidth, midCut / fileWidth, topCoord, bottomCoord)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", region, "TOPRIGHT", (endCut - openRight) * perTexel, (openTop - top) * perTexel)
    right:SetSize((rightWidth or (rightCut - endCut)) * perTexel, height)
    right:SetTexCoord(endCut / fileWidth, rightCut / fileWidth, topCoord, bottomCoord)
    mid:ClearAllPoints()
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetTexCoord(midCut / fileWidth, endCut / fileWidth, topCoord, bottomCoord)
end

-- Classic's border (its lower half) drawn 128 x 16 round a 103.75 x 10 bar, the fill running under
-- its inner bevel as it did. Forever's level box is wider: its end is drawn squeezed to Classic's.
local BORDER_CUTS = { 0, 8, 100, 136 }    -- the left cap, the middle that stretches, the end with the box
local BORDER_OPEN = { 3.5, 107.25, 18.5 } -- the bar's left and right in the border, and its top row
local BORDER_ROWS, BORDER_SIZE = { 16, 32 }, { 256, 32 }
local BORDER_END = 28                     -- the end piece's width as drawn (Forever's 100-136 as 100-128)
local CLASSIC_BAR_WIDTH, CLASSIC_BAR_HEIGHT = 103.75, 10
-- The classic cast bar inside its border, from each edge; the border lined up under the health
-- bar's, 2 below it. The spell's icon (14) sits 11.5 in from the border's left.
local CAST_INSET_LEFT, CAST_INSET_RIGHT, CAST_INSET_TOP, CAST_INSET_BOTTOM = 20.75, 3.5, 2.5, 3.5
local CAST_BORDER_GAP = 2
local CAST_EXTRAS = Engine.CAST_EXTRAS

------------------------------------------------------------------------------
-- Casts you can't interrupt
------------------------------------------------------------------------------

-- Blizzard's cast bar knows (notInterruptible, secret for enemies in combat) and shows its shield to
-- match; the engine passes that on, and our fill and shield follow it (SetAlphaFromBoolean).
local casts = {} -- Blizzard cast bar -> our parts on it: fill, shield, the classic frame and shield

local function OurCast(cast)
    local ours = casts[cast]
    if ours then return ours end
    ours = {}
    ours.fill = cast:CreateTexture(nil, "ARTWORK", nil, 7)
    ours.fill:SetAlpha(0)
    ours.shield = cast:CreateTexture(nil, "OVERLAY", nil, 7)
    ours.shield:SetTexture(MEDIA .. "Shield.tga")
    ours.shield:SetAlpha(0)
    -- The classic look's cast bar frame, and its shielded one over it for casts you can't interrupt.
    ours.classic = cast:CreateTexture(nil, "OVERLAY", nil, 5)
    ours.classic:SetTexture(CLASSIC.cast)
    ours.classic:SetTexCoord(0, 1, 0.5, 1)
    ours.classic:SetAlpha(0)
    ours.classicShield = cast:CreateTexture(nil, "OVERLAY", nil, 6)
    ours.classicShield:SetTexture(CLASSIC.shield)
    ours.classicShield:SetAlpha(0)
    casts[cast] = ours
    return ours
end

function Plates:CastShield(cast, shown, owned)
    local ours = OurCast(cast)
    local db = ns.db
    local on = owned and db.enabled and db.castBar
    if cast.BorderShield then cast.BorderShield:SetAlpha(on and 0 or 1) end -- its art doesn't fit our bar
    AlphaFrom(ours.fill, shown, on and db.castColor)
    local classic = Classic()
    AlphaFrom(ours.shield, shown, on and db.castShield and not classic)
    ours.classic:SetAlpha((on and classic) and 1 or 0)
    AlphaFrom(ours.classicShield, shown, on and classic and db.castShield)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

-- The black edge (or the Forever frame), and your target's ring in the target colour right outside it, sized in
-- screen pixels (on holders that ignore the plate's scale, so they stay so as it grows).
function Plates:PlaceBorders(plate)
    local db = ns.db
    local style = Classic() and "none" or db.borderStyle
    Borders.Show({ edges = plate.border, stone = plate.stone, forever = plate.frameArt }, style,
        { size = 1, color = { r = 0, g = 0, b = 0 }, thickness = db.frameThickness })
    -- The target ring goes right outside whichever border it is.
    local ringOffset = (style == "classic" and 3) or (style == "forever" and 2 * (db.frameThickness or 1)) or 1
    plate.ringBorder:Place(1, ringOffset, db.colors.target)
    local color = db.colors.target
    -- Arrows: a little taller than the bar, half as wide as tall, clear of the border.
    local arrowHeight = db.height + 8
    local gap = ringOffset + 4
    for _, arrow in ipairs({ plate.arrowLeft, plate.arrowRight }) do
        arrow:SetSize(arrowHeight / 2, arrowHeight)
        arrow:SetVertexColor(color.r, color.g, color.b)
    end
    -- The glow: 10 out from the bar all round.
    plate.glow:ClearAllPoints()
    plate.glow:SetPoint("TOPLEFT", plate.bar, "TOPLEFT", -10, 10)
    plate.glow:SetPoint("BOTTOMRIGHT", plate.bar, "BOTTOMRIGHT", 10, -10)
    plate.glow:SetVertexColor(color.r, color.g, color.b, 0.55)
    -- The raid mark and threat text move out past the arrows when they show.
    plate.arrowGap = gap
    plate.arrowRoom = gap + arrowHeight / 2
    self:PlaceSides(plate)
end

-- What sits beside the bar (arrows, raid mark, threat text) keeps clear of the dragons, and the
-- raid mark and threat text of the arrows too.
function Plates:PlaceSides(plate)
    local reach = plate.hasDragon and plate.dragonReach or 0
    local right, left = reach, ns.db.dragons.both and reach or 0
    -- The classic look: clear of its level box (and the elite dragon round it).
    if Classic() then right, left = plate.classicReach or 0, 0 end
    local gap = plate.arrowGap or 5
    plate.arrowLeft:ClearAllPoints()
    plate.arrowLeft:SetPoint("RIGHT", plate.bar, "LEFT", -gap - left, 0)
    plate.arrowRight:ClearAllPoints()
    plate.arrowRight:SetPoint("LEFT", plate.bar, "RIGHT", gap + right, 0)
    local room = plate.arrows:IsShown() and (plate.arrowRoom or 0) or 0
    plate.mark:ClearAllPoints()
    plate.mark:SetPoint("RIGHT", plate.bar, "LEFT", -4 - left - room, 0)
    plate.threat:ClearAllPoints()
    plate.threat:SetPoint("LEFT", plate.bar, "RIGHT", 4 + right + room, 0)
end

-- The dragons' hole a little taller than the bar, its middle a little inside the bar's end, so the
-- head sits over the bar and the tail curls under it; in plate units, so they scale with the plate.
function Plates:PlaceDragons(plate)
    local db = ns.db
    local perTexel = (db.height + 12) / (2 * DRAGON.holeR) * (db.dragons.size or 1)
    local inset = 2 * perTexel
    local shiftX, shiftY = (DRAGON.size / 2 - DRAGON.holeX) * perTexel, (DRAGON.size / 2 - DRAGON.holeY) * perTexel
    local size = DRAGON.size * perTexel
    plate.dragonRight:ClearAllPoints()
    plate.dragonRight:SetPoint("CENTER", plate.bar, "RIGHT", shiftX - inset, -shiftY)
    plate.dragonRight:SetSize(size, size)
    plate.dragonLeft:ClearAllPoints()
    plate.dragonLeft:SetPoint("CENTER", plate.bar, "LEFT", inset - shiftX, -shiftY)
    plate.dragonLeft:SetSize(size, size)
    -- How far past the bar's end they reach.
    plate.dragonReach = (DRAGON.right - DRAGON.holeX) * perTexel - inset
end

-- The classic look as 1.x drew it: the level's middle 11.5 in from the border's right end, and the
-- elite dragon (its 64 x 32 art at 57.5 x 29) from 12.5 left of and 12 above the level.
local LEVEL_X = 128 - 11.5 - 107.25 -- past the bar's end
local BORDER_RIGHT = 128 - 107.25

function Plates:PlaceClassic(plate)
    local db = ns.db
    local on = Classic()
    plate.classic:SetShown(on)
    plate.name:SetJustifyH(on and "CENTER" or "LEFT")
    if not on then
        plate.level:Hide()
        plate.skull:Hide()
        plate.elite:Hide()
        return
    end
    local perTexel = (plate.barHeight or db.height) / CLASSIC_BAR_HEIGHT
    PlaceThree(plate.classicParts, plate.bar, perTexel, BORDER_CUTS, BORDER_OPEN, BORDER_ROWS, BORDER_SIZE, BORDER_END)
    for _, piece in ipairs(plate.classicParts) do piece:SetDesaturated(db.classicGrey and true or false) end
    local boxX, boxY = LEVEL_X * perTexel, -0.5 * perTexel
    -- The level (and the skull in its place) nudged by levelX / levelY; the dragon stays put.
    local levelX, levelY = boxX + (db.levelX or 0), boxY + (db.levelY or 0)
    plate.level:ClearAllPoints()
    plate.level:SetPoint("CENTER", plate.bar, "RIGHT", levelX, levelY)
    ns.Media:SetFont(plate.level, db.font, db.textSize, db.outline)
    plate.skull:ClearAllPoints()
    plate.skull:SetPoint("CENTER", plate.bar, "RIGHT", levelX, levelY)
    plate.skull:SetSize(12 * perTexel, 12 * perTexel)
    plate.elite:ClearAllPoints()
    plate.elite:SetPoint("TOPLEFT", plate.bar, "RIGHT", boxX - 12.5 * perTexel, boxY + 12 * perTexel)
    plate.elite:SetSize(57.5 * perTexel, 29 * perTexel)
    plate.boxReach = BORDER_RIGHT * perTexel
    plate.eliteReach = math.max(plate.boxReach, boxX - 12.5 * perTexel + 57.5 * perTexel * 37 / 64)
    plate.classicReach = plate.elite:IsShown() and plate.eliteReach or plate.boxReach
    -- Your target's glow over the bar, in the target colour.
    local color = db.colors.target
    plate.classicGlow:SetVertexColor(color.r, color.g, color.b, db.highlight.classicGlow or 0.5)
end

function Plates:Layout(plate)
    local db, unitFrame = ns.db, plate.uf
    local bar = plate.bar
    bar:ClearAllPoints()
    -- Centred on the plate (which the game keeps over the enemy), at the height of Blizzard's bar:
    -- the engine's slot is the plate's width there.
    Engine.PlaceSlot(plate)
    local slot = plate.slot
    -- The classic look at Classic's own size (classicSize): its bar, and a cast bar as wide with its
    -- frame's proportions.
    local classicSize = Classic() and db.classicSize
    local width = classicSize and CLASSIC_BAR_WIDTH or db.width
    plate.barHeight = classicSize and CLASSIC_BAR_HEIGHT or db.height
    -- Blizzard's cast bar isn't ours, so our scale (db.scale) is put on its height and gap.
    local scale = db.scale or 1
    local perTexel = plate.barHeight / CLASSIC_BAR_HEIGHT -- the classic look's units per texel
    local castHeight = (Classic() and CLASSIC_BAR_HEIGHT * perTexel or db.castHeight) * scale
    if width > 0 then
        bar:SetPoint("CENTER", slot, "CENTER")
        bar:SetWidth(width)
    else
        -- As wide as the plate.
        bar:SetPoint("LEFT", slot, "LEFT")
        bar:SetPoint("RIGHT", slot, "RIGHT")
    end
    bar:SetHeight(plate.barHeight)
    bar:SetStatusBarTexture(Texture())
    local execute = db.colors.execute
    OverFill(plate.execute, bar)
    plate.execute:SetTexture(Texture())
    plate.execute:SetVertexColor(execute.r, execute.g, execute.b)
    -- The game dims a plate whose enemy is behind terrain or far off (on the plate's base
    -- frame); without gameFade ours keeps its own opacity, like the cast bar and auras do.
    plate:SetIgnoreParentAlpha(not db.gameFade)
    Plates:PlaceDragons(plate)
    Plates:PlaceClassic(plate)
    Plates:PlaceBorders(plate)

    ns.Media:SetNameFont(plate.name, db.font, db.nameSize, db.outline) -- names in other scripts draw too
    for _, text in pairs(plate.texts) do ns.Media:SetFont(text, db.font, db.textSize, db.outline) end
    ns.Media:SetFont(plate.threat, db.font, db.textSize, db.outline)

    -- Blizzard's cast bar, under ours.
    local cast = BlizzardCast(unitFrame)
    if cast then
        cast:SetIgnoreParentAlpha(db.castBar)
        if db.castBar then
            cast:ClearAllPoints()
            if Classic() then
                -- Its border lined up under the health bar's, so the bar itself sits further right.
                local shiftX = (CAST_INSET_LEFT - BORDER_OPEN[1]) * perTexel * scale
                local below = BORDER_ROWS[2] - BORDER_OPEN[3] - CLASSIC_BAR_HEIGHT -- the health border under its bar
                local shiftY = -(below + CAST_BORDER_GAP + CAST_INSET_TOP) * perTexel * scale
                cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", shiftX, shiftY)
                cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", shiftX, shiftY)
            else
                cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -db.castGap * scale)
                cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -db.castGap * scale)
            end
            cast:SetHeight(castHeight)
        end
        -- Casts you can't interrupt: our fill in their colour, and the shield to the left of the
        -- bar, a little taller than it, in a lighter shade of that colour.
        local ours = OurCast(cast)
        local color = db.colors.uninterruptible
        OverFill(ours.fill, cast)
        ours.fill:SetTexture(Texture())
        ours.fill:SetVertexColor(color.r, color.g, color.b)
        local shieldSize = castHeight + 4
        ours.shield:ClearAllPoints()
        ours.shield:SetPoint("RIGHT", cast, "LEFT", -2, 0)
        ours.shield:SetSize(shieldSize, shieldSize)
        ours.shield:SetVertexColor(color.r + (1 - color.r) * 0.5, color.g + (1 - color.g) * 0.5, color.b + (1 - color.b) * 0.5)
        -- The classic look: its border round the cast bar, the spell's icon in its slot, Classic's
        -- small shield round casts you can't interrupt (as Blizzard's own Classic style has them).
        if Classic() then
            local scaled = perTexel * scale
            ours.classic:ClearAllPoints()
            ours.classic:SetPoint("TOPLEFT", cast, "TOPLEFT", -CAST_INSET_LEFT * scaled, CAST_INSET_TOP * scaled)
            ours.classic:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", CAST_INSET_RIGHT * scaled, -CAST_INSET_BOTTOM * scaled)
            ours.classicShield:ClearAllPoints()
            ours.classicShield:SetPoint("TOPLEFT", cast, "TOPLEFT", -20 * scaled, 11 * scaled)
            ours.classicShield:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 13 * scaled, -13 * scaled)
            if cast.Icon then
                cast.Icon:ClearAllPoints()
                cast.Icon:SetPoint("CENTER", cast, "LEFT", (11.5 - CAST_INSET_LEFT) * scaled, 0)
                cast.Icon:SetSize(14 * scaled, 14 * scaled)
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
        -- the cast's target's name there), right past it in ours (where that name stays).
        local engineParts = Engine.CastParts(cast)
        local time = engineParts.time
        if time then
            time:SetShown(db.castTime and true or false)
            -- Its own size (castTimeSize; 0: the small text's) and nudge (castTimeX, castTimeY).
            local size = (db.castTimeSize or 0) > 0 and db.castTimeSize or db.textSize
            ns.Media:SetFont(time, db.font, size, db.outline)
            time:ClearAllPoints()
            local nudgeX, nudgeY = db.castTimeX or 0, db.castTimeY or 0
            if Classic() then
                time:SetPoint("RIGHT", cast, "RIGHT", -2 + nudgeX, nudgeY)
            else
                time:SetPoint("LEFT", cast, "RIGHT", 3 + nudgeX, nudgeY)
            end
        end
        -- Blizzard's own border, the cast's target's name and its "aimed at you" outline: out of
        -- sight in the classic look (1.x had none of them).
        for _, key in ipairs(CAST_EXTRAS) do
            if cast[key] then cast[key]:SetAlpha(Classic() and 0 or 1) end
        end
        -- Put the last shield state Blizzard set back, now the plate is ours (or the settings
        -- changed). It may be secret, so it's never tested here.
        if engineParts.seen then
            self:CastShield(cast, engineParts.last, true)
        else
            self:CastShield(cast, false, true)
        end
    end
    -- Blizzard's auras (your debuffs, buffs you can steal, crowd control) over the name, in their own
    -- unscaled units; higher and centred in the classic look; crowd control right past the bar's end.
    local up = db.nameSize + 6
    if Classic() then up = up + 2.5 * plate.barHeight / CLASSIC_BAR_HEIGHT end
    local side = (plate.classicReach and Classic() and plate.classicReach or 0) * scale + 5
    Engine.PlaceAuras(unitFrame, bar, db.auras and true or false, up * scale, Classic(), side)
end

------------------------------------------------------------------------------
-- Filling it in
------------------------------------------------------------------------------

function Plates:UpdateHealth(plate)
    local unit = plate.unit
    plate.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    plate.bar:SetValue(UnitHealth(unit))
    -- Health, the name and the level may be secret: FrogLib.Unit's words only ever go to
    -- SetFormattedText.
    for slot, text in pairs(plate.texts) do
        Unit.SetText(text, ns.db.text[slot], unit)
    end
    self:UpdateExecute(plate)
end

-- The execute overlay: the engine's 1 under your execute's line, 0 above (may be secret).
function Plates:UpdateExecute(plate)
    local below = ns.db.execute and Engine.ExecuteBelow()
    if not below then
        plate.execute:Hide()
        return
    end
    plate.execute:SetAlpha(Engine.ExecuteAlpha(plate.unit, below))
    plate.execute:Show()
end

-- Elite (gold), rare (silver) or rare elite (silver, winged); world bosses get the gold one.
function Plates:UpdateDragon(plate)
    local dragons = ns.db.dragons
    local class = Safe(UnitClassification(plate.unit)) or ""
    -- The classic look: Classic's own little dragon round the level box, for elites only.
    if Classic() then
        plate.hasDragon = false
        plate.dragons:Hide()
        plate.elite:SetShown(dragons.shown and (class == "elite" or class == "rareelite" or class == "worldboss"))
        plate.classicReach = plate.elite:IsShown() and plate.eliteReach or plate.boxReach
        self:PlaceSides(plate)
        return
    end
    plate.elite:Hide()
    local art = dragons.shown and DRAGON_ART[class]
    plate.hasDragon = art and true or false
    if art then
        plate.dragonRight:SetTexture(MEDIA .. art .. ".tga")
        plate.dragonLeft:SetTexture(MEDIA .. art .. ".tga")
        plate.dragonLeft:SetShown(dragons.both)
    end
    plate.dragons:SetShown(plate.hasDragon)
    self:PlaceSides(plate)
end

-- The "!" sits right before the name, which moves along to make room for it (the engine's OnQuest
-- says if your quests still need this enemy).
function Plates:UpdateQuest(plate)
    local db = ns.db
    local shown = db.questMarker and Engine.OnQuest(plate.unit) or false
    local size = db.nameSize + 4
    plate.quest:SetSize(size, size)
    plate.quest:ClearAllPoints()
    -- The classic look: the name centred over the plate as wide as it needs (as 1.x had it), 2
    -- above the border, the "!" right before it.
    if Classic() then
        local perTexel = (plate.barHeight or db.height) / CLASSIC_BAR_HEIGHT
        plate.name:ClearAllPoints()
        plate.name:SetPoint("BOTTOM", plate.bar, "TOP", shown and math.floor(size * 0.4 + 0.5) or 0, 2.5 * perTexel + 2)
        plate.quest:SetPoint("RIGHT", plate.name, "LEFT", 2, 0)
        plate.quest:SetShown(shown)
        return
    end
    -- The "!" is the middle third or so of its square: its left edge on the bar's.
    plate.quest:SetPoint("BOTTOMLEFT", plate.bar, "TOPLEFT", -math.floor(size * 0.3 + 0.5), 1)
    plate.quest:SetShown(shown)
    plate.name:ClearAllPoints()
    plate.name:SetPoint("BOTTOMLEFT", plate.bar, "TOPLEFT", shown and math.floor(size * 0.7 + 0.5) or 0, 3)
    plate.name:SetPoint("BOTTOMRIGHT", plate.bar, "TOPRIGHT", 0, 3)
end

function Plates:UpdateName(plate)
    local unit, db = plate.unit, ns.db
    -- The name may be secret: never tested, only written.
    local name = Unit.Name(unit)
    if not issecret(name) and name == nil then name = "" end
    -- The classic look: the name alone, the level in its box (the skull for ??, nothing while the
    -- game keeps it secret).
    if Classic() then
        pcall(plate.name.SetText, plate.name, name)
        local level = Safe(UnitLevel(unit))
        local skull = level ~= nil and level <= 0
        plate.skull:SetShown(skull)
        plate.level:SetShown(level ~= nil and not skull)
        if level and level > 0 then
            local color = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level) or { r = 1, g = 1, b = 1 }
            plate.level:SetText(level)
            plate.level:SetTextColor(color.r, color.g, color.b)
        end
        return
    end
    local level = db.showLevel and Safe(UnitLevel(unit))
    if level then
        local text = level > 0 and tostring(level) or "??"
        local class = Safe(UnitClassification(unit))
        if class == "elite" or class == "rareelite" or class == "worldboss" then text = text .. "+" end
        local color = (level > 0 and GetCreatureDifficultyColor) and GetCreatureDifficultyColor(level) or { r = 1, g = 0.2, b = 0.2 }
        pcall(plate.name.SetFormattedText, plate.name, "%s %s", Color.Wrap(text, color.r, color.g, color.b), name)
    else
        pcall(plate.name.SetText, plate.name, name)
    end
end

function Plates:UpdateColour(plate)
    plate.bar:SetStatusBarColor(Colour(plate.unit))
end

function Plates:UpdateThreat(plate)
    local db = ns.db
    local shown = db.threatText and Engine.ThreatText(plate.threat, plate.unit, db.colors)
    plate.threat:SetShown(shown and true or false)
end

-- Which mark a unit has can be secret in combat, so the number is never looked at: FrogLib.Icons
-- writes it into the icon's file name inside the text; a secret "no mark" fails to format and hides.
function Plates:UpdateMark(plate)
    local shown = ns.db.raidMarks and Icons.RaidMark(plate.mark, plate.unit, ns.db.markSize) or false
    plate.mark:SetShown(shown)
end

-- One plate's look as your target or not (target: your target's plate base, or nil).
function Plates:TargetOne(plate, target)
    local isTarget = target == plate.base
    local highlight = ns.db.highlight
    -- The classic look's own target glow over the bar, for either the outline or the glow.
    local classic = Classic()
    plate.ringBorder:SetShown(isTarget and highlight.outline and not classic)
    plate.glow:SetShown(isTarget and highlight.glow and not classic)
    plate.classicGlow:SetShown(isTarget and classic and (highlight.outline or highlight.glow))
    local arrows = isTarget and highlight.arrows
    if arrows ~= plate.arrows:IsShown() then
        plate.arrows:SetShown(arrows)
        if arrows then plate.arrows.pulse:Play() else plate.arrows.pulse:Stop() end
    end
    self:PlaceSides(plate)
    plate:SetScale((isTarget and highlight.scale or 1) * (ns.db.scale or 1))
    plate:SetAlpha((target and not isTarget) and ns.db.otherAlpha or 1)
end

function Plates:UpdateTarget()
    local target = C_NamePlate.GetNamePlateForUnit("target")
    Engine.Each(function(plate) self:TargetOne(plate, target) end)
end

------------------------------------------------------------------------------
-- The skin the engine drives
------------------------------------------------------------------------------

local UPDATES = {
    all = function(plate)
        Plates:UpdateHealth(plate)
        Plates:UpdateName(plate)
        Plates:UpdateColour(plate)
        Plates:UpdateThreat(plate)
        Plates:UpdateMark(plate)
        Plates:UpdateDragon(plate)
        Plates:UpdateQuest(plate)
    end,
    health = function(plate) Plates:UpdateHealth(plate) end,
    name = function(plate) Plates:UpdateName(plate) end,
    class = function(plate)
        Plates:UpdateName(plate)
        Plates:UpdateDragon(plate)
    end,
    threat = function(plate)
        Plates:UpdateColour(plate)
        Plates:UpdateThreat(plate)
    end,
    mark = function(plate) Plates:UpdateMark(plate) end,
    quest = function(plate) Plates:UpdateQuest(plate) end,
    execute = function(plate)
        Plates:UpdateColour(plate)
        Plates:UpdateExecute(plate)
    end,
}

local skin = {
    owner = "FrogPlates",
    enabled = function() return ns.db.enabled end,
    -- (Read by EnmityList: its own threat text on plates stays off while ours shows.)
    threatText = function() return ns.db.enabled and ns.db.threatText and true or false end,
    create = Create,
    layout = function(plate) Plates:Layout(plate) end,
    update = function(plate, what)
        local Update = UPDATES[what]
        if Update then Update(plate) end
    end,
    target = function() Plates:UpdateTarget() end,
    -- A plate just come: only its own target look (your target is the same).
    targetPlate = function(plate) Plates:TargetOne(plate, C_NamePlate.GetNamePlateForUnit("target")) end,
    -- (No tick: the pixel edges and the Forever frame sit on holders that ignore the plate's scale, see Create, so nothing is placed
    -- again as the plate grows with distance.)
    castShield = function(_, cast, shown, owned) Plates:CastShield(cast, shown, owned) end,
    -- Blizzard may swap its fill texture as the cast changes state.
    castFill = function(cast) OverFill(OurCast(cast).fill, cast) end,
    -- An interrupted cast turns red, which ours mustn't cover; the next cast sets it again.
    castInterrupted = function(cast) OurCast(cast).fill:SetAlpha(0) end,
    release = function(_, cast)
        local ours = casts[cast]
        if ours then
            ours.fill:SetAlpha(0)
            ours.shield:SetAlpha(0)
            ours.classic:SetAlpha(0)
            ours.classicShield:SetAlpha(0)
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
