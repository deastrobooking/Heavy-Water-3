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
| Weapon tool | Left button fires (hold to charge or draw), right button is the alternate, Tab switches weapons. Saber: click cuts (click again mid-cut to chain the combo), hold after a cut to charge a wave, right button guards (parries bolts at first). Sniper: right button scopes. Heavy rifle: hold right to charge. Bazooka: right detonates the orb |
| Z / C / H | Class specials. Ranger: arc grenade, sentry turret, overshield. Synthetic: phase dash, kinetic slam, lumen lance |
| Left click a hover car, hands | Board it. W / S thrust, A / D turn, Space or E climb, Q descend, Shift boost, click to leave |
| Left click the fabricator kiosk | Fabricate cars, suits, armor, weapons and the Kestrel fighter from pickups |
| Left click the Kestrel, hands | Board it. Mouse aims (the jet flies where you point), W / S throttle, A / D roll, Space or E climb and Q sink while hovering, Shift afterburner, left button cannons, hold right button to lock and release to fire a missile, F climbs out |
| Q / E | Descend / ascend in flight |
| Left click, then mouse | Capture pointer and look |
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
| Escape | Pause menu: resume, customize, save, load, settings, controls, quit. Every key in this table except Escape and Enter can be rebound under Controls |
| F7 / F1 | Toggle culling / toggle metrics |
| Window close | Quit |

## Local Co-op

Up to four players share one window in split screen. On macOS, supported extended-profile controllers join and leave with **Menu**; disconnecting a controller also leaves. F6 adds or removes a keyboard-less guest for testing.

| Controller input | Action |
| --- | --- |
| Left / right stick | Move / look |
| A | Jump |
| B | Roll, boost, or dash; closes a market stall (P1: back in any menu) |
| X | Press the aimed button or open a stall; hold to hang and mantle |
| D-pad | Choose a market stall row (P1: navigate any menu or panel); left / right switch weapons; away from a stall, up and down use specials 1 and 2 (up with the right stick held: special 3) |
| Right trigger | Fire the party's selected weapon (hold to charge or draw) |
| Right stick click (held) | The weapon's alternate: saber guard, scope, charge |
| Menu (P1's controller) | Open or close the pause menu |
| Y | First- / third-person view |
| LB / RB | Grapple / cycle traversal kit |
| LT | Sprint |
| Left stick click | Stomp |
| Options | Respawn beside P1 |

Guests can traverse, press machine buttons, and trade using the shared wallet. Building, wiring, carrying, driving, salvage, and saving remain P1's actions. Guests are not saved and rejoin beside P1 after loading.

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
