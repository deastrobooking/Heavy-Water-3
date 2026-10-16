# Settlement: city planning, building, farming, terraforming and mining

**Status:** proposed, 2026-10-15. Planning only; nothing here is built. The [roadmap](../roadmap.md) stays the single plan. This is the design for the "Grow" pillar of [world](../world.md) ("guide the city and the trees themselves: graft new branches, plan bridge roads, raise districts"), extended with farming, terraforming and mining.

**Owner decisions (2026-10-15):**
- **Hybrid sandbox with light simulation:** free placement of districts, buildings, roads and farms, plus a modest loop of power, water, food, materials and population that gives players reasons to build. Not a full city-builder.
- **One shared settlement** with a shared stockpile. Each structure records who built it. Personal rewards (gear, upgrades) stay in each player's own `Kit`.
- **Build sites:** ground claims **and** Arbor shelves.
- **Terraforming:** bounded stamps near settlements, stored as a compact edit layer; the rest of the world stays procedural.
- **Seasons:** the global calendar in [weather and seasons](weather-seasons.md) drives farming.
- **Losses:** storms and Hive raids can destroy crops.
- **Settlers:** a count drives the simulation **and** a bounded sample of settlers is visible as people.
- **Stockpile access:** any player can withdraw from the shared team stockpile, **with no caps** (withdrawals are still logged per player).
- **Weather damages structures** (storms, heavy highland snow); repair is paid from the stockpile.
- **Claim sizes:** left to me; chosen in section 4 (40 m growing to 96 m by settlement level).
- **Mining depth:** down to the **deepest known mine in the world**, about **4,000 m** (Mponeng in South Africa).
- **Full irrigation systems:** wells, tanks and reservoirs, channels, aqueducts, pipes, pumps, gates, sprinklers and drains (section 7).
- **Weather and seasons** (see that plan): seasons do not change sap or machine power; highland ice is walkable; night glow stays on for every tree.

**Audience:** engineers and coding agents. The five Zig blocks labelled *compiled* (eleven tests) passed `zig test` on the default compiler (`0.16.0-dev.3142+5ccfeb926`) and on `HEAVYWATER_ZIG_CHANNEL=0.17`, and were extracted back out of this document and re-tested. Each module's tests were also checked by deliberately breaking its logic. They illustrate the design and are not committed code.

## 1. Principles

1. **A shared place, personal rewards.** The settlement is the team's: one stockpile, one population. Gear, upgrades, wallet and pets never go into it ([AGENTS.md](../../AGENTS.md)); a player *contributes* from their `Kit` by an explicit action.
2. **Light simulation, deterministic.** The economy advances in whole settlement hours (3,600 ticks, one real minute) with integer arithmetic. Growth and production are derived from the saved tick, so a reload, an offline gap and a capture all agree.
3. **Bounded everything.** Fixed capacities for claims, plots, structures, fields and edits, each checked at load, so a bad save cannot blow memory and a long game cannot outgrow the 4 MiB save limit.
4. **Validate, then apply.** A rejected placement, edit or load leaves state unchanged, as for builds, bridges and saves today.
5. **The world stays procedural.** Settlements sit on top of the seeded world: scatter ids, rivers, caves and the fixed district do not move.
6. **Four players, one screen each.** Everyone can contribute and harvest; building input for guests follows the co-op completeness milestone ([next steps](next-steps.md)).
7. **Native Zig, no frame allocation.**

## 2. What exists, and the limits that force new structures

| Area | Today | Source |
| --- | --- | --- |
| Building | `Build.preview` snaps to a 0.5 m grid, validates with a physics overlap test and a 5x5 grid of support rays, 14 m reach. Every building is a **machine**: at most 16 machines, 16 prefabs, 24 devices and 16 parts per machine. Spending uses `kits[0]` only. | `game/Build.zig`, `machine/Blueprint.zig`, `game/Sandbox.zig` |
| Bridges and plazas | 6 fixed plazas, 4 player bridges (`District.max_bridges`), grade at most 6 percent, persisted as plaza-id edges. | `procedural/District.zig`, `game/BridgeTool.zig` |
| Economy | Per-player `Wallet` (scrap, parts, kits), `Kit` inventory of four collectible kinds, fabricator recipes with costs, 3 market stalls. **No production, storage, upkeep, population or zoning.** | `city/Market.zig`, `game/Kit.zig`, `game/Fabricator.zig` |
| Sap | `Sap.allocate` shares a tree's vascular capacity among taps; trees have up to 512 nodes and 8 natural shelves each. | `machine/Sap.zig`, `procedural/Arbor.zig` |
| Terrain | pure `Noise.height(seed, x, z)`, used by `Chunk.fill`, `Terrain.surface` (103 call sites), Scatter, Biome, Caves, Mountains; `Terrain.surface` and the chunk mesh must agree exactly. No edit layer; `Modifications` stores only removed object ids (cap 4,096). | `procedural/*.zig`, `world/Modifications.zig` |
| Streaming | a worker generates chunks; there is no per-chunk invalidate. | `world/Streamer.zig` |
| Mining | deterministic caves with static meshes and colliders; the only harvest is one-shot relic salvage; no ore, depletion or digging. | `procedural/Caves.zig`, `game/Sandbox.zig` |
| Farming | four render-only farmsteads with crop-bed boxes; no plant state. | `game/Frontier.zig` |
| Saves | JSON, format 25, `min_supported_format` 13, 4 MiB cap; per-player data in `Kit.Doc`, team data in `Progress` or `Document`; `Progress.max_flags` is 96. | `game/Save.zig`, `game/Progress.zig` |

The consequences: buildings cannot be machines (too few slots), plot state cannot live in story flags (too few), terrain edits need a real layer (there is none), and saves need compact encodings.

## 3. Architecture

New code lives in `src/settlement/`:

```text
 Claim      up to 8 claims, radius <= 96 m, a founding rule and a cost
 Plots      a 4 m cell grid per claim: kind, structure id, builder slot
 Structures bulk struct-of-arrays store (about 2,048) + a data table of definitions
 Economy    the hourly deterministic step over the structures: stockpile, power, population
 Fields     crop fields (growth points, water, alive) inside claims
 Water      the irrigation network: wells, tanks, channels, pipes, gates (section 7)
 Mines      deep mine shafts, lifts and generated levels to 4,000 m (section 9)
 Terrain edit layer   sparse per-chunk lattice deltas (section 8)
 Ore        deterministic ore nodes and quarries (section 9)
 Plan mode  the planning UI (section 10)
```

| Concept | Rule |
| --- | --- |
| Shared stockpile | one per world: wood, stone, ore, alloy, food, water, with caps from storage structures; power is a flow from sap, not a stock. **Any player may withdraw (owner decision)**, with no caps (owner decision) and each withdrawal logged against the player so the team can see who took what |
| Contribution | a player moves materials from their `Kit` into the stockpile, and any player may withdraw from it; the structure and a bounded ledger record who built and who moved what |
| Builder | each structure stores the slot (0 to 3) that placed it, for attribution and recognition |
| Personal rewards | boss and mission rewards, gear, upgrades and cosmetics stay in `Kit`; a settlement milestone may grant each player their own reward |
| Settlement level | camp, hamlet, village, town, Arbor city, from population and services; unlocks structure kinds and claim sizes (thresholds are placeholders to tune) |

Structure art comes from the **City studio** of the [asset studio](asset-studio.md); a first set of about a dozen kinds (small and medium house, workshop, farm shed, well, silo, depot, sap hub, watch turret, road and path tiles, bridge deck, platform deck) can use existing mesh generators.

## 4. Claims and plots

- **Founding.** A claim is a circle on the ground or a set of shelves on one Arbor. It must not overlap the fixed district, a cave mouth, a river channel, a shrine or another claim, and it costs materials. Founding **clears scatter** inside it by saved `Modifications` removals, so scatter ids never change.
- **Claim sizes (the owner left this to me).** A claim's radius follows the settlement level: camp 40 m, hamlet 56 m, village 72 m, town 88 m, Arbor city 96 m (the cap). A claim grows to its level's radius by itself, paid in materials; there are at most 8 claims; founding cost scales with area. A claim can be **abandoned** (half the founding materials come back, its structures become ruins that slowly decay, terrain edits stay) but not moved. 96 m keeps one claim within at most nine 128 m chunks, so eight claims touch at most 72 chunks, which is why the terrain edit cap below is 96 chunks.
- **Plots.** A 4 m grid inside the claim records each cell's use (empty, road, path, field, lot, civic) and the structure covering it. A 96 m claim is at most 48 by 48 cells; the grid is stored run-length encoded.
- **Roads and paths.** Drawn as polylines that snap to the grid and respect the grade limit already used for bridges (`District.max_grade`, 6 percent).
- **Placement validation** reuses the `Build.preview` approach (physics overlap, support rays, `Terrain.surface` footprints) and adds: inside a claim you may build in, every footprint cell free, slope within the structure's limit, required neighbours (a farm shed needs a field, a forge needs power), and builder permission.

## 5. Structures and building

- **Bulk store.** Struct-of-arrays: kind id, cell, yaw, builder slot, level, built tick, state. Capacity about 2,048, each a few bytes; kinds are defined in a data table (`StructureDef`: footprint cells, height, cost, build time, production and consumption per hour, housing, power, site type, requirements) so adding a kind is data. Stable string ids for kinds keep saves and the later interchange standard clean ([interchange](interchange.md)).
- **Construction.** A placed structure is a site that completes after its build time using stockpile materials (settlers abstractly do the work); a player can also hand-build (spend on the spot) to match today's tool.
- **Rendering.** Instanced draws per kind with distance level of detail; bounded draw and triangle budgets measured by the nature benchmark.
- **Colliders.** One merged static collider per active chunk, rebuilt when that chunk's structures change (the Arbor collider pattern), not one body per building.
- **Arbor shelves.** The existing `Arbor.platforms` (8 per tree) become plots, and players may build **grafted decks** anchored to wood (`Tree.attachment`); each deck's load counts against the tree's vascular capacity (`Sap.allocate`), so over-building stresses the tree as [world](../world.md) describes.
- **Bridges.** Keep the existing bridge tool for district plazas; claim roads use the same style set.

### Weather damage and repair

Weather can damage structures (owner decision). Two hazards: **storms** (wind, from thunder of at least one half) and **heavy snowfall** (snowfall of at least 0.6, which only happens on the highlands). A hit is not certain (about a third of storms and a quarter of heavy snowfalls land on a given structure) and does between 10 and 39 points before the structure's resilience is applied. Resilience comes from the structure's kind and upgrades: stone and timber builds shrug off more than canvas, a pitched roof sheds snow, a storm roof or shelter helps. Damage is deterministic from the world seed, the structure, the weather window and the hazard, so a reload or an offline replay agrees. A structure at zero health is a ruin: it produces nothing and houses no one until repaired. Settlers repair from the shared stockpile (one wood restores four points), so storms create a steady, readable demand for materials, not a loss of progress.

*Compiled* (deterministic damage with the hit rates tested, resilience, saturation at zero health, ruins that do not operate, and repair that takes only the wood it uses):

```zig
pub const Hazard = enum { storm, heavy_snow };

pub const Building = struct {
    health: u16,
    max_health: u16,
    /// 0 to 100: how much of a weather hit the structure shrugs off (a sturdy build, a storm roof).
    resilience: u8,
};

fn hash64b(x: u64) u64 {
    var z = x +% 0x9e3779b97f4a7c15;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

/// Damage points one weather window does to one structure. Deterministic from the world seed, the
/// structure, the window and the hazard, so a reload or an offline replay agrees. A storm needs
/// thunder of at least one half; heavy snow needs snowfall of at least 0.6 (so it only happens on
/// the highlands). Hits are not certain: a third of storms and a quarter of heavy snowfalls land.
pub fn weatherDamage(seed: u64, structure: u32, window: u64, hazard: Hazard, intensity: f32, resilience: u8) u16 {
    const threshold: f32 = switch (hazard) {
        .storm => 0.5,
        .heavy_snow => 0.6,
    };
    if (intensity < threshold) return 0;
    const chance: f32 = switch (hazard) {
        .storm => 0.35,
        .heavy_snow => 0.25,
    };
    const roll = hash64b(seed ^ hash64b(@as(u64, structure) ^ hash64b(window *% 31 +% @intFromEnum(hazard))));
    const unit = @as(f32, @floatFromInt(roll >> 40)) / @as(f32, @floatFromInt(@as(u64, 1) << 24));
    if (unit >= chance) return 0;
    const base = 10 + @as(f32, @floatFromInt((roll >> 8) % 30)); // 10 to 39 points
    const kept = @as(f32, @floatFromInt(100 - @min(resilience, 100))) / 100;
    return @intFromFloat(@round(base * intensity * kept));
}

pub fn applyDamage(b: *Building, points: u16) void {
    b.health -|= points;
}

/// A ruin produces nothing and houses no one until it is repaired above zero.
pub fn operating(b: Building) bool {
    return b.health > 0;
}

/// Repairs from the shared stockpile: one wood restores four health points, up to the maximum.
/// Returns the points restored; takes only the wood it uses.
pub fn repair(b: *Building, wood: *u32) u16 {
    const missing = b.max_health - b.health;
    const affordable: u32 = wood.* * 4;
    const points: u16 = @intCast(@min(@as(u32, missing), affordable));
    wood.* -= (points + 3) / 4;
    b.health += points;
    return points;
}

test "weather damages structures deterministically, sturdy ones less, and repairs use wood" {
    const seed: u64 = 0x4845415659;
    // Same inputs, same answer.
    try std.testing.expectEqual(weatherDamage(seed, 3, 40, .storm, 1, 0), weatherDamage(seed, 3, 40, .storm, 1, 0));
    // Showers and flurries do nothing.
    for (0..3000) |i| {
        try std.testing.expectEqual(@as(u16, 0), weatherDamage(seed, @intCast(i), 7, .storm, 0.4, 0));
        try std.testing.expectEqual(@as(u16, 0), weatherDamage(seed, @intCast(i), 7, .heavy_snow, 0.5, 0));
    }
    // Over many structures roughly a third are hit by a storm, a quarter by heavy snow.
    var storm_hits: usize = 0;
    var snow_hits: usize = 0;
    var weak_total: u64 = 0;
    var sturdy_total: u64 = 0;
    const n: usize = 20_000;
    for (0..n) |i| {
        const s: u32 = @intCast(i);
        if (weatherDamage(seed, s, 11, .storm, 1, 0) > 0) storm_hits += 1;
        if (weatherDamage(seed, s, 11, .heavy_snow, 1, 0) > 0) snow_hits += 1;
        weak_total += weatherDamage(seed, s, 11, .storm, 1, 0);
        sturdy_total += weatherDamage(seed, s, 11, .storm, 1, 80);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), @as(f32, @floatFromInt(storm_hits)) / n, 0.015);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), @as(f32, @floatFromInt(snow_hits)) / n, 0.015);
    try std.testing.expect(sturdy_total * 3 < weak_total); // an 80-resilience structure takes about a fifth
    try std.testing.expectEqual(@as(u16, 0), weatherDamage(seed, 1, 11, .storm, 1, 100)); // fully resilient
    // Damage saturates at zero health and a ruin does not operate.
    var shed: Building = .{ .health = 30, .max_health = 100, .resilience = 0 };
    applyDamage(&shed, 500);
    try std.testing.expectEqual(@as(u16, 0), shed.health);
    try std.testing.expect(!operating(shed));
    // Repair: four points per wood, only what is needed, only what the stockpile holds.
    var wood: u32 = 10;
    try std.testing.expectEqual(@as(u16, 40), repair(&shed, &wood));
    try std.testing.expectEqual(@as(u32, 0), wood);
    try std.testing.expect(operating(shed) and shed.health == 40);
    wood = 100;
    try std.testing.expectEqual(@as(u16, 60), repair(&shed, &wood));
    try std.testing.expectEqual(@as(u32, 85), wood); // 15 wood for the last 60 points
    try std.testing.expectEqual(@as(u16, 100), shed.health);
    try std.testing.expectEqual(@as(u16, 0), repair(&shed, &wood)); // nothing missing: nothing spent
    try std.testing.expectEqual(@as(u32, 85), wood);
}
```

## 6. Economy and population

Resources: wood (harvested saplings and trees), stone (quarries, terraforming), ore, alloy (a forge turns ore into alloy using power), food (farms), water (wells, rain catch). The existing personal collectibles (lumen shards, rotor cores, Hive alloy, vital cells) stay in `Kit`.

The hourly step, in placement order: sum power supply and demand; each structure that needs inputs it cannot afford does nothing that hour; powered structures scale with the power available; production is capped by storage; settlers eat and drink, a shortage drives people away, and spare housing with food and water brings new ones. Offline time is replayed hour by hour but only up to a cap (48 hours), so loading is bounded.

**Population is a count and also visible people (owner decision).** The count is the simulation (housing, food, water, safety). A bounded sample of settlers appears as people walking the claim, reusing the city-life pedestrians and routes (`city/Life.zig`), at most a small fixed number per view so the existing pedestrian cap and frame budget are respected; the sample is cosmetic and never changes the count. A settler who flees or is lost lowers the count through the economy step, not through the visible person.

*Compiled* (the hourly step with caps, power scaling, affordability, starvation and housing; exact alloy totals are asserted for half power and full power):

```zig
pub const Resource = enum(u3) { wood, stone, ore, alloy, food, water };
pub const resource_count = 6;

/// One kind of structure's effect each settlement hour.
pub const Def = struct {
    housing: u16 = 0,
    /// Positive supplies power, negative demands it.
    power: i16 = 0,
    /// Per hour by resource: positive produces, negative consumes.
    flow: [resource_count]i16 = @splat(0),
};

pub const Settlement = struct {
    stock: [resource_count]u32 = @splat(0),
    cap: [resource_count]u32 = @splat(0),
    population: u16 = 0,
};

/// One settlement hour over every built structure, in placement order. A structure that needs
/// inputs it cannot afford does nothing this hour; production scales with available power;
/// stock never exceeds its cap and never goes below zero. Settlers eat and drink; a shortage
/// shrinks the population and spare housing with food and water grows it.
pub fn step(s: *Settlement, defs: []const Def) void {
    var supply: i64 = 0;
    var demand: i64 = 0;
    var housing: u64 = 0;
    for (defs) |d| {
        if (d.power >= 0) supply += d.power else demand -= d.power;
        housing += d.housing;
    }
    const power_permille: i64 = if (demand == 0) 1000 else @min(1000, @divTrunc(supply * 1000, demand));
    const food = @intFromEnum(Resource.food);
    const water = @intFromEnum(Resource.water);
    for (defs) |d| {
        var affordable = true;
        for (d.flow, 0..) |f, i| {
            if (f < 0 and s.stock[i] < @as(u32, @intCast(-@as(i32, f)))) affordable = false;
        }
        if (!affordable) continue;
        const scale: i64 = if (d.power < 0) power_permille else 1000;
        for (d.flow, 0..) |f, i| {
            if (f < 0) {
                s.stock[i] -= @intCast(-@as(i32, f));
            } else {
                const made: u32 = @intCast(@divTrunc(@as(i64, f) * scale, 1000));
                s.stock[i] = @min(s.cap[i], s.stock[i] + made);
            }
        }
    }
    const need: u32 = (@as(u32, s.population) + 9) / 10;
    if (s.stock[food] >= need and s.stock[water] >= need) {
        s.stock[food] -= need;
        s.stock[water] -= need;
        if (s.population < housing and s.stock[food] >= 1 and s.stock[water] >= 1) s.population += 1;
    } else if (s.population > 0) {
        s.population -= 1; // a shortage drives people away
    }
}

test "the economy step respects caps, power, affordability and population needs" {
    const farm: Def = .{ .flow = .{ 0, 0, 0, 0, 12, -2 } }; // food up, water down
    const well: Def = .{ .flow = .{ 0, 0, 0, 0, 0, 10 } };
    const hut: Def = .{ .housing = 4 };
    const forge: Def = .{ .power = -20, .flow = .{ 0, 0, -2, 3, 0, 0 } }; // ore into alloy, needs power
    const tap: Def = .{ .power = 10 }; // supplies half of what the forge wants
    var s: Settlement = .{ .cap = .{ 100, 100, 100, 100, 30, 100 } };
    s.stock[@intFromEnum(Resource.ore)] = 50;
    s.stock[@intFromEnum(Resource.water)] = 5;
    const defs = [_]Def{ well, farm, hut, tap, forge };
    for (0..40) |_| {
        step(&s, &defs);
        for (s.stock, s.cap) |have, cap| try std.testing.expect(have <= cap);
    }
    try std.testing.expect(s.population >= 1 and s.population <= 4); // never beyond housing
    // Half the needed power scales the forge's 3 alloy to 1 an hour (3 * 500 / 1000, rounded down)
    // and it runs while its 50 ore lasts: 25 hours at 2 ore an hour, so exactly 25 alloy.
    try std.testing.expectEqual(@as(u32, 25), s.stock[@intFromEnum(Resource.alloy)]);
    // With enough power it makes the full 3 an hour: 75 alloy from the same ore.
    var powered: Settlement = .{ .cap = .{ 100, 100, 100, 100, 30, 100 } };
    powered.stock[@intFromEnum(Resource.ore)] = 50;
    const second_tap: Def = .{ .power = 10 };
    for (0..40) |_| step(&powered, &[_]Def{ tap, second_tap, forge });
    try std.testing.expectEqual(@as(u32, 75), powered.stock[@intFromEnum(Resource.alloy)]);

    // No water at all: people leave and nothing underflows.
    var dry: Settlement = .{ .cap = @splat(100), .population = 3 };
    dry.stock[@intFromEnum(Resource.food)] = 10;
    step(&dry, &[_]Def{hut});
    step(&dry, &[_]Def{hut});
    try std.testing.expectEqual(@as(u16, 1), dry.population);
    // A structure that cannot afford its inputs does nothing and does not underflow stock.
    var broke: Settlement = .{ .cap = @splat(100) };
    step(&broke, &[_]Def{ .{ .flow = .{ 0, -5, 0, 7, 0, 0 } }, hut });
    try std.testing.expectEqual(@as(u32, 0), broke.stock[@intFromEnum(Resource.alloy)]);
    try std.testing.expectEqual(@as(u32, 0), broke.stock[@intFromEnum(Resource.stone)]);
}
```

## 7. Farming

- **Crops** are a data table: growth points to seedling, growing and ripe; the seasons they grow in; the temperature below which frost kills them; and how long a watering lasts.
- **Fields** record growth points, water left and whether the crop is alive. Growth points accrue **in the hourly step** from the calendar and climate ([weather and seasons](weather-seasons.md)): none when cold or dry or out of season, full between 15 and 25 degrees, tapering to none at 38. Rain waters fields, and a full irrigation network (below) waters them between rains; a sap-powered **greenhouse** ignores season and frost.
- **Harvest** goes to the shared stockpile, with a personal first-harvest share (a seed or a small reward) to the harvester's `Kit`.
- **Losses (owner decision).** A killing frost destroys a crop (the existing rule). **A storm can flatten an unsheltered field:** only real storms (thunder at least one half) can, the chance rises with the crop's stage (about 8 percent for a seed up to about 26 percent when ripe), and it is decided deterministically from the world seed, the field and the storm's window, so a reload or an offline replay agrees. A greenhouse protects its fields. **A Hive raid that reaches a field destroys its crop** (the raid system and the field table must agree on which fields it reached). A destroyed field stays and can be replanted; losses are meant to sting, not to wipe a settlement, so the rates and any protective structures (a storm cellar, a watch turret) are tuning items.
- **Rendering** uses the existing flora meshes by stage, with a bounded instance budget near the camera.
- **Starter crops (placeholders):** a staple grain (spring to autumn), a cool-season root, a summer fruiting plant, a frost-hardy berry, and a glowing gourd for night colour.

*Compiled* (growth only when watered, warm and in season; greenhouse and frost; storms that flatten unsheltered crops deterministically, with ripe crops hit most; save-and-resume equals playing straight through; offline catch-up capped at 48 hours):

```zig
pub const Season = enum(u2) { spring, summer, autumn, winter };

/// What the hourly step needs from the climate. The settlement module takes plain values, so the
/// calendar and weather stay in their own module.
pub const Conditions = struct { celsius: f32, raining: bool, season: Season, irrigated: bool = false };

pub const Crop = struct {
    /// Growth points needed to reach seedling, growing and ripe.
    stage_points: [3]u16,
    /// Bit `n` is set when the crop grows in season `n`.
    seasons: u4,
    /// Frost below this temperature kills the crop unless it is sheltered.
    frost_below: f32,
    /// How many hours one watering (or one rain) lasts.
    water_hours: u8 = 24,
};

pub const Field = struct {
    points: u16 = 0,
    water_left: u8 = 0,
    alive: bool = true,

    pub fn stage(self: Field, crop: Crop) u2 {
        if (!self.alive) return 0;
        var s: u2 = 0;
        for (crop.stage_points) |needed| {
            if (self.points >= needed) s += 1;
        }
        return s; // 0 seed, 1 seedling, 2 growing, 3 ripe
    }
};

/// Points per hour from temperature: none when cold, full between 15 and 25 degrees, tapering to
/// none at 38.
pub fn growthRate(celsius: f32) u8 {
    if (celsius <= 5 or celsius >= 38) return 0;
    if (celsius < 15) return @intFromFloat(@round((celsius - 5) / 10 * 10));
    if (celsius <= 25) return 10;
    return @intFromFloat(@round((38 - celsius) / 13 * 10));
}

/// One settlement hour. `sheltered` is a greenhouse (or similar): it ignores season and frost.
pub fn growHour(field: *Field, crop: Crop, now: Conditions, sheltered: bool) void {
    if (!field.alive) return;
    if (!sheltered and now.celsius < crop.frost_below) {
        field.alive = false; // a killing frost
        return;
    }
    if ((now.raining and !sheltered) or now.irrigated) field.water_left = crop.water_hours;
    if (field.water_left == 0) return; // dry: no growth, and it keeps what it has
    field.water_left -= 1;
    const in_season = sheltered or (crop.seasons >> @intFromEnum(now.season)) & 1 == 1;
    if (!in_season) return;
    const rate: u16 = growthRate(now.celsius);
    field.points = @min(std.math.maxInt(u16), field.points + rate);
}

test "an irrigated field grows through a dry spell that stalls an unwatered one" {
    const wheat: Crop = .{ .stage_points = .{ 20, 80, 160 }, .seasons = 0b0111, .frost_below = -1 };
    var dry: Field = .{};
    var watered: Field = .{};
    for (0..48) |_| {
        growHour(&dry, wheat, .{ .celsius = 22, .raining = false, .season = .summer }, false);
        growHour(&watered, wheat, .{ .celsius = 22, .raining = false, .season = .summer, .irrigated = true }, false);
    }
    try std.testing.expectEqual(@as(u16, 0), dry.points);
    try std.testing.expectEqual(@as(u16, 480), watered.points);
    // Irrigation still works under cover (a greenhouse is not rain-fed).
    var covered: Field = .{};
    for (0..5) |_| growHour(&covered, wheat, .{ .celsius = 22, .raining = false, .season = .winter, .irrigated = true }, true);
    try std.testing.expectEqual(@as(u16, 50), covered.points);
}

fn hash64(x: u64) u64 {
    var z = x +% 0x9e3779b97f4a7c15;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

/// Whether a storm flattens this field. Deterministic from the world seed, the field, and the
/// storm's window, so a reload or an offline replay agrees. Only real storms (thunder at least
/// one half) can do it; ripe crops are the most exposed; a greenhouse protects a field.
pub fn stormHits(seed: u64, field_index: u32, window: u64, thunder: f32, stage: u2, sheltered: bool) bool {
    if (sheltered or thunder < 0.5) return false;
    const chance = (0.08 + 0.06 * @as(f32, @floatFromInt(stage))) * thunder;
    const roll = hash64(seed ^ hash64(@as(u64, field_index) ^ hash64(window)));
    return @as(f32, @floatFromInt(roll >> 40)) / @as(f32, @floatFromInt(@as(u64, 1) << 24)) < chance;
}

/// A hit destroys the crop outright; the field itself remains and can be replanted.
pub fn applyStorm(field: *Field, hit: bool) void {
    if (hit) field.alive = false;
}

test "storms destroy unsheltered crops deterministically, ripe ones most often" {
    const seed: u64 = 0x4845415659;
    // Same inputs, same answer.
    try std.testing.expectEqual(stormHits(seed, 7, 12, 1, 3, false), stormHits(seed, 7, 12, 1, 3, false));
    // A greenhouse and a mere shower are always safe.
    for (0..2000) |i| {
        try std.testing.expect(!stormHits(seed, @intCast(i), 5, 1, 3, true));
        try std.testing.expect(!stormHits(seed, @intCast(i), 5, 0.4, 3, false));
    }
    // Across many fields the hit rate follows the stage: about 8% seedlings-of-nothing up to 26% when ripe.
    var hits: [4]usize = @splat(0);
    const fields: usize = 20_000;
    for (0..4) |stage| {
        for (0..fields) |i| {
            if (stormHits(seed, @intCast(i), 99, 1, @intCast(stage), false)) hits[stage] += 1;
        }
    }
    for (hits, 0..) |count, stage| {
        const rate = @as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(fields));
        try std.testing.expectApproxEqAbs(0.08 + 0.06 * @as(f32, @floatFromInt(stage)), rate, 0.015);
    }
    try std.testing.expect(hits[3] > hits[0]);
    // A hit kills the crop but keeps the field for replanting.
    var field: Field = .{ .points = 200, .water_left = 5 };
    applyStorm(&field, true);
    try std.testing.expect(!field.alive and field.stage(.{ .stage_points = .{ 20, 80, 160 }, .seasons = 0b1111, .frost_below = -5 }) == 0);
    var spared: Field = .{ .points = 200 };
    applyStorm(&spared, false);
    try std.testing.expect(spared.alive);
}

test "crops grow only when watered, warm and in season, and a frost kills them" {
    const wheat: Crop = .{ .stage_points = .{ 20, 80, 160 }, .seasons = 0b0111, .frost_below = -1 }; // not winter
    var field: Field = .{};
    const warm: Conditions = .{ .celsius = 20, .raining = false, .season = .summer };
    for (0..30) |_| growHour(&field, wheat, warm, false);
    try std.testing.expectEqual(@as(u16, 0), field.points); // never watered

    growHour(&field, wheat, .{ .celsius = 20, .raining = true, .season = .summer }, false); // rain waters it
    try std.testing.expectEqual(@as(u8, 23), field.water_left);
    for (0..23) |_| growHour(&field, wheat, warm, false);
    try std.testing.expectEqual(@as(u16, 240), field.points); // 24 hours at full rate
    try std.testing.expectEqual(@as(u2, 3), field.stage(wheat));

    var winter: Field = .{ .water_left = 24 };
    for (0..24) |_| growHour(&winter, wheat, .{ .celsius = 20, .raining = false, .season = .winter }, false);
    try std.testing.expectEqual(@as(u16, 0), winter.points); // out of season: stalls
    var greenhouse: Field = .{ .water_left = 24 };
    for (0..24) |_| growHour(&greenhouse, wheat, .{ .celsius = 20, .raining = false, .season = .winter }, true);
    try std.testing.expectEqual(@as(u16, 240), greenhouse.points); // sheltered: grows anyway

    var frosted: Field = .{ .points = 100, .water_left = 10 };
    growHour(&frosted, wheat, .{ .celsius = -3, .raining = false, .season = .autumn }, false);
    try std.testing.expect(!frosted.alive and frosted.stage(wheat) == 0);
    var covered: Field = .{ .points = 100, .water_left = 10 };
    growHour(&covered, wheat, .{ .celsius = -3, .raining = false, .season = .autumn }, true);
    try std.testing.expect(covered.alive);

    try std.testing.expectEqual(@as(u8, 0), growthRate(4));
    try std.testing.expectEqual(@as(u8, 10), growthRate(20));
    try std.testing.expect(growthRate(10) > 0 and growthRate(10) < 10);
    try std.testing.expectEqual(@as(u8, 0), growthRate(40));
}

/// Offline time is replayed hour by hour but never more than `max_catch_up` hours, so loading a
/// save after a long absence costs bounded work and cannot grow a field without limit.
pub const max_catch_up: u32 = 48;

pub fn catchUp(field: *Field, crop: Crop, absent_hours: u32, conditionsAt: *const fn (hour: u32) Conditions, first_hour: u32) void {
    const hours = @min(absent_hours, max_catch_up);
    // The last `hours` of the absence are the ones that count.
    var h: u32 = first_hour + (absent_hours - hours);
    while (h < first_hour + absent_hours) : (h += 1) growHour(field, crop, conditionsAt(h), false);
}

fn sampleConditions(hour: u32) Conditions {
    return .{ .celsius = 8 + @as(f32, @floatFromInt(hour % 24)), .raining = hour % 17 == 0, .season = .spring };
}

test "saving and resuming gives the same field as playing straight through, and catch-up is bounded" {
    const crop: Crop = .{ .stage_points = .{ 20, 80, 160 }, .seasons = 0b1111, .frost_below = -10 };
    var straight: Field = .{};
    var h: u32 = 0;
    while (h < 200) : (h += 1) growHour(&straight, crop, sampleConditions(h), false);

    // Play 100 hours, save the field as raw bytes, restore it, and play the other 100.
    var first: Field = .{};
    h = 0;
    while (h < 100) : (h += 1) growHour(&first, crop, sampleConditions(h), false);
    var saved: [@sizeOf(Field)]u8 = undefined;
    @memcpy(&saved, std.mem.asBytes(&first));
    var resumed: Field = std.mem.bytesToValue(Field, &saved);
    while (h < 200) : (h += 1) growHour(&resumed, crop, sampleConditions(h), false);
    try std.testing.expectEqual(straight, resumed);
    try std.testing.expect(straight.points > 0);

    // After a very long absence only the last 48 hours are replayed.
    var long_away: Field = .{};
    catchUp(&long_away, crop, 5_000, sampleConditions, 0);
    var last_two_days: Field = .{};
    h = 5_000 - max_catch_up;
    while (h < 5_000) : (h += 1) growHour(&last_two_days, crop, sampleConditions(h), false);
    try std.testing.expectEqual(last_two_days, long_away);
    var short_away: Field = .{};
    catchUp(&short_away, crop, 10, sampleConditions, 0); // under the cap: every hour replays
    var ten: Field = .{};
    h = 0;
    while (h < 10) : (h += 1) growHour(&ten, crop, sampleConditions(h), false);
    try std.testing.expectEqual(ten, short_away);
}
```

### Irrigation

Owner decision: **full irrigation systems**. Water is a network the player plans and builds.

| Part | Role |
| --- | --- |
| Well | taps groundwater at a yield set by the local moisture (wetland yields most, arid ground least); costs power on dry ground |
| Rain catcher and cistern | collect rain into a tank |
| Tank, reservoir, pond | store water; a pond is a basin dug with the terraform tools and given a flat water surface, drawn with the existing water shader (a bounded set of pools per claim) |
| Channel | open, gravity-fed, follows the terrain and needs a fall of at least 5 cm between its ends; the slope-to-grade tool carves it; loses water to the air in the heat; stops while iced |
| Aqueduct | an elevated channel on piers across a gap (built like a bridge deck), still gravity-fed |
| Pipe and pump | pressurised and buried: moves water uphill, needs power from sap, never freezes, loses nothing to the air |
| Gate and valve | open or close a branch, so a player can ration water |
| Sprinkler and drip line | spread water over the fields in range; drip lines waste the least |
| Drain | returns excess water to a reservoir |

The water network is a small graph (at most 512 nodes and 1,024 links per settlement). An hourly step moves water along links in order, subject to capacity, fall or power, and room at the far end; fills wells; adds rain; evaporates open water when it is warm; and lets each field that has water use one unit and report itself wet to its crops. **Nothing is created or lost except by a well, rain, evaporation or a field**, and the step returns those totals, so a test can check conservation exactly. A field that is irrigated grows through a dry summer; one that is not, stalls. The settlement's own drinking water is the same network feeding a municipal tank, so a drought threatens both crops and people.

*Compiled* (gravity only downhill, powered pipes uphill, link capacity and tank limits, evaporation and rain, a sealed well, an unconnected field staying dry, and exact conservation of water):

```zig
pub const WaterKind = enum { well, tank, field };

/// One place water is held. Wells produce; tanks and reservoirs store; fields use.
pub const WaterNode = struct {
    kind: WaterKind,
    /// Surface height in metres, from the terrain (and the edit layer) at the structure.
    elevation: f32,
    stock: u32 = 0,
    cap: u32,
    /// Units a well adds each hour.
    yield_per_hour: u16 = 0,
};

pub const Conduit = enum {
    /// Open channel or aqueduct: gravity only, needs a fall, loses water to the air.
    channel,
    /// Pressurised pipe: moves water uphill, needs power.
    pipe,
};

pub const Link = struct { from: u8, to: u8, kind: Conduit, capacity: u16 };

/// A channel needs this much drop (metres) between its ends to flow.
pub const min_fall_m: f32 = 0.05;

pub const WaterTotals = struct { produced: u32 = 0, rained: u32 = 0, evaporated: u32 = 0, used: u32 = 0 };

fn room(n: WaterNode) u32 {
    return n.cap - n.stock;
}

/// One settlement hour of water: wells fill, links move water in order, open tanks and channels
/// lose a little to the air when it is warm, rain tops up whatever can hold it, and every field
/// that has water uses one unit and reports itself wet for crops. Nothing is created or lost
/// except by a well, rain, evaporation or a field, and every total is returned for the books.
pub fn waterHour(nodes: []WaterNode, links: []const Link, powered: bool, celsius: f32, rain_units: u16, wet: []bool, totals: *WaterTotals) void {
    for (nodes) |*n| {
        if (n.kind != .well) continue;
        const made: u32 = @min(room(n.*), n.yield_per_hour);
        n.stock += made;
        totals.produced += made;
    }
    for (links) |l| {
        const from = &nodes[l.from];
        const to = &nodes[l.to];
        const allowed = switch (l.kind) {
            .channel => from.elevation - to.elevation >= min_fall_m,
            .pipe => powered,
        };
        if (!allowed) continue;
        const moved: u32 = @min(@min(from.stock, room(to.*)), l.capacity);
        from.stock -= moved;
        to.stock += moved;
    }
    if (rain_units > 0) {
        for (nodes) |*n| {
            if (n.kind == .well) continue; // a sealed well does not catch rain
            const caught: u32 = @min(room(n.*), rain_units);
            n.stock += caught;
            totals.rained += caught;
        }
    }
    if (celsius > 20) {
        for (nodes) |*n| {
            if (n.kind != .tank) continue;
            const lost: u32 = @min(n.stock, @as(u32, @intFromFloat((celsius - 20) / 5)));
            n.stock -= lost;
            totals.evaporated += lost;
        }
    }
    for (nodes, 0..) |*n, i| {
        if (n.kind != .field) continue;
        wet[i] = n.stock > 0;
        if (n.stock > 0) {
            n.stock -= 1;
            totals.used += 1;
        }
    }
}

fn held(nodes: []const WaterNode) u32 {
    var total: u32 = 0;
    for (nodes) |n| total += n.stock;
    return total;
}

test "water flows downhill by gravity, uphill only by powered pipe, and is conserved" {
    // A well on a hill feeds a tank by pipe, the tank feeds two fields down a channel; a third field
    // sits uphill of the tank and is only reachable by a pipe.
    var nodes = [_]WaterNode{
        .{ .kind = .well, .elevation = 12, .cap = 50, .yield_per_hour = 8 }, // 0
        .{ .kind = .tank, .elevation = 10, .cap = 100 }, // 1
        .{ .kind = .field, .elevation = 6, .cap = 20 }, // 2 downhill
        .{ .kind = .field, .elevation = 5, .cap = 20 }, // 3 downhill
        .{ .kind = .field, .elevation = 15, .cap = 20 }, // 4 uphill of the tank
    };
    const links = [_]Link{
        .{ .from = 0, .to = 1, .kind = .channel, .capacity = 20 }, // the well is higher: gravity works
        .{ .from = 1, .to = 2, .kind = .channel, .capacity = 4 },
        .{ .from = 1, .to = 3, .kind = .channel, .capacity = 4 },
        .{ .from = 1, .to = 4, .kind = .channel, .capacity = 10 }, // uphill by channel: never flows
    };
    var wet: [5]bool = @splat(false);
    var totals: WaterTotals = .{};
    for (0..30) |_| waterHour(&nodes, &links, false, 15, 0, &wet, &totals);
    try std.testing.expect(wet[2] and wet[3]); // both downhill fields stay watered
    try std.testing.expect(!wet[4] and nodes[4].stock == 0); // the uphill field gets nothing by gravity
    // Conservation: what is held now equals what came in minus what was used or lost.
    try std.testing.expectEqual(held(&nodes), totals.produced + totals.rained - totals.evaporated - totals.used);

    // Add a powered pipe to the uphill field: it flows only while there is power.
    const with_pipe = links ++ [_]Link{.{ .from = 1, .to = 4, .kind = .pipe, .capacity = 10 }};
    var unpowered = nodes;
    var no_power_totals: WaterTotals = .{};
    for (0..10) |_| waterHour(&unpowered, &with_pipe, false, 15, 0, &wet, &no_power_totals);
    try std.testing.expectEqual(@as(u32, 0), unpowered[4].stock);
    var powered = nodes;
    var power_totals: WaterTotals = .{};
    for (0..10) |_| waterHour(&powered, &with_pipe, true, 15, 0, &wet, &power_totals);
    try std.testing.expect(wet[4]); // powered: even the uphill field is watered
    try std.testing.expectEqual(held(&powered), held(&nodes) + power_totals.produced + power_totals.rained - power_totals.evaporated - power_totals.used);
}

test "capacity limits, evaporation, rain and an unconnected field behave" {
    var nodes = [_]WaterNode{
        .{ .kind = .well, .elevation = 10, .cap = 100, .yield_per_hour = 50 },
        .{ .kind = .tank, .elevation = 8, .cap = 30 },
        .{ .kind = .field, .elevation = 2, .cap = 10 },
        .{ .kind = .field, .elevation = 1, .cap = 10 }, // never linked to anything
    };
    const links = [_]Link{
        .{ .from = 0, .to = 1, .kind = .channel, .capacity = 5 },
        .{ .from = 1, .to = 2, .kind = .channel, .capacity = 3 },
    };
    var wet: [4]bool = @splat(false);
    var totals: WaterTotals = .{};
    waterHour(&nodes, &links, false, 15, 0, &wet, &totals);
    try std.testing.expectEqual(@as(u32, 45), nodes[0].stock); // 50 made, 5 moved on (capacity of the link)
    try std.testing.expectEqual(@as(u32, 2), nodes[1].stock); // 5 in, 3 out
    try std.testing.expect(!wet[3] and nodes[3].stock == 0); // an unconnected field stays dry
    // A tank never holds more than its capacity.
    for (0..60) |_| waterHour(&nodes, &links, false, 15, 0, &wet, &totals);
    try std.testing.expect(nodes[1].stock <= nodes[1].cap and nodes[0].stock <= nodes[0].cap);
    // Heat costs the open tank water; rain refills what can hold it, including the unlinked field.
    var hot = nodes;
    var hot_totals: WaterTotals = .{};
    waterHour(&hot, &links, false, 40, 0, &wet, &hot_totals);
    try std.testing.expectEqual(@as(u32, 4), hot_totals.evaporated); // (40 - 20) / 5 = 4 from the one tank
    var rainy = nodes;
    var rain_totals: WaterTotals = .{};
    waterHour(&rainy, &links, false, 15, 6, &wet, &rain_totals);
    try std.testing.expect(wet[3]); // the unlinked field is rain-fed
    try std.testing.expect(rain_totals.rained > 0);
    var no_rain = nodes;
    var no_rain_totals: WaterTotals = .{};
    waterHour(&no_rain, &links, false, 15, 0, &wet, &no_rain_totals);
    try std.testing.expectEqual(no_rain[0].stock, rainy[0].stock); // a sealed well takes no rain
}
```

## 8. Terraforming

**Scope (owner decision):** bounded edits inside claims; the rest of the world stays procedural.

**The hard part.** Terrain height is a pure function used in many places, and chunk meshes, collision, placement and biome must agree exactly. Scatter's `local_id` is generation order, so changing which objects pass a filter would corrupt saved removals. The plan therefore changes *where height comes from*, not *what scatter decides*.

**Step T0, a refactor with no behaviour change.** Route every height query through one function (`Terrain.height`, the base height plus an overlay delta that is zero for now) and add a test that no code outside `Terrain.zig` and the chunk base calls `Noise.height` directly. Rivers, caves and mountains keep using the **base** height.

**Step T1, the overlay.**
- A sparse map from chunk key to a 65 by 65 grid of signed bytes in quarter-metre steps (a range of about 32 m up or down), on the same 2 m lattice the chunk mesh uses, so the mesh and `Terrain.surface` interpolate the same values and agree exactly. Normals use the same function.
- A lattice point on a chunk edge belongs to two (or four) chunks and must hold the same value in all; writes go to every owner and loading verifies it.
- A stamp (raise, lower, level, smooth) settles its allocations and the cap **before** it writes, so a refused or failed stamp changes nothing.
- Placement of scatter is decided from base height and slope (ids stay stable); only the object's `y` follows the overlay, and objects inside a claim were cleared at founding.
- The streaming worker reads an **immutable snapshot with a revision**, swapped atomically; a new `Streamer.invalidate(key)` regenerates a chunk when its revision changes.
- **No-edit zones:** within a margin of rivers, cave mouths and systems, the fixed district and its clearance envelope, shrines, and the hub height bound (`Terrain.hub_height_upper_bound`); and a depth and height limit around the base.
- **Tools:** raise, lower, level to a height, smooth, and slope-to-grade for roads; undo uses the shared studio `History`; lowering yields stone only through a quarry structure at a bounded rate, so digging is not free.
- **Save:** an embedded, run-length encoded and base64 section capped near 1 MiB (at most 96 chunks), in the save document, so one atomic write holds the world; format version 1 for the section itself.

*Compiled* (stamps across a chunk seam, matching shared edges, deterministic bytes, a refused stamp over the cap leaves no change, hostile files rejected, seams verified on load, allocation failures freed):

```zig
pub const lattice = 65; // vertices per chunk side: 64 cells of 2 m
pub const points_per_chunk = lattice * lattice;
pub const unit_m: f32 = 0.25;
pub const Key = [2]i32;
pub const Delta = [points_per_chunk]i8;

/// Chunk `c` owns lattice points `c*64 - 32 ..= c*64 + 32`, so a point on a shared edge belongs to
/// two chunks and must hold the same value in both or a seam opens.
fn owners(g: i32) [2]?i32 {
    const first = @divFloor(g + 32, 64);
    return .{ first, if (@mod(g + 32, 64) == 0) first - 1 else null };
}
fn localIndex(g: i32, chunk: i32) usize {
    return @intCast(g - (chunk * 64 - 32));
}

fn smooth(t: f32) f32 {
    const c = std.math.clamp(t, 0, 1);
    return c * c * (3 - 2 * c);
}

pub const Overlay = struct {
    chunks: std.AutoHashMapUnmanaged(Key, *Delta) = .empty,
    max_chunks: usize,

    pub const Error = error{ CapExceeded, InvalidOverlay, OutOfMemory };

    pub fn deinit(self: *Overlay, allocator: std.mem.Allocator) void {
        var it = self.chunks.valueIterator();
        while (it.next()) |p| allocator.destroy(p.*);
        self.chunks.deinit(allocator);
    }

    pub fn get(self: *const Overlay, gx: i32, gz: i32) i8 {
        const ox = owners(gx);
        const oz = owners(gz);
        const chunk = self.chunks.get(.{ ox[0].?, oz[0].? }) orelse return 0;
        return chunk[localIndex(gz, oz[0].?) * lattice + localIndex(gx, ox[0].?)];
    }

    fn ensure(self: *Overlay, allocator: std.mem.Allocator, key: Key) !*Delta {
        const entry = try self.chunks.getOrPut(allocator, key);
        if (!entry.found_existing) {
            errdefer _ = self.chunks.remove(key);
            const fresh = try allocator.create(Delta);
            @memset(fresh, 0);
            entry.value_ptr.* = fresh;
        }
        return entry.value_ptr.*;
    }

    /// Writes a point into every chunk that owns it, so shared edges always agree.
    fn write(self: *Overlay, gx: i32, gz: i32, value: i8) void {
        for (owners(gx)) |maybe_x| {
            const cx = maybe_x orelse continue;
            for (owners(gz)) |maybe_z| {
                const cz = maybe_z orelse continue;
                const chunk = self.chunks.get(.{ cx, cz }).?;
                chunk[localIndex(gz, cz) * lattice + localIndex(gx, cx)] = value;
            }
        }
    }

    /// Raises (positive `meters`) or lowers the ground around a centre with a smooth falloff. The
    /// cap and the allocations are settled before the first write, so a refused or failed stamp
    /// changes no height.
    pub fn stamp(self: *Overlay, allocator: std.mem.Allocator, center_x: f32, center_z: f32, radius: f32, meters: f32) Error!void {
        const g_min_x: i32 = @intFromFloat(@floor((center_x - radius) / 2));
        const g_max_x: i32 = @intFromFloat(@ceil((center_x + radius) / 2));
        const g_min_z: i32 = @intFromFloat(@floor((center_z - radius) / 2));
        const g_max_z: i32 = @intFromFloat(@ceil((center_z + radius) / 2));
        // Pass 1: which chunks does this stamp touch, and do they fit under the cap?
        var gz = g_min_z;
        var fresh_keys: [16]Key = undefined;
        var fresh: usize = 0;
        while (gz <= g_max_z) : (gz += 1) {
            var gx = g_min_x;
            while (gx <= g_max_x) : (gx += 1) {
                if (weight(gx, gz, center_x, center_z, radius) == 0) continue;
                for (owners(gx)) |mx| for (owners(gz)) |mz| {
                    if (mx == null or mz == null) continue;
                    const key: Key = .{ mx.?, mz.? };
                    if (self.chunks.contains(key)) continue;
                    var seen = false;
                    for (fresh_keys[0..fresh]) |k| {
                        if (k[0] == key[0] and k[1] == key[1]) seen = true;
                    }
                    if (!seen) {
                        if (fresh == fresh_keys.len) return error.CapExceeded;
                        fresh_keys[fresh] = key;
                        fresh += 1;
                    }
                };
            }
        }
        if (self.chunks.count() + fresh > self.max_chunks) return error.CapExceeded;
        for (fresh_keys[0..fresh]) |key| _ = try self.ensure(allocator, key);
        // Pass 2: write. Nothing below can fail.
        gz = g_min_z;
        while (gz <= g_max_z) : (gz += 1) {
            var gx = g_min_x;
            while (gx <= g_max_x) : (gx += 1) {
                const w = weight(gx, gz, center_x, center_z, radius);
                if (w == 0) continue;
                const step_units = @round(meters / unit_m * w);
                const next = std.math.clamp(@as(f32, @floatFromInt(self.get(gx, gz))) + step_units, -127, 127);
                self.write(gx, gz, @intFromFloat(next));
            }
        }
    }

    fn weight(gx: i32, gz: i32, cx: f32, cz: f32, radius: f32) f32 {
        const dx = @as(f32, @floatFromInt(gx)) * 2 - cx;
        const dz = @as(f32, @floatFromInt(gz)) * 2 - cz;
        const d = @sqrt(dx * dx + dz * dz);
        return if (d >= radius) 0 else smooth(1 - d / radius);
    }
};

/// Run-length encoding: pairs of (run length 1..255, value). Skips nothing and trusts nothing on read.
fn rleEncode(list: *std.ArrayList(u8), allocator: std.mem.Allocator, cells: []const i8) !void {
    var i: usize = 0;
    while (i < cells.len) {
        var run: usize = 1;
        while (i + run < cells.len and cells[i + run] == cells[i] and run < 255) run += 1;
        try list.append(allocator, @intCast(run));
        try list.append(allocator, @bitCast(cells[i]));
        i += run;
    }
}

/// Serialises every non-empty chunk. Format 1: version, chunk count (u16), then per chunk its key
/// (two i32) and its run-length data (ending exactly after 4,225 values).
pub fn encode(allocator: std.mem.Allocator, overlay: *const Overlay) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var count: u16 = 0;
    var it = overlay.chunks.iterator();
    while (it.next()) |e| {
        if (!std.mem.allEqual(i8, e.value_ptr.*, 0)) count += 1;
    }
    try out.append(allocator, 1);
    try out.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, count)));
    // Sorted keys keep the bytes identical for identical edits, whatever the hash order.
    var keys: std.ArrayList(Key) = .empty;
    defer keys.deinit(allocator);
    it = overlay.chunks.iterator();
    while (it.next()) |e| {
        if (!std.mem.allEqual(i8, e.value_ptr.*, 0)) try keys.append(allocator, e.key_ptr.*);
    }
    std.mem.sort(Key, keys.items, {}, struct {
        fn less(_: void, a: Key, b: Key) bool {
            return if (a[0] != b[0]) a[0] < b[0] else a[1] < b[1];
        }
    }.less);
    for (keys.items) |key| {
        for (key) |v| try out.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToLittle(i32, v)));
        try rleEncode(&out, allocator, overlay.chunks.get(key).?);
    }
    return out.toOwnedSlice(allocator);
}

/// Validates the whole file before returning an overlay: version, counts, exact run lengths, no
/// duplicate keys, no trailing bytes, and agreement on every shared chunk edge.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, max_chunks: usize) Overlay.Error!Overlay {
    if (bytes.len < 3 or bytes[0] != 1) return error.InvalidOverlay;
    const count = std.mem.readInt(u16, bytes[1..3], .little);
    if (count > max_chunks) return error.InvalidOverlay;
    var overlay: Overlay = .{ .max_chunks = max_chunks };
    errdefer overlay.deinit(allocator);
    var at: usize = 3;
    for (0..count) |_| {
        if (at + 8 > bytes.len) return error.InvalidOverlay;
        const key: Key = .{ std.mem.readInt(i32, bytes[at..][0..4], .little), std.mem.readInt(i32, bytes[at + 4 ..][0..4], .little) };
        at += 8;
        if (overlay.chunks.contains(key)) return error.InvalidOverlay;
        const chunk = try overlay.ensure(allocator, key);
        var filled: usize = 0;
        while (filled < points_per_chunk) {
            if (at + 2 > bytes.len) return error.InvalidOverlay;
            const run: usize = bytes[at];
            const value: i8 = @bitCast(bytes[at + 1]);
            at += 2;
            if (run == 0 or filled + run > points_per_chunk) return error.InvalidOverlay;
            @memset(chunk[filled .. filled + run], value);
            filled += run;
        }
    }
    if (at != bytes.len) return error.InvalidOverlay;
    // Every lattice point must read the same from every chunk that owns it.
    var it = overlay.chunks.iterator();
    while (it.next()) |e| {
        const key = e.key_ptr.*;
        for (0..lattice) |lz| for (0..lattice) |lx| {
            const gx: i32 = key[0] * 64 - 32 + @as(i32, @intCast(lx));
            const gz: i32 = key[1] * 64 - 32 + @as(i32, @intCast(lz));
            if (overlay.get(gx, gz) != e.value_ptr.*[lz * lattice + lx]) return error.InvalidOverlay;
        };
    }
    return overlay;
}

test "a stamp raises the ground smoothly, writes shared edges into both chunks, and round-trips" {
    const a = std.testing.allocator;
    var overlay: Overlay = .{ .max_chunks = 8 };
    defer overlay.deinit(a);
    // Centred on the seam between chunk 0 and chunk 1 (x = 64 m, lattice point 32).
    try overlay.stamp(a, 64, 0, 12, 2.0);
    try std.testing.expectEqual(@as(i8, 8), overlay.get(32, 0)); // 2 m is eight quarter-metre steps
    try std.testing.expect(overlay.get(35, 0) < overlay.get(32, 0) and overlay.get(35, 0) > 0);
    try std.testing.expectEqual(@as(i8, 0), overlay.get(60, 0)); // far outside the radius
    // The shared edge column holds identical values from either chunk.
    const left = overlay.chunks.get(.{ 0, 0 }).?;
    const right = overlay.chunks.get(.{ 1, 0 }).?;
    for (0..lattice) |lz| try std.testing.expectEqual(left[lz * lattice + 64], right[lz * lattice + 0]);

    const bytes = try encode(a, &overlay);
    defer a.free(bytes);
    try std.testing.expect(bytes.len < 2_500); // a radius-12 stamp is a few runs, not 4,225 bytes a chunk
    var back = try decode(a, bytes, 8);
    defer back.deinit(a);
    var gz: i32 = -10;
    while (gz <= 10) : (gz += 1) {
        var gx: i32 = 20;
        while (gx <= 44) : (gx += 1) try std.testing.expectEqual(overlay.get(gx, gz), back.get(gx, gz));
    }
    const again = try encode(a, &back);
    defer a.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again); // deterministic bytes
}

test "a stamp over the cap or a hostile file is refused without changing anything" {
    const a = std.testing.allocator;
    var overlay: Overlay = .{ .max_chunks = 1 };
    defer overlay.deinit(a);
    // Straddling a corner needs four chunks; the cap of one refuses it and nothing is written.
    try std.testing.expectError(error.CapExceeded, overlay.stamp(a, 64, 64, 12, 3.0));
    try std.testing.expectEqual(@as(usize, 0), overlay.chunks.count());
    try std.testing.expectEqual(@as(i8, 0), overlay.get(32, 32));

    var ok: Overlay = .{ .max_chunks = 4 };
    defer ok.deinit(a);
    try ok.stamp(a, 64, 0, 10, 1.0);
    const bytes = try encode(a, &ok);
    defer a.free(bytes);
    try std.testing.expectError(error.InvalidOverlay, decode(a, bytes[0 .. bytes.len - 1], 4)); // truncated
    var padded = try a.alloc(u8, bytes.len + 1);
    defer a.free(padded);
    @memcpy(padded[0..bytes.len], bytes);
    padded[bytes.len] = 0;
    try std.testing.expectError(error.InvalidOverlay, decode(a, padded, 4)); // trailing byte
    var wrong_version = try a.dupe(u8, bytes);
    defer a.free(wrong_version);
    wrong_version[0] = 2;
    try std.testing.expectError(error.InvalidOverlay, decode(a, wrong_version, 4));
    try std.testing.expectError(error.InvalidOverlay, decode(a, bytes, 1)); // more chunks than allowed
    // A seam that disagrees between two chunks is rejected: break the first run of the second chunk.
    var torn = try a.dupe(u8, bytes);
    defer a.free(torn);
    var at: usize = 3 + 8; // first chunk's data
    var filled: usize = 0;
    while (filled < points_per_chunk) : (at += 2) filled += torn[at];
    at += 8; // second chunk's key
    torn[at + 1] +%= 5; // change the value of its first run (its left edge)
    try std.testing.expectError(error.InvalidOverlay, decode(a, torn, 4));
}

fn overlayProbe(allocator: std.mem.Allocator) !void {
    var overlay: Overlay = .{ .max_chunks = 4 };
    defer overlay.deinit(allocator);
    try overlay.stamp(allocator, 64, 0, 10, 1.5);
    const bytes = try encode(allocator, &overlay);
    defer allocator.free(bytes);
    var back = try decode(allocator, bytes, 4);
    back.deinit(allocator);
}

test "the edit layer frees everything when an allocation fails part-way" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, overlayProbe, .{});
}
```

## 9. Mining

### Surface and shallow mining

- **Ore nodes.** `Ore.layout(seed)` places nodes deterministically on cave floors (using the existing floor-spot helper) and mountain outcrops, each with a richness and a tool tier. Depletion and respawn are stored sparsely by node id and timestamp.
- **Harvest.** Hold to mine with the right tool tier; ore goes to the player's `Kit` or, near a **mining outpost**, is hauled to the shared stockpile at a bounded rate.
- **Forge.** Turns ore into alloy using power (the economy step).
- **Quarries.** A quarry structure converts terraform lowering inside its area into stone at a bounded rate.

### Deep mines (owner decision: as deep as the deepest known mine)

The deepest known mine in the world is **Mponeng gold mine in South Africa, about 4 km deep** (the operator reports 3,891 m below datum, other sources about 4.0 km, and plans to go further). The game's maximum mine depth is **4,000 m**.

A 4 km vertical range cannot live inside the world's height field (terrain spans tens of metres, mountains about 1.3 to 1.7 km), so a deep mine is its own generated space, entered by a **lift**:

- **Shaft and lift.** A mine is a structure on a claim (at most 4 per settlement) with a headframe and a lift. The lift travels between **levels every 100 m (40 levels)**; riding it is a short transition, so the world never needs 4 km of vertical streaming.
- **Levels.** Each level is a cave-style complex generated from a seed of `(mine, level)`, with drifts, halls, ore bodies and a lift station. It is built on a worker when entered (like the cave systems), kept only while loaded (the current level and the lift shaft), and evicted when left. Level geometry is **never saved**; only the seed, the deepest level reached, the lift tier, the placed supports, and which ore nodes are depleted are saved.
- **Descent tiers.** A lift tier limits depth: tier 1 to 500 m, tier 2 to 1,500 m, tier 3 to 4,000 m. Higher tiers cost alloy and need more sap power.
- **Depth makes it dangerous and richer.** Rock heat rises with depth (a game-scale curve to tune), so deep levels need cooling and ventilation structures run from sap, and suits that resist heat; cave-in risk rises with depth and is reduced by player-placed supports; Hive burrowers and gas pockets appear at depth, so deep mining stays a hack-and-slash activity. Ore richness and rarity increase with depth (placeholder bands: stone and common ore to 500 m, alloy ore and lumen crystal to 1,500 m, the rarest ores below).
- **Weather and mines.** Mines are underground, so weather does not reach them; their headframes and surface buildings are structures like any other and can be damaged by storms.
- **Raids.** Mine entrances near caves attract Hive raids through the existing corruption and raid systems.

**Unmeasured risks, labelled so they are not mistaken for facts:** the build time and memory of a generated level (the existing cave meshes are built on a worker at about 1 m cells; a mine level is a different shape and size and must be measured at B6b); the exact heat and cave-in curves; and whether 40 levels of 100 m reads as depth or as repetition. Free tunnelling through the open world remains out of scope: the open-world cave meshes are static and the cave queries analytic.

## 10. City planning UI

A **plan mode** with an orbit camera over the claim, zone and road drawing, ghost placement coloured by validity, and overlays: slope, fertility, power, water, threat. It is built on the pointer and gesture layer from the [asset studio](asset-studio.md) so mouse, controller and touch all work, and uses the studio's `History` for undo. Initially the first player plans and builds; every player can contribute, harvest and mine. Guest planning follows the co-op completeness milestone.

## 11. Saves and caps

One new defaulted section in the save `Document` (so old saves still load), one `Save.format_version` bump to 26, a checked-in `save-v26.json` fixture, and a decode cap for every list:

| Data | Cap | Notes |
| --- | --- | --- |
| Claims | 8 | centre, radius, founder, level |
| Plot grid | per claim, 48 by 48 cells | run-length encoded |
| Structures | about 2,048 | compact integer arrays, not indented objects |
| Fields | about 1,024 | crop, points, water left, alive |
| Stockpile and population | one record | six counters and a count |
| Last economy hour | one `u64` tick | for bounded catch-up |
| Ore and mine depletion | about 4,096 | surface node ids and (mine, level, node) records with timestamps |
| Terrain edits | 96 chunks, about 1 MiB encoded | section 8; eight claims of up to 96 m span at most 72 chunks |
| Water network | 512 nodes, 1,024 links | stock per node; links as integer arrays |
| Mines | 4 per settlement, 40 levels each | seed, lift tier, deepest level reached, supports; geometry regenerated |
| Structure health | one `u16` per structure | inside the structure store |

Estimated total well under 2 MiB against the 4 MiB cap (an estimate, to be measured at B0). `Progress.max_flags` is not used for any per-plot state.

## 12. Phases

Sizes: S under a day, M a few days, L about a week. These are user-directed tracks time-boxed against the MVP gate ([next steps](next-steps.md)). Order: the weather and seasons plan first (no save change), then B4, then B0 to B3, then B5 to B9.

| Phase | Work | Size | Depends on |
| --- | --- | --- | --- |
| B0 | data tables, claims, the structure store, validators, the save section, caps, `save-v26.json` | M | |
| B1 | the hourly economy step, stockpile, offline catch-up, readouts | M | B0 |
| B2 | placement on plots, bulk structures, instanced render, merged colliders | M | B0 |
| B3 | farming: crops, fields, greenhouse, harvest, and storm, frost and raid losses | M | B1, weather W0 |
| B3b | the irrigation network: wells, tanks, channels, pipes, gates, sprinklers, ponds, hourly water step and ice stops | L | B3, B5 for ponds and channels |
| B4 | **terrain height refactor (T0)**, `Streamer.invalidate`, the grep-style test | M | |
| B5 | terraform tools, the overlay, the no-edit zones, the overlay save section | L | B4, B0 |
| B6a | ore nodes, quarries, mining outposts, forge | M | B1, B5 |
| B6b | deep mines: shaft, lift, generated levels to 500 m, supports | L | B6a |
| B6c | deep mines to 4,000 m: lift tiers, heat, cooling and ventilation, depth hazards and ore bands | L | B6b |
| B7 | plan mode UI | L | B2, studio pointer layer |
| B8 | population, levels, raids | M | B1, B6 |
| B9 | Arbor shelf decks and the sap load | M | B2 |
| B10 | weather damage and repair for structures; ruins | M | B2, weather W2 |

Each phase ends with `tools/validation_gate.py`, the captures it needs, and a dated entry in [validation](../validation.md) saying what ran.

**Tests that must be able to fail** (examples): a refused placement, stamp or load leaves state unchanged; a stamp's shared edges agree; the economy never exceeds a cap or goes negative; growth is identical played straight or resumed; scatter ids are identical with and without an overlay; every list's decode cap rejects an oversized save; a four-player test where two players contribute and each keeps their own `Kit`.

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| Terrain overlay disagrees with chunk mesh, collision, scatter or biome | one height function (T0 first); a test that nothing else calls the base noise; seam checks on write and load |
| Scatter ids shift and corrupt saved removals | placement decided from base terrain; claims clear scatter by removal, not by regeneration |
| Rivers, caves and the district break near edits | no-edit margins; rivers and caves use base height |
| Worker reads while the main thread edits | immutable snapshot with a revision, swapped atomically |
| Save size and format churn | compact encodings, caps, one bump, a fixture, a measured budget at B0 |
| Hard caps (16 machines, 4 bridges, 96 flags) block growth | a separate structure store; no per-plot flags |
| Four-player fairness and ownership | shared stockpile with explicit contribution, per-structure builder, personal rewards in `Kit`, a two-player test |
| Physics and draw cost of thousands of structures | merged per-chunk colliders, instanced draws, budgets checked in the benchmark |
| The economy becomes a chore | hourly step, low upkeep, visible readouts, no punishing failure states at first |
| Deep mine levels cost too much to generate or hold | build on a worker when entered, keep only the current level, measure at B6b, reduce cave size or detail before widening |
| The irrigation network becomes fiddly | automatic fitting (sprinklers find fields), a clear overlay of flow and shortage, sensible defaults, and the conservation test |
| Weather damage feels punishing | resilience upgrades, cheap repair from the stockpile, ruins rebuild cheaper, tune hit rates by playing |
| Scope against the MVP | time-boxed, sequenced after the MVP gate |

## 14. Decisions

**Recorded (owner, 2026-10-15):**

| Topic | Decision | Effect |
| --- | --- | --- |
| Crop losses | storms and Hive raids can destroy crops | section 7 and the compiled storm test |
| Settlers | both a count and visible people | section 6 |
| Stockpile access | any player may withdraw, **no caps** | section 3; withdrawals are logged per player only |
| Structure damage | weather can damage structures | section 5, the compiled damage test, phase B10 |
| Claim sizes | left to me | 40 m growing to 96 m by level (section 4) |
| Mining depth | as deep as the deepest known mine | 4,000 m, by lift tiers (section 9) |
| Irrigation | full irrigation systems | section 7, the compiled water-network tests, phase B3b |
| Seasons and sap | no seasonal change to machine power | no hook |

**Still open (tuning, not decisions):**
1. Whether raids also damage structures (raids destroy crops by decision; structure damage from raids is not yet decided).
2. Whether deep mines need a gameplay reason to reach the very bottom, such as a unique ore or story site.
3. Which structure kinds ship first, and whether they come from the City studio or existing generators.
4. The heat and cave-in curves, and the placeholder ore bands.
5. Whether ponds may be dug anywhere inside a claim or only on suitable ground.

## 15. Reference

Sources read: [Build.zig](../../src/game/Build.zig), [Blueprint.zig](../../src/machine/Blueprint.zig), [District.zig](../../src/procedural/District.zig), [Market.zig](../../src/city/Market.zig), [Kit.zig](../../src/game/Kit.zig), [Fabricator.zig](../../src/game/Fabricator.zig), [Sap.zig](../../src/machine/Sap.zig), [Arbor.zig](../../src/procedural/Arbor.zig), [Terrain.zig](../../src/procedural/Terrain.zig), [Chunk.zig](../../src/procedural/Chunk.zig), [Scatter.zig](../../src/procedural/Scatter.zig), [Caves.zig](../../src/procedural/Caves.zig), [Landscape.zig](../../src/procedural/Landscape.zig), [Streamer.zig](../../src/world/Streamer.zig), [Modifications.zig](../../src/world/Modifications.zig), [Save.zig](../../src/game/Save.zig), [Progress.zig](../../src/game/Progress.zig), [Frontier.zig](../../src/game/Frontier.zig).

```sh
python3 tools/zig.py test settlement_examples.zig                              # default pair: 11 of 11
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test settlement_examples.zig  # 0.17: 11 of 11
```
