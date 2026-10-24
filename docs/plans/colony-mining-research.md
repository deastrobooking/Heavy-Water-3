# Colony: mining, settlers, research and the road to space

**Status:** CM1 implemented 2026-10-24 (ore veins, hand mining, plasma cutter, drill station, shared stockpile, settlers, research tree, launch pad and orbital station as numbers). CM2 onward are planned. The [roadmap](../roadmap.md) stays the single plan. This is step BS5 of the [automation plan](automation-and-defense.md), widened by the owner's request below; it uses that plan's structures, power and shared stockpile, and the settlement plan's light, deterministic economy ([settlement building](settlement-building.md)).

**Owner request (2026-10-24):** explore and build mining stations on Earth and in space; a light Civilization-style layer on Earth; a few mining types and a mining station that runs on its own; a farming path, a population counter, and a science research path that unlocks more futuristic equipment. The owner shared two long idea lists (an "Omni-Select" build window with explosives and energy drills, and real and speculative mining machines) as suggestions, and asked not to make it too complicated.

**Owner decisions (2026-10-24):**
- **Mining types in the first slice:** hand mining, an automated drill station, and the plasma cutter.
- **Research:** one shared team tree. Points come from labs and settlers; unlocks are tools and structures. Personal gear stays in each player's `Kit`.
- **Population:** food and housing drive it; settlers add to drills and labs. A HUD counter shows it.
- **Space:** start now. CM1 gives it a real but small first step: research reaches ROCKETRY and ORBITAL MINING, and each launch pad runs an orbital mining station simulated as numbers. The owner has now directed a physical Asteroid Belt operation and repeatable space battles; the Solar level design is in [Solar democracy](solar-democracy.md#solar-map-and-orbital-activity-before-surface-landings). Visiting the station and building its drone-supported base are later steps.

## Where it sits

This is a separate track from the city liberation loop, like building and automation ([AGENTS.md](../../AGENTS.md)). It gives ore, settlers and research a shared team purpose, while every personal reward (ore you mined and have not deposited, gear, wallet) stays in each player's kit.

## CM1: what is built

| Piece | Where | Rules |
| --- | --- | --- |
| Ore veins | `game/Mining.zig` | 24 seeded veins in a ring 30 to 420 m around the spawn: 12 iron (orange), 8 copper (green), 4 lumen crystal (violet, 180 m and farther). Drawn as a dark boulder with three glowing crystals. Veins do not run out. |
| Hand mining | `Mining.interact` | Hands tool (1), click a vein within 4.5 m: one ore every 0.6 s into P1's kit. |
| Plasma cutter | `Mining.cutterUpdate`, tool 8 | After PLASMA CUTTING: hold fire, a 14 m beam mines 4 ore a second. Heat rises 22% a second and falls 35% a second; at 100% it vents until below 30%. P1 only for now. |
| Deposit | `Mining.depositNear` | Click (hands, nothing aimed) within 7 m of a structure with a store module: all held ore joins the team stockpile. |
| Colony clock | `game/Colony.zig` | One settlement hour per 60 s of play; integer stockpile with fractional carry; at most 4 hours made up in one step. |
| Drill station | starter structure | Drill (12 ore an hour from the vein within 4 m of its footprint, draws 100 W) plus a store. |
| Habitat | starter structure | Housing, 6 beds. |
| Research lab | starter structure | 6 research points an hour, draws 100 W. Click beside it to cycle the research target. |
| Farm field | starter structure | Field module, radius 6 at rate 1: 1.2 food an hour, no power. |
| Supply depot | starter structure | Store only. |
| Launch pad | starter structure | Needs ROCKETRY to build; draws 300 W; with ORBITAL MINING each powered pad adds 6 iron, 2 copper and 3 crystal an hour. |
| Settlers | `Colony.hour` | Each hour settlers eat one food per four; with food left and a free bed, one arrives. A short larder sends a tenth away (at least one); more settlers than beds, the extra leave. Each settler adds 2% to drills and labs, up to 50%. |
| Research | `Colony.info` | PLASMA CUTTING, DEEP DRILLING (drills ×1.5), HYDROPONICS (fields ×1.5), HABITAT MODULES (beds ×1.5), FUSION CELLS (power supply ×1.5), ROCKETRY (launch pad), ORBITAL MINING. Each costs points and ore; the last three need the one before. Ore is taken when it completes. |
| HUD | `ui/Screens.zig colonyPanel` | Under the wallet: settlers / beds, food, stockpile, P1's held ore, and research progress. |
| Guide | `ui/Guide.zig` | A COLONY page and the cutter on the TOOLS page. |
| Save | format 35 | The colony (stockpile, food, settlers, points, researched, target, hours, clock) in the world save; held ore in each kit. Older saves load with an empty colony. |

Power is the existing team-wide supply over demand (`Defense.powerSatisfaction`): build solar arrays beside drills, labs and pads.

## Next steps

Each step is small and playable, proven by a test or smoke stage, and updates these docs.

| Step | Deliverable |
| --- | --- |
| CM2 | **Hands-on pass:** the owner plays CM1; tune rates, costs and vein placement (some veins may land in water or under buildings). A smoke stage that mines, deposits and runs a colony hour. |
| CM3 | **Guests and controllers:** hand mining, the cutter, deposits and the research choice for players 2 to 4 and for pads. Today all four run for P1 on keyboard and mouse only; guests' kits can hold ore but have no way to mine it. |
| CM4 | **Miner and hauler drones** (BS6): a bay module, drones that visibly carry ore from drills to stores. |
| CM5 | **Command view** (BS7): an orbit camera over the colony with the stockpile, income per hour, research choice and alerts. This is the Civilization-style screen. |
| CM6 | **Orbital station visit:** fly from a launch pad to the station (the existing space scene) and see its mining arm work; station upgrades through research. |
| CM7 | **Solar mining base (owner-directed 2026-10-24):** extend the CM4/BS6 miner and hauler state machines to one persistent Asteroid Belt site; use a tethered landing cradle, power, drill/extractor, store, bay and defense. Nearby drones visibly survey, mine and haul; remote output advances on the colony clock. Reuse the shared colony stockpile and CM5/BS7 command view. The physical site replaces that station's flat hourly yield while active, avoiding double-counted orbital output. |
| CM8 | **Solar combat ladder:** seed replayable skirmishes across Luna, Mars orbit, the Asteroid Belt and Kuiper Belt; scale from drone patrols through battleships, transforming Scalari fighters and Mother Ship encounters. Level 10 is a scripted Mars rescue/blockade break, which opens the later heightmap landing stage. |
| CM9 | **More tools from the idea list, behind research:** one explosive (crater charge: fast, wastes part of the ore) and one more energy tool (rotary drill with coolant). Ore yield and heat stay the two tuning surfaces. |

## Deferred from the idea lists

Kept out on purpose to keep the slice small: the nine-by-N slot window and hotbar (the block palette already lists structures), symmetry and mass fill, structural integrity and blast propagation, the material interaction matrix, ore grades, the Midas sorter, and the asteroid lasso. The newly requested orbital track is bounded to one persistent mining site and a ten-level encounter ladder before it expands to more planetary surfaces. New persistent volatile/ice resource kinds wait for a separate economy and save-format decision.

## Risks

- **Balance is untested by hand.** All rates are first guesses.
- **Vein placement** ignores rivers, buildings and the district; a vein can be hard to reach.
- **Save size** grows by a few hundred bytes.
- **Four-player cost:** veins add 96 props, drawn like other frontier props.
