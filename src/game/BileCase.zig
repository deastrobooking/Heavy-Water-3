//! Belle Isle archive traces and a small code lock whose deterministic sequence is drawn from
//! the same verified Shrine puzzle generator used by Detroit's Rootdeep vaults.
const std = @import("std");
const Hydrology = @import("../procedural/Hydrology.zig");
const Seed = @import("../procedural/Seed.zig");
const Shrine = @import("../procedural/Shrine.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Progress = @import("Progress.zig");
const V = @import("../physics/Rotation.zig").Vec3;

pub const trace_count = 3;
pub const relay_count = 3;
pub const started_flag = "bile_started";
pub const traces_complete_flag = "bile_traces_complete";
pub const vault_open_flag = "bile_vault_open";
pub const notes_read_flag = "bile_notes_read";
pub const exposed_flag = "bile_exposed";
const trace_flags = [_][]const u8{ "bile_trace_0", "bile_trace_1", "bile_trace_2" };

pub const RelayResult = enum { unavailable, wrong, progress, opened };

/// The institute's deterministic Belle Isle route: three traces around the lab, three relays,
/// and Dr. Bile's notes inside the opened archive.
pub fn tracePositions(seed: u64, out: *[trace_count]V) usize {
    const center = Hydrology.centerZ(seed, 0, 0);
    const xs = [_]f32{ -100, 0, 100 };
    const zs = [_]f32{ -28, 31, -22 };
    for (xs, zs, out) |x, dz, *point| point.* = .{ x, Terrain.surface(seed, x, center + dz).height + 1.05, center + dz };
    return trace_count;
}

/// A compact symbol selected from a real action in a generated, solvable Rootdeep plan.
pub fn sequence(seed: u64) [relay_count]u8 {
    const generated = Shrine.generate(Seed.mix(seed ^ 0x42494c4541524348));
    var result: [relay_count]u8 = undefined;
    for (0..relay_count) |i| result[i] = actionSymbol(generated.plan.slice()[i]);
    return result;
}

fn actionSymbol(action: Shrine.Action) u8 {
    return switch (action) {
        .press => |i| i % relay_count,
        .pick => |i| (i + 1) % relay_count,
        .drop_floor => 2,
        .drop_plate => |i| (i + 2) % relay_count,
        .move => |room| room % relay_count,
        .vault => unreachable,
    };
}

pub fn relayPosition(seed: u64, index: usize) ?V {
    if (index >= relay_count) return null;
    const center = Hydrology.centerZ(seed, 0, 0);
    const x = 139 + @as(f32, @floatFromInt(index)) * 3.2;
    const z = center + 2;
    return .{ x, Terrain.surface(seed, x, z).height + 1.45, z };
}

pub fn notesPosition(seed: u64) V {
    const x: f32 = 155;
    const z = Hydrology.centerZ(seed, 0, 0) + 14;
    return .{ x, Terrain.surface(seed, x, z).height + 1.05, z };
}

pub fn institutePosition(seed: u64) V {
    const x: f32 = 155;
    const z = Hydrology.centerZ(seed, 0, 0) + 14;
    return .{ x, Terrain.surface(seed, x, z).height, z };
}

pub fn collected(progress: *const Progress, index: usize) bool {
    return index < trace_count and progress.hasFlag(trace_flags[index]);
}

pub fn traceCount(progress: *const Progress) u8 {
    var count: u8 = 0;
    for (0..trace_count) |index| count += @intFromBool(collected(progress, index));
    return count;
}

pub fn nextTrace(progress: *const Progress) ?usize {
    for (0..trace_count) |index| if (!collected(progress, index)) return index;
    return null;
}

pub fn collectTrace(progress: *Progress, index: usize) bool {
    if (index >= trace_count or !progress.hasFlag(started_flag) or progress.hasFlag(exposed_flag) or collected(progress, index)) return false;
    progress.setFlag(trace_flags[index]);
    if (traceCount(progress) == trace_count) progress.setFlag(traces_complete_flag);
    return true;
}

/// Advances one physical relay interaction, restarting at the first symbol after a wrong input.
/// The partial sequence is transient; the opened-vault flag is shared and saved in Progress.
pub fn pressRelay(progress: *Progress, answer: [relay_count]u8, step: *u8, relay: usize) RelayResult {
    if (relay >= relay_count or !progress.hasFlag(traces_complete_flag) or progress.hasFlag(vault_open_flag) or progress.hasFlag(exposed_flag)) return .unavailable;
    if (step.* >= relay_count) step.* = 0;
    if (relay != answer[step.*]) {
        step.* = if (relay == answer[0]) 1 else 0;
        return .wrong;
    }
    step.* += 1;
    if (step.* == relay_count) {
        progress.setFlag(vault_open_flag);
        step.* = 0;
        return .opened;
    }
    return .progress;
}

pub fn readNotes(progress: *Progress) bool {
    if (!progress.hasFlag(vault_open_flag) or progress.hasFlag(notes_read_flag)) return false;
    progress.setFlag(notes_read_flag);
    return true;
}

pub fn expose(progress: *Progress) bool {
    if (!progress.hasFlag(notes_read_flag) or progress.hasFlag(exposed_flag)) return false;
    progress.setFlag(exposed_flag);
    return true;
}

test "Bile Archive trace collection, Shrine-seeded lock, notes, and exposure follow the mission order" {
    const seed = 0x42494c4543415345;
    const answer = sequence(seed);
    var progress: Progress = .{};
    var step: u8 = 0;
    try std.testing.expect(!collectTrace(&progress, 0));
    try std.testing.expectEqual(RelayResult.unavailable, pressRelay(&progress, answer, &step, 0));
    progress.setFlag(started_flag);
    try std.testing.expect(collectTrace(&progress, 2));
    try std.testing.expect(!collectTrace(&progress, 2));
    try std.testing.expect(collectTrace(&progress, 0));
    try std.testing.expect(collectTrace(&progress, 1));
    try std.testing.expect(progress.hasFlag(traces_complete_flag));

    const generated = Shrine.generate(Seed.mix(seed ^ 0x42494c4541524348));
    try std.testing.expect(generated.plan.len >= relay_count + 1);
    try std.testing.expectEqual(answer, sequence(seed));
    for (answer) |symbol| try std.testing.expect(symbol < relay_count);
    try std.testing.expectEqual(RelayResult.wrong, pressRelay(&progress, answer, &step, (answer[0] + 1) % relay_count));
    for (answer, 0..) |relay, index| {
        const result = pressRelay(&progress, answer, &step, relay);
        try std.testing.expectEqual(if (index + 1 == relay_count) RelayResult.opened else RelayResult.progress, result);
    }
    try std.testing.expect(progress.hasFlag(vault_open_flag));
    try std.testing.expect(readNotes(&progress));
    try std.testing.expect(!readNotes(&progress));
    try std.testing.expect(expose(&progress));
    try std.testing.expect(!expose(&progress));
}

test "Belle Isle traces, relays, and notes are deterministic and grounded on the island" {
    const seed = 0x42494c4543415345;
    var a: [trace_count]V = undefined;
    var b: [trace_count]V = undefined;
    _ = tracePositions(seed, &a);
    _ = tracePositions(seed, &b);
    try std.testing.expectEqualDeep(a, b);
    const center = Hydrology.centerZ(seed, 0, 0);
    for (a) |point| {
        try std.testing.expect(@abs(point[1] - Terrain.surface(seed, point[0], point[2]).height) > 0.5);
        try std.testing.expect(Hydrology.belleIsleHalfWidth(point[0]) > @abs(point[2] - center));
    }
    for (0..relay_count) |i| try std.testing.expect(relayPosition(seed, i) != null);
    try std.testing.expect(relayPosition(seed, relay_count) == null);
    const notes = notesPosition(seed);
    try std.testing.expect(Hydrology.belleIsleHalfWidth(notes[0]) > @abs(notes[2] - center));
}
