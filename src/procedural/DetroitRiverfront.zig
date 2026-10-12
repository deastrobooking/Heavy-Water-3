//! Detroit's broad river corridor, Belle Isle park, industrial waterfront, and Windsor crossings.
//! Everything is generated from the same river centre and water level as streamed terrain.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const Terrain = @import("Terrain.zig");
const Hydrology = @import("Hydrology.zig");
const V = R.Vec3;

const steel: V = .{ 0.20, 0.25, 0.29 };
const copper: V = .{ 0.74, 0.34, 0.17 };
const concrete: V = .{ 0.40, 0.43, 0.40 };
const lumen: V = .{ 0.22, 0.73, 0.72 };
const park: V = .{ 0.22, 0.37, 0.24 };

fn add(out: anytype, center: V, size: V, rotation: R.Quat, color: V, solid: bool) !void {
    try out.add(.{ .center = center, .size = size, .rotation = rotation, .color = color, .solid = solid });
}

fn box(out: anytype, center: V, size: V, color: V, solid: bool) !void {
    try add(out, center, size, R.identity, color, solid);
}

fn beam(out: anytype, a: V, b: V, width: f32, color: V, solid: bool) !void {
    const d = R.sub(b, a);
    const horizontal = @sqrt(d[0] * d[0] + d[2] * d[2]);
    const length = R.length(d);
    const rotation = R.mul(R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(d[0], d[2])), R.axisAngle(.{ 1, 0, 0 }, -std.math.atan2(d[1], horizontal)));
    try add(out, R.scale(R.add(a, b), 0.5), .{ width, width, length }, rotation, color, solid);
}

const BridgeKind = enum { road, grand_road, park_walk };

fn bridgeY(start_y: f32, end_y: f32, rise: f32, t: f32) f32 {
    return start_y * (1 - t) + end_y * t + rise * 4 * t * (1 - t);
}

fn bridge(out: anytype, seed: u64, x: f32, from_z: f32, to_z: f32, kind: BridgeKind) !void {
    const from = if (from_z < to_z) from_z else to_z;
    const to = if (from_z < to_z) to_z else from_z;
    const start_y = Terrain.surface(seed, x, from).height + 0.8;
    const end_y = Terrain.surface(seed, x, to).height + 0.8;
    const grand = kind == .grand_road;
    const walkway = kind == .park_walk;
    const width: f32 = if (grand) 24 else if (walkway) 8 else 18;
    const desired_clearance: f32 = if (walkway) 3 else 7;
    const rise = @max(Hydrology.level(seed, 0, x) + desired_clearance - (start_y + end_y) * 0.5, 0);
    const length = to - from;
    const segments: usize = @intFromFloat(@max(1, @ceil(length / 16)));
    const yaw: f32 = 0;
    // Segmented arch decks meet ground-level approaches at both banks and rise over the channel.
    for (0..segments) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segments));
        const y0 = bridgeY(start_y, end_y, rise, t0);
        const y1 = bridgeY(start_y, end_y, rise, t1);
        const a: V = .{ x, y0, from + length * t0 };
        const b: V = .{ x, y1, from + length * t1 };
        const d = R.sub(b, a);
        const horizontal = R.length(.{ d[0], 0, d[2] });
        const rotation = R.mul(R.axisAngle(.{ 0, 1, 0 }, yaw), R.axisAngle(.{ 1, 0, 0 }, -std.math.atan2(d[1], horizontal)));
        const middle = R.scale(R.add(a, b), 0.5);
        const segment_length = R.length(d);
        try add(out, R.add(middle, .{ 0, -0.45, 0 }), .{ width, 0.9, segment_length + 0.25 }, rotation, steel, true);
        for ([_]f32{ -width * 0.5 + 0.5, width * 0.5 - 0.5 }) |side| {
            const lateral = R.rotate(R.axisAngle(.{ 0, 1, 0 }, yaw), .{ side, 0, 0 });
            try add(out, R.add(middle, R.add(.{ 0, 1.2, 0 }, lateral)), .{ 0.55, 1.7, segment_length + 0.25 }, rotation, copper, true);
        }
        if (i % 2 == 0) for ([_]f32{ -width * 0.43, width * 0.43 }) |side| {
            const lateral = R.rotate(R.axisAngle(.{ 0, 1, 0 }, yaw), .{ side, 0, 0 });
            try box(out, R.add(b, R.add(lateral, .{ 0, 2.2, 0 })), .{ 0.65, 0.45, 0.65 }, lumen, false);
        };
        // Deep piers carry the deck while leaving the water channel open between them.
        if (i % 3 == 1 and !walkway) for ([_]f32{ -width * 0.38, width * 0.38 }) |side| {
            const lateral = R.rotate(R.axisAngle(.{ 0, 1, 0 }, yaw), .{ side, 0, 0 });
            const foot: V = .{ x + lateral[0], Terrain.surface(seed, x + lateral[0], middle[2] + lateral[2]).height - 1.5, middle[2] + lateral[2] };
            try beam(out, foot, R.add(middle, R.add(lateral, .{ 0, -0.8, 0 })), 1.35, concrete, true);
        };
    }
    if (grand) {
        // Twin illuminated cable towers mark the international crossing at long range.
        for ([_]f32{ 0.22, 0.78 }) |t| {
            const p: V = .{ x, bridgeY(start_y, end_y, rise, t), from + length * t };
            for ([_]f32{ -width * 0.42, width * 0.42 }) |side| {
                const foot = R.add(p, R.rotate(R.axisAngle(.{ 0, 1, 0 }, yaw), .{ side, 0, 0 }));
                const top = R.add(foot, .{ 0, 34, 0 });
                try beam(out, foot, top, 2.4, copper, true);
                try box(out, R.add(top, .{ 0, 1.7, 0 }), .{ 3.5, 3.5, 3.5 }, lumen, false);
            }
        }
    }
}

fn promenade(out: anytype, seed: u64, z_offset: f32) !void {
    for (0..10) |i| {
        const x = -225 + @as(f32, @floatFromInt(i)) * 50;
        const center = Hydrology.centerZ(seed, 0, x);
        const z = center + z_offset;
        const ground = Terrain.surface(seed, x, z).height;
        try box(out, .{ x, ground + 0.45, z }, .{ 54, 0.9, 13 }, concrete, true);
        for ([_]f32{ -21, 21 }) |side| try box(out, .{ x + side, ground + 1.1, z }, .{ 2, 1.7, 1.3 }, lumen, false);
    }
    // A surviving freight gantry and ferry pavilion anchor the industrial riverfront.
    const gx: f32 = 78;
    const gz = Hydrology.centerZ(seed, 0, gx) + z_offset - 13;
    const gy = Terrain.surface(seed, gx, gz).height;
    for ([_]f32{ -18, 18 }) |dx| try box(out, .{ gx + dx, gy + 12, gz }, .{ 2.2, 24, 2.2 }, steel, true);
    try beam(out, .{ gx - 21, gy + 24, gz }, .{ gx + 21, gy + 24, gz }, 2, copper, true);
    try beam(out, .{ gx + 15, gy + 23, gz }, .{ gx + 15, gy + 4, gz }, 0.8, lumen, false);
    const px: f32 = -118;
    const pz = Hydrology.centerZ(seed, 0, px) + z_offset + 11;
    const py = Terrain.surface(seed, px, pz).height;
    try box(out, .{ px, py + 4.4, pz }, .{ 32, 8.8, 20 }, .{ 0.29, 0.36, 0.36 }, true);
    try box(out, .{ px, py + 9, pz }, .{ 38, 1.1, 25 }, copper, false);
    try box(out, .{ px, py + 4.7, pz + 10.3 }, .{ 21, 5.3, 0.45 }, lumen, false);
}

fn belleIsle(out: anytype, seed: u64) !void {
    const cx: f32 = 0;
    const cz = Hydrology.centerZ(seed, 0, cx);
    // Curving park paths follow the dry, seeded island ground and leave its centre open.
    for (0..12) |i| {
        const angle = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 12;
        const r0: f32 = 0.43;
        const r1: f32 = 0.87;
        const a: V = .{ @cos(angle) * 245 * r0, 0, cz + @sin(angle) * 68 * r0 };
        const b: V = .{ @cos(angle) * 245 * r1, 0, cz + @sin(angle) * 68 * r1 };
        const ga = Terrain.surface(seed, a[0], a[2]).height;
        const gb = Terrain.surface(seed, b[0], b[2]).height;
        try beam(out, .{ a[0], ga + 0.3, a[2] }, .{ b[0], gb + 0.3, b[2] }, 3.2, park, false);
    }
    for (0..6) |i| {
        const angle = @as(f32, @floatFromInt(i)) * std.math.pi / 3 + 0.3;
        const x = @cos(angle) * 125;
        const z = cz + @sin(angle) * 34;
        const y = Terrain.surface(seed, x, z).height;
        try box(out, .{ x, y + 0.65, z }, .{ 5.5, 1.3, 1.2 }, copper, false);
        try box(out, .{ x, y + 5, z }, .{ 0.55, 8, 0.55 }, lumen, false);
    }
}

/// Adds the Detroit promenade, Belle Isle approaches, and two road bridges toward Windsor.
pub fn geometry(seed: u64, out: anytype) !void {
    // Riverfront promenades occupy the Detroit/north bank and the Windsor/south bank.
    try promenade(out, seed, -Hydrology.surfaceHalfWidth(0, 0) - 30);
    try promenade(out, seed, Hydrology.surfaceHalfWidth(0, 0) + 30);
    try belleIsle(out, seed);

    // Both international bridges are independently drivable; the eastern one is taller and
    // broader, with illuminated cable towers. Belle Isle has a separate pedestrian crossing.
    for ([_]f32{ -315, 315 }) |x| {
        const center = Hydrology.centerZ(seed, 0, x);
        const half = Hydrology.surfaceHalfWidth(0, x) + 9;
        try bridge(out, seed, x, center - half, center + half, if (x > 0) .grand_road else .road);
    }

    const center = Hydrology.centerZ(seed, 0, 0);
    const half = Hydrology.surfaceHalfWidth(0, 0);
    const island = Hydrology.belleIsleHalfWidth(0);
    try bridge(out, seed, 0, center - half - 9, center - island, .park_walk);
    try bridge(out, seed, 0, center + island, center + half + 9, .park_walk);
}
