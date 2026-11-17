local ADDON, ns = ...

-- FrogPlates: minimal dark enemy nameplates to go with FrogUI (see Plates.lua).

ns.defaults = {
    enabled = true,
    -- The look: "frog" (ours) or "classic" (Classic's own nameplate art and pure red, yellow and
    -- grey); classicSize: Classic's own size (a 103.75 x 10 bar); classicGrey tints its gold grey.
    look = "frog",
    classicSize = true,
    classicGrey = false,
    texture = "Interface\\AddOns\\FrogUI\\Media\\Bars\\Matte.tga", -- flat white without FrogUI
    width = 0,     -- 0: as wide as Blizzard's plate (the nameplate size setting decides)
    scale = 1,     -- the whole plate drawn bigger or smaller (0.5 to 2), its shape kept
    height = 10,
    font = "Interface\\AddOns\\FrogUI\\Fonts\\SourceSans3.ttf",
    outline = "OUTLINE",
    nameSize = 11,
    textSize = 9,
    showLevel = true,   -- level before the name, in its difficulty colour ("+" for elites)
    levelX = 0,         -- the classic look's level (and skull) in its box: nudges, right and up positive
    levelY = 0,
    -- Text inside the bar, left / centre / right. Words (FrogLib.Unit's): value, max, percent
    -- (percent.1 for a decimal), name, level, class. Empty hides it.
    text = { left = "", center = "", right = "percent" },
    castBar = true,     -- Blizzard's cast bar, under ours
    castHeight = 10,
    castGap = 3,
    castColor = true,   -- casts you can't interrupt in colors.uninterruptible
    castShield = true,  -- and a small shield to their left
    castTime = true,    -- the time left on the cast, at the cast bar's right end
    castTimeSize = 0,   -- its text size (0: the small text's)
    castTimeX = 0,      -- and nudges, right and up positive
    castTimeY = 0,
    castNameSize = 0,   -- the spell's name on the cast bar: its size (0: the small text's)
    castNameX = 0,      -- and nudges
    castNameY = 0,
    execute = true,     -- the bar in colors.execute once the enemy is in your class's execute range
    -- Dragons round the bar's right end (both: round both ends): gold for elites and world
    -- bosses, silver for rares, silver and winged for rare elites. size: 0.6 to 1.6.
    dragons = { shown = true, both = false, size = 1 },
    questMarker = true, -- a "!" before the name of enemies your quests still need
    raidMarks = true,   -- raid marks (skull, cross...) beside the bar, markSize pixels
    markSize = 18,
    auras = true,       -- Blizzard's auras (your debuffs...), above the name
    allDebuffs = true,  -- every debuff of yours, not only the ones on Blizzard's list
    -- auraScale: their size (the game's debuff scale, 0.7 to 1.4); unset leaves the game's as is.
    threat = true,      -- colour by threat while you're on its threat list
    role = "auto",      -- "auto" (a tanking stance, form or aura), "tank" or "damage"
    threatText = true,  -- your lead (or how far behind), or your threat %, beside the bar
    otherAlpha = 0.7,   -- other plates' opacity while you have a target
    -- How your target stands out, in colors.target: an outline, arrows either side ("> bar <"), a
    -- soft glow, the classic look's glow (its opacity), and its plate scaled up by `scale`.
    highlight = { outline = true, arrows = false, glow = false, scale = 1, classicGlow = 0.5 },
    borderStyle = "pixel", -- "pixel" (1px black), "classic" (the grey stone) or "forever" (our Forever frame)
    frameThickness = 1,    -- the forever frame: screen pixels per pixel of its art (1 to 3)
    gameFade = false,   -- let the game dim plates behind terrain or far away
    colors = {
        hostile = { r = 0.78, g = 0.26, b = 0.24 },
        neutral = { r = 0.88, g = 0.72, b = 0.28 },
        tapped = { r = 0.50, g = 0.50, b = 0.50 },
        safe = { r = 0.32, g = 0.66, b = 0.46 },   -- tanking: it's on you
        warn = { r = 0.95, g = 0.62, b = 0.22 },   -- it's slipping, or about to come to you
        danger = { r = 0.92, g = 0.24, b = 0.42 }, -- tanking: it's off you; otherwise: it's on you
        target = { r = 1.00, g = 1.00, b = 1.00 },
        uninterruptible = { r = 0.58, g = 0.58, b = 0.62 },
        execute = { r = 0.66, g = 0.38, b = 0.96 },
    },
}

ns.Print = FrogLib.Util.Printer("FrogPlates", "7fd15f")
-- The bar textures and fonts the settings offer, and setting a font safely (FrogLib's Media).
ns.Media = FrogLib.Media.New()

function ns.Refresh()
    ns.Plates:Refresh()
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

-- The settings controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })

local ROLES = UI.Options("auto", "Auto (tanking stance, form or aura)", "tank", "Always tanking", "damage", "Never tanking")
-- Without an outline, the text has a soft shadow.
local OUTLINES = UI.Options("", "None (soft shadow)", "SHADOW", "Drop shadow", "OUTLINE", "Outline",
    "THICKOUTLINE", "Thick outline")

-- Every page is two columns of headed groups (FrogLib's UI.Column).
local LEFT, RIGHT, COLUMN_WIDTH, INDENT = 0, 470, 430, 20

local function Help(page, place, text, height, indent)
    place(UI.Help(page, text, COLUMN_WIDTH - 10 - (indent or 0)), height, indent or 4)
end

local function Swatch(page, place, label, key, indent)
    place(UI.ColorSwatch(page, label, ns.db.colors, key), 28, indent)
end

local function BuildLook(page)
    local db = ns.db
    local place, head = UI.Column(page, LEFT, COLUMN_WIDTH)
    head("Plates")
    place(UI.Checkbox(page, "Restyle enemy nameplates", db, "enabled"), 30)
    place(UI.Dropdown(page, "Look", UI.Options("frog", "FrogPlates (dark, minimal)", "classic", "Classic (1.x nameplates)"),
        db, "look"), 30)
    place(UI.Checkbox(page, "Classic: its own size (bar 104 x 10; off: the sizes below)", db, "classicSize"), 26, INDENT)
    place(UI.Checkbox(page, "Classic: grey stone instead of gold", db, "classicGrey"), 30, INDENT)
    place(UI.Dropdown(page, "Bar texture", function() return ns.Media:List("statusbar") end, db, "texture"), 30)
    place(UI.Dropdown(page, "Border", UI.Options("pixel", "Pixel (1px black)", "classic", "Classic stone",
        "forever", "Forever"), db, "borderStyle"), 30)
    place(UI.Stepper(page, "Forever border thickness", 1, 3, 1, db, "frameThickness"), 28, INDENT)

    head("Size")
    place(UI.Stepper(page, "Width (0 = Blizzard's)", 0, 250, 5, db, "width"), 28)
    place(UI.Stepper(page, "Height", 4, 30, 1, db, "height"), 28)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, db, "scale", "%.2f"), 30)
    place(UI.Checkbox(page, "Let the game dim plates behind terrain or far away", db, "gameFade"), 30)
    Help(page, place, "Friendly nameplates stay Blizzard's. The cast bar and debuffs are Blizzard's own, "
        .. "moved round ours, so they keep working where the game hides cast and aura details.", 40)

    local right, rightHead = UI.Column(page, RIGHT, COLUMN_WIDTH)
    rightHead("Text")
    right(UI.Dropdown(page, "Font", function() return ns.Media:List("font") end, db, "font"), 30)
    right(UI.Dropdown(page, "Outline", OUTLINES, db, "outline"), 30)
    right(UI.Stepper(page, "Name size", 6, 20, 1, db, "nameSize"), 28)
    right(UI.Stepper(page, "Small text size", 6, 18, 1, db, "textSize"), 30)
    right(UI.Checkbox(page, "Level before the name (\"+\" for elites)", db, "showLevel"), 26)
    right(UI.XY(page, "Classic: level nudge", db, "level", 30), 28)

    rightHead("Text in the bar")
    for _, slot in ipairs({ { "left", "Left" }, { "center", "Centre" }, { "right", "Right" } }) do
        right(UI.TextBox(page, slot[2], db.text, slot[1]), 28)
    end
    Help(page, right, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r "
        .. "(|cffffd100percent.1|r for a decimal), |cffffd100name|r, |cffffd100level|r, |cffffd100class|r. "
        .. "For example: value / max. Leave one empty to hide it.", 40)
end

local function BuildCasts(page)
    local db = ns.db
    local place, head = UI.Column(page, LEFT, COLUMN_WIDTH)
    head("Cast bar")
    place(UI.Checkbox(page, "Cast bar under the bar", db, "castBar"), 28)
    place(UI.Stepper(page, "Height", 4, 24, 1, db, "castHeight"), 28)

    head("Spell name")
    place(UI.Stepper(page, "Size (0 = small text's)", 0, 24, 1, db, "castNameSize"), 28)
    place(UI.Pair(page, "Nudge", { "x", -60, 60, db, "castNameX" }, { "y", -30, 30, db, "castNameY" }), 28)

    head("Time left")
    place(UI.Checkbox(page, "Time left on the cast", db, "castTime"), 28)
    place(UI.Stepper(page, "Size (0 = small text's)", 0, 24, 1, db, "castTimeSize"), 28, INDENT)
    place(UI.Pair(page, "Nudge", { "x", -60, 60, db, "castTimeX" }, { "y", -30, 30, db, "castTimeY" }), 28, INDENT)

    local right, rightHead = UI.Column(page, RIGHT, COLUMN_WIDTH)
    rightHead("Casts you can't interrupt")
    right(UI.Checkbox(page, "In their own colour", db, "castColor"), 26)
    Swatch(page, right, "Colour", "uninterruptible", INDENT)
    right(UI.Checkbox(page, "A shield beside them", db, "castShield"), 26)

    rightHead("Your debuffs")
    right(UI.Checkbox(page, "Your debuffs above the name", db, "auras"), 26)
    right(UI.Checkbox(page, "All of them (off: only the ones Blizzard picks)", db, "allDebuffs"), 26, INDENT)
    right(UI.Stepper(page, "Debuff size", 0.7, 1.4, 0.1,
        function() return db.auraScale or tonumber(C_CVar.GetCVar("nameplateAuraScale")) or 1 end,
        function(value) db.auraScale = value end, "%.1f"), 28, INDENT)
end

local function BuildTarget(page)
    local db = ns.db
    local highlight = db.highlight
    local place, head = UI.Column(page, LEFT, COLUMN_WIDTH)
    head("Your target")
    place(UI.Checkbox(page, "Outline", highlight, "outline"), 26)
    place(UI.Checkbox(page, "Arrows either side  > bar <", highlight, "arrows"), 26)
    place(UI.Checkbox(page, "Glow", highlight, "glow"), 28)
    place(UI.Stepper(page, "Classic glow", 0, 1, 0.05, highlight, "classicGlow", "%.2f"), 28)
    place(UI.Stepper(page, "Size", 1, 1.5, 0.05, highlight, "scale", "%.2f"), 28)
    Swatch(page, place, "Colour", "target")
    place(UI.Stepper(page, "Others while targeting", 0.2, 1, 0.05, db, "otherAlpha", "%.2f"), 30)
    Help(page, place, "Classic glow is the Classic look's own glow over the bar, at this opacity.", 24)

    local right, rightHead = UI.Column(page, RIGHT, COLUMN_WIDTH)
    rightHead("Threat")
    right(UI.Checkbox(page, "Colour by threat while you're on its threat list", db, "threat"), 28)
    right(UI.Dropdown(page, "Are you tanking?", ROLES, db, "role"), 30)
    right(UI.Checkbox(page, "Beside the bar: your lead (or how far behind), else your %", db, "threatText"), 30)
    rightHead("Colours")
    Swatch(page, right, "Safe (on you, tanking)", "safe")
    Swatch(page, right, "Slipping / about to come", "warn")
    Swatch(page, right, "Danger", "danger")
    Swatch(page, right, "Hostile, no threat", "hostile")
    Swatch(page, right, "Neutral", "neutral")
    Swatch(page, right, "Tapped by others", "tapped")
    Help(page, right, "Tanking: safe while it's on you, the warning colour when someone's close to "
        .. "taking it, danger once it's off you. Not tanking: the warning colour when you're about to "
        .. "pull it, danger once it's on you. The lead compares you with your group and pets.", 54)
end

local function BuildExtras(page)
    local db = ns.db
    local place, head = UI.Column(page, LEFT, COLUMN_WIDTH)
    head("Execute range")
    place(UI.Checkbox(page, "Colour the bar once you can execute", db, "execute"), 26)
    Swatch(page, place, "Colour", "execute", INDENT)
    Help(page, place, "Only once you know it, and in a stance that can use it: warriors' Execute (Battle "
        .. "or Berserker Stance) and paladins' Hammer of Wrath, both below 20% health.", 40)

    head("Elites and rares")
    local dragons = db.dragons
    place(UI.Checkbox(page, "Dragons round the bar's end", dragons, "shown"), 26)
    place(UI.Checkbox(page, "Round both ends", dragons, "both"), 26, INDENT)
    place(UI.Stepper(page, "Dragon size", 0.6, 1.6, 0.1, dragons, "size", "%.1f"), 30, INDENT)
    Help(page, place, "Gold for elites (and world bosses), silver for rares, silver and winged for rare elites.", 30)

    local right, rightHead = UI.Column(page, RIGHT, COLUMN_WIDTH)
    rightHead("Quests and marks")
    right(UI.Checkbox(page, "A \"!\" before the name of enemies your quests need", db, "questMarker"), 26)
    right(UI.Checkbox(page, "Raid marks (skull, cross...) beside the bar", db, "raidMarks"), 26)
    right(UI.Stepper(page, "Raid mark size", 10, 40, 1, db, "markSize"), 28, INDENT)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("FrogPlatesConfig", "FrogPlates", 940, 560, {
            { "look", "Look", BuildLook },
            { "casts", "Casts & debuffs", BuildCasts },
            { "target", "Target & threat", BuildTarget },
            { "extras", "Extras", BuildExtras },
        }, { tabWidth = 130 })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

------------------------------------------------------------------------------
-- Loading and commands
------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON then
        FrogPlatesDB = FrogPlatesDB or {}
        -- A short-lived version set the game's own plate fading (to fade only behind things and
        -- far away); put those game settings back to the game's defaults, once.
        if FrogPlatesDB.behindAlpha ~= nil or FrogPlatesDB.farAlpha ~= nil then
            for _, name in ipairs({ "nameplateSelectedAlpha", "nameplateNotSelectedAlpha", "nameplateMaxAlpha",
                "nameplateMinAlpha", "nameplateOccludedAlphaMult" }) do
                local default = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
                if default then SetCVar(name, default) end
            end
            FrogPlatesDB.behindAlpha, FrogPlatesDB.farAlpha = nil, nil
        end
        -- 0.1 had a single "health %" switch; it's the right-hand text now.
        if FrogPlatesDB.healthText ~= nil then
            if FrogPlatesDB.healthText == false then FrogPlatesDB.text = { left = "", center = "", right = "" } end
            FrogPlatesDB.healthText = nil
        end
        FrogLib.Util.CopyDefaults(ns.defaults, FrogPlatesDB)
        ns.db = FrogPlatesDB
    elseif event == "PLAYER_LOGIN" then
        ns.Plates:Init()
    end
end)

SLASH_FROGPLATES1 = "/fp"
SLASH_FROGPLATES2 = "/frogplates"
SlashCmdList.FROGPLATES = function(input)
    if strtrim(input or ""):lower() == "threat" then
        ns.Plates:ThreatReport()
    else
        ns.ToggleConfig()
    end
end
function FrogPlates_OnCompartmentClick() ns.ToggleConfig() end

FrogLib.Options.Add("FrogPlates", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/fp", "open or close the settings" },
        { "/fp threat", "what the game shows addons of the threat on your target" } },
})
