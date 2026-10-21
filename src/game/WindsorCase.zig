//! Shared evidence and deterministic bridge/civic-hall locations for Detroit's Windsor Gate case.
const std = @import("std");
const District = @import("../procedural/District.zig");
const Hydrology = @import("../procedural/Hydrology.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Progress = @import("Progress.zig");
const V = @import("../physics/Rotation.zig").Vec3;

pub const checkpoint_count = 3;
pub const started_flag = "windsor_started";
pub const complete_flag = "windsor_records_complete";
pub const exposed_flag = "windsor_exposed";
const checkpoint_flags = [_][]const u8{
    "windsor_log_west",
    "windsor_log_east",
    "windsor_hall_record",
};

/// Gate logs sit at the Detroit-side control towers on the two road crossings; the recorder is
/// outside the closest Gothic building to the west civic plaza so it remains on a public route.
pub fn positions(layout: *const District.Layout, out: *[checkpoint_count]V) usize {
    out[0] = bridgeControl(layout.seed, -315, 0.22);
    out[1] = bridgeControl(layout.seed, 315, 0.22);

    var hall: ?District.Building = null;
    var best = std.math.inf(f32);
    const plaza = layout.nodes[4].position;
    for (layout.buildings[0..layout.building_count]) |building| {
        if (building.architecture != .gothic) continue;
        const dx = building.base[0] - plaza[0];
        const dz = building.base[2] - plaza[2];
        const distance = dx * dx + dz * dz;
        if (distance < best) {
            best = distance;
            hall = building;
        }
    }
    if (hall) |building| {
        const x = building.base[0] + building.half[0] + 3.5;
        const z = building.base[2];
        out[2] = .{ x, Terrain.surface(layout.seed, x, z).height + 1.05, z };
    } else {
        const x = plaza[0] + District.plaza_radius + 5;
        const z = plaza[2];
        out[2] = .{ x, Terrain.surface(layout.seed, x, z).height + 1.05, z };
    }
    return checkpoint_count;
}

/// Closed crossing barrier center at the Detroit-side approach of each international bridge.
pub fn gatePosition(seed: u64, index: usize) ?V {
    const x: f32 = switch (index) {
        0 => -315,
        1 => 315,
        else => return null,
    };
    const at = bridgeControl(seed, x, 0.07);
    return .{ at[0], at[1] - 1.1, at[2] };
}

/// Safe fast-travel approach on the Detroit bank, clear of the closed barrier.
pub fn travelPoint(seed: u64, index: usize) ?V {
    const x: f32 = switch (index) {
        0 => -315,
        1 => 315,
        else => return null,
    };
    const center = Hydrology.centerZ(seed, 0, x);
    const bank = center - Hydrology.surfaceHalfWidth(0, x) - 12;
    return .{ x, Terrain.surface(seed, x, bank).height + 0.1, bank };
}

fn bridgeControl(seed: u64, x: f32, t: f32) V {
    const center = Hydrology.centerZ(seed, 0, x);
    const half = Hydrology.surfaceHalfWidth(0, x) + 9;
    const start_z = center - half;
    const end_z = center + half;
    const start_y = Terrain.surface(seed, x, start_z).height + 0.8;
    const end_y = Terrain.surface(seed, x, end_z).height + 0.8;
    const desired_clearance: f32 = 7;
    const rise = @max(Hydrology.level(seed, 0, x) + desired_clearance - (start_y + end_y) * 0.5, 0);
    const deck = start_y * (1 - t) + end_y * t + rise * 4 * t * (1 - t);
    return .{ x, deck + 1.1, start_z + (end_z - start_z) * t };
}

pub fn collected(progress: *const Progress, index: usize) bool {
    return index < checkpoint_count and progress.hasFlag(checkpoint_flags[index]);
}

pub fn count(progress: *const Progress) u8 {
    var found: u8 = 0;
    for (0..checkpoint_count) |index| found += @intFromBool(collected(progress, index));
    return found;
}

pub fn next(progress: *const Progress) ?usize {
    for (0..checkpoint_count) |index| if (!collected(progress, index)) return index;
    return null;
}

/// A clue can only be filed for an active investigation; repeated interaction is harmless.
pub fn collect(progress: *Progress, index: usize) bool {
    if (index >= checkpoint_count or !progress.hasFlag(started_flag) or progress.hasFlag(exposed_flag) or collected(progress, index)) return false;
    progress.setFlag(checkpoint_flags[index]);
    if (count(progress) == checkpoint_count) progress.setFlag(complete_flag);
    return true;
}

/// Ines can expose the councillor only after both gate logs and the hall recording are shared.
pub fn expose(progress: *Progress) bool {
    if (!progress.hasFlag(started_flag) or !progress.hasFlag(complete_flag) or progress.hasFlag(exposed_flag)) return false;
    progress.setFlag(exposed_flag);
    return true;
}

test "Windsor evidence requires its case, records each checkpoint once, and exposes the councillor in order" {
    var progress: Progress = .{};
    try std.testing.expect(!collect(&progress, 0));
    progress.setFlag(started_flag);
    try std.testing.expect(!collect(&progress, checkpoint_count));
    try std.testing.expect(collect(&progress, 1));
    try std.testing.expect(!collected(&progress, 0));
    try std.testing.expectEqual(@as(u8, 1), count(&progress));
    try std.testing.expect(collect(&progress, 0));
    try std.testing.expect(collect(&progress, 2));
    try std.testing.expect(progress.hasFlag(complete_flag));
    try std.testing.expect(!collect(&progress, 2));
    try std.testing.expect(expose(&progress));
    try std.testing.expect(progress.hasFlag(exposed_flag));
    try std.testing.expect(!expose(&progress));
}

test "Windsor gate logs align with both river crossings and the hall record has a stable public position" {
    const first = District.generate(0x57494e44534f52) catch return error.TestUnexpectedResult;
    const second = District.generate(0x57494e44534f52) catch return error.TestUnexpectedResult;
    var a: [checkpoint_count]V = undefined;
    var b: [checkpoint_count]V = undefined;
    try std.testing.expectEqual(@as(usize, checkpoint_count), positions(&first, &a));
    _ = positions(&second, &b);
    try std.testing.expectEqualDeep(a, b);
    try std.testing.expect(a[0][0] < 0 and a[1][0] > 0);
    try std.testing.expect(@abs(a[0][2] - Hydrology.centerZ(first.seed, 0, a[0][0])) < 300);
    try std.testing.expect(@abs(a[1][2] - Hydrology.centerZ(first.seed, 0, a[1][0])) < 300);
    try std.testing.expect(a[2][1] > Terrain.surface(first.seed, a[2][0], a[2][2]).height);
}
