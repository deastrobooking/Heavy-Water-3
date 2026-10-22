## Loot table (automation plan BS2) — 2026-10-22

- **Changed:** `game/Loot.zig` is the one table of what each enemy kind drops, rolled with the world's enemy random source and paid to the killer's own wallet and kit. Robots pay more: a scout 6 to 10 scrap and 1 to 2 parts, a stinger 10 to 16 and 2 to 3, a hybrid 14 to 22 and 2 to 3, a titan 80 to 120 and 10 to 11 (these were 3, 6, 8 and 40 scrap before). Hive insects, which dropped no scrap, now drop 2 to 14 scrap and sometimes a part, plus the alloy and lumen they always dropped. The kill message now lists everything dropped. Rewards of kill-based events (captures, arena waves, the Foundry titan's case) are unchanged.
- **Checked:** a test that every kind's roll stays in its range, robots out-pay insects, only insects drop alloy and lumen, and a stinger-sized purchase of 60 scrap takes at most six kills; default and 0.17 `build check`; the full suite (614/614). The numbers are first guesses for "easy to get" and are not tuned by play. Not checked: kills in play with the new message, and the Metal smoke.

## Tool registry (automation plan BS1) — 2026-10-22

- **Changed:** `game/Tools.zig` is a table of the seven tools (hands, build, wire, bridge, weapon, terrain, blocks): name, key action, update, hint and select hook. `Build.update`, `Build.hint`, `Build.selectTool`, the number-key and pad-toggle routing in `App.zig` and `Sandbox.zig` now go through it. The build and wire updates moved into `Build.updateBuild` and `Build.updateWire` unchanged, and the weapon, build and wire HUD hints into `Build`. No behaviour was meant to change.
- **Checked:** a test that the table matches the tool enum in order with distinct key actions and number keys; default and 0.17 `build check`; the full suite (613/613); the Metal smoke (exit 0, no validation messages), whose stages drive every tool through number keys. Not checked by hand: pressing the number keys and the pad build chord in play.

## Face designs: twelve faces, eye shapes, face marks, eye colours — 2026-10-22

- **Decided:** reusable character parts will be a shared library for the team; the face swap on imported bodies covers only the face area ([character assets](plans/character-assets.md)).
- **Added:** six faces (youthful, noble, rugged, fierce, gentle, stoic) for twelve in all. Presets gained an upper-lid cut (`eye_lid`), a brow arch, one or two catch-lights and a resting-smile offset, and the original six use them. Six face marks (freckles, scar, war paint, beauty mark, tech seams, tear lines; paint takes the lumen accent) and ten eye colours are new profile fields under the designer's FACE/HAIR tab. The lid and the marks are drawn per fragment in `skin_lit.wgsl`, using the spare `w` lanes of the eye vertex data (the mark and a packed paint colour); `toon.zig` holds the same drawing as the CPU reference. The baked mouth line is darker and wider, and the GPU path now bakes the same resting smile as the CPU path. Save format 32 (fixture `save-v32.json`); older saves load with no mark and the default eyes. Mod face presets accept the new keys, within limits.
- **Checked:** tests for the lid cut, every mark drawn where it belongs and nowhere above the brows, paint colour packing, profile round trips and the eye-colour range; the creator tab layout test caught a wrong tab boundary, which was fixed. Default and 0.17 `build check`; the full suite in a worktree holding only these changes. Close-up captures of all twelve faces in both presentations and of each mark with a different eye colour, under Metal API Validation with no messages; review led to sparser freckles, a bolder mouth and a stronger scar. Mach's WGSL compiler rejected a `let` name repeated across `if` branches in one function; the shader uses distinct names.
- **Also:** the disk was full (455 MB free). Removing build-cache outputs older than six hours freed 87 GB but left manifests pointing at deleted outputs, which broke dependency steps for the other session's build check ("failed to check cache ... FileNotFound"). Removing the manifests whose output folders were gone repaired it; the main tree's `build check` passes again.
- **Not checked:** faces at play distance and in split screen, Wildkin faces with marks, the CPU-skinning fallback, and choosing the new rows by hand in the designer.

## Upload library for imported characters; auto-rig switched on — 2026-10-22

- **Reported:** an upload from the Parts panel did not appear, and a blue mecha seen earlier had gone. The blue mecha was a test file I placed and then deleted during the previous import fix. The upload itself most likely failed: of the GLBs in the owner's Downloads three have no skeleton, and the refusal went to the HUD status line, which is hidden while the designer is open.
- **Added:** `game/ImportLibrary.zig`: every upload is kept in `saves/imports/<name>/` (source GLB, component sidecar, saved edits), named after the file (the macOS picker now returns the file's name). The panel's MESH row steps through uploads (< >) and DELETE MESH removes one after a confirming second press; the next upload takes its place or the character returns to the built-in body. Import results show in the panel. The old single import moves into the library on first start. Meshes without a usable skeleton are auto-rigged (`character/AutoRig.zig`) and labelled AUTO-RIGGED.
- **Checked:** auto-rig on the owner's mecha suit model: bind pose and in-game idle both intact; on the armored warrior the source itself is sculpted crouched with a weapon, so it stays that way. A capture of character showcase 55 with two uploads placed in the library shows "MECHA-SUIT-3D-MODEL (2 OF 2)", DELETE MESH and the result line. Tests for library names and paths; default and 0.17 `build check`; the full suite passed 609/609; the Metal smoke exited 0. The test uploads were removed afterwards.
- **Not checked:** an upload through the macOS picker by hand, deleting by hand, more auto-rig models. **Proposed next:** [character assets](plans/character-assets.md) (sockets, the game face and armor on imported bodies, reusable parts).

## Discovery courses raised for the new jumps — 2026-10-22

- **Changed:** with 9.2 m running jumps the 6 m plate pillars could be skipped from the ground. Every discovery course now ends on a plate 16 m up (`Challenges.plate_height`), out of reach of a running jump even from the 5 m cage roof. Courses are spiral towers: a low first block, four steps rising 3 m around the plate column (stone, or crumbling for the stair methods); the spring course puts the spring on a 5 m pillar beside the plate column; the ferry crosses between a spiral tower and the plate column at the top. Springs launch at 20.5 m/s (about 14 m, above any jump; the course checker still counts on 11 m). Pressure plates reach gates within 20 m (was 16) so a tall plate still opens its whole cage.
- **Tests added:** a spring lifts at least 12 m and above a running jump; no plate is within a running jump of the floor or the cage roof. The existing test still lays all eight challenges on the real seed and checks each finishable.
- **Checked:** default and 0.17 `build check`; the full suite passed 604/604; the Metal smoke exited 0; a capture of showcase 100 shows a crumble-stair tower beside its cage.
- **Not checked:** climbing a tower by hand (crumble timing on the spiral, the spring onto the ledge, the ferry at 16 m), and that towers this tall read well on the plazas.

## Limitless specials, 15 ft and 30 ft jumps, a phased jump animation — 2026-10-22

- **Specials:** grenades, turrets, shields and every other special no longer draw on an energy bar; each is limited only by its own recharge, so it can be used again as often as it recharges. The old energy cost is gone from the data; a character's former energy regeneration became a recharge rate (8 is real time: Rangers 10 recharge a quarter faster, Synthetics 7 slower, Wildkin keep their hero's value). The HUD drops the energy bar and shows each power's recharge.
- **Jumps:** a standing jump peaks at 4.56 m (15 ft); any running jump at 9.24 m (30 ft). Launch is 11.8 m/s plus up to 42 percent more with ground speed, full at normal running speed. Sprint long jumps go the same height and farther.
- **Jump animation:** `Ranger.jumpPose` poses the jump from vertical speed instead of holding one frame: a drive off the ground (legs straight, toes pointed, arms swung overhead, chest lifted), a float at the top (knees tucked, arms wide, chest over the knees), and a braced reach for the landing (knees soft and forward, feet flexed, arms out in front). A running jump is a stride leap (left leg leading, right trailing, opposite arm forward) that folds into the landing reach. Landings absorb deeper. Character showcases 51 to 54 hold the four poses.
- **Tests added:** specials refuse while recharging and work again every time they recharge, with the Ranger's faster rate measured; a standing jump peaks within 0.25 m of 4.6 m and a running jump within 0.45 m of 9.1 m; the jump poses (hands above the hips on the drive, knees up at the top, feet down on the reach, the left foot well ahead in a running leap) and the phase weights summing to one.
- **Checked:** default and 0.17 `build check`; the full suite passed 602/602; the Metal smoke exited 0; side-view captures of all four phases and a three-quarter view of the reach. The reach was first too like the drive (straight legs, arms up) and was redrawn as a braced landing.
- **Consequence, not changed:** a 9 m running jump clears the discovery courses' 6 m plate pillars from the ground, so those courses can now be skipped; `Course.reachable` still uses a conservative 3 m rise. **Not checked:** jump feel and timing by hand, the animation on imported characters, a take-off crouch (a jump still leaves on the press; an anticipation crouch would delay it).

## More powerful jumps; GLB import fixes — 2026-10-22

- **Jumps:** the standing jump launches at 11 m/s instead of 9.4 (peak about 4.0 m instead of 2.9). Ground jumps gain lift with ground speed (`Player.runningJumpSpeed`, up to 18 percent more launch at full sprint), so a running jump climbs higher than a standing one and the sprint long jump peaks at about 5.5 m instead of about 3.7. Wall jumps scale with the new base. A first try at 7.8 m for the sprint jump (the running bonus stacked on a raised long-jump multiplier) was cut back, since it cleared most walls and course steps. The jump poses are unchanged; with the longer airtime they hold longer. Discovery courses stay finishable: `Course.reachable` still assumes a 3 m rise, below the new heights.
- **GLB import:** reported as "not importing the new mesh". The import path itself worked for rigged files (checked by placing a rigged GLB where a finished import saves it and seeing it drive the character), but of the eleven GLBs in the owner's Downloads, two (76 MB) were over the picker's 64 MB read limit and three have no skeleton, and the error shown was the raw `CharacterNeedsSkin`. The limit is now 192 MB, and import errors read in words (no skeleton: rig it as a humanoid and export a GLB; bones without humanoid names; over a million vertices; unsupported extension, morph targets, version). An automatic rig for bone-less meshes (`character/AutoRig.zig`, fitted joints and nearest-bone weights, with tests) was written but is not wired in: its first capture crumpled a T-posed model, so it needs work before players see it.
- **Tests added:** a running jump peaks at least 0.6 m higher than a standing one and a standing jump above 3.4 m; the auto-rig fits A- and T-poses and refuses flat meshes.
- **Checked:** default and 0.17 `build check`; the full suite passed 601/601; the Metal smoke exited 0. **Not checked:** jump feel by hand, how the longer airtime reads in the jump animation, and a fresh import through the picker by hand.

## Guest fabricator; review and commit of the shared tree — 2026-10-22

- **Added (another session's work, reviewed and completed here):** players 2 to 4 can use the fabricator kiosk. Aiming at it and pressing interact opens a compact panel in that player's own view (`Screens.drawGuestFabricator`); the D-pad chooses tab and recipe, X builds, B closes, and the body stands still while it is open. `Sandbox.fabricateFor(owner, recipe)` now serves P1 and guests alike: it charges the builder's own `Kit`, dresses the builder (suits, armor) and readies the weapon in the builder's own arsenal; vehicles and the Kestrel still go to the shared garage and hangar, and Kestrel upgrades stay shared progress. A Sandbox test covers a guest building an energy bow from their own kit while P1's kit and movement stay independent; the layout test draws the panel in four-way split screen at 1280x720 and 640x480. Several `switch` lines in `Screens.zig` were reformatted by `zig fmt`.
- **Fixed:** the smoke's P2 fabricator stage failed in most runs. Its scripted presses went through the gamepad command buffer, and a guest without a connected pad has its press cleared every frame before the fixed step, so the press was lost whenever no step ran in that frame. The stage now sets the press and steps the sandbox at once, as the other smoke stages drive P1; two full runs passed.
- **Checked (whole tree, all of today's work together):** default and 0.17 `build check`; 0.17 compile checks for Linux (Vulkan) and Windows (D3D12) with no errors; the full suite passed 598/598; three full Metal smoke runs under `MTL_DEBUG_LAYER=1` exited 0 with no SMOKE failures; the ReleaseFast install build. **Not checked:** a real second controller at the kiosk, hands-on panel reading in a small split view, running on Linux or Windows (compile only).

## Menus pass and HOW TO PLAY — 2026-10-22

- **Added:** a HOW TO PLAY screen on the title and pause menus (`ui/Guide.zig`): six pages covering the goal (wilds, the three investigations, the Titan, the caged discoveries), moving and fighting, the tools (1 to 6), block building, platformer blocks and farming, and four players including building on a pad. Keys are the defaults, as the screen says. The keyboard Controls screen gains a block-building line; the gamepad screen gains a building line. Showcases 101 (the guide) and 102 (keyboard controls) frame them.
- **Fixed:** on the keyboard Controls screen the last key row (CAPTURE PREFAB) overlapped the hint line once the terrain and block tools added two rows; the panel now sizes to its rows. On the gamepad screen the subtitle ran into the CONTROLLER MAPPING title; it now sits below the presets.
- **Tests added:** HOW TO PLAY opens from title and pause, turns pages, wraps to BACK and returns to its menu row; every guide line fits the panel; every guide page is drawn inside the window by the layout test. Two menu tests that hard-coded item positions now look items up by label.
- **Checked:** default and 0.17 `build check`; the full suite passed 598/598; captures under `MTL_DEBUG_LAYER=1` of the guide (blocks page), keyboard and gamepad controls, the pause menu (15 items, fits at 1280x800) and the title menu.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 597/597 tests and the full Metal smoke exit 0, including its GUI stage.
- **Noted, not changed:** the pause menu opens with BUILD selected, so Enter builds rather than resumes; the controls list follows the order actions were added, so the tool keys are split across the list. The other guide pages were drawn by the layout test but only the blocks page was captured. Smaller windows than 1280x800 were not captured.

## Foundry Ledger gaps closed: solid gate, saved fight progress, civilian evacuation (C3) — 2026-10-22

- **Added:** the Foundry yard gate is a static collider from Maro's case until the steward is exposed (`FoundryCase.gateBox` matches the drawn uprights, panel and beam; too tall to jump, a flier can pass above). Each dock fighter sets `foundry_steward_down`, `foundry_trooper_down` or `foundry_skirmisher_down` when defeated; a load brings back only the fighters still standing (health and positions are still not saved), and if all were down the fight completes on the next step. `Frontier.cityDanger` names the active city fight (the dock ambush or the Titan); `Life` pedestrians within 45 m turn back if their walkway leads toward it, hurry (input 0.85 instead of 0.3), prefer roads leading away, and stop fleeing when it ends.
- **Bug found by a test:** the first flee rule compared the two plazas' distances to the fight, which keeps a walker heading into a fight just past its start plaza; it now compares the walking direction with the direction of the fight.
- **Tests added:** a Sandbox test that the gate blocks a ray while shut and not after exposure, a mid-fight load with the trooper down brings back only the steward and the skirmisher, all-down completes the fight, and `cityDanger` follows the fight; a pedestrian test where a walker ten metres from a fight turns back and gains distance and nobody keeps fleeing after it ends.
- **Checked:** default and 0.17 `build check`; the full suite passed 596/596 before the last test tweak (the gate test then passed alone); the Metal smoke's Foundry stage now checks the gate is solid, saves and loads after the first takedown (two fighters return), finishes the fight and checks the gate opened. The run's only failures are the other session's intermittent P2 fabricator checks.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 595/595 tests and the full Metal smoke exit 0.
- **Not checked:** hands-on fighting at the gate, whether civilians fleeing reads well on screen, flee behaviour around the Titan in play (covered only through `cityDanger`), and cross-compiles.

## Detroit approved; discovery approach challenges (C0, C2) — 2026-10-22

- **Owner decision:** Detroit's content approved as it stands; `CityContent.detroit.draft` is false and the quest screen drops "(DRAFT CONTENT)".
- **Added:** `game/Challenges.zig` gives eight of the ten keepsakes an approach challenge built from city blocks (`Blocks.authored`): a gate cage around the keepsake and a course matched to the discovery's method (rising pillars, crumbling stair, spring to a ledge, mover ferry) ending on a plate that opens the cage. Taking a keepsake now needs a clear line of sight (`Frontier.pick` checks physics), so a closed cage hides it. Pressure plates now open only the gates within 16 m and hold them 8 s. Courses and cages avoid plaza hubs, bridge lines and decks, and Arbor spurs; four keepsakes move to the nearest open spot on their floor. Showcase 100 frames a challenge.
- **Bugs found:** (1) the loading-deck keepsake floated 50 m up, 5 m past its plaza's edge (placed at 25 m on a 20 m deck); moved to 18.5 m. (2) A chunk whose blocks were all hidden (an open cage) failed to build its collider (`InvalidMesh`); it now has none. (3) Re-laying challenges on a load saw the old cages' colliders and shifted every cage; colliders are now cleared first and the anchors recomputed. (4) Rebuilding block colliders during a load could fail after the session had changed (out of memory in the allocation-failure test); block rebuilds are now non-fatal on load and retried each step.
- **Tests added:** method-to-course mapping, every course's plate reaches every cage gate even when pushed out, a Sandbox test that all eight challenges are laid on the real seed and finishable, a cage hides its keepsake until its plate is pressed, the tools cannot clear city blocks, the save holds no city blocks and a load lays the same challenges, and a hidden-only chunk keeps its slot without a collider. Six existing tests (walking the district loop and the Arbor spurs, driving the rover loop, city traffic, rover placement on a plaza, and the platformer test) caught the first version blocking routes; all pass now.
- **Checked:** default and 0.17 `build check`; the full suite passed 594/594; the Metal smoke's discovery stage passes (it now opens the cages first and stands inside them); a capture of showcase 100 shows the spring-ledge challenge on its plaza (cage, 9 m plate pillar, spring and start stone beside the market). The run's only failures are the other session's intermittent P2 fabricator checks.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 593/593 tests and the full Metal smoke exit 0.
- **Not checked:** running a course by hand (timing the 8 s from plate to cage, spring height onto the ledge, the ferry), the look of the cages (plain dark gate blocks), whether moved keepsakes still read as their landmark (the station keepsake is no longer at the plaza centre), cross-compiles. **Known gap:** a bridge a player adds later is not checked against existing challenges.

## Building polish and measurements (BT7) — 2026-10-21

- **Added:** per-player building tips (`game/BuildTips.zig`): selecting blocks (P1) or starting to build from a pad (any player) shows the current tip; each tip advances only when the player does what it taught (place, box fill, change style, lay a prefab). A smoke stage measures block meshing and a terrain dab. The block-building plan gains the measurements and a ten-point hands-on checklist.
- **Bug found by a test:** advancing a finished player's tips overflowed the step enum (a panic); it is guarded and the test covers it.
- **Measured** (ReleaseSafe, Metal debug layer, smoke run): 3,584 blocks in one chunk mesh and collide in 26 ms (5,552 triangles, 542 KiB); one edit re-meshes that chunk in 17.5 ms (about one frame at 60 Hz); a radius-24 terrain dab costs 0.02 ms of CPU. GPU upload and frame time while editing were not measured.
- **Checked:** default and 0.17 `build check`; the full suite passed 590/590; the Metal smoke ran the new stages; its only failure is the other session's intermittent `SMOKE P2 FABRICATION DID NOT USE THEIR KIT`.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 589/589 tests and the full Metal smoke exit 0; the benchmark repeated at 27.5 ms, 17.4 ms and 0.03 ms.
- **Not checked:** the hands-on checklist itself, which needs a person.

## Farming (BT6, part) — 2026-10-21

- **Added:** crops (`game/Farm.zig`). In the farm style the block tool offers SEEDS; a seed on tilled soil costs one hay, grows through three stages over 180 s, and a ripe harvest gives the harvester four hay blocks (their own kit), so farming funds building. Crops are shared, saved (format 30, fixture checked in), refuse building on their cell, and die when their soil is dug out. Drawn with the scatter plant mesh, scaled by growth and gold when ripe.
- **Tests added:** growth stages; a Sandbox test that plants through the block tool aimed at soil, charges the seed, refuses building on the crop, grows it, has P2 harvest it for P2's hay while the soil stays, restores the saved crop, kills it when the soil goes and refuses seeds off soil.
- **Checked:** default and 0.17 `build check`; the full suite passed 588/588; the Metal smoke exited 0 with a farm stage (five seeds planted, four left at different stages, a ripe one harvested into P1's kit); a capture showed the crops too small to read, they were scaled up 2.4 times and a second capture shows sprouts growing along the soil row.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 587/587 tests and the full Metal smoke exit 0.
- **Deferred:** dungeon spawner and treasure chest (to the generated dungeon work), a swinging drawbridge, and strategy hooks; crops ignore seasons, weather and water. **Not checked:** hands-on farming, cross-compiles.

## Platformer blocks (BT5) — 2026-10-21

- **Added:** a PLATFORMER style whose eight materials are mechanisms (`game/Platformer.zig`): springs launch at 15 m/s, boost strips fling along their facing, crumbling blocks drop 0.6 s after a landing and return 4 s later, hazards deal 20 damage every 0.6 s, checkpoints set a per-player recovery point (also used when the wilds knock a player out), pressure plates hold every gate open, movers are kinematic bodies sliding 4 m and back. Hidden cells (crumbled, open gates, movers) are left out of the mesh and collider through `Mesher.Hide`. `build/Course.zig` checks a course can be finished. Starter pieces: jump course, gate room, mover bridge.
- **Tests added:** kinds follow the style roles; the jump course is reachable and is not once its spring is replaced; a gap wider than a jump cuts a course and a stepping stone joins it; a Sandbox test where a spring launches, a crumble loses and regains its collider, a checkpoint is set, a hazard hurts and a knockout recovers at the checkpoint healed, a plate removes and restores the gate's collider, and a mover's body slides under physics.
- **Checked:** default and 0.17 `build check`; the full suite passed 586/586; the Metal smoke exited 0, now laying the jump course too and checking it is reachable in the world grid; a capture at frame 140 shows the course among the other starters.
- **Committed tree alone** (clean checkout without the other session's uncommitted work): 585/585 tests and the full Metal smoke exit 0.
- **Not checked:** jumping the course by hand (spring height, boost feel and riding a mover are tested headlessly, not played), crumble and gate timing in play, cross-compiles. **Known gaps:** no key doors or wiring to the machine signal bus yet; crumble, gate and checkpoint state are not saved.

## Block styles and prefabs (BT4) — 2026-10-21

- **Added:** dungeon, eco city and farm styles beside castle: 32 materials in four styles of eight shared roles, so `restyleBox` re-skins a box role for role and swaps the blocks through the builder's kit. Ten starter prefabs (castle tower, wall run, gatehouse; dungeon cell, corridor; eco greenhouse, walkway; farm barn, fence, planter) built at compile time in `build/Prefabs.zig`; `BlockTool.stamp` lays one whole, centred and turned, after checking every cell, support and cost. Copy a box (up to 512 blocks) to a per-player clipboard and paste it. Shift+Tab (LT + right on a pad) changes style. Starter stock is now 256 per material so any starter prefab is affordable; a save that predates a material gives that material the starter stock.
- **Tests added:** style roles and restyle mapping, every starter fits its size, uses its own style and repeats no cell, starter stock pays for any one starter, four quarter turns are the identity, a Sandbox test that lays a turned tower cell for cell and charges exactly its cost, refuses a second tower in the same place, restyles it as a farm with the kit swap, and has P2 copy and paste it from P2's own kit; the Kit and pad-chord tests were extended.
- **Checked:** default and 0.17 `build check`; the full suite passed 582/582; the Metal smoke exited 0 with a new stage that lays one starter of each style and restyles the barn; a capture at frame 140 shows the tower, cell, greenhouse and the restyled barn with its ramp roof in all four views.
- **Committed tree alone** (a clean checkout without the other session's uncommitted fabricator work): 581/581 tests and the full Metal smoke exit 0, including the P2 building stage that BT3 had left out of the stage list by mistake.
- **Not checked:** hands-on use, a real pad, cross-compiles. **Known gaps:** the clipboard is session-only; prefabs carry no mechanisms yet.

## Four-player building (BT3) — 2026-10-21

- **Added:** every player builds blocks. `BlockTool.step` works for any player slot and spends from that player's `Kit.blocks` (64 per material to start; save format 29 stores the stock by material id, older kits get the starter stock). Removing refunds the remover. Pick (P, or LT + D-pad up) copies the aimed block. Shift-click (LT on a pad) marks two corners to fill or clear a box of up to 512 cells; a fill is checked in full (cost, players, bodies, support) before any cell changes. Guests toggle building with LT + D-pad left; P1 can do the same on a pad. `ui/BlockPalette.zig` draws a material strip with the builder's own counts in each building player's view.
- **Tests added:** the pad chord and one-click-per-press triggers (`BlockTool.fromPad`), box size, Kit block stock round trip with unknown and duplicate material refusal, a Sandbox test where P1 and P2 build from separate kits, a fill P2 cannot pay for changes nothing, and P1 clearing P2's box refunds P1, with the stock surviving a save, and the palette's canvas budget for four builders.
- **Checked:** default and 0.17 `build check`; the full suite passed 577/577 before the pad mapping moved into `BlockTool` (its test then passed alone); the Metal smoke ran the new stage (P2 fills six sandstone blocks from P2's kit while P1's stock is unchanged) without failure; a capture shows P2's palette with P2's counts (sandstone 58 after the fill). The palette sat over the powers panel in that capture and was moved up; the moved position was not captured again.
- **Smoke status:** the run exits non-zero on the other session's uncommitted P2 fabricator checks (`SMOKE P2 DID NOT OPEN FABRICATOR`, `SMOKE P2 FABRICATION DID NOT USE THEIR KIT`). They fail intermittently: they passed in the BT2 run, and failed in a BT3 run with my guest-building smoke removed, and one BT3 capture shows the fabricator open. I could not isolate them further.
- **Not checked:** a real pad (the chord is covered by a unit test and the smoke sets building directly, because a scripted held button does not survive the next pad poll), hands-on play, cross-compiles. **Known gaps:** blocks cannot be earned yet beyond the starter stock and refunds; guests cannot sculpt terrain; no undo key.

## Castle block grid (BT2) — 2026-10-21

- **Added:** the block tool (key 7). Click places a cube, slab, ramp or stair in the 1 m grid beside the aimed surface; right click removes; Tab, [ ] and T pick shape, material and turn. New modules: `build/Blocks.zig` (sparse sections and save codec), `build/Materials.zig` (castle style, stable material ids), `build/Mesher.zig` (face-culled flat-shaded mesh, stairs collide as a ramp), `build/BlockWorld.zig` (per-chunk mesh and collider), `game/BlockTool.zig`. `App.publishBlocks` installs chunk meshes in the catalog. Save format 28 stores block sections, with a fixture.
- **Bug found by a test:** quarter turns first wrote `q = .{ q[2], q[1], -q[0] }`, which reads fields it has already overwritten (a Zig result-location alias), so turned ramps had collapsed normals. The outward-facing test caught it; turns now copy first.
- **Tests added:** sections in negative space and pool return, pool-full refusal, chunk-edge dirtying, section text round trip and bad text, material table, face culling between cubes and against a slab, every triangle faces outward for all shapes and turns, collider ray heights including the stair ramp and freeing an emptied chunk, and a Sandbox test that places with the tool, checks solidity, saves, clears, restores and refuses a save with an unknown material.
- **Checked:** default and 0.17 `build check`; the full suite passed 573/573; the Metal smoke under `MTL_DEBUG_LAYER=1` exited 0 with the new stage (a crenellated wall, stair, ramp and slab, solid, saved and restored) and the check that a block mesh reached the renderer; a capture at frame 140 shows the wall drawn and lit in all four split-screen views.
- **Not checked:** hands-on placement and walking up stairs in play, cross-compiles, cost of remeshing a large castle (meshing runs on the main thread at each edit). **Known gaps:** player 1 only, blocks cost nothing, at most 16 chunk columns hold blocks, no undo key, no prefabs or other styles yet.

## Terrain sculpting (BT1) — 2026-10-21

- **Added:** the terrain tool (key 6). Hold left click to raise, lower, level or smooth the ground under the crosshair; Tab picks the brush, [ and ] resize it, right click undoes a stroke, T redoes it. `world/TerrainEdit.zig` holds the edits, `procedural/TerrainBrush.zig` the brushes, `game/TerrainTool.zig` the tool and its ring cursor. `CityHeightmaps.heightAt` now adds the edit to `generatedHeight`. `Streamer.invalidate` rebuilds the touched chunks in every split-screen view, and a chunk keeps its old GPU copy until the new one is ready. Save format 27 stores the tiles, with a checked-in fixture.
- **Tests added:** lattice ownership and bilinear reads, pool-full refusal, undo and redo, clamping and dirty chunks, tile text round trip and bad text, raise and undo through `Terrain.surface`, level and smooth, refused dab changes nothing, seamless chunks with `Terrain.surface` still matching the mesh, `Streamer.invalidate`, and a Sandbox test that sculpts with the tool, saves, clears, restores and refuses a damaged save.
- **Checked:** default `build check`; the full suite passed 563/563; the Metal smoke under `MTL_DEBUG_LAYER=1` ran the new sculpt stage (raise 6 m, undo, redo, save, clear, restore) and the check that the renderer received the rebuild request, both without failure.
- **Smoke status:** the run still exits non-zero because of two checks in another session's uncommitted P2 fabricator stage (`SMOKE P2 DID NOT OPEN FABRICATOR`, `SMOKE P2 FABRICATION DID NOT USE THEIR KIT`). I did not confirm those fail without my change.
- **Not checked:** any capture or hands-on sculpting (the chunk swap and the ring cursor are unseen), the 0.17 channel, Linux and Windows cross-compiles, benchmarks of rebuild cost, the ReleaseFast reinstall. **Known gaps:** only player 1 can sculpt; no claims (the only restriction is 60 m around cave mouths); machines and crates do not follow raised ground; ramp and pit brushes are not built; a second `Sandbox` alive at once shares the one published overlay.

## Block-building plan, BT0 terrain cleanup — 2026-10-21

- Planned the block-building and terrain-sculpting track ([block building](plans/block-building.md)). Moved `Biome.coverAt` and the flora review position from `Noise.height` to `CityHeightmaps.heightAt`, so they agree with the raster terrain the chunk mesh uses; registered `CityHeightmaps.zig` in `src/tests.zig` and added two tests. Corrected stale facts in [settlement and building](plans/settlement-building.md).
- **Checked:** `build check` and the three new tests passed. **Not checked:** the other-session edits in the tree, 0.17 channel, smoke, captures. No gameplay changed; nothing of the block grid or sculpting exists yet.

## Immediate 3D helpers on Mach — 2026-10-16

- Added `engine/Scene3D.zig`, an allocation-free per-frame builder over caller-owned `World.Prop` storage. It validates catalog mesh and LOD handles/readiness, transform/tint values, and capacity before append; box and sphere helpers use the existing catalog primitives. `Sandbox.publishProps` routes the district, raceway, and NYC landmarks through it. Showcase 78 demonstrates box, sphere, crate, and hover-car model submission with LOD.
- **Checked:** default `python3 tools/zig.py build check` passed; Zig 0.17 `build check` passed; the default headless suite passed **467/467**; `git diff --check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=78 -Dcapture-frame=120` completed on Apple M3 Pro / Metal, with assets ready at 995 ms and a 2560×1600 frame captured to `zig-out/capture.bmp`. The capture was visually inspected; all four helper examples rendered. No Metal API validation messages appeared.

## Scene inspection helpers — 2026-10-16

- Added `Scene3D.screenRay` to map normalized screen points to the game's +Z-forward camera ray, and `Scene3D.pick` to find the nearest ready catalog prop using conservative model bounds spheres. Invalid camera inputs and rays are rejected; unloaded/stale props are skipped. This supports editor selection only; gameplay still uses physics raycasts.
- **Checked:** default `python3 tools/zig.py build check` passed; Zig 0.17 `build check` passed; default headless suite passed **468/468**; `git diff --check` passed. No renderer or Metal code changed, so the Metal smoke/capture was not rerun.
- **Not checked:** Zig 0.17 headless suite, Linux/Windows cross-compiles or runtime, and high-volume frame-submission performance. No new backend or asset format was introduced.

## New York City Hudson Reach travel slice — 2026-10-16

- Added a seventh world-map destination, `NEW YORK CITY`, east of Detroit. It uses independently seeded streamed terrain and vegetation, safe terrain-based arrival, a destination-specific map view, and five simple skyline landmarks around the landing area. `Worlds.zig` now lists Hudson Reach as an eighth Arbor Frontier city region. Detroit generation and existing save fields are unchanged.
- **Checked:** default `python3 tools/zig.py build check` passed; Zig 0.17 `build check` passed; the headless suite passed 461/461, including deterministic regional terrain, the landmark catalog, safe landing, and solo-player fast travel; `git diff --check` passed.
- **Not checked:** Metal visual smoke/capture and in-game hands-on travel. NYC's full district, missions, boss, ten discoveries, shops, interiors, and liberation persistence are not implemented; this is the playable arrival/exploration foothold only.

# Local validation

Host: Apple M3 Pro, macOS 26.5.1, Metal. Compiler and Mach revision are pinned in `build.zig.zon`.

## Ten-move beam-saber chain — 2026-10-19

- Expanded the saber's queued ground combo from three cuts to ten named moves: Crosscut, Return Slash, Rising Phoenix, Falling Star, Phantom Step, Skywheel Flip, Twin Vortex, Comet Thrust, Meteor Break and Nova Arc. Each maps to a separate blade path, the flip/spin attacks add full-body poses, the finisher launches a small crescent wave, and the current move name appears in the weapon HUD. Dash, aerial and charged attacks remain separate inputs.
- **Checked:** default and Zig 0.17 `python3 tools/zig.py build check` passed; `git diff --check` passed.
- **Not checked:** headless tests, gamepad/keyboard chaining, hit registration and movement through all ten poses in game, Metal smoke/capture, and tuning against enemy health. The finisher and new body rotations need visual review.

## Shared travel destination table — 2026-10-19

- Consolidated the duplicated travel labels and destination-index checks into `Sandbox.travel_destinations`. The world map builds its rows from this table; map titles and travel dispatch use the same destination record. Metro row labels are derived from `Metro.stop_names`; playable regional rows, labels, titles and arrivals are generated from `Worlds.cities` region records. Detroit preserves the existing world seed while NYC uses its regional salt. The gameplay smoke retains readable labels through a derived `travel_labels` view.
- **Checked:** default and Zig 0.17 `python3 tools/zig.py build check` passed; `git diff --check` passed.
- **Not checked:** headless tests, smoke stage, and hands-on travel. Regional entries now come from playable city records; each regional destination in smoke also gets an arrival-to-ground check. Detroit shrine and Metro destination definitions remain in the shared Sandbox travel table, so G1 is not complete.




## Mountain cave dressing — 2026-10-16

The cave systems keep their signed-distance rock, collision and encounters unchanged and gain visual-only ancient-lab dressing, drawn in `Frontier` with the cave's other props: an ancient **gate** over every cave mouth (leaning pylons with glowing seams, a lintel with a lens and gimbal rings, flanking stelae and resonator coils, circuit lines leading in; visible from 320 m and tilted slightly into the slope), a carved **doorway** where each tunnel opens into a chamber (placed from the room's ellipse and the tunnel's floor slope), and a **collapsed lab** (broken columns, a bench with a lit screen, a floor disc with a hovering ring, a conduit) twice in every hall. Three new meshes (`cave_gate`, `cave_arch`, `cave_ruin`) are in the catalog and unit-tested for finite, lit, grounded geometry. Evidence: captures of showcase 42 (the mouth) and 43 (inside the first chamber looking at the next doorway) under `MTL_DEBUG_LAYER=1`. **Not verified:** the heart and cache rooms after the change, doorway fit in every cave of every seed (the rock wall is noisy, so posts can sink into it), a full lean-free gate on gentle mouths, and draw cost. The cave rock is still smooth, interior lighting and reverb are still open (see the roadmap), and no new dungeon layouts or puzzles were added.

The same day the cave rock colours were rebuilt (`Caves.rockColor`, baked into the mesh at build time, no renderer change): layered warm strata over slate, pale dust on floors, darker crevices from a three-sample occlusion probe along the surface normal, and thin glowing mineral veins in each cave's own hue (`Caves.veinHue`, now also the crystals' hue so a cave reads as one place). A new test checks that colours are finite and bounded, that veins exist but are a minority, that floors are lighter than walls, and that tone varies widely. Evidence: captures of showcases 43 and 44; the change is visible as dustier floors, darker corners and cyan veins, but modest, because the sun still shades cave walls and the walls remain smooth. **Not verified:** the other five caves' hues in a capture, mesh build time (the occlusion probe adds three field evaluations per vertex).

Underground lighting followed: each view carries an `underground` blend (0 in the open, 1 deep in a cave, eased in over about half a second from how far the camera is below the ground inside cave air). In a cave the key light drops to about a fifth, the ambient and fog take a dim cool tone plus the cave's own hue (`Renderer.caveAmbient`), and lumen glows as at night. No shader changed; it only changes the frame's light values per view, so split screen works per player. A first pass (key light off, ambient 0.03) was nearly black and was brightened after the capture. Evidence: captures of showcases 43 and 44 (the heart): the chamber reads as a cool dark cave with glowing crystals and doorway seams. **Not verified:** the crossing of a mouth in motion (only the blend maths and still frames), other caves' hues, and the nest's glow at the heart, which looks duller than before (its emission rides the same light values). Echo underground and point lights are still open.

## Cave temple redesign — 2026-10-16

The boxy pillared pavilion (`WildsMeshes.caveTemple`, placed in cave cache rooms) is now an ancient temple that is also a science lab: three round terraces with a stair, a glass reaction chamber holding a glowing core inside three tilted gimbal rings, a seven-column peristyle with glyph bands, lintels and crystal antennae, two resonator coils, two instrument benches with screens, inlaid glowing floor rings and circuit lines, a leaning pylon gate at the entrance and an arc of standing stelae behind. The hovering signal gem now sits over the chamber (`temple_crown`) and turns; the old front trim prop was folded into the mesh. A new test checks finite bounds, valid indices, height, detail count and that a real share of vertices glow. Evidence: captures of showcase 67 and a new close-up showcase 76 under `MTL_DEBUG_LAYER=1`. **Not verified:** a capture inside a cave cache room at the 0.66 scale and draw cost of the extra vertices.

### Rootdeep shrine dressing — 2026-10-16

The puzzle shrines keep their solvable machine-kit rooms (walls, doors, plates, buttons are unchanged, so the verifier and blueprint tests are untouched) and gain visual-only lab and temple dressing in `Frontier.publishShrines` / `dressShrineInterior`: two slowly turning halo rings over the portal; per room, four wall pilasters, glowing wall panels, ceiling light strips, inlaid floor lines and a turning gimbal hoop; and two rings around the seed lamp in the vault room. Two new unit meshes (`shrine_hoop`, `shrine_pilaster`) are registered in the catalog. Interior props are skipped when the player is more than about 90 m away, and everything sits clear of the walkway, buttons, plates and crates. Evidence: captures of showcase 60 (exterior) and the new showcase 77 (inside the first shrine) under `MTL_DEBUG_LAYER=1`. **Not verified:** the second shrine's colours in a capture, a multi-room shrine's furthest rooms, split-screen cost, and any draw-cost measurement. The interior walls themselves are still plain boxes.

## Imported rig retargeting fix — 2026-10-15

Review of the live-skinning path for imported characters found that the Ranger palette rotates about the Ranger's own joint positions (in metres) but was applied to imported geometry in the model's units, and that the per-bone inverse-bind data was stored and never read. Imported bones now store only their bind pivot (HWMS v3 bone is 16 bytes), and `Model.retargetBone` keeps the Ranger rotation, moves the pivot to the imported joint, and converts joint travel to model units. Evidence: a unit test (identity at rest, pivot fixed under rotation, +X swings to -Z, a 0.1 m bob arrives as 10 model units) that fails when the pivot term is replaced by the Ranger's; 455/455 headless tests on the default compiler; `build check` on 0.17; Metal smoke 300 frames clean under `MTL_DEBUG_LAYER=1`. A capture of the bundled `rigged_character.glb` in the world (`-Dcharacter-showcase=47`, third person) shows the mesh intact and posed, with no detached or sheared limbs in idle or the overhead swing; the arm movement is modest. **Not verified:** a run or walk cycle on screen, the 0.17 test run, and visual proportions for rigs whose bind pose differs from the Ranger's. Only seven joints animate; hips, spine, neck and head follow their nearest mapped ancestor.

## Denser Arbor canopy pass — 2026-10-15

- Increased the Arbor generator to 448 attraction points, a 640-node cap and 8.5 m growth steps; crown targets span more height, and short deterministic twigs fill primary and secondary limbs. Every non-trunk limb carries two overlapping foliage clusters and terminal twigs carry six. Arbor generator version 3 migrates version-1 and version-2 saves; unknown versions still reject. The separate heightmap authoring path also gained a smooth mountain stamp in the previous pass.
- **Checked:** default `python3 tools/zig.py build check`, `git diff --check`, and a frame-120 canopy capture with `MTL_DEBUG_LAYER=1` on Metal. The capture completed with no Metal API validation messages; the larger crown is denser, but the foliage still reads as rounded clumps.
- **Not checked:** headless tests, save round-trip/migration, longer performance benchmarks, and the Landscape mountain profile in an authored map. The heightmapped Landscape path is still not connected to the live world.

## Metal command-buffer GPU timing — 2026-10-14

- Added a benchmark timing hook to the vendored Metal queue. After command-buffer completion it records the duration between `MTLCommandBuffer.GPUStartTime` and `GPUEndTime`; the renderer samples those durations into p50/p95/p99. This is whole-command-buffer timing, not per-pass timing. Other backends report no GPU sample.
- **Checked:** default and Zig 0.17 `build check` passed. Four `python3 tools/benchmark.py --nature --frames 600 --silent` runs passed all nature benchmark checks, including `gpu_timing_collected`, on Apple M3 Pro / Metal / ReleaseFast. Each recorded 596–598 GPU samples. Median run-level p50/p95/p99 were **12.199/17.969/19.729 ms** (p99 range **19.354–20.009 ms**); median CPU p99 **2.914 ms**; median presentation p99 **21.017 ms**; all runs showed 551 visible vegetation instances and **12,248,988** submitted triangles.
- **Also checked:** the complete `python3 tools/validation_gate.py` passed after the fork change: default and Zig 0.17 checks, **440/440 tests on each**, and a clean 300-frame default Metal smoke with API validation enabled. Zig 0.17 Linux Vulkan/OpenGL and Windows D3D12 cross-compiles passed (compile-only). `python3 tools/zig.py build -Doptimize=ReleaseFast` refreshed the installed executable.
- **Not checked:** Zig 0.17 smoke, Linux/Windows runtime, and per-pass GPU attribution. The Metal HUD attempt emitted no timing samples, and `xctrace` is not installed. The 19.690 ms GPU p99 exceeds the 16.7 ms target; tree LOD is the next step.

## Green headless suite, explicit save floor, and Designer tabs — 2026-10-14

- Fixed the Catalog's deferred-mesh count, changed the Creator test to select `.height` directly, and split the 35-field Character Designer into Basics, Hair, Gear, Armor RGB, and Style tabs. Field navigation remains continuous; clicking a tab selects its first field. The layout test checks every field and tab hit at 720p and 640×480.
- Added `Save.min_supported_format = 13`, replacing the rolling `format_version - 12` check. Format 12 is now intentionally rejected. Added checked-in JSON fixtures for every supported format 13–25 and a decode/encode/decode round-trip test for each.
- Added `python3 tools/validation_gate.py`, which runs default check/tests and Metal smoke, then Zig 0.17 check/tests. It uses temporary test caches so cached build steps cannot suppress the test count.
- **Checked:** the complete gate passed on Apple M3 Pro / macOS 26.5.1 / Metal. Default and Zig 0.17 both pass **440/440**; default Metal smoke completed 300 frames with no validation messages. A 2560×1600 ReleaseSafe Character Designer capture (`-Dcharacter-showcase=23 -Dcapture-frame=120`) was visually inspected; tab labels and the selected page fit. `python3 tools/zig.py build check` passed on both channels; `python3 tools/zig.py build -Doptimize=ReleaseFast` refreshed `zig-out/bin/heavy-water`; `git diff --check` passed.
- **Not checked:** Zig 0.17 smoke or benchmarks, Linux/Windows builds or runtime, and hands-on tab clicking. The layout test covers navigation targets and field reachability. GPU timing and content priorities are updated in [next steps](plans/next-steps.md#revised-next-steps).

## Weather and seasons and settlement plans — 2026-10-15

- **Added (documents only):** [weather and seasons](plans/weather-seasons.md) and [settlement and building](plans/settlement-building.md), with owner decisions recorded: one global calendar with a two-hour year (four 30-minute seasons), bounded terraforming near settlements, a hybrid sandbox with light simulation, one shared settlement with personal rewards in each `Kit`, and building on ground claims and Arbor shelves. A second follow-up recorded: highland ice is walkable, night glow stays on for every tree, seasons do not change sap or machine power, weather can damage structures, claim sizes (chosen: 40 m growing to 96 m by level), mining down to the deepest known mine (Mponeng, about 4 km, so 4,000 m, checked by a web search that gave 3,891 m below datum to 4.0 km depending on the measure), no stockpile withdrawal caps, and full irrigation systems. The first follow-up recorded: winter freezes only the highlands, the civic Arbors stay lush, weather does not affect vehicles, storms and raids can destroy crops, settlers are both a count and visible people, and any player can withdraw from the shared stockpile. Links added from the roadmap, next steps, the nature plan, world and architecture. No game source changed.
- **Checked:** fifteen reference tests in two files (calendar, climate, highland ice and weather; crop growth with irrigation and storm damage, structure weather damage and repair, an irrigation network with exact water conservation, the hourly economy step, and the terrain edit-layer codec with chunk-seam consistency) pass `zig test` on the default compiler and on `HEAVYWATER_ZIG_CHANNEL=0.17`, and the blocks extracted back out of the finished documents pass again on both. After the second follow-up, seventeen more deliberate breakages of the ice, damage and irrigation code were run: one survived (ice measured at midday instead of the coldest hour), which exposed a missing assertion, and two first failed to compile; all were then caught. A test failure also corrected a claim of mine: at this lapse rate a 600 m lake freezes every dawn even in summer, and 40 m hills can grow a thin unwalkable ice skin on the driest winter dawn, so the docs say so. After the first follow-up retuned the climate (a test now scans the whole year to keep the lowlands at or above freezing) and added deterministic storm damage, nine further breakages were run and all were caught (two first needed a compiling form). Earlier, eighteen distinct deliberate breakages of the code were run; two were first missed (season progress and the economy's power scaling), and a third test, a catch-up check that compared a function with itself, was found weak by review; all three were strengthened until the breakages were caught. The exploration claims about the codebase (frame uniform layout, baked snow and frost, 103 `Terrain.surface` call sites, scatter id stability, the 16-machine and 96-flag caps) came from reading the cited files and were not re-run.
- **Not checked:** none of this is built. GPU cost of precipitation, the Metal HUD, the real memory and draw cost of 2,048 structures, the terrain overlay against the real chunk mesher, scatter and collision, and the real save size are unmeasured; the save budget in the settlement plan is an estimate. No build, test or smoke gate was run because no game code changed.

## Vehicle studio core and city content plan — 2026-10-15

- **Changed:** the first vehicle studio slice, headless. New `src/studio/` (`History`, `Knob`, `Brush`, `VehicleRecipe`, `VehiclePreview`), two `asset-compiler` commands (`vehicle-recipe`, `vehicle-preview`), and the test registrations in `tests.zig`. A recipe reproduces the three shipped hover cars exactly, edits a nine-station hull cage and twelve parameters through undoable, validated edits, and evaluates the real car with the game's own lift rule. Documented in [asset studio](plans/asset-studio.md) (section 11, S5), [architecture](architecture.md) and [building and testing](building-and-testing.md). The city content plan is documentation only: [city content](plans/city-content.md).
- **Checked:** `python3 tools/validation_gate.py` passed: default pair 451 of 451, Zig 0.17 451 of 451, Metal smoke clean. Ten new tests (history, knob, brush, six recipe tests, one preview). Five deliberate breakages of the recipe code were each caught by a test (never skipping a factor of 1, dropping the boost-over-cruise rule, never merging a brush stroke, an always-true lift rule, skipping validation in `set`); the boost-over-cruise breakage first survived because a test used an out-of-range value, and the test was fixed. A fuzz test builds 24 recipes at and between the cage and parameter extremes and all are finite. `asset-compiler vehicle-preview` rendered the three shipped cars and an edited custom car, inspected as images; building the car, rendering three CPU views and writing the PNG takes about 70 ms in ReleaseFast. A script over every doc reports no broken links.
- **Finding:** the car's mass is a fixed budget per part, not derived from its shape, so a longer and taller custom car kept exactly the skimmer's 1,046 kg. The brush cannot create real trade-offs until hull mass follows the shape (planned as slice V2).
- **Not checked:** the studio is not reachable in the game: `Designs.Design` is a fixed three-car enum used by the garage, fabricator, progress bitmask and saves, so custom cars need ids, dynamic mesh registration and a save migration (slices V3 and V4). No UI, pointer, pen or touch support exists yet, none tested on any device. The review sheet's top view crops a very long car slightly. The city plan's names, allies, boss and discoveries are proposals awaiting owner approval; nothing in it is built or tested, and its flag-capacity risk (96 flags) is from reading `Progress`.

## Owner decisions, asset studio and interchange plans — 2026-10-15

- **Recorded:** the owner's answers (ability core and behavior trees first; the mesh editor grows into specialized, touch-friendly, node-based studios for characters, vehicles, nature and cities; a local desktop four-player product with a later exchange standard for the sibling web engine; three sub-missions, one boss battle and ten item discoveries per city). The reply was not numbered like the questions, so answers were mapped by content and the mapping is stated in [engine features](plans/engine-features.md) section 8. Ability scope, ragdolls and a trailing "3." were not answered; defaults are recorded there.
- **Added:** [asset studio](plans/asset-studio.md) (shared shell, pointer and gesture layer, brushes, knobs, sockets, per-player library, phases S0 to S10) and [interchange](plans/interchange.md) (requirements only, standard after feature freeze). Networking (phase 16) is marked not planned in `networking.md`, the roadmap and next steps; the per-city quota is in `AGENTS.md`, `world.md`, the roadmap and next steps.
- **Checked:** the four asset-studio reference blocks (a mouse, pen and touch gesture recogniser; a symmetric pull brush; socket snapping; macro knobs) pass `zig test` on the default compiler and on `HEAVYWATER_ZIG_CHANNEL=0.17` (5 tests, all passing on both), and the blocks extracted back out of the finished doc pass again. A search of `vendor/mach` found no touch, pressure, tablet or pencil events in the core; the generated AppKit bindings do contain the event APIs.
- **Not checked:** touch and pen on any device or platform (no touch or pen hardware or Windows host here; an external touchscreen on macOS is expected to arrive as mouse events, unverified); none of the studios, the ability core or behavior trees is built; no build, test or smoke gate was run because this change is docs only. Another commit (`2d07a0d`) completed next-steps steps 0, 1 and 5 while this was written, so those rows read "complete".

## Unreal-style feature review and plan — 2026-10-14

- **Reviewed:** twelve proposed features against the code and docs: visual scripting, an ability system, behavior trees, virtualized geometry, global illumination, a material editor, live coding, world partition, a sequencer, deterministic physics, animation graphs, and replication. The verdicts and ordered plan are in [engine features](plans/engine-features.md).
- **Checked:** four reference blocks (a tag, attribute and effect core; a reactive behavior tree; a node-graph-to-register-program compiler; a sequencer track with once-only events) pass `zig test` on the default compiler and on `HEAVYWATER_ZIG_CHANNEL=0.17`, 4 of 4 each, and the same blocks extracted back out of the finished document pass again. Compiling them found a real design flaw (a behavior tree that resumes at its running child never re-checks higher-priority branches; the doc uses a reactive, stateless form) and two 0.17 differences (`x ** n` spacing and direct `@typeInfo` reflection). Claims about the game were verified against `Specials.zig`, `Enemies.zig`, `Device.zig`, `HotReload.zig`, `Streamer.zig`, `Rigid.zig`, `ik.zig` and the frontier benchmark taken the same day.
- **Not checked:** none of the proposed systems is implemented, so no cost or feel is measured; the example code is standalone and does not import project modules; the Mach claims (no mesh shaders, work graphs or GPU-built command buffers; atomics unimplemented) come from searching `vendor/mach/src` and the existing alignment notes.

## State review and docs alignment — 2026-10-14

- **Reviewed:** the roadmap, next steps, alignment, architecture, building-and-testing, AGENTS.md and the plan docs against the code and the gates, on commit `1eac838`. The review and the re-ordered next steps are in [next steps](plans/next-steps.md#technical-review--2026-10-14).
- **Checked:** `python3 tools/zig.py build check` passed on the default pair and on `HEAVYWATER_ZIG_CHANNEL=0.17`. `build test --summary all` gave 435 of 439 on both channels with the same four failures (`asset.Catalog` deferred meshes, `game.Save` round trip, `game.Creator` draft edit, `ui.Screens` layout); their causes are in the review. `MTL_DEBUG_LAYER=1 build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` completed (1,858 submitted objects, 396 simulation ticks) with no Metal validation messages. `python3 tools/benchmark.py --nature --frames 600` passed all checks (CPU p99 2.976 ms, `Chunk.fill` p99 8.894 ms, scatter p99 0.580 ms, 551 visible vegetation instances, **12,248,988 submitted triangles**, against 1,855,985 on 2026-10-13). `--frontier --frames 600` passed all checks (simulation p99 2.815 ms, character skinning p99 0.101 ms, render CPU p99 4.879 ms, presentation p99 20.955 ms; no audio device, so audio is unmeasured). `build modifier-bench` (ReleaseFast): `analyze` 3.8 to 52.6 ms, full `apply` 11.0 to 148.8 ms, `recolor` 10.1 to 132.9 ms, and one incremental `part_update` 0.32 to 32.1 microseconds over 100k and 1M vertices with 50 and 500 parts. A script over every doc found five broken anchors (fixed) and no missing files.
- **Changed:** docs only. `next-steps.md` (review, findings R1 to R9, revised order), `roadmap.md` (Next list), `AGENTS.md` and `alignment.md` (test counts, the dated re-gate), `architecture.md` (save format v25 and the supported window, the L-system forest, the mesh-editor bake), `building-and-testing.md` (showcases 71 to 75, `modifier-bench`, `-Dnature-benchmark`, `-Dbenchmark-frontier`, `--nature`), `nature-upgrade.md` (the triangle finding), and anchors in `project-overview.md` and `visual-direction.md`. No source file was changed; the four failing tests and the stale `Save.zig` comment are listed as steps, not fixed.
- **Process finding:** eighteen of the latest twenty entries in this file list tests as not checked (a text count of their *Not checked* lines), which is how the suite went red unnoticed.
- **Not checked:** hands-on play (milestone A checklist), the 0.17 smoke and benchmarks, Linux and Windows cross-compiles and runtime, GPU frame time, and audio callback timing. The Metal HUD attempt on 2026-10-14 initialized but emitted no timing samples; Xcode `xctrace` was unavailable. See the dated forest measurement follow-up in [next steps](plans/next-steps.md).

## L-system crown and nature camera follow-up — 2026-10-14

- **Changed:** fit each species' generated branch skeleton to the normalized bole height; generate leaf clusters on selected secondary branch segments as well as terminal twigs; modestly increase per-cluster leaf density and size while keeping individual foliage fans small. Showcase 71 now looks across ground cover from an offset, downward-facing position; showcase 72 backs away from the nearby trunks and frames the forest; showcase 73 uses daylight for terrain review.
- **Checked:** `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase={71,72,73} -Dcapture-frame=120` passed on Apple M3 Pro / Metal with no Metal API validation errors; each capture is 2560×1600. Frames are stored at `/tmp/hw-nature-baselines/showcase-{71-ground-final,72-crown-final,73-terrain-daylight-final}-frame-120.png` and visually inspected. The 71 camera clears the close trunk and shows low plants against an open field; 72 shows crowns spanning more of the bole and foliage on secondary branches; 73 now presents daylight terrain. The distant giant silhouettes in 72/73 still appear narrow and spindly, leaving species tuning and distance LOD open. Default `build check`, ReleaseFast install and `git diff --check` passed.
- **Not checked:** showcases 62/70, frame-480 captures, automated tests, benchmark after the crown changes, interactive tree traversal, Zig 0.17, cross-compiles or Linux/Windows runtime.

## Shared L-system forest skeleton — 2026-10-14

- Added `procedural/LSystem.zig`: eight seeded species grammars share a bounded turtle interpreter (4,096-symbol expansion buffer, 32-level branch stack). One generated skeleton provides tapered branch segments and terminal foliage anchors. `Vegetation.tree` builds compact leaf cards at those anchors; `Vegetation.trunk` bakes structural branches into the bark-tagged mesh. The foliage shader reads the bark tag and species bark vertex color, preventing the tree's green instance tint from turning branches green. Geometry is generated during catalog construction, outside the frame loop. This is a deterministic CPU Zig foundation; the pasted GPU work-graph / mesh-node proposal is not implemented. Mach exposes regular compute passes in some backends, but not the work-graph and mesh-node pipeline described there.
- **Checked:** default `python3 tools/zig.py build check`, `git diff --check`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed; ReleaseFast refreshed `zig-out/bin/heavy-water`. Metal API Validation captures of showcases 62 (frame 480) and 72 (frame 120) loaded the generated tree meshes on Apple M3 Pro / Metal, at 2560×1600, with no API errors. The final daylight frame-120 view of 72 was inspected: branch color is brown and the leaf cards are green and much smaller than the former pod-like masses. The mid-distance tree crowns still read sparse and pole-like, so the capture does not approve the forest art.
- **Not checked:** automated tests, benchmark after the generator change, close-up/daylight species lineup, gameplay tree interactions, canopy traversal/collision behavior, 0.17 channel, Linux/Windows builds or runtime. Arbors still use their separate space-colonization generator; integrating the grammar there needs attachment and save-compatibility review.

## Smaller canopy leaf clusters — 2026-10-14

- Rescaled the normalized giant-tree foliage before 96–152 m instance scaling: reduced broadleaf and willow cards, smaller leaf ellipsoids across redwood/copper-fan/cascade/blossom/pine crowns, and shortened the pine crown reach from 0.68 to 0.32. This targets the house-sized leaf masses and overlapping pine boughs found in review. It remains an art refinement, not a final tree pass.
- **Checked:** default `python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1` ReleaseSafe showcase 72, frame 120 (2560×1600), was captured and visually inspected after the changes; the oversized oval masses are reduced, but dense branch lattices and bead-like foliage remain. Showcase 71, frame 120, was inspected and found to look into a giant trunk/canopy instead of ground cover. Showcase 73, frame 120, was inspected and found too dark and sky-heavy to judge terrain. The Metal runs logged no API validation errors. Captures are outside the repository at `/tmp/hw-nature-baselines/`.
- **Not checked:** automated tests, benchmark after the foliage edits, showcase 62/70 or frame-480 captures, corrected 71/73 review cameras, 0.17 channel, cross-compiles, Linux/Windows runtime. Daylight gameplay review remains open.

## Nature review camera baselines — 2026-10-13

- Added fixed-seed showcases `-Dshowcase=71` (ground cover), `72` (mid-distance forest) and `73` (dusk terrain overview), positioned against the shared terrain surface. Updated the build option help and roadmap capture list.
- **Checked:** `python3 tools/zig.py build check` passed on the default pinned compiler.
- **Not checked:** visual captures, showcase 71–73 camera framing, tests, Zig 0.17, cross-compiles, Linux/Windows runtime. The nature benchmark now has a separate entry below; Phase 0 regression tests and visual review remain open.

## Nature benchmark instrumentation — 2026-10-13

- Added `python3 tools/benchmark.py --nature` and report fields for `Chunk.fill` p50/p99, scatter generation p50/p99, generated and visible object counts by kind, submitted scene triangles, and CPU frame p50/p95/p99. Chunk and scatter timings are sampled on the existing streaming worker; there is no new frame-path allocation.
- **Checked:** default `python3 tools/zig.py build check`, Python syntax compilation and `git diff --check`. `python3 tools/benchmark.py --nature --frames 600 --silent` passed all benchmark checks on Apple M3 Pro / Metal: CPU p99 2.856 ms, presentation p99 20.985 ms, `Chunk.fill` p50/p99 3.045/8.150 ms, scatter p50/p99 0.228/0.583 ms, 551 visible vegetation instances and 1,855,985 submitted triangles. The measured run generated 329 chunks, had no underfilled active-ring frames, and used the 384 KiB terrain upload budget. Timings cover the most recent 256 generated chunks; visible counts and triangles are the final measured frame.
- A 120-frame trial collected metrics but failed the existing `active_ring_covered` gate (68 frames underfilled), so it is not treated as a passing benchmark. The 600-frame run passed.
- **Not checked:** captures, tests, Zig 0.17, cross-compiles, Linux/Windows runtime. GPU timing is unavailable on this Mach path.

## Fixed-view showcase camera and broadleaf leaf crown — 2026-10-13

Fixed-view showcases (such as 62 and 70) set their camera before the simulation step, and every sim step moves the camera to the player's eye, so a capture showed the showcase view only if its frame happened to run no sim steps. That timing luck made some captures render a dark close-up of the ground instead, which earlier looked like broken tree meshes. `App.zig` now remembers the pose a showcase sets and re-applies it after the simulation steps. Verified: showcase 62 at frame 120 now reports the camera at the stage plus (28, 98, 430). The broadleaf crown is now 460 small six-point leaves in three clumps (`leafCards` in `Vegetation.zig`) instead of three smooth ellipsoids; at review distance the leaves read slightly hexagonal. A new test checks every tree mesh for finite values, bounded coordinates and valid indices. Checked: `build check`, the headless suite (420 of 424; the same four failures occur on HEAD), the Metal smoke run (clean), and the showcase 62 capture. Not done: the other species keep their ellipsoid crowns; GUI showcases that return early are unchanged; no Linux or Windows check.

## Arbor branching and flora trunks — 2026-10-13

Arbor limbs now keep 45% of their parent's heading and reject steps that turn more than about 75 degrees back on their limb, so branches curve instead of zig-zagging and hooking. Each branch tip carries three rounder foliage lobes instead of one flat pad. Flora trunks are a tapered, flared bole, and the deciduous species fork into three limbs under the crown. Checked: `build check`, the headless suite (419 of 423 pass; the same four failures occur on HEAD: Catalog deferred meshes, Save round-trip, Creator draft, Screens layout), the Metal smoke run (clean), and captures of showcases 62 and 70 at frame 480. Not done: one large looping limb remained in showcase 70; no Linux or Windows check. Arbor trees grow differently, so tap and graft positions saved against the old node layout may not line up; `Arbor.generator_version` was not bumped, which needs a decision.

## Launch from outside the checkout — 2026-10-12

- Startup now checks for the game marker in the current directory and then walks upward from the executable's resolved path. Once found, it sets the process working directory to the checkout so all existing relative asset, mod and save paths stay consistent.
- **Checked:** default `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed; launched the installed executable with cwd `/Users/home` for 12 seconds. It loaded both mods, initialized CoreAudio and Metal, and completed deferred mesh loading without a panic. `git diff --check` passed.
- **Not checked:** Finder launch, running after moving the binary outside the checkout, packaged-app resources, tests, Zig 0.17, Linux or Windows.

## Modular Scalari villain frames and city assault first slice — 2026-10-12

- Added data-driven frame/head/shoulder/arm/leg/back/weapon modules and five black-to-silver colorways in `game/EnemyDesign.zig`. The in-game Character Designer now opens HIVE FORGE to change a Titan's modules and palette; selected changes affect every Scalari siege frame for the current session.
- Surface nests now have visible workshop blocks, relay pylons and a lit assembly apron around the destructible command spire. The existing spire health, enemy waves, alloy cache and campaign flag still own raid completion.
- A bomber plaza raid now dispatches a Scalari siege frame and two ground escorts alongside the Hive aircraft attack, using the reserved encounter anchor without changing save indices.
- **Checked:** `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed with the pinned default compiler; the optimized executable was installed; `git diff --check` passed. The existing Metal-validated `-Dshowcase=30` capture completed without Metal validation messages, but its camera showed nearby canopy trees and combatants rather than clearly framing the new base/frame, so it is not a useful art review.
- **Not checked:** forge layout and input, robot silhouette/color readability, frame visibility at encounter distances, a focused Metal art capture, a full surface nest raid, bomber assault and rewards, balance, save round-trips, headless tests, Zig 0.17, or Linux/Windows targets. Forge choices currently last only for the running session and cannot yet use imported asset-library parts.

## Smooth GPU-drawn character eyes — 2026-10-12

- Moved eye whites, irises, pupils, highlights and upper eyelid ink from coarse head-vertex color interpolation to SDF drawing in the GPU-skinned character fragment shader. Eye geometry and both iris colors travel with each character's skinned vertices, so the existing eye customization is retained. Brows, nose and mouth remain baked face marks.
- **Checked:** `python3 tools/zig.py build check` passed. A ReleaseSafe close-up capture (`-Dcharacter-showcase=3 -Dcharacter-view=4 -Dcapture-frame=120`, Metal API Validation enabled) completed on Apple M3 Pro without Metal validation messages; `zig-out/eyes-review.png` was inspected and shows smooth iris boundaries and highlights.
- **Not checked:** headless tests, hands-on creator/gameplay review, CPU-skinned custom characters, Zig 0.17, Linux/Windows builds or runtime, and performance benchmarks. Mach's current WGSL compiler rejects derivative built-ins here, so smoothing uses a fixed UV-space edge band rather than screen-scaled derivatives.

## Detroit Riverfront, Belle Isle, and Windsor crossings — 2026-10-12

- Widened only Detroit's lane-zero river reach, fading it back to the regular channel beyond the city; terrain remains above water across Belle Isle and the streamed water ribbon splits around the island.
- Added an industrial promenade and ferry pavilion, park paths/fixtures on Belle Isle, two static road bridges toward Windsor, and two pedestrian approach spans linking the island to both banks. They share the district mesh/collider, while existing player-built bridge anchors and IDs remain unchanged.
- Bumped district generator to v7 and save format to v23. District generator 3–6 saves migrate with their plaza and player bridge identities retained.
- Added hydrology regression coverage for broad Detroit water, dry island terrain, and the narrow channel outside Detroit.
- Increased the terrain upload budget default to 384 KiB (minimum 322 KiB) to fit the split river-water buffers.
- **Checked:** `python3 tools/zig.py build -Doptimize=ReleaseFast` passed with the default pinned compiler and installed `zig-out/bin/heavy-water`; `git diff --check` passed.
- **Not checked:** headless tests, Metal capture or visual inspection, walking/driving the spans, vehicle clearance, save migration round-trip, benchmarks, Zig 0.17, Linux/Windows compilation or runtime. River width, bank approaches, and bridge height need in-game review.

## Detroit Arbor Reach and native pines — 2026-10-12

- Named the first city Detroit, Michigan, and show Detroit / Arbor Reach on the world map. The procedural skyline now mixes modern canopy towers, warm-windowed Gothic civic spires, and broad industrial factories with flues, service piping, hazard lamps, and transfer gantries; the industrial belt is a deliberate Hive foothold.
- Added a smaller layered pine mesh, scaled to 6–18 m and seeded through lower-arid forest and parkland scatter. Existing giant tree forms remain unchanged.
- Bumped the district generator to v6, scatter/world generator to v9, and save format to v22. District-generator-3 through -5 and scatter-generator-5 through -8 saves migrate while preserving plaza, bridge, and collected-object identities.
- **Checked:** `git diff --check` only.
- **Not checked:** build, tests, Metal capture or visual inspection, seed coverage for city silhouettes, hands-on routes, save migration round-trip, benchmarks, Zig 0.17, Linux/Windows compilation or runtime. Gothic/factory composition and pine scale need in-game review.

## Rootdeep shrine presentation and campaign beacon — 2026-10-12

- Replaced the stepped exterior shrine crowns and monumental piers with open rootwork arches, dark stone thresholds, inset lumen channels, and suspended ember/teal crystal crowns. Puzzle interiors, collision, solver, rewards, and saves are unchanged.
- Restored an outdoor sky beacon for the active campaign destination. It appears within 1,250 m and hides at close approach (34 m), and advances through Tavi, the first surface spire, Ines, a Brood carrier, Maro/the fabricator, remaining nests, and remaining carriers.
- **Checked:** `git diff --check` only.
- **Not checked:** build, tests, Metal capture or visual inspection, hands-on objective progression, benchmark, Zig 0.17, Linux/Windows compilation or runtime. The beacon and shrine silhouette need review in-game.

## Steampunk Arbor Rootways — 2026-10-12

- Added a reusable covered approach at each of the two outer Arbor ring plazas. Riveted bronze ribs and portal frames enclose the pedestrian/road path, paired metro rails pass through the crown, and five inset colored gems per side are published with night-responsive emission.
- Kept tree and plaza geometry intact: the gallery reaches the root-ring approach and frames its portal; it does not cut a physical opening through the living trunk.
- Bumped district generator version to 5 and save format to 21. District-generator-3 and -4 saves migrate with stable bridge endpoints.
- **Checked:** default `python3 tools/zig.py build check`, ReleaseSafe Metal capture `MTL_DEBUG_LAYER=1 ... build run -Dshowcase=64 -Dcapture-frame=120`, and `git diff --check` passed. `zig-out/rootway-review.png` was inspected; the rail and amber ceiling lights read through the gallery and the three gem hues are visible along both walls. Metal API Validation reported no errors.
- **Not checked:** headless tests, hands-on gallery traversal, Zig 0.17, Linux/Windows builds or runtime.

## Rootway gallery clearance cleanup — 2026-10-12

- Corrected gallery rib dimensions: the cross-section rotation follows each arch segment's local Y axis, so its length now belongs on Y. Previously the corridor-length Z dimension made each arch segment span the full gallery and stack across neighboring ribs, cluttering the walkable road. Opened the portal arch to 16.8 m wide and 11 m high, above the road and elevated rail clearance.
- The fixed geometry feeds both the resident city render mesh and static collider. Bumped the district generator to v8 and save format to 24; district-generator-3 through -7 saves migrate without changing bridge anchors or removals.
- **Checked:** `python3 tools/zig.py build check`, ReleaseSafe Metal capture `MTL_DEBUG_LAYER=1 ... build run -Dshowcase=64 -Dcapture-frame=120 -Daudio=false`, and `git diff --check` passed on Apple M3 Pro. The new `zig-out/rootway-v8-review.png` capture was inspected: the route stays clear and ribs now read as separate arches rather than stacked slabs. Metal API Validation reported no errors.
- **Not checked:** headless tests, hands-on traversal and Linux/Windows runtime.

## Canopy metro first slice — 2026-10-12

- Added `procedural/Metro.zig`: paired elevated guide rails and ties over the six plaza roads, outboard supports, and boarding platforms at the three market towers. These reuse the district's render/collision piece pipeline; station decks are walkable.
- Added South, North and West Line destinations to the per-player world map and fast-travel flow. Station arrivals use a nearby clear platform point. The UI map shows all six current destinations and party markers.
- Bumped district generator version to 4 and save format to 20; generator-3 worlds migrate while preserving their saved bridges. Scatter generator 8 and its generator-5 through -7 save migrations remain supported.
- **Checked:** default `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed. ReleaseSafe captures `-Dshowcase=8` and `-Dshowcase=55` completed on Apple M3 Pro with Metal API Validation enabled and no reported errors; `zig-out/metro-city-review.png` and `zig-out/metro-map-review.png` were inspected.
- **Not checked:** headless tests, manual station arrival/reachability, rail traversal, moving train behavior, downtown/suburb/farm generation, subway/venue interiors, high-speed intercity rail, spaceport arrivals, or Linux/Windows/Zig 0.17.

## Harvestable young trees — 2026-10-11

- Replaced the repeated blue cube salvage markers with small broadleaf trees that combine a leafy crown and trunk in one mesh. Their generated heights range from 6.1 to 18.3 m (20–60 ft); the giant tree scale is unchanged. They remain harvestable for parts, with a tree-sized interaction target.
- Bumped scatter generator version to 8 and save format to 19. Generator-5, -6 and -7 saves migrate while preserving candidate IDs and collected-object removals.
- **Checked:** `python3 tools/zig.py build check` and `git diff --check` passed. `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 120 python3 tools/zig.py build run -Dshowcase=62 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with no Metal validation messages. `zig-out/sapling-review.png` was inspected; the blue blocks are replaced by tree silhouettes.
- **Not checked:** headless tests, hands-on harvest reach and reward flow, Zig 0.17, Linux/Windows builds or runtime.

## Forward flight and expanded jet fuel — 2026-10-11

- Holding forward and tapping dodge three times within 0.92 seconds launches into sustained forward flight. Flight cruises at 32 m/s, reaches 52 m/s with sprint, uses jump/ascend to climb, and reaches 76 m/s during chained dash bursts. Each flight dash uses 18 fuel before efficiency upgrades.
- Increased the base fuel reserve from 100 to 240 and each of the three fuel-tank upgrade levels from +30 to +100, for 540 maximum (620 for winged heroes). Fuel efficiency applies to sustained flight and its dash bursts.
- Updated the upgrade description and movement documentation. The gesture works through the existing keyboard dodge binding and controller dodge button while forward is held.
- **Checked:** default pinned `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed.
- **Not checked:** headless tests, hands-on keyboard/controller timing, flight steering against terrain, fuel depletion/recharge feel, gameplay smoke, Metal capture, benchmarks, Zig 0.17, Linux/Windows builds or runtime.


## Character silhouette and fantasy canopy expansion — 2026-10-11

- Added two built-in hair cuts (crown braid and tempest sweep), pilot and recon helmet profiles, and the fabricable Solar Mantle armor set. New enum choices are appended to preserve existing saved tags; the helmet cycle reads its length from reflection.
- Added copper-fan, moon-cascade and star-blossom giant trees alongside the existing four forms, each with its own trunk and leaf pigment. Raised crown mesh tessellation and added a repeatable character showcase for reviewing the new armor, helmet and hair combinations. Scatter generator version 7 preserves candidate IDs; save format 18 migrates generator-5 and generator-6 worlds.
- **Checked:** default pinned `python3 tools/zig.py build check`, `python3 tools/zig.py build -Doptimize=ReleaseFast`, and `git diff --check` passed; the installed executable was refreshed. ReleaseSafe captures for `-Dshowcase=62` and `-Dcharacter-showcase=44..45` completed on Apple M3 Pro with Metal API Validation enabled and no reported validation errors. The tree lineup and character captures were visually inspected. The first character capture exposed oversized pilot helmet temple pods, which were reduced before the final captures.
- **Not checked:** headless tests, full gameplay smoke, benchmark, Zig 0.17, Linux/Windows compilation or runtime, old-save round-trip at runtime, and hands-on creator browsing. The first captured lineup remains visually dense and partly dark; clean close-ups of individual tree silhouettes and helmet fit still need review.

## Nearby loot, visible wild encounters and capture rewards — 2026-10-11

- Ground pickups now auto-collect within 3.5 m horizontally and 3.5 m vertically. Enemy takedowns immediately credit the nearest present player's Kit with XP and materials, so ranged kills no longer leave required salvage behind; Scalari pay scrap and parts, Hive units pay alloy and sometimes lumen. Hive drops remain for the no-player case.
- Four net-capturable animals now spawn 48–80 m from the starting point, within the near-body rendering range, and flee over terrain when approached. The practice patrol starts about 45 m from spawn with a low-damage prospector droid, followed by scout and stinger roles.
- A fresh pet capture separately grants 100 combat XP, 60 pet XP, 15 scrap, two parts and two lumen shards to that player's kit.
- **Checked:** `git diff --check`, `python3 tools/zig.py build check`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed with the pinned macOS compiler; the optimized executable was refreshed.
- **Not checked:** headless tests, Metal smoke/capture, hands-on play (including net aiming, capture interaction and reward display), benchmarks, Zig 0.17, Linux/Windows compilation or runtime. Prior uncommitted work in the tree is still present and was not altered as part of this feature.

## Running, dodge, dash and jump gestures — 2026-10-11

- Ground dodge now starts a short low roll even from a standstill; the previous minimum-speed gate made it appear unresponsive. An air dodge gives a brief evade, and a second tap upgrades it to the powered dash. The double-tap window is 0.42 seconds, and paired taps can chain up to four boosts. Sprint plus forward and jump launches the extended long jump; backward movement plus jump launches the backflip. Added separate sprint, roll, dash, long-jump and backflip poses, including timed rotation through the backflip.
- Documented keyboard and controller gestures and added showcase 63 to review each locomotion pose.
- **Checked:** `python3 tools/zig.py build check` passed on the pinned default compiler. ReleaseSafe Metal captures `-Dshowcase=63 -Dcapture-frame=400` and `-Dshowcase=28 -Dcapture-frame=120` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. `zig-out/movement-review.png` and `zig-out/controls-movement-review.png` were inspected; the backflip reads clearly mid-rotation, and the gesture guide fits on the Controls screen.
- **Not checked:** headless tests, full gameplay smoke, hands-on keyboard/controller timing, chain exhaustion and stamina behavior, Linux/Windows runtime, Zig 0.17, or benchmarks. The capture validates rendered poses, not live input feel or collision outcomes.

## Frontier wildlife, Scalari hybrid and field droid — 2026-10-11

- Added territorial retaliation for the four seeded wild companion species. The energy net deals nonlethal damage; two hits weaken and snare an animal at 24% vitality for eight seconds, and interaction catches it into that player's Kit. A close uncaught animal can swipe for 8 damage. The capture timer, co-op ownership and best encounter distances still need in-game tuning.
- Added a Scalari machine-insect hybrid melee role with its own health, speed and attack values, a character profile, XP and personal salvage. Its first instance appears near the existing distant Scalari nest. Existing Scalari scout, stinger, titan and miner remain distinct.
- Added a buildable field droid in the fabricator's Companions tab. It runs with the animal pet, follows, fires at nearby ground enemies, has independent health and combat-XP levels, and is saved per player. Scalari takedowns award the owner's parts. Save format 16 stores droid ownership and XP; formats 12–15 default those fields. Format 17 migrates generator-5 saves to the expanded flora while preserving candidate IDs.
- **Checked:** `python3 tools/zig.py build check` passed on the default pinned compiler; `git diff --check` passed.
- **Not checked:** tests, Metal smoke, performance, screenshots/art review, Zig 0.17, Linux, Windows, and the complete in-game capture-to-fabrication progression. This change has only had the macOS Debug compile check.

## Character ink hull cost and post-overhaul platform gate — 2026-10-11

ReleaseFast, Apple M3 Pro, Metal, silent, default pair, 600 measured frames (`tools/benchmark.py`, new `--cel-debug 1` flag hides the ink hull, same as F8):

| Route | Ink | Views | Render CPU p50 / p99 | Presentation interval p50 |
| --- | --- | --- | --- | --- |
| Frontier (four players, guests visible) | on | 4 | 3.18 / 4.46 ms | 20.85 ms |
| Frontier | off | 4 | 3.29 / 4.70 ms | 20.85 ms |
| Streaming (one view, no other characters in frame) | on | 1 | 0.36 / 0.56 ms | 20.85 ms |
| Streaming | off | 1 | 0.33 / 0.51 ms | 20.85 ms |

Findings: with four characters the ink hull adds no measurable CPU cost (the on/off difference is inside run-to-run noise, and ink-on was lower). Character skinning is 0.07 ms p50 either way. The presentation interval is identical in every run, including the empty one-view route, so it is set by display pacing, not rendering; **GPU time of the hull is not measured** (Mach has no timestamp queries). The hull is a second indexed draw per visible character, and `Characters.draw` already skips characters that are not visible, so no distance cut was added. Not measured: a true one-character route (the benchmark has only one view with no other characters, or four views); a lone character is drawn only in the creator. The frontier run also reports `simulation_step_budget` failing at p99 4.04 ms against a 4.0 ms budget with ink on and off, unrelated to rendering.

Platform gate results for the same commit are in [engine alignment](plans/alignment.md#post-overhaul-gate-on-main-1fe9e13-2026-10-11).

## Anime face and head proportions — 2026-10-11

- **Changed:** `HeadSpec` and the comptime `face_presets` table (six faces, with the new `hero`), keyframed head profile, short neck, 5.9 to 6.5 head ratio for humans, larger eyes, tapered brow strokes, flat nose with a shadow mark, adjustable mouth, `hand_scale` and `foot_scale`. `Profile.FaceStyle` gained `hero` at the end; no save format change (the tag is stored by name, old saves default to `classic`).
- **Checked:** `python3 tools/zig.py build check` (default pair) and `HEAVYWATER_ZIG_CHANNEL=0.17 build check` pass. `build test`: 369 of 377 pass; the 8 failures (armor suits count, asset Meta sidecar, Save format rejection, Sandbox controller, Profile hair-style wrap, Creator height, Screens layout, Enemies nest) fail identically on the unmodified base commit and are not from this change. New tests that pass: head profile ordering and head-ratio range for every preset, preset and `FaceStyle` order, hero versus classic proportions, face decal brow, nose and mouth placement, and the `FaceStyle` JSON round trip with a legacy document. ReleaseSafe Metal smoke (300 frames, validation layer) passed. ReleaseFast captures with `-Dcharacter-showcase=3` and `4` for classic, hero, soft, angular, alien and heroic were inspected.
- **Not checked:** the other platforms, benchmarks, helmet and hair fit across all styles (the visor and hair generators scale with head height and were only seen on the short hairstyle), profile and three-quarter views, and Wildkin visuals (they keep their own head ratio, neck and hand scale, only the tests exercise them). Captures are at creator distance, where the mouth and brows are only a few pixels.

## GLB source trace and modular export — 2026-10-11

- The repository already had a static glTF/GLB-to-HWMS converter. Added `asset-compiler trace` to validate sidecars and report GUID/hash provenance, stable node/mesh/primitive addresses, material slots, buffer/image dependencies and features outside the static importer.
- Added `asset-compiler split` to bake each selected-scene node/mesh/primitive into an independent HWMS model and write `modules.json` with source identity, content hash, material, triangle count and bounds. The bundled crate fixture exported two modules: hull (12 triangles) and band (12 triangles), with expected distinct bounds.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the pinned compiler; the game and host asset compiler were installed. Manual `trace` and `split` commands completed on `assets/source/crate.gltf`; output is under ignored `zig-out/`.
- Headless tests and cross-compiles were not run. Mod API 1 still cannot load or place exported model modules; texture maps, animation, audio and scene import are also outside this first static-model step.

## Importer expansion review — 2026-10-11

- glTF primitives without authored normals now import with deterministic area-weighted normals computed from transformed triangle faces. Trace and split manifests identify generated normals. The GLB reader rejects a mismatched declared file length, misaligned chunks, non-JSON first chunks, and duplicate JSON/BIN chunks.
- `python3 tools/zig.py build import` refreshed the crate sidecar to glTF importer version 2, retaining its GUID. `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the pinned compiler.
- Manual CLI review used a temporary copy of the crate with NORMAL removed: trace and split completed, both modules were exported, and all 48 output vertex normals were finite and unit length. A 12-byte malformed GLB was rejected with `InvalidGlbLength`.
- The headless suite, Metal smoke/capture, Zig 0.17 and cross-compiles were not run. No runtime or Mod API model installation was added. Additional formats, mesh optimization/LOD/meshlets, and guessed semantic labels were deferred; the current exporter preserves literal source primitive boundaries and stable hashes.

## Jeweled armor customization — 2026-10-11

- Added three armor unlocks to the fabricator and creator: Gem Aegis, Starforge and Deep Prism. All fit both existing body presentations. The player can customize the saved gemstone color (six options) and cut (three options); these appearance choices do not affect combat stats. New profile fields default for old saves, so no save version change was needed.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the pinned default Zig/Mach pair; the installed `zig-out/bin/heavy-water` was refreshed. The creator line-count expectation was updated for the two added appearance rows; tests were not run.
- `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=61 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed and the capture `zig-out/gem-armor-review.png` was inspected. Metal API Validation produced no reported errors. The ruby setting and customization controls are visible; the creator obscures part of the lineup, so all three silhouettes still need a clean visual review.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks and Linux/Windows runtime checks were not run for this increment.

## Energy net and greatblade — 2026-10-11

- Added a fabricable energy net. Its fast lattice shot reaches 120 m/s, damages every Hive flyer intersecting a broad capture corridor, and briefly freezes survivors for 1.45 seconds so they are easier to hit again. It has a 1.1-second firing cooldown and a distinct cyan lattice visual. The existing firearm shots still damage flyers through the shared Skies shot path.

## Starter companion, pet growth and air support — 2026-10-11

- Enlarged the energy-net lattice and its flyer hit corridor by 15%.
- New games, new local players, empty ranger files, and older empty saves receive the level-one plasma hound. Pet experience remains individually saved and now increases both damage and maximum health; each pet shows its current level and health in the HUD.
- Companion targeting now includes Hive flyers within 28 m as well as ground enemies. Pet strikes damage and stagger flyers, bring them down for alloy, and award nearby companions XP. Hostile melee units can damage pets; companions recover health outside combat.
- Default Zig/Mach build verification is in progress. Headless tests, smoke, visual capture, and other compiler/platform checks have not been run.
- Expanded the held saber into an oversized, curved, segmented plasma blade with a white-hot center and accent-colored outer facets. The animated swing trail is wider, longer, and uses the player's weapon accent; the damage sweep reach now matches the larger silhouette.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair.
- `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=37 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. Capture `zig-out/energy-blade-review.png` was inspected. The blade reads at a dramatically larger scale; the showcase image shows the held silhouette more clearly than its active swing, so the swing's pose and feel still need hands-on review.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run. Flyer net damage and snare behavior were reviewed in code but were not separately exercised in a gameplay run.

## Fantasy forest and species-colored bioluminescence — 2026-10-11

- Added procedural redwoods reaching 152.4 m (500 ft), with a dark-crimson crown and matching species trunk; broadleaf, needleleaf and willow forms scale to 96–150 m. These giant trees are sparse so native grass, ferns, manzanita and ember, moonbell and sunspear flowers remain the forest-floor layer. Scatter generator version 6 records the changed distribution and scale; prior generator versions are rejected rather than silently regenerated.
- Leaf flecks preserve each plant's own pigment at night: crimson redwood, red ember blossom, blue moonbell, gold sunspear, and the existing green and cyan plants. Grassy low-slope ground keeps its scattered glow patches; snow and steep rock remain masked out.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair. `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 120 python3 tools/zig.py build run -Dshowcase=62 -Dcapture-frame=120 -Daudio=false -Doptimize=ReleaseSafe` completed on Apple M3 Pro with Metal API Validation enabled and no validation messages. Capture `zig-out/flora-review.png` was visually inspected for tree silhouettes and night pigments.
- Headless tests, full smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this flora pass.

## Controller interaction and D-pad routing — 2026-10-11

- Reviewed the controller factory mapping and preset example. The factory layout already assigns all 16 standardized physical inputs; A is jump and X is contextual interact. The actual gameplay gap was P1 routing: D-pad edges were only used in UI, while guests already used left/right for weapon cycling and up/down for specials.
- P1 now gets the same gameplay D-pad functions: left/right cycle owned weapons; up/down trigger specials 1/2, with up+RB for special 3. Menus and trade panels keep their existing D-pad navigation.
- X remains separate from jump and now handles relic salvage as well as existing contextual use: talk/trade, hero recruitment, vehicle boarding/exit, device buttons, and machine inspection when aimed at a structure. Mouse salvage is preserved. HUD prompts identify X for these targets, and the mapping screen calls out interaction/discovery/mantling.
- Updated the portable preset example to match the real factory mapping and documented the button roles.
- `python3 tools/zig.py build check` passed on the default Zig/Mach channel. Headless tests, smoke, other compiler channels and cross-compiles were not run.

## Contextual vehicle boarding and smooth saber moves — 2026-10-11

- Nearby parked vehicles now remain interact targets when the aim ray lands on terrain, generic scenery or a bridge. The forgiving proximity radius is 6.5 m, boarding works from any selected tool, and the target prompt names X as the left face button. Semantic nearby targets such as a person, kiosk, device or jet keep priority.
- Replaced segmented held-blade pieces and block-built saber waves with generated curved blade, inner-spine and 64-segment crescent meshes. The third quick cut fires a smaller weak wave; the held charge remains the stronger, longer-reaching wave. Dash attacks slash through, ascending attacks rise, falling/stomp attacks cut down, neutral air attacks spin, and attack+dodge throws a piercing saber that returns to its owner.
- **Checked:** `python3 tools/zig.py build check` passed on the pinned default compiler. A ReleaseSafe Metal API Validation capture (`-Dshowcase=37 -Dcapture-frame=120`) completed twice on Apple M3 Pro with no reported validation errors; the smooth crescent shape and updated blade were inspected in `zig-out/saber-mesh-review.png`.
- **Not checked:** headless tests, full smoke, benchmarks, controller-in-hand boarding, move timing/target damage during gameplay, Zig 0.17, cross-compiles or Linux/Windows runtime. Compile-only vehicle reach and combat behavior still need direct input verification.

## Vehicle boarding prompt and keyboard interaction — 2026-10-11

- Parked garage cars remain interactable within 6.5 meters if the aim ray misses their chassis or is occluded by terrain. This also keeps the boarding prompt visible while standing beside a car.
- The existing `I` investigate key now performs contextual interaction; it still toggles the inspection panel when aimed at a structure. Vehicle prompts list `I`, controller `X`, and mouse click.
- The default Zig/Mach `build check` and installed `build` passed. `git diff --check` passed. Headless tests, smoke, Metal visual review, and other compiler/platform checks were not run.

## Ranger hairstyles — 2026-10-11

- Expanded the character creator from five hair entries to eleven: short, ponytail, long, crest, hood, bob, twin tails, bun, braids, curls and undercut. Ponytail, paired braid, bun, curly, cropped and mohawk silhouettes now have separate procedural generation paths. New enum tags are appended so existing profile JSON names remain valid.
- The pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. A Metal API Validation ReleaseSafe character preview for braids completed on Apple M3 Pro and was visually inspected. Headless tests were not run.

## Anime action hair — 2026-10-11

- Added data-driven hair (`hair_style.zig`, `hair_library.zig`): fat tapered clumps rooted on the scalp ellipsoid, a per-style hairline, `validate`, and `HairSpec.custom` for modded styles. Short and crest are now data; nine new styles (spiky_hero, widow_flame, fringe_spikes, super_flare, flip_bob, pilot_sweep, big_fringe, topknot, spike_tail). Profile gained `hair_spike`, `hair_volume`, `hair_length` (creator rows). New fields default on old saves and round-trip in a Profile test; `Save.format_version` was not bumped because nothing existing changes meaning (same policy as the face and boot additions).
- Tests: every definition validates, builds finite vertices with in-range joints, roots sit on the scalp, extents are bounded, the styles produce different meshes, adjustments change height, and a wider head still fits. Pinned `build check` passed; ReleaseSafe Metal captures of short and the nine new styles were inspected (all read as distinct, spiky or swept, not a cap). Not reviewed: side and back views, non-brown colours, spring chains moving (`sway` clumps only move when `chain_joints` > 0, which the game sets to 0), the remaining procedural styles' cap look, 0.17 channel and cross-compiles.

## Anime hair shading — 2026-10-11

- Ranger hair now bakes a broad broken highlight band plus narrow comb-strand glints into its vertex colors. This runs on GPU-skinned game characters; the CPU preview's existing cel light, face-shadow map, SDF facial decals and silhouette ink remain unchanged.
- Pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. `MTL_DEBUG_LAYER=1` ReleaseSafe braid character preview completed on Apple M3 Pro and was inspected. Headless tests were not run; close-up readability, other hair colors and moving-light response remain unreviewed.

## Solar-system roster, fusion-pulse travel and democratic campaign — 2026-10-11

- Added `procedural/SolarSystem.zig`, cataloging Mercury through Neptune, twelve visitable moon concepts, settlement/governance hooks, and one Scalari mining front per planet. Added a low-threat Scalari Talus Prospector enemy near the distant surface nest, with a compact drill rendering, 45 health, 20 XP and 2 scrap on defeat. Its mining-site records specify 4 abstract resource units/minute; a functioning mining economy is not connected.
- Fusion-pulse drive rating is fictional 0.5c for fast travel between bodies. The selected campaign scope is local flight around a planet/moon and its stations; continuous interplanetary flight and orbital mechanics are out of scope. Planet-scale metadata does not enter local physics or rendering. Gaia remains a constructed globe in Saturn space, and the Hive/Scalari homeworld stays interstellar.
- Updated the Solar Assembly / voluntary Galactic Democratic Compact framework and campaign plan for mining stations, staged city-planet growth, Venus terraforming, and an original winged transforming-mecha art direction.
- This is catalog/design groundwork plus one unverified ground enemy. No Kestrel form transition, mech locomotion/combat, mining production simulation, station building, space HUD, planetary fast-travel UI, or democracy interaction is playable. No build, tests, smoke or benchmark was run; compilation and behavior are unverified.

## Weapon visuals, suit runners and Energy Skate — 2026-10-11

- Saber blades use each player's profile accent. Charged waves use the saber slot's weapon element, and render as 14 overlapping facets forming a broad colored crescent with a white-hot inner edge. Mk III increases speed, radius, lifetime and pierce count.
- Hardsuits add joint-bound shoulder shells and luminous twin-roller heel runners. Energy Skate uses low-traction board movement on all current ground types, 16/23 m/s walk/sprint speeds, a 1.52× base jump and fuel-consuming air assist. It has a run animation pose and a distinct sound cue.
- No build, tests, smoke, visual capture or hands-on controller check was run for this pass. Zig compilation and the in-game look/feel remain unverified.

## Planet feature packs and maximum-progression test setting — 2026-10-11

- `Worlds.zig` now catalogs per-destination traversal, hazards, interactive city systems, enemy roles and mission objectives for Arbor Frontier, Hive Homeworld and Gaia. This remains typed design data; it does not add planetary travel or playable regions.
- Settings has a persistent `MAX PROGRESSION TEST MODE` toggle. Runtime test unlocks max out each player's gear, upgrades, combat level, pets and materials, plus team vehicles, aircraft, hero roster and Kestrel progression. Objective-completion flags remain untouched so the story can still be played in sequence.
- The application holds a full serialized pre-test world snapshot in memory, restores it when the toggle is turned off, and refuses world/ranger quicksaves while the toggle is on. Existing save data is not modified by enabling or exercising the mode.
- Build, tests and smoke were not run for this pass. Zig syntax, UI fit, unlock coverage, restore behavior and save blocking remain unverified.

## Chained dashes, Scalari practice patrol and ranger combat levels — 2026-10-11

- Dodge double-taps now start a 42 m/s directional dash on ground or in air. Further double-taps chain up to four bursts inside a 1.35-second window; single-dodge ground roll and board boost behavior remain available.
- Added low-health melee-only Scalari scout and stinger roles. A patrol near the spawn replenishes at 16-second intervals up to three active units; a Scalari bio-titan with 1,850 health and a heavy melee attack is placed beside a distant surface nest.
- Combat XP is stored in each player's Kit and ranger file/save shape. Every 250 XP advances a level, up to 50, and adds 2 maximum health. The nearest active player gets XP on a takedown; Scalari defeats also award personal scrap. Save format 14 reads formats 12 and 13 with their existing migration/default rules.
- Added cyan low-profile scout drone rendering, amber stinger and oversized titan character profiles, separate Scalari reward handling, and updated combat/world docs.
- No build, tests, smoke, benchmark, save round-trip, dash handling check or visual review was run. These changes are implementation-only and remain unverified on macOS.

## Long jumps and energy martial combat — 2026-10-11

- Sprint-jump now launches a long-jump motion with forward carry. An airborne stomp sets a short landing pulse; combat turns it into a 92-damage radial energy kick with push/stun and colored impact effects.
- Hands-tool attacks with no world target chain two energy punches into a roundhouse. The alternate input guards and briefly parries. The Ranger gets strike/kick poses; punch, kick and landing effects use the profile accent. Existing four-step chained dash remains available to set up an airborne finisher.
- The first pinned Debug check exposed a missing armor enum value plus syntax/name errors in the Scalari practice-patrol count and drone render local; these were corrected. `python3 tools/zig.py build check` and the ReleaseFast build both passed, rebuilding `zig-out/bin/heavy-water`.
- Headless tests, Metal capture, and hands-on combat were not run. Enemy hit feel, control conflicts and animation quality remain unverified.

## Starter Skimmer access and cockpit silhouette — 2026-10-11

- Worlds with no vehicle now receive a Skimmer in the garage, including existing saves with no fabricated ride. Boarding reports the drive/flight controls: W/S thrust, A/D steer, Space/E ascend, Q descend, Shift boost; click or controller interact to exit.
- The generated hovercar now has a raised panoramic canopy and swept nose canards. The Skimmer uses a deep blue shell, dark composite accents and cyan flight lighting. The existing four-fan hover controller supports close-to-ground driving and vertical flight.
- The pinned Debug check and ReleaseFast build passed; `zig-out/bin/heavy-water` was reinstalled. A Metal API Validation ReleaseSafe showcase capture completed on an Apple M3 Pro, and the refreshed model was visually inspected. Headless tests and hands-on driving/flight were not run.

## City modules and enemy damage audit — 2026-10-11

- Interior room roles now map to reusable fixture modules and local interaction anchors (exit, trade, evidence, power, alarm, loot, unlock, and Hive heart). This is a data contract for the runtime; rendering, entry transitions, doors, population, and actual interactions remain open.
- The district now composes a canopy parkour route at each market tower from reusable ladder, patio, ramp, mini-bridge, jump-gap, and grapple-anchor pieces. These are included in the same district render/collision mesh. Their placement and traversability have not been visually reviewed or hand-played.
- Hive damage is now fully held in each archetype's `Stats`: projectile burst values plus melee damage, guarded melee damage, grenade damage/radius/fuse/cooldown. Existing values are unchanged. Static rates at uninterrupted firing are drone 3.85 damage/s (5 every 1.3 s), sentinel 8.57 (three 8-damage bolts every 2.8 s), trooper 6.67 (two 6-damage bolts every 1.8 s), skirmisher 2.0 (3 every 1.5 s) plus 14.63 point-blank melee (12 every 0.82 s), and bulwark 2.5 (6 every 2.4 s) plus 15.76 point-blank melee (26 every 1.65 s). Trooper's 24-damage grenade adds up to 3.43 averaged over its 7 s cooldown at the blast center. These sources stack when multiple attacks connect.
- A correctly facing guard reduces bolts and grenade damage to 25%; it halves melee damage (trooper 18→9, skirmisher 12→6, bulwark 26→13). Player health regenerates after 5 quiet seconds at 10/s. These are code-derived rates, not measured encounter DPS or a manual balance verdict.
- Generated Arbor foliage now uses larger irregular eight-facet clusters, and the canopy course palette shifts toward warm grown decking, green structural rails, and lumen grappling markers. This changes render geometry and color only; the Metal art-review capture and hands-on route check have not been run.
- Build, tests, and smoke were not run for this pass, as requested; compile and runtime integration remain unverified.

## Ocean city catalog and feature plan — 2026-10-11

- Added stable Frontier city IDs for Pelaglass (human pressure-dome habitat) and Sonorous Reef (fully submerged cetacean city), an `ocean_shelf` biome descriptor, and distinct city roles. Frontier's expected catalog count is now seven; Hive Homeworld and Gaia remain five each. The campaign-wide data test was updated to expect 17 city records.
- Added the Stormwake Carrier Siege arena descriptor and encounter kind for open-ocean combat, plus [the ocean-cities design](plans/ocean-cities.md) covering wave surfing, underwater movement, carrier subsystem assaults, the paired-city liberation loop, original orca-form Tideborn champion Neri Tidebreak (working name), and separate Hive and Scalari roles.
- This is catalog and design groundwork only. No build, tests, smoke, ocean renderer, underwater movement, city geometry, or carrier encounter implementation was run or verified.

## Scalari campaign foundation — 2026-10-05

- The campaign catalog now has three destinations, five stable city-region IDs and one capital per destination. Validation enforces the city count, unique IDs/capitals and the single final-boss site at the Scalari Obsidian Coil; the Hive Homeworld records the Scalarians as its ancient founders.
- Five procedural Scalari ship assets are built and registered under generated GUIDs: Ember Wyrm, Void Lance, Dreadclaw, Throne Serpent and Worldcoil Ark. Their shell/glow geometry test checks non-empty indexed meshes and finite 3D vertices. The final mothership geometry uses one full-span armored wing assembly.
- `-Dshowcase=47` presents the three fighters and two motherships together for in-game visual review.
- `python3 tools/zig.py build test --summary all` passed **331/331 Debug tests**. After the mothership mesh review, the targeted Scalari/vehicle run passed **36/36 tests**; `python3 tools/zig.py build check --summary all` passed the full application compile, and `git diff --check` passed.
- ReleaseSafe Metal art-review capture: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dshowcase=47 -Dcapture-frame=90 -Daudio=false -Doptimize=ReleaseSafe` exited cleanly on Apple M3 Pro. It rendered all five ships in one 3D frame with no Metal validation messages; the review image is `zig-out/scalari_fleet.png`.
- City descriptions and ship meshes are authoring foundations only. City environments, capital interiors, playable Scalari flight/combat and final-boss gameplay remain unimplemented.

## Collision, interiors and shareable controller profiles — 2026-10-05

- Free-flight movement now passes through the character collision controller. Regression coverage checks landing on terrain and a rigid platform. Rigid boxes also resolve oriented SAT contacts against each other, while characters can stand on or be stopped by rigid-body floors and ceilings.
- Controller setup captures button mappings, adjusts axis sources/inversion and analog thresholds, and stores eight versioned JSON slots. macOS adds generic HID discovery and native JSON file dialogs; imported files are validated before becoming active and are copied into the chosen slot. Exported JSON can be uploaded to a community website. No website endpoint is part of this game repository.
- Interior generation now produces connected deterministic room-module graphs for residences, shops, factories, enemy bases and dungeons. Room rendering, entry transitions, doors, population and loot remain to be integrated into gameplay.
- `python3 tools/zig.py build test check --summary all` passed: **330/330 Debug tests** and the full application compile check. The latest world-catalog source also passes `python3 tools/zig.py test src/procedural/Worlds.zig` (**2/2**, including its Seed dependency).
- ReleaseSafe Metal smoke: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dsmoke-frames=120 -Doptimize=ReleaseSafe` completed all nine scripted stages, including saber/sniper combat, caves, four-player split-screen, building, save/restore and city traffic, with no Metal validation errors. The smoke also exposed and fixed an invalid tagged-union read in its weapon-fabrication loop.
- No physical unfamiliar HID controller or native import/export dialog was available for a hands-on run. Linux and Windows controller backends remain unimplemented.

Bootstrap (phase 1):

- Debug unit suite: 10/10 passed. Covers fixed-step stall accounting, projection depth and camera orientation, seed hashing, shared chunk seams, same/different seeds, allocation-failure cleanup, frustum boundaries, and signal graph validation.
- ReleaseSafe unit suite and application compile pass.
- ReleaseFast application builds and installs.
- Initial Debug smoke completed 120 submitted frames with 1,000 objects and clean shutdown.
- Final ReleaseSafe smoke completed all three scripted stages and 16 frames with `MTL_DEBUG_LAYER=1`; Metal API validation reported no errors. The final camera view submitted 732 of 1,000 objects with CPU culling enabled, and shutdown returned exit code 0.

The HUD reports render-callback interval, submitted instance count, draw count, seed, and culling state. No GPU timing or representative throughput claim has been established. Screen capture was unavailable in this session, so pixel-level visual inspection and manual keyboard/mouse interaction remain unverified.

## Procedural streaming (phase 2)

- Debug and ReleaseSafe unit suites: 20/20 passed. New coverage: chunk key boundaries (negative, NaN, out of range), planner bounds and center priority, handle invalidation on recycle, canceled generation, in-flight slots held until the worker acknowledges cancellation, unload/regenerate producing an identical terrain and scatter fingerprint with no new pool allocations, allocation-failure cleanup, biome normalization, scatter stability and slope limits, percentile ranks, and the fly-through route.
- ReleaseSafe 120-frame smoke with `MTL_DEBUG_LAYER=1`: no Metal validation errors, clean exit.
- ReleaseFast benchmark, 600 measured frames, default budget: interval P50/P95/P99 20.8/21.0/21.1 ms (presentation-paced), render-thread CPU P99 about 1.1 ms, 40 chunk crossings, 225 uploads, 200 evictions, peak upload 278 KiB of a 320 KiB budget, peak 25 resident chunks, 0 frames with the active 3×3 ring missing, pool allocations fixed at 2 CPU and 50 GPU buffers.
- One benchmark run reported an interval P95 of about 1 s with normal CPU times, which is macOS throttling an occluded window. The benchmark now fails such runs (`presentation_unthrottled`).

Interval timing is presentation pacing, not GPU execution time. Visual seam inspection at chunk borders is still manual.

## Interaction and assets (phase 3)

- Debug and ReleaseSafe unit suites: 36/36 passed. New coverage: typed handle pools; terrain queries matching rendered vertices and triangle interiors in a negative chunk; runtime model round trip, version, truncation, index, and allocation-failure rejection; glTF compile of the crate (two materials, interleaved view), baked node rotation and translation, out-of-range accessors, and unsafe external URIs; catalog load and allocation failure; box settling, stacking, friction, and raycasts; the character blocked by walls, stepping onto a ledge, and pushing a prop; save round trip with a seed above 2^53, and rejection of mismatched seed, generator, format, prop ranges, and truncated JSON; atomic save file write and read.
- Headless acceptance tests (`game/Sandbox.zig`): walk until a crate blocks the player, pick it up, turn and carry it 7.5 m, drop it, save, disturb the crate, relic set, and player, then reload the crate's exact position. A save from another seed is rejected. Salvage a relic by stable ID; it can no longer be targeted; regeneration yields the same object at that ID; the removal survives a save round trip.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: flight, empty view, walk mode, grab of crate 1 (`held=1`), and an in-memory save/restore of 1.4 KB; no Metal validation errors, clean exit.
- The streaming benchmark still passes every check after the renderer moved to catalog handles: interval P99 21.1 ms, render CPU P99 1.2 ms.

Not yet verified by hand: mouse-driven grabbing and salvaging, the on-screen crate model and crosshair, and F5/F9 against the real `saves/` directory. The code paths are covered by the tests above, but no screenshots or interactive session were taken.

## Machines (phase 4, door and elevator)

- Debug and ReleaseSafe unit suites: 44/44 passed. New coverage: port tables; blueprint parsing and rejection of wrong format, direction, port kind, multiple drivers, unknown ports, duplicate IDs, bad parameters, zero sizes, missing or cyclic logic, and malformed JSON; latch-driven actuators with two-hop latency and a mid-travel reversal; brownout sharing (two 100 W actuators on 100 W move at half speed); disabled generators; logic combining a proximity sensor; state restore validation; kinematic platforms carrying a crate, a character reporting its platform as support, and a door pushing a still character; the save round trip with machine state; and the catalog loading the shipped blueprints.
- Headless acceptance (`game/Sandbox.zig`): the closed door blocks the player; the button opens it in 150 steps to exactly 2.9 m of travel; the player walks through; a saved open state survives a manual close and reload, and stays open after stepping. The elevator carries a standing player from the platform to 4.2 m (±0.05 m), the player steps onto the landing, and the top call button sends the platform down while the player stays on the landing.
- Build-time validation: rewiring `toggle.state` to `platform.power` in `elevator.json` fails the build with `PortKindMismatch`.
- ReleaseSafe 150-frame smoke with `MTL_DEBUG_LAYER=1`: two machines placed, crate grabbed, 1.7 KB in-memory save round trip, door button pressed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 1.2 ms).

Not yet verified by hand: how the machines look on screen, placement on steep terrain (foundations extend 1.1 m below the origin, and deeper slopes can leave gaps), and pressing buttons with the mouse.

## Vehicle (phase 4, completed)

- Debug and ReleaseSafe unit suites: 53/53 passed. New coverage: quaternion rotation, matrix form, and integration; a tilted rigid box falling and settling flat on its largest face; a sliding rigid box shoving a crate; a fast rigid box stopped by a static wall; rigid boxes blocking the character; surface rays reporting platform velocity; the rover settling at its computed ride height (±3 cm), accelerating straight, turning more than 0.5 rad while upright, and braking to a stop; staying put without throttle; losing wheel contact in the air; holding on a 20° slope with brakes, both nose-up and sideways (drift under 0.02 m over 4 s); rolling freely when released; seat, motor, and steering outputs, including a 50 W supply halving a 100 W motor's drive; frame-relative device positions; and vehicle blueprint validation.
- Headless acceptance (`game/Sandbox.zig`): the rover settles aligned with sloped terrain on four wheels, is entered by aiming at its chassis, moves more than 4 m forward in 2 s on motor power (with nonzero network demand), stops under the parking brake after exit with the player standing outside the chassis, and its pose survives a save round trip exactly.
- Fixed while testing: tires that cancelled only velocity let a parked rover creep down slopes at 0.15 m/s. Tire forces sized with a quarter of the vehicle mass overshot into roll oscillation. Suspension pushing along the chassis axis leaked downhill force. Each fix has a regression test above.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: three machines, crate grab, 2.4 KB save round trip, door button, then the rover driven 3.5 m; no Metal validation errors, clean exit. The first GPU run found that Mach's WGSL compiler lacks `cross`; the shader now defines it.
- Streaming benchmark: all checks pass (interval P99 21.2 ms, render CPU P99 1.5 ms).

Not yet verified by hand: driving feel, chase-camera comfort, rendered wheel spin and steering, and collisions between the rover and machine structures at speed.

## Creation tools (phase 5, first slice)

- Debug and ReleaseSafe unit suites: 58/58 passed. New coverage: runtime blueprint edits under the file format's rules (multiple drivers, kind mismatch, direction, duplicate IDs, vehicle-only kinds); document round trips including wires and body flags; device removal shifting wires and compacting logic nodes; live machine reconfiguration keeping state; lamps lit only when switched and supplied; save v4 with embedded blueprints, yaw, and slot validation.
- Headless acceptance (`game/Build.zig`): generator, button, latch, and lamp placed from the palette on the 0.5 m grid; three wires made by aiming and clicking; a fourth refused because the lamp input is already driven; the button lights the lamp; a fresh session restored from the save has the same circuit with the lamp lit; removing the latch drops its wires, darkens the lamp, and re-tagged bodies still pick correctly. A quarter-turned door is placed on the grid with its travel mapped from +X to −Z, a second overlapping door is refused, and aiming at its structure removes it.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a four-device, three-wire workshop circuit built through the tool APIs, alongside the earlier stages; no Metal validation errors, clean exit. The whole-world save is now about 22 KB.
- Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.9 ms).

Not yet verified by hand: mouse-driven placement feel, preview visibility, wire bar readability, and F5/F9 of a built world through the real `saves/` directory.

## Prefabs and inspection (phase 5)

- Debug and ReleaseSafe unit suites: 59/59 passed. New headless acceptance: capture a generator, button, latch, and lamp circuit (named `circuit_1`, lowest device on the origin), place a copy that is its own machine, light only the copy's lamp with its button, inspect the copy (`NET 0 SUPPLY 200 W DEMAND 25 W 100%`, `lit 1.00`), rewire the copy while the prefab keeps its three wires, and restore the prefab library into a fresh session from the save.
- Manual library run: `saves/prefabs` holding a renamed elevator blueprint and a lamp with 0 W imported one prefab and logged `prefab broken.json: InvalidDeviceParameters`. The test files were removed afterwards.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: the smoke circuit is captured and a quarter-turned copy placed; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass (interval P99 21.4 ms, render CPU P99 0.9 ms).

Not yet verified by hand: pressing P and I in the running game, exporting a prefab file from a live capture, and the panel's legibility.

## Signal bus (phase 5)

- Debug and ReleaseSafe unit suites: 61/61 passed. New coverage: a sender machine's latched button carried over channel 7 to another machine's lamp; channel validation (0 and non-bus kinds rejected); and the in-world acceptance test (workshop button → latch → transmitter lights a separately placed beacon's lamp, retuning darkens it, channels wrap 1 ↔ 64, and the channel persists through a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` and the streaming benchmark: unchanged and passing (interval P99 21.3 ms, render CPU P99 1.0 ms).

## Player character

- Debug and ReleaseSafe unit suites: 65/65 passed. New coverage: name validation, typing, and the length cap; palette wrapping and proportion clamps; profile document validation; creator flow (name required, typing only in the name field, Escape only after a first confirmation, panel text); avatar proportions, hood parts, facing, glowing accents, and opposite leg swing; and the in-world test (frozen input in the creator, third-person camera behind the eyes while the crate stays targeted, avatar parts drawn, profile restored from a save).
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1`: a character named SORA with a ponytail created through the window-key path, then the crate grab done in third person; no Metal validation errors, clean exit.
- Streaming benchmark: all checks pass.

Not yet verified by hand: how the avatar and palettes look on screen, and the creator's usability.

## Mesh colliders (phase 6)

- Debug unit suite: 69/69 passed. The BVH ray cast matches brute force over 300 random rays on a bumpy 800-triangle grid; oriented boxes face outward; mesh build cleans up on allocation failure. Acceptance: the character climbs a 15° ramp, resting on its uphill footprint sample (0.7 r × tan 15° above center, within 1 cm); it stops at a leaning 80° wall exactly one radius from the face above step height; it lands on a 5° deck at y = 3.0 (±5 cm) and climbs toward the high end; picking reports the deck mesh and user; placement overlap sees the deck until it is destroyed; a crate rests on a mesh floor at 3.4 m (±2 cm); a rigid box settles on a tilted deck.

## Test Arbor and depth (phase 6)

- Debug and ReleaseSafe unit suites: 71/71 passed, with no leaks under the testing allocator (every test Sandbox is deinitialized). New coverage: test Arbor geometry (ramp grade under 12%, platform, bridge ends, and tower meeting at 40 m and 36 m within 1 cm, valid render mesh); the reversed infinite projection (near → 1, monotonic toward 0, distinct depths at 1 km and 1.001 km); and the full walk acceptance: steered up the whole spiral ramp at sprint input without dropping more than 0.6 m below its surface, reaching platform height (±0.3 m), then down the bridge road to the tower top (±0.1 m), grounded.
- Found and fixed by the walk test: the ramp first reached 40 m only at the platform's center line and ran into the platform's side 0.8 m below its top. It now levels out for the last 8% of its sweep.
- ReleaseSafe 300-frame smoke with `MTL_DEBUG_LAYER=1` (reversed depth, the test Arbor drawn): no validation errors, clean exit. Streaming benchmark: all checks pass (interval P99 21.0 ms, render CPU P99 0.8 ms).

Not yet verified by hand: how the tree reads on screen and at distance, and haze tuning.

## Canopy lighting and review (2026-09-30)

- Review found the renderer's time of day was never published, lamps and avatar accents never set the shader's emission channel, the twilight key changed direction while still bright, and the smoke circuit button press was overwritten by the door press. Those connections are fixed. The renderer now retains Mach's GPU error callback (which exits unsuccessfully), replacing a log-only override that could hide a failed render in successful smoke/benchmark exit codes.
- ReleaseSafe: **77/77 tests pass**, application compile passes. Added clock periodicity/large-tick/wrap checks, twilight continuity, and the canopy route. Extended existing integration tests to verify that save/load restores world time, a wired lamp publishes emission when powered and loses it after disconnection, and avatar lumen carries emission.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: all 300 frames complete, 383 simulation ticks, no Metal validation errors, exit 0. The smoke sweeps a complete lighting cycle, creates SORA, grabs a crate, round-trips a save, builds/wires/copies the workshop, confirms `Smoke lamp: lit=1`, and drives the rover 2.4 m.
- `python3 tools/benchmark.py --canopy --frames 300 --output .tools/canopy-benchmark.json`: all checks pass on Apple M3 Pro / Metal, ReleaseFast, default seed. 60 warm-up frames then 300 measured frames; 128 detailed-Arbor and 172 proxy-Arbor frames, 16 chunk crossings, 105 uploads, 80 evictions, no underfilled active-ring frames. Render CPU P50/P95/P99: **0.572 / 0.858 / 0.926 ms**. Presentation interval P50/P95/P99: **20.851 / 20.944 / 21.074 ms**. Peak upload 284,204 B within 327,680 B; peak 25 GPU terrain chunks; fixed pools remain at 2 CPU and 50 GPU allocations.
- Formatting and diff whitespace checks pass. Benchmark CLI help works with the new canopy option and separate default report path.

The benchmark measures render CPU submission cost and presentation intervals, not GPU execution time. Pixel-level appearance, outline thickness, color tuning, and manual day/night play remain unverified; no screenshot review was performed. The single test Arbor stays resident at both detail levels. Multi-Arbor residency, local lights, and bloom are not implemented by this change.

## Arbor genomes and sap (2026-09-30)

- ReleaseSafe suite: **85/85 tests pass**. New coverage includes deterministic bounded space colonization; genome validation; measurable narrow/broad silhouette differences; valid full/proxy/collision meshes; parent-before-child graph structure; allocation-failure cleanup; and landing/walking on a generated shelf at its rendered height. Existing full test-Arbor ramp/bridge walk remains passing.
- Sap coverage: proportional root sharing and branch limits, order-independent grants, independent trees, exclusion of local generator supply and detached/disabled/idle taps, continuous lamp brownout, and shared power across separate machines. The sandbox test saves overloaded beacons, removes a load and observes recovery, reloads and reconnects both to the same tree, rejects a generator-version mismatch without mutating the session, and verifies a remote copied tap supplies nothing. Tree lumen publishes reduced emission under overload.
- Build-tool acceptance: select the sap beacon from the palette, aim at terrain beside tree 1, obtain a valid preview, place it, receive full power, inspect its tree ID, then verify placement away from wood is invalid.
- ReleaseSafe application compile and `build assets` pass. All four blueprints, including `sap_beacon.json`, are validated and installed. Formatting, diff whitespace checks, and benchmark CLI help pass.
- **400-frame Metal validation smoke passes**, exit 0, no validation errors. It creates the player, grabs a crate, round-trips the save, builds/wires a lamp, drives the rover 3.3 m, views both generated Arbors, and reports `Smoke sap: tree 1 demand=300 W supply=150 W satisfaction=50%`. Final count: 509 simulation ticks, 861 submitted objects. The lighting cycle is swept across the run.

Apple M3 Pro / Metal, ReleaseFast, seed 310399555161; each canopy run has 60 warm-up and 300 measured frames:

| Route | CPU P50 / P95 / P99 (ms) | Presentation P99 (ms) | Detailed / proxy frames | Chunk crossings | Uploads / evictions |
| --- | --- | --- | --- | --- | --- |
| `--arbor 1` narrow crown | 0.561 / 0.744 / **0.868** | 20.987 | 174 / 126 | 14 | 95 / 70 |
| `--arbor 2` spreading crown | 0.580 / 0.789 / **0.898** | 20.976 | 174 / 126 | 16 | 102 / 77 |

## Hive air-wing variety (step 7)

- Added distinct dragonfly interceptor and beetle bomber meshes, type-specific speed, turn rate, hull strength and missile jinking. Carriers now launch a varied wing; bombers select the three market plazas as raid targets.
- Rangers on foot can hit flyers with their aimed blaster and firearm shots; the Kestrel retains its cannon and missile defense. Three successful bomb drops clear that stall's stock until dawn; destroying the bomber records a defended raid.
- Debug unit suite: **295/295 passed**. The focused Skies cases cover interceptor fragility, a ranger projectile defending a bomber raid, and the raid's three-hit loss condition.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: passed on Apple M3 Pro / Metal with no validation errors. All 300 frames completed; the smoke exercised the existing flight, four-player split-screen, market, and world-rendering paths with the new ship meshes registered.

## Kestrel progression (step 8)

- Aircraft tab adds three-level armor, missile rack, engine and gun-cooling upgrades, plus four paint finishes. Upgrade tiers cost shared scrap and parts; finishes save with player progress. Marked landing pads are published on each tower roof.
- Focused progression suite: 169/169 passed before the Aircraft-tab bounds case was added. Coverage includes purchase/refusal behavior, paint selection and save round trips, measurable hull/thrust changes, missile capacity, and cannon heat recovery.
- ReleaseSafe application compile and 300-frame Metal smoke pass on Apple M3 Pro with MTL_DEBUG_LAYER=1; no validation errors. The updated 300-frame smoke completed with 1,295 submitted objects and 394 simulation ticks.
- Debug unit suite: **299/299 passed**, including the Aircraft-tab bounds assertion.

## Hive campaign: corruption spread and seeded spires (step 9)

- Living surface nests spread a purple terrain stain that expands with the saved market day and stops at a fixed radius. Destroyed nests no longer spread corruption.
- The first new market day records the `corruption_seen` story flag. Up to three combat nests seed beyond a living surface nest on later market days; parent links, seeded locations and destroyed states rebuild from saved progression flags.
- Regression tests cover spread timing and cap, deterministic seed locations, seeded-nest population cap and market restock notice behavior. Debug unit suite: **301/301 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: passed on Apple M3 Pro / Metal with no validation errors; 120 frames completed with 862 submitted objects and 170 simulation ticks. This smoke starts on market day 0 and does not exercise later corruption growth.

## Hive campaign: story beats and quest log (step 10)

- Tavi's scout mark unlocks after corruption appears; a surface-nest kill advances that lead. Ines's Hive-sap warning follows the scout flag. A nearby Brood carrier records the sighting; Maro then grants the saved Kestrel blueprint. The fabricator refuses the Kestrel until that blueprint is received.
- The pause menu's Quest Log shows the active objective, saved story milestones and remaining nests/carriers. A saved campaign-complete flag is set when every nest and both carriers are destroyed.
- Regression tests cover keeper dialogue gates, Kestrel blueprint gating, objective progression (including saves that already own the Kestrel), quest-menu navigation, and screen bounds. Debug unit suite: **306/306 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: passed on Apple M3 Pro / Metal with no validation errors; 120 frames completed with 862 submitted objects and 169 simulation ticks. The staged Kestrel flight fixture supplies the blueprint reward directly. The smoke covers startup and split-screen, not a manual campaign play-through.

## Trooper tactics and skeletal actions (step 11)

- Wounded troopers search 16 grounded positions around their target and hold the nearest point whose line of sight is blocked by world geometry. If no cover is found, they keep advancing.
- Troopers close inside 2.5 m for a committed melee strike; a facing guard reduces its damage. At 7–24 m they throw a magenta grenade toward the player's predicted position. It has a 1.25 s fuse and 4.2 m blast radius; solid geometry blocks blast damage.
- The renderer maps cover, melee wind-up/strike, and grenade launch to dedicated poses on the existing skinned rig. Strike timing drives shoulder, elbow, chest and hip joints; cover folds the legs and guards the torso.
- Regression tests cover obstruction-based cover selection, the close-range attack, grenade launch and blast, dodging, skinned strike/cover poses, key interpolation and loop seams, weighted clip blending, traversal-state mapping, and walk/run/climb crossfades. Debug unit suite: **313/313 passed**.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=120`: clean exit on Apple M3 Pro / Metal with no validation errors; 120 frames, 862 submitted objects. This smoke covers general character rendering and split-screen but does not stage trooper tactics. Manual combat balance and animation readability still need a hands-on playtest.
- Controller smoke after the walk/run/climb crossfade change: same command, clean Metal validation, 120 frames, 862 submitted objects and 172 simulation ticks, including four-player split-screen.

Both reports pass all checks, including both LODs, the 16.667 ms render CPU budget, active-ring coverage (zero underfilled frames), and unthrottled presentation. Peak upload remains 284,204 B within 327,680 B; peak GPU terrain residency remains 25 chunks; terrain pools stay at 2 CPU and 50 GPU allocations. Reports are `.tools/canopy-1-benchmark.json` and `.tools/canopy-2-benchmark.json`.

These are submission and presentation measurements, not GPU execution timings or an art review. The three trees and both of their mesh detail levels remain resident; terrain-pool counters do not represent total process/GPU memory. No screenshot or manual visual approval was performed. Runtime grafting/growth, tree eviction, and allocation of unused flow after branch bottlenecks remain deferred. See [Arbor genomes and sap](arbors.md) for controls and content-v4 save compatibility.

## Upstream programmatic resize issue

A ReleaseSafe smoke run with Metal API validation reproduced a hang after setting `Core.windows.width/height` from the application thread. Sampling showed the main thread in `macOS.tick → NSWindow.setFrame_display_animate → windowDidResize → handleResize → windows.lock`. `tick` already owns that non-reentrant lock. The renderer and application then wait on the same collection lock. This is in the pinned Mach source, not a GPU validation error.

The experiment was terminated and the programmatic size change removed from the app. No dependency cache files were patched. The smoke sequence now exercises culling, an empty view, and HUD toggling. Initial sizing works. Before exposing a resolution selector, update or patch Mach with a tested callback/locking fix. Native drag-resize is a separate path and still needs manual validation.

## Remaining platform checks

- Manual camera capture/release, focus loss, minimization, live resizing, and high-DPI transitions.
- Windows/D3D12 and Linux/Vulkan runtime tests.
- Whole-process memory instrumentation: Mach's stock entrypoint currently omits module-container teardown.
- Deterministic screenshot regression tests and CPU/GPU percentile benchmarks.

## Packs and background loading (phase 13, slice 2) — 2026-10-01

- Debug suite: **159/159 tests pass**. The new tests cover:
  - **Packs:** round trip, blob verification, and five kinds of damaged table rejected.
  - **Loader:** 64 pack models load in the background with group progress reaching 1. A corrupted blob fails only its own asset with `HashMismatch`; a missing GUID fails with `UnknownAsset`; a generator job works; a bad pack header is refused on open.
  - **Catalog:** reserve and install, with double installs and unknown handles refused.
- The existing allocation-failure test caught a leak when a deferred build failed inside `loadSeeded`; fixed.
- `tools/benchmark.py --pack 64` (ReleaseFast, 600 measured frames): **all checks pass**.
  - The 80 MiB pack of 64 meshes was requested at frame 60, and all were decoded and installed by frame 64 and uploaded.
  - Render CPU P50/P95/P99 was 0.903/1.474/1.777 ms, presentation interval P99 21.297 ms, with zero underfilled frames.
  - The peak frame upload was 6.29 MB: the largest mesh going up alone, the allowed oversize case; every other frame stayed within the 4 MiB budget.
  - The first run failed `pack_uploaded`: 13 installs hit the 64-material pool limit. The stress code had also counted failed installs as installed. Both are fixed: the material pool is now 256, and only successful installs are counted.
- Smoke (`MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames, including four split-screen views): no validation errors. Deferred meshes were ready 145 ms after start. The overview capture shows the Arbors and district drawn from deferred builds.

## Asset identity (phase 13, slice 1) — 2026-10-01

- Debug suite: **149/149 tests pass**. The new tests cover:
  - **GUIDs:** format, parse rejection, derived and random generation, JSON form.
  - **Sidecars:** identity and settings kept across re-import, stale-source and old-importer detection, invalid and unknown settings rejected, kind by source type.
  - **Registry:** atomic manifest load, duplicate GUIDs refused with no change, typed resolution with kind mismatch and unbound errors, reference JSON.
  - **Catalog:** every compiled and generated asset resolves by GUID, and every blueprint is reachable by GUID.
- The existing allocation-failure test of catalog load caught `loadManifest` turning out-of-memory into "invalid manifest"; fixed.
- Build behaviour, checked by hand:
  - The build fails without sidecars, and `zig build import` created all 10 (crate plus nine blueprints).
  - A second import changed nothing.
  - Editing `rover.json` without re-importing failed the build with "StaleMeta; run `zig build import`". Re-import refreshed the hash and kept GUID `275f5eab…`, and the source was then restored.

## Sky city — 2026-09-30

- Debug suite: **133/133 tests pass**. The new tests cover:
  - **Bridges:** the clear envelope for six styles on six roads plus 0 → 3 across three seeds, grounded supports clear of plazas, and light-string geometry.
  - **Skyline:** at least 12 towers per seed for four seeds, every tower clear of corridors, plazas, trunks and spawn, deterministic placement, and 0 → 3 still buildable.
  - **In the world:** every buildable style built at 0 → 3 and stood on at 12 lane and walkway points each, with styles kept through save/load.
  - **Capture:** BMP encoding.
  - **Regressions:** the existing walk and drive district loops, Arbor walks, bridge tool, traffic, and shrine tests all pass with the new geometry.
- Visual review from captured frames (`-Dshowcase`, `-Dcapture-frame`), an overview plus every road by day and at dusk. Two problems found this way were fixed: a showcase camera inside a skyscraper, and a skyline that went dark at night (window columns and road lighting added). The cable-stayed pylon was also thickened. Art-direction approval remains yours.
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 frames: no validation errors, clean exit, 1,173 objects submitted.
- Benchmarks during this session ran with the window throttled by macOS, so only `presentation_unthrottled` failed. Render CPU P99 was 1.429 ms (canopy) and 1.527 ms (streaming), against 1.40 ms on the previous throttled run, with zero underfilled frames. Presentation numbers need a run with the window visible.

## Scale workloads — 2026-09-30

- Debug suite: **127/127 tests pass**. The new tests cover field determinism and cell sorting, bounds containment, budgeted streaming (20 frames at 64 KiB for 20K objects, with the CPU copy freed), frustum and distance culling, LOD selection, run merging and coverage, normalized frustum planes against the sphere test on 500 random spheres, and the process footprint.
- `tools/benchmark.py --scale` for 10K, 100K and 1M objects (ReleaseFast, 600 measured frames): **all checks pass**. See the results table in [scale](scale.md). Render CPU p99 is 1.271 / 1.213 / 1.281 ms and presentation p99 21.188 / 21.093 / 20.984 ms.
- Memory investigation at 1M:
  - The steady footprint was 1,006 MiB against 522 MiB without the field.
  - Skipping only the field's draws gave 742 MB, so about 380 MB is driver geometry storage for drawn instances.
  - The upload pattern changed the peak: 1.20 GB when uploading in one frame, 0.99 GB at 512 KiB per frame.
  - Uploads were moved from `queue.writeBuffer` to the frame encoder to share Mach's staging page.
- Not available: GPU execution time (Mach Metal has no timestamp queries), GPU-compacted culling and indirect draws (not implemented in the pinned Mach). Not measured: the visual result of the field at each LOD in the window.

## Mods and scripting — 2026-09-30

- Debug suite: **123/123 tests pass**. The new tests cover:
  - **Interpreter:** hand-assembled modules for control flow, memory, traps, fuel, depth, float conversion and float semantics; rejected imports, bad versions, and truncated or unbalanced bodies.
  - **Host:** the Zig-compiled `glowworks` module against native results, script-signature checks, and recovery from a starved fuel budget.
  - **Mod loader:** the example package, plus twelve rejected manifests or packages.
  - **World:** a breathing lamp tracks its script one step behind; duplicate installs, changed designs and missing mods are handled, and the save round-trips. The save test was also extended for v10 mods.
- Two bugs were found by tests while building it. The interpreter's loop branch re-entered the `loop` opcode, which broke branch depths. Script devices wrote their result to port 0 while `out` is port 4, as for logic.
- Interpreter cost (Apple M3 Pro, ReleaseFast / ReleaseSafe): `breathe` 802 / 836 ns per call (170 instructions); `majority` 374 / 408 ns (99 instructions); native `breathe` 5.6 ns. See the [scripting evaluation](scripting.md).
- Smoke, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 200 frames: the app installed `glowworks 1.0.0` from `mods/`; no validation errors, clean exit, 261 ticks for 200 frames (unthrottled).
- Canopy benchmark re-run with the window visible (300 measured frames, ReleaseSafe): **all checks pass**. Render CPU P50/P95/P99 0.675/1.061/1.142 ms, presentation interval P50/P99 20.842/21.1 ms, zero underfilled frames, 25 peak resident chunks, unchanged pools. This replaces the throttled presentation result recorded below.
- Not measured: official WebAssembly spec-suite conformance, and a mod placed and used by hand in the window.

## Rootsong, plaza priority, guest trading, Rootdeep shrines — 2026-09-30

- Debug suite: **115/115 tests pass**. The new tests cover:
  - **Rootsong:** root grouping, and a world test with a sender at the test Arbor and listeners at the narrow Arbor, the spreading Arbor, and away from wood.
  - **Traffic and trading:** plaza priority, and guest trading.
  - **Shrine generation:** 300 seeds verified with plan replay and blueprint validation, plus unsolvable, trivial and carry-versus-drop solver cases.
  - **Shrine playthrough:** both placed shrines played in the world from their verifier plans, with door states matched to the model after every action, then rewards, protections, reset and save/load.
- Shrine generation over 300 seeds: fallback shrine for about 1%. The median shortest solution is 8 actions (longest 16), and 187 of 300 need 8 or more. Keeping the longest of six verified candidates raised the median from 6.
- Two bugs were found by the in-world playthrough and fixed in the test's play method, not the game. Carrying a crate at eye height wedged it against the next divider wall; backing up swung it through the player. The test now carries crates overhead, clear of walls and above plate sensing height.
- ReleaseSafe step cost with city life and shrines, measured headlessly at spawn: full Sandbox step **0.130 ms** (physics 0.091, city life 0.043, machines 0.008).
- The free-traffic acceptance phase was lengthened from 60 s to 90 s, because plaza waits legitimately delay a car's third plaza on a long route.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames: no validation errors, clean exit, both shrines logged with their verified plans.
- **Not representative:** during these final runs, the window was being throttled by macOS (presentation interval p95 about 1 s). The committed build behaved identically on the same run: 4,301 against 4,292 simulation ticks over 200 frames. The canopy benchmark therefore failed only its `presentation_unthrottled` check. Render CPU P50/P95/P99 was **1.021/1.232/1.399 ms**, with zero underfilled frames, 25 peak resident chunks, and unchanged pools. Presentation measurements need re-running with the window visible.
- Not measured: a controller-driven guest trading session in the window, and manual play of a shrine in the window.

## Living city: traffic, pedestrians, markets — 2026-09-30

- Debug suite: **108/108 tests pass**. New tests cover route choice with and without a bridge, replanning, lane and walkway offsets, and market stock, sell-out, dawn restock, prices and save validation. They also include the Sandbox traffic and market acceptance tests described in the [roadmap](roadmap.md), plus a save round trip for the v8 wallet and stock fields.
- Traffic acceptance: 3,600 free steps with every car upright on the deck and reaching at least three plazas, and pedestrians each moving more than 20 m without falling. Then a 0 → 3 bridge crossing (the bridge reported occupied), and a bridge closed mid-trip: the car reroutes 1 → 0 → 5 → 4 → 3 and reaches plaza 3. The closed bridge is removed after its last pedestrian crosses, with **zero recoveries** throughout.
- A first draft refused to remove occupied bridges. The test showed that a pedestrian can hold a 320 m bridge for over three minutes, so removal now closes the bridge and removes it once clear.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 600 smoke frames with city life enabled: no validation errors, clean exit. There were 3 cars and 8 pedestrians with 0 recoveries and 0 deadlocks broken, and 814 objects submitted at completion. The market logged day 0 stock.
- Canopy benchmark (narrow Arbor), ReleaseSafe, 900 measured frames with city life running: render CPU P50/P95/P99 **0.814/0.992/1.103 ms**, interval P99 20.994 ms. There were zero underfilled frames, peak residency was 25 chunks, and pools stayed at 2 CPU / 50 GPU allocations.
- Not measured: simulation cost per step for city life (the benchmark measures render CPU), a long soak for rare traffic deadlocks, and manual play of the trade panel in the window.

## Traversal and local co-op — 2026-09-30

- Debug suite: **103/103 tests pass**. New tests cover the controller (buffered versus dropped early jump, stomp bounce, roll collider height, climb gate and mantle onto a 3 m block, grapple zip to a static anchor, glide, triple-tap hover). They also cover co-op proximity sensing, split-screen tiling, and the four-player Sandbox acceptance. In that acceptance, three guests join, P1 stays put within 0.05 m while P2 walks, P3 strafes and P4 turns 2.8 rad, all four bodies are published with owner tags, and P3 presses the powered-door button and the door opens. A guest then leaves, and the save contains no guest data but loads with guests beside P1.
- The previous controller commit had broken three existing acceptance tests (the crate carry, the powered door, and the third-person character). Walking into the crate row or the closed door started a climb over it. Climbing now starts only from a jump into a wall; all three pass again.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: players went 1 → 4 → 2 → 1. Views 2–4 each created their own streaming pool (49 CPU / 25 GPU chunks) once. There were no validation errors and the exit was clean (code 0). P2 walked under its own input while P1 flew to the far Arbors. The rover displacement (1.3 m) matches the pre-change build on the same run (1.2 m).
- Single-view streaming benchmark after the change, ReleaseSafe, **900 measured frames**: render CPU P50/P99 **0.805/1.085 ms**, interval P99 20.976 ms. Peak upload was 284,204 B, peak residency 25 chunks, with zero underfilled frames and unchanged pool allocation counts (2 CPU, 50 GPU).
- Not measured: split-screen CPU/GPU cost as a benchmark, a physical controller test (no pad was attached to this machine; the pad path is covered by the `Gamepads` unit test and the same `Input` route the guests use), and a manual visual review of the split layouts.

## Canopy district milestone — 2026-09-30

- ReleaseSafe suite: **95/95 tests pass**, including all existing ramp, machine, sap, physics, streaming, and asset tests. The application compile check passes.
- District generator v1 reproduces its six-node layout across five tested seeds. Solver tests reject invalid anchors, duplicate/reversed spans, excessive grades, trunk collisions, disconnected graphs, road crossings, and insufficient terrain clearance. Junctions reserve room for trunk spurs and market bays.
- Movement acceptance uses the real fixed-step Sandbox and collision: the player walks **0 → 1 → 2 → 3 → 4 → 5 → 0** without falling below the road, and a machine-powered rover drives that same loop without resetting its pose between roads. Every plaza is reached; the rover stays upright and the player exits onto the deck. Additional walks cover both complete trunk-ring plazas and their spurs, plus a newly constructed **0 → 3** bridge through both plaza seams.
- Construction tests place and settle a rover on an elevated plaza, reject unsupported edge placement, select two visible bridge anchors, commit/cancel/remove, and preserve endpoints and collision through save/load. Invalid bridge deltas leave the session unchanged. Allocation-failure injection exercises each allocation during bridge restoration and verifies cleanup and preservation of the old bridge and session.
- Native Apple M3 Pro / Metal run with `MTL_DEBUG_LAYER=1`, ReleaseSafe, **500 frames**: completed with no validation errors, 635 simulation ticks, 681 submitted objects at completion, powered lamp lit, rover displacement 3.2 m, sap demand/supply 300/150 W (50%), bridge preview rendered, and bridge **0 → 3** rebuilt through a 38,074-byte in-memory save. User save files were not touched. This is runtime validation; visual art-direction review remains outstanding.
- Existing narrow-Arbor canopy benchmark, with the district resident: **300 measured frames**, 60 warm-up frames, ReleaseFast. Render CPU P50/P95/P99 **0.877/1.009/1.084 ms**; presentation interval P99 **20.983 ms**. Fourteen chunk crossings, 95 uploads, 70 evictions, peak 25 resident chunks, zero underfilled frames, and unchanged fixed pool allocation counts. All benchmark checks passed. This measures renderer CPU submission and presentation intervals, not GPU execution time or city simulation performance. Report: `.tools/city-canopy-benchmark.json`.
- New saves use format **7**, content **5**, district generator **1**; old formats/content are rejected. One district and three Arbors remain resident. Runtime woody grafting/growth, city streaming, traffic, trading, and manual visual review remain future work. The original test-Arbor entrance keeps its 10% bridge; the new district roads enforce the 6% limit.

## Team saves: every player on their own — 2026-10-10

- **What changed:**
  - personal progression moved from the shared `Progress` into a per-player `Kit` (wallet included);
  - save format 13 stores every known player, and format 12 migrates into P1;
  - each save writes a ranger file per player;
  - FOUR PLAYER SETUP can seat any saved ranger;
  - pets became per player;
  - guests can meet heroes, free pets and pet any pet;
  - the setup screen widened to show each seat's character and scrap.
- **Tests:** **371/371 pass**, plus the app check.
  - Updated to the new rules: a guest trades from their own wallet and fires their own blaster.
  - The four-player test now checks that P4's kit and character survive a save and load after P4 leaves.
  - New: kit purchases and round-trips, team progress with format 12 migration, save members (duplicate slots rejected), and ranger files.
- **A bug the tests caught:** saving read each seat's profile through a by-value accessor, so the saved name was a slice into a temporary. `profileOf` now returns a pointer.
- **Smoke:** the Metal-validated ReleaseSafe smoke passed every stage. The new `Smoke team` line read: each player's kit restored to their seat=true, P2 ranger file round trip=true. That run was throttled (2,175 ticks).
- **Capture:** `-Dshowcase=54` first showed seat names overlapping the pad status in the 400-unit panel. The party panel is now 560 wide, with columns for character, scrap and pad.
- **Not checked:**
  - LOAD NEXT SAVED RANGER by hand, with real files and controllers;
  - two seats playing the same ranger file. It is prevented only among present players, and a second team could still diverge a file: the last save wins.

## Pets and armor detail — 2026-10-10

- **Captures reviewed and fixed:**
  - The armor lineup (`-Dshowcase=16`, `17`) showed a dark band on every jaw that read as a beard. It was the cel shadow on downward-facing jaw normals; faces now shade from a smoothed sphere.
  - The suits read as plain bodysuits. They now have distinct palettes, lit strips, cops, buckles, headsets, collar rings, core lights and power packs.
  - Pet captures (`58`, `59`): the moth's and falcon's wings were edge-on from the front, and are now pitched to face the eye. The moth's wings sat dark in their own shadow and now glow softly. The lineup moved to the open meadow, clear of spawn crates and buildings.
- **Tests:** **370/370 pass**, plus the app check.
  - New: pet levels and damage; spots on the ring and apart; every species follows, then attacks a trooper until it falls (and the moth mends); puppets use their part meshes and the golem stands tallest; the pet save round-trips and rejects unknown or unfreed pets; suits carry lit strips and a back pack standing off by suit; jaw normals.
  - The old test-only `Companion.zig` is removed; `Pets` replaces it.
- **Smoke:** the Metal-validated ReleaseSafe smoke (300 frames, 395 ticks) passed every stage. The new `Smoke pets` line read: freed GARU=true, followed within 1.8 m, fought a trooper down and learned=true.
- **Not checked:**
  - hand play: pet pacing next to a running ranger, attack readability in a big fight, and swapping pets by petting;
  - pets on bridges and in caves (the ground lookup takes the deck below, but this is untested);
  - the frame cost of up to five puppets (about 40 props each).

## Nature pass: ground, water, foliage and footing — 2026-10-10

- **What changed:**
  - terrain, foliage and water have their own shading stages (`terrain.wgsl`, `foliage.wgsl`, `water.wgsl`), spliced onto the scene shader's shared prelude;
  - the mountain panorama and caves are shaded as terrain (they had shown the props' checker);
  - boulders are added as new scatter candidates, and snow thins and frosts plants;
  - rivers can be waded and swum; snow, marsh and sand change footing;
  - footsteps are voiced by the ground, with new `crunch` and `splash` sounds.
- **Tests:** **364/364 pass**, plus the app check. New tests cover:
  - footing kinds from cover;
  - the river surface over its channel;
  - boulder meshes (closed, outward normals, sunk) and placement (IDs above the old candidates, sizes, all shapes);
  - runner speed on grass, snow, marsh and in shallows, and the longer slide to a stop on snow;
  - wading, then floating into a swim, then walking out;
  - ground-voiced footfalls and the fall-in splash.
- **Smoke:** Metal-validated ReleaseSafe smoke runs (`MTL_DEBUG_LAYER=1`, 300 frames) passed every stage with the three new pipelines. The first ran 399 ticks; the final run was throttled by macOS (8,062 ticks) but clean.
- **Mach WGSL compiler, newly hit:** `reflect` is unimplemented (written out as `reflected`), and `patch` is reserved.
- **Captures** (`-Dshowcase=36`, `41`, `42`, `48`), reviewed and retuned:
  - River water at grazing angles washed out to grey stripes. Fixed: the reflection is bluer and capped, and ripples are gentler and fade with distance.
  - Meadow colour patches were too strong; they are now subtler.
  - The mountain panorama showed the props' checker. Fixed: the landscape meshes use the terrain stage.
  - Stone strata aliased into moiré on the distant ranges and striped the low riverbanks grey. Fixed: bands fade by 260 m, and low steep ground stays earthy.
  - Close up, the strata were too regular. Each bed now has its own tone and crack.
  - Final captures show clean snow caps, earthy banks, natural rock beds by the cave mouth, and soft meadow grass.
- **Frontier benchmark** (window visible, before the cheaper ground lookup):
  - presentation p50/p95 **20.84 / 21.01 ms**, unchanged;
  - render CPU p50/p99 **2.35 / 3.83 ms**;
  - simulation p95/p99 **3.57 / 4.07 ms**: p99 is just over the 4 ms budget, so `simulation_step_budget` failed.
  - `Sandbox.surroundings` then stopped taking five extra height samples per player per step and reuses the terrain sample's normal.
  - Two reruns after that were throttled (presentation p95 above 1.3 s), so the effect is **not yet measured**.
- **Not checked:**
  - the wind sway and water motion in a live window;
  - GPU time of the new stages (the pinned Mach has no timestamp queries; presentation did not slow);
  - hand play of wading, swimming and snow footing.

## GPU skinning and the air-war budget — 2026-10-10

- **GPU skinning (phase 14 slice 2):** characters are skinned in a vertex stage (`render/skin.wgsl`) from a per-character dual-quaternion palette; see the [plan](plans/skeletal-animation.md). The skinned module reuses the scene shader's fragment stage. `-Dcpu-skinning` keeps the CPU path. The GPU and CPU captures of `-Dshowcase=49` look identical.
- **Air war:** terrain ray casts march adaptively (stride from the terrain clearance, 5 cm to 6 m, then 14 bisection steps) instead of a fixed small step, and the wasps' structure check casts against objects only (the terrain check already ran separately).
- **Verification:** **357/357 tests pass**, plus the app check. A new test matches GPU-style palette skinning to the CPU skin for four species in two poses (under 1e-4 m, normals within 0.999). The Metal-validated ReleaseSafe smoke (`MTL_DEBUG_LAYER=1`, 400 ticks) passes every stage.
- **Frontier benchmark** (`tools/benchmark.py --frontier --frames 600`, M3 Pro, ReleaseFast, window visible), before → after:
  - simulation p50/p95/p99: 3.55 / 6.27 / 6.72 → **2.15 / 3.57 / 3.99 ms** (budget 4 ms: now passes);
  - air war mean 2.09 → **0.11 ms** (wasps 0.63 → 0.03, air projectiles 0.68 → 0.04);
  - character skinning p50/p99: 0.86 / 2.05 → **0.08 / 0.15 ms**; character prepare p99 **0.19 ms**;
  - render CPU p50/p95/p99 **2.56 / 3.83 / 4.48 ms**; presentation interval p95 20.94 ms.
- The largest stages are now physics (0.79 ms mean, 1.82 max) and Hive AI (0.29 mean, 1.00 max); p99 sits just under budget, so either can push it over as content grows.
- A run with the window occluded or the screen locked is throttled by macOS (presentation p95 above 1 s) and fails `presentation_unthrottled` and `active_ring_covered`; keep the window visible when benchmarking.

## Controller weapons, controller start and scrolling GUIs — 2026-10-10

- **Right trigger and right bumper:** the energy gun and saber were routed correctly in code, but the installed `zig-out/bin/heavy-water` dated from Oct 5, before the Oct 6 controller change; `build run` and tests never reinstall it. It is reinstalled now. A new test drives a raw controller sample through the real mapping and P1 routing into a full Sandbox step: the right trigger fires energy-gun bolts and the right bumper swings the saber. P1's pad weapon routing is now one shared function (`Sandbox.padWeapons`). The build doc's troubleshooting covers stale installs.
- **Starting from a controller:** Start now begins from the title and finishes the creator, as well as pausing. Menus repeat when the D-pad or left stick is held.
- **Scrolling GUIs:** panels and menus scroll when taller than the screen, following the selection, with the right stick and mouse wheel scrolling freely. The Heroes screen keeps its natural layout at small widths instead of overlapping.
- **Verification:** **356/356 tests pass**, plus the app check. New tests cover canvas scrolling (follows focus, stays within the content, no scroll when it fits, hits shift with content) and the held D-pad.
- **Captures:** `-Dshowcase=56` (Heroes at 150%, scrolled to BACK) and `57` (pause menu at 150%, scrolled to its last item).
- **Not checked:** a hand pass with a physical controller (repeat timing, stick thresholds) was not possible in this session.
- **Review pass, the same day:**
  - The baseline was 353/353 tests and the app check, with a clean Metal smoke.
  - The three newest commits (armor coverage, controller intro weapons, fast travel) read correctly. Fast travel searches for a safe, unoccupied arrival (mesh colliders included) and changes nothing when none fits.
  - The frontier benchmark fails `simulation_step_budget`: simulation p95 6.27 ms against 4 ms, mostly the air war (2.1 ms mean: wasps and air projectiles). Character skinning p99 is 2.05 ms and render CPU p99 3.26 ms.
  - Long smoke runs while the window is occluded log tens of thousands of ticks (macOS throttling); unlocked, focused reruns log about 390.

## Review, Wildkin heroes and the Starbowl — 2026-10-05

- **Project review baseline:** 331/331 Debug tests, the app check, and the Metal smoke all passed before any change. The review read the most recent and riskiest changes (controller HID bridge, presets, rigid-body pairs, flight collision, menus). Issues found and fixed:
  - **Phantom pads:** `gamepad.m` matched HID devices to GameController pads by manufacturer against `vendorName` (which holds the device name), so a supported pad could appear twice, as two players. It now asks `GCController.supportsHIDDevice` (macOS 11+), with a product-name fallback.
  - **Stuck triggers:** on HID pads whose right stick reports on Z/Rz (0–255), those axes were also read as triggers, about 0.5 at rest and above the 0.15 threshold, holding sprint and fire down. Z/Rz are now triggers only when the pad has separate Rx/Ry axes.
  - **Off-thread dialogs:** preset export/import ran `NSSavePanel`/`NSOpenPanel` on Mach's app thread, but AppKit requires the main thread. They now run synchronously on the main queue.
  - **Preset string ownership:** `PadPreset.parse` could return strings aliasing the input buffer, which `loadSlot` frees first. It now always copies (regression test added).
  - **Flag limit:** `Progress` kept at most 48 story flags and silently dropped the rest; nests, carriers, caves and conversations can exceed that. Raised to 96 (test added).
  - Untyped HID name properties are type-checked before use.
  - **Noted, not changed:** `SuperMobility`, `Companion` (since replaced by `Pets`) and `QuestLog` logic exist but are only referenced from tests (the quest log screen draws from `QuestLog`, but nothing drives the other two in play). The rigid-body pair contacts and character rigid floors read correctly.
- **After the expansion:** **340/340 tests pass** (Debug), plus the app check.
- **Metal smoke** (ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames, unlocked, 391 ticks): `Smoke heroes: met ROOK BANDIT joined=true, played as them=true, powers used 3/3; arena entered=true wave 1 bots 2, cleared and paid=true, left=true`. Every other stage was unchanged and there were no validation messages.
  - An earlier run of the same build logged 71,259 ticks because the window was throttled during a long run; an immediate rerun with the screen confirmed unlocked logged 391.
- **Debug launch:** the Debug executable starts and builds its background meshes.
- **Captures:** `-Dshowcase=48` to `53`. Fixes from looking at them:
  - The first lineups showed dark bodies (the human undersuit covered the fur); Wildkin now wear a bright tank and shorts.
  - The lineup was wider than the view.
  - Long hero names overflowed their cards.
  - The arena floor was blown out white.
  - The scorpion's tail curled down instead of arching over its back (bend sign for a backward chain).
- **Not done or not measured:**
  - power balance and arena difficulty by hand;
  - guests choosing heroes from their own pads (the Heroes screen assigns any present player from P1's input);
  - per-form animation (tails and wings are rigid);
  - faces under snouts and beaks are simple;
  - the Starbowl has no boss;
  - cost of 32 skinned characters at once.

## Mountain ranges and cave dungeons — 2026-10-02

- Debug suite: **288/288 tests pass** (about 3.5 minutes). New tests:
  - **Ranges:** clear of the hub, peaks over 120 m, nothing added on river centre lines.
  - **Panorama:** below the real ground and facing up.
  - **Cave layout:** an open mouth; chambers under at least 7 m of rock; hollow above every chamber floor and solid below; the heart no higher than the mouth; deterministic.
  - **Cave mesh:** a ray down from each chamber finds an upward floor within 0.6 m of its floor height, and every covered chamber has a ceiling.
  - **Mouth coverage:** the cave mesh covers every dropped heightfield sample at the mouth. It first covered 95 of 105; ground quads that only touched the hole were being dropped, and are now kept.
  - **Walk-in:** the full Sandbox walks a player through the first mouth. The player stays under the slope, stands on the floor of the first chamber, and sets `cave_0_found`; the collider is built on approach.
- **World generator version 5:** saves from version 4 are rejected because the terrain changed. The Save, Enemies and nest-count tests were updated for this.
- Native Metal smoke, ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames, unlocked screen, 394 simulation ticks:
  - `Smoke caves: 6 cave systems in 4 ranges (highest spine ground 287 m), 6 meshes ready; walked in underground=true grounded=true 60.9 m under the slope, 1 colliders built`.
  - The frontier stage now reports 9 nests and 114 pickups.
  - No validation messages.
- Captures (`-Dshowcase=41` to `44`):
  - **Fixes from review:** the first captures had snow down to the cave mouths, so the range snowline was raised. They also showed a ragged hole around the mouth (the coverage bug above). The far panorama's edges were grown onto the foothills.
  - **Now:** snow-capped ranges on the horizon from the foothills. A dark mouth with a rock rim. A cave chamber with rough walls, a tunnel onward and crystals. The heart chamber's nest, whose troopers engaged the player.
- **Not measured or open:**
  - the added cost of mountain sampling in every terrain query, and of cave tests in rays near the ranges (no benchmark run);
  - collider build time on approach (a hitch, once per system);
  - mouths on gentle flanks read as slots rather than arches;
  - the sun still lights cave walls;
  - the panorama's far edges show as thin outlines against the sky beyond the streamed terrain.

## Fighting, energy firearms and classes — 2026-10-02

- Debug suite: **282/282 tests pass** (about 3 minutes). New tests:
  - The rig's hand sweeps across the front through a forehand and comes forward to aim.
  - A cut hits a trooper exactly once (forehand + backhand damage to 0.01), a mid-cut press queues the backhand, a full hold releases a charged wave, and the guard parries for 0.3 s and then blocks.
  - Blades cut each unit once per swing with knockback and stun; guards turn bolts into `deflected` events.
  - A sniper beam pierces exactly one unit and scopes to 0.3×; a bazooka orb bursts and stuns the unit beside its target.
  - Firearm rhythms: machine gun 13–15 shots a second until it overheats, sniper steadiness, heavy-rifle charge, bazooka detonation.
  - Specials: overshield soak, refusal while cooling down, grenade burst and stun, sentry zaps, phase-dash blink and stun, slam throw, lance damage and cast pose.
  - The profile class round-trips and defaults to Ranger for older documents. An old settings file with culling on C loads with special 2 moved to F7.
- Fixes found while testing:
  - The machine gun fired 12 a second, not 14, because the cooldown clamped to zero inside a step. It now carries the remainder.
  - Piercing shots hit the same unit again because they resumed inside its sphere; they now skip the unit slots they have passed.
  - The combat showcases first took the existing river viewpoint `-Dshowcase=36`; they are now 37–40.
- Native Metal smoke, ReleaseSafe, `MTL_DEBUG_LAYER=1`, 300 frames: `Smoke combat: saber and sniper made=true, saber cuts=3 trooper health 1616 stunned=true, sniper pierced=true, grenade burst=true, slam threw=true`. Every other stage was unchanged, with no validation messages. That run, unlocked, took 394 simulation ticks. Reruns after the screen locked took about 6,330, because macOS throttles presentation and each frame catches up more fixed steps; their results were otherwise the same.
- The Debug executable starts and runs, with no stack overflow from the new module state.
- Captures:
  - `-Dshowcase=37`: the forehand cut and overhead raise with blade trails, the blade leaving the right hand.
  - `-Dshowcase=38` and `40`: the first-person rifle and the lumen lance from the hand. The beams were first far too wide near the camera and were narrowed.
  - `-Dcharacter-showcase=5`: a Synthetic with lit eyes, collar, core and cheek seams. The cheek seams can read as tear streaks; art direction is yours.
- Not measured or checked by hand:
  - feel and balance (damage, energy, cooldowns, lunge strength);
  - the guest controls on a real controller;
  - the cost of posing a rig per armed player per step (one skeleton pose each, plus three per step while swinging);
  - the held weapons and slam or lance effects are block-and-gem placeholders.

## Debug executable stack overflow — 2026-10-01

- **Report:** running `zig-out/bin/heavy-water` (a Debug build) crashed at startup with a segmentation fault in Mach's `Modules.init`, at a stack address.
- **Cause:** Mach's entry point keeps every module's state by value on the main thread's 8 MB stack, and its `init` copies each module through a local. The overlay's inline vertex array (raised to 120,000 vertices for the GUI, 2.9 MB) sat inside the Renderer's state, so Debug builds, which keep those copies, overflowed. The smoke runs had all been ReleaseSafe or ReleaseFast, so they missed it.
- **Fix:** the overlay's vertices are now allocated on the heap when the renderer starts. A test caps the module-state sizes the suite can see (Sandbox under 1 MB, World under 256 KiB, Overlay under 4 KiB, Canvas under 256 KiB).
- **Verified:** the rebuilt Debug `zig-out/bin/heavy-water` starts, loads mods, opens audio and Metal, and runs for 25 s at the title screen. **270/270 tests pass.**
- **Follow-up:** run at least one smoke in Debug after state-size changes.

## Focused review: flight, air war and frontier — 2026-10-01

Review of the flight, air war, combat, garage and frontier code since the vehicle work began. Findings and outcomes:

- **Fixed (high):** a Kestrel left mid-flight kept its throttle and flew on unpiloted. Empty jets now cut the engine and let the lift jets lower them onto the gear. Test: a jet left at 30 m and 40 m/s settles onto its gear.
- **Fixed (medium):** the gear springs balanced at about 1 m of penetration, so parked jets rested on the hard-floor clamp rather than the gear. Each leg now carries a third of the weight at 10 cm. The same test checks the rest height.
- **Fixed (medium):** a shot could register on a carrier's launch bay even with a wasp nearer along the line, because the bay's 4 m allowance applied against any nearer hit. It now applies only past that carrier's own hull hit. Test: a wasp between the gun and a bay takes the shot, and the carrier is unharmed.
- **Fixed (low):** a stray no-op statement in `Frontier.stepSkies`.
- **Open (low):** a missile locked on a ground Hive unit tracks its slot index; if the unit dies and the slot is reused, the missile homes on the newcomer. See [next steps](plans/next-steps.md).
- **Open (docs):** the save-format description was stale (v10, without progress, cars or the fighter); it is rewritten in [architecture](architecture.md).
- **Checked, no change:**
  - The HUD projection's basis matches `Camera.move`'s right vector, and the up vector is forward × right. A capture with a live lock is still needed to confirm the reticle's side.
  - Wasps keep thinking after their carrier sleeps; with analytic avoidance that is bounded (14 at most).
  - Guests are in the wasps' target list with matching player indices.
- **Debug suite: 269/269 tests pass.**
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 smoke frames: no validation errors, clean exit; frontier and flight stages passed (Kestrel fabricated, lifted off, wasp downed).

## Flight: the Kestrel and the air war — 2026-10-01

- Debug suite: **267/267 tests pass**. New tests:
  - **Flight:** a vertical takeoff from the gear on the lift jets; wingborne cruise holding altitude at −4° to 10° angle of attack, with the top speed under 300 m/s; mouse-aim turns to a 90° aim and levels the wings; an afterburner climb; crash damage; a hangar test that takes off, transitions and flies.
  - **Ship meshes:** they build at their intended lengths, and the Kestrel's fuselage and fins are closed solids.
  - **Air war:** carriers launch wasps that attack, hit the jet and draw flak; cannons down a wasp; a locked missile damages a carrier.
  - **Fabricator:** the Kestrel recipe.
- **Found and fixed:**
  - **Climb:** at 48 kN the fighter bled from 150 to 78 m/s in a turn-and-climb. Thrust is now 58/95 kN (about 0.9 thrust-to-weight).
  - **Cruise angle of attack:** a fast cruise on the cambered NACA 2408 wing sits just below zero incidence, so the test range was corrected.
  - **Fin winding:** the lofted fin was inside out (volume −0.28).
  - **Hover transition:** hover drift-bleed fought the engine and capped the jet near 24 m/s, at the lift jets' handover. It now bleeds only sideways drift while the engine pushes.
  - **Wasp cost:** each wasp cast a 120–170 m ray every step. A test sat at full CPU for over 11 minutes and the game would have paid it every frame. Avoidance is now analytic terrain samples plus a short structure ray every fourth step, and the suite is back to about 2 minutes.
  - **Air war placement:** carriers now circle beyond the nests and wake within 650 m, so the air war stays over the Hive's ground.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke flight` fabricated the Kestrel through the panel, lifted off, and downed a wasp with the cannons; carriers were at 264 m and 326 m. The first run reported no wasp downed because the smoke placed the wasp along a level line from the pad into rising ground; it now aims into open sky.
- **Captures:**
  - `-Dshowcase=33`: the Kestrel on its pad.
  - `-Dshowcase=34`: the Kestrel banking hard on afterburner beside a Brood carrier, with wasps in formation and the second carrier distant.
- **Not measured:** flying by hand, missile play, jet–ship collisions (not implemented), and frame cost with 12 wasps and two carriers awake.

## Guest weapons, Hive troopers, saved cars — 2026-10-01

- Debug suite: **258/258 tests pass**. New tests:
  - Troopers march out of a nest, stay on the ground, and hunt.
  - Saved car positions and headings round-trip, unowned designs stay absent, and collected pickups stay collected.
  - A guest fires the party's blaster with the trigger through `Sandbox.step` and downs a drone.
  - The combat tests now run per arsenal; a shield raised by any player absorbs.
- Two first versions of the guest test failed on placement, not code:
  - The drone sat under the slope along the guest's pitched aim.
  - The shot met the crate row beside the spawn.

  The debug traces showed the shot flying true, so the test now levels the aim and uses a nearer drone.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** (screen unlocked): no validation errors, clean exit. `Smoke frontier` fabricated a car and a blaster, the car flew 19.5 m, and the drone went down; four-player stages ran with guest arsenals.
- **Captures:**
  - `-Dshowcase=32` (in flight) shows the Skimmer cruising 7 m over the terrain toward the city. Flown straight ahead, it stopped at a wall as designed.
  - `-Dshowcase=30` shows troopers in Hive plate advancing beside drones and a sentinel. The player lost 65% of their health in about 2.5 s standing still, so bolt damage was lowered and the spread widened; bolts are thinner too.
- **Not measured:** difficulty by hand, controller play, and skinning cost with eight troopers near P1.

## Frontier: hover cars, pickups, fabricator, the Hive and weapons — 2026-10-01

- **Generator code:** your vehicle generator modules (`hull`, `airfoil`, `prims`, `fan`, `nozzle`, `dynamics`) were added with their imports pointed at the character core. Their tests all passed the first time. The paste ended partway through the `dynamics` tests, so the energy test and a torque-direction test were finished here. `hover.zig` and `car.zig` were not in the paste and are written for this game.
- Debug suite: **255/255 tests pass**. New coverage:
  - **Vehicle geometry:** watertight hull, wing, fan and nozzle meshes; NACA and Helmbold values; the isentropic area ratio; closed-form box inertia; torus volume; energy-conserving torque-free spin.
  - **Hover:** momentum theory and its inverse; ground effect; lift shares balanced about an aft COM; settling level at ride height; cruise and boost caps; rolling hills at 45 m/s without touching; altitude hold over gaps; wall stops.
  - **Garage:** a built car hovers, all three designs lift themselves, and a car parks, is boarded, flown and left.
  - **Pickups and fabricator:** deterministic placement covering every kind; collect-once; drop expiry; recipes paid exactly and made once; first weapons alloy-free.
  - **Hive:** nest sites away from landmarks; dormant nests; woken nests spawning units that hunt, shoot and hit; strikes downing units and nests; a destroyed nest stops spawning.
  - **Combat:** weapon selection and cycling; a blaster shot destroying a drone; the saber cutting only in front; shield absorption; regeneration; restoring a downed player; health from vital cells.
  - **Saves and screens:** progress round-trips with inventory, picked IDs and owned cars, armor and weapons, and every screen, including the fabricator, lays out inside the window.
- **Fixed during the work:**
  - **Momentum theory:** four 0.6 m fans at 60 kW lift only about 7 kN; a 1.1 t car needs about 280 kW per fan, so fans now have 300 kW.
  - **Aft COM:** the COM sits 0.42 m aft, so equal lift per fan pitched the car up and it drifted backward. Lift is now shared by lever arm, plus a trim integral.
  - **Glow-mesh leak:** a glow mesh leaked when the catalog failed partway through; the allocation-failure test caught it.
  - **Top speed:** boosting reached 91 m/s; drag now includes fan ram drag.
  - **Ground loss:** at speed, a pad dipping into a slope lost the ground (its ray started underground) and the car sank. Rays now start 2 m up, there is a 0.9 s look-ahead probe and a hard keel floor.
- **Metal smoke:** native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke frontier` fabricated a Skimmer and a blaster through the panel, the car flew 19.5 m in 2 s, and 3 nests and 62 pickups were placed. That run reported "drone downed=false" because the smoke gave the drone 30 health against a 22-damage shot; the test was corrected to 15. This smoke ran before the hover floor and drag fix, the sound cues and the new dialogue.
- **Not re-run:** the screen locked partway through, so later smoke and capture runs could not render (`CGSSessionScreenIsLocked`; the app idles in its event loop). Re-run `-Dsmoke-frames=300` under Metal validation and the `-Dshowcase=29..32` captures once the session is unlocked.
- **Visual review** (`-Dshowcase=29..31`): the three cars hover on their pads with light strips and wings; the nest spire glows, drones and a sentinel hunt and fire red bolts, and the player's health drops; the fabricator panel shows tabs, cost chips and inventory. The first flight capture showed the 91 m/s top speed and the ground loss, both fixed above.
- **Not measured:**
  - frame cost of the Hive and the hover probes at full load;
  - flying the car by hand;
  - guests' weapons (not implemented);
  - listening to the new sounds.

## Audio — 2026-10-01

- Debug and ReleaseSafe suites: **216/216 tests pass**. New tests:
  - Synthesis: every sound is finite, audible and peak-limited, generation is deterministic, and loops join without a jump.
  - Mixer: one-shots end, pan, respect muted buses, and steal voices oldest-first; loops fade smoothly; a full ring drops commands.
  - Director: each event sounds once, the first frame only starts loops, guests are attenuated and panned, dialogue blips, and a paused world stays quiet.
  - Volume settings clamp and round-trip.
- A ReleaseSafe smoke crashed with an integer overflow on the CoreAudio thread on its first callback. The cause was `@min(chunk, frames - done)`: with a comptime bound of 256, Zig narrows the result to `u9`, so `n * 2` overflowed at 512. The fix widens it to `usize`. Debug had not tripped it in the runs tried; the mixer's own ReleaseSafe tests passed because they never went through the device path.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames** with audio on: CoreAudio at 48 kHz stereo f32, no validation errors, clean exit, every stage including four players and the GUI pass.
- Levels from `zig build sounds`: interface sounds around −10 to −16 dBFS RMS, effects around −13 to −17, loops around −13 to −19 before their gains. In the mix, the canopy pad sits near −26 dBFS under footsteps near −20.
- Not measured: listening (nobody has heard it yet; the WAVs are for that), latency, behaviour when the output device changes mid-session, and CPU cost on the audio thread.

## Guest HUD and rebindable controls — 2026-10-01

- Debug suite: **212/212 tests pass**. New tests:
  - Bindings swap conflicting keys, refuse reserved keys, and round-trip by name, ignoring unknown names.
  - The controls screen captures a key, swaps conflicts, cancels with Escape, and resets.
  - Settings round-trip with a rebound key.
  - The screen layout test now also draws a four-player split screen with a guest trading.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**, including four players with the new guest HUD: no validation errors, clean exit.
- Visual review: `-Dshowcase=27` (four players, P3 at Maro's stall) and `-Dshowcase=28` (controls while rebinding). Two fixes came from it:
  - Ware names showed underscores in the guest stall panel.
  - The interaction prompt showed through behind the pause menu.
- Not measured: rebinding by hand in the window, and controller play.

## Menus, GUI and conversations — 2026-10-01

- Debug suite: **210/210 tests pass**. New coverage:
  - Canvas wrapping, hits and measurement.
  - Scaled overlay text.
  - Menu navigation: disabled CONTINUE and LOAD are skipped, sub-screens return to their entry, quit is confirmed.
  - Settings clamping, round trip, and per-field clamping of a wild value.
  - Dialogue: the built-in file validates, branches follow flags, a gift is given once, panels end the conversation, and malformed data is rejected with a reason.
  - Purchases: upgrades and suits change nothing on failure, and progress round-trips, including shorter level lists from older saves.
  - Creator skips clothing that is not owned.
  - The Sandbox stall test now greets Maro and opens trade from his reply.
  - Every screen and every conversation node lays out inside a 1280×720 canvas.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, **300 smoke frames**: no validation errors, clean exit. `Smoke GUI` drives pause → settings → resume (closed), Maro's first greeting into the upgrades panel, buys fuel tank level 1, and closes every panel.
- Visual review from `-Dshowcase=18..26` captures:
  - The clock overlapped the scrap count: the wallet panel is wider.
  - The vitals panel overlapped the dialogue box: vitals hide under panels.
  - The player blocked the keeper: the conversation camera is now over the shoulder.
  - The wardrobe panel covered the character: it moved to the left and narrowed.
- A code review then found eight hardening items, all fixed:
  - Clicks are limited to the top layer.
  - Load failures show on the title screen.
  - Settings are written once on leaving their screen.
  - Upgrade levels are saved as a list, so adding an upgrade keeps old saves loading.
  - A wild settings value clamps instead of resetting every setting.
  - Purchase errors are worded for players.
  - Number keys only pick existing replies.
  - Fixed limits now follow the content: the clothing mask, the reply line buffer, and pedestrian conversations picked in file order.
- Not measured: manual play with a physical controller, split-screen GUI for guests (P1 only), and art-direction approval of the screens.

## Character generator and sci-fi armor — 2026-10-01

- The user-supplied procedural character generator (`src/character/`) replaced the block avatar for players, guests, pedestrians and stall keepers. Three new clothing types (exo rig, hardsuit, vanguard) are built from eight hard-surface armor coverages.
- Debug suite: **195/195 tests pass**. New tests:
  - Every armor vertex is rigidly bound to one joint.
  - Armor vertex counts grow exo rig < hardsuit = vanguard. The vanguard cuirass stands further from the chest than the hardsuit's, and the exo rig has none.
  - Two forearm plate vertices keep their distance within 1e-4 m through a walk pose.
  - Segment gaps split a span continuously.
- Fixes found while integrating:
  - The hair-removal index compaction used an aliasing `@memcpy` and aborted under a sealed helmet. It now uses `copyForwards`.
  - Two tests assumed block avatars, and the four-player Sandbox count also overflowed on owner-0 pedestrians. Both now count one character prop per player.
  - A heavy-armor test compared against a sealed helmet that also removes hair. It now compares like with like, and checks that the sealed helmet leaves no hair triangles.
- Visual review: `-Dshowcase=16/17` captures. Two jagged edges, on the faulds top and the cuirass bottom, followed body-region borders as stair steps. Both are now single continuous cuts across belly and hips. Art-direction approval remains yours.
- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, Debug, **300 smoke frames** with the armor lineup: no validation errors, clean exit.
- Not measured: CPU skinning cost with many armored characters (an armored body has about 3.5K more vertices), and a manual review of the creator cycling clothing in the window.

## Rivers, waterfalls, mountains and snow — 2026-10-02

- Seeded terrain now transitions from a smooth hub valley to ridged highlands. Exposed alpine rock and snow use elevation and slope masks.
- Rivers carve continuous channels and stream as blue world-space ribbons. Periodic seeded drops add vertical waterfall curtains; geometry is generated with each terrain chunk, including across chunk boundaries.
- World generator version is 4 because the terrain and water generation changed; saves from prior generator versions are rejected. Profile and content data are unaffected.
- ReleaseSafe tests and app checks: **276/276 pass**. New coverage checks waterfall drop height, river mesh indices, snow coloration, terrain sampling against the rendered ground mesh, and existing district/building/bridge clearances.
- Four-player native Metal smoke passed with terrain streaming, save/restore, construction and rover checks. `-Dshowcase=36` captures the river and waterfall viewpoint for visual review.

## Frontier correctness and renderer baseline — 2026-10-03

- Ground Hive missile and HUD references now include a per-spawn generation. Replacing a dead unit in the same slot invalidates its old lock instead of redirecting the missile to the replacement. Regression coverage checks slot generation increments, stale HUD lock rejection, new candidate identity, and a missile retaining its course after its target slot is reused.
- Debug suite: **290/290 tests pass**.
- Native Apple M3 Pro / Metal, ReleaseFast streaming benchmark, 600 measured frames: all checks pass. Render CPU P50/P95/P99 **5.87/6.44/6.85 ms**; 40 chunk crossings, 225 uploads, 200 evictions; peak terrain upload **299.4 KiB / 320 KiB**; peak 25 resident chunks; **0 underfilled frames**.
- This route does not stress the full frontier encounter. Simulation, 24-character skinning, and audio-thread costs remain unmeasured; the documented `--frontier` benchmark and hands-on flight/combat/audio checklist are still outstanding.

## Playtest checklist, automated smoke — 2026-10-03

- Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300 frames with audio enabled: clean completion, no Metal validation messages, 395 simulation ticks. The run fabricated and flew the Skimmer 18.7 m; fabricated the Kestrel, lifted off and downed a wasp with its cannon; exercised saber, sniper, grenade and slam combat; and ran four local players through split-screen and co-op movement.
- This smoke did not fly all three car types, dogfight and land the Kestrel, exercise every firearm and guard/parry action, use a physical controller, or listen through the sound set. Those hands-on checks remain open; audio-device startup is verified, sound quality is not.

## Four-player frontier combat and performance — 2026-10-04

- `tools/benchmark.py --frontier --frames 600` now runs four local players, scripts 360 ground-fight and 390 air-combat simulation ticks, records weapon-fire and target counts, and measures simulation stages, character skinning, rendering, presentation, and CoreAudio callbacks.
- Apple M3 Pro / Metal, ReleaseFast: render CPU P50/P95/P99 **1.76 / 2.72 / 3.03 ms**; character skinning **0.86 / 1.79 / 2.05 ms**; simulation **3.55 / 6.27 / 6.72 ms**; presentation interval **20.85 / 20.91 / 20.93 ms**. Four views remained covered, with zero underfilled frames and peak terrain upload **299.4 KiB / 320 KiB**.
- Audio callback P99 was **0.197 ms**, or **1.85%** of its real-time budget. All render, character, streaming, combat-coverage, and audio checks pass. The 4 ms simulation P99 target still fails.
- Profiling isolated terrain queries in projectile raycasts as a repeated air-war cost. Airborne segments proven above the hub's conservative height bound now raycast bodies and meshes without marching the terrain; ground-level and mountain-region shots retain full terrain collision. The detailed projectile-stage mean fell from **1.37 ms** in the 240-frame profile to **0.91 ms** in its 240-frame comparison; the full 600-frame run measured **0.70 ms** mean and **2.25 ms** maximum. Wasp terrain look-ahead also reuses its samples for one fixed step.

## Balance tuning foundation — 2026-10-03

- Gathered the current encounter and balance values into named module tables: Hive stats and spawn pacing (`Enemies`), wasp/carrier/Kestrel combat (`Skies`), player damage and survivability (`Combat`, `Weapon`, `Firearms`), pickup placement counts (`Collectibles`), per-car handling (`Designs`), and Kestrel mass/camera values (`Hangar`). Fabricator recipes were already a single table; hover and jet flight parameters remain grouped in their `Config` structs.
- No numeric balance values changed. The deterministic tests and scripted smoke verify actions complete, but cannot tell whether wasps feel fair, handling is satisfying, or recipe pacing is too long. Actual balance edits remain pending the hands-on checklist above.
- Debug suite: **290/290 tests pass**. ReleaseSafe 300-frame smoke with Metal validation and audio also passed after the refactor.

## Missile lock reticle capture — 2026-10-03

- Added `-Dshowcase=45`, which stages the Kestrel above the canopy, spawns a ground drone ahead, holds missile lock, and captures the normal flight HUD. Reproduce with `MTL_DEBUG_LAYER=1 caffeinate -d -u -t 90 python3 tools/zig.py build run -Dshowcase=45 -Dcapture-frame=120 -Doptimize=ReleaseSafe`.
- The captured frame shows the red target box and `LOCK` label on the target inside the flight view. The generation-checked lock lifecycle is covered by the 290-test suite above; the showcase verifies the reticle projection in a live render.

## Kestrel ramming and wasp spacing — 2026-10-03

- Kestrel contact uses the carrier's hull spheres and a 5 m aircraft collision radius; wasps use their 3.2 m hit radius. Impact damage scales with relative speed above 18 m/s and has a short repeat-hit cooldown. Contacts move the Kestrel clear and rebound only inward velocity. Wasps steer away inside 16 m.
- Regression tests cover aircraft separation/rebound and hull loss, deterministic close-range separation vectors, and ram damage to both the Kestrel and each target type.
- Debug suite: **293/293 tests pass**. ReleaseSafe application check passes. Native Apple M3 Pro, `MTL_DEBUG_LAYER=1`, ReleaseSafe, 300-frame smoke completed with all stages passing and no Metal validation messages.

## Brood carrier assault — 2026-10-03

- Carrier damage now advances through four flak turrets, four launch bays, and an exposed underside core. Cannons and lock-on missiles target the active stage's individual hit volumes; intact stages shield later parts. The flight HUD reports the nearest carrier objective, active weak points receive bright target markers, and destroyed turrets stop firing.
- Core failure starts a scripted descent with a tumbling carrier and repeated debris bursts. The carrier defeat flag and reward cache trigger when it reaches the ground; the event remains deterministic and testable.
- Debug suite: **294/294 tests pass**, including the complete turret → bay → core → impact sequence. ReleaseSafe app check passes. Native Apple M3 Pro / Metal, `MTL_DEBUG_LAYER=1`, 300-frame smoke completed with all stages passing and no validation messages.
- Visual review: `-Dshowcase=34` at frame 120 shows the Kestrel, active turret markers, and persistent `BROOD 1 FLAK TURRETS 4/4` HUD objective.

## Development asset reload (phase 13, slice 3) — 2026-10-01

- Baseline review: 159 ReleaseSafe tests and the application compile passed. Fixed index-only loader tickets that could access reused slots, checked pack indices before worker access, and replaced an unlocked telemetry read with a mutex-protected snapshot.
- Expanded suite: **165/165 tests pass** in Debug and ReleaseSafe; application compile checks pass. The final Debug run also verifies changed Wasm bytecode changes live output while a subsequent malformed edit retains the working module. New coverage includes stale loader tickets, repeated model replacement without pool growth, generation exhaustion, external glTF buffer edits, source/settings changes, unchanged-scan counters, wrong GUID rejection, missing-file recovery, staged script replacement and invalid-module recovery, live door state, locally edited machine preservation, rejected physical layout changes and resized crate colliders.
- ReleaseSafe model reload smoke: `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Dreload-smoke=true -Dsmoke-frames=600 -Doptimize=ReleaseSafe`. Passed all 600 frames, including four split-screen views, machine building, in-memory save/restore, city traffic and rover driving. The isolated fixture's material changed, generation advanced 2 → 3, stale handle failed, and the GPU accepted the replacement **848 ms** after the source edit. No Metal validation errors. Initially macOS was not rendering the test window; bringing it forward allowed frame progression before the timed edit.
- Full-watch ReleaseSafe smoke (`-Dhot-reload=true -Dsmoke-frames=300`) also completed: crate, all nine built-in blueprints and the installed Glowworks script staged successfully; four-player views, building and save/restore remained functional.
- The smoke writes only an isolated fixture under `zig-out/reload-smoke`; tracked asset sources and sidecars are untouched. Physical blueprint layout edits, vehicle edits, path moves and package manifest changes require restart. Live heightmaps and generated geometry remain future work.

## Wildkin anatomy and held weapon shapes — 2026-10-11

- Added joint-bound family details to all non-human forms: mammal paws, claws and a small bib; reptile/amphibian belly bands and toe claws; bird bibs and talons; and insect/arachnid thorax and limb plates. Existing species-specific heads, tails and wings remain in place.
- Held weapons now select the shared block, gem and spike meshes for individual parts. Saber blades and selected rifle barrels use tapered geometry; grips, rails and other mechanical parts retain their block shapes. No combat damage or balance values changed.
- `python3 tools/zig.py build check` passed on the default Zig 0.16/Mach pair.
- ReleaseSafe Metal art captures for `-Dshowcase=48` and `-Dshowcase=37` completed with `MTL_DEBUG_LAYER=1` on Apple M3 Pro. No Metal validation errors appeared. The lineup capture shows new paws clearly, though the heroes face away and the busy city backdrop limits face/material review. The saber capture still reads as a straightforward energy bar; this pass does not claim a finished weapon art direction.
- Headless tests, smoke, 0.17 checks, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this visual pass.

## Character appearance options and Scalari palette crash — 2026-10-11

- Expanded human hair choices to 24 cuts and styles, including short and long curl patterns, fades, coils, afro, locs, swept-back and shag shapes, plus oversized nova and alien crown spikes. Hair color has 14 choices, with a separate optional highlight color and automatic lumen highlights for synthetic characters.
- Added five face shapes and five boot designs to the persistent character profile and creator. Older profiles use classic face, no explicit hair highlight, and trail runner boots by default.
- Fixed the startup crash in `Ranger.suitTones`: two Scalari enemy profiles selected accent index 5 even though the palette has indices 0–4. Both now use index 4.
- `python3 tools/zig.py build check` and `python3 tools/zig.py build` passed on the default Zig 0.16/Mach pair. `git diff --check` passed.
- A ReleaseSafe Metal showcase capture was attempted for the nova spike style but did not finish compiling in the available session; no visual capture was inspected. Tests, smoke, Zig 0.17, cross-compiles, benchmarks, and Linux/Windows runtime checks were not run for this pass.

## Ground flora and canopy trees

- Scatter remains deterministic by seed, chunk and candidate ID. Generator version 3 adds sparse broadleaf, needleleaf and willow trees among grass, ferns and wildflowers. Each streamed chunk groups the new forms into instanced mesh draws; slope filters, biome thinning and stable removal IDs remain in place.
- Mesh-generation tests check the three ground-plant forms, shared trunk, and distinct canopy silhouettes; deterministic scatter coverage finds all six species across a fixed 100-chunk sample. `python3 tools/zig.py build test check -Doptimize=ReleaseSafe --summary all` passed **273/273 tests** and the application compile check.
- `caffeinate -d -u -t 60 python3 tools/zig.py build run -Dsmoke-frames=180 -Dcapture-frame=100 -Dcharacter-showcase=4 -Doptimize=ReleaseSafe` completed on Apple M3 Pro. Smoke logs confirmed four-player split-screen, streamed chunks, save round-trip, and generator version 3; frame 100 was captured at 2560×1600.

## Faces and skyline architecture

- Ranger profiles now select masculine or feminine presentation in the creator. The game bakes analytic eye, iris, brow, and mouth decals into a denser face mesh, while head and body proportions vary with the selected presentation. Legacy profile JSON without the new field defaults to masculine.
- Skyline towers add inset glass bays and open observatory crowns. District generator version 3 records the updated architecture rules. Tests assert glass detailing, deterministic placement, and district clearance. The ReleaseSafe 273-test run and four-player runtime smoke above passed with this upgrade.

## Hover racer and elevated sprint circuit — 2026-10-04

- The seeded elevated circuit uses the same generated route for its render mesh, ordered checkpoint gates, charge pads, and static physics collider. The road includes ramp grades, two mesh gaps, and a tessellated vertical loop; racers carry a finite boost capacitor that recharges over time and at pads. The garage HUD reports charge, gate progress, and lap time.
- Racer meshes add a front splitter, side intake louvers, canopy spines, and a three-fin diffuser. The course and collider raycast, checkpoint order, boost depletion/recharge, and app integration are covered by the test suite.
- Signed magnetic normal force and a track-relative attitude controller keep the vehicle aligned through the inverted crown. A regression test holds a racer on the inverted frame; loop geometry tests verify closure, crown orientation, and mesh density.
- Full Debug test suite passed. `python3 tools/zig.py build check --cache-dir .zig-cache-loop-check` passed. A ReleaseSafe 180-frame smoke run on Apple M3 Pro completed all stages, including hover-car fabrication and driving, four-player split-screen, save/restore, and city traffic.
- The smoke initializes the circuit but does not drive a complete loop at speed. Entry speed, boost timing, and sustained high-speed stability still need hands-on tuning.

## Persistent sprint-course best lap — 2026-10-05

- Save format 12 stores the best completed sprint lap, validates it as a finite non-negative time, restores it with the world, and displays `PB --` until a lap is recorded. The save document regression covers time round-trip and rejects negative values.
- Format 11 saves migrate with an empty best-lap record; earlier save formats remain rejected.
- Best laps update only when all ordered gates are crossed and the finish gate is reached. P1's explicit quicksave persists the record; split-screen race starts and separate player records remain future work.

## Gameplay menus, terrain map, and travel review — 2026-10-09

- Fast travel preserves traversal selection and suit resources, clears motion and guest interaction edges, and searches a bounded ground neighborhood for a gentle slope and full standing-body clearance. Obstructed destinations either find a nearby arrival or leave player/camera state unchanged.
- Menu Back restores the parent screen and row. Travel availability is shared by mouse hit handling and keyboard/controller navigation. Controller input remains in the menu route for the entire update that closes a menu.
- Map markers remain visible at the boundary with compass/off-screen labels; clustered labels are separated. Destination framing, three zoom levels, horizontal distance, and ground altitude are available.
- `python3 tools/zig.py build test check --summary all`: **353/353 tests passed**, application compile passed. Coverage includes obstructed and fully blocked travel, nested menu navigation, disabled travel, clustered/off-screen markers, and map layouts at 640×480, 853×480, and 1280×720 across every zoom and framing mode.
- Native Apple M3 Pro / Metal: `python3 tools/zig.py build run -Daudio=false -Dsmoke-frames=120` completed 120 frames and 199 simulation ticks, including co-op, vehicle motion, and save/restore stages.
- `python3 tools/zig.py build run -Daudio=false -Dshowcase=55 -Dcapture-frame=3`: captured and inspected the map, separated four-player labels, elevation/distance rows, and framing control. Local preview: `zig-out/map-review.png` (generated, not tracked).
- Physical controller playtest remains pending: judge jump buffering/coyote-time feel, grapple release, landings, camera transitions, and held-button behavior across menus. Automated traversal tests and scripted smoke do not establish subjective handling quality or hardware-specific input behavior.

## Character cel shading and ink — 2026-10-11

**What changed:** the GPU-skinned character path now has per-material cel ramps, the face shadow map on faces, a hard specular band and rim on armor and hair, emissive accent strips, and an inverted-hull ink outline (see [architecture](architecture.md)). `CelStyle` holds all tunables with four presets.

**Checked:**
- `python3 tools/zig.py build check` passes. `build test`: new tests for `CelStyle` (presets validate, bad values rejected, GPU table round-trips every material), `toon.shadeCel` (ramp ordering per material, hard specular on armor only, face map overrides N.L) and `toon.hullWidth` (equals `outlineWidth`, thinner on faces, zero for eyes) pass, as does the existing GPU-versus-CPU skinning test with the larger vertex.
- ReleaseSafe Metal captures under `MTL_DEBUG_LAYER=1` of `-Dcharacter-showcase=1` and `2` (scout and sentinel), before and after, with no validation messages. Ink reads on the silhouette and on armor plate edges; the ramp view (`-Dcel-debug=2`) shows lit, shadow and deep bands and a clean face terminator; `-Dcel-style=2` (Comic ink) gives visibly heavier lines.

The face mask view (`-Dcel-debug=4`, showcase 3) shows a clean vertical terminator with the nose wedge.

**Not checked:** the Watercolor and Flat presets were not captured; hair and Wildkin and beasts were not reviewed closely; four-player split-screen ink widths (the view pixel height is per view but only one view was captured); dusk and night; Vulkan, OpenGL and D3D12 (compile-only for the shared Zig, WGSL not compiled there); the 0.17 channel; benchmarks (the hull doubles skinned-character draws). Ink on thin geometry such as hair strands can look busy at distance. The CPU-skinned fallback path (`-Dcpu-skinning`) still uses the scene ramp and has no ink.

## Mecha armor sets and ShapeSpec review — 2026-10-11

- New: `character/armor.zig` (data-driven sets, `ArmorSetDef.validate`, rigid fitted pieces), `ShapeSpec` on hard garments, four sets (mobile_suit, buster, iron_titan, battle_plate), 16-bit armor ownership masks, four fabricator recipes. Saves: armor is stored by tag name, old tags unchanged, so `Save.format_version` is not bumped; Profile and Kit round-trip tests cover the new tags. A save with a new tag will not load in an older build.
- Tests: armor finite/rigid/winding/bounded for every set at two body sizes, fit test (fails if fitting is disabled; checked by mutation), shapes differ, determinism, validation errors, shell fin test, Ranger builds every armor over undersuit and hardsuit with open and sealed helmets while walking.
- Looked at: ReleaseFast Metal captures `-Dcharacter-showcase=30..33` (front only, creator panel overlaps the left). Not looked at: back and side views, women, the 0.9 and 1.1 heights visually, MTL_DEBUG_LAYER capture, extreme poses (pauldrons can sink into the chest when arms are raised, since plates bind to one joint). Linux, Windows and the 0.17 channel were not run.

## Mod character content is drawn (2026-10-11)

- **Changed:** `CharacterContent` schemas now map 1:1 to `ClumpDef`/`CapDef`, `FacePreset`/`HeadSpec`, `ArmorSetDef`/`Piece`/`ShapeSpec` and `CelStyle`, with per-key diagnostics from the real validators. `Ranger.initContent` draws a profile's mod face, hair (`HairSpec.custom`) and armor set; each character id has its own cel table.
- **Checked at integration:** `build check`, `build validate-mods` (emberwear and glowworks ok), `build test`: 407 of 412 pass on the base commit and 414 of 419 with this change; five pre-existing failures were recorded (armor suits count, asset Meta sidecar, Sandbox controller, Screens layout, Enemies nest). New passing tests cover: mod armor, hair and face change the mesh; missing mod and no registry fall back to the built-in mesh bit for bit; entries that stopped validating fall back; every struct field round-trips from JSON; about 50 bad values are rejected with file, key and code; a rejected mod leaves the registry unchanged; `sameAppearance` sees mod ids. ReleaseSafe Metal smoke (300 frames, validation layer) passed. ReleaseSafe captures `-Dcharacter-showcase=40` and `41` were inspected: flame crest spikes, Ember Eyes face, ink outlines, phoenix finned pauldrons and gold trim all draw.
- **Not checked:** `-Dcharacter-showcase=42` and `43`; split-screen with two players on different cel styles; Linux, Windows and the 0.17 channel (the dynamic offset on the cel bind group is new); palettes are listed but not drawn; the face limits in `CharacterContent.zig` are mine, chosen to contain every built-in preset.

## Creator framing and armor fit follow-up — 2026-10-11

- Merged the remaining Claude creator pass: responsive creator rows and section headers, automatic head close-ups on face/hair/helmet fields, reusable camera framing for character review captures, fitted visor placement based on the generated head, a sealed-helmet jaw guard, and small mecha plate proportion adjustments.
- `python3 tools/zig.py build check` passes on the default pinned Zig/Mach pair. The latest full headless suite passes 419/419; the initial run surfaced three test expectation/setup issues, corrected in `Meta.zig`, `Sandbox.zig`, and `Enemies.zig`, then rerun cleanly.
- ReleaseSafe Metal smoke passed 300 frames with `MTL_DEBUG_LAYER=1`. Creator face and armor captures rendered under Metal validation. Linux/Windows runtime checks were not run. Benchmark status is recorded with the follow-up results below.

## Integrated creator follow-up and refreshed frontier gate — 2026-10-11

- `python3 tools/zig.py build check`: passed on the default pinned Zig/Mach pair.
- `python3 tools/zig.py build test --summary all`: **419/419 passed**. Three test assumptions exposed by the first integrated run were corrected: importer version tracks the active glTF importer, the gun test selects the Weapon tool, and the nest test disables the independent Scalari training patrol.
- `MTL_DEBUG_LAYER=1 ... build run -Doptimize=ReleaseSafe -Dsmoke-frames=300`: passed on Apple M3 Pro / Metal, 300 frames, no Metal validation errors.
- Creator captures for a face close-up and the Battle Plate armor rendered under Metal validation. The full armor view reads clearly from the back; the large Super Flare hairstyle occludes much of the rear head, as designed. The creator panel remains visible in capture mode.
- `python3 tools/benchmark.py --frontier --frames 600`: all checks passed on the default pair, ReleaseFast, four views, Apple M3 Pro / Metal. Simulation P50/P95/P99: **2.430 / 3.337 / 3.967 ms**; character skinning P99: **0.129 ms**; render CPU P99: **4.799 ms**; presentation interval P50/P95/P99: **20.845 / 20.937 / 20.989 ms**; audio callback P99: **0.198 ms (1.86% of its real-time budget)**. Uploads stayed within budget (306,572 / 327,680 bytes), with no underfilled frames. GPU execution time remains unavailable.
- Linux and Windows runtime checks were not run. Their compile-only results are tracked separately in the engine alignment document; this follow-up did not change platform code.

## GLB skin preview and rig trace — 2026-10-12

- Added `asset-compiler preview-bind` for native Zig CPU evaluation of GLB skin weights and inverse-bind matrices, rendered to a diagnostic PNG. It supports the authored bind pose and the game's procedural run pose retargeted by compatible humanoid joint names. The resulting preview model is static and does not import a rig or animation into the game.
- Added joint names, indices, inverse-bind accessor references, and nearest joint-parent links to the GLB trace.
- Generated `assets/Characters/Test+Chroma (1).glb.meta` with the normal importer command, then ran `trace` and both preview poses. The report found one `Armature` skin with 65 joints rooted at `mixamorig:Hips`, zero animation clips, and each preview used 5,688 vertices / 10,064 triangles. Images: `zig-out/test-chroma-bind.png` and `zig-out/test-chroma-run.png`.
- `python3 tools/zig.py build` passed on the default pinned compiler. The normal `asset-compiler compile` rejects this skinned source with `SkinsUnsupported`, as intended until the runtime skin importer is implemented.
- **Not checked:** the game renderer, Metal validation, imported animated clips, root-motion handling, mesh editing, or mod installation. This is an offline asset-review tool slice, not a rigged-character integration.

## Captain mesh modifier authoring — 2026-10-12

- Added `asset/Modifiers.zig`: it splits a compiled mesh into disconnected triangle islands, assigns conservative position-based labels/surface suggestions, validates source identity and component IDs, and supports palette colors plus per-island scale/offset edits. The generated `tools/captain/Captain.modifiers.json` preserves the Captain type choice and an authored pauldron adjustment. The asset has 74 disconnected islands despite being one GLB primitive.
- `asset-compiler preview-modified` applied the Captain modifier file to both the bind pose and the compatible procedural run pose. Review images: `zig-out/captain-modified-bind.png` and `zig-out/captain-modified-run.png`.
- **Checked:** `python3 tools/zig.py build check` passed; `python3 tools/zig.py build` passed and installed the executable; the full headless target ran **407/420 passing, 13 failing**, with one reported allocation leak. The new modifier regression test passed (it is absent from the failing-test list).
- Existing suite failures observed in that run: Ranger sprint-to-run expectation; Catalog allocation-failure cleanup; Save character-content decoding; Sandbox salvage, canopy walk, bridge walk, city traffic, and Rootdeep interaction; Build circuit, bus-channel, and rover placement; Profile hairstyle wrap; Player grapple/flight fuel; Pets meadow spacing. Representative output: `expected .run, found .sprint`; several traversal assertions exceeded their step bounds; Save decode recursed through `CharacterContent.loadOne` until `InvalidCharacterContent`. These failures were not compared against a clean base revision, so their pre-existing status is unknown.
- **Not checked:** in-game Captain selection, runtime imported-rig rendering/animation, Metal validation, or mod installation. The mesh has one base-color material and no textures/UVs or semantic part names, so auto labels and eye/skin assignments need author review. Captain is available to the modifier authoring profile, not yet the playable Creator type picker.

## Third-person camera collision — 2026-10-12

- Third-person camera placement now raycasts from just outside the player capsule toward its desired position and shortens the arm before solid world geometry. This covers building, tree and cave colliders; terrain height still clamps the final camera position above open ground.
- Added a regression test with a wall collider in the camera path. `python3 tools/zig.py build check` passed; `python3 tools/zig.py build test --summary all` reported **408/421 passed, 13 failed**, one allocation leak. The new camera test passes; the same 13 failures listed above remain.
- `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` passed on Apple M3 Pro / Metal with 300 frames and 395 simulation ticks. ReleaseFast executable was rebuilt. Metal validation ran, but no dedicated visual capture was inspected for the camera transition.
- At the time of this camera change, the Captain modifier tool was still offline and the mesh was absent from Creator. The follow-up below connects a baked static preview to the playable selector; live skeletal animation remains unsupported.

## Captain test mesh in Creator — 2026-10-12

- Added `asset-compiler compile-modified`, which validates the GLB metadata and source hash, applies `Captain.modifiers.json`, and bakes the selected bind pose into a HWMS runtime asset. The build generates the Captain asset from the original GLB and modifier sidecar and installs it with the other compiled assets.
- Added a `CHARACTER MODEL` field in Creator. `CAPTAIN GLB (STATIC POSE)` selects the imported mesh for both the Creator preview and the player's saved character; the regular procedural ranger remains the default. The model is scaled to character height and hides correctly in first-person view.
- Save format 25 records the body style. Older profile documents default to the procedural body.
- **Checked:** `python3 tools/zig.py build check`, `python3 tools/zig.py build assets`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default Zig/Mach pair. Builds generated the source-hash-validated, modifier-baked Captain HWMS (74 islands, 5,688 vertices) and rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` captured the Creator and Captain on Apple M3 Pro / Metal; the imported model is clearly visible at character scale and Metal API validation reported no errors.
- **Not checked:** headless tests, Linux/Windows or 0.17 builds, and imported skeleton animation. This is a static bind-pose mesh; the source has no clips. Capture: `zig-out/capture.bmp`.

## Powered flight, jump combos, and modern UI type — 2026-10-12

- Free-flight mode now drives the visible ranger with a fast, camera-pitched flight vector through character collision. The traversal button exits to walking; keyboard toggle also lands at the current character position. The animation pitches the body from the hips and points both arms into flight. Sprint flight reaches 55 m/s; hands-off powered flight cruises forward at 28 m/s.
- Jump input now combines with dodge: forward + jump + dash launches a longer leap, back + jump performs a backflip, and the dash burst no longer replaces the jump animation. Triple forward dodges during a jump press do not accidentally enter sustained flight. Control labels state these combinations and identify the flight exit button.
- Replaced the 3×5 bitmap overlay glyphs with Mach's bundled Fira Sans, rasterized once into an alpha atlas. Text now retains lowercase, uses smooth linear sampling, and scales fractionally with the UI.
- **Checked:** `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. ReleaseSafe captures for `-Dshowcase=63 -Dcapture-frame=450` (flight pose) and `-Dshowcase=25 -Dcapture-frame=120` (settings text) ran with `MTL_DEBUG_LAYER=1` and were inspected; no Metal validation messages appeared. The text capture is crisp and readable at 2560×1600.
- The final `python3 tools/zig.py build -Doptimize=ReleaseFast` reinstall passed. The control screen's gesture hint names forward+shift+jump for long jump, dash+jump for the boost leap, and back+jump for the flip.
- **Not checked:** controller handling by hand, gameplay feel for dash-jump timing, the complete smoke stages, or headless tests. The flight capture is a pose review, not a control simulation.

## Detroit road and Rootway clearance review — 2026-10-12

- Tall procedural trees now keep 26 m clear of the district road decks and plazas, without changing stable scatter candidate IDs. Spawn clearings also exclude large salvage props and trees that covered the opening workshop.
- Corrected Rootway rib orientation and widened/raised its arch so repeated cross-section ribs frame the road instead of filling the gallery. Matching collision bounds leave the passage open. Metro stop canopies no longer use plaza-level columns across traffic approaches. Salvage footprints that overlap shrine rooms are omitted from the nearby scene so they cannot cover controls.
- Bumped the district generator to 8 and save format to 24; district generators 3–7 migrate with plaza and player-bridge IDs preserved. Extended the supported save window to format 12 so the documented wallet migration remains available.
- **Checked:** `python3 tools/zig.py build check` passed; all **423 headless tests** passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=64 -Dcapture-frame=120` captured and visually inspected the Rootway gallery on Apple M3 Pro / Metal. The road is clear through the ribs, and Metal API validation reported no errors. The 300-frame Metal smoke completed all nine stages, including city traffic and save round-trip; traffic and shrine-interaction regression tests passed.
- **Not checked:** Linux/Windows runtime, cross-compilation, performance benchmarks, or the 0.17 channel in this review.

## Startup title background stability — 2026-10-12

- The title camera now holds an elevated city panorama rather than orbiting through giant Arbor canopies. Gameplay simulation, pickup collection, combat, and the day cycle pause while the title is open, so the background cannot advance or change under the menu.
- **Checked:** `python3 tools/zig.py build check` passed. A 120-frame title-menu capture ran on Apple M3 Pro / Metal with `MTL_DEBUG_LAYER=1` and was inspected; the city remains framed behind the menu and no Metal API validation errors appeared.
- **Not checked:** screen-recorded temporal flicker measurement; the local display capture interface was unavailable. The title camera and gameplay state are now held stable in code.

## Mountain Wilds farmsteads and cave sanctuaries — 2026-10-12

- Added generated cabin, field barn, and rootbound sanctuary meshes to the runtime asset catalog. Seeded farmsteads appear on the cityward approach to mountain cave mouths with low crop beds; cave cache rooms carry the sanctuary and a hue-matched signal crystal. The cave heart and Hive nest layout are unchanged.
- Cave waves still cap at four active ground enemies. Each cave rolls once for an 18% rare spawn chance, choosing a Scalari hybrid or stinger in a regular trooper slot; both reuse the existing combat, loot, XP, and rendering paths.
- **Checked:** default `python3 tools/zig.py build check` passed. ReleaseSafe showcase capture with `MTL_DEBUG_LAYER=1` (`-Dshowcase=67 -Dcapture-frame=120 -Daudio=false`) completed on Apple M3 Pro / Metal; the cabin, barn, and sanctuary lineup was inspected in `zig-out/wilds-assets-review.png`, and no Metal API validation errors were reported. `git diff --check` passed.
- **Not checked:** headless tests (not run), in-cave placement during gameplay, farm route visibility across seeds, rare-spawn probability in a playthrough, collision/entry for the buildings, hands-on cave combat, benchmarks, Zig 0.17, Linux/Windows compilation or runtime.

## Wilds map markers and recurring Scalari patrols — 2026-10-12

- The world map now marks active surface nests, cave entrances, unmet Wildkin in the Wilds, catchable wildlife not yet owned by a local player, active enemy groups, and travel points. A compact legend identifies each icon; destination names remain in the selectable list, and player markers retain their labels. The default scale includes the starting ring of surface nests.
- Open-ground exploration beyond 235 m from the starter patrol can draw a Scalari miner and scout pair near the player. The pair does not appear near a live surface nest, below terrain in caves, or more than 5 m above ground. After it is cleared, another pair can arrive after 42 seconds; an ignored pair is removed after players leave its 210 m leash for 14 seconds. The starter practice route remains in its original nest slot, so saved nest identities and arena indexing do not move.
- **Checked:** `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default pinned Zig/Mach pair; the latter rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=68 -Dcapture-frame=120` captured the map on Apple M3 Pro / Metal; the capture was inspected, the destination labels no longer crowd activity markers, and Metal API validation reported no errors. `git diff --check` passed.
- **Not checked:** headless tests, in-game encounter cadence or balance, multiplayer sharing, Zig 0.17, Linux/Windows compilation or runtime, and benchmarks.

## Arcade Kestrel handling — 2026-10-12

- Keyboard steering now deflects the fly-by-wire aim while banking/pitch controls remain active; mouse aim remains supported. Reverse input applies a strong air brake. Shift boost drains a 2.6-second reserve, which recharges at 0.55 seconds per second when released; holding it after depletion keeps moderate engine thrust. The dodge binding starts a 0.85-second barrel roll, which absorbs flak and stinger hits and prevents ram damage to the Kestrel while preserving target ram damage.
- Updated the boarding prompt, Controls label, and flight HUD with steering, boost reserve, and roll state. Existing cannon/missile lock and release fire remain unchanged. No playable spacefighter or orbital combat scene exists yet; this pass only changes the atmospheric Kestrel.
- **Checked:** `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed; the latter rebuilt the installed executable. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=34 -Dcapture-frame=120` captured the Kestrel dogfight HUD on Apple M3 Pro / Metal; the image was inspected and Metal API validation reported no errors. `git diff --check` passed.
- **Not checked:** headless tests, hands-on keyboard/controller flight, barrel-roll animation/evade timing, boost/brake feel, Zig 0.17, Linux/Windows compilation or runtime, and benchmarks.

## CLI mesh modifier authoring — 2026-10-12

- Expanded the source-hash-linked Captain modifier document into a usable headless authoring flow. `modifier-list` exposes stable island IDs and spatial context; `modifier-edit` writes one validated change to a separate document and supports part labels, material roles, explicit colors, per-island scale/offset, and shared skin/eye/armor/energy palettes. Invalid values are rejected before output; exact same-path input/output is rejected.
- **Checked:** `python3 tools/zig.py build check`, `python3 tools/zig.py build install`, and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed on the default compiler; ReleaseFast reinstalled the game. The generated Captain is still 74 islands / 5,688 vertices. Manually listed all IDs, edited label 912, changed the armor palette and scaled that pauldron in separate output documents, then rendered `zig-out/Captain.custom.png`; image inspected successfully. An out-of-range scale and an input-equals-output edit were both rejected. `git diff --check` passed.
- **Not checked:** headless tests, a graphical Mach viewport (there is no standalone GUI target yet), click/face selection, undo/redo, editing a live rig or textures, 0.17, Linux/Windows, or an in-game custom modifier install. This is command-line sidecar authoring only.

## Mesh editor, runtime rigs, and animation capture status — 2026-10-12

- At that earlier review point, the modifier work had added offline CLI commands but no standalone editor. The next section records the editor implementation added afterward. [The editor plan](plans/mesh-editor.md) tracks remaining work.
- Corrected the rig status: the GLB trace and CPU bind/run preview understand skin data for review; `HWMS` remains static and runtime gameplay still uses the game's procedural rig. Captain's source has 65 joints, one more than the current GPU palette; preserve it and start with CPU skinning for imported rigs. [Skeletal animation](plans/skeletal-animation.md) records the integration boundary.
- Added a staged design for user animation capture: begin from repeatable local video, turn pose tracks into editable canonical motion, then add local webcam capture behind a platform boundary. The repository currently has no webcam/video input. [Animation capture](plans/animation-capture.md) records privacy, quality limits, and dependencies.
- **Checked:** documentation/source status review only; no code or platform build changed in this clarification.
- **Not checked:** any visual editor, runtime imported rig, camera capture, pose estimator, or video-to-animation prototype.

## Standalone mesh editor first UI — 2026-10-12

- (Historical: this file was deleted again in commit `f4e7bea`.) Added `src/MeshEditor.zig` as an independent Mach app and `mesh-editor` / `mesh-editor-build` build steps. It loads the source Captain GLB plus its sidecar without starting gameplay simulation, lists all 74 disconnected islands, and supports list/click selection, rename, component scale/color, sidecar save, orbit/zoom and bind versus compatible procedural-run pose preview.
- Added `Catalog.replaceHandle` for transactional preview mesh replacement with a generation bump, so edited geometry uploads as a new mesh while the renderer rejects stale handles.
- **Checked:** `python3 tools/zig.py build mesh-editor-build`, `python3 tools/zig.py build check`, `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build mesh-editor-build`, and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build mesh-editor -Dcapture-frame=3` passed; captured frame 3 at 2880×1800 and inspected it. The front-view Captain mesh and editor panels were visible, and Metal emitted no validation errors. The editor opens the source GLB and uses `Modifiers.apply` against the source-linked sidecar for its viewport. `git diff --check` passed.
- **Not checked:** interactive rename/color/scale behavior during a live session, regular-game `build check`, headless tests, runtime imported skeletal rendering, glTF animation-channel import, retargeted authored clips, webcam/video input, or pose estimation. The run-pose toggle is still an offline CPU-skinned static preview; `HWMS` contains no rig. No modifier sidecar was edited during validation.

## Imported components in Character Designer — 2026-10-12

- The separate editor target was replaced with an **IMPORTED PARTS** window in the game's Character Designer. It browses all 74 Captain mesh islands across surface categories; supports changing a component's surface role, painting or clearing it from a palette, hiding/restoring it, and adjusting skin/eye/armor/energy RGB values.
- The editor loads a saved override from `saves/captain.modifiers.json` or falls back to the checked-in import recipe. **SAVE LIBRARY** writes only to the save path. Preview refresh starts from an immutable copy of the build-baked mesh and changes colors/component indices under the render mutex, avoiding repeated transforms and stale GPU mesh generations.
- Removed the separate `mesh-editor` application/build steps. Offline `asset-compiler` commands remain for GLB import, advanced transforms and diagnostics; runtime skeletal import and webcam capture remain future work.
- **Checked:** default `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` captured the Character Designer at 2560×1600 on Apple M3 Pro / Metal; I inspected the component browser, RGB controls, Back and Save buttons, and saw no Metal validation errors. `python3 tools/zig.py build -Doptimize=ReleaseFast` rebuilt `zig-out/bin/heavy-water`. `git diff --check` passed.
- **Not checked:** headless tests, hands-on component edits, saved override behavior across a full restart, Linux/Windows, live runtime rig/clip import, and webcam capture.

## In-game GLB character import and controller retarget preview — 2026-10-12

- Added an **IMPORT GLB** action inside Character Designer → **IMPORTED PARTS**. On macOS, the file panel reads a binary GLB up to 64 MB. Skinned GLBs are imported through the native CPU skin preview, and recognized Blender/Mixamo/Unity-style humanoid joint names map to the game's locomotion run tracks. The panel reports the mapped track count.
- The imported controller pose is currently baked into the game's static character mesh. Source GLB and appearance sidecar persist under `saves/imported-character.glb` and `saves/imported-character.modifiers.json`, then reload at startup. A new import replaces that one imported-character slot; it does not overwrite the bundled Captain source.
- **Checked:** default `python3 tools/zig.py build check`, `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check`, and `git diff --check` passed.
- **Not checked:** no interactive file-picker import, screenshot/capture, restart persistence check, headless tests, Linux/Windows targets, authored glTF animation clips, or live skeletal gameplay playback. The renderer/gameplay asset is still HWMS static geometry; unsupported joint names do not receive locomotion motion, and external-buffer `.gltf` is not accepted by this picker.

## Homing ki blast and aerial combat pass — 2026-10-12

- Promoted the charged blaster to the starting ranged weapon, labeled **KI BLAST** in the HUD, and redesigned its held form as a palm-mounted emitter. Its sphere retargets the nearest Hive unit within 80 m, grows and gains splash reach with charge, and bursts with area damage and knockback/stun.
- Connected existing flight and dash states to the attack: airborne blasts fly faster and dash-fired blasts also deal more damage and create a stronger impact. The projectile uses the ranger's accent color, a layered luminous core/shell/trail, and the blaster adopts a two-hand cast pose while charging.
- **Checked:** default `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check` passed. The final showcase adjustment compiled in `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=69 -Dcapture-frame=90`, which completed on the Apple M3 Pro with Metal API validation and saved a 2560×1600 capture. The capture confirms the weapon HUD and showcase load, but the shot is not visible: the camera framing obstructs it and the charge is mid-cycle. This is not visual approval of the projectile. `python3 tools/zig.py build -Doptimize=ReleaseFast` installed the final executable; `git diff --check` passed.
- **Not checked:** headless combat suite and hands-on flight/aim feel. Splash radius, lock-on turn rate, damage bonus, showcase framing, and projectile visibility still need play tuning.

## Old-growth Arbor and giant pine surface pass — 2026-10-12

- Added layered world-space bark grain, fissures and lichen, plus distance-faded leaf and needle color breakup. The material tags apply to procedural Arbors, the hand-authored test Arbor, and streamed tree species; the test Arbor now carries a redwood crown at canopy height.
- Promoted variant 14 from a small pine prop to an old-growth pine with descending irregular bough whorls. It now uses the same 96–150 m scatter tier as the other giant trees, while its procedural mesh keeps open gaps between branch fans.
- **Checked:** `python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=62 -Dcapture-frame=120 -Daudio=false` completed on Apple M3 Pro / Metal without API validation errors. The final capture was inspected, but its camera showed bare terrain rather than the staged trees, so it does not verify the new tree appearance. `git diff --check` passed.
- **Not checked:** the tree forms in regular gameplay or at multiple distances, headless tests, the 0.17 channel, Linux/Windows compilation or runtime, and performance. The canopy and pine silhouettes still need a clear in-game visual review.

## Forest-floor and canopy branch refinement — 2026-10-12

- Reduced the share and scale of grass and ferns so they read as low understory accents instead of crowding the camera; kept large tree scale and flower variety. Replaced the generated Arbor's flat triangular crown clusters with rounded, softly lobed foliage. Added a space-colonized branch skeleton through the Detroit test Arbor's crown so the foliage connects back to the trunk. The flora review camera now frames the staged lineup, and showcase 70 gives a trunk-to-crown view of the test Arbor.
- Updated the world guide to call for connected structural limbs, branch-supported patios and warm-lit canopy neighborhoods, with open visibility at ground level.
- **Checked:** default `python3 tools/zig.py build check` and `python3 tools/zig.py build -Doptimize=ReleaseFast` passed; ReleaseFast reinstalled `zig-out/bin/heavy-water`. `MTL_DEBUG_LAYER=1` ReleaseSafe captures ran for showcase 62 (giant flora) and showcase 70 (Detroit test Arbor) on Apple M3 Pro / Metal; both completed without Metal API validation errors. The captures were inspected: the flora lineup is in frame, and the test Arbor's major limbs now visibly join the trunk and crown. `git diff --check` passed.
- **Not checked:** headless tests, gameplay across seeds, hands-on upper-canopy traversal, Zig 0.17, Linux/Windows, and performance. Upper branch collision paths and the small canopy neighborhoods remain open; the current three-city course and the test Arbor's lower ramp/bridge remain the playable routes. The views are still stylized and do not yet show fine leaves or lit homes at canopy scale.

## Pine foliage and forest-floor grass reduction — 2026-10-13

- Reduced long grass and fern candidates from roughly two thirds of scattered plants to 15%; rounded shrubs and flowering natives now make up most of the forest floor. Replaced both giant and young pine's flat blade-shaped boughs and sprays with tapered round branch segments and compact needle clusters, which keep scaled foliage from resembling oversized grass.
- **Checked:** default `python3 tools/zig.py build check`, ReleaseFast `python3 tools/zig.py build -Doptimize=ReleaseFast` (rebuilt the installed executable), and `git diff --check` passed.
- **Not checked:** Metal capture/visual inspection, headless tests, gameplay across seeds, Zig 0.17, Linux/Windows, or performance.

## Conifer branch and needle pass — 2026-10-14

- Gave the shared L-system explicit conifer grammars for needleleaf and giant pine. The pine now grows three-direction branch whorls around the trunk, with longer outward boughs and downward secondary growth. Fine radial needle sprays attach along boughs as well as at their tips. Broadleaf leaf fans retain their ovate shape, and exposed branch ends taper rather than stopping flat.
- Added `-Dshowcase=74` for a fixed-midday close view of the giant pine; showcase 62 now also holds midday light for species comparisons. The close view makes branch and needle tuning repeatable.
- **Checked:** default `python3 tools/zig.py build check` and `git diff --check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=74 -Dcapture-frame=120 -Daudio=false` completed on Apple M3 Pro with Metal API Validation enabled and no reported API errors. The final capture was inspected: pine boughs form a wider, tiered crown and carry needle clusters along their length.
- **Not checked:** headless tests (not run), gameplay across seeds, triangle/performance benchmarks, Zig 0.17, Linux/Windows compilation or runtime, or hands-on traversal among the trees. The pine crown remains deliberately open enough to read individual bough tiers; branch spread and canopy density need a gameplay-distance review.

## Species foliage and branch visibility review — 2026-10-14

- Fixed deciduous leaf-card orientation: each blade follows its twig and faces outward around the twig axis, so upright branches no longer present most leaf fans edge-on. Added ovate, lanceolate, scale, fan, cascade and blossom profiles; increased recursive branch density for willow, copper-fan, moon-cascade and star-blossom; and changed redwood to balanced radial forks with a denser scale-leaf crown.
- Added `-Dshowcase=75`, a close midday view of moon-cascade, alongside the species lineup at 62 and pine close-up at 74. Capture 75 visibly shows leaves attached along boughs. The final 62 capture shows several distinct foliage silhouettes and the denser redwood crown; needleleaf and moon-cascade still read sparse at the wide lineup distance, so gameplay-distance coverage needs more tuning.
- **Checked:** `python3 tools/zig.py build check` and `git diff --check` passed on the default Zig 0.16/Mach pair. ReleaseSafe captures for showcase 75 and 62 at frame 120 completed on Apple M3 Pro with Metal API Validation enabled and no reported validation errors; both captures were visually inspected.
- **Not checked:** headless tests (not run), performance benchmarks, regular gameplay across seeds, Zig 0.17, Linux/Windows compilation or runtime, or hands-on play among the revised trees. The capture proves generated mesh visibility in the fixed showcases, not final art approval or frame cost at forest density.

## Mesh modifier hardening and baseline — 2026-10-14

- Completed M0 from [the mesh editor engineering plan](plans/mesheditor.md). `Modifiers.zig` now shares palette resolution through `partColor`, resolves sidecar part ids through a sorted binary-search slot index, and binary-searches the sorted analysis components. Added regression coverage for rejected edits, missing components, filtered submesh ranges, and allocation failures in both `apply` and `recolor`. Added the `modifier-bench` build step for synthetic connected meshes.
- **Measured:** `python3 tools/zig.py build modifier-bench` (Zig 0.16 ReleaseSafe), timings in ms (`analyze / apply / recolor`): 100k vertices, 50 parts **4.006 / 5.876 / 4.847**; 100k, 500 parts **4.083 / 7.591 / 5.936**; 1M, 50 parts **39.428 / 59.978 / 50.400**; 1M, 500 parts **39.727 / 74.741 / 58.998**. Under the same ReleaseSafe benchmark step on Zig 0.17: 100k/50 **1.447 / 3.442 / 2.404**; 100k/500 **1.571 / 5.256 / 3.528**; 1M/50 **15.194 / 36.911 / 26.151**; 1M/500 **15.283 / 53.543 / 35.912**. These are single-run baselines, not statistically sampled comparisons.
- **Checked:** default `python3 tools/zig.py build check`; `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check`; both compiler channels' `modifier-bench` steps; `git diff --check`. The full default headless suite completed **427/431 passing**. All new `Modifiers` tests passed. Four unrelated tests failed: `asset.Catalog.test.deferred meshes reserve handles at load and install once, later` (expected 5, found 6), a `game.Save` v12 migration decode (`Malformed input`), `game.Creator.test.creator edits a draft...` (height expected 1.02, got 1), and `ui.Screens.test.every screen lays out inside the window and records hits` (expected 35, found 25).
- **Not checked:** baseline results are not a before/after comparison; benchmark variance and Linux/Windows runs were not measured. No rendering code changed, so no Metal smoke was run. M1 welding and its GLB fixture are recorded in the following entry.

## Weld-aware mesh islands and v1 compatibility — 2026-10-14

- Completed M1 from [the mesh editor engineering plan](plans/mesheditor.md). New modifier documents use format 2 with a saved 0.1 mm `weld_cell`; welding joins split vertices by quantized position before triangle connectivity. Format 1 documents without the field retain index-only analysis. Added [a split-corner cube GLB fixture](../src/asset/seam_cube.glb), imported through `Gltf.compile`: old analysis finds six face islands, welded analysis finds one shell. An unsplit indexed shell preserves its ids.
- The Captain GLB does contain coincident split positions, so the planned assumption that its welded and unwelded ids match was false. Its checked-in format 1 sidecar was instead tested through `apply` and still matches the original 74-part analysis. The in-game override check accepts legacy format 1 against newly generated format 2 source metadata when the source hash matches; bake-time component validation remains authoritative.
- **Checked:** default and `HEAVYWATER_ZIG_CHANNEL=0.17` `build check`; the direct modifier dependency test run passed **26/26 on both compiler channels**; full default headless suite **431/435 passing**. Four unrelated failures remain: Catalog expected 5 pending meshes but found 6; Save v12 migration returned `Malformed input`; Creator got height 1 instead of 1.02; Screens found 25 rows instead of 35. `git diff --check` passed.
- **Not checked:** interactive loading/saving of a legacy imported-character override, Linux/Windows builds, or rendering. The seam fixture is covered in headless import and analysis tests; no rendering code changed, so no Metal smoke was run. Next is M2 reversible commands and history.

## Reversible mesh-editor commands and history — 2026-10-14

- Completed M2 from [the mesh editor engineering plan](plans/mesheditor.md). Imported-part changes now use validated before/after commands for surface, part paint, enabled state, palette colors, scale and offset. The fixed 64-entry history discards the redo tail after a new edit, coalesces continuous scale/offset changes, and exposes keyboard (`z`, `shift-z`) plus panel Undo/Redo controls and a history counter. Undo/redo route through the same validation path; imports clear history when replacing the document.
- Added tests for byte-identical undo and redo across all command kinds, history coalescing and redo-tail discard, rejected-command transactionality, and Creator keyboard edit/undo/redo.
- **Checked:** default and `HEAVYWATER_ZIG_CHANNEL=0.17` `build check`; both full headless suites **434/438 passing** (all new tests pass on both). The same four existing failures appear on both channels: Catalog expected 5 pending meshes but found 6; Save v12 migration returned `Malformed input`; Creator height expected 1.02 but got 1; Screens expected 35 rows but found 25. `MTL_DEBUG_LAYER=1` ReleaseSafe capture of `-Dcharacter-showcase=46 -Dcapture-frame=120` completed on Apple M3 Pro and the imported-parts panel was visually inspected. The 300-frame ReleaseSafe Metal smoke completed with all scripted stages and Metal API Validation enabled. `git diff --check` passed.
- **Not checked:** interactive mouse/keyboard use beyond the Creator unit path was not manually exercised. Linux/Windows builds and runtime remain unmeasured. Next is M3 incremental bake and preview.

## Incremental mesh-editor bake and preview — 2026-10-14

- Completed M3 from [the mesh editor engineering plan](plans/mesheditor.md). `Modifiers.Bake` caches a pristine model, analysis, sorted part slots, and compressed per-part vertex/triangle lists. Creator dirty tracking feeds a renderer patch queue; the first preview uploads the full bake, while appearance or visibility edits write only changed vertex runs and triangle triplets. Hiding degenerates each affected triangle in place, keeping index count and submesh ranges stable. Runtime preview currently covers surface, palette color and visibility edits; scale/offset remain in the offline full bake path.
- Added an incremental/full comparison test over 18 surface, color and enabled-state changes. It checks the incremental output against a fresh full `recolor` result. `modifier-bench` now also measures one-part `Bake.updatePart` updates (1000 repetitions, `analyze / apply / recolor` in ms, `part_update` in µs):

  | Compiler | Vertices / parts | Analyze | Apply | Recolor | Part update |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | Zig 0.16 | 100k / 50 | 4.115 | 11.692 | 10.933 | 3.52 |
  | Zig 0.16 | 100k / 500 | 3.889 | 12.850 | 11.189 | 0.33 |
  | Zig 0.16 | 1M / 50 | 40.990 | 139.713 | 126.156 | 34.16 |
  | Zig 0.16 | 1M / 500 | 41.122 | 147.723 | 133.843 | 3.52 |
  | Zig 0.17 | 100k / 50 | 1.474 | 6.760 | 5.781 | 3.46 |
  | Zig 0.17 | 100k / 500 | 3.143 | 10.224 | 7.112 | 0.33 |
  | Zig 0.17 | 1M / 50 | 15.115 | 79.652 | 71.868 | 32.99 |
  | Zig 0.17 | 1M / 500 | 15.159 | 95.158 | 81.704 | 3.40 |

  Timings are single-run synthetic results; the selected part sizes differ across part counts, so `part_update` is expected to vary with that size. It confirms the update is bounded by the part's vertices/triangles rather than a full mesh recolor.
- **Checked:** default `python3 tools/zig.py build check` and `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check`; both headless suites **435/439 passing**, including the new bake test. The same four existing failures remain on both channels: Catalog expected 5 pending meshes but found 6; Save v12 migration returned `Malformed input`; Creator height expected 1.02 but got 1; Screens expected 35 rows but found 25. `MTL_DEBUG_LAYER=1` ReleaseSafe 300-frame smoke completed on Apple M3 Pro / Metal, exercising partial hide and restore patches with Metal API Validation enabled and no reported API errors. Both compiler channels' `modifier-bench` steps passed; `git diff --check` passed.
- **Not checked:** no manual interactive editing session, Linux/Windows builds or runtime, or multi-asset library behavior. The incremental equality test covers appearance and visibility, not transforms; transforms are not yet exposed by the runtime editor. Next is M4 library and stale-source handling.

## Imported GLB type visibility, preview, and armor RGB — 2026-10-12

- Added a distinct **IMPORTED GLB** character model choice separate from the bundled Captain. Import selects it immediately, and the in-world Creator avatar is the live preview while editing the imported component document; the panel now identifies preview state and component count. The importer and startup loader continue using the same source-hash-backed generation path and single replaceable saved slot.
- Added nine RGB channel controls for native armor metal, secondary, and trim colors. Unedited channels use the selected set's authored defaults; edited values serialize in the existing profile document and are consumed by native armor mesh generation.
- **Checked:** default `python3 tools/zig.py build check`, ReleaseFast `python3 tools/zig.py build -Doptimize=ReleaseFast` (rebuilt the installed executable), and `git diff --check` passed.
- **Not checked:** interactive GLB picker/import, preview appearance, armor color appearance, restart persistence, headless tests, Metal capture/validation, Zig 0.17, Linux/Windows, or benchmarks.

## Live imported-character skinning — 2026-10-15

- **Changed:** retained glTF skin influences and inverse-bind data in HWMS v3, keeping v1 and v2 readers; imported vertices now carry the glTF bind pose, and `Characters` applies each mapped Ranger joint’s live pose palette on the GPU. Added a bundled 65-joint humanoid GLB fixture, expanded the palette to 128 joints, and kept the Character Designer’s bind/run previews as static thumbnails. The renderer requires the GPU skinning pipeline for imported rigs.
- **Checked:** default `python3 tools/zig.py build check`; full headless suite **454/454 passed**; `git diff --check`. `MTL_DEBUG_LAYER=1` ReleaseSafe gameplay captures completed on Apple M3 Pro at frames 1 and 120 with Metal API Validation enabled. Both were visually inspected: the imported mesh stays intact in its idle pose and changes into the gameplay pose; no Metal API errors were reported.
- **Not checked:** source-authored animation clips, rigs with multiple skins, non-rigid inverse-bind transforms, Linux/Windows runtime, or CPU skinning for imported rigs. Retargeting supports one skin up to 128 joints and maps the seven named Ranger gameplay joints; other source joints follow their nearest mapped ancestor or the root.

## Imported-rig review follow-up — 2026-10-15

- **Fixed:** HWMS v2 now reads its original 36-byte bind-dual-quaternion bone records and keeps their prior runtime palette behavior; v3 continues to use 16-byte source pivots. The v2 regression fixture now uses the legacy record size instead of relabeling v3 bytes. The glTF reader now accepts normalized UBYTE/USHORT skin weights. Unskinned accessory primitives are bound to a synthetic root influence and keep their baked node transform.
- **Checked:** default `python3 tools/zig.py build check`; full headless suite **457/457 passed**; the 300-frame ReleaseSafe smoke completed with Metal API Validation enabled on Apple M3 Pro. The `-Dcharacter-showcase=47 -Dcapture-frame=120` capture completed at 2560×1600 and was inspected: the imported humanoid mesh remained intact in its pose, with no Metal API validation messages. `git diff --check` passed.
- **Not checked:** runtime playback of an actual HWMS v2 imported character. The legacy reader, retained DQ palette composition, and re-import error are covered by format-level checks, but the bundled runtime showcase exercises a v3 rig.

## Double-jump air-assist control — 2026-10-16

- **Changed:** walking jump now launches normally. Air assist requires a fresh jump press after takeoff and stops when that press is released; holding the takeoff jump no longer starts the jetpack. Falling from a ledge alone does not grant the second press.
- **Checked:** default `python3 tools/zig.py build check`; full headless suite **458/458 passed**, including takeoff/held-input/second-press/release/ledge-fall coverage; the 300-frame ReleaseSafe smoke completed on Apple M3 Pro with Metal API Validation enabled and no reported validation errors. `git diff --check` passed.

## Wilds combat density and map tracking — 2026-10-16

- **Changed:** surface nests can sustain ten enemies, including five walking troopers; cave nests can sustain eight ground fighters. Each city bomber assault spawns a six-unit Scalari squad. The character renderer now has sixteen slots for nearby ground enemies while retaining eight slots for Wildkin. The world map tracking row cycles through live nests, caves, unmet Wildkin and wildlife the selected player can still capture; it centers and highlights the nearest target. During play, a compass bearing and distance appear on the HUD.
- **Checked:** default `python3 tools/zig.py build check`; full headless suite **460/460 passed**, including map target cycling, far-unit slot reclamation, and the five-trooper nest wave; `git diff --check`. A 300-frame ReleaseSafe smoke completed with Metal API Validation enabled. A showcase 76 capture also completed in the shared workspace. **Not checked:** interactive city/cave combat pacing or live map navigation.
## Captured Detroit and New York campaign direction — 2026-10-19

- **Changed:** the story and world bible now establish Detroit and New York City as Hive-occupied fronts in a spreading Earth assault. The Eight Synthetic Siblings and a new generation of synthetic humanoid warriors fight beside humanity and help lead its future as trusted partners. Detroit remains the first complete city liberation loop; New York follows after that loop is proven. Added a New York occupation hook to the city content outline and clarified that its current travel foothold does not yet implement the occupation.
- **Checked:** documentation edits reviewed; `git diff --check`.
- **Not checked:** no game code changed, so no build, tests, smoke, visual review, or hands-on gameplay was run. Both cities' in-game Hive occupation and all liberation content remain unimplemented.

## New York terrain region and travel smoke — 2026-10-19

- **Superseded later that day:** the terrain-heightmap commit moved New York to x 250,000 and made its region and arrival data in `Worlds.zig` (`RegionData`); the chunk numbers, x 1320 arrival and five landmarks below are the state when this entry was written. The seed-per-region collision fix and the smoke travel check still apply.
- **Bug found and fixed:** New York's regional terrain seed applied to chunks 19..23 by -5..-1, written when chunks were 64 m. Chunks are now 128 m, so the arrival at x 1320, z -180 and all five skyline landmarks sat in chunk 10, -1 and got Detroit's terrain. Separately, physics (`Terrain.surface`, river queries) always used the world seed, so even inside the region collision would not have matched the mesh. The region is now chunks 9..12 by -3..0 (`Chunk.regionalSeed`), and `Terrain.surface` and the player's river query pick the regional seed themselves, so callers pass the world seed. Scatter and the Sandbox share the one salt constant.
- **Smoke:** stage 1 now fast-travels to every destination (including New York, which stays loaded for the following frames) and fails if New York's arrival is more than 2 m off the ground.
- **Checked:** default `build check` and Zig 0.17 `build check` passed; the headless suite passed 469/469, including a new test that terrain queries equal the regional chunk mesh; the Metal smoke with `MTL_DEBUG_LAYER=1` passed and logged all seven arrivals (New York at 1322, 15, -184).
- **Region table (G1 first slice):** [src/world/Region.zig](../src/world/Region.zig) now holds New York's title, salt, chunk bounds and arrival; `Chunk`, `Scatter`, `Terrain`, the Sandbox arrival and the world-map title read it, and the map now colours each sample with the seed of the region it falls in. Two new tests check that every region contains its arrival and that regions do not overlap. After the refactor: default and 0.17 `build check` pass, the suite passes 471/471, and the Metal smoke passes. Travel destination indices, labels and the menu rows are still hard-coded in `Sandbox`, `Menu` and `Screens`.
- **Second bug, found while making the map data-driven:** the world-map handler for "cycle tracked target" was hard-coded to row 6. When New York became row 6, Enter on it cycled the tracking target instead of travelling, and the tracking label drew over its row, so New York could not be reached from the menu (the suite called `fastTravel` directly and never saw it). The map rows now come from `Sandbox.travel_menu_labels`, `Menu.frame_row` is `travel_count`, and a Menu test confirms every destination row returns `travel` and only the frame row cycles the target (it would fail on the old code). Suite 472/472, default and 0.17 `build check` and the Metal smoke pass. Not checked: clicking the New York row in a window by hand.
- **Not checked:** the new Terrain test was not run against the old region range to see it fail on its own; a visual capture of New York; cave openings in the region still use the world-seed cave layout (`Caves.hollow`), so a cave mouth carved into New York terrain would not collide; Linux and Windows cross-compiles.

## GLB character editor preview visibility — 2026-10-19

- **Changed:** dock the imported-character library on the right, narrow its component list to fit, and offset the frozen in-game character into the exposed left preview area while the editor is open. Paint and skinning use the existing live game renderer and retargeting path.
- **Checked:** `python3 tools/zig.py build check`; `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dcharacter-showcase=46 -Dcapture-frame=120` completed on Apple M3 Pro / Metal without validation messages. Inspected the 2560×1600 capture at `/tmp/glb-editor-review4.png`: the avatar is visible beside the editor. Showcase 47 rendered the bundled 65-joint Mixamo GLB through the game's skinning path with Metal validation enabled. `python3 tools/zig.py build -Doptimize=ReleaseFast` installed the updated executable; `git diff --check` passed.
- **Not checked:** no automated tests or hands-on import/paint interaction were run. Showcase 46 uses the bundled Captain body; the user's specific GLB and its joint-name compatibility were not available, so its import and rig mapping remain unverified.

## Hive siege bases around the occupied cities — 2026-10-19

- **Changed:** added a procedural Hive fortress mesh: dark synthetic stone, ribbed elongated egg tower, large perimeter walls with an open gate, glowing seams, and four outward-facing laser cannon emplacements. Living surface nests now use the fortress; cave nests keep their compact spire. Three installations sit around Detroit Arbor Reach and four around New York's playable regional bounds.
- **Checked:** default and `HEAVYWATER_ZIG_CHANNEL=0.17` `python3 tools/zig.py build check` passed; `git diff --check` passed.
- **Not checked:** headless tests, Metal capture/API validation, and hands-on placement/combat. The showcase capture did not complete because another `heavy-water` process was already running in the shared workspace; it was left untouched. City installations are visual siege landmarks; their turrets do not fire yet, and city liberation progression remains unimplemented.

## Detroit and New York terrain rasters — 2026-10-19

- **Changed:** added 16-bit grayscale PNG heightmap import and read-only `HWMH` sampling. The Detroit raster shapes a 120 km region around the existing Detroit arrival (380 m relief). The NYC raster shapes a 160 km region aligned to a low coastal pixel near the Hudson Reach arrival (700 m relief); that region now streams around world position 250 km east of Detroit. Both use a 9 km blend to seeded terrain, and chunk meshes, scatter placement, and `Terrain.surface` share the map sampler. Approximate placement and raised relief aim for a recognizable, fun version of the 1,500-years-future terrain. LA and Chicago source maps are untouched for later regions.
- **Checked:** generated both runtime `HWMH` assets with the repository's pinned asset compiler; `python3 tools/zig.py build check` passed.
- **Not checked:** 0.17 build, headless suite, Metal capture/visual review, and hands-on terrain/collision. Georeferencing was absent, so city extents, pixel alignment, elevation scales, and coast/water interpretation are estimates. Water rendering does not yet consume the maps.

## Imported-mesh editing core (E1) — 2026-10-19

- **Added:** `src/asset/MeshEdit.zig`, the headless core of the imported-mesh overhaul: welded topology, ray-triangle picking, vertex selection, soft-selection move, draw/inflate/smooth/paint brushes, stroke undo/redo of vertex and triangle changes, and extract/separate to tear selected faces off as a standalone `Model`. Plan and audit are in [mesh editor](plans/mesheditor.md) section 0.
- **Checked:** its 7 tests (plus the `Model` tests it pulls in) pass on the default compiler and on Zig 0.17, run directly with `tools/zig.py test`; tests cover welded corner picking, falloff, normals after a move, one-step undo/redo, seams staying closed under inflate, a part that encodes and decodes as HWMS, reversible separate, and every allocation failure in setup.
- **Not checked:** nothing in the game calls it yet (no viewport, UI or save); no performance measurement on large meshes (`dab` and `prepareSoft` scan every vertex; `prepareSoft` compares against every selected vertex); the extract recentring of skinned parts is skipped by design and untested on a real rig.

## Controls tabs and regional player map — 2026-10-19

- **Changed:** controls now show keyboard and gamepad tabs with direct switching between their existing remapping panels. Selecting a fast-travel destination centers the map on its marker; an added zoom level spans regional travel distances so local players can be found across Detroit and NYC.
- **Checked:** `python3 tools/zig.py build check` passed.
- **Not checked:** headless suite, Metal smoke/capture, and hands-on keyboard/gamepad navigation or map readability.

## Detroit skyline scale and crown skyways — 2026-10-19

- **Changed:** the seeded Detroit skyline now targets about twenty 2,500–3,500 ft towers, with a nearest-link network joining the high-rises plus a three-link market loop; lower factory blocks stay in the ground city. Roof gardens, kiosks, broad terraces, stone-and-glass palettes, hanging ivy, gate pylons, suspension cables and hangers share the district render/collision mesh. NYC's visual skyline now has twenty large landmarks with varied stone colors and planted roofs; they remain scene props without collision or connected skyways.
- **Inspected:** the Detroit, NYC and LA rasters are 2048×2048, 16-bit grayscale PNGs. NYC is already sampled by `CityHeightmaps` for both chunks and physics/placement queries; the image contains a broad dark water channel and raised landforms, but no georeferencing metadata, so the current 160 km placement and 700 m relief are still approximate. No Chicago heightmap asset is present under `assets/`.
- **Checked:** default `python3 tools/zig.py build check` passed. `MTL_DEBUG_LAYER=1` ReleaseSafe showcase 7 captured frame 120 and exited cleanly; Metal API Validation was enabled. The overview keeps the ground city and existing road bridges visible beneath the megatowers, but it does not clearly show the crown route at this camera distance.
- **Capture recheck:** after excluding low factory roofs from the skyway graph, a repeat showcase run initialized Metal but did not reach frame 120 within about three minutes; I stopped it. The successful capture above predates that graph filter.
- **Not checked / next:** hands-on walkability on the crown loop, Hive patrols on the elevated routes, civilian panic/evacuation behavior, and headless tests. The existing prefab elevator already has a ride-to-landing smoke test, but the tower ascent route is not yet connected as a complete playable path. Chicago cannot be imported until its source raster is added.

## Floating platform editor — 2026-10-20

- **Added:** the initial editor was opened with O in the build tool. The current entry path is Pause → BUILD → STRUCTURES → FLOATING PLATFORM. The popup offers horizontal and vertical 16 m square decks and 1 m / 10 m height adjustments from the aimed surface, clamped to −1,000…+1,200 m. Platforms are saved as ordinary body-plate machines. Their placement preview renders the body device and permits unsupported placement at the chosen offset; overlap and player collision checks still apply. P remains prefab capture.
- **Checked:** default `python3 tools/zig.py build check` and `git diff --check` passed. `MTL_DEBUG_LAYER=1` ReleaseSafe showcase 80 captured frame 120 and exited cleanly with Metal API Validation enabled; the popup is readable and the aimed platform preview is visible, red where it overlaps nearby geometry.
- **Not checked:** hands-on input and placement, save/reload in the game, and headless tests. The existing elevator ride test remains the current evidence for elevator operation; it does not prove a continuous ascent route through the new skyline.
- **Still open:** playable route walkability across the crown loop, Hive patrols on elevated skyways, and civilian flight from threats.

## Build inventory menu — 2026-10-20

- **Added:** pause-menu BUILD is the first option. It opens a fixed four-by-four inventory with STRUCTURES, KITS, and BLUEPRINTS tabs. Selecting a card equips it; choosing FLOATING PLATFORM opens the existing orientation and height popup. Build placement no longer cycles its palette with Tab, and the O shortcut is removed; the inventory is the selection path. Showcase 91 opens this inventory for review.
- **Checked:** the default `python3 tools/zig.py build check` and installed `python3 tools/zig.py build` pass. The first compile caught two new Zig typing errors in grid navigation and card colors; both were corrected. The full headless suite passed **532/532** on the working tree. The first Metal showcase attempt exposed a dispatcher omission: showcase 91 configured the inventory but fell through to the world camera. It now routes through the GUI showcase. After the fix, the build check and install build passed, and `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=91 -Dcapture-frame=30` captured frame 30 at 2560×1600 with Metal API Validation enabled; the inventory tabs, 4×4 structure grid, focus outline, instructions and background are visible. `git diff --check` passes; no Metal validation errors appeared.
- **Not checked:** keyboard/controller or mouse interaction, placement via the new route, save/reload, and performance. The capture confirms the menu's rendered layout but not hands-on use.

## Chicago heightmap and rotating Earth map — 2026-10-20

- **Added:** converted `assets/CitiesUSA/chicago_metro_heightmap_16bit.png` to `src/assets/chicago_terrain.hwmh` at 160 km square / 550 m relief. The Chicago region is centered at arrival x −360 km and uses the same height sampler for terrain, collision and scatter as Detroit/NYC. Its initial approximate lakefront anchor was later replaced by the shared downtown alignment recorded below.
- **Added:** at the world map's widest zoom, a rotatable Earth globe shows Detroit, Chicago, NYC, and a future LA marker. Drag rotates the globe; the existing destination rows select and travel to the playable landings. Planet view reduces its globe panel height to keep the destination list and footer clear.
- **Checked:** default `python3 tools/zig.py build check`; `MTL_DEBUG_LAYER=1` ReleaseSafe showcase 81 captured frame 120 and exited cleanly with Metal API Validation enabled. The capture shows the globe and Chicago travel row. `git diff --check` passed.
- **Not checked:** hands-on globe dragging or Chicago travel/save behavior; headless tests were not run. Chicago has heightmapped terrain and an arrival but no dedicated city skyline, missions, or liberation content. LA is still not a travel destination.

## Antarctica terrain landing and globe marker — 2026-10-20

- **Added:** imported the 2048×2048 16-bit grayscale Antarctica raster as `src/assets/antarctica_terrain.hwmh` (160 km square, −200 m base, 1,200 m relief). Added a separated playable region at z −420 km, a terrain sampler binding, fast-travel row, and selectable Antarctica marker on the rotating Earth globe. Added the Subglacial Hive premise and named rescue roster to the creative bible. The raster is not georeferenced; this region samples the raster as a local gameplay landscape.
- **Checked:** default `python3 tools/zig.py build check` and `git diff --check` pass.
- **Not checked:** terrain collision at the Antarctic landing, travel in a live session, or mission/rescue gameplay. Two Metal-validated globe capture attempts (`-Dcapture-frame=120`, then `-Dcapture-frame=1`) launched and enabled Metal API Validation, but remained alive without producing a fresh capture after 108 and 60 seconds; both were stopped. The older `zig-out/capture.bmp` predates this change and is not evidence for Antarctica. The robots and AMP are campaign canon and planned content; they are not currently playable heroes or in-world rescue encounters.

## Antarctic glacier surface and sentry perimeter — 2026-10-20

- **Added:** generated and checked in `assets/antarctica_blue_ice_albedo.png`, with a 512×512 RGBA runtime copy in `src/assets/antarctica_blue_ice.rgba`. The terrain shader blends the atlas over Antarctica with world-space ice strata, cold cel-shadows, and sharpened sun glints. World props tagged as ice use triplanar texture coordinates and a blue Fresnel sheen. The Antarctic approach now suppresses biome plants, salvage and boulders, draws four 46 m ice ramparts with lit seams, and animates two large six-legged scorpion sentries around the perimeter. A 6 km prop visibility bound prevents scenery at the far-separated Detroit coordinates leaking into the Antarctic view. Review scenes: `-Dshowcase=85` overview and `-Dshowcase=86` sentry close-up.
- **Checked:** default `python3 tools/zig.py build check`, default `python3 tools/zig.py build` (installed executable), and `git diff --check` passed. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=85 -Dcapture-frame=120` completed with Metal API Validation enabled; the capture was inspected and shows the glacier atlas, icy wall ring, and animated sentries. The terrain is locally visible, though the current streamer/haze can make farther ground fade toward the sky colour.
- **Not checked:** gameplay collision, combat or damage for the visual sentries; the walls are non-colliding scenery. No tests were added or run. The Antarctic robots and AMP rescue arc remain campaign plans.

## Scalari metal and insectoid layer styles — 2026-10-20

- **Added:** the Hive Forge now switches between a brushed-metal layer with visible dark bearings and metallic struts, and an insectoid-carapace layer with overlapping oval plates, glowing compound optics, paired antennae, dorsal shells and tapered claws. Added silver, moss-steel and amber-carapace palettes with distinct understructure and trim colors. Showcases 82–84 review the panel and each finish.
- **Checked:** default `python3 tools/zig.py build check` passed with the new renderer code before the later importer-side `Gltf.zig` edit; showcase 83 completed under Metal API Validation at frame 1. The capture shows paired antennae, three optics, layered chest/shoulder shells, and a segmented abdomen in the amber-carapace palette.
- **Blocked on current tree:** the brushed-metal showcase build now stops compiling at `src/asset/Gltf.zig:325:10` (`expected statement, found ';'`), in an unrelated in-progress importer edit. The current whole-graph build check therefore needs that syntax error resolved before it can pass again.
- **Not checked:** final brushed-metal capture, hands-on style switching, or raid play; no tests were added or run. Forge designs remain session-only.

## Water flow and high-speed swimming — 2026-10-20

- **Added:** river shader caustic highlights use broad, slow world-space patterns to add moving surface detail without tight shimmer. Swimming now follows camera pitch and yaw in 3D, accepts the existing ascend/descend controls (jump rises, roll dives), and uses the sprint control for an 18 m/s burst. Swim bursts drain stamina; normal swimming recovers it. Low breath forces a steady surface ascent, and buoyancy holds the swimmer up when there is no directional input.
- **Checked:** default `python3 tools/zig.py build check` passed (exit 0); `git diff --check` passed.
- **Not checked:** headless tests were not run. The Metal-validated showcase 36 capture initialized the Apple M3 Pro backend and completed deferred-mesh preparation, but produced no fresh capture after about a minute and was stopped. The existing capture file was stale, so water appearance is not visually verified. Underwater controls and burst tuning still need hands-on play.

## Per-vertex cel pens (E1b) — 2026-10-19

- **Added:** HWMS v4 adds one cel pen per vertex (`Model.pens`), written only when present; imported characters now shade and ink each vertex with its pen's cel material instead of always pen 0. `MeshEdit` adds the pen brush, pen fill, selection-masked dabs and select-by-pen/colour. Checked in a scratch worktree of HEAD with the pre-`2c361e4` `build.zig` restored there only, because HEAD's `build.zig` does not compile (it uses `captain_mesh` after the step that defines it was removed): default and 0.17 `build check` pass; the suite runs 476/482, with the same six failures already present after the terrain-heightmap commit (Field LOD, Chunk seed, cave mouth, Hive meshes, Skies, Pets) and every MeshEdit, Model, flight and New York test passing; the Metal smoke with `MTL_DEBUG_LAYER=1` completed 300 frames. Not checked: a capture of a painted imported character (no in-game way to paint yet), and painted colour surviving a part recolour (it does not; see the mesh editor plan).

## Flight boost tiers — 2026-10-19

- **Changed:** held boost in free-fly and in suit flight doubles the flight speed every 1.2 s, up to tier 3 (`Player.max_boost_tier`: 55 to 440 m/s free-fly, 52 to 416 m/s suit flight); letting go or braking returns to cruise within about two seconds, and the HUD shows the tier, speed and altitude while boosting. `Player.move` used to divide the step by the uncapped substep count but run only the capped number, so any step above 64 substeps fell short and stalled the player; the cap is now 128 and the step is divided by the count actually run. Speeds and the tier rule are in [gameplay and Hive war](../gameplay_and_hive_war.md), [architecture](architecture.md) and [project overview](project-overview.md).
- **Checked:** two new `Player` tests (free-fly speeds per tier, the tier cap, the full distance of a long step, the slow-down after release; suit flight tier and fuel burn) pass in the headless suite on the default compiler; default and 0.17 `build check` pass.
- **Not checked:** hands-on flight feel; the Metal smoke on the flight change by itself; collision with walls at tier 3 (about 7 m per tick); and everything past tier 3. Terrain streaming covers about 320 m, haze turns everything to the horizon colour past about 2 km, f32 positions lose precision toward the 524 km world edge, and there is no sky, stars or space, so higher tiers wait on those (the space-ascent stages in the plan are not started).

## Vertex tools in the Character Designer (E3 + E4 first slice) — 2026-10-20

- **Added:** VERTEX TOOLS in the imported library: a docked tool bar (select, move, draw, inflate, smooth, grab, paint, cel pen, split; brush size, strength, soft radius, swatches, pen, paint-inside-selection, selection ops, fills, tear-off to `saves/parts/part-N.hwmesh`, undo/redo), an orbit view, bind-pose preview, selection dots and brush ring. Pointer events queue and apply in `App.publish`. Edits mirror into the part bake's base copy and painted vertices are masked from part recolours. `-Dcharacter-showcase=48` scripts a pen fill, accent band, chest sculpt and head selection.
- **Bugs found while capturing, fixed:** installing the imported mesh closed the tools (they now just rebind); the character-showcase review camera overrode the tools' orbit view; 909 selection dots used the whole 640-command GUI canvas so the panel did not draw (the panel now draws first and the dots share what is left, sampled).
- **Checked:** the `-Dcharacter-showcase=48 -Dcapture-frame=60` capture under `MTL_DEBUG_LAYER=1`, inspected: the panel, the gold selection dots on the head, the upper body in the armour cel pen (hard specular) painted blue, and the orange accent band at the waist all render on the GPU-skinned imported character. MeshTools tests cover world/model placement round trips, a move drag on a turned and scaled model, pen painting, tear-off and its undo, and panel control clamping. Default and 0.17 `build check` pass; the suite runs 481/487 with every new test passing and the same six failures present since the terrain-heightmap commit (Field LOD, Chunk seed, cave mouth, Hive meshes, Skies, Pets); the Metal smoke completes 300 frames; the ReleaseFast build is installed.
- **Not checked:** clicking and dragging by hand in a window (the capture is scripted, not driven by the mouse); whether the bundled GLB's bind pose differs visibly from its retargeted idle (the capture shows arms down either way); performance on large meshes (every brush dab scans all vertices); touch and pen tablets.

## Character animation, imported rigging and GUI pass — 2026-10-20

- **Rigging:**
  - `Gltf.humanoidJoint` maps bone names onto all 21 humanoid joints, where it used to recognise 7 run tracks. It covers Mixamo, VRoid `J_Bip_L_*`, Rigify `DEF-*.L`, Unreal `*_l`/`spine_03` and Biped `Bip01 L *` names. Fingers, twist and end bones inherit their parent.
  - Fixed: `forearm.L` and `lowerarm_l` were matched to the upper arm, and hips and spine fell back to root, which tore the waist.
  - New `character/Retarget.zig`: a per-joint bind correction (a T-pose's arms come down to the game's A-pose) and forward kinematics over the source's own bone offsets, so proportions are the source's and the joints stay connected.
  - Also fixed, older than this pass: `Sandbox.avatar` never applied the combat stance to imported skinned characters, so they never showed swings, aiming or guarding.
  - The status line now reads "LIVE RETARGET n/21 JOINTS".
- **Animation:**
  - `Ranger.solvePose` crossfades from the displayed pose on every motion or action change: about 0.15 s, and about 0.06 s for an attack starting.
  - The fade keeps going while the game clock is stopped (one frame per call) and always re-solves after a fading frame, so it never sticks or leaves a sliver of the old pose. Both bugs were found during this work, and each has a regression test that failed first.
  - A landing dip reads `Player.landing`.
  - Idle adds a breath, a weight shift and a head turn (idle motion only).
  - The stride step length now follows speed (0.7–1.6 m) instead of a flat 1.4 rad/m.
- **GUI:**
  - Part hit rows are masked and resolved to the part nearest the selection, so parts at 256 and above no longer trigger another control.
  - Enter (pad A or Start) no longer closes the imported library.
  - With the vertex tools open, the pad cycles tools, sizes the brush and backs out, and no longer edits the library hidden behind them.
  - Saving the library now says vertex edits are not saved yet.
  - The vertex panel's status lines follow the content.
- **Checked:**
  - New tests pass: rig names (about 40 cases), retarget identity, T-pose correction with joint continuity, and knee bend with hips travel in centimetre units; crossfade continuity and settling, a crossfade with a stopped clock, and the landing dip.
  - Default and 0.17 `build check` pass.
  - Captures of `-Dcharacter-showcase=47` under `MTL_DEBUG_LAYER=1`:
    - At the last commit (old retarget), the bundled rigged GLB stands with splayed, stretched legs and a tilted, torn body.
    - With this change it stands in a clean A-pose.
    - With `-Dcharacter-pose=2` it performs the overhead swing with the arm, forearm and shoulder pad connected.
  - The suite runs 486/494, and every test from this pass passes. Of the 8 failures, 6 predate this work (Field LOD, Chunk seed, cave mouth, Hive meshes, Skies, Pets); 2 come from another session's uncommitted edits to `Worlds.zig` and `Player.zig`.
  - The Metal smoke completes 300 frames.
  - The ReleaseFast build is installed.
- **Not checked:**
  - Hands-on play feel of the fades, landing and strides.
  - Real Rigify, VRoid and Unreal files: only names are tested, and VRoid files usually fail earlier on morph targets.
  - Fingers, which follow the hand.
  - Turn lean and strafing gaits, foot IK, distinct swim/stomp/board/hang poses, and Wildkin quadruped and wing motion.
  - Remaining GUI items: the library panel at UI scale above 1, a pad path into the library and creator tabs, and the Heroes narrow layout.

## Stylization painting core (mesh editor S1) — 2026-10-20

- **Added:** mirror-X symmetry for every brush (each side of the centre plane painted once), front-only masking, brush hardness, paint blend modes (mix, multiply, screen, smudge), the PICK eyedropper tool, five brush presets, an HSV colour picker, and a re-laid-out tool bar (10 tools, two steppers per row). Plan: [mesh editor](plans/mesheditor.md) section 0.1.
- **Checked:** new tests pass. They cover mirrored dabs (once per side), backface masking (masked from below, painted from above), multiply/screen/smudge values, hardness at 80% radius, eyedropper colour and pen, HSV round-trips, presets, picking colour back off the mesh, and a panel layout test at 1280×720 and 853×480 (no overlapping hits, within the canvas and hit budgets). The suite runs 491/499; the 8 failures are the same as in the entry above (6 predate this work, 2 come from another session's Worlds and Player edits). Default and 0.17 `build check` pass. The Metal smoke completes 300 frames. The `-Dcharacter-showcase=48` capture was inspected and the new tool bar renders without overlap. The ReleaseFast build is installed.
- **Not checked:** painting by hand with a mouse; symmetry on a model whose bounds are not centred on its own mirror plane (the plane is the bounds centre); pen-tablet pressure (not implemented).

## Gradients and filters (mesh editor S2) — 2026-10-20

- **Added:** colour ramps; linear, radial, height and curvature (edge/cavity) gradient fills over the selection or the whole mesh; posterize; the GRAD drag tool, a second colour with SWAP, and HEIGHT, EDGES and POSTERIZE buttons. Curvature uses the welded group's mean normal, so a cube's split-normal corners count as convex (an earlier per-copy version read them as flat; the test caught it). `-Dcharacter-showcase=48` now also runs an edges-and-cavities pass.
- **Checked:** new tests pass: ramp sampling, linear/radial/height fills respecting the selection, posterize to two bands and its rejection of one band, one undo step per fill, curvature sign on a peak, a pit and a cube corner, the GRAD drag on a turned and scaled model, and panel fills as single undo steps. The suite runs 494/502 with the same 8 failures. The showcase-48 capture under `MTL_DEBUG_LAYER=1` was inspected: ridges and plate edges are lightened, crevices darkened, and the panel fits. The 0.17 `build check` passes. The Metal smoke exited 0 and reached stage 9 (this run printed no closing "Smoke complete" line). The ReleaseFast build is installed.
- **Not checked:** using the GRAD tool by hand; curvature on very dense meshes (it scans every vertex's ring, without caching).

## Selection modes and gizmo (mesh editor S3) — 2026-10-20

- **Added:** vertex, face and edge selection modes; a move/rotate/scale gizmo on the MOVE tool with axis handles; selection counts and size in the panel. Showcase 48 now ends on the move gizmo.
- **Bugs found while testing, fixed:** clicking at the selection centre picked an axis (every handle starts at the pivot), and looking straight down an axis picked that handle, whose drag cannot move anything. The inner quarter of each handle and handles within about 18° of the view direction are no longer pickable. The existing "move tool drags the clicked corner" test caught both.
- **Checked:** new tests pass: face pick and face-in-sphere selection, nearest edge, selection bounds, soft rotate and per-axis scale about the centre with one-step undo, the face/edge select modes through the tool, an X-handle drag that moves only along x, and a free scale that doubles the face. The suite runs 496/504 with the same 8 failures. The showcase-48 capture under `MTL_DEBUG_LAYER=1` was inspected: the three handles on the selected head, the info line and the mode buttons. The 0.17 `build check` passes and the Metal smoke completes 300 frames; the shared run below covers the install.
- **Not checked:** rotating and scaling by hand with a mouse; the gizmo on very small or very large selections (the handle length is a fixed share of the model's height).

## Topology operations (mesh editor S4) — 2026-10-20

- **Added:** delete faces, extrude faces (as one region, with walls, the cap left selected for the gizmo), split edge and collapse edge, each one undo step holding the whole mesh before and after. After a topology edit the app re-registers the model with the catalog (new GPU buffers for the static and skinned paths) and detaches the part library, whose part ids belonged to the old vertices; a one-time message says so.
- **Checked:**
  - New tests pass: delete with vertex compaction and exact undo and redo, refusal with no faces selected; an extrude producing the expected vertex and triangle counts, a raised cap and outward-facing walls (checked with rays); split adding two triangles with a midpoint and its undo; collapse removing two triangles; a non-edge refused; and the topology buttons through the tool. The suite runs 500/508 with the same 8 failures.
  - The showcase-48 capture under `MTL_DEBUG_LAYER=1` now extrudes a chest patch. The log shows the mesh at 5,704 vertices and the detach message, and the GPU-skinned character rendered after the rebuild with no validation error.
  - The 0.17 `build check` passes, the Metal smoke completes 300 frames, and the ReleaseFast build is installed.
- **Not checked:**
  - Extrude, split and collapse by hand.
  - Topology edits on a mesh whose welded seams split a selected region (walls follow welded edges; seam copies inside the region move together).
  - Memory on very large meshes: every topology edit keeps two whole-mesh copies in the undo history (up to 64 steps).

## Saving vertex edits (mesh editor E2) — 2026-10-20

- **Added:** SAVE and DISCARD on the vertex tool bar. SAVE LIBRARY also saves the edited mesh when there are vertex edits. `game/EditedMesh.zig` writes the edited model (HWMS with pens and skin) and adopts it on load only when the rig matches. `App.loadEditedMesh` applies it once the mesh is installed and detaches the part library. The old "vertex edits are not saved yet" message is gone.
- **Checked:**
  - A new test covers the encode/adopt round trip (positions, colours, pens) and refusal of a different joint mapping, an unskinned source and junk bytes. The suite runs 501/509 with the same 8 failures. Default and 0.17 `build check` pass.
  - An isolated round trip in a scratch worktree (its own `saves/`), with a worktree-only line making showcase 48 save at the end:
    - Showcase 48 wrote a 493 KB `saves/imported-character.edited.hwmesh` after the scripted edits, including the extrude.
    - A second launch (showcase 47) logged "Loaded saved mesh edits", and its capture shows the edges, the armour pen and the chest plate on the live, retargeted character.
  - The Metal smoke completes 300 frames, and the ReleaseFast build is installed. The user's real `saves/` holds no edited-mesh file afterwards.
- **Not checked:** DISCARD by hand; a saved edit after the source GLB is replaced by a different rig (refused by the test, not tried in the app); edited saves of the built-in Captain (same code path, not run).

## Antarctic spawn depression heightmap correction — 2026-10-20

- **Changed:** replaced the zero-valued center of `assets/antarctica_continent_heightmap_16bit.png` with the newly supplied corrected raster. Recompiled `src/assets/antarctica_terrain.hwmh` with the existing 160 km square, −200 m base, and 1,200 m relief settings. The center sample now maps to about 596 m, avoiding the previous deep spawn hole.
- **Checked:** the heightmap compile completed and reported a 2048×2048 source with the expected settings; `python3 tools/zig.py build check` passed. The supplied PNG was inspected and the center depression is gone.
- **Not checked:** hands-on arrival. A ReleaseSafe showcase 85 build launched on Apple M3 Pro with Metal API Validation enabled and completed deferred-mesh preparation, but did not write a fresh capture after about a minute and was stopped. Runtime camera angles still need a fresh showcase review.

## Weight painting (mesh editor S5) — 2026-10-20

- **Added:** the WEIGHT tool with a joint picker, add/subtract/replace/smooth, mirror to the partner joint, and a heatmap view. Weights are per game joint (summed over every skin bone mapped to it). Skin influences are part of stroke snapshots and of saved edits. `-Dcharacter-showcase=49` ends in the heatmap.
- **Design fix found while capturing:** the first heatmap measured a single skin bone per joint and lit only part of the upper arm. Retargeting moves every bone of a joint together, so weight is now measured and painted per joint.
- **Checked:**
  - New tests pass: joint weights scaling all of a joint's bones together; `setWeight` keeping four influences summing to one and taking the weakest slot; the brush adding, smoothing, mirroring to the partner joint and undoing; refusal without a skin; the tool painting the left arm and mirroring to the right; the heatmap restoring the real colours; colour edits refused in the view.
  - The suite runs 505/513 with the same 8 failures. Default `build check` passes.
  - The showcase-49 capture under `MTL_DEBUG_LAYER=1` was inspected. The body reads cold blue for `upper_arm_l` and the upper arm under the shoulder pad reads green to red. A direct read of the GLB's `WEIGHTS_0` confirms `LeftArm` carries about as much weight as `LeftForeArm` (207 against 199 vertex-weights) on a short upper arm, so the small hot region matches the data.
  - The 0.17 `build check` passes, the Metal smoke completes 300 frames, and the ReleaseFast build is installed.
- **Not checked:** painting weights by hand and watching the limb deform in the game; auto-weights and the lattice (not built).

## Lattice deformer (mesh editor S5b) — 2026-10-20

- **Added:** the LATTICE tool: a 3x3x3 control grid over the selection (or the whole mesh), a smooth quadratic blend, no topology change, one undo step per drag, and the 27 points drawn in the view. `-Dcharacter-showcase=50` bends the head with it.
- **Checked:** new tests pass: pulling the four top corner points stretches the top of a cube (to about 2.5 from 2) while its base stays put, the unselected grid does not move, undo restores the exact shape, no selection lattices the whole mesh, and the tool picks the nearest control point by ray, drags it in the view plane, and starts nothing when the press misses every point. The suite runs 507/515 with the same 8 failures; default `build check` passes. The showcase-50 capture under `MTL_DEBUG_LAYER=1` was inspected: the head is taller (selection height 0.14 to 0.16) and the lattice points are drawn over the selection's bounds, which include the horns and hair.
- **Notes:** a mid-edge control point has no pull at the exact corners (quadratic Bernstein), so bending a box's corners needs the corner points; this is deliberate and the test uses the corners.
- **Not checked:** dragging the lattice by hand; lattice on a skinned mesh while posing (it moves rest positions only); very dense meshes. The 0.17 `build check` passes, the Metal smoke completes 300 frames, and the ReleaseFast build is installed.

## Metro terrain alignment — 2026-10-20

- **Changed:** aligned Detroit, NYC, and Chicago heightmap samples to downtown arrival coordinates using the active geographic export bounds in the terrain-generation instructions. This replaces the centered Detroit raster and guessed NYC/Chicago pixel anchors. Added `CityGeography.zig` as a shared source for those terrain anchors and the city markers on the rotating globe. Updated the landscape plan and Earth README with the projection and regeneration notes. The existing 2048×2048 PNGs and HWMH imports were retained; no re-export was needed.
- **Checked:** `python3 tools/zig.py build check` passes after both alignment changes. The `MTL_DEBUG_LAYER=1` ReleaseSafe showcase 81 capture completed at frame 120 with Metal API Validation enabled; the globe and destination list render with the shared city markers. The source images are 2048×2048, 16-bit grayscale. The NYC and Chicago imported settings remain 160 km square / 700 m and 550 m relief; Detroit remains 120 km square / 380 m relief.
- **Not checked:** a live visual review of the revised arrival terrain or precise consistency of the original PNGs with their active bbox scripts (the PNGs have no georeferencing metadata). The globe still uses its procedural land outline; the new global Earth maps are not sampled by it yet.

## Terrain asset organization and content expansion — 2026-10-20

- **Changed:** moved Detroit, NYC, Chicago, and LA metro source PNGs to `assets/CitiesUSA/`. Removed the unused root `assets/Earth.png`, an 8-bit shaded-relief image superseded by the new 16-bit elevation rasters for terrain use. Compiled runtime `.hwmh` maps remain under `src/assets/`.
- **Added:** `procedural/TerrainSites.zig` catalogs ten Himalayan mountain sites, six alien strongholds, and 24 US city entries with biome, faction, hazards, traversal, enemy roles, bosses, and facility recipes. There are 36 available heightmaps for those 40 entries. Four city entries (Phoenix, Seattle-Tacoma, St. Louis, Charlotte) have metadata in the 20-city manifest but their PNGs are absent; their catalog paths are nullable instead of dangling.
- **Added:** `procedural/Interiors.zig` now generates connected sky-city, Scalari mechworks, Hive broodworks, mountain-vault and drake-roost room graphs. Hostile graphs span 144–192 m below their entry floors, with explicit lift/shaft/resin-tube/drake-tunnel links; sky-city room levels use 45 m floor spacing and sky lifts.
- **Checked:** pinned `python3 tools/zig.py build check` passes. Catalog path audit found 36 existing raster files and four missing manifest files. `git diff --check` passes; repository search found no runtime dependency on the deleted `assets/Earth.png` and no stale root-level metro PNG paths.
- **Not checked:** no tests or live captures were run. These new city/base recipes remain authoring data: site heightmaps are not streamed, room graphs are not rendered or collidable, and new enemy roles do not yet have models/AI or playable encounters. The global Earth elevation maps are still not used by globe rendering.

## K2 Black-Summit expedition slice — 2026-10-20

- **Added:** activated the K2 raster as a named Earth expedition region and globe marker. The shared height sampler now drives its high-altitude terrain mesh and collision; K2 uses an icy alpine palette, suppresses vegetation, and keeps salvage scatter. Fixed terrain-chunk frustum bounds to use sampled terrain elevation, which had culled all elevated city/mountain chunks as though they sat at sea level.
- **Added:** a six-room underground Black-Summit Works branching from the glacier landing, using the cave system's existing rock mesh and collision path. Added cyan-lit metal service framing, Scalari guards, and a Black-Summit Titan encounter that records the defeat and awards per-player combat XP and Scalari materials. Cave meshes are now retained by world-prop distance filtering because their vertices are already in absolute coordinates.
- **Checked:** pinned `python3 tools/zig.py build check` passes. ReleaseSafe showcases 87 (K2 landing) and 88 (mechworks heart) each captured frame 120 at 2560×1600 under `MTL_DEBUG_LAYER=1` with Metal API Validation enabled on Apple M3 Pro. Both captures were inspected; the glacier renders at its real elevation without vegetation, and the cave chamber, metal frames, and Titan render. The globe destination caption includes K2. `git diff --check` passes.
- **Not checked:** headless tests, hands-on traversal from the surface to the heart, combat completion and reward confirmation in a normal play session, save/load of the defeat flag, performance/memory across the full raster, or cross-platform builds. The surface screenshot also retains the game's unrelated garage tutorial toast; it does not affect the K2 terrain.

## Earth globe site plotting — 2026-10-20

- **Changed:** the globe now plots all 24 catalogued U.S. city sites, all 10 Himalayan mountain sites, six alien strongholds, and Antarctica. Marker styles/colors distinguish active travel destinations, city biomes, mountains, and strongholds. Cities without a local raster are shown dimly. Catalog-only markers remain non-travelable until they have a playable region and safe arrival. Fixed a `shop` role typo in the sky-city room recipe and set a larger compile-time quota for validating the full site catalog when the globe imports it.
- **Checked:** the pinned `build check` passes. The ReleaseSafe showcase 81 capture completed at frame 120 under Metal API Validation on Apple M3 Pro and was visually reviewed. `git diff --check` passes.
- **Not checked:** marker selection/tooltips (the points are informational and globe drag still rotates the map), current-world labels at every zoom, or activation of any catalog-only region.

## Flight controls and combat input review — 2026-10-20

- **Changed:** added Left Alt as a rebindable air brake for suit and free flight, with strong deceleration to a hover; controller B dodges on foot and brakes in flight. When its default brake and dodge bindings point at the same button, flight suppresses the dash/roll edge so braking does not also launch an evasive move. The gamepad D-pad now gives direct climb/descent in flight and continues to select specials on foot. Older controller profiles retain the original 16 mapped actions; air brake is stored in a separate defaulted field.
- **Changed:** increased the Kestrel's afterburner from 95 to 155 kN, its boost reserve from 2.6 to 8 seconds, and recharge from 0.55 to 0.9 seconds per second. Added the dedicated air brake while keeping S as throttle cut and braking. Gamepad RT/RB now reach the Kestrel cannons and missile lock/release instead of the on-foot energy/saber handler.
- **Added:** short movement, flight, vehicle and combat guides to both the keyboard and gamepad Controls tabs.
- **Reviewed:** `Player`, input sampling and merging, keyboard and controller bindings, Kestrel flight, the player weapon/saber path, class specials, and the Hive air war's cannon, missile, flak, carrier weak points, and ramming. Only the Kestrel is currently pilotable; Scalari fighter meshes remain non-playable assets.
- **Checked:** the pinned `python3 tools/zig.py build check` passes. ReleaseSafe keyboard Controls showcase 28 and gamepad Controls showcase 46 captured frame 120 at 2560×1600 under `MTL_DEBUG_LAYER=1`; both tabs were visually inspected and the guide text fits above the buttons. A 300-frame ReleaseSafe Metal smoke completed under API validation, including Kestrel lift-off and a wasp kill, saber/sniper/grenade combat, four-player stages, and the broader interaction/build/city smoke. No Metal validation errors appeared. `git diff --check` passes.
- **Headless suite:** the first test build exposed a pre-existing inferred-enum type error in `Interiors`; adding an explicit `Connector` type let compilation continue. The rerun remained in expensive city/Arbor TriangleMesh collision tests after about eight minutes and was interrupted, so the full suite has no result.
- **Not checked:** hands-on flight and combat feel, controls on a physical gamepad, balance of the increased Kestrel speed against live carrier/wasp encounters, or other operating systems. Only the atmospheric Kestrel is pilotable; the Scalari fighter meshes remain assets rather than flyable aircraft.

## Canopy city garden asset pass — 2026-10-20

- **Changed:** expanded the seeded Detroit roof-garden kit with open soil planting beds, native shrubs and flowers, a kiosk pergola, and benches. Added benches to the public skyway terraces. `Vegetation.hangingVine` generates reusable trailing stems and foliage; the catalog registers one mesh, and `Frontier.publish` places it on selected stone towers without changing ground-scatter IDs. Added `-Dshowcase=89` for a close skyline garden view.
- **Checked:** pinned `python3 tools/zig.py build check` passes; `git diff --check` passes. ReleaseSafe showcase 89 captured frame 120 at 2560×1600 under `MTL_DEBUG_LAYER=1` with Metal API Validation enabled on Apple M3 Pro. The capture was inspected after tuning the vine leaf spacing and planter layout; no Metal validation messages appeared.
- **Not checked:** headless tests, performance benchmarking for the added city props, hands-on rooftop traversal, or equivalent planting on NYC/Chicago. This is visual dressing on the existing Detroit skyline, not a player-facing city construction tool.

## Character generator mesh-editor direction — 2026-10-20

- **Reviewed:** the current VERTEX TOOLS panel is inside Character Designer, but its editable target is an imported GLB `Model`; the native `Profile` → `Ranger` generator is not connected to it. Imported mesh edits persist as `.hwmesh`; that remains useful for imported bodies, but it is not the desired source of truth for generated player characters.
- **Owner direction recorded:** make the tools an overlay over the generated native character. Keep `Profile` and procedural generator data authoritative, persist a small per-character edit layer, and flatten it through the existing Ranger mesh and GPU skinning path. Avoid a second generated mesh asset, extra draw/skin passes, and frame-path rebuilds or allocations. The product and engineering plans now define this target and its staged integration.
- **Performance evidence:** the 2026-10-20 Apple M3 Pro ReleaseFast Frontier run (600 measured frames, four views) recorded character-skinning p99 0.161 ms, render-CPU p99 17.316 ms, simulation p99 6.445 ms and whole-command-buffer GPU p99 23.299 ms. Character skinning passed its 3 ms budget; render CPU and simulation exceeded their budgets, and active-ring coverage failed with 18 underfilled frames. With the cel ink hull disabled, a single comparison recorded skinning p99 0.172 ms, render CPU p99 14.247 ms, simulation p99 10.649 ms, GPU p99 23.398 ms, and 18 underfilled frames; render CPU passed while simulation and active-ring coverage still failed. The GPU result is effectively unchanged, and one run per setting cannot attribute the CPU difference to ink hulls. Whole-command-buffer GPU timing is available, but per-pass timestamps are not. The older 2026-10-11 baseline was 0.129 ms character-skinning p99 and 4.799 ms render-CPU p99. Ranger source tests only enforce a lower bound above 2,000 vertices, so light/default/heavy vertex and byte counts are still needed before increasing geometry.
- **Not changed or checked in this review:** generator or renderer code, native-generator editing, persistent overlay application, per-profile mesh counts, or a Metal visual capture of the proposed generator overlay. The fresh Frontier benchmark ran, but did not pass all performance and streaming-coverage checks.

## Packaged MP3 player — 2026-10-20

- **Added:** a title-screen player, compact gameplay widget, and a pause-menu player reachable with keyboard or controller. Previous, play/pause, and next controls operate on the sorted MP3 tracks packaged in `assets/Music/`; there is deliberately no custom-folder picker. A worker streams decoded/resampled audio through a bounded ring, keeping file I/O and MP3 decoding outside the real-time audio callback. The decoder is vendored under MIT license with its upstream revision recorded in `vendor/zig-mp3/NOTES.md`.
- **Checked:** default `python3 tools/zig.py build check` passed; focused music tests **3/3 passed** (MP3 filtering, deterministic ordering, and stable status-label storage). `python3 tools/zig.py build assets` installed the 30,255,019-byte `Telecom Giants Master.mp3` into `zig-out/assets/Music/`. ReleaseSafe captures of showcase 18 (title) and 26 (gameplay HUD), frame 120, completed on Apple M3 Pro / Metal with `MTL_DEBUG_LAYER=1`; both widgets were inspected, and logs confirmed the 44.1 kHz MP3 decoded. The title capture caught and verified a fix for a dangling track-label slice. No Metal API validation errors appeared. The ReleaseFast install build and `git diff --check` passed.
- **Not checked:** the music was not listened to subjectively, physical controller skip/pause controls were not manually playtested, and no Linux/Windows runtime or 0.17 build was run. The installed-folder fallback is implemented but was not exercised with the source folder absent. Keyboard/controller use of the pause-menu track commands is covered by the menu path, but not separately tested with a physical gamepad.

## Traversal mode cycling crash — 2026-10-20

- **Cause:** the crash report's `debug.FullPanic.invalidEnumValue` stack ends in `game.Player.stepIn`. `cycle_mode` incremented the enum's underlying 3-bit integer with wrapping arithmetic. The representation wraps at eight values, while `Traversal` has five; cycling forward from `.energy_skate` (4) produced invalid enum value 5.
- **Fixed:** traversal cycling now advances modulo the reflected field count. Added a regression test that starts at `.energy_skate`, cycles through all five modes, and verifies the sequence wraps to `.grapple`.
- **Checked:** before the fix, the focused regression failed with the same invalid-enum panic at the old assignment. After the fix, `python3 tools/zig.py build test -Dtest-filter='cycling every traversal wraps' --summary all` passes (4/4 matching tests); default `python3 tools/zig.py build check`, `HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py build check`, and the default install build `python3 tools/zig.py build` all pass. The 0.17 gate also required replacing the vendored MP3 decoder's test-fixture array-repeat syntax; these are compile-compatibility edits only, with no runtime decoder change. `git diff --check` passes.
- **Not checked:** the full headless suite, a Metal smoke, and an interactive game session were not run for this fix.

## Antarctic landing exit and controller weapons — 2026-10-20

- **Changed:** the Antarctic visual ramparts now have a 153 m north exit with a blue-lit route and marker pylons leading from the landing square onto the open glacier. Flight at the Antarctic landing initially appeared stuck because its large world coordinates rounded small f32 movement to zero, which the player then treated as a collision and used to erase velocity. Horizontal collision response now preserves velocity when the physics result matches the collision-free, representable endpoint. P1's pad fire and saber actions now select the Weapon tool even when starting in the default Hands tool; RT fires the ranged gun and RB swings the saber on their existing separate mappings.
- **Checked:** the Antarctic movement regression crosses the north exit in both flight and ordinary walking after the fix (4/4 tests selected by the filter), and the P1 controller regression passes after failing before the tool-selection fix (4/4 tests selected by the filter). The controller regression starts from Hands, verifies RT fires, verifies RB swings, releases the saber, and verifies RT fires again. Showcase 85 captured frame 120 at 2560×1600 under `MTL_DEBUG_LAYER=1`; the widened exit and route markers were visually inspected and Metal API Validation reported no errors. Default and Zig 0.17 `build check`, default install build, and `git diff --check` pass.
- **Not checked:** a physical Xbox controller and hands-on walking through the exit were not playtested; the visual perimeter and sentries remain non-colliding scenery. The full headless suite and 300-frame smoke were not run.

## K2 Cloudwater Basin stop — 2026-10-20

- **Added:** a distinct safe fast-travel stop and map title inside the existing K2 region, based on the three family clay-art references. The imported heightmap now feeds a continuous carved streambed and three stepped falls; the same authored path drives the animated river ribbon, waterfall curtains, gameplay water query, terrain color bands and a small sheltered alpine flora zone. The stop is dressed with a pale stone terrace hamlet, natural ice arch, copper-gold grove and non-colliding floating rocks. Showcase 90 reviews the basin and settlement.
- **Checked:** default `python3 tools/zig.py build check`; focused Cloudwater tests **8/8 passed**, including K2 stream water above its carved bed, a vertical waterfall curtain in the streamed chunk, a distinct map destination, and safe arrivals/teleportation for every travel row (**4/4**). `git diff --check` passes. ReleaseSafe showcase 90 captured frame 30 at 2560×1600 on Apple M3 Pro / Metal under `MTL_DEBUG_LAYER=1`; the stream, falls, settlement, grove and floating forms were visually inspected, with no Metal API validation errors.
- **Not checked:** the full headless suite, manual swimming or waterfall traversal, and performance benchmarking. The village and floating rocks are scenery without collision; this stop adds no new mission or combat encounter, and the existing Black-Summit Works campaign remains unchanged.

## Suite restored to green, smoke that can fail, and what it found — 2026-10-21

- **Why:** the terrain-heightmap, K2 and city commits left the suite red (8 failures, then 10 with two new ones) and their validation entries said tests were not run. A review found the cause of each, and several turned out to be real defects.
- **Real defects fixed:**
  - **Mountains and caves were gone near Detroit.** The Detroit raster replaced the noise terrain inside its 120 km square, which removed the four procedural mountain ranges (1.3 to 1.7 km from the hub) and, with them, the mountain caves (only K2's mechworks was left). `CityHeightmaps.heightAt` now lays `Mountains.height` back on the raster in the Detroit branch (an owner decision, 2026-10-21). Cave mouths now prefer an approach a walker can climb (`Caves.max_approach_slope`), and `Sandbox.walkableCave` names the first reachable one.
  - **K2 had no safe arrival:** fast travel to K2 was refused (the arrival shares a spot with the cave mouth collider). Region arrivals now search 24 rings (48 m) instead of 6. A new test checks that every travel destination has an arrival within 70 m.
  - **Swimming forward never surfaced:** since the swim rewrite, any input zeroed the water's buoyancy, so a swimmer moving at level pitch stayed under and ran out of breath. The lift now applies unless the player steers up or down (`Player.zig`).
  - **The world map overflowed:** with ten destinations the RESUME row sat at y = 738 on a 720-tall screen. The map's height now follows the number of rows (`map_row_step`).
  - **`Worlds.validate()` itself returned false** (it hardcoded nine Frontier cities; there are eleven).
  - **The scripted smoke could not fail:** its `SMOKE …` checks only wrote status text, so a refused destination still exited 0. They are now counted and fail the run (proven: with the old arrival search the smoke exits 1 with `SMOKE TRAVEL K2 EXPEDITION REFUSED`). The cave check now requires a walk-in that reaches underground (37.6 m under the slope).
- **Test expectations updated** (code was right): Worlds city counts (21, 11), Chunk seed (the seed no longer moves ground near the origin; colour and everything else still do), HiveMeshes size bound (the fortified base reaches about 42), Pets (stand on the terrain), Field cull (eye above the instances), Skies raid (plazas 60 m above the ground, as in the canopy city).
- **Tooling:** `-Dtest-filter="name"` runs matching tests only (seconds instead of 4 minutes).
- **Checked:** full suite 516/516 on the whole working tree (this session's changes and another session's uncommitted flight-controls work); default and 0.17 `build check` pass; the Metal smoke visits all ten destinations and walks into a cave.
- **Seen:** showcase 42 (the cave mouth) under `MTL_DEBUG_LAYER=1` shows the restored mountainside, a steep snow-covered flank; showcase 41 (the foothills panorama) is mostly forest and shows no obvious range, so the far look of the four ridges was not judged.
- **Not checked:** hands-on cave entry and swimming; the other session's flight and gamepad edits by hand; the audit's claim that seven test files were unregistered was wrong (their tests already ran) and `Renderer.zig`'s two tests cannot compile as a unit (they need the build's `options` module and have a division-coercion error), so they do not run.

## Nature benchmark rebaseline — 2026-10-21

- **Measured:** four consecutive ReleaseFast `python3 tools/benchmark.py --nature --frames 600 --silent` runs on Apple M3 Pro / Metal. Every run passed all benchmark checks, including complete frames, upload budget, bounded GPU residency/pools, active-ring coverage, streaming exercised and GPU timing collected.
- **Results:** all runs reported 83 visible vegetation instances and 5,579,930 submitted triangles. Median whole-command-buffer GPU p50/p95/p99 was **5.623/10.264/12.439 ms** (p99 range **12.086–12.622 ms**), with 598 GPU samples per run. Median CPU p99 was **4.101 ms**; no active-ring frames were underfilled. The current GPU p99 is below the 16.667 ms target.
- **Discrepancy:** this run did not reproduce the 2026-10-14 notes' 551 visible vegetation instances, 12,248,988 triangles, and 19.690 ms GPU p99. This review did not isolate why the benchmark draw set differs. Keep tree LOD as the next nature step before further crown detail, and reconcile the measurement change before treating it as a current budget failure.
- **Report:** `.tools/nature-benchmark.json` contains the final run; the four results are summarized here because each run overwrites that report.

## Detroit liberation loop audit — 2026-10-21

- **Already connected:** `CityContent.detroit` defines the three draft missions, boss and ten discoveries; keeper conversations can start each mission; `QuestLog` selects the current mission from shared `Progress` flags; those flags are part of the existing world save.
- **Concrete gaps:** there is no runtime evidence collection or mission-completion interaction, so no gameplay path sets `foundry_exposed`, `windsor_exposed`, or `bile_exposed`. `titan_defeated` is only set in tests, and the runtime never calls `CityContent.updateLiberation`; Detroit therefore cannot become free in a playthrough. The ten discoveries and declared personal rewards have no runtime placement or award path.
- **Next slice:** implement only the existing draft Foundry Ledger proposal: three shipment checkpoints, shared evidence progress, a Maro exposure conversation, and a per-player Kit reward. Preserve the draft label. Add deterministic progression and save coverage plus a real-game smoke before beginning the next mission.
- **Not changed or verified in this audit:** no game code changed for city content; no build, tests, smoke, or hands-on city play were run for this audit. The fresh nature benchmark above was the only executable validation in this pass.

## Detroit Foundry Ledger first playable slice — 2026-10-21

- **Added:** Maro starts the draft case; three deterministic checkpoint props are placed at generated industrial buildings, highlighted when aimed at, and collected through normal hands interaction. Shared `Progress` flags persist each page, and the quest log/HUD report the count. After the last page, Maro's ledger report sets `foundry_exposed` and rewards Sprint Servos +1 in each active player's `Kit`.
- **Checked:** default `python3 tools/zig.py build check` passes; the full headless suite passes **537/537**. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=92 -Dcapture-frame=30` captured frame 30 at 2560×1600 with Metal API Validation enabled; the manifest prop and `FOUNDRY LEDGER PAGE 1/3 X / CLICK RECOVER` prompt were visually confirmed under the crosshair. The full `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` passed all 300 frames. Its in-game smoke started the case through Maro's dialogue, recovered all three pages through aim/interact, saved and restored them, exposed the case through Maro's report, and verified P1's Sprint Servos reward. No Metal validation errors appeared.
- **Still open:** the page/checkpoint visuals are temporary world props. There is no brood-scavenger fight, physical foundry steward, loading-dock confrontation or yard opening yet. The other two Detroit missions, Titan boss, ten discoveries and final liberation outcome remain unimplemented. Hands-on keyboard/controller play and active-guest reward delivery were not checked.

## Detroit Foundry loading-dock console — 2026-10-21

- **Added:** Maro's report now records `foundry_reported`. The player then targets and uses the loading-dock console, which records `foundry_exposed`, grants Sprint Servos +1 to each active player's private `Kit`, and slides the visible gate aside. The gate is presentation geometry and does not block movement; the physical steward and brood-scavenger fight are still absent.
- **Checked:** default `python3 tools/zig.py build check` passes; Foundry/Maro focused tests pass; the full headless suite passes **538/538**. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` passed all 300 frames and logged that the console exposed the steward, opened the gate and awarded P1 Sprint Servos +1. `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dshowcase=93 -Dcapture-frame=90` captured frame 90 at 2560×1600 with Metal API Validation enabled; visual review confirmed the console prompt and closed gate are both visible. No Metal validation errors appeared. `python3 tools/zig.py build -Doptimize=ReleaseFast` installed the updated game.
- **Still open:** add the physical steward and scavenger set piece beyond the gate, then complete Detroit's remaining missions, boss, ten discoveries and liberation outcome. Active-guest reward delivery and hands-on play remain to be checked.

## Detroit Foundry steward ambush — 2026-10-21

- **Added:** publishing Maro's report at the dock console starts a persistent shared confrontation. A human field-jacketed steward leads two Hive guards; the yard gate remains shut until the whole group is defeated. The final takedown exposes the steward, opens the visible gate and grants Sprint Servos +1 to each active player's private `Kit`. The city quest stays on this mission during the fight. The enemies use a reserved encounter slot and respawn as a full group if a save is loaded before they are defeated; enemy health and positions are not saved.
- **Checked:** the default app check passes. The full suite passes **540/540**. A 300-frame `MTL_DEBUG_LAYER=1` ReleaseSafe smoke completed with Metal API Validation enabled; its Foundry stage started the dock ambush, defeated all three enemies through the sniper path, opened the gate and awarded P1 Sprint Servos +1. Showcase 94 captured frame 45 at 2560×1600 on Apple M3 Pro; visual review confirmed the field-jacketed steward and both Hive guards are visible against the closed gate. No Metal validation errors appeared. The ReleaseFast install build and `git diff --check` pass.
- **Still open:** the gate has no collision, and the encounter has no civilian evacuation behavior or saved enemy health. The other Detroit missions, Titan, discoveries and liberation remain draft work. Active-guest reward delivery and hands-on combat balance are not verified.

## Detroit Windsor Gate evidence and crossing stops — 2026-10-21

- **Added:** Ines starts the investigation; two deterministic bridge-control logs and a Gothic civic-hall recording are targetable with the normal hands interaction. Shared evidence flags drive the quest count, and Ines's report sets `windsor_exposed` and animates open the visual crossing gates. Two Detroit-bank world-map stops unlock at that point; their rows remain visible and disabled before exposure. Safe arrivals are tested. The story mentions watching after dark, but the first slice does not hard-gate evidence on the clock.
- **Checked:** default and Zig 0.17 `python3 tools/zig.py build check` passed; Windsor-focused tests passed **7/7**; the full default headless suite passed **545/545**; the ReleaseFast install build passed; `git diff --check` passed. The extra map rows initially made the map overflow at 640×480; the existing screen-layout regression caught it, and the layout now adapts row spacing across the tested window sizes and zoom levels.
- **Smoke path:** the game smoke now starts Ines's case, recovers all three records through aim/interact, reports the councillor, and fast-travels to both unlocked crossings. **Not run:** this smoke and showcase 95 capture could not be verified because macOS reported the display session locked. Hands-on investigation, controller interaction, and the after-dark narrative timing remain unreviewed.

## Detroit Bile Archive investigation — 2026-10-21

- **Added:** Tavi's Belle Isle case now has three shared trace pickups, three targetable relay controls, a visual institute vault, and Dr. Bile's notes. Each trace reveals its relay symbol and sequence slot; the seeded sequence is drawn from a verified Shrine plan. Wrong inputs restart the relay attempt. Reading the notes enables Tavi's report choice, which sets `bile_exposed` and awards 60 pet XP to the active pet in each present player's personal `Kit`. The quest log follows trace, relay, vault, notes, and report stages. Showcase 96 frames the institute and active traces.
- **Checked:** default `python3 tools/zig.py build check` passes; Zig 0.17 `build check` passes; Bile-focused tests pass **5/5**; the full default headless suite passes **547/547**; `python3 tools/zig.py build -Doptimize=ReleaseFast` passes; `git diff --check` passes.
- **Smoke path:** a scripted smoke is authored to collect all traces, enter the seeded sequence, read/report the notes, and confirm P1/P2 pet XP goes to their separate kits. **Not run:** macOS reported `CGSSessionScreenIsLocked=true`; therefore no Metal capture, windowed smoke, or visual review of showcase 96 was performed. Hands-on play and controller use remain unchecked.

## Detroit Collaborators' Titan and liberation path — 2026-10-21

- **Added:** once all three Detroit allies are exposed and the surface/cave nests and carriers are down, approaching the west Windsor bridge starts the existing Scalari Titan. Two drones and a bulwark join at 66% health; the Titan is stunned for a short core-exposure window at 34%. The bridge pylons display the allies' colors. When the whole encounter is defeated, each present player's `Kit` receives 1200 combat XP, 120 scrap, 18 parts and two rotor cores. Shared progress records the boss defeat and frees Detroit while the Frontier remains clear. The encounter flag persists, but live enemies/phase restart at phase one after loading or a long retreat. Detroit's three Hive base landmarks hide after liberation; broader city-cleanup visuals are not implemented.
- **Checked:** default and Zig 0.17 `build check` pass; Detroit-focused tests pass **8/8**; the full headless suite passes **549/549**; the ReleaseFast install build and `git diff --check` pass. The regression test confirms that either a live nest or carrier keeps the objective on the wilds and prevents the Titan from starting.
- **Smoke and capture:** `MTL_DEBUG_LAYER=1 python3 tools/zig.py build run -Doptimize=ReleaseSafe -Dsmoke-frames=300` passes all 300 frames, including the bridge trigger, both health thresholds, firearm takedowns and P1/P2 reward checks; no Metal validation errors were reported. Showcase 97 was reframed from a high distant view to a lower river-side approach and captured at 2560×1600 under Metal API Validation. The Titan is readable with the three ally pylons; large trees and buildings still fill the background. Hands-on arena sightlines, controller and four-player balance checks remain open. The ten discoveries and their rewards are the next Detroit content step.

## Detroit optional landmark discoveries — 2026-10-21

- **Added:** ten deterministic landmark pickups across the Detroit skyline and river district. Normal aim/interact recovers each item. Seven personal rewards (flight, suit, energy and grapple upgrades, a transit voucher, Gem Aegis and Lumi) are claimed independently in each ranger's `Kit`; three keepsakes set shared `Progress` flags. Pickup props show colored beacons near the party. Kit claim masks are validated and saved in format 26; older saves default to no personal claims. Showcase 98 frames the Undercroft Stash in the plaza side aisle.
- **Checked:** default and Zig 0.17 `build check` pass. The full headless suite passes **549/549**. Its first run reported 547/549: the new discovery target stole a guest's stall target, and a CharacterContent loader stack failure did not recur on the next run. Changing discovery priority fixed the guest case; the guest-trading and market tests then passed filtered, followed by a green full run. Showcase 98 captured frame 120 at 2560×1600 with Metal API Validation enabled on Apple M3 Pro. The cyan beacon is visible between the market and trunk bridge; the fixed camera view still does not show the interaction prompt. No Metal validation errors were reported.
- **Follow-up:** the 300-frame ReleaseSafe Metal smoke now aims at all ten finds with all four seats. Each ranger recovers all seven personal rewards; P1 recovers the three shared keepsakes; every claim and flag survives save/load. Two smoke failures exposed pickup overlaps: the Undercroft Stash sat under a market canopy, and the Pylon Relic shared a ray with salvage. The stash moved to the plaza side aisle, and city discoveries now take priority over relic salvage while stalls and machines retain priority. The final Metal smoke passes with no validation errors. Nearby landmark props now follow any present player, including guests exploring away from P1.
- **Final gates on the follow-up:** default and Zig 0.17 `build check` pass; default headless suite **549/549**; ReleaseSafe Metal smoke passes; the showcase capture passes visual review; ReleaseFast install build and `git diff --check` pass. Zig 0.17 tests were not rerun for this follow-up.
- **Still open:** these are aim/interact checks, not traversal challenges; grapple, swim, glide, wiring and transit methods still lack their own route mechanics. Hands-on route visibility, controller interaction and four-player play remain unchecked. The reclaimed stronghold sites below cover only a small part of city cleanup.

## Detroit reclaimed stronghold sites — 2026-10-21

- **Added:** once shared progress marks Detroit free, its three former outer Hive strongholds are replaced with small pale-stone relay beacons, teal light and native shrubs/bluebells. Before liberation, the original Hive structures remain. This is visual state only; it does not add new collision or a second objective.
- **Checked:** the Detroit Titan integration test now verifies the pre-liberation Hive mesh is replaced by the relay garden props after the boss reward sets `detroit_free`. The showcase-99 ReleaseSafe capture completed at 2560×1600 under Metal API Validation and was visually inspected; the reclaimed signal and plants are visible against the existing skyline. No Metal validation errors were reported.
- **Gates:** default and Zig 0.17 `build check` pass; the Titan-focused filter passes **4/4** and the latest full default suite passes **551/551**. The 300-frame ReleaseSafe Metal smoke, showcases 97 and 99, the ReleaseFast install build and `git diff --check` pass. Zig 0.17 tests were not rerun.
- **Still open:** this only marks the three stronghold sites. There is no citywide damage repair, civilian return behavior or change to the architecture, and the live Titan fight still needs hands-on sightline and controller review.

## Hive air and travel encounter pass — 2026-10-22

- **Added:** the second Hive carrier is now a metallic synthetic command ship and launches tougher robot fighters; insect Brood carriers launch up to eight flyers each at 4.5-second intervals. Surface and cave nests wake within 210 m, support 15 active units each, and reinforce every 5.5 seconds after a shorter initial delay. Both capital ships have kinematic dorsal decks that follow their circuits, support the Kestrel and rangers, and fall with the wreck before being removed. A landing pad marks the deck; players can dismount and keep fighting from the landed Kestrel.
- **Checked:** default `python3 tools/zig.py build check` passes. The full default suite passed **605/605** after the spawn/fighter change; after adding moving decks, the carrier-focused suite passes **11/11**, including a solid-support and motion check. The 300-frame ReleaseSafe Metal smoke passes with API Validation enabled and no Metal errors. Showcase 35 captured frame 120 at 2560×1600 under API Validation; the Kestrel fills the view and the distant carrier deck is not visually legible in this existing framing. `git diff --check` passes. A robot-carrier-specific capture has not been added.

## Space fighter family and route-map plan — 2026-10-22

- **Added:** three sequentially unlockable Scalari fighter frames in the Aircraft fabricator, distinct thrust/lift/hull profiles, owned/equipped progress, and save format 31 defaults for existing Kestrel saves. The current Hangar restores the selected frame and renders its matching hull/glow meshes. The space-combat plan now specifies LOCAL PLANET and SPACE ROUTES GUI layers, with travel gated on playable destinations.
- **Checked:** default `build check` passed before an unrelated in-progress mesh-tool edit appeared in `App.zig` and `Screens.zig`; the full headless suite passed **608/608**; the 300-frame ReleaseSafe smoke passed with Metal API Validation enabled. A later showcase build was blocked by that concurrent edit's three unhandled `Screens.Area` values in the `App.zig` hit-area switch. The attempted showcase 83 is not evidence for these fighter frames; no frame-specific capture or hands-on flight review was completed. Zig 0.17 and ReleaseFast install gates were not run.

## Drop-in Starbowl and GET READY — 2026-10-22

- **Added:** the Starbowl platform is now 72 m square and opens above the party's current location, so pause-menu drop-ins use the current landscape as their backdrop. The three-second wave-one countdown now shows a pulsing GET READY banner that fades out in the final 0.8 seconds. The compact Dogfight square remains a separate planned space venue.
- **Checked:** default `build check` passes; the focused wave/countdown filter passes **4/4**; the 300-frame ReleaseSafe smoke passes with Metal API Validation enabled and confirms arena entry, wave start, clear and rewards. No GET READY capture or hands-on readability review was run. Venue-specific city/biome presets and the Dogfight square runtime remain future work.

## Starbowl location picker — 2026-10-22

- **Added:** the arena menu cycles through Current Landscape, Wilds Overlook, Detroit Skyline, New York Skyline, and Chicago Skyline using keyboard or gamepad arrows/confirm, plus mouse arrows. City sites resolve through the same playable `Region` arrival coordinates used by the world map; the selected point is where the expanded Starbowl opens, and party return positions stay local.
- **Checked:** arena venue anchor and menu-cycle tests pass (**4/4** on the arena filter); default `build check` passes; the 300-frame ReleaseSafe smoke passes with Metal API Validation and the existing arena wave/reward flow intact. Venue-specific captures, hands-on city streaming/readability review, and terrain-specific arena geometry remain open.
- **Still open:** the robot capital ship currently shares the carrier mesh with metallic/blue lighting; its bespoke robot silhouette remains art work. Hands-on deck landings, dismounts, travel combat pacing and balance are unverified.

## Fighter fabricator comparison panel — 2026-10-22

- **Added:** the Aircraft panel now displays the selected frame's live thrust, hull and wing aspect from its Hangar configuration. Kestrel upgrade rows show their current level, and the detail line explains the next level's armor/engine effect or the rack/cooling benefit. Paint rows show equipped/owned/available state in the detail area. Showcase 31 now opens this aircraft panel with all frames unlocked for review.
- **Checked:** default `build check` and the ReleaseFast install build pass. The first API-validated capture revealed that the duplicated inventory chips overlapped the tabs; removing that duplicate leaves the wallet/inventory HUD visible above the panel. Metal API Validation capture 31 at 2560×1600 was visually reviewed after the layout fix. No gameplay, controller, or headless suite was run; those remain needed to verify the full unlock/equip loop in game.

## Orbital arena and robot interceptor art pass — 2026-10-22

- **Added:** generated meshes now include an angular synthetic interceptor, a 240 m open orbital combat ring with four gate pylons and emissive boundary rails, and a low-relief blue/green Gaia backdrop. Showcase 103 places that set with five asteroid cover pieces, the Kestrel, both Hive fighter factions and a Brood carrier. Robot fighter flights now use the synthetic ship mesh instead of reusing the insect dragonfly hull and wings.
- **Checked:** `build check` and a 2560×1600 Metal API Validation capture passed for the ring, cover and ship lineup before the planet backdrop was added. Visual review prompted brighter space lighting, thicker boundary lights, larger cover rocks and a closer camera. A later `build check` after adding the planet backdrop was blocked by unrelated in-progress edits in `Ranger.zig` (runtime float inference at line 169) and `Creator.zig` (unhandled `face_mark` and `eye_color` fields); no errors in the orbital mesh or catalog files were reported. The final planet placement has not been captured. No combat mode, flight controls, or performance budget was verified; this is an art-review scene, not playable space combat.

## Mothership and fighter design pass — 2026-10-22

- **Added:** two more player frames, the high-thrust Starwing interceptor and heavy Bulwark strike fighter, are sequential unlocks after Dreadclaw with different thrust, hull and wing-area settings. The Aircraft fabricator names and equips both. Synthetic carrier launches now alternate between the angular robot interceptor and a faster needle-wing robot lancer; the lancer has its own hull/glow mesh and is rendered without insect wings. New large art meshes define the insectoid Brood Crown and modular synthetic Robot Forge Ark, with contrasting silhouettes, wings/legs/launch sacs versus flight decks/turret towers/light lanes. Showcase 103 includes both motherships and the four extra fighter types.
- **Checked:** existing synthetic-carrier launch coverage recognizes either robot fighter. `python3 tools/zig.py build check` was attempted, but stopped in transitive dependency generation before checking game code: missing cached Ogg headers/objects and Vulkan generator, plus missing `kb_text_shape.h`, `ft2build.h` and Opus `config.h`. Metal capture and visual review of the updated showcase were not possible, and this pass has no new gameplay mothership boss behaviors. The motherships are showcase assets; existing ground-world carriers remain the only functional large ship encounter.

## Orbital service hub design pass — 2026-10-22

- **Added:** a civilian service-hub mesh with a segmented habitation ring, radial structure, four marked docking approaches and solar wings. It is catalogued as shell and emissive meshes and added to showcase 103 as a route-stop visual anchor. This is still scenery; it has no docking interaction or repair/economy behavior.
- **Checked:** `zig fmt --ast-check` on `OrbitalMeshes.zig`, `Catalog.zig` and `App.zig`, plus `git diff --check`. `python3 tools/zig.py build check` remains blocked before game compilation by missing Ogg/Vulkan cache artifacts and missing `kb_text_shape.h`, `ft2build.h` and Opus `config.h`. No Metal capture or visual review was possible.

