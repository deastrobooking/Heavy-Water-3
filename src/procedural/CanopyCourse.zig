//! Reusable vertical parkour modules around the canopy market towers. These are static city
//! pieces, so the same geometry supports running, climbing, jumping, and the player's grapple.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const V = R.Vec3;

pub const Site = struct { plaza: V, ground: f32, outward: V };
pub const Piece = struct { center: V, size: V, rotation: R.Quat = R.identity, color: V, solid: bool = true };
pub const max_pieces = 384;
pub const Palette = struct {
    deck: V = .{ 0.39, 0.31, 0.22 },
    rail: V = .{ 0.20, 0.31, 0.24 },
    ladder: V = .{ 0.54, 0.43, 0.29 },
    anchor: V = .{ 0.12, 0.72, 0.76 },
};

pub fn generate(sites: []const Site, out: []Piece) usize {
    var count: usize = 0;
    for (sites) |site| {
        if (out.len - count < 120) break;
        const radial = R.normalize(.{ site.outward[0], 0, site.outward[2] });
        const lateral: V = .{ -radial[2], 0, radial[0] };
        const start = R.add(site.plaza, R.scale(radial, 31));
        const low_y = site.plaza[1] + 4;
        const high_y = site.plaza[1] + 12;
        const top_y = site.plaza[1] + 21;
        const low: V = .{ start[0], low_y, start[2] };
        var mid = R.add(low, R.add(R.scale(radial, 12), R.scale(lateral, 2)));
        mid[1] = high_y;
        const far = R.add(mid, R.add(R.scale(radial, 14), R.scale(lateral, 8)));
        var top = far;
        top[1] = top_y;
        const jump = R.add(top, R.add(R.scale(radial, 8), R.scale(lateral, 2)));

        // A ground-to-patio ladder gives the high route a visible, climbable start.
        const ladder_height = @max(5, low_y - site.ground);
        const ladder_center = R.add(start, .{ 0, site.ground + ladder_height / 2, 0 });
        const across = acrossRotation(lateral);
        put(out, &count, .{ .center = R.add(ladder_center, R.scale(lateral, -0.72)), .size = .{ 0.14, ladder_height, 0.14 }, .rotation = across, .color = Palette{}.ladder });
        put(out, &count, .{ .center = R.add(ladder_center, R.scale(lateral, 0.72)), .size = .{ 0.14, ladder_height, 0.14 }, .rotation = across, .color = Palette{}.ladder });
        var rung_y = site.ground + 0.7;
        while (rung_y < low_y - 0.4) : (rung_y += 1.15) {
            const rung: V = .{ start[0], rung_y, start[2] };
            put(out, &count, .{ .center = rung, .size = .{ 1.5, 0.11, 0.12 }, .rotation = across, .color = Palette{}.ladder });
        }

        patio(out, &count, low, radial, 8, Palette{}.deck);
        ramp(out, &count, low, mid, 4, Palette{}.deck);
        patio(out, &count, mid, radial, 7, Palette{}.deck);
        miniBridge(out, &count, mid, far, 2.6, Palette{}.deck, Palette{}.rail);
        patio(out, &count, far, radial, 7, Palette{}.deck);
        ladder(out, &count, far, top, lateral, Palette{}.ladder);
        patio(out, &count, top, radial, 6, Palette{}.deck);
        // A deliberate three-meter jump gap returns the route to a second landing.
        patio(out, &count, jump, radial, 5, Palette{}.deck);
        anchor(out, &count, low, Palette{}.anchor);
        anchor(out, &count, mid, Palette{}.anchor);
        anchor(out, &count, top, Palette{}.anchor);
    }
    return count;
}

fn put(out: []Piece, count: *usize, piece: Piece) void {
    if (count.* < out.len) {
        out[count.*] = piece;
        count.* += 1;
    }
}

fn patio(out: []Piece, count: *usize, center: V, radial: V, width: f32, color: V) void {
    const yaw = R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(radial[0], radial[2]));
    put(out, count, .{ .center = center, .size = .{ width, 0.5, width }, .rotation = yaw, .color = color });
    const edge = width * 0.48;
    for ([_]f32{ -edge, edge }) |side| {
        const along = R.add(center, R.scale(radial, side));
        put(out, count, .{ .center = R.add(along, .{ 0, 0.62, 0 }), .size = .{ width, 0.24, 0.18 }, .rotation = yaw, .color = Palette{}.rail });
    }
}

fn ramp(out: []Piece, count: *usize, a: V, b: V, width: f32, color: V) void {
    const delta = R.sub(b, a);
    const horizontal = @sqrt(delta[0] * delta[0] + delta[2] * delta[2]);
    const yaw = std.math.atan2(delta[0], delta[2]);
    const pitch = -std.math.atan2(delta[1], horizontal);
    const rotation = R.mul(R.axisAngle(.{ 0, 1, 0 }, yaw), R.axisAngle(.{ 1, 0, 0 }, pitch));
    put(out, count, .{ .center = R.scale(R.add(a, b), 0.5), .size = .{ width, 0.42, R.length(delta) + 0.5 }, .rotation = rotation, .color = color });
}

fn miniBridge(out: []Piece, count: *usize, a: V, b: V, width: f32, deck: V, rail: V) void {
    ramp(out, count, a, b, width, deck);
    const delta = R.sub(b, a);
    const horizontal = @sqrt(delta[0] * delta[0] + delta[2] * delta[2]);
    const yaw = std.math.atan2(delta[0], delta[2]);
    const pitch = -std.math.atan2(delta[1], horizontal);
    const rotation = R.mul(R.axisAngle(.{ 0, 1, 0 }, yaw), R.axisAngle(.{ 1, 0, 0 }, pitch));
    for ([_]f32{ -width * 0.42, width * 0.42 }) |side| {
        const offset = R.rotate(rotation, .{ side, 0.5, 0 });
        put(out, count, .{ .center = R.add(R.scale(R.add(a, b), 0.5), offset), .size = .{ 0.16, 0.75, R.length(delta) }, .rotation = rotation, .color = rail });
    }
}

fn ladder(out: []Piece, count: *usize, a: V, b: V, across: V, color: V) void {
    const delta = R.sub(b, a);
    const height = @abs(delta[1]);
    const center = R.scale(R.add(a, b), 0.5);
    const yaw = acrossRotation(across);
    for ([_]f32{ -0.64, 0.64 }) |side| {
        put(out, count, .{ .center = R.add(center, R.scale(across, side)), .size = .{ 0.13, height, 0.13 }, .rotation = yaw, .color = color });
    }
    var y = @min(a[1], b[1]) + 0.8;
    while (y < @max(a[1], b[1]) - 0.4) : (y += 1.15) {
        const rung: V = .{ center[0], y, center[2] };
        put(out, count, .{ .center = rung, .size = .{ 1.35, 0.1, 0.12 }, .rotation = yaw, .color = color });
    }
}

fn acrossRotation(across: V) R.Quat {
    // A box's long axis is local X; rotate it to the ladder's horizontal crossbar direction.
    return R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(-across[2], across[0]));
}

fn anchor(out: []Piece, count: *usize, patio_center: V, color: V) void {
    const base = R.add(patio_center, .{ 0, 2, 0 });
    put(out, count, .{ .center = base, .size = .{ 0.22, 4, 0.22 }, .color = color });
    put(out, count, .{ .center = R.add(base, .{ 0, 1.75, 0 }), .size = .{ 1.8, 0.2, 0.2 }, .color = color });
}
