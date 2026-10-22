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
| Jump higher | Run first: a standing jump is about 15 ft, a running jump about 30 ft |
| Long jump, backflip | Sprint forward and jump; hold back and jump |
| Grapple, mantle, cycle traversal suit | G, F, B |
| Fly (Shift boosts, E and Q climb and descend, Alt brakes) | V |
| Dive kick | X |
| Attack, alternate fire or guard, switch weapon | Click, right click, Tab (weapon tool, key 5) |
| Specials | Z, C, H: grenade, turret, overshield for a ranger; phase dash, slam, lumen lance for a synthetic |

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
- **Tab** cycles cube, slab, ramp, stair, then ready-made pieces. **[ ]** change material, **T** turns, **P** picks up the aimed block's shape and material.
- **Shift+Tab** changes style: castle, dungeon, eco city, farm, platformer.
- Hold **Shift** and click two corners to fill a box; right click two corners to clear one. **Shift+T** on two corners restyles a box; **Shift+P** copies one, then Tab to paste.
- Blocks come from your own stock (the strip at the bottom). A block needs ground or another block beside it. The city's own blocks (discovery courses) cannot be removed.
- **Structures:** after the clipboard, Tab reaches the structure designs: sentry turret, heavy turret, shield generator and missile launcher, plus any your team has saved. The hint line shows the cost: its blocks come from your stock, and its modules cost scrap and parts from your wallet (robots drop both). Click builds it, T turns it, and right click on any of its blocks takes the whole structure apart (every block back, half the scrap and parts). To make your own, copy blocks with Shift+P twice, press Shift+[ or Shift+] to choose what it does (turret, shield, drill and so on), then press P while the clipboard is selected. It is saved as a file in `saves/structures/`, which you can share. For now turrets and shields are built pieces only; their behaviour (shooting, absorbing, raids) comes in the next step.
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

## Saving

F5 quicksaves and F9 quickloads. The pause menu has SAVE and LOAD. Your ranger and kit are saved with the world, and each ranger can also be saved on its own. Saves from earlier versions load; the new face mark and eye colour default to none.

## If something looks wrong

- An upload did nothing: read the line at the bottom of the IMPORTED PARTS panel; it names the problem.
- Out of disk space: the build cache in `.zig-cache` can grow past 100 GB and is safe to delete when no build is running (delete the whole folder, not part of it).
- More help: [Building and Testing](building-and-testing.md#troubleshooting).
