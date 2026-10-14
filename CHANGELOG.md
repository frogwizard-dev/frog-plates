# FrogPlates

## 0.3.1

- Runs on FrogLib's nameplate engine now, shared with the new XIVPlates (FFXIV-style nameplates). Nothing about how FrogPlates looks or works changes. Turn one of the two off: with both on, the second leaves the plates to the first and says so.

## 0.3.0

- A nudge for the Classic look's level (and the skull in its place) in its box: "Classic: level nudge" under Text, right/left and up/down.
- Your debuffs sit over the plate (centred in the Classic look, from the bar's left end in ours), and crowd control just past its right end: Blizzard pins them to its own hidden bar and name, which put them off to one side.
- The time left on an enemy's cast or channel, on its cast bar (from the game's own timer, so it shows even when the game keeps cast times hidden in combat). On by default; "Time left on the cast" under the cast bar settings, with its own size and nudge. The spell's name on the cast bar in your font and outline, with its own size and nudge too.
- Font outline: a new "Drop shadow" choice, no outline but a soft black shadow under the text (FrogLib's).
- A dead enemy's plate goes straight away (it could stay up while the game kept the plate).
- Scale: the whole plate drawn bigger or smaller (0.5 to 2), its shape kept, Blizzard's cast bar and your debuffs with it; your target's own enlargement on top.
- A Classic look (Look, at the top of the settings): Classic's own nameplate art, still in the game's files, round the same bar. At Classic's own size and proportions (a 103.75 x 10 bar in a 128 x 16 border, or your own sizes): the old gold border with the level in its box at the end (the skull for ?? levels; grey stone if you'd rather), Classic's pure red, yellow and grey, the name centred above, Forever's own Classic cast bar frame (the health border's twin, the spell's icon in its slot at the left) lined up under the health bar as Blizzard's own Classic style lays it out, with Classic's small shield round casts you can't interrupt, the old glow over your target's bar (in your target colour, at your opacity), and Classic's little dragon curled round an elite's level. Threat colours, the execute colour, your debuffs, raid marks, the quest "!" and threat text all carry on as before.

## 0.2.2

- Settings: a dropdown shows the current choice afresh whenever its page opens, and shift-clicking + or - moves ten steps at once. The settings controls now come from FrogLib, shared with Frog Wizard's other add-ons.

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
