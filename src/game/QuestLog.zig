//! The active Hive-campaign objective, derived from saved story flags and live war state.
const std = @import("std");
const Enemies = @import("Enemies.zig");
const Progress = @import("Progress.zig");
const Skies = @import("Skies.zig");
const CityContent = @import("CityContent.zig");
const FoundryCase = @import("FoundryCase.zig");

pub const Objective = struct {
    title: []const u8,
    detail: []const u8,
    nests_left: u8 = 0,
    carriers_left: u8 = 0,
    /// The objective belongs to placeholder content that the owner has not signed off.
    draft: bool = false,
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
    // The wilds are broken: the city half. Detroit is the first city to free.
    return city(progress, &CityContent.detroit);
}

/// The liberation objective for a city once the Hive is broken around it: expose the three
/// allies (the sub-missions), then the boss, then the city is free.
pub fn city(progress: *const Progress, content: *const CityContent.CityContent) Objective {
    if (CityContent.liberated(content, progress)) return .{ .title = "DETROIT IS FREE", .detail = "The Hive's allies are exposed and its occupation is broken. The canopy is yours.", .draft = content.draft };
    if (CityContent.nextMission(content, progress)) |i| {
        const m = content.missions[i];
        if (i == 0 and CityContent.started(content, progress, i)) return .{
            .title = m.title,
            .detail = switch (FoundryCase.count(progress)) {
                0 => "Recover the three manifest pages from the marked factory checkpoints (0/3).",
                1 => "Recover the remaining manifest pages from the factory checkpoints (1/3).",
                2 => "Recover the last manifest page from the factory checkpoints (2/3).",
                else => if (progress.hasFlag(FoundryCase.confrontation_flag))
                    "Defeat the foundry steward and brood scavengers at the loading-dock gate."
                else if (progress.hasFlag(FoundryCase.reported_flag))
                    "Publish the ledger at the loading-dock console to draw the steward out."
                else
                    "Take the three manifest pages back to Maro, then carry the report to the loading dock.",
            },
            .draft = content.draft,
        };
        return .{ .title = m.title, .detail = m.detail, .draft = content.draft };
    }
    if (!CityContent.bossDefeated(content, progress)) return .{ .title = content.boss.name, .detail = content.boss.detail, .draft = content.draft };
    return .{ .title = "THE FRONTIER IS SECURE", .detail = "The Hive nests and Brood carriers have all fallen." };
}

test "once the wilds are broken the quest log moves to Detroit: three exposures, the Titan, freedom" {
    var progress: Progress = .{ .fighter = true };
    for ([_][]const u8{ "met_tavi", "tavi_scouted", "first_spire_broken", "ines_sap_warned", "carrier_seen" }) |f| progress.setFlag(f);
    var enemies: Enemies = .{};
    var skies: Skies = undefined;
    skies.carriers = @splat(.{ .center = .{ 0, 0, 0 }, .radius = 0, .altitude = 0, .angle = 0, .alive = false });
    try std.testing.expectEqualStrings("THE FOUNDRY LEDGER", current(&progress, &enemies, &skies).title);
    progress.setFlag("windsor_started");
    try std.testing.expectEqualStrings("THE WINDSOR GATE", current(&progress, &enemies, &skies).title);
    progress.setFlag("windsor_exposed");
    progress.setFlag("foundry_exposed");
    try std.testing.expectEqualStrings("THE BILE ARCHIVE", current(&progress, &enemies, &skies).title);
    progress.setFlag("bile_exposed");
    try std.testing.expectEqualStrings("THE COLLABORATORS' TITAN", current(&progress, &enemies, &skies).title);
    progress.setFlag("titan_defeated");
    try std.testing.expectEqualStrings("THE FRONTIER IS SECURE", current(&progress, &enemies, &skies).title);
    try std.testing.expect(CityContent.updateLiberation(&CityContent.detroit, &progress, true));
    try std.testing.expectEqualStrings("DETROIT IS FREE", current(&progress, &enemies, &skies).title);
}

test "Foundry Ledger stays active through the dock fight and advances after the yard clears" {
    var progress: Progress = .{};
    progress.setFlag("foundry_started");
    for (0..FoundryCase.checkpoint_count) |index| try std.testing.expect(FoundryCase.collect(&progress, index));
    try std.testing.expect(FoundryCase.report(&progress));
    try std.testing.expectEqualStrings("Publish the ledger at the loading-dock console to draw the steward out.", city(&progress, &CityContent.detroit).detail);

    try std.testing.expect(FoundryCase.beginDockConfrontation(&progress));
    const fight = city(&progress, &CityContent.detroit);
    try std.testing.expectEqualStrings("THE FOUNDRY LEDGER", fight.title);
    try std.testing.expectEqualStrings("Defeat the foundry steward and brood scavengers at the loading-dock gate.", fight.detail);
    try std.testing.expect(FoundryCase.finishDockConfrontation(&progress));
    try std.testing.expectEqualStrings("THE WINDSOR GATE", city(&progress, &CityContent.detroit).title);
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
    // With the wilds broken the log turns to the city (the first Detroit mission).
    try std.testing.expectEqualStrings("THE FOUNDRY LEDGER", current(&progress, &enemies, &skies).title);
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
