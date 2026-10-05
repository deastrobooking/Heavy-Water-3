//! Campaign destinations and bounded co-op arena slices. Planet-scale coordinates are metadata;
//! gameplay remains in a local streamed frame so terrain, physics, and f32 transforms stay stable.
const std = @import("std");
const Seed = @import("Seed.zig");

pub const player_capacity = 4;
pub const catalog_version: u32 = 1;
pub const earth_radius_m: f64 = 6_371_000;
pub const mile_m: f32 = 1609.344;

pub const Id = enum(u8) { arbor_frontier = 0, hive_homeworld = 1, gaia = 2 };
pub const Form = enum { regional_frontier, planetary_surface, artificial_globe };
pub const Biome = enum { canopy_rootdeep, hive_chitin, gaia_habitat, gaia_wilds };
pub const Faction = enum { arbor_colony, hive_brood, scalari, gaia_colony };
pub const CityId = enum(u16) {
    arboris_reach = 0x0101,
    rootdeep_ward = 0x0102,
    crownfall = 0x0103,
    bridgewell = 0x0104,
    solace_basin = 0x0105,
    varkhoss = 0x0201,
    nacre_spindle = 0x0202,
    sable_crucible = 0x0203,
    threxian_fold = 0x0204,
    broodheart = 0x0205,
    meridian_habitat = 0x0301,
    aster_vale = 0x0302,
    faraday_deep = 0x0303,
    equator_garden = 0x0304,
    jovian_gate = 0x0305,
};
pub const CityRole = enum { market, seed_vault, observatory, engineering, riverworks, scalari_ruins, brood_industry, forge, brood_habitat, hive_nexus, colony_hub, agriculture, research, biosphere, orbital_port };
pub const City = struct {
    id: CityId,
    world: Id,
    name: []const u8,
    role: CityRole,
    biome: Biome,
    exploration_hook: []const u8,
};
pub const Capital = struct {
    world: Id,
    name: []const u8,
    identity: []const u8,
    final_boss_site: bool = false,
    final_boss: ?[]const u8 = null,
};
pub const ArenaId = enum(u16) {
    rootdeep_shrine = 0x0101,
    spire_basin = 0x0102,
    outer_husk = 0x0201,
    brood_heart = 0x0202,
    sulfur_rift = 0x0203,
    habitat_ruins = 0x0301,
    agri_ring = 0x0302,
    geodesic_spine = 0x0303,
};
pub const Encounter = enum { shrine_recovery, spire_assault, salvage_run, nest_break, brood_siege, colony_defense, terraforming, shell_repair };
pub const Reward = struct {
    lumen: u16 = 0,
    rotor_cores: u8 = 0,
    hive_alloy: u16 = 0,
    brood_enzymes: u16 = 0,
    geodesic_alloy: u16 = 0,
    fabrication_data: u8 = 0,
};

pub const World = struct {
    id: Id,
    name: []const u8,
    form: Form,
    home_biome: Biome,
    arena_diameter_m: u16,
    planet_radius_m: f64 = 0,
    sky_clearance_m: f32 = 0,
    rotation_hours: f32 = 0,
    geodesic_shell: bool = false,
    resident_faction: Faction,
    ancient_founder: ?Faction = null,
};

pub const Arena = struct {
    id: ArenaId,
    world: Id,
    name: []const u8,
    biome: Biome,
    encounter: Encounter,
    radius_m: u16,
    poi_count: u8,
    build_sites: u8,
    reward: Reward,
    min_players: u8 = 1,
    max_players: u8 = player_capacity,
};

pub const worlds = [_]World{
    .{ .id = .arbor_frontier, .name = "Arbor Frontier", .form = .regional_frontier, .home_biome = .canopy_rootdeep, .arena_diameter_m = 1800, .resident_faction = .arbor_colony },
    .{ .id = .hive_homeworld, .name = "Hive Homeworld", .form = .planetary_surface, .home_biome = .hive_chitin, .arena_diameter_m = 2000, .resident_faction = .hive_brood, .ancient_founder = .scalari },
    .{ .id = .gaia, .name = "Gaia", .form = .artificial_globe, .home_biome = .gaia_habitat, .arena_diameter_m = 1800, .planet_radius_m = earth_radius_m, .sky_clearance_m = mile_m, .rotation_hours = 24, .geodesic_shell = true, .resident_faction = .gaia_colony },
};

/// Five major explorable city regions per destination. These are campaign content descriptors,
/// not a claim that city geometry or world travel is already playable.
pub const cities = [_]City{
    .{ .id = .arboris_reach, .world = .arbor_frontier, .name = "Arboris Reach", .role = .market, .biome = .canopy_rootdeep, .exploration_hook = "Canopy markets, transit bridges, and the first shipyard route." },
    .{ .id = .rootdeep_ward, .world = .arbor_frontier, .name = "Rootdeep Ward", .role = .seed_vault, .biome = .canopy_rootdeep, .exploration_hook = "Buried engineer vaults and machine shrines beneath the buttress roots." },
    .{ .id = .crownfall, .world = .arbor_frontier, .name = "Crownfall", .role = .observatory, .biome = .canopy_rootdeep, .exploration_hook = "A high observatory district overlooking the mountain rivers." },
    .{ .id = .bridgewell, .world = .arbor_frontier, .name = "Bridgewell", .role = .engineering, .biome = .canopy_rootdeep, .exploration_hook = "Suspended bridge foundries and vehicle test routes between Arbors." },
    .{ .id = .solace_basin, .world = .arbor_frontier, .name = "Solace Basin", .role = .riverworks, .biome = .canopy_rootdeep, .exploration_hook = "River locks, waterworks, and a frontier landing zone." },
    .{ .id = .varkhoss, .world = .hive_homeworld, .name = "Varkhoss", .role = .scalari_ruins, .biome = .hive_chitin, .exploration_hook = "Scalari ruins expose the earliest records of the engineered Hive." },
    .{ .id = .nacre_spindle, .world = .hive_homeworld, .name = "Nacre Spindle", .role = .brood_industry, .biome = .hive_chitin, .exploration_hook = "Vertical resin mills and living production towers." },
    .{ .id = .sable_crucible, .world = .hive_homeworld, .name = "Sable Crucible", .role = .forge, .biome = .hive_chitin, .exploration_hook = "A volcanic armor forge guarded by Scalari dragon-wing squadrons." },
    .{ .id = .threxian_fold, .world = .hive_homeworld, .name = "Threxian Fold", .role = .brood_habitat, .biome = .hive_chitin, .exploration_hook = "A vast brood quarter where modified insect lineages can be traced." },
    .{ .id = .broodheart, .world = .hive_homeworld, .name = "Broodheart", .role = .hive_nexus, .biome = .hive_chitin, .exploration_hook = "The Hive command nexus and the route into the Scalari capital." },
    .{ .id = .meridian_habitat, .world = .gaia, .name = "Meridian Habitat", .role = .colony_hub, .biome = .gaia_habitat, .exploration_hook = "The colony's first landing terraces beneath the geodesic sky." },
    .{ .id = .aster_vale, .world = .gaia, .name = "Aster Vale", .role = .agriculture, .biome = .gaia_wilds, .exploration_hook = "Terraced farms, pollinator forests, and terraforming machinery." },
    .{ .id = .faraday_deep, .world = .gaia, .name = "Faraday Deep", .role = .research, .biome = .gaia_habitat, .exploration_hook = "A shielded science district with a damaged shell-control relay." },
    .{ .id = .equator_garden, .world = .gaia, .name = "Equator Garden", .role = .biosphere, .biome = .gaia_wilds, .exploration_hook = "A warm biome reserve where the rotating habitat's climate systems meet." },
    .{ .id = .jovian_gate, .world = .gaia, .name = "Jovian Gate", .role = .orbital_port, .biome = .gaia_habitat, .exploration_hook = "The cargo port and orbital approach linking Gaia to Jupiter space." },
};

/// A capital is a distinct campaign destination/site in addition to the five city regions.
/// The Scalari capital on the Hive Homeworld hosts the campaign's final boss encounter.
pub const capitals = [_]Capital{
    .{ .world = .arbor_frontier, .name = "Crown Harbor", .identity = "The Arbor colony's shipyard and campaign home base." },
    .{ .world = .hive_homeworld, .name = "The Obsidian Coil", .identity = "The Scalari throne-base built around the Hive's command heart.", .final_boss_site = true, .final_boss = "The Scalari Sovereign" },
    .{ .world = .gaia, .name = "Concord Spire", .identity = "Gaia's human colony capital and planetary command center." },
};

pub const arenas = [_]Arena{
    .{ .id = .rootdeep_shrine, .world = .arbor_frontier, .name = "Rootdeep Shrine Basin", .biome = .canopy_rootdeep, .encounter = .shrine_recovery, .radius_m = 650, .poi_count = 5, .build_sites = 4, .reward = .{ .lumen = 24, .rotor_cores = 1, .fabrication_data = 1 } },
    .{ .id = .spire_basin, .world = .arbor_frontier, .name = "Spirefall Basin", .biome = .canopy_rootdeep, .encounter = .spire_assault, .radius_m = 700, .poi_count = 6, .build_sites = 3, .reward = .{ .lumen = 18, .hive_alloy = 8, .fabrication_data = 1 } },
    .{ .id = .outer_husk, .world = .hive_homeworld, .name = "The Outer Husk", .biome = .hive_chitin, .encounter = .salvage_run, .radius_m = 750, .poi_count = 5, .build_sites = 3, .reward = .{ .hive_alloy = 30, .brood_enzymes = 8, .fabrication_data = 1 } },
    .{ .id = .brood_heart, .world = .hive_homeworld, .name = "Brood Heart", .biome = .hive_chitin, .encounter = .nest_break, .radius_m = 850, .poi_count = 7, .build_sites = 2, .reward = .{ .hive_alloy = 42, .brood_enzymes = 18, .rotor_cores = 2, .fabrication_data = 2 } },
    .{ .id = .sulfur_rift, .world = .hive_homeworld, .name = "Sulfur Rift", .biome = .hive_chitin, .encounter = .brood_siege, .radius_m = 800, .poi_count = 6, .build_sites = 4, .reward = .{ .hive_alloy = 24, .brood_enzymes = 12, .fabrication_data = 1 } },
    .{ .id = .habitat_ruins, .world = .gaia, .name = "Habitat Ruins", .biome = .gaia_habitat, .encounter = .colony_defense, .radius_m = 650, .poi_count = 6, .build_sites = 6, .reward = .{ .lumen = 12, .geodesic_alloy = 24, .fabrication_data = 2 } },
    .{ .id = .agri_ring, .world = .gaia, .name = "Agri Ring", .biome = .gaia_wilds, .encounter = .terraforming, .radius_m = 700, .poi_count = 5, .build_sites = 8, .reward = .{ .lumen = 16, .geodesic_alloy = 18, .fabrication_data = 1 } },
    .{ .id = .geodesic_spine, .world = .gaia, .name = "Geodesic Spine", .biome = .gaia_habitat, .encounter = .shell_repair, .radius_m = 800, .poi_count = 7, .build_sites = 4, .reward = .{ .geodesic_alloy = 36, .rotor_cores = 2, .fabrication_data = 2 } },
};

pub fn get(id: Id) World {
    return worlds[@intFromEnum(id)];
}

pub fn arena(id: ArenaId) Arena {
    for (arenas) |entry| if (entry.id == id) return entry;
    unreachable;
}

pub fn capital(id: Id) Capital {
    for (capitals) |entry| if (entry.world == id) return entry;
    unreachable;
}

/// World- and arena-scoped seeds prevent one destination's generation changes from perturbing
/// another. The campaign seed remains the stable root stored by the save system.
pub fn worldSeed(campaign_seed: u64, id: Id) u64 {
    return Seed.mix(campaign_seed ^ (0x574f524c44000000 | @as(u64, @intFromEnum(id))));
}

pub fn arenaSeed(campaign_seed: u64, id: ArenaId) u64 {
    const spec = arena(id);
    return Seed.mix(worldSeed(campaign_seed, spec.world) ^ (0x4152454e41000000 | @as(u64, @intFromEnum(id))));
}

pub fn validate() bool {
    for (worlds, 0..) |spec, i| {
        if (@as(usize, @intFromEnum(spec.id)) != i or spec.arena_diameter_m == 0) return false;
        if (spec.form == .artificial_globe and (spec.planet_radius_m <= 0 or spec.sky_clearance_m <= 0 or !spec.geodesic_shell or spec.rotation_hours <= 0)) return false;
    }
    var city_count: [worlds.len]u8 = @splat(0);
    for (cities, 0..) |entry, i| {
        if (entry.name.len == 0 or entry.exploration_hook.len == 0) return false;
        city_count[@intFromEnum(entry.world)] += 1;
        for (cities[i + 1 ..]) |other| if (entry.id == other.id) return false;
    }
    for (city_count) |count| if (count != 5) return false;
    if (capitals.len != worlds.len) return false;
    var capital_count: [worlds.len]u8 = @splat(0);
    var final_boss_sites: u8 = 0;
    for (capitals, 0..) |entry, i| {
        capital_count[@intFromEnum(entry.world)] += 1;
        if (entry.name.len == 0 or entry.identity.len == 0) return false;
        if (entry.final_boss_site) {
            final_boss_sites += 1;
            if (entry.final_boss == null or entry.world != .hive_homeworld) return false;
        } else if (entry.final_boss != null) return false;
        for (capitals[i + 1 ..]) |other| if (entry.world == other.world) return false;
    }
    for (capital_count) |count| if (count != 1) return false;
    if (final_boss_sites != 1 or get(.hive_homeworld).ancient_founder != .scalari) return false;
    var world_has_arena: [worlds.len]bool = @splat(false);
    for (arenas, 0..) |entry, i| {
        if (entry.radius_m == 0 or entry.radius_m * 2 > get(entry.world).arena_diameter_m or entry.poi_count == 0 or entry.max_players != player_capacity or entry.min_players == 0 or entry.min_players > entry.max_players) return false;
        world_has_arena[@intFromEnum(entry.world)] = true;
        for (arenas[i + 1 ..]) |other| if (entry.id == other.id) return false;
    }
    for (world_has_arena) |has_arena| if (!has_arena) return false;
    return true;
}

test "campaign world catalog is bounded, four-player ready, and deterministically seeded" {
    try std.testing.expect(validate());
    const gaia = get(.gaia);
    try std.testing.expectEqual(@as(f64, 6_371_000), gaia.planet_radius_m);
    try std.testing.expectEqual(@as(f32, 1609.344), gaia.sky_clearance_m);
    try std.testing.expect(gaia.geodesic_shell and gaia.rotation_hours > 0);
    try std.testing.expectEqual(@as(u8, 4), arena(.brood_heart).max_players);
    const a = arenaSeed(0x4845415659, .brood_heart);
    try std.testing.expectEqual(a, arenaSeed(0x4845415659, .brood_heart));
    try std.testing.expect(a != arenaSeed(0x4845415659, .habitat_ruins));
    try std.testing.expect(worldSeed(4, .hive_homeworld) != worldSeed(4, .gaia));
    try std.testing.expect(arena(.habitat_ruins).reward.geodesic_alloy > 0);
    try std.testing.expect(arena(.brood_heart).reward.brood_enzymes > 0);
    try std.testing.expectEqual(@as(usize, 15), cities.len);
    try std.testing.expectEqual(@as(u8, 5), blk: {
        var count: u8 = 0;
        for (cities) |entry| if (entry.world == .gaia) {
            count += 1;
        };
        break :blk count;
    });
    try std.testing.expect(capital(.hive_homeworld).final_boss_site);
    try std.testing.expectEqualStrings("The Scalari Sovereign", capital(.hive_homeworld).final_boss.?);
}
