# Heavy Water: Project Overview

Heavy Water is a native Zig exploration and engineering game set on a future Earth where advanced technology grows alongside a vast, wild biosphere. Its visual and thematic direction pairs luminous wilderness and ancient mysteries with practical machines, a living canopy city, and science-fiction traversal.

This document is a player-facing overview of the current prototype. The [roadmap](roadmap.md) tracks what is implemented and what comes next; the [architecture guide](architecture.md) records technical ownership and constraints.

## The World

The Rootdeep is a wild forest floor of ruins, seed vaults, and shrines. Above it, enormous Arbors draw groundwater through living wood and concentrate deuterium in their sap. Settlements climb the trunks into the Crown, connected by towers, plazas, and bridges. Nature and machinery are interdependent: sap powers devices, roots carry signals, and the city changes as players build.

The current playable world is a bounded, seeded canopy district with three distinct Arbors, generated towers and roads, markets, traffic, pedestrians, Rootsong networks, and two solver-verified shrines. It is a substantial systems prototype, not yet the full open-world wilderness or civilization simulation described in the long-term vision.

See [World and Systems](world.md), [Arbor Genomes and Sap](arbors.md), [Canopy City](city.md), and [Rootdeep Shrines](rootdeep.md).

## What You Can Do

- Explore on foot, climb, wall-jump, grapple, hover, fly, glide, dash, swim, and ride a hoverboard.
- Create and customize a ranger, switch between first- and third-person views, and play local split-screen with up to four players.
- Fabricate one of three hover racers and run the elevated sprint loop, chaining its ramps, jump gaps, magnetic vertical loop, checkpoints, and charge pads; completed best laps appear on the HUD and persist in the world save.
- Build and wire machines, ride a powered rover, place sap beacons, add bridges, and capture machine circuits as reusable prefabs.
- Solve shrines, salvage relics, trade at markets, and save or restore your constructed world.
- Grow the district through procedural Arbors, powered Rootsong networks, and player-built connections.

The Hive conflict is connected to the playable campaign: nests spread corruption, ground units and air wings attack, carriers can be assaulted in stages, and story flags drive the quest log through the end state. Combat pacing, balance, and four-player combat readability still need hands-on playtesting. Recruitable bio-synth companions and the broader loot progression remain future work. See [The Hive War: Gameplay Direction](gameplay_and_hive_war.md) and [the roadmap](roadmap.md) for current limits.

The next campaign expansion spans the Arbor Frontier, the Hive/Scalari Homeworld, and Gaia, an Earth-radius artificial planet with a rotating human colony inside a geodesic sky shell beyond Jupiter. Its design foundation now names five city regions on each destination, three capital sites, and a final Scalari Sovereign battle at the Obsidian Coil. Five procedural Scalari ship meshes (three fighters and two motherships) establish the dragon-armor visual family; they are catalog assets but not flyable yet. Arena loot will feed modular ship fabrication and a real-time outpost-building/defense loop. The [Planetary Frontier plan](plans/planetary-frontier.md) defines the campaign and implementation gates; the worlds and cities are not playable yet.

## Controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move |
| Space | Jump; use traversal abilities while airborne |
| Shift | Sprint or increase flight speed |
| Left Ctrl | Roll, hoverboard boost, or flight dash |
| X | Air stomp |
| G | Grapple (grapple traversal kit) |
| B | Cycle traversal kit: grapple, hover jet, flight, hoverboard |
| F | Hold a ledge, then mantle |
| V | Toggle walking and free-flight modes |
| F2 / F4 | Change camera view / customize your ranger |
| 1 / 2 / 3 / 4 / 5 | Hands / build / wire / bridge / weapon tools |
| Weapon tool | Left click or trackpad click fires; hold to charge or draw. The first click also captures mouse look and fires immediately. Right button is the alternate; Tab switches weapons. Saber: click cuts (click again mid-cut to chain the combo), hold after a cut to charge a wave, right button guards (parries bolts at first). Sniper: right button scopes. Heavy rifle: hold right to charge. Bazooka: right detonates the orb |
| Z / C / H | Class specials. Ranger: arc grenade, sentry turret, overshield. Synthetic: phase dash, kinetic slam, lumen lance |
| Left click a hover car, hands | Board it. W / S thrust, A / D turn, Space or E climb, Q descend, Shift boost, click to leave |
| Left click the fabricator kiosk | Fabricate cars, suits, armor, weapons and the Kestrel fighter from pickups |
| Left click the Kestrel, hands | Board it. Mouse aims (the jet flies where you point), W / S throttle, A / D roll, Space or E climb and Q sink while hovering, Shift afterburner, left button cannons, hold right button to lock and release to fire a missile, F climbs out |
| Q / E | Descend / ascend in flight |
| Left click and mouse / trackpad | Capture pointer and aim; the click also fires the current weapon or performs the current hands action |
| Left click (captured), hands | Grab or drop a crate, press a machine button, enter or exit the rover |
| Right click (captured), hands | Salvage the relic under the crosshair |
| Left click a stall keeper or pedestrian, hands | Talk. Up / Down or 1–6 choose a reply, Enter says it, Escape leaves. Keeper replies open the trade, upgrade, or wardrobe panels |
| In any menu or panel | Arrows or W / S choose, Left / Right change, Enter or Space confirm, Escape back; the mouse hovers and clicks |
| Build tool | Tab changes palette item; T rotates; left click places; right click removes |
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
| A | Jump |
| B | Roll, boost, or dash; closes a market stall (P1: back in any menu) |
| X | Press the aimed button or open a stall; hold to hang and mantle |
| D-pad | Choose a market stall row (P1: navigate any menu or panel); left / right switch weapons; away from a stall, up and down use specials 1 and 2 (up with RB held: special 3) |
| In any menu or panel (P1's controller) | D-pad or left stick moves (hold to repeat), A or X chooses, B goes back, right stick scrolls panels taller than the screen |
| Right trigger | Fire the selected energy weapon; starts with level 1 rapid shot (machine gun) |
| RB | Quick-draw the neon-purple beam saber with blue electrical pulses; tap for a cut, hold then release for a charged wave |
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

Choose **Controls → Gamepad Setup** to capture each action onto a button, change which physical stick axes drive movement and aiming, invert individual axes, and tune the stick deadzone or analog trigger point. Eight JSON preset slots live in `saves/controller-presets/`; Export creates a shareable file through the macOS Save dialog, and Import selects a downloaded preset through the Open dialog. The format is platform-neutral and records the controller label when one is available. macOS also scans generic HID gamepads; devices with unusual interfaces or unavailable OS access may still need backend support. Linux and Windows gamepad backends are not implemented yet.

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
