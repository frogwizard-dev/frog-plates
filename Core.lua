local ADDON, ns = ...
local UI = ns.UI

-- FrogPlates: minimal dark enemy nameplates to go with FrogUI (see Plates.lua).

ns.defaults = {
    enabled = true,
    texture = "Interface\\AddOns\\FrogUI\\Media\\Bars\\Matte.tga", -- flat white without FrogUI
    width = 0,     -- 0: as wide as Blizzard's plate (the nameplate size setting decides)
    height = 10,
    font = "Interface\\AddOns\\FrogUI\\Fonts\\SourceSans3.ttf",
    outline = "OUTLINE",
    nameSize = 11,
    textSize = 9,
    showLevel = true,   -- level before the name, in its difficulty colour ("+" for elites)
    -- Text inside the bar, left / centre / right. Words (FrogLib.Unit's): value, max, percent
    -- (percent.1 for a decimal), name, level, class. Empty hides it.
    text = { left = "", center = "", right = "percent" },
    castBar = true,     -- Blizzard's cast bar, under ours
    castHeight = 10,
    castGap = 3,
    castColor = true,   -- casts you can't interrupt in colors.uninterruptible
    castShield = true,  -- and a small shield just left of them
    execute = true,     -- the bar in colors.execute once the enemy is in your class's execute range
    -- Dragons round the bar's right end (both: round both ends): gold for elites and world
    -- bosses, silver for rares, silver and winged for rare elites. size: 0.6 to 1.6.
    dragons = { shown = true, both = false, size = 1 },
    questMarker = true, -- a "!" before the name of enemies your quests still need
    raidMarks = true,   -- raid marks (skull, cross...) beside the bar, markSize pixels
    markSize = 18,
    auras = true,       -- Blizzard's auras (your debuffs...), above the name
    allDebuffs = true,  -- every debuff of yours, not just the ones on Blizzard's list
    -- auraScale: their size (the game's debuff scale, 0.7 to 1.4); unset leaves the game's as is.
    threat = true,      -- colour by threat while you're on its threat list
    role = "auto",      -- "auto" (a tanking stance, form or aura), "tank" or "damage"
    threatText = true,  -- your lead (or how far behind), or your threat %, beside the bar
    otherAlpha = 0.7,   -- other plates' opacity while you have a target
    -- How your target stands out, in colors.target: any mix of an outline round the bar, arrows
    -- either side ("> bar <") and a soft glow, and its plate scaled up by `scale`.
    highlight = { outline = true, arrows = false, glow = false, scale = 1 },
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

local CopyDefaults = FrogLib.Util.CopyDefaults

ns.Print = FrogLib.Util.Printer("FrogPlates", "7fd15f")

function ns.Refresh()
    ns.Plates:Refresh()
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local ROLES = UI.Options("auto", "Auto (tanking stance, form or aura)", "tank", "Always tanking", "damage", "Never tanking")

local function BuildLook(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Checkbox(p, "Restyle enemy nameplates", function() return db.enabled end,
        function(v) db.enabled = v end), 30)
    place(UI.Dropdown(p, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end, function(v) db.texture = v end), 28)
    place(UI.Stepper(p, "Width (0 = Blizzard's)", 0, 250, 5, function() return db.width end,
        function(v) db.width = v end), 26)
    place(UI.Stepper(p, "Height", 4, 30, 1, function() return db.height end, function(v) db.height = v end), 30)
    place(UI.Dropdown(p, "Font", function() return ns.Media:List("font") end,
        function() return db.font end, function(v) db.font = v end), 28)
    place(UI.Dropdown(p, "Font outline", UI.OUTLINES, function() return db.outline end,
        function(v) db.outline = v end), 28)
    place(UI.Stepper(p, "Name size", 6, 20, 1, function() return db.nameSize end, function(v) db.nameSize = v end), 26)
    place(UI.Stepper(p, "Small text size", 6, 18, 1, function() return db.textSize end,
        function(v) db.textSize = v end), 30)
    place(UI.Checkbox(p, "Level before the name (\"+\" for elites)", function() return db.showLevel end,
        function(v) db.showLevel = v end), 26)
    place(UI.Label(p, "Text in the bar"), 22)
    for _, slot in ipairs({ { "left", "Left" }, { "center", "Centre" }, { "right", "Right" } }) do
        place(UI.TextBox(p, slot[2], function() return db.text[slot[1]] end,
            function(v) db.text[slot[1]] = v end), 26, 12)
    end
    place(UI.Help(p, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r "
        .. "(|cffffd100percent.1|r for a decimal), |cffffd100name|r, |cffffd100level|r, |cffffd100class|r. "
        .. "For example: value / max. Leave one empty to hide it.", 440), 36, 4)
    place(UI.Checkbox(p, "Cast bar under the bar", function() return db.castBar end,
        function(v) db.castBar = v end), 26)
    place(UI.Stepper(p, "Cast bar height", 4, 24, 1, function() return db.castHeight end,
        function(v) db.castHeight = v end), 26, 20)
    place(UI.Checkbox(p, "Your debuffs above the name", function() return db.auras end,
        function(v) db.auras = v end), 26)
    place(UI.Checkbox(p, "All of them (off: only the ones Blizzard picks)", function() return db.allDebuffs end,
        function(v) db.allDebuffs = v end), 26, 20)
    place(UI.Stepper(p, "Debuff size", 0.7, 1.4, 0.1,
        function() return db.auraScale or tonumber(C_CVar.GetCVar("nameplateAuraScale")) or 1 end,
        function(v) db.auraScale = v end, "%.1f"), 30, 20)
    place(UI.Dropdown(p, "Border", UI.Options("pixel", "Pixel (1px black)", "classic", "Classic stone",
        "forever", "Forever"), function() return db.borderStyle end, function(v) db.borderStyle = v end), 28)
    place(UI.Stepper(p, "Forever border thickness", 1, 3, 1, function() return db.frameThickness end,
        function(v) db.frameThickness = v end), 30, 20)
    place(UI.Label(p, "Your target"), 22)
    local hl = db.highlight
    place(UI.Checkbox(p, "Outline", function() return hl.outline end, function(v) hl.outline = v end), 24, 12)
    place(UI.Checkbox(p, "Arrows either side  > bar <", function() return hl.arrows end,
        function(v) hl.arrows = v end), 24, 12)
    place(UI.Checkbox(p, "Glow", function() return hl.glow end, function(v) hl.glow = v end), 26, 12)
    place(UI.Stepper(p, "Size", 1, 1.5, 0.05, function() return hl.scale end,
        function(v) hl.scale = v end, "%.2f"), 26, 12)
    place(UI.ColorSwatch(p, "Colour", function() return db.colors.target end,
        function(r, g, b) db.colors.target = { r = r, g = g, b = b } end), 26, 12)
    place(UI.Stepper(p, "Other plates while targeting", 0.2, 1, 0.05, function() return db.otherAlpha end,
        function(v) db.otherAlpha = v end, "%.2f"), 30)
    place(UI.Checkbox(p, "Let the game dim plates behind terrain or far away", function() return db.gameFade end,
        function(v) db.gameFade = v end), 30)
    place(UI.Help(p, "Friendly nameplates stay Blizzard's. The cast bar and debuffs are Blizzard's own, "
        .. "moved round ours, so they keep working where the game hides cast and aura details.", 440), 40)
end

local function BuildThreat(p)
    local db, c = ns.db, ns.db.colors
    local place = UI.Placer()
    place(UI.Checkbox(p, "Colour by threat while you're on its threat list", function() return db.threat end,
        function(v) db.threat = v end), 28)
    place(UI.Dropdown(p, "Are you tanking?", ROLES, function() return db.role end,
        function(v) db.role = v end), 30)
    local function Swatch(label, key)
        place(UI.ColorSwatch(p, label, function() return c[key] end,
            function(r, g, b) c[key] = { r = r, g = g, b = b } end), 26)
    end
    Swatch("Safe (on you, tanking)", "safe")
    Swatch("Slipping / about to come", "warn")
    Swatch("Danger", "danger")
    Swatch("Hostile, no threat", "hostile")
    Swatch("Neutral", "neutral")
    Swatch("Tapped by others", "tapped")
    place(UI.Checkbox(p, "Threat beside the bar: your lead (or how far behind), else your %",
        function() return db.threatText end, function(v) db.threatText = v end), 34)
    place(UI.Help(p, "Tanking: safe while it's on you, the warning colour when someone's close to "
        .. "taking it, danger once it's off you. Not tanking: the warning colour when you're about to "
        .. "pull it, danger once it's on you. The lead compares you with your group and pets.", 440), 54)
end

local function BuildExtras(p)
    local db, c = ns.db, ns.db.colors
    local place = UI.Placer()
    local function Swatch(label, key)
        place(UI.ColorSwatch(p, label, function() return c[key] end,
            function(r, g, b) c[key] = { r = r, g = g, b = b } end), 30, 12)
    end
    place(UI.Label(p, "Casts you can't interrupt"), 22)
    place(UI.Checkbox(p, "In their own colour", function() return db.castColor end,
        function(v) db.castColor = v end), 26, 12)
    Swatch("Colour", "uninterruptible")
    place(UI.Checkbox(p, "A shield beside them", function() return db.castShield end,
        function(v) db.castShield = v end), 34, 12)
    place(UI.Label(p, "Execute range"), 22)
    place(UI.Checkbox(p, "Colour the bar once you can execute", function() return db.execute end,
        function(v) db.execute = v end), 26, 12)
    Swatch("Colour", "execute")
    place(UI.Help(p, "Only once you know it, and in a stance that can use it: warriors' Execute (Battle "
        .. "or Berserker Stance) and paladins' Hammer of Wrath, both below 20% health.", 420), 40, 12)
    place(UI.Label(p, "Elites and rares"), 22)
    place(UI.Checkbox(p, "Dragons round the bar's end", function() return db.dragons.shown end,
        function(v) db.dragons.shown = v end), 26, 12)
    place(UI.Checkbox(p, "Round both ends", function() return db.dragons.both end,
        function(v) db.dragons.both = v end), 26, 12)
    place(UI.Stepper(p, "Dragon size", 0.6, 1.6, 0.1, function() return db.dragons.size end,
        function(v) db.dragons.size = v end, "%.1f"), 26, 12)
    place(UI.Help(p, "Gold for elites (and world bosses), silver for rares, silver and winged for rare elites.",
        420), 34, 12)
    place(UI.Label(p, "Quests"), 22)
    place(UI.Checkbox(p, "A \"!\" before the name of enemies your quests need", function() return db.questMarker end,
        function(v) db.questMarker = v end), 26, 12)
    place(UI.Checkbox(p, "Raid marks (skull, cross...) beside the bar", function() return db.raidMarks end,
        function(v) db.raidMarks = v end), 26, 12)
    place(UI.Stepper(p, "Raid mark size", 10, 40, 1, function() return db.markSize end,
        function(v) db.markSize = v end), 26, 12)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("FrogPlatesConfig", "FrogPlates", 480, 980, {
            { "look", "Look", BuildLook },
            { "threat", "Threat", BuildThreat },
            { "extras", "Extras", BuildExtras },
        })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
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
        CopyDefaults(ns.defaults, FrogPlatesDB)
        ns.db = FrogPlatesDB
    elseif event == "PLAYER_LOGIN" then
        ns.Plates:Init()
    end
end)

SLASH_FROGPLATES1 = "/fp"
SLASH_FROGPLATES2 = "/frogplates"
SlashCmdList.FROGPLATES = function(msg)
    if strtrim(msg or ""):lower() == "threat" then
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
