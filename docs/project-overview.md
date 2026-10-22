# Heavy Water: Project Overview

Heavy Water is a native Zig exploration and engineering game set on a future Earth where advanced technology grows alongside a vast, wild biosphere. Its visual and thematic direction pairs luminous wilderness and ancient mysteries with practical machines, a living canopy city, and science-fiction traversal.

This document is a player-facing overview of the current prototype. The [roadmap](roadmap.md) tracks what is implemented and what comes next; the [architecture guide](architecture.md) records technical ownership and constraints.

## The World

The Rootdeep is a wild forest floor of ruins, seed vaults, and shrines. Above it, enormous Arbors draw groundwater through living wood and concentrate deuterium in their sap. Settlements climb the trunks into the Crown, connected by towers, plazas, and bridges. Nature and machinery are interdependent: sap powers devices, roots carry signals, and the city changes as players build.

The current playable world centers on Detroit, Michigan, reimagined as the Detroit Arbor Reach: a bounded seeded canopy district with three distinct Arbors, modern and Gothic towers, an industrial skyline and riverfront, Belle Isle, two Windsor crossings, markets, traffic, pedestrians, Rootsong networks, and two solver-verified shrines. Smaller pines now bridge the streetside parks and the giant wild forest. It is a substantial systems prototype, not yet the full open-world wilderness or civilization simulation described in the long-term vision.

See [World and Systems](world.md), [Arbor Genomes and Sap](arbors.md), [Canopy City](city.md), and [Rootdeep Shrines](rootdeep.md).

## What You Can Do

- Explore on foot, climb, wall-jump, grapple, hover, fly, glide, dash, swim, and ride a hoverboard.
- Create and customize a ranger, switch between first- and third-person views, and play local split-screen with up to four players.
- Fabricate one of three hover racers and run the elevated sprint loop, chaining its ramps, jump gaps, magnetic vertical loop, checkpoints, and charge pads; completed best laps appear on the HUD and persist in the world save.
- Build and wire machines, ride a powered rover, place sap beacons, add bridges, and capture machine circuits as reusable prefabs.
- Solve shrines, salvage relics, trade at markets, and save or restore your constructed world.
- Grow the district through procedural Arbors, powered Rootsong networks, and player-built connections.

The Hive conflict is connected to the playable campaign: nests spread corruption, ground units and air wings attack, carriers can be assaulted in stages, and story flags drive the quest log through the end state. Combat pacing, balance, and four-player combat readability still need hands-on playtesting. Each of up to four players keeps their own saved character, gear, wallet and pets (save format 13, plus a portable ranger file per player). Four bio-synth pets can be freed from Hive collars to follow, fight, mend and level up beside P1 ([architecture](architecture.md#field-wildlife-and-companions)); guest pets and pet evolutions remain future work, as does the broader loot progression. See [The Hive War: Gameplay Direction](gameplay_and_hive_war.md) and [the roadmap](roadmap.md) for current limits.

The campaign expansion spans the Arbor Frontier, Hive/Scalari Homeworld, Gaia and all eight canonical Solar System planets. `procedural/SolarSystem.zig` catalogs twelve moons and Scalari mining fronts alongside settlement and governance data. The intended loop uses fast travel between planets/moons, local ship flight, and station docking/building; continuous interplanetary flight is out of scope. The fictional fusion-pulse drive is rated for strategic travel at 0.5c. The [Solar Democracy plan](plans/solar-democracy.md) defines the voluntary Galactic Democratic Compact, staged city-planet growth and Venus terraforming, plus the planned winged Kestrel transformation into a space interceptor and Colossus mech. Gaia remains an Earth-radius artificial habitat in Saturn space. The existing design foundation also names city regions, three capital sites, and a final Scalari Sovereign battle at the Obsidian Coil. The Arbor Frontier has catalog concepts for human pressure-dome city Pelaglass and fully submerged cetacean city Sonorous Reef; the [ocean-cities plan](plans/ocean-cities.md) proposes the Tideborn champion and underwater combat slice. Five procedural Scalari ship meshes establish the dragon-armor visual family; they are catalog assets but not flyable yet. Arena loot will feed modular ship fabrication and real-time outpost defense. The [Planetary Frontier plan](plans/planetary-frontier.md) defines the campaign and implementation gates; the worlds and cities are not playable yet.

## Controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move |
| Space | Jump; use traversal abilities while airborne |
| Shift | Sprint or increase flight speed |
| Left Alt | Air brake in powered or free flight; also brakes the Kestrel |
| Left Ctrl | Ground roll / dodge, hoverboard boost, or flight dash; double tap on foot for a powered dash |
| X | Air stomp |
| G | Grapple (grapple traversal kit) |
| B | Cycle traversal kit: grapple, hover jet, flight, hoverboard |
| F | Hold a ledge, then mantle |
| V | Toggle walking and free-flight modes |
| F2 / F4 | Change camera view / customize your ranger |
| 1 / 2 / 3 / 4 / 5 / 6 / 7 | Hands / build / wire / bridge / weapon / terrain / block tools |
| Block tool (7) | Click places the chosen block in the 1 m grid beside the surface you aim at (14 m reach); right click removes the aimed block. Tab cycles cube, slab, ramp and stair; [ and ] cycle the castle materials (stone, dark stone, sandstone, timber, slate, moss stone, iron, banner red); T turns the block; P picks up the aimed block's shape, material and turn. Hold Shift and click two corners to fill (or right click two corners to clear) a box of up to 512 cells. Shift+Tab changes style (castle, dungeon, eco city, farm; eight materials each), and Tab also reaches the style's starter pieces (castle tower, wall run, gatehouse; dungeon cell, corridor; greenhouse, walkway; barn, fence, planter), which are laid whole, centred on the crosshair. Shift+T on two corners re-skins a box into the current style, role for role (main stone becomes brick, planks or living wood); Shift+P on two corners copies a box, which Tab then offers as CLIPBOARD to paste. Every block comes from your own stock (256 of each material to start, shown on the palette strip); removing a block returns it to whoever removed it. A block needs the ground or another block beside it. Stairs collide as a walkable ramp |
| Platformer blocks | The PLATFORMER style (Shift+Tab to reach it) holds the mechanisms: SPRING launches you about 11 m up, BOOST STRIP flings you along its facing (turn it with T), CRUMBLE falls away 0.6 s after you land and returns 4 s later, HAZARD hurts (20 per 0.6 s, standing on or walking into it), CHECKPOINT becomes the place you recover when knocked out, PRESSURE PLATE opens every GATE while anyone stands on it, MOVER slides 4 m along its facing and back, carrying you. Starter pieces: JUMP COURSE, GATE ROOM, MOVER BRIDGE |
| Building on a pad (any player) | Hold the sprint button (LT) and press D-pad left to start or stop building. RT places, RB removes, D-pad up changes shape (LT + up picks the aimed block), left and right change material, down turns, LT + right changes style; hold LT while clicking to mark box corners, LT + down for restyle corners and LT + up for copy corners |
| Terrain tool (6) | Hold left click to sculpt the ground under the crosshair (60 m reach). Tab cycles raise, lower, level and smooth; [ and ] resize the brush (2 to 24 m); right click undoes the last stroke and T redoes it. Sculpting is refused within 60 m of a cave mouth |
| Weapon tool | Left click or trackpad click fires; hold to charge or draw. The first click also captures mouse look and fires immediately. Right button is the alternate; Tab switches weapons. Saber: click cuts (click again mid-cut to chain the combo), the third quick cut fires a weaker crescent, and hold after a cut to charge the stronger wave. Dash + attack cuts through; attack while rising, falling/stomping, or neutral in air gives an up, down, or spin slash. Attack + dodge throws the returning blade. Right button guards. Sniper: right button scopes. Heavy rifle: hold right to charge. Bazooka: right detonates the orb |
| Z / C / H | Class specials. Ranger: arc grenade, sentry turret, overshield. Synthetic: phase dash, kinetic slam, lumen lance |
| Left click the starter Skimmer, hands | Board it. W / S drive, A / D turn, Space or E climb, Q descend, Shift boost, F to leave |
| Left click the fabricator kiosk | Fabricate cars, suits, armor, weapons and the Kestrel fighter from pickups |
| Left click the Kestrel, hands | Board it. Mouse aims (the jet flies where you point), W / S throttle (S also brakes), A / D roll, Space or E climb and Q sink while hovering, Shift afterburner, Left Alt air brake, left button cannons, hold right button to lock and release to fire a missile, F climbs out |
| Q / E | Descend / ascend in flight |
| Left click and mouse / trackpad | Capture pointer and aim; the click also fires the current weapon or performs the current hands action |
| Left click (captured), hands | Grab or drop a crate, press a machine button, enter or exit the rover |
| Right click (captured), hands | Salvage the relic under the crosshair |
| Left click a stall keeper or pedestrian, hands | Talk. Up / Down or 1–6 choose a reply, Enter says it, Escape leaves. Keeper replies open the trade, upgrade, or wardrobe panels |
| In any menu or panel | Arrows or W / S choose, Left / Right change, Enter or Space confirm, Escape back; the mouse hovers and clicks |
| Build tool | Escape → BUILD opens the inventory; choose a card; T rotates; left click places; right click removes |
| Wire tool | Click source then target; Tab cycles port pairs; right click disconnects or cancels |
| Bridge tool | Tab selects bridge style; click two plaza markers to build; right click cancels or removes |
| P / I | Capture the aimed machine as a prefab / inspect the aimed machine |
| [ / ] | Change an aimed Rootsong transmitter or receiver channel (1–64) |
| Shrine buttons | Red toggles latches; gold opens the vault; blue resets the shrine |
| W / S, A / D (driving) | Throttle / reverse and steer |
| Space (driving) | Brake |
| F5 / F9 | Quicksave / quickload |
| R | Return to spawn |
| Escape | Pause menu: resume, heroes, hero arena, customize, quest log, save, load, settings, controls, quit. Every key in this table except Escape and Enter can be rebound under Controls |
| Left click a Wildkin hero, hands | Meet them: they join your heroes (look for the beams of light in the city, the wilds and the mountain caves) |
| Pause > HEROES | Choose a tab (P1–P4), then a joined hero to play as them, or YOUR RANGER to switch back |
| Pause or title > HERO ARENA | Take the party into the Starbowl: Hive waves, loot after each, a new hero every third wave |
| F7 / F1 | Toggle culling / toggle metrics |
| Window close | Quit |

## Local Co-op

Up to four players share one window in split screen. On macOS, controllers exposed by Apple's Extended or Micro Gamepad profile or generic HID joystick/gamepad devices join with **Menu**; an already joined guest opens the party setup. Disconnected players keep their slot and character. The first controller operates P1 alongside the keyboard; the next three operate P2–P4. The game reports the detected vendor/product category. Xbox-, PlayStation- and Switch-style controllers use macOS's standard profile mapping where available, and unfamiliar HID pads can be remapped in Gamepad Setup. F6 adds or removes a keyboard-less guest for testing.

| Controller input | Action |
| --- | --- |
| Left / right stick | Move / look |
| A | Jump or lift the Kestrel vertically from its pad |
| B | On foot, tap to roll, boost, or dash; in flight, hold to air-brake; closes a market stall (P1: back in any menu) |
| X (left face button) | One contextual interact button: meet/recruit a nearby hero, talk or trade, board/exit nearby vehicles from any selected tool, operate machine buttons, salvage relics, or inspect an aimed machine structure; hold to hang and mantle. A remains jump. |
| D-pad | On foot, left / right switch owned weapons and up / down trigger specials 1 and 2 (up with RB held: special 3). During flight, up / down climb and descend. P1's menus and panels use the D-pad for navigation; a market stall uses up/down for rows. |
| Movement gestures | Hold W + Shift and press Space for a long jump; hold S and press Space while moving for a backflip. Tap Left Ctrl for a ground roll or short air evade; double tap within 0.42 seconds for a powered dash, then repeat to chain up to four boosts. Hold W and tap Left Ctrl three times within 0.92 seconds to launch into sustained forward flight; hold Shift to accelerate (every 1.2 seconds of held boost doubles your speed, up to four times the boost speed), steer with movement/look, use Space to climb, Left Alt to brake, and dash for a 76 m/s burst. Controller: hold forward + LT and press A for a long jump; hold back and press A while moving for a backflip; on foot, tap B to dodge or double tap to dash, and hold forward while tapping B three times to engage flight. In flight, hold B to air-brake. |
| In any menu or panel (P1's controller) | D-pad or left stick moves (hold to repeat), A or X chooses, B goes back, right stick scrolls panels taller than the screen |
| Right trigger | Fire the selected energy weapon; starts with level 1 rapid shot (machine gun). In the Kestrel, fires its cannons |
| RB | Quick-draw the beam saber; tap for a cut, three quick cuts fire a weaker crescent, hold then release for a charged wave. In the Kestrel, hold to lock a missile and release to fire |
| RB + B | Throw the saber; it pierces enemies and returns |
| Menu (P1's controller) | On the title, start (CONTINUE or NEW GAME, whichever is highlighted); in the creator, finish; in play, open or close the pause menu. P1 can start and play the whole game from a controller |
| Right stick click (R3) | First- / third-person view |
| LB / Y | Grapple / cycle traversal kit |
| LT | Sprint |
| Left stick click | Stomp |
| Select / Options | Open the individual player menu (hero, party setup, map) |

Every new game and legacy save includes the level 1 machine gun and beam saber. Homing missiles and other energy weapons remain fabrication unlocks. RB returns to the previously selected energy weapon after the saber cut finishes.

Use **Local Co-op Setup** on the title or **Four Player Setup** from pause to select a player, join/leave, assign a controller, or swap with the next occupied screen position. Assigning a controller exchanges its previous assignment so ownership stays unique. P1 remains the host; controller assignments and guest characters are session-only.

**World Map / Fast Travel** is available from pause and each player menu. The regional map uses biome colors and terrain relief, centers on the selected player, and marks joined players, base camp, and two Rootdeep shrines. Left/right zoom between 350, 700, and 1400 meters across; destination rows show horizontal distance and ground altitude. Use **Frame Destination / Player** to center the last selected destination or return to your player. Markers labeled **OFF** sit at the map edge and include a compass direction; clustered player labels are separated. Choose a destination to move the selected player; other players stay where they are. Travel preserves the traversal kit, suit upgrades, fuel, and stamina while clearing motion and interactions. Travel is unavailable in the arena; the host must exit their vehicle, but guests can travel independently. The map displays the reason when travel is blocked, and unavailable travel rows are disabled for mouse, keyboard, and controller. Arrival searches up to 12 meters along each ground axis for body clearance and a gentle slope; if no spot fits, travel fails without moving the player. Back returns to the menu that opened the map. These initial destinations are available immediately.

Guests can traverse, press machine buttons, and trade using the shared wallet. Building, wiring, carrying, driving, salvage, and saving remain P1's actions. Guests are not saved and rejoin beside P1 after loading.

The Controls screen keeps keyboard bindings and gamepad setup in separate tabs and includes short flight and combat guides. **Controls → Gamepad Setup** can capture each action onto a button, including the air brake; it also changes which physical stick axes drive movement and aiming, inverts individual axes, and tunes the stick deadzone or analog trigger point. Eight JSON preset slots live in `saves/controller-presets/`; Export creates a shareable file through the macOS Save dialog, and Import selects a downloaded preset through the Open dialog. Older presets keep their existing mappings and get the default air-brake button. The format is platform-neutral and records the controller label when one is available. macOS also scans generic HID gamepads; devices with unusual interfaces or unavailable OS access may still need backend support. Linux and Windows gamepad backends are not implemented yet.

The [controller preset format](controller-presets.md) documents the upload/import flow and field meanings for the community preset page.

## How It Is Built

The engine is written in Zig; Mach supplies the platform, window, input, and GPU foundation.

- **Procedural world:** versioned seeded generation, continuous biome masks, deterministic scatter, and asynchronous chunk streaming with bounded CPU/GPU pools.
- **World simulation:** native Zig physics, a swept character controller, rigid vehicles, machine power and signal networks, and root-linked Rootsong.
- **Creation:** grid-snapped building, blueprint-driven machines, wiring, player bridges, prefab capture, and versioned world saves.
- **Rendering:** instanced meshes, cel shading, atmospheric haze, terrain streaming, level of detail, and CPU/GPU visibility work within the pinned Mach capabilities.
- **Extensibility:** validated asset compilation and a constrained WebAssembly mod API.

The project prioritizes bounded storage, explicit ownership, deterministic tests, and playable vertical slices. Some larger-engine features remain limited by the current renderer and prototype scope; the roadmap and validation notes document these boundaries.

See [Architecture and Ownership](architecture.md), [Mod API](mods.md), and [Scale Tests](scale.md).

## Current Limits

- Validation is strongest on Apple Silicon with Metal. Linux/Vulkan and Windows/D3D12 runtime behavior still needs testing.
- Some gameplay systems are bounded prototypes rather than scalable open-world systems; consult the phase limits in the roadmap.
- Reported frame intervals include presentation pacing and are not GPU execution timings.

See [Validation](validation.md) for tested configurations, benchmark methodology, and remaining checks.
