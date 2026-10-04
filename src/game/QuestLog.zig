//! The active Hive-campaign objective, derived from saved story flags and live war state.
const std = @import("std");
const Enemies = @import("Enemies.zig");
const Progress = @import("Progress.zig");
const Skies = @import("Skies.zig");

pub const Objective = struct {
    title: []const u8,
    detail: []const u8,
    nests_left: u8 = 0,
    carriers_left: u8 = 0,
};

pub fn remainingNests(enemies: *const Enemies) u8 {
    var count: u8 = 0;
    for (enemies.nests[0..enemies.nest_count]) |nest| count += @intFromBool(nest.alive);
    return count;
}

pub fn remainingCarriers(skies: *const Skies) u8 {
    var count: u8 = 0;
    for (skies.carriers) |carrier| count += @intFromBool(carrier.alive);
    return count;
}

fn firstSurfaceNestDown(progress: *const Progress) bool {
    if (progress.hasFlag("first_spire_broken")) return true;
    for (0..Enemies.surface_nests) |i| {
        var flag: [16]u8 = undefined;
        if (progress.hasFlag(std.fmt.bufPrint(&flag, "nest_{d}_down", .{i}) catch unreachable)) return true;
    }
    return false;
}

pub fn current(progress: *const Progress, enemies: *const Enemies, skies: *const Skies) Objective {
    const nests = remainingNests(enemies);
    const carriers = remainingCarriers(skies);
    if (!progress.hasFlag("met_tavi")) return .{ .title = "FIND TAVI", .detail = "Visit the west market and ask the scout about the black spires." };
    if (!progress.hasFlag("tavi_scouted")) return .{ .title = "GET TAVI'S SCOUTING MARK", .detail = "Ask Tavi to mark the nearest Hive spire." };
    if (!firstSurfaceNestDown(progress)) return .{ .title = "BREAK THE MARKED SPIRE", .detail = "Follow Tavi's map to a surface nest and destroy it.", .nests_left = nests, .carriers_left = carriers };
    if (!progress.hasFlag("ines_sap_warned")) return .{ .title = "ASK INES ABOUT THE STAIN", .detail = "The Hive is spreading. Find Ines at the north market." };
    if (!progress.hasFlag("carrier_seen")) return .{ .title = "SIGHT A BROOD CARRIER", .detail = "Head beyond the frontier and get within view of a carrier." };
    if (!progress.hasFlag("kestrel_blueprint") and !progress.fighter) return .{ .title = "GET MARO'S KESTREL BLUEPRINT", .detail = "Tell Maro you saw the carrier; then use the fabricator." };
    if (!progress.fighter) return .{ .title = "FABRICATE THE KESTREL", .detail = "Use the frontier fabricator to build Maro's fighter design." };
    if (nests > 0) return .{ .title = "CLEAR THE HIVE NESTS", .detail = "Destroy the remaining surface and cave spires.", .nests_left = nests, .carriers_left = carriers };
    if (carriers > 0) return .{ .title = "DESTROY THE BROOD CARRIERS", .detail = "Break both carriers' defenses, bays and exposed cores.", .carriers_left = carriers };
    return .{ .title = "THE FRONTIER IS SECURE", .detail = "The Hive nests and Brood carriers have all fallen." };
}

test "Hive quest follows story flags, a surface spire, the Kestrel, and war state" {
    var progress: Progress = .{};
    var enemies: Enemies = .{};
    enemies.nest_count = 1;
    enemies.nests[0] = .{ .position = .{ 0, 0, 0 } };
    var skies: Skies = undefined;
    skies.carriers = @splat(.{ .center = .{ 0, 0, 0 }, .radius = 0, .altitude = 0, .angle = 0 });
    try std.testing.expectEqualStrings("FIND TAVI", current(&progress, &enemies, &skies).title);
    progress.setFlag("met_tavi");
    try std.testing.expectEqualStrings("GET TAVI'S SCOUTING MARK", current(&progress, &enemies, &skies).title);
    progress.setFlag("tavi_scouted");
    try std.testing.expectEqualStrings("BREAK THE MARKED SPIRE", current(&progress, &enemies, &skies).title);
    progress.setFlag("nest_0_down");
    try std.testing.expectEqualStrings("ASK INES ABOUT THE STAIN", current(&progress, &enemies, &skies).title);
    progress.setFlag("ines_sap_warned");
    progress.setFlag("carrier_seen");
    try std.testing.expectEqualStrings("GET MARO'S KESTREL BLUEPRINT", current(&progress, &enemies, &skies).title);
    progress.setFlag("kestrel_blueprint");
    try std.testing.expectEqualStrings("FABRICATE THE KESTREL", current(&progress, &enemies, &skies).title);
    progress.fighter = true;
    enemies.nests[0].alive = false;
    skies.carriers[0].alive = false;
    skies.carriers[1].alive = false;
    try std.testing.expectEqualStrings("THE FRONTIER IS SECURE", current(&progress, &enemies, &skies).title);
}

test "existing Kestrel saves do not get stuck on the new blueprint objective" {
    var progress: Progress = .{ .fighter = true };
    progress.setFlag("met_tavi");
    progress.setFlag("tavi_scouted");
    progress.setFlag("first_spire_broken");
    progress.setFlag("ines_sap_warned");
    progress.setFlag("carrier_seen");
    var enemies: Enemies = .{};
    enemies.nest_count = 1;
    enemies.nests[0] = .{ .position = .{ 0, 0, 0 } };
    var skies: Skies = undefined;
    skies.carriers = @splat(.{ .center = .{ 0, 0, 0 }, .radius = 0, .altitude = 0, .angle = 0, .alive = true });
    try std.testing.expectEqualStrings("CLEAR THE HIVE NESTS", current(&progress, &enemies, &skies).title);
}
