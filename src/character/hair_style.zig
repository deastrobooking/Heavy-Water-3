//! Data-driven hair: a hairstyle is a short list of fat, tapered clumps whose roots sit on the
//! scalp, plus a hairline for the scalp cap. Everything here is plain data with a `validate`, so
//! a mod can describe a hairstyle without touching generator code.
//!
//! Coordinates are "scalp space". A clump root is an azimuth (0 = front, + toward the
//! character's left, pi = back) and an elevation (radians, + up, pi/2 = crown) on the head
//! ellipsoid, so the same style fits any head shape. Lengths and widths are fractions of the
//! head height. Nothing in this file reads the body; `Head` is the one place the generator
//! feeds head measurements in.

const std = @import("std");
const m = @import("math.zig");

const Vec3 = m.Vec3;

pub const max_clumps = 96;

/// Head measurements a style is fitted to. `hair.zig` fills this from the body landmarks in one
/// helper; if the head model changes, only that helper changes.
pub const Head = struct {
    /// Scalp ellipsoid center and radii (slightly larger than the skull).
    center: Vec3,
    radii: Vec3,
    /// Head height (chin to crown).
    H: f32,
    chin_y: f32,
    half_width: f32,

    /// Clump widths scale with how big the head is around, relative to a 0.5 H radius.
    pub fn girth(h: Head) f32 {
        return m.clamp((h.radii.x + h.radii.z) * 0.5 / (0.5 * h.H), 0.6, 1.6);
    }
    pub fn direction(az: f32, el: f32) Vec3 {
        return Vec3.init(@sin(az) * @cos(el), @sin(el), @cos(az) * @cos(el));
    }
    /// Outward unit normal of the scalp ellipsoid in the direction `d`.
    pub fn normalAt(h: Head, d: Vec3) Vec3 {
        return Vec3.init(d.x / h.radii.x, d.y / h.radii.y, d.z / h.radii.z).normalize();
    }
    /// Distance from the center in ellipsoid units: 1 is on the scalp.
    pub fn radius(h: Head, p: Vec3) f32 {
        const q = p.sub(h.center);
        return Vec3.init(q.x / h.radii.x, q.y / h.radii.y, q.z / h.radii.z).length();
    }
};

/// One tapered tuft of hair.
pub const ClumpDef = struct {
    /// Root azimuth on the scalp (radians; 0 front, + left, pi back).
    az: f32,
    /// Root elevation on the scalp (radians; 0 ear height, pi/2 crown).
    el: f32,
    /// Heading of the free part (radians; 0 forward, + left, pi back).
    yaw: f32 = 0,
    /// Pitch of the free part (radians; + up, - down).
    pitch: f32 = 0,
    /// Length in head heights.
    length: f32 = 0.5,
    /// Width at the root in head heights.
    width: f32 = 0.25,
    /// Thickness at the root in head heights; 0 uses 0.75 of the width (a fat, round spike).
    thickness: f32 = 0,
    /// Taper exponent: 1 = straight cone, lower = bulging then pointed, higher = blunt.
    taper: f32 = 1.2,
    /// Sideways bend over the whole length (radians, + toward the character's left of heading).
    curl: f32 = 0,
    /// Bend of the tip in the vertical plane (radians, + flicks up, - droops).
    flick: f32 = 0,
    /// 0..1 share of the length that rises along the scalp normal before turning to the heading.
    /// Higher gives a lifted, voluminous root; 0 sets the clump straight onto its heading.
    stand: f32 = 0.45,
    /// 0 = against the scalp, 1..3 = progressively more lifted layers on top of it.
    layer: u8 = 0,
    /// 0..1 how strongly the style's spikiness adjustment changes this clump.
    spike: f32 = 0.5,
    /// Hangs from a spring chain when the character has dynamic hair.
    sway: bool = false,
    /// Also emit the mirror image (azimuth, heading and curl negated).
    mirror: bool = false,
};

/// Where the scalp cap ends. The cap hides the skull under and between the clumps.
pub const CapDef = struct {
    /// Lowest covered elevation at azimuth 0, 0.9, 1.6, 2.4 and pi (symmetric about the face).
    hairline: [5]f32 = .{ 0.62, 0.42, -0.12, -0.75, -0.95 },
    /// Cap offset from the scalp in head heights.
    lift: f32 = 0.006,
};

pub const StyleDef = struct {
    name: []const u8,
    clumps: []const ClumpDef,
    cap: CapDef = .{},
};

/// Per-character adjustments, 1 = as authored. The creator exposes these.
pub const Adjust = struct {
    spike: f32 = 1,
    volume: f32 = 1,
    length: f32 = 1,
};

pub const Error = error{ NoClumps, TooManyClumps, NotFinite, OutOfRange };

/// Check a definition before it reaches the generator (a mod can hand us anything).
pub fn validate(def: StyleDef) Error!void {
    if (def.clumps.len == 0) return error.NoClumps;
    var total: usize = 0;
    for (def.clumps) |c| {
        total += if (c.mirror) 2 else 1;
        const all = [_]f32{ c.az, c.el, c.yaw, c.pitch, c.length, c.width, c.thickness, c.taper, c.curl, c.flick, c.stand, c.spike };
        for (all) |v| if (!std.math.isFinite(v)) return error.NotFinite;
        if (c.el < -1.4 or c.el > m.pi / 2.0 + 0.01) return error.OutOfRange;
        if (@abs(c.az) > m.tau or @abs(c.yaw) > m.tau) return error.OutOfRange;
        if (@abs(c.pitch) > m.pi / 2.0 + 0.01 or @abs(c.flick) > m.pi or @abs(c.curl) > m.tau) return error.OutOfRange;
        if (c.length < 0.02 or c.length > 4) return error.OutOfRange;
        if (c.width < 0.01 or c.width > 1 or c.thickness < 0 or c.thickness > 1) return error.OutOfRange;
        if (c.taper < 0.4 or c.taper > 6) return error.OutOfRange;
        if (c.stand < 0 or c.stand > 1 or c.spike < 0 or c.spike > 1) return error.OutOfRange;
        if (c.layer > 3) return error.OutOfRange;
    }
    if (total > max_clumps) return error.TooManyClumps;
    for (def.cap.hairline) |e| {
        if (!std.math.isFinite(e)) return error.NotFinite;
        if (e < -1.5 or e > m.pi / 2.0) return error.OutOfRange;
    }
    if (!std.math.isFinite(def.cap.lift) or def.cap.lift < 0 or def.cap.lift > 0.5) return error.OutOfRange;
}

/// The mirrored twin of `c`.
pub fn mirrored(c: ClumpDef) ClumpDef {
    var o = c;
    o.az = -c.az;
    o.yaw = -c.yaw;
    o.curl = -c.curl;
    o.mirror = false;
    return o;
}

/// Six centerline points from the scalp root to the tip.
pub fn clumpPath(head: Head, c: ClumpDef, adj: Adjust) [6]Vec3 {
    const H = head.H;
    const lay: f32 = @floatFromInt(c.layer);
    const d0 = Head.direction(c.az, c.el);
    const n = head.normalAt(d0);
    const root = head.center.add(d0.mul(head.radii)).addScaled(n, -0.012 * H + lay * 0.02 * H * adj.volume);
    const free = Vec3.init(@sin(c.yaw) * @cos(c.pitch), @sin(c.pitch), @cos(c.yaw) * @cos(c.pitch)).normalize();
    // axis for vertical-plane bends: horizontal, perpendicular to the heading
    const side_axis = Vec3.init(@cos(c.yaw), 0, -@sin(c.yaw));
    const spike_gain = 1 + (adj.spike - 1) * c.spike;
    const len = c.length * H * adj.length * (1 + (adj.spike - 1) * c.spike * 0.5);
    const flick = c.flick * spike_gain;
    const seg = len / 5.0;
    const stand = @max(c.stand, 0.02);

    var pts: [6]Vec3 = undefined;
    pts[0] = root;
    var p = root;
    for (1..6) |i| {
        const tm = (@as(f32, @floatFromInt(i)) - 0.5) / 5.0;
        const b = m.smoothstep(0, stand, tm);
        var dir = n.lerp(free, b).normalize();
        dir = m.Quat.fromAxisAngle(side_axis, -flick * tm * tm).rotate(dir);
        dir = m.Quat.fromAxisAngle(Vec3.unit_y, c.curl * tm).rotate(dir);
        p = p.addScaled(dir, seg);
        // hair never sinks into the skull, however it is bent
        const r = head.radius(p);
        if (r < 1.04) {
            const q = p.sub(head.center).scale(1.04 / @max(r, 0.2));
            p = head.center.add(q);
        }
        pts[i] = p;
    }
    return pts;
}

test "mirrored twin reflects about the face plane" {
    const c: ClumpDef = .{ .az = 0.7, .el = 0.9, .yaw = 0.5, .curl = 0.3 };
    const t = mirrored(c);
    try std.testing.expectEqual(@as(f32, -0.7), t.az);
    try std.testing.expectEqual(@as(f32, -0.5), t.yaw);
    try std.testing.expectEqual(@as(f32, -0.3), t.curl);
}

test "validate rejects empty, non-finite and out-of-range definitions" {
    const ok: ClumpDef = .{ .az = 0, .el = 1 };
    try validate(.{ .name = "ok", .clumps = &.{ok} });
    try std.testing.expectError(error.NoClumps, validate(.{ .name = "none", .clumps = &.{} }));
    var bad = ok;
    bad.width = std.math.nan(f32);
    try std.testing.expectError(error.NotFinite, validate(.{ .name = "nan", .clumps = &.{bad} }));
    bad = ok;
    bad.length = 9;
    try std.testing.expectError(error.OutOfRange, validate(.{ .name = "long", .clumps = &.{bad} }));
    const many: [60]ClumpDef = @splat(.{ .az = 0, .el = 1, .mirror = true });
    try std.testing.expectError(error.TooManyClumps, validate(.{ .name = "many", .clumps = &many }));
}

test "clump paths start on the scalp and stay outside the head" {
    const head: Head = .{ .center = Vec3.init(0, 1.4, -0.03), .radii = Vec3.init(0.12, 0.13, 0.12), .H = 0.25, .chin_y = 1.25, .half_width = 0.11 };
    const c: ClumpDef = .{ .az = 0.4, .el = 0.8, .yaw = 0.4, .pitch = -1.2, .length = 1.5, .flick = -1, .curl = 1.2 };
    const pts = clumpPath(head, c, .{});
    try std.testing.expect(@abs(head.radius(pts[0]) - 1) < 0.15);
    for (pts) |p| try std.testing.expect(head.radius(p) >= 0.9);
    for (pts[1..]) |p| try std.testing.expect(head.radius(p) >= 1.039);
}
