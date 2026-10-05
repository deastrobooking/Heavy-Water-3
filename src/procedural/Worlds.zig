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
    .{ .id = .arbor_frontier, .name = "Arbor Frontier", .form = .regional_frontier, .home_biome = .canopy_rootdeep, .arena_diameter_m = 1800 },
    .{ .id = .hive_homeworld, .name = "Hive Homeworld", .form = .planetary_surface, .home_biome = .hive_chitin, .arena_diameter_m = 2000 },
    .{ .id = .gaia, .name = "Gaia", .form = .artificial_globe, .home_biome = .gaia_habitat, .arena_diameter_m = 1800, .planet_radius_m = earth_radius_m, .sky_clearance_m = mile_m, .rotation_hours = 24, .geodesic_shell = true },
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
}
