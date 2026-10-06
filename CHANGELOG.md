# FrogPlates

## 0.2.1

### Threat
- Where the game hides the threat numbers (in dungeons), the plate shows where you stand instead of a percent that read 100% for the tank all the time: "Tanking" when it's on you and staying, "Slipping" when someone else is about to take it, "Pulling!" when you're about to take it. Otherwise your share of what would pull it, as before; with the numbers available, your lead as before.

### Fixes
- Plates keep their name and texts where the game hides an enemy's name (some instances); before, they stopped updating.
- An enemy player whose class the game hides no longer causes an error in the plate's colour.
- Text inside the bar shows the level when the game hides it, instead of leaving it blank, and a new word, `class`.

### Under the hood
- The execute range's curve is FrogLib's now, shared with Frog Wizard's other add-ons; nothing changes in use.
- Names, levels, class colours, raid marks, the threat lead's text and the text templates are FrogLib's, shared with EnmityList and the other Frog Wizard add-ons.

## 0.2.0

- Casts you can't interrupt stand out: the cast bar turns grey (or a colour of your choice) and a small shield shows beside it. Either can be turned off. It follows Blizzard's own cast bar, so it keeps working in combat when the game hides cast details.
- Execute range: the health bar changes colour once an enemy is low enough for your execute, but only if you have one and can use it right now: a warrior's Execute in Battle or Berserker Stance, or a paladin's Hammer of Wrath, below 20% health. Works in combat too. The colour is yours to pick.
- Elites and rares get a dragon curled round the end of their bar, as on the old target frame: gold for elites and world bosses, silver for rares, silver with wings for rare elites. Its size can be set, and it can go round both ends of the bar.
- A yellow "!" before the name of enemies your quests still need; it goes once those objectives are done.
- Raid marks (skull, cross and the rest) show beside the bar again, in combat too, where the game now hides which mark it is from addons. Their size can be set.
- These settings are on a new Extras tab.

## 0.1.0

- First version: minimal dark nameplates for enemies (friendly ones stay Blizzard's). Blizzard's plate keeps working underneath, so clicking a plate targets as always.
- Coloured by threat while you're on its threat list (safe, slipping or on someone else, tanking or not), with your lead over the next highest (or how far behind you are) beside the bar; otherwise by reaction, class or tapped.
- Name with the level in its difficulty colour, and left, centre and right text in the bar from your own templates (value, max, percent, name, level).
- Blizzard's own cast bar and your debuffs, moved round the bar, with a debuff size setting and the choice of all your debuffs or only Blizzard's picks.
- Your target picked out by any mix of an outline, arrows either side (> bar <, gently pulsing) and a soft glow, in your colour, and optionally made bigger; the other plates faded; the game's own dimming of plates behind terrain or far away can be kept or turned off.
- Three borders: a crisp pixel edge, the classic stone border, or a Forever-style frame (1 to 3 pixels thick).
- Pixel-snapped so edges and text stay crisp as plates move and scale.
