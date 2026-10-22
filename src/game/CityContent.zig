//! A city's liberation content as validated data: three sub-missions (each exposes one human ally
//! of the Hive), one boss battle and ten item discoveries ([city content](../../docs/plans/city-content.md)).
//! The array lengths are the budget, so "exactly 3, 1 and 10" is a compile-time fact; `validate`
//! checks everything the types cannot (unique ids, legal and unique flag names, distinct allies and
//! discovery methods, the reward spread). Progress lives in shared story flags (`Progress`);
//! personal rewards go to each player's `Kit`, never to the shared state.
//!
//! Detroit's content was approved by the owner on 2026-10-22 (`draft` is false). A new city starts
//! with `draft` true until its names, allies, boss and rewards are signed off.
const std = @import("std");
const Progress = @import("Progress.zig");

pub const mission_count = 3;
pub const discovery_count = 10;

/// The three threads of the conspiracy: every city has one ally of each kind.
pub const Ally = enum { industry, government, science };

/// How a discovery is reached. Ten different ways, so no discovery is just a walk to a marker.
pub const Method = enum { grapple_climb, service_stairs, wiring_puzzle, follow_trail, glide_across, grapple_rings, swim_dive, metro_ride, gallery_trail, tower_climb };

/// What a player keeps for themselves (goes to their own `Kit`).
pub const PersonalReward = enum { flight_cell, suit_upgrade, energy_upgrade, grapple_upgrade, travel_item, armor_gem, pet_freed, growth_item };

/// A discovery rewards each finder personally, or sets one shared flag for the whole team.
pub const Reward = union(enum) { personal: PersonalReward, shared: []const u8 };

pub const Mission = struct {
    id: []const u8,
    title: []const u8,
    /// The keeper (a speaker id in `conversations.json`) who gives it.
    giver: []const u8,
    ally: Ally,
    place: []const u8,
    /// The ally's cover and what the player must do, in one line for the quest log.
    detail: []const u8,
    /// Set when the giver hands the mission over, and when the ally is exposed (shared story).
    started_flag: []const u8,
    exposed_flag: []const u8,
    /// Each player's own reward for the exposure.
    reward: PersonalReward,
};

pub const Boss = struct {
    id: []const u8,
    name: []const u8,
    place: []const u8,
    detail: []const u8,
    started_flag: []const u8,
    defeated_flag: []const u8,
};

pub const Discovery = struct {
    id: []const u8,
    name: []const u8,
    where: []const u8,
    method: Method,
    reward: Reward,
};

pub const CityContent = struct {
    id: []const u8,
    name: []const u8,
    /// True until the owner signs off the names, allies, boss and rewards.
    draft: bool,
    missions: [mission_count]Mission,
    boss: Boss,
    discoveries: [discovery_count]Discovery,
    /// Set once the city is free: the three exposures, the boss defeated and the Hive broken around it.
    liberated_flag: []const u8,
};

pub const detroit: CityContent = .{
    .id = "detroit",
    .name = "Detroit Arbor Reach",
    .draft = false,
    .liberated_flag = "detroit_free",
    .missions = .{
        .{
            .id = "foundry_ledger",
            .title = "THE FOUNDRY LEDGER",
            .giver = "maro",
            .ally = .industry,
            .place = "the industrial belt: machine works and rail yards",
            .detail = "Maro is missing rotor cores. Trace the shipments through three checkpoints and expose the foundry steward who sells sap and alloy to the brood.",
            .started_flag = "foundry_started",
            .exposed_flag = "foundry_exposed",
            .reward = .suit_upgrade,
        },
        .{
            .id = "windsor_gate",
            .title = "THE WINDSOR GATE",
            .giver = "ines",
            .ally = .government,
            .place = "the two Windsor bridges and the Gothic civic hall",
            .detail = "Ines hears the toll gates open after dark. Watch the bridges at night and expose the councillor who lets Hive carriers cross.",
            .started_flag = "windsor_started",
            .exposed_flag = "windsor_exposed",
            .reward = .travel_item,
        },
        .{
            .id = "bile_archive",
            .title = "THE BILE ARCHIVE",
            .giver = "tavi",
            .ally = .science,
            .place = "Belle Isle, reached by glide or boat, and a vault below",
            .detail = "Tavi found Rootdeep tracks leading to the island. Break into the vault and expose the institute that trades Dr. Bile's notes with the Hive.",
            .started_flag = "bile_started",
            .exposed_flag = "bile_exposed",
            .reward = .growth_item,
        },
    },
    .boss = .{
        .id = "collaborators_titan",
        .name = "THE COLLABORATORS' TITAN",
        .place = "a bridge deck with cover and open sky",
        .detail = "Reach the west Windsor crossing after the three reports and a cleared frontier; break the Titan and its Hive waves.",
        .started_flag = "titan_started",
        .defeated_flag = "titan_defeated",
    },
    .discoveries = .{
        .{ .id = "bell_tower_cache", .name = "THE BELL TOWER CACHE", .where = "a Gothic spire", .method = .grapple_climb, .reward = .{ .personal = .flight_cell } },
        .{ .id = "undercroft_stash", .name = "THE UNDERCROFT STASH", .where = "below the plaza 1 market", .method = .service_stairs, .reward = .{ .personal = .suit_upgrade } },
        .{ .id = "sealed_sap_barrel", .name = "THE SEALED SAP BARREL", .where = "the plaza 3 loading deck", .method = .wiring_puzzle, .reward = .{ .personal = .energy_upgrade } },
        .{ .id = "scouts_rootmap", .name = "THE SCOUT'S ROOTMAP", .where = "plaza 5", .method = .follow_trail, .reward = .{ .shared = "found_rootmap" } },
        .{ .id = "arboretum_seed", .name = "THE ARBORETUM SEED", .where = "Belle Isle", .method = .glide_across, .reward = .{ .shared = "found_arbor_seed" } },
        .{ .id = "pylon_relic", .name = "THE PYLON RELIC", .where = "a Windsor bridge pylon", .method = .grapple_rings, .reward = .{ .personal = .grapple_upgrade } },
        .{ .id = "time_capsule", .name = "THE RIVERFRONT TIME CAPSULE", .where = "the promenade", .method = .swim_dive, .reward = .{ .shared = "found_time_capsule" } },
        .{ .id = "ghost_station", .name = "THE GHOST STATION", .where = "the canopy metro", .method = .metro_ride, .reward = .{ .personal = .travel_item } },
        .{ .id = "rootway_gem", .name = "THE ROOTWAY GEM", .where = "a root gallery", .method = .gallery_trail, .reward = .{ .personal = .armor_gem } },
        .{ .id = "collar_chest", .name = "THE COLLAR CHEST", .where = "a sky lobby", .method = .tower_climb, .reward = .{ .personal = .pet_freed } },
    },
};

pub const Error = error{ EmptyText, DuplicateId, BadFlag, DuplicateFlag, DuplicateAlly, DuplicateMethod, RewardSpread };

fn legalFlag(name: []const u8) bool {
    if (name.len == 0 or name.len > Progress.flag_capacity) return false;
    for (name) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '_')) return false;
    return true;
}

/// Everything the types cannot say. Runs in tests; `detroit` is also checked at compile time.
pub fn validate(city: CityContent) Error!void {
    if (city.id.len == 0 or city.name.len == 0) return error.EmptyText;
    // Flags: every flag a city can set, legal as a story flag and unique across the city.
    var flags: [mission_count * 2 + 3 + discovery_count][]const u8 = undefined;
    var n: usize = 0;
    for (city.missions) |m| {
        if (m.id.len == 0 or m.title.len == 0 or m.giver.len == 0 or m.detail.len == 0 or m.place.len == 0) return error.EmptyText;
        flags[n] = m.started_flag;
        flags[n + 1] = m.exposed_flag;
        n += 2;
    }
    if (city.boss.id.len == 0 or city.boss.name.len == 0 or city.boss.detail.len == 0 or city.boss.place.len == 0) return error.EmptyText;
    flags[n] = city.boss.started_flag;
    n += 1;
    flags[n] = city.boss.defeated_flag;
    flags[n + 1] = city.liberated_flag;
    n += 2;
    // Discoveries only own a flag when their reward is shared.
    for (city.discoveries) |d| {
        if (d.id.len == 0 or d.name.len == 0 or d.where.len == 0) return error.EmptyText;
        switch (d.reward) {
            .personal => {},
            .shared => |flag| {
                flags[n] = flag;
                n += 1;
            },
        }
    }
    for (flags[0..n], 0..) |flag, i| {
        if (!legalFlag(flag)) return error.BadFlag;
        for (flags[i + 1 .. n]) |other| if (std.mem.eql(u8, flag, other)) return error.DuplicateFlag;
    }
    // Ids are unique within their kind.
    for (city.missions, 0..) |m, i| for (city.missions[i + 1 ..]) |other| if (std.mem.eql(u8, m.id, other.id)) return error.DuplicateId;
    for (city.discoveries, 0..) |d, i| for (city.discoveries[i + 1 ..]) |other| if (std.mem.eql(u8, d.id, other.id)) return error.DuplicateId;
    // One ally of each kind, and ten different ways of finding things.
    for (city.missions, 0..) |m, i| for (city.missions[i + 1 ..]) |other| if (m.ally == other.ally) return error.DuplicateAlly;
    for (city.discoveries, 0..) |d, i| for (city.discoveries[i + 1 ..]) |other| if (d.method == other.method) return error.DuplicateMethod;
    // The spread from the plan: at most three shared discoveries, the rest personal, and at
    // least one that is not an upgrade (a pet or a cosmetic gem) so rewards are not all stats.
    var shared: usize = 0;
    var keepsake: usize = 0;
    for (city.discoveries) |d| switch (d.reward) {
        .shared => shared += 1,
        .personal => |r| if (r == .pet_freed or r == .armor_gem) {
            keepsake += 1;
        },
    };
    if (shared > 3 or keepsake < 1) return error.RewardSpread;
}

comptime {
    validate(detroit) catch |err| @compileError("Detroit's city content is invalid: " ++ @errorName(err));
}

// ---- Progress, from the shared story flags ---------------------------------------------------

pub fn started(city: *const CityContent, progress: *const Progress, mission: usize) bool {
    return progress.hasFlag(city.missions[mission].started_flag);
}

pub fn exposed(city: *const CityContent, progress: *const Progress, mission: usize) bool {
    return progress.hasFlag(city.missions[mission].exposed_flag);
}

pub fn exposedCount(city: *const CityContent, progress: *const Progress) u8 {
    var count: u8 = 0;
    for (0..mission_count) |i| count += @intFromBool(exposed(city, progress, i));
    return count;
}

/// The mission to point the player at: one already started but not finished, else the first not
/// yet exposed. Null when all three allies are exposed.
pub fn nextMission(city: *const CityContent, progress: *const Progress) ?usize {
    for (0..mission_count) |i| if (started(city, progress, i) and !exposed(city, progress, i)) return i;
    for (0..mission_count) |i| if (!exposed(city, progress, i)) return i;
    return null;
}

/// The Titan can be fought once every ally is exposed.
pub fn bossReady(city: *const CityContent, progress: *const Progress) bool {
    return exposedCount(city, progress) == mission_count;
}

pub fn bossDefeated(city: *const CityContent, progress: *const Progress) bool {
    return progress.hasFlag(city.boss.defeated_flag);
}

pub fn bossStarted(city: *const CityContent, progress: *const Progress) bool {
    return progress.hasFlag(city.boss.started_flag);
}

pub fn liberated(city: *const CityContent, progress: *const Progress) bool {
    return progress.hasFlag(city.liberated_flag);
}

/// Sets the liberation flag when its conditions hold: three exposures, the boss down, and the
/// Hive broken around the city (`frontier_clear`, from the live war state). Returns whether the
/// city became free just now.
pub fn updateLiberation(city: *const CityContent, progress: *Progress, frontier_clear: bool) bool {
    if (liberated(city, progress) or !frontier_clear or !bossReady(city, progress) or !bossDefeated(city, progress)) return false;
    progress.setFlag(city.liberated_flag);
    return true;
}

// ---- Tests -----------------------------------------------------------------------------------

test "Detroit's approved content meets the budget and the rules" {
    try validate(detroit);
    try std.testing.expect(!detroit.draft);
    try std.testing.expectEqual(@as(usize, 3), detroit.missions.len);
    try std.testing.expectEqual(@as(usize, 10), detroit.discoveries.len);
}

test "validate rejects duplicate ids, bad or repeated flags, repeated allies and methods, and a bad reward spread" {
    var c = detroit;
    c.missions[1].id = c.missions[0].id;
    try std.testing.expectError(error.DuplicateId, validate(c));
    c = detroit;
    c.missions[0].exposed_flag = "Has Spaces";
    try std.testing.expectError(error.BadFlag, validate(c));
    c = detroit;
    c.missions[0].exposed_flag = "a_flag_name_that_is_far_too_long";
    try std.testing.expectError(error.BadFlag, validate(c));
    c = detroit;
    c.missions[2].started_flag = c.missions[0].started_flag;
    try std.testing.expectError(error.DuplicateFlag, validate(c));
    c = detroit;
    c.boss.defeated_flag = c.liberated_flag;
    try std.testing.expectError(error.DuplicateFlag, validate(c));
    c = detroit;
    c.missions[2].ally = .industry;
    try std.testing.expectError(error.DuplicateAlly, validate(c));
    c = detroit;
    c.discoveries[3].method = c.discoveries[0].method;
    try std.testing.expectError(error.DuplicateMethod, validate(c));
    c = detroit;
    for (&c.discoveries, 0..) |*d, i| if (i < 5) {
        d.reward = .{ .shared = switch (i) {
            0 => "s0",
            1 => "s1",
            2 => "s2",
            3 => "s3",
            else => "s4",
        } };
    };
    try std.testing.expectError(error.RewardSpread, validate(c));
    c = detroit;
    c.name = "";
    try std.testing.expectError(error.EmptyText, validate(c));
}

test "exposures, the boss and liberation follow shared story flags" {
    var progress: Progress = .{};
    const c = &detroit;
    try std.testing.expectEqual(@as(?usize, 0), nextMission(c, &progress));
    progress.setFlag("windsor_started");
    // A started mission is pointed at before an untouched one.
    try std.testing.expectEqual(@as(?usize, 1), nextMission(c, &progress));
    progress.setFlag("windsor_exposed");
    try std.testing.expectEqual(@as(u8, 1), exposedCount(c, &progress));
    try std.testing.expectEqual(@as(?usize, 0), nextMission(c, &progress));
    try std.testing.expect(!bossReady(c, &progress));
    progress.setFlag("foundry_exposed");
    progress.setFlag("bile_exposed");
    try std.testing.expect(bossReady(c, &progress));
    try std.testing.expectEqual(@as(?usize, null), nextMission(c, &progress));
    // Not free until the boss is down and the wilds are broken.
    try std.testing.expect(!updateLiberation(c, &progress, true));
    progress.setFlag("titan_defeated");
    try std.testing.expect(!updateLiberation(c, &progress, false));
    try std.testing.expect(updateLiberation(c, &progress, true));
    try std.testing.expect(liberated(c, &progress));
    // Only once.
    try std.testing.expect(!updateLiberation(c, &progress, true));
}
