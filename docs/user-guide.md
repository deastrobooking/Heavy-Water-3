# Heavy Water: Player Guide

Written for players. The in-game version is **HOW TO PLAY** (title and pause menus); the full key table is in [Project Overview](project-overview.md#controls). Keys here are the defaults; **CONTROLS** in the pause menu shows and rebinds yours.

## Start the game

From the repository root: `python3 tools/zig.py build run` (see [Building and Testing](building-and-testing.md)). Choose NEW GAME or CONTINUE on the title. The first time, you make a ranger; afterwards F4 reopens the designer.

## The goal

The Hive holds Earth. You free it one city at a time, starting with Detroit.

- **The wilds are combat.** Clear Hive nests, brood carriers and cave dungeons. Every player keeps their own loot, upgrades, gear and pets.
- **The city is exploration.** Talk to the keepers Maro, Ines and Tavi. Each gives an investigation that exposes one of the Hive's human allies.
- **Free the city:** with all three exposed and the wilds clear, the collaborators' Titan wakes on the West Windsor bridge. Defeat it and Detroit is free.
- **Ten discoveries** are hidden around the city. Most sit in a cage of gates: run the course beside it, stand on its plate, and reach the cage within 8 seconds.
- The **quest log** (pause menu) always shows the next objective.

## Move and fight

| Do this | With |
| --- | --- |
| Move, jump, sprint, dodge | W A S D, Space, Shift, Ctrl |
| Jump higher | Run first: a standing jump is about 17 ft (5 m); a jump at full sprint reaches about 54 ft (16 m) |
| Long jump, backflip | Sprint forward and jump; hold back and jump |
| Grapple, mantle, cycle traversal suit | G, F, B |
| Fly (Shift boosts, E and Q climb and descend, Alt brakes) | V |
| Dive kick | X |
| Attack, alternate fire or guard, switch weapon | Click, right click, Tab (weapon tool, key 5) |
| Specials | Z, C, H: grenade, turret, overshield for a ranger; phase dash, slam, lumen lance for a synthetic |

**Reading a fight:** an orange gem spins and grows over a Hive fighter for a moment before it swings, and over a drone or sentinel just before it fires. Raise your guard (right click with the saber) as the glow peaks: guarding cuts the damage, and a guard raised just in time parries, which staggers the attacker or sends a bolt back. Heavy fighters (bulwarks and the Titan) do not flinch when hit, so parry or dodge their swings. Your hits show floating damage numbers (gold for a kill), land with a short pause on the saber, and shake your own screen; controllers rumble. Turn shake, numbers and rumble down or off in SETTINGS.

**Sun shadows:** trees, towers and props cast crisp shadows in the sun (blue on snow), and the moon casts faint ones at night. If four-player feels slow, turn SUN SHADOWS off in SETTINGS.

Specials are unlimited; each one only has to recharge. Pets and Wildkin heroes fight beside you (pause menu, HEROES). If you are knocked out you recover at your last checkpoint, or back with the team. R returns you to the spawn, and the pause menu's WORLD MAP fast travels.

## Tools (keys 1 to 7)

1. **Hands:** talk, press buttons, carry crates; right click salvages a relic.
2. **Build:** machines and kits from the pause menu's BUILD. Click places, T turns, right click removes, P saves the aimed machine as a blueprint.
3. **Wire:** click a source, then a target; Tab picks the ports.
4. **Bridge:** click two plazas to grow a bridge; Tab picks its style.
5. **Weapon.**
6. **Terrain:** hold click to sculpt the ground under the ring. Tab cycles raise, lower, level and smooth; [ and ] resize; right click undoes; T redoes. Sculpting is refused within 60 m of a cave mouth.
7. **Blocks:** build with a 1 m block grid.

The line above your vitals always shows the held tool's controls.

## Block building

- Click places a block beside the surface you aim at; right click removes it (the block returns to you).
- **Tab** cycles cube, slab, ramp, stair, ready-made pieces, structures, then twelve **PLANTS** entries. Aim at terrain or a block and click to plant; **T** turns the plant. Each costs one nature material from your kit (leaf for grasses, bushes and trees; bloom for flowers). Right click removes a plant and refunds that material to whoever removes it. Plants are decorative and do not block movement.
- **[ ]** change block material, **T** turns blocks, **P** picks up the aimed block's shape and material.
- **Shift+Tab** changes style: castle, dungeon, eco city, farm, platformer.
- Hold **Shift** and click two corners to fill a box; right click two corners to clear one. **Shift+T** on two corners restyles a box; **Shift+P** copies one, then Tab to paste.
- Blocks come from your own stock (the strip at the bottom). A block needs ground or another block beside it. The city's own blocks (discovery courses) cannot be removed.
- **Structures:** after the clipboard, Tab reaches the structure designs: sentry turret, heavy turret, shield generator and missile launcher, plus any your team has saved. The hint line shows the cost: its blocks come from your stock, and its modules cost scrap and parts from your wallet (robots drop both). Click builds it, T turns it, and right click on any of its blocks takes the whole structure apart (every block back, half the scrap and parts). To make your own, copy blocks with Shift+P twice, press Shift+[ or Shift+] to choose what it does (turret, shield, drill and so on), then press P while the clipboard is selected. It is saved as a file in `saves/structures/`, which you can share. - **Defenses work:** the sentry turret needs no power; the heavy turret, shield generator and missile launcher draw power, so build a **solar array** (also in the list) beside them: a defense works at the fraction of its power the arrays cover. Turrets and launchers shoot Hive units that come in range with a clear line; the shield generator's dome absorbs Hive bolts until its hit points run out, then recharges after a few quiet seconds. A launcher's missiles refill slowly.
- **Raids:** while you are near an outpost a timer runs; about two and a half minutes after you arrive (then every four minutes) a raid of two to six Hive units attacks from 70 m away, with a warning ten seconds ahead. Structures have hit points: a destroyed one loses its blocks and gives back a quarter of the scrap and parts. Take a hurt one apart and rebuild it, or keep the shield up.
- **Colony:** glowing ore veins ring the spawn: iron (orange), copper (green) and, farther out, lumen crystal (violet). With the hands tool (1), click a vein for one ore; it is yours until you stand beside a **drill station** or **supply depot** and click, which adds everything you hold to the team stockpile. The structure list also has a **habitat** (six beds), **farm field** (food), **research lab** and, after research, a **launch pad**. A drill station built on a vein mines every settlement hour (one minute of play). Settlers arrive one an hour while there is food and a free bed, eat one food per four settlers an hour, leave when food runs out, and make drills and labs faster. Click beside a lab to choose the next research: plasma cutting, deep drilling, hydroponics, habitat modules, fusion cells, rocketry and orbital mining. Each costs research points and ore from the stockpile. Once researched, the **plasma cutter (8)** mines four ore a second while you hold fire, until it overheats and vents. With orbital mining, each powered launch pad runs a station in orbit that sends ore down every hour. The panel under your wallet shows settlers, food, the stockpile, the ore you hold and the research in progress. Drills, labs and pads need power from solar arrays. Only player 1 can mine, deposit or choose research so far.
- **Space battles:** TITLE or PAUSE > SOLAR SYSTEM / SPACE BATTLES opens the solar route: Luna, Mars, the Asteroid Belt and the Kuiper Belt, ten levels each of three waves. Level 5 is a battleship and level 10 a mother ship that changes pattern twice; clearing a sector's level 5 opens the next. You fly top-down: WASD moves, the mouse or right stick aims (the fighter faces its aim), Shift boosts, Alt brakes, F returns. Click or RT fires the energy machine guns until they overheat; hold right click and release for a charge blast that pierces and eats enemy shots; Z fires a tracking missile at the enemy nearest your aim; C drops a tracking energy bomb that bursts and wipes the enemy shots around it. Enemies glow before every attack and their shots are slow. Kills pay your own kit; a clear pays every player, and H starts the next level. FIGHTER DESIGNER (on the same screen) shows the six frames, what each is best at, and equips or unlocks them in order. The ASTEROID MINING RUN is shot ore rocks: the ore goes to your kit, to deposit at a colony store. Only player 1 flies in space so far.
- **Moon landing:** clear all ten Luna orbit levels to rescue the Moon and unlock LAND ON MOON / SELENE RELAY in the solar map. On the surface, hand-mine nearby colored veins, use build mode and the colony structure system to expand the habitat, and follow the cave approach to fight the Hive nest and collect its cache. The local world map gains the same Moon destination after the rescue. Mining is centered on the active landing site.
- **Platformer style:** spring launches you up, boost strip flings you the way it faces, crumble falls away after you land, hazard hurts, checkpoint is where you recover, a pressure plate opens nearby gates for 8 seconds, a mover slides and carries you.
- **Farm style:** Tab to seeds and click them onto tilled soil (one hay each). Crops grow for three minutes and turn gold when ripe. Right click the soil to harvest: a ripe crop gives four hay blocks.

## Four players

F6, or a pad's menu button, adds a player with their own screen. Each player has their own character, gear, wallet, pets and blocks; the team shares the world and the story. Anyone can use the fabricator kiosk (it spends that player's own kit) and anyone can play a teammate's saved ranger or a Wildkin hero.

| Pad | |
| --- | --- |
| A jump, B dodge, X interact, Y traversal suit | LB grapple, LT sprint |
| RT fire, RB saber or guard | D-pad specials, Options player menu |
| Build on a pad | Hold LT and press D-pad left. RT places, RB removes, D-pad up piece, left and right material, down turn, LT + right style. Hold LT while placing or removing to mark box corners |

PAUSE > FOUR PLAYER SETUP assigns pads and screen positions.

## Your ranger

Press **F4** (or CUSTOMIZE in the pause menu). The designer has five tabs:

- **BASICS:** name, class (ranger or synthetic), body model, species, presentation, height, build, skin.
- **FACE/HAIR:**
  - **Face style:** twelve faces (classic, soft, angular, heroic, alien, hero, youthful, noble, rugged, fierce, gentle, stoic), each with its own head shape, eyes, brows and expression.
  - **Face mark:** none, freckles, a scar, war paint, a beauty mark, tech seams or tear lines. War paint and tech seams use your accent colour.
  - **Eye color:** ten colours or the default (synthetics keep glowing eyes).
  - **Hair:** style, spikes, volume, length, colour and highlight streaks.
- **GEAR:** outfit colour, clothing, armor set, helmet, boots, accent, gem and cut. Armor suits are bought from Maro in the South Market.
- **ARMOR RGB:** the armor's metal, secondary and trim colours.
- **STYLE:** the render look; installed mods add more.

Rows that change the head zoom the camera to it.

### Your own character model (imported parts)

**IMPORTED PARTS** (bottom of the designer) opens the mesh tools.

1. **UPLOAD GLB** and choose a `.glb` file (up to 192 MB). A model with a humanoid skeleton is fitted to the game's skeleton. A model without one is **auto-rigged** if it stands in a T- or A-pose; a model sculpted in an action pose keeps that pose.
2. The result, good or bad, appears on the line at the bottom of the panel. A refused file says why.
3. Every upload is kept. The **MESH** row steps through them with **<** and **>**; the one shown is the one your character wears. **DELETE MESH** removes it (press twice to confirm). Up to 16 can be stored.
4. Set **BODY STYLE** to IMPORTED GLB to wear it. Each part of the model has a surface type (armor, skin, eyes, energy, neutral), a palette colour and a hide switch. VERTEX TOOLS sculpts, paints, bends and re-weights the mesh, and tears parts off.

Not yet possible: wearing the game's face, hair, helmet or armor on an imported body, and reusing torn-off parts. These are planned in [character assets](plans/character-assets.md): the game face on the face area of an imported head, and a library of parts shared by the whole team.

## The wilds' glowing plants

Patchy meadows of **living-sap plants** grow across the lowlands and wet ground: glowing grasses and reeds, lilies, starcups and poppies, lantern bushes hung with pods, crystal shrubs, sapferns, and small glowvine, crystal-leaf and sapwillow trees. They are pale by day and burn lumen-bright at night, even on snow. You can also plant them as decoration with the block tool; each player's kit pays for their own plants.

## Saving

F5 quicksaves and F9 quickloads. The pause menu has SAVE and LOAD. Your ranger and kit are saved with the world, and each ranger can also be saved on its own. Saves from earlier versions load; the new face mark and eye colour default to none.

## If something looks wrong

- An upload did nothing: read the line at the bottom of the IMPORTED PARTS panel; it names the problem.
- Out of disk space: the build cache in `.zig-cache` can grow past 100 GB and is safe to delete when no build is running (delete the whole folder, not part of it).
- More help: [Building and Testing](building-and-testing.md#troubleshooting).
