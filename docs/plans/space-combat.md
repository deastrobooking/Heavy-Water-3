# Space travel, fighter frames, and arcade battle arenas

**Owner direction — 2026-10-22:** expand the Kestrel into a family of space fighters and build Solar travel, battle levels, and arenas. The attached feature list defines the arcade combat target: fast readable bullet patterns, score chains, close-range graze risk, limited-use bombs, phased bosses, and insect and robot factions. This track is now active alongside the Earth liberation work; it must keep the local four-player save and reward rules.

## Current foundation

- `vehicle/jet.zig` and `game/Hangar.zig` implement the atmospheric Kestrel with VTOL, lift, airfoil flight, afterburner, guns and missiles. It is a chase-camera aircraft, not a top-down space controller.
- `game/Progress.zig` and the Aircraft fabricator hold the Kestrel's shared armor, missile rack, engine and cooling upgrades, plus paint. A new frame needs an owned/unlocked state, an equipped selection, a save migration and a real performance difference.
- `vehicle/ScalariMeshes.zig` already builds three enemy fighter frames (Ember Wyrm, Void Lance, Dreadclaw) and giant motherships (Throne Serpent and Worldcoil). `Catalog.zig` registers them and showcase 83/84 reviews the small frames. They are enemy meshes today, not player ships or arena bosses.
- The Starbowl is a ground-based four-player wave arena. Its 72 m floor can start over the current location, a nearby wilds overlook, or Detroit, New York, or Chicago, exposing the chosen region as a backdrop. These use the same floating-platform layout; terrain-specific geometry and rooftop venues are future work. `SolarSystem.zig` and `Worlds.zig` describe destinations, but no space travel or orbital arena runtime loads them.

## Experience target

Create a dedicated arcade space-flight mode. Keep the Kestrel's atmospheric flight intact. Space steering must be readable from a top-down 3D camera, keep the action in a bounded battle field, and prioritize lateral dodge movement, aim direction, quick acceleration and braking. The first version is local couch co-op; enemy projectiles and the player's shots use fixed-capacity storage and readable shapes/colors.

Navigation is one GUI entry with two explicit tabs: **LOCAL PLANET** and **SPACE ROUTES**. LOCAL PLANET keeps the current globe and regional map, showing cities, destinations, and nearby points of interest on the world currently being explored. SPACE ROUTES shows the solar-system map, visited planets, unlocked battle sectors and their connecting routes. Selecting a space node opens its battle or service stop when that content is playable; locked or planned planets remain visible as unavailable, never as dead-end travel choices. Both tabs must support keyboard, mouse and gamepad, preserve the selected layer on reopen, and clearly mark the current player/world and destination.

A run should move through a short chain of authored orbital battle sectors, with a service/rest stop between sectors. A sector introduces one arena pattern, then mixes patterns, then ends with a giant ship boss. Keep the compact Dogfight square as the tight aerial challenge. Expand the ground battle venue modestly and let a drop-in arena frame the current terrain or city as its backdrop; later venue presets can select a wilds overlook or a city rooftop district. The route map is the travel layer; travel is a choice of connected playable destinations, not a cutscene or list of unreachable worlds.

## Ordered slices

| Slice | Player-visible result | Gate |
| --- | --- | --- |
| S0 — Fighter family | Kestrel plus three unlockable frames based on the existing alien designs. Aircraft tab shows frame silhouette, handling profile, cost, prerequisite and equipped state. Frame-specific handling changes speed, turn response, shields and weapon capacity; existing upgrades apply to the selected frame. | Save round-trip and old-save migration; blocked purchases leave wallet/progress unchanged; all four models render in flight and on landing pads. |
| S1 — Space handling test | Dedicated space control mode with top-down chase camera, fixed arena bounds, strong lateral acceleration, dash/afterburner, quick deceleration and no terrain gravity. | Physics tests for bounds, brake and boost; Metal capture and hands-on keyboard/gamepad review. |
| S2 — First arena, Brood Interception | One reusable orbital arena with entry/exit gates, cover asteroids, kill boundary, three insect wave patterns, readable hostile projectiles, score/chain, close graze meter, a panic bomb and end-of-wave rewards to each player's Kit. Preserve the compact Dogfight square and expand the location picker to playable Antarctic, mountain, and rooftop venues as those arenas are built. | Four-seat smoke proves damage, enemy attacks, bomb projectile cancel, scoring and per-player rewards; measured frame budget at the maximum projectile count. |
| S3 — Giant carrier boss | Brood carrier boss with destructible turrets and launch bays, exposed core windows, fighter launches, phase changes and a large crash/debris finale. | Boss phase, weakpoint and co-op reward tests; boss can be defeated with each starter frame. |
| S4 — Robot Armada sector | Robot fighters use predictive but telegraphed aimed lines and pincer/formation patterns. A robot carrier adds turret grids, shield generators and EMP tells. | Faction tests and readable bullet-density cap; capture with both factions in frame. |
| S5 — Solar route and service stop | Add the SPACE ROUTES tab beside LOCAL PLANET in the map GUI. The solar map selects a connected sector and travel arrives at an orbiting service platform where players repair, spend credits on upgrades and pick the next battle route. | Both map layers work with keyboard, mouse and gamepad; save/reload route and unlocks; destination selection is limited to sectors with a playable arrival arena. |
| S6 — Broader arsenal | Add weapon slots, spread, laser, wave, homing, rail, arc, flak, bounce and drill options only as arena encounters require them. Add smart-bomb variants after the first bomb's bullet-cancel and score conversion work. | Each weapon has a distinct readable job and a combat test; do not ship the feature list as an unbalanced menu dump. |
| S7 — Boss and faction expansion | Hive Queen, Mantis Duelist, Beetle Juggernaut, AI Core and hybrid bosses reuse tested phase/weakpoint/pattern primitives. Insect/robot fights, corruption and adaptive AI are later experiments. | New boss uses existing arena primitives and does not exceed the measured object/projectile budget. |

## Design constraints

- Keep the first playable route short: one service platform, two arenas and one Brood carrier boss. Build a second faction only after the first run is fun and stable.
- Keep ship upgrades and campaign progress shared as they are today; combat score and consumable pickups belong to each player's `Kit` unless a reward explicitly advances shared story.
- Give each projectile a small collision radius, a telegraph, a fixed lifetime, and a clear cancellation rule. A bomb must clear hostile shots and convert them into score/pickups without allowing score farming from one repeated pattern.
- Cap live enemy shots and enemies. When a cap is reached, skip or replace spawns deterministically; never allocate in the frame loop.
- Boss attacks communicate the safe lane and the damage window before firing. A phase transition clears or resolves old bullets before introducing the next pattern.
- The existing giant Scalari mothership meshes are art inputs, not proof of a playable ship. Add landing, collision, boss parts, attacks, and rewards before calling one complete.
- Continue the city loop in parallel in small commits. This Solar track does not change the MVP save separation or add networking.

## First implementation order

1. Wire the existing three Scalari fighter meshes into a persistent, sequential Aircraft frame unlock/equip path with distinct handling stats.
2. Add a dedicated `SpaceFlight` controller and a capture/test ring without changing atmospheric Kestrel controls.
3. Build the Brood Interception arena and its score/graze/bomb loop.
4. Make the first giant carrier a real phased boss; then connect the playable arena and service stop through the SPACE ROUTES map layer before adding further sectors.
