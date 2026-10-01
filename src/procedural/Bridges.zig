//! Bridge superstructures for the sky city: what holds each 14 m road deck up. Every style
//! keeps the same deck (two lanes, two walkways, rails) and keeps everything solid outside the
//! clear envelope above it, so traffic, pedestrians, and players use any bridge the same way.
//!
//! - suspension: twin steel towers from the forest floor, parabolic main cables, hangers.
//! - cable_stayed: one H pylon with fanned stay cables, on braced end piers.
//! - arch: a tied steel arch rising over the deck, with hangers and top struts.
//! - truss: Warren truss side walls with overhead lateral bracing, on braced piers.
//! - girder: a deep box girder on braced steel pole piers.
//! - vine: the original organic cable decoration (trunk spurs).
//!
//! Piers and towers stand on the terrain under the span, never inside a plaza or near a trunk.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const Terrain = @import("Terrain.zig");
const District = @import("District.zig");
const V = R.Vec3;

pub const Style = District.Style;
/// Nothing solid may enter this box above the deck: |x| ≤ clear_half_width, 0 < y ≤ clear_height.
pub const clear_half_width: f32 = 6.5;
pub const clear_height: f32 = 6;

const steel: V = .{ 0.38, 0.42, 0.48 };
const dark_steel: V = .{ 0.24, 0.28, 0.33 };
const cable: V = .{ 0.78, 0.80, 0.82 };
const concrete: V = .{ 0.52, 0.53, 0.50 };
const vine: V = .{ 0.24, 0.46, 0.29 };
const palette = struct {
    const suspension: V = .{ 0.74, 0.30, 0.20 };
    const cable_stayed: V = .{ 0.86, 0.88, 0.86 };
    const arch: V = .{ 0.30, 0.56, 0.52 };
    const truss: V = .{ 0.28, 0.34, 0.44 };
    const girder: V = .{ 0.42, 0.46, 0.50 };
};

/// The span's local frame: `t` along the road (0..1), `x` to the right, `y` up from the deck.
const Frame = struct {
    layout: *const District.Layout,
    s: District.Span,
    yaw: R.Quat,
    right: V,
    length: f32,

    fn init(layout: *const District.Layout, s: District.Span) Frame {
        const d = R.sub(s.b, s.a);
        const yaw = R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(d[0], d[2]));
        return .{ .layout = layout, .s = s, .yaw = yaw, .right = R.rotate(yaw, .{ 1, 0, 0 }), .length = s.horizontal() };
    }
    fn at(f: Frame, t: f32, x: f32, y: f32) V {
        return R.add(R.add(f.s.point(t), R.scale(f.right, x)), .{ 0, y, 0 });
    }
    fn ground(f: Frame, p: V) f32 {
        return Terrain.surface(f.layout.seed, p[0], p[2]).height;
    }
    /// Whether a ground support at `t` stays clear of plazas and trunks.
    fn supportAllowed(f: Frame, t: f32) bool {
        const p = f.at(t, 0, 0);
        for (f.layout.nodes) |node| if (planar(p, node.position) < District.plaza_radius + 6) return false;
        for (f.layout.trees, 0..) |tree, i| if (planar(p, tree.position) < tree.radius + (if (i == 0) @as(f32, 45) else 18)) return false;
        return true;
    }
};

fn planar(a: V, b: V) f32 {
    return @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2]));
}

fn add(out: anytype, piece: District.Piece) !void {
    try out.add(piece);
}

/// A vertical post (yawed with the road) from `y0` to `y1` at `base`.
fn post(out: anytype, f: Frame, base: V, y0: f32, y1: f32, side: f32, color: V, solid: bool) !void {
    if (y1 <= y0) return;
    try add(out, .{ .center = .{ base[0], (y0 + y1) / 2, base[2] }, .size = .{ side, y1 - y0, side }, .rotation = f.yaw, .color = color, .solid = solid });
}

pub fn beam(out: anytype, a: V, b: V, thickness: f32, color: V, solid: bool) !void {
    const s: District.Span = .{ .a = a, .b = b };
    if (s.length() < 0.01) return;
    try add(out, .{ .center = s.point(0.5), .size = .{ thickness, thickness, s.length() }, .rotation = beamRotation(a, b), .color = color, .solid = solid });
}

/// Rotation taking local +Z to the direction a → b (also exactly vertical segments).
fn beamRotation(a: V, b: V) R.Quat {
    const d = R.sub(b, a);
    const horizontal = @sqrt(d[0] * d[0] + d[2] * d[2]);
    const yaw = if (horizontal < 1e-5) 0 else std.math.atan2(d[0], d[2]);
    return R.mul(R.axisAngle(.{ 0, 1, 0 }, yaw), R.axisAngle(.{ 1, 0, 0 }, -std.math.atan2(d[1], horizontal)));
}

/// A braced steel pole pier under the deck at `t`: twin columns, X-bracing, a cap beam, and
/// footings. `depth` is how far below the deck surface the pier meets the structure.
fn pier(out: anytype, f: Frame, t: f32, depth: f32, color: V) !void {
    if (!f.supportAllowed(t)) return;
    const top = f.at(t, 0, -depth)[1];
    var bases: [2]V = undefined;
    var low: f32 = top;
    for ([_]f32{ -5, 5 }, &bases) |x, *b| {
        b.* = f.at(t, x, 0);
        b.*[1] = f.ground(b.*) - 1;
        low = @min(low, b.*[1]);
        try post(out, f, b.*, b.*[1], top, 1.6, color, true);
        try add(out, .{ .center = .{ b.*[0], b.*[1] + 0.6, b.*[2] }, .size = .{ 3.4, 1.4, 3.4 }, .rotation = f.yaw, .color = concrete, .solid = true });
    }
    try beam(out, f.at(t, -6.2, -depth - 0.6), f.at(t, 6.2, -depth - 0.6), 1.3, color, true);
    if (top - low < 8) return;
    // X-bracing in two stories for tall piers.
    const levels: usize = if (top - low > 30) 2 else 1;
    for (0..levels) |k| {
        const y0 = low + 2 + (top - low - 3) * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(levels));
        const y1 = low + 2 + (top - low - 3) * @as(f32, @floatFromInt(k + 1)) / @as(f32, @floatFromInt(levels));
        const l0: V = .{ bases[0][0], y0, bases[0][2] };
        const r0: V = .{ bases[1][0], y0, bases[1][2] };
        const l1: V = .{ bases[0][0], y1, bases[0][2] };
        const r1: V = .{ bases[1][0], y1, bases[1][2] };
        try beam(out, l0, r1, 0.5, color, true);
        try beam(out, r0, l1, 0.5, color, true);
    }
}

/// Piers spaced about `spacing` apart between `t0` and `t1`.
fn piers(out: anytype, f: Frame, spacing: f32, t0: f32, t1: f32, depth: f32, color: V) !void {
    const n: usize = @intFromFloat(@max(1, @round((t1 - t0) * f.length / spacing)));
    for (0..n) |k| try pier(out, f, t0 + (t1 - t0) * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(n)), depth, color);
}

fn girderBox(out: anytype, f: Frame, depth: f32, color: V) !void {
    try add(out, .{ .center = R.add(f.s.point(0.5), R.rotate(f.s.rotation(), .{ 0, -0.8 - depth / 2, 0 })), .size = .{ District.width - 3, depth, f.s.length() }, .rotation = f.s.rotation(), .color = color, .solid = true });
}

fn girder(out: anytype, f: Frame) !void {
    try girderBox(out, f, 2.6, palette.girder);
    try piers(out, f, 48, 0.08, 0.92, 3.4, palette.girder);
}

fn truss(out: anytype, f: Frame) !void {
    const n: usize = @intFromFloat(std.math.clamp(@round(f.length / 12), 6, 28));
    const h: f32 = 8;
    for ([_]f32{ -7.4, 7.4 }) |x| {
        try beam(out, f.at(0, x, h), f.at(1, x, h), 0.7, palette.truss, true);
        try beam(out, f.at(0, x, 0.3), f.at(1, x, 0.3), 0.5, palette.truss, true);
        for (0..n + 1) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            try beam(out, f.at(t, x, 0.3), f.at(t, x, h), 0.4, palette.truss, true);
            if (i == n) continue;
            const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(n));
            if (i % 2 == 0) try beam(out, f.at(t, x, 0.3), f.at(t1, x, h), 0.3, palette.truss, true) else try beam(out, f.at(t, x, h), f.at(t1, x, 0.3), 0.3, palette.truss, true);
        }
    }
    // Overhead lateral bracing, well above the clear envelope.
    var i: usize = 0;
    while (i <= n) : (i += 2) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        try beam(out, f.at(t, -7.4, h), f.at(t, 7.4, h), 0.45, palette.truss, true);
    }
    try girderBox(out, f, 1.6, dark_steel);
    try piers(out, f, 60, 0.08, 0.92, 2.4, palette.truss);
}

fn arch(out: anytype, f: Frame) !void {
    const rise = std.math.clamp(0.14 * f.length, 16, 42);
    const segments = 20;
    const t0: f32 = 0.05;
    const t1: f32 = 0.95;
    for ([_]f32{ -7.9, 7.9 }) |x| {
        var previous = f.at(t0, x, 0);
        for (1..segments + 1) |k| {
            const u = @as(f32, @floatFromInt(k)) / segments;
            const p = f.at(t0 + (t1 - t0) * u, x, rise * 4 * u * (1 - u));
            try beam(out, previous, p, 1.3, palette.arch, true);
            previous = p;
        }
        // Hangers every ~8 m from the rib down to the deck edge.
        const hangers: usize = @intFromFloat(@round((t1 - t0) * f.length / 8));
        for (1..hangers) |k| {
            const u = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(hangers));
            const h = rise * 4 * u * (1 - u);
            if (h < 1.5) continue;
            const t = t0 + (t1 - t0) * u;
            try beam(out, f.at(t, x, 0.4), f.at(t, x, h), 0.14, cable, false);
        }
    }
    // Top struts between the ribs where they are high above the deck.
    for (2..segments - 1) |k| {
        if (k % 3 != 0) continue;
        const u = @as(f32, @floatFromInt(k)) / segments;
        const h = rise * 4 * u * (1 - u);
        if (h < clear_height + 4) continue;
        const t = t0 + (t1 - t0) * u;
        try beam(out, f.at(t, -7.9, h), f.at(t, 7.9, h), 0.6, palette.arch, true);
    }
    try girderBox(out, f, 1.8, dark_steel);
    // Abutment piers take the arch's feet.
    try pier(out, f, t0, 2.6, palette.arch);
    try pier(out, f, t1, 2.6, palette.arch);
}

fn cableStayed(out: anytype, f: Frame) !void {
    const h = std.math.clamp(0.16 * f.length, 30, 60);
    const base = f.at(0.5, 0, 0)[1];
    for ([_]f32{ -9.8, 9.8 }) |x| {
        var foot = f.at(0.5, x, 0);
        foot[1] = f.ground(foot) - 1;
        try post(out, f, foot, foot[1], base + h, 3.4, palette.cable_stayed, true);
        try add(out, .{ .center = .{ foot[0], foot[1] + 0.9, foot[2] }, .size = .{ 6, 2, 6 }, .rotation = f.yaw, .color = concrete, .solid = true });
    }
    for ([_]f32{ h - 1, h * 0.55, -3.2 }) |y| try beam(out, f.at(0.5, -11.5, y), f.at(0.5, 11.5, y), 2, palette.cable_stayed, true);
    // Fans of stays to both deck edges on both sides of the pylon.
    for ([_]f32{ -8.6, 8.6 }) |x| for ([_]f32{ -1, 1 }) |direction| for (1..11) |k| {
        const kf: f32 = @floatFromInt(k);
        const anchor = f.at(0.5, x, h - 2 - kf * 1.1);
        const deck_point = f.at(0.5 + direction * kf * 0.044, x, 0.4);
        try beam(out, anchor, deck_point, 0.18, cable, false);
    };
    try girderBox(out, f, 2.2, dark_steel);
    try pier(out, f, 0.1, 3, palette.cable_stayed);
    try pier(out, f, 0.9, 3, palette.cable_stayed);
}

fn suspension(out: anytype, f: Frame) !void {
    const h = std.math.clamp(0.13 * f.length, 30, 55);
    const towers = [_]f32{ 0.17, 0.83 };
    const sag: f32 = 2.5;
    for (towers) |t| {
        const deck_y = f.at(t, 0, 0)[1];
        for ([_]f32{ -9.5, 9.5 }) |x| {
            var foot = f.at(t, x, 0);
            foot[1] = f.ground(foot) - 1;
            try post(out, f, foot, foot[1], deck_y + h + 1, 2.6, palette.suspension, true);
            try add(out, .{ .center = .{ foot[0], foot[1] + 0.8, foot[2] }, .size = .{ 5, 1.8, 5 }, .rotation = f.yaw, .color = concrete, .solid = true });
        }
        for ([_]f32{ h - 1, h * 0.55, -3.4 }) |y| try beam(out, f.at(t, -10.8, y), f.at(t, 10.8, y), 1.8, palette.suspension, true);
    }
    // Main cable height above the deck at t: back spans rise straight from the anchorages to
    // the tower saddles; the main span sags to `sag` at midspan.
    const Cable = struct {
        fn y(t: f32, top: f32, low: f32, a: f32, b: f32) f32 {
            if (t <= a) return 1 + (top - 1) * t / a;
            if (t >= b) return 1 + (top - 1) * (1 - t) / (1 - b);
            const u = (t - 0.5) / (0.5 - a);
            return low + (top - low) * u * u;
        }
    };
    for ([_]f32{ -9.5, 9.5 }) |x| {
        var previous = f.at(0, x, 1);
        const samples = 28;
        for (1..samples + 1) |k| {
            const t = @as(f32, @floatFromInt(k)) / samples;
            const p = f.at(t, x, Cable.y(t, h, sag, towers[0], towers[1]));
            try beam(out, previous, p, 0.8, cable, true);
            previous = p;
        }
        const hangers: usize = @intFromFloat(@round((towers[1] - towers[0]) * f.length / 9));
        for (1..hangers) |k| {
            const t = towers[0] + (towers[1] - towers[0]) * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(hangers));
            try beam(out, f.at(t, x * 0.86, 0.4), f.at(t, x, Cable.y(t, h, sag, towers[0], towers[1]) - 0.4), 0.14, cable, false);
        }
    }
    try girderBox(out, f, 2.4, palette.suspension);
}

fn vineCables(out: anytype, s: District.Span) !void {
    const q = s.rotation();
    for ([_]f32{ -6.75, 6.75 }) |x| {
        var previous: V = undefined;
        for (0..9) |i| {
            const t = @as(f32, @floatFromInt(i)) / 8;
            const height = 3 + 9 * (2 * t - 1) * (2 * t - 1);
            const foot = R.add(s.point(t), R.rotate(q, .{ x, 0, 0 }));
            const top = R.add(foot, .{ 0, height, 0 });
            if (i > 0) try beam(out, previous, top, 0.35, vine, false);
            try beam(out, R.add(foot, .{ 0, 1.1, 0 }), top, if (i == 0 or i == 8) 0.6 else 0.12, vine, i == 0 or i == 8);
            previous = top;
        }
    }
}

pub const Light = struct { a: V, b: V };
pub const max_lights = 64;

/// Segments that carry light strings at night: suspension main cables and arch ribs, from
/// the same curves as their structure.
pub fn lights(layout: *const District.Layout, s: District.Span, style: Style, out: *[max_lights]Light) []const Light {
    const f = Frame.init(layout, s);
    var n: usize = 0;
    switch (style) {
        .suspension => {
            const h = std.math.clamp(0.13 * f.length, 30, 55);
            for ([_]f32{ -9.5, 9.5 }) |x| {
                var previous = f.at(0, x, 1);
                for (1..29) |k| {
                    const t = @as(f32, @floatFromInt(k)) / 28;
                    const y = if (t <= 0.17) 1 + (h - 1) * t / 0.17 else if (t >= 0.83) 1 + (h - 1) * (1 - t) / 0.17 else blk: {
                        const u = (t - 0.5) / 0.33;
                        break :blk 2.5 + (h - 2.5) * u * u;
                    };
                    const p = f.at(t, x, y + 0.5);
                    out[n] = .{ .a = previous, .b = p };
                    n += 1;
                    previous = p;
                }
            }
        },
        .arch => {
            const rise = std.math.clamp(0.14 * f.length, 16, 42);
            for ([_]f32{ -7.9, 7.9 }) |x| {
                var previous = f.at(0.05, x, 0.8);
                for (1..21) |k| {
                    const u = @as(f32, @floatFromInt(k)) / 20;
                    const p = f.at(0.05 + 0.9 * u, x, rise * 4 * u * (1 - u) + 0.8);
                    out[n] = .{ .a = previous, .b = p };
                    n += 1;
                    previous = p;
                }
            }
        },
        else => {},
    }
    return out[0..n];
}

/// The deck shared by every style, then the style's structure.
pub fn parts(layout: *const District.Layout, s: District.Span, style: Style, out: anytype) !void {
    const q = s.rotation();
    const center = s.point(0.5);
    const length = s.length();
    try add(out, .{ .center = R.add(center, R.rotate(q, .{ 0, -0.4, 0 })), .size = .{ District.width, 0.8, length }, .rotation = q, .color = .{ 0.30, 0.34, 0.38 } });
    // Two 3.5 m lanes, two 3 m walkways and two 0.5 m rail strips total 14 m.
    for ([_]f32{ -5, 5 }) |x| try add(out, .{ .center = R.add(center, R.rotate(q, .{ x, 0.012, 0 })), .size = .{ 3, 0.024, length }, .rotation = q, .color = .{ 0.55, 0.49, 0.37 }, .solid = false });
    try add(out, .{ .center = R.add(center, R.rotate(q, .{ 0, 0.015, 0 })), .size = .{ 0.15, 0.03, length }, .rotation = q, .color = .{ 0.91, 0.75, 0.32 }, .solid = false });
    const rail: V = if (style == .vine) vine else steel;
    for ([_]f32{ -6.75, 6.75 }) |x| try add(out, .{ .center = R.add(center, R.rotate(q, .{ x, 0.55, 0 })), .size = .{ 0.5, 1.1, length }, .rotation = q, .color = rail });
    const f = Frame.init(layout, s);
    switch (style) {
        .vine => try vineCables(out, s),
        .girder => try girder(out, f),
        .truss => try truss(out, f),
        .arch => try arch(out, f),
        .cable_stayed => try cableStayed(out, f),
        .suspension => try suspension(out, f),
    }
}

/// Whether `p` is inside a piece's oriented box.
pub fn contains(piece: District.Piece, p: V) bool {
    const local = R.inverseRotate(piece.rotation, R.sub(p, piece.center));
    for (0..3) |k| if (@abs(local[k]) > piece.size[k] / 2) return false;
    return true;
}

/// Checks the clear envelope over a deck: nothing solid but the deck slab itself.
pub fn envelopeClear(s: District.Span, pieces: []const District.Piece) bool {
    const d = R.sub(s.b, s.a);
    const yaw = R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(d[0], d[2]));
    const right = R.rotate(yaw, .{ 1, 0, 0 });
    const samples: usize = @intFromFloat(@ceil(s.horizontal() / 2));
    for (0..samples + 1) |i| {
        const t = 0.01 + 0.98 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples));
        for ([_]f32{ -clear_half_width + 0.45, -3, 0, 3, clear_half_width - 0.45 }) |x| for ([_]f32{ 0.25, 1, 2.5, 4, clear_height }) |y| {
            const p = R.add(R.add(s.point(t), R.scale(right, x)), .{ 0, y, 0 });
            for (pieces, 0..) |piece, k| {
                if (k == 0 or !piece.solid) continue; // piece 0 is the deck slab
                if (contains(piece, p)) return false;
            }
        };
    }
    return true;
}

test "every style keeps the deck envelope clear and fits its capacity, on every road and new span" {
    for ([_]u64{ 0, 42, 310399555161 }) |seed| {
        const layout = try District.generate(seed);
        var spans: [District.base_edge_count + 1]District.Span = undefined;
        for (layout.edges, spans[0..District.base_edge_count]) |e, *s| s.* = District.span(&layout, e);
        spans[District.base_edge_count] = District.span(&layout, .{ .a = 0, .b = 3 });
        for (spans) |s| for (std.enums.values(Style)) |style| {
            var out: District.BridgeParts = .{};
            try parts(&layout, s, style, &out);
            try std.testing.expect(envelopeClear(s, out.slice()));
            for (out.slice()) |p| for (p.center ++ p.size) |v| try std.testing.expect(std.math.isFinite(v));
        };
    }
}

test "supports reach the ground and avoid plazas and trunks" {
    const layout = try District.generate(310399555161);
    for (layout.edges) |e| for ([_]Style{ .girder, .suspension, .cable_stayed }) |style| {
        const s = District.span(&layout, e);
        var out: District.BridgeParts = .{};
        try parts(&layout, s, style, &out);
        var grounded: usize = 0;
        for (out.slice()) |p| {
            if (p.size[1] < 8 or p.size[0] > 4) continue; // tall vertical members only
            const bottom = p.center[1] - p.size[1] / 2;
            const ground = Terrain.surface(layout.seed, p.center[0], p.center[2]).height;
            try std.testing.expect(@abs(bottom - (ground - 1)) < 1.5);
            for (layout.nodes) |node| try std.testing.expect(planar(p.center, node.position) >= District.plaza_radius + 4);
            grounded += 1;
        }
        try std.testing.expect(grounded >= 2);
    };
    // A wobbly obstruction inside the envelope is caught.
    const s = District.span(&layout, layout.edges[0]);
    var out: District.BridgeParts = .{};
    try parts(&layout, s, .girder, &out);
    try out.add(.{ .center = R.add(s.point(0.5), .{ 0, 2, 0 }), .size = .{ 1, 1, 1 }, .color = steel });
    try std.testing.expect(!envelopeClear(s, out.slice()));
}

test "light strings follow suspension cables and arch ribs only" {
    const layout = try District.generate(310399555161);
    const s = District.span(&layout, .{ .a = 0, .b = 3 });
    var buffer: [max_lights]Light = undefined;
    const cables = lights(&layout, s, .suspension, &buffer);
    try std.testing.expectEqual(@as(usize, 56), cables.len);
    // The strings run above the deck and meet the cable's ends at the anchorages.
    for (cables) |l| try std.testing.expect(l.a[1] >= s.point(0)[1] - 1 and l.b[1] > s.point(1)[1] - 2);
    try std.testing.expectEqual(@as(usize, 40), lights(&layout, s, .arch, &buffer).len);
    try std.testing.expectEqual(@as(usize, 0), lights(&layout, s, .truss, &buffer).len);
}
