//! Shared state and deterministic industrial checkpoints for Detroit's draft Foundry Ledger case.
//! Clue flags live in team Progress; the suit reward is applied independently to each Kit.
const std = @import("std");
const District = @import("../procedural/District.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Progress = @import("Progress.zig");
const Kit = @import("Kit.zig");
const V = @import("../physics/Rotation.zig").Vec3;

pub const checkpoint_count = 3;
pub const complete_flag = "foundry_pages_complete";
pub const reported_flag = "foundry_reported";
pub const confrontation_flag = "foundry_ambush_started";
pub const exposed_flag = "foundry_exposed";
const checkpoint_flags = [_][]const u8{
    "foundry_manifest_1",
    "foundry_manifest_2",
    "foundry_manifest_3",
};

/// Deterministic loading-dock-side positions beside three generated industrial buildings.
/// It prefers detached, low-rise factories, then fills from any remaining industrial building.
pub fn positions(layout: *const District.Layout, out: *[checkpoint_count]V) usize {
    var chosen: [checkpoint_count]usize = undefined;
    var written: usize = 0;
    // The generated industrial belt is east of the civic core. Spread the checkpoints along it.
    const anchors = [_][2]f32{ .{ 220, 145 }, .{ 360, 175 }, .{ 290, 345 } };
    for (anchors) |anchor| {
        var best: ?usize = null;
        var best_score = std.math.inf(f32);
        for (layout.buildings[0..layout.building_count], 0..) |building, index| {
            if (building.architecture != .industrial) continue;
            var already_chosen = false;
            for (chosen[0..written]) |previous| already_chosen = already_chosen or previous == index;
            if (already_chosen) continue;
            const height = building.roof - building.base[1];
            const preferred_penalty = (if (building.plaza == null) @as(f32, 0) else 240) + @max(@as(f32, 0), height - 360) * @as(f32, 0.2);
            const dx = building.base[0] - anchor[0];
            const dz = building.base[2] - anchor[1];
            const score = dx * dx + dz * dz + preferred_penalty * preferred_penalty;
            if (score < best_score) {
                best = index;
                best_score = score;
            }
        }
        const index = best orelse break;
        chosen[written] = index;
        const building = layout.buildings[index];
        out[written] = checkpointPoint(layout, building, out[0..written]);
        written += 1;
    }
    // Every seed has at least the plaza-3 factory. If skyline placement yields fewer than three
    // detached factories, use its north and south loading faces for the remaining checkpoints.
    if (written > 0) {
        const factory = layout.buildings[chosen[0]];
        while (written < checkpoint_count) {
            out[written] = checkpointPoint(layout, factory, out[0..written]);
            written += 1;
        }
    }
    return written;
}

/// Project each checkpoint beside its factory but inside the road clearance that keeps tall
/// scatter trees off the ground beneath Detroit's public skyway routes.
fn checkpointPoint(layout: *const District.Layout, building: District.Building, previous: []const V) V {
    var road = layout.nodes[0].position;
    var best_d2 = std.math.inf(f32);
    for (layout.nodes) |node| {
        const dx = building.base[0] - node.position[0];
        const dz = building.base[2] - node.position[2];
        const d2 = dx * dx + dz * dz;
        if (d2 < best_d2) {
            best_d2 = d2;
            road = node.position;
        }
    }
    for (layout.edges) |edge| {
        const span = District.span(layout, edge);
        const dx = span.b[0] - span.a[0];
        const dz = span.b[2] - span.a[2];
        const length2 = dx * dx + dz * dz;
        const t = std.math.clamp(((building.base[0] - span.a[0]) * dx + (building.base[2] - span.a[2]) * dz) / @max(length2, 0.001), 0, 1);
        const point = span.point(t);
        const px = building.base[0] - point[0];
        const pz = building.base[2] - point[2];
        const d2 = px * px + pz * pz;
        if (d2 < best_d2) {
            best_d2 = d2;
            road = point;
        }
    }
    var toward_factory: [2]f32 = .{ building.base[0] - road[0], building.base[2] - road[2] };
    const length = @sqrt(toward_factory[0] * toward_factory[0] + toward_factory[1] * toward_factory[1]);
    if (length < 0.001) toward_factory = .{ 1, 0 } else {
        toward_factory[0] /= length;
        toward_factory[1] /= length;
    }
    var x = road[0] + toward_factory[0] * (District.width * 0.5 + 4);
    var z = road[2] + toward_factory[1] * (District.width * 0.5 + 4);
    for (previous) |point| {
        const dx = x - point[0];
        const dz = z - point[2];
        if (dx * dx + dz * dz < 16 * 16) {
            // A rare low-industrial-count seed uses another side of the same plaza factory.
            x += -toward_factory[1] * 18;
            z += toward_factory[0] * 18;
        }
    }
    return .{ x, Terrain.surface(layout.seed, x, z).height + 0.9, z };
}

pub fn collected(progress: *const Progress, index: usize) bool {
    return index < checkpoint_count and progress.hasFlag(checkpoint_flags[index]);
}

pub fn count(progress: *const Progress) u8 {
    var n: u8 = 0;
    for (0..checkpoint_count) |i| n += @intFromBool(collected(progress, i));
    return n;
}

pub fn next(progress: *const Progress) ?usize {
    for (0..checkpoint_count) |i| if (!collected(progress, i)) return i;
    return null;
}

/// The collected pages may only be entered in Maro's report after all three are shared.
pub fn report(progress: *Progress) bool {
    if (!progress.hasFlag("foundry_started") or !progress.hasFlag(complete_flag) or progress.hasFlag(reported_flag)) return false;
    progress.setFlag(reported_flag);
    return true;
}

/// The dock console publishes Maro's dossier and reveals the steward's armed ambush.
pub fn beginDockConfrontation(progress: *Progress) bool {
    if (!progress.hasFlag(reported_flag) or progress.hasFlag(confrontation_flag) or progress.hasFlag(exposed_flag)) return false;
    progress.setFlag(confrontation_flag);
    return true;
}

/// Defeating the steward and brood guards exposes the foundry ally and opens the yard.
pub fn finishDockConfrontation(progress: *Progress) bool {
    if (!progress.hasFlag(confrontation_flag) or progress.hasFlag(exposed_flag)) return false;
    progress.setFlag(exposed_flag);
    return true;
}

/// The checkpoint crate occupies the loading dock's public evidence console once the pages
/// have been reported. Its y is raised so ray targeting lands on the console face.
pub fn consolePosition(layout: *const District.Layout) ?V {
    var points: [checkpoint_count]V = undefined;
    if (positions(layout, &points) == 0) return null;
    return .{ points[0][0], points[0][1] + 0.48, points[0][2] };
}

/// The closed gate and the steward's stand point across the loading-dock road from the console.
pub fn gatePosition(layout: *const District.Layout) ?V {
    var points: [checkpoint_count]V = undefined;
    if (positions(layout, &points) == 0) return null;
    return .{ points[0][0], points[0][1] - 0.9, points[0][2] + 8 };
}

/// A checkpoint can only be recovered after Maro starts the case; duplicate pickup is harmless.
pub fn collect(progress: *Progress, index: usize) bool {
    if (index >= checkpoint_count or !progress.hasFlag("foundry_started") or collected(progress, index)) return false;
    progress.setFlag(checkpoint_flags[index]);
    if (count(progress) == checkpoint_count) progress.setFlag(complete_flag);
    return true;
}

/// Applies the proposed one-level Sprint Servos reward directly to this ranger's own kit.
pub fn awardSuitUpgrade(kit: *Kit) bool {
    const upgrade: Kit.Upgrade = .sprint_servos;
    if (kit.level(upgrade) >= Kit.max_level) return false;
    kit.levels[@intFromEnum(upgrade)] += 1;
    return true;
}

test "Foundry Ledger checkpoints require the case, collect once, and persist in shared progress" {
    var progress: Progress = .{};
    try std.testing.expect(!collect(&progress, 0));
    progress.setFlag("foundry_started");
    try std.testing.expect(collect(&progress, 2));
    try std.testing.expect(collect(&progress, 0));
    try std.testing.expect(!collect(&progress, 2));
    try std.testing.expectEqual(@as(u8, 2), count(&progress));
    try std.testing.expect(!progress.hasFlag(complete_flag));
    try std.testing.expect(collect(&progress, 1));
    try std.testing.expect(progress.hasFlag(complete_flag));
    try std.testing.expectEqual(@as(u8, checkpoint_count), count(&progress));
    try std.testing.expect(next(&progress) == null);

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const json = try std.json.Stringify.valueAlloc(allocator, try progress.toDoc(allocator), .{});
    const restored = try Progress.fromDoc(try std.json.parseFromSliceLeaky(Progress.Doc, allocator, json, .{}));
    try std.testing.expect(restored.hasFlag(complete_flag));
    try std.testing.expectEqual(@as(u8, checkpoint_count), count(&restored));
    try std.testing.expect(report(&progress));
    try std.testing.expect(!report(&progress));
    try std.testing.expect(beginDockConfrontation(&progress));
    try std.testing.expect(!beginDockConfrontation(&progress));
    try std.testing.expect(!progress.hasFlag(exposed_flag));
    try std.testing.expect(finishDockConfrontation(&progress));
    try std.testing.expect(!finishDockConfrontation(&progress));
}

test "Foundry Ledger report and dock exposure require the correct shared progression order" {
    var progress: Progress = .{};
    try std.testing.expect(!report(&progress));
    try std.testing.expect(!beginDockConfrontation(&progress));
    try std.testing.expect(!finishDockConfrontation(&progress));
    progress.setFlag("foundry_started");
    try std.testing.expect(!report(&progress));
    for (0..checkpoint_count) |index| try std.testing.expect(collect(&progress, index));
    try std.testing.expect(report(&progress));
    try std.testing.expect(!progress.hasFlag(exposed_flag));
    try std.testing.expect(beginDockConfrontation(&progress));
    try std.testing.expect(finishDockConfrontation(&progress));
    try std.testing.expect(progress.hasFlag(exposed_flag));
}

test "Foundry checkpoints are distinct and use generated industrial buildings" {
    for ([_]u64{ 1, 7, 310399555161, 0xdeadbeef, 0x1badb002 }) |seed| {
        const layout = try District.generate(seed);
        var points: [checkpoint_count]V = undefined;
        try std.testing.expectEqual(@as(usize, checkpoint_count), positions(&layout, &points));
        for (points) |point| try std.testing.expect(District.nearRoad(seed, point[0], point[2], 26));
        for (points, 0..) |point, i| for (points[0..i]) |other| {
            const dx = point[0] - other[0];
            const dz = point[2] - other[2];
            try std.testing.expect(dx * dx + dz * dz > 100);
        };
    }
}

test "Foundry Ledger suit reward is per kit and respects the upgrade cap" {
    var first: Kit = .{};
    var second: Kit = .{};
    try std.testing.expect(awardSuitUpgrade(&first));
    try std.testing.expectEqual(@as(u8, 1), first.level(.sprint_servos));
    try std.testing.expectEqual(@as(u8, 0), second.level(.sprint_servos));
    first.levels[@intFromEnum(Kit.Upgrade.sprint_servos)] = Kit.max_level;
    try std.testing.expect(!awardSuitUpgrade(&first));
}
