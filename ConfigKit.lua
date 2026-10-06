local _, ns = ...

-- The settings controls are FrogLib's (UI.lua); every change calls ns.Refresh().
ns.UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })
-- Without an outline, the text has a soft shadow.
ns.UI.OUTLINES = ns.UI.Options("", "None (soft shadow)", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline")
