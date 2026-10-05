//! Wildkin forms: the animal and insect features built onto a character for every species but
//! human. Each feature is a rigid, oriented ellipsoid (or a chain of them, for tails, trunks,
//! antennae and legs) bound to one joint of the shared humanoid skeleton, so it follows the gait
//! and every combat pose with no new animation. Proportions are cartoon-heroic: bigger heads and
//! eyes than the realistic Ranger, with each species' height and build on top.
const std = @import("std");
const Profile = @import("../game/Profile.zig");
const gen = @import("character.zig");
const spec = @import("spec.zig");
const sk = @import("skeleton.zig");
const cm = @import("mesh.zig");
const m = @import("math.zig");
const V = m.Vec3;
const Q = m.Quat;

pub const Family = enum { human, mammal, reptile, amphibian, bird, insect, arachnid };

pub fn family(s: Profile.Species) Family {
    return switch (s) {
        .human => .human,
        .hedgehog, .fox, .rabbit, .raccoon, .possum, .lion, .elephant, .kangaroo, .wolf, .rhino, .panda, .gorilla, .bat => .mammal,
        .turtle, .snake, .alligator => .reptile,
        .frog => .amphibian,
        .eagle, .hawk, .owl => .bird,
        .mantis, .beetle, .bee, .butterfly => .insect,
        .spider, .scorpion => .arachnid,
    };
}

/// Whether the form flies (wings: the flight traversal kit is theirs from the start).
pub fn winged(s: Profile.Species) bool {
    return switch (s) {
        .eagle, .hawk, .owl, .bat, .bee, .butterfly => true,
        else => false,
    };
}

/// Height and build multipliers on the profile's own, per form.
pub const Scale = struct { height: f32 = 1, build: f32 = 1 };

pub fn scale(s: Profile.Species) Scale {
    return switch (s) {
        .human => .{},
        .hedgehog, .rabbit, .frog => .{ .height = 0.88, .build = 0.95 },
        .possum, .bee => .{ .height = 0.86, .build = 0.95 },
        .fox, .bat, .hawk => .{ .height = 0.95, .build = 0.9 },
        .raccoon, .owl, .butterfly => .{ .height = 0.92, .build = 0.95 },
        .turtle => .{ .height = 0.92, .build = 1.2 },
        .snake, .mantis, .spider => .{ .height = 1.0, .build = 0.86 },
        .alligator, .scorpion => .{ .height = 1.0, .build = 1.12 },
        .lion, .wolf, .eagle, .beetle => .{ .height = 1.02, .build = 1.05 },
        .elephant => .{ .height = 1.1, .build = 1.3 },
        .kangaroo => .{ .height = 1.08, .build = 1.0 },
        .rhino, .gorilla => .{ .height = 1.06, .build = 1.3 },
        .panda => .{ .height = 1.0, .build = 1.25 },
    };
}

/// Heads tall: Wildkin read as cartoon heroes, insects a little slimmer-headed.
pub fn headRatio(s: Profile.Species) f32 {
    return switch (family(s)) {
        .human => 7.5,
        .insect, .arachnid => 5.4,
        else => 5.0,
    };
}

/// Eye colouring per form (cartoon-large eyes, coloured to the animal).
pub fn eyes(s: Profile.Species, base: spec.EyeSpec, accent: spec.Rgb) spec.EyeSpec {
    if (s == .human) return base;
    var e = base;
    e.size = 0.24;
    e.aspect = 1.0;
    e.pupil_size = 0.42;
    e.highlight_count = 2;
    e.iris_color = switch (s) {
        .snake, .alligator, .frog => spec.Rgb.hex(0xd8c22a),
        .owl, .eagle, .hawk => spec.Rgb.hex(0xf09a1c),
        .spider, .scorpion => spec.Rgb.hex(0xd8303a),
        .wolf => spec.Rgb.hex(0x9fc8e8),
        .fox, .lion => spec.Rgb.hex(0xc98a2a),
        .mantis, .beetle, .bee, .butterfly => spec.Rgb.hex(0x2a2a34),
        else => spec.Rgb.hex(0x6a4a2a),
    };
    e.iris_dark = .{ .r = e.iris_color.r * 0.35, .g = e.iris_color.g * 0.35, .b = e.iris_color.b * 0.35 };
    // Insects' compound eyes are glossy and dark, with the accent caught in them.
    if (family(s) == .insect) {
        e.size = 0.3;
        e.pupil_size = 0.7;
        e.iris_dark = accent;
    }
    return e;
}

// ---------------------------------------------------------------- building

const Builder = struct {
    a: std.mem.Allocator,
    ch: *gen.Character,

    /// The palette index for `color`, reusing an equal entry (the palette holds at most 256).
    fn paint(self: Builder, color: spec.Rgb) !u8 {
        for (self.ch.palette.items, 0..) |c, i| if (c.r == color.r and c.g == color.g and c.b == color.b) return @intCast(i);
        if (self.ch.palette.items.len >= 255) return 0;
        try self.ch.palette.append(self.a, color);
        return @intCast(self.ch.palette.items.len - 1);
    }

    /// An ellipsoid with `radii` along its local axes, turned by `rot`, bound rigidly to `joint`.
    fn blob(self: Builder, joint: sk.Joint, center: V, radii: V, rot: Q, color: spec.Rgb) !void {
        const rows = 8;
        const cols = 14;
        const base = self.ch.mesh.vertexCount();
        const palette = try self.paint(color);
        for (0..rows + 1) |r| for (0..cols) |c| {
            const latitude = m.pi * @as(f32, @floatFromInt(r)) / rows;
            const angle = m.tau * @as(f32, @floatFromInt(c)) / cols;
            const n = V.init(@sin(latitude) * @cos(angle), @cos(latitude), @sin(latitude) * @sin(angle));
            const p = rot.rotate(V.init(n.x * radii.x, n.y * radii.y, n.z * radii.z));
            const normal = rot.rotate(V.init(n.x / radii.x, n.y / radii.y, n.z / radii.z).normalize());
            _ = try self.ch.mesh.addVertex(self.a, .{ .pos = center.add(p), .normal = normal, .joints = .{ joint.idx(), 0, 0, 0 }, .material = .cloth_outer });
            try self.ch.color_index.append(self.a, palette);
        };
        try self.ch.mesh.stitchRings(self.a, base, rows + 1, cols, true, false);
    }

    /// An upright-axis ellipsoid (no rotation).
    fn ball(self: Builder, joint: sk.Joint, center: V, radii: V, color: spec.Rgb) !void {
        try self.blob(joint, center, radii, Q.identity, color);
    }

    /// A tapering chain along a curve: `count` segments from `start`, heading `dir`, turning by
    /// `bend` (radians per segment about `axis`), radius `r0` to `r1`. Colours alternate when
    /// `banded` (striped and ringed tails).
    fn chain(self: Builder, joint: sk.Joint, start: V, dir: V, length: f32, count: usize, r0: f32, r1: f32, axis: V, bend: f32, color: spec.Rgb, band: ?spec.Rgb) !V {
        var at = start;
        var d = dir.normalize();
        const step = length / @as(f32, @floatFromInt(count));
        const turn = Q.fromAxisAngle(axis.normalize(), bend);
        for (0..count) |k| {
            const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(@max(1, count - 1)));
            const r = r0 + (r1 - r0) * t;
            const mid = at.add(d.scale(step * 0.5));
            const rot = Q.fromTo(V.unit_y, d);
            const c = if (band) |b| (if (k % 2 == 1) b else color) else color;
            try self.blob(joint, mid, V.init(r, step * 0.62, r), rot, c);
            at = at.add(d.scale(step));
            d = turn.rotate(d).normalize();
        }
        return at;
    }
};

fn rgb(c: [4]f32, f: f32) spec.Rgb {
    return .{ .r = c[0] * f, .g = c[1] * f, .b = c[2] * f };
}

fn tilt(axis: V, angle: f32) Q {
    return Q.fromAxisAngle(axis, angle);
}

/// Builds the form's features onto `ch`. Hair has already been removed for Wildkin.
pub fn build(a: std.mem.Allocator, ch: *gen.Character, p: Profile) !void {
    if (p.species == .human) return;
    const b: Builder = .{ .a = a, .ch = ch };
    const lm = ch.landmarks;
    const s = &ch.skeleton;
    const H = lm.H;
    const h = lm.height;
    const coat = rgb(Profile.coat_colors[p.coat], 1);
    const mark = rgb(Profile.coat_colors[p.marking], 1);
    const dark = spec.Rgb.hex(0x1f1a1c);
    const ivory = spec.Rgb.hex(0xf1e6cf);
    const pink = spec.Rgb.hex(0xe89aa6);
    const beak = spec.Rgb.hex(0xf2b22e);
    const glow = rgb(Profile.accent_colors[p.accent], 1.3);
    // Head frame: centre of the skull, and the face's front.
    const head = V.init(0, lm.chin_y + 0.52 * H, 0);
    const face_z = lm.scalp_center.z + lm.scalp_radii.z * 0.92;
    const mouth = V.init(0, lm.chin_y + 0.24 * H, face_z);
    const hw = lm.head_half_width;
    const chest = s.worldPos(.chest);
    const hips = s.worldPos(.hips);
    const back_z = chest.z - 0.14 * h;
    const tail_root = V.init(0, hips.y - 0.02 * h, hips.z - 0.11 * h);
    const x_axis = V.unit_x;

    // Shared head parts.
    const Parts = struct {
        fn snout(bb: Builder, at: V, length: f32, width: f32, height: f32, color: spec.Rgb, nose: ?spec.Rgb) !void {
            try bb.ball(.head, at.add(V.init(0, 0, length * 0.5)), V.init(width, height, length * 0.65), color);
            if (nose) |n| try bb.ball(.head, at.add(V.init(0, height * 0.35, length * 1.05)), V.init(width * 0.36, height * 0.3, width * 0.3), n);
        }
        fn ears(bb: Builder, top: V, spread: f32, size: V, lean: f32, color: spec.Rgb, inner: ?spec.Rgb) !void {
            for ([_]f32{ -1, 1 }) |side| {
                const rot = Q.fromAxisAngle(V.unit_z, -side * lean);
                const at = top.add(V.init(side * spread, size.y * 0.7, 0));
                try bb.blob(.head, at, size, rot, color);
                if (inner) |i| try bb.blob(.head, at.add(V.init(0, 0, size.z * 0.6)), V.init(size.x * 0.55, size.y * 0.7, size.z * 0.4), rot, i);
            }
        }
        fn antennae(bb: Builder, top: V, spread: f32, length: f32, color: spec.Rgb, tip: ?spec.Rgb) !void {
            for ([_]f32{ -1, 1 }) |side| {
                const end = try bb.chain(.head, top.add(V.init(side * spread, 0, 0)), V.init(side * 0.35, 1, 0.45), length, 5, length * 0.05, length * 0.03, V.init(1, 0, 0), 0.22, color, null);
                if (tip) |t| try bb.ball(.head, end, V.init(length * 0.1, length * 0.1, length * 0.1), t);
            }
        }
        /// Feathered wings on the back: fans of long feathers, each side.
        fn featherWings(bb: Builder, root: V, span: f32, color: spec.Rgb, tips: spec.Rgb) !void {
            for ([_]f32{ -1, 1 }) |side| for (0..6) |k| {
                const t = @as(f32, @floatFromInt(k)) / 5;
                const out = V.init(side * (0.55 + 0.45 * t), 0.75 - 1.1 * t, -0.35).normalize();
                const len = span * (1 - 0.45 * t);
                const rot = Q.fromTo(V.unit_y, out);
                const center = root.add(V.init(side * 0.05 * span, 0, 0)).add(out.scale(len * 0.5));
                try bb.blob(.chest, center, V.init(len * 0.09, len * 0.5, len * 0.025), rot, if (k < 2) tips else color);
            };
        }
        /// Membrane wings from the arm: a broad sheet from the upper arm and another from the
        /// forearm, so they open and fold with the arms.
        fn membraneWings(bb: Builder, sk_: *const sk.Skeleton, color: spec.Rgb, bone: spec.Rgb, hh: f32) !void {
            inline for (.{ .{ sk.Joint.upper_arm_l, sk.Joint.lower_arm_l, @as(f32, 1) }, .{ sk.Joint.upper_arm_r, sk.Joint.lower_arm_r, @as(f32, -1) } }) |arm| {
                const upper = sk_.worldPos(arm[0]);
                const lower = sk_.worldPos(arm[1]);
                const side = arm[2];
                try bb.blob(arm[0], upper.add(V.init(side * 0.04 * hh, -0.14 * hh, -0.03 * hh)), V.init(0.1 * hh, 0.17 * hh, 0.012 * hh), Q.fromAxisAngle(V.unit_z, side * 0.5), color);
                try bb.blob(arm[1], lower.add(V.init(side * 0.08 * hh, -0.16 * hh, -0.03 * hh)), V.init(0.12 * hh, 0.2 * hh, 0.012 * hh), Q.fromAxisAngle(V.unit_z, side * 0.75), color);
                try bb.blob(arm[1], lower.add(V.init(side * 0.12 * hh, -0.02 * hh, -0.02 * hh)), V.init(0.012 * hh, 0.15 * hh, 0.012 * hh), Q.fromAxisAngle(V.unit_z, side * 1.2), bone);
            }
        }
    };

    switch (p.species) {
        .human => {},
        .hedgehog => {
            // Swept-back quills: the speedster's crest.
            for (0..7) |k| {
                const t = @as(f32, @floatFromInt(k)) / 6;
                const dir = V.init((t - 0.5) * 1.1, 0.35 - 0.25 * @abs(t - 0.5), -1).normalize();
                const root = head.add(V.init((t - 0.5) * hw * 1.2, 0.2 * H, -0.2 * H));
                try b.blob(.head, root.add(dir.scale(0.28 * H)), V.init(0.1 * H, 0.42 * H, 0.1 * H), Q.fromTo(V.unit_y, dir), coat);
            }
            for (0..3) |k| {
                const x = (@as(f32, @floatFromInt(k)) - 1) * 0.06 * h;
                try b.blob(.chest, V.init(x, chest.y + 0.02 * h, back_z - 0.02 * h), V.init(0.03 * h, 0.09 * h, 0.03 * h), tilt(x_axis, -0.9), coat);
            }
            try Parts.snout(b, mouth, 0.22 * H, 0.2 * H, 0.15 * H, mark, dark);
            try Parts.ears(b, head.add(V.init(0, 0.3 * H, -0.05 * H)), 0.5 * hw, V.init(0.1 * H, 0.14 * H, 0.06 * H), 0.4, coat, mark);
        },
        .fox, .wolf => {
            const long = p.species == .wolf;
            try Parts.snout(b, mouth.add(V.init(0, 0.05 * H, 0)), (if (long) @as(f32, 0.45) else 0.38) * H, 0.17 * H, 0.14 * H, mark, dark);
            try Parts.ears(b, head.add(V.init(0, 0.38 * H, -0.05 * H)), 0.62 * hw, V.init(0.13 * H, 0.26 * H, 0.06 * H), 0.25, coat, mark);
            const end = try b.chain(.hips, tail_root, V.init(0, -0.2, -1), 0.42 * h, 6, 0.045 * h, 0.07 * h, x_axis, 0.18, coat, null);
            try b.ball(.hips, end, V.init(0.06 * h, 0.06 * h, 0.07 * h), mark);
        },
        .rabbit => {
            try Parts.snout(b, mouth, 0.16 * H, 0.18 * H, 0.14 * H, mark, pink);
            try b.ball(.head, mouth.add(V.init(0, -0.08 * H, 0.14 * H)), V.init(0.06 * H, 0.08 * H, 0.03 * H), ivory);
            for ([_]f32{ -1, 1 }) |side| try b.blob(.head, head.add(V.init(side * 0.35 * hw, 0.9 * H, -0.1 * H)), V.init(0.12 * H, 0.5 * H, 0.06 * H), tilt(V.unit_z, -side * 0.15), coat);
            try b.ball(.hips, tail_root, V.init(0.07 * h, 0.07 * h, 0.07 * h), mark);
        },
        .raccoon => {
            try Parts.snout(b, mouth, 0.24 * H, 0.16 * H, 0.13 * H, mark, dark);
            try Parts.ears(b, head.add(V.init(0, 0.32 * H, -0.05 * H)), 0.62 * hw, V.init(0.12 * H, 0.15 * H, 0.05 * H), 0.3, dark, mark);
            _ = try b.chain(.hips, tail_root, V.init(0, -0.1, -1), 0.5 * h, 8, 0.05 * h, 0.04 * h, x_axis, 0.12, coat, dark);
        },
        .turtle => {
            // The shell: a broad dome on the back, rimmed darker, with a plastron in front.
            try b.ball(.chest, V.init(0, chest.y - 0.05 * h, back_z - 0.05 * h), V.init(0.24 * h, 0.27 * h, 0.13 * h), mark);
            try b.ball(.chest, V.init(0, chest.y - 0.05 * h, back_z - 0.02 * h), V.init(0.26 * h, 0.29 * h, 0.07 * h), dark);
            try b.ball(.chest, V.init(0, chest.y - 0.06 * h, chest.z + 0.12 * h), V.init(0.16 * h, 0.2 * h, 0.05 * h), spec.Rgb.hex(0xe9d38c));
            try Parts.snout(b, mouth, 0.14 * H, 0.22 * H, 0.14 * H, coat, null);
        },
        .frog => {
            for ([_]f32{ -1, 1 }) |side| {
                try b.ball(.head, head.add(V.init(side * 0.42 * hw, 0.42 * H, 0.18 * H)), V.init(0.2 * H, 0.18 * H, 0.18 * H), coat);
                try b.ball(.head, head.add(V.init(side * 0.42 * hw, 0.44 * H, 0.33 * H)), V.init(0.1 * H, 0.1 * H, 0.05 * H), dark);
            }
            try b.ball(.head, mouth.add(V.init(0, 0, 0.02 * H)), V.init(0.55 * hw, 0.05 * H, 0.06 * H), spec.Rgb.hex(0x9a2d3a));
            try b.ball(.chest, V.init(0, chest.y - 0.06 * h, chest.z + 0.1 * h), V.init(0.14 * h, 0.17 * h, 0.05 * h), mark);
        },
        .snake => {
            // A flared hood behind the head, a blunt snout, and a long tail along the ground.
            try b.ball(.neck, head.add(V.init(0, -0.1 * H, -0.3 * H)), V.init(1.25 * hw, 0.7 * H, 0.06 * H), mark);
            try Parts.snout(b, mouth.add(V.init(0, 0.06 * H, 0)), 0.3 * H, 0.26 * H, 0.12 * H, coat, null);
            try b.ball(.head, mouth.add(V.init(0, -0.05 * H, 0.42 * H)), V.init(0.05 * H, 0.015 * H, 0.08 * H), spec.Rgb.hex(0xd8303a));
            _ = try b.chain(.hips, tail_root.add(V.init(0, -0.04 * h, 0)), V.init(0, -0.6, -1), 0.95 * h, 9, 0.07 * h, 0.02 * h, x_axis, 0.1, coat, mark);
        },
        .alligator => {
            try Parts.snout(b, mouth.add(V.init(0, 0.02 * H, 0)), 0.75 * H, 0.24 * H, 0.12 * H, coat, null);
            for (0..5) |k| for ([_]f32{ -1, 1 }) |side| {
                try b.ball(.head, mouth.add(V.init(side * 0.2 * H, -0.08 * H, (0.15 + 0.18 * @as(f32, @floatFromInt(k))) * H)), V.init(0.025 * H, 0.05 * H, 0.025 * H), ivory);
            };
            for (0..5) |k| try b.ball(.chest, V.init(0, chest.y + 0.08 * h - 0.06 * h * @as(f32, @floatFromInt(k)), back_z), V.init(0.03 * h, 0.03 * h, 0.04 * h), mark);
            _ = try b.chain(.hips, tail_root, V.init(0, -0.55, -1), 0.8 * h, 8, 0.09 * h, 0.03 * h, x_axis, 0.06, coat, null);
        },
        .possum => {
            try Parts.snout(b, mouth, 0.34 * H, 0.14 * H, 0.12 * H, mark, pink);
            try Parts.ears(b, head.add(V.init(0, 0.3 * H, -0.05 * H)), 0.62 * hw, V.init(0.13 * H, 0.13 * H, 0.04 * H), 0.4, pink, null);
            _ = try b.chain(.hips, tail_root, V.init(0, -0.3, -1), 0.6 * h, 9, 0.025 * h, 0.012 * h, x_axis, 0.32, pink, null);
        },
        .lion => {
            // The mane: a ring of thick tufts around the face.
            for (0..12) |k| {
                const angle = @as(f32, @floatFromInt(k)) / 12 * m.tau;
                const at = head.add(V.init(@cos(angle) * 1.2 * hw, @sin(angle) * 0.6 * H + 0.02 * H, -0.12 * H));
                try b.ball(.head, at, V.init(0.24 * H, 0.24 * H, 0.2 * H), mark);
            }
            try Parts.snout(b, mouth, 0.22 * H, 0.22 * H, 0.15 * H, rgb(Profile.coat_colors[p.coat], 1.15), dark);
            try Parts.ears(b, head.add(V.init(0, 0.36 * H, 0)), 0.55 * hw, V.init(0.1 * H, 0.1 * H, 0.05 * H), 0.3, coat, null);
            const end = try b.chain(.hips, tail_root, V.init(0, -0.4, -1), 0.55 * h, 7, 0.022 * h, 0.018 * h, x_axis, -0.12, coat, null);
            try b.ball(.hips, end, V.init(0.045 * h, 0.05 * h, 0.045 * h), mark);
        },
        .elephant => {
            for ([_]f32{ -1, 1 }) |side| {
                try b.blob(.head, head.add(V.init(side * 1.25 * hw, 0.0, -0.05 * H)), V.init(0.55 * H, 0.62 * H, 0.05 * H), tilt(V.unit_y, side * 0.35), coat);
                _ = try b.chain(.head, mouth.add(V.init(side * 0.18 * H, -0.05 * H, 0.1 * H)), V.init(side * 0.2, -0.4, 1), 0.38 * H, 4, 0.045 * H, 0.03 * H, V.unit_x, -0.3, ivory, null);
            }
            _ = try b.chain(.head, mouth.add(V.init(0, 0.08 * H, 0.08 * H)), V.init(0, -0.2, 1), 1.1 * H, 8, 0.13 * H, 0.07 * H, x_axis, 0.32, coat, null);
            _ = try b.chain(.hips, tail_root, V.init(0, -1, -0.4), 0.3 * h, 5, 0.015 * h, 0.012 * h, x_axis, 0, coat, null);
        },
        .kangaroo => {
            try Parts.snout(b, mouth, 0.34 * H, 0.17 * H, 0.15 * H, coat, dark);
            try Parts.ears(b, head.add(V.init(0, 0.42 * H, -0.05 * H)), 0.5 * hw, V.init(0.12 * H, 0.3 * H, 0.05 * H), 0.15, coat, mark);
            try b.ball(.hips, V.init(0, hips.y + 0.04 * h, hips.z + 0.12 * h), V.init(0.13 * h, 0.1 * h, 0.05 * h), mark);
            _ = try b.chain(.hips, tail_root, V.init(0, -0.8, -1), 0.75 * h, 7, 0.08 * h, 0.035 * h, x_axis, -0.06, coat, null);
        },
        .rhino => {
            try Parts.snout(b, mouth.add(V.init(0, 0.03 * H, 0)), 0.4 * H, 0.3 * H, 0.2 * H, coat, null);
            try b.blob(.head, mouth.add(V.init(0, 0.28 * H, 0.42 * H)), V.init(0.1 * H, 0.32 * H, 0.1 * H), tilt(x_axis, 0.45), ivory);
            try b.blob(.head, mouth.add(V.init(0, 0.3 * H, 0.18 * H)), V.init(0.06 * H, 0.16 * H, 0.06 * H), tilt(x_axis, 0.3), ivory);
            try Parts.ears(b, head.add(V.init(0, 0.33 * H, -0.12 * H)), 0.6 * hw, V.init(0.08 * H, 0.14 * H, 0.05 * H), 0.4, coat, null);
            for ([_]f32{ -1, 1 }) |side| try b.ball(if (side > 0) .shoulder_l else .shoulder_r, s.worldPos(if (side > 0) .shoulder_l else .shoulder_r).add(V.init(side * 0.05 * h, 0.03 * h, 0)), V.init(0.1 * h, 0.07 * h, 0.09 * h), mark);
        },
        .panda => {
            try Parts.snout(b, mouth, 0.16 * H, 0.2 * H, 0.14 * H, coat, dark);
            try Parts.ears(b, head.add(V.init(0, 0.34 * H, -0.05 * H)), 0.6 * hw, V.init(0.13 * H, 0.13 * H, 0.08 * H), 0.3, mark, null);
            for ([_]f32{ -1, 1 }) |side| try b.ball(if (side > 0) .shoulder_l else .shoulder_r, s.worldPos(if (side > 0) .shoulder_l else .shoulder_r).add(V.init(side * 0.03 * h, 0, 0)), V.init(0.09 * h, 0.08 * h, 0.09 * h), mark);
        },
        .gorilla => {
            try b.ball(.head, head.add(V.init(0, 0.2 * H, face_z * 0.75)), V.init(0.9 * hw, 0.08 * H, 0.1 * H), coat);
            try Parts.snout(b, mouth, 0.2 * H, 0.3 * H, 0.2 * H, mark, null);
            try b.ball(.chest, V.init(0, chest.y - 0.04 * h, chest.z + 0.1 * h), V.init(0.15 * h, 0.13 * h, 0.05 * h), mark);
        },
        .eagle, .hawk, .owl => {
            const hook = p.species != .owl;
            try b.blob(.head, mouth.add(V.init(0, 0.08 * H, 0.12 * H)), V.init(0.13 * H, 0.13 * H, (if (hook) @as(f32, 0.3) else 0.16) * H), tilt(x_axis, 0.35), beak);
            if (p.species == .owl) {
                try Parts.ears(b, head.add(V.init(0, 0.4 * H, -0.02 * H)), 0.65 * hw, V.init(0.06 * H, 0.2 * H, 0.05 * H), 0.35, coat, null);
            } else for (0..3) |k| {
                const x = (@as(f32, @floatFromInt(k)) - 1) * 0.15 * H;
                try b.blob(.head, head.add(V.init(x, 0.38 * H, -0.42 * H)), V.init(0.08 * H, 0.32 * H, 0.04 * H), tilt(x_axis, -1.0), mark);
            }
            try Parts.featherWings(b, V.init(0, chest.y + 0.04 * h, back_z), (if (p.species == .hawk) @as(f32, 0.62) else 0.7) * h, coat, mark);
            for (0..5) |k| {
                const t = (@as(f32, @floatFromInt(k)) - 2) * 0.22;
                const dir = V.init(t, -0.55, -1).normalize();
                try b.blob(.hips, tail_root.add(dir.scale(0.12 * h)), V.init(0.035 * h, 0.15 * h, 0.012 * h), Q.fromTo(V.unit_y, dir), if (k % 2 == 0) coat else mark);
            }
        },
        .bat => {
            try Parts.snout(b, mouth, 0.14 * H, 0.15 * H, 0.12 * H, coat, pink);
            try Parts.ears(b, head.add(V.init(0, 0.4 * H, -0.05 * H)), 0.6 * hw, V.init(0.16 * H, 0.32 * H, 0.05 * H), 0.35, coat, pink);
            try Parts.membraneWings(b, s, mark, dark, h);
        },
        .spider => {
            // Eight eyes' worth of extra glints above the two, small fangs, four more legs.
            for (0..6) |k| {
                const x = (@as(f32, @floatFromInt(k % 3)) - 1) * 0.16 * hw;
                const y = 0.3 * H + @as(f32, @floatFromInt(k / 3)) * 0.1 * H;
                try b.ball(.head, V.init(x, head.y + y, face_z - 0.02 * H), V.init(0.045 * H, 0.045 * H, 0.03 * H), dark);
            }
            for ([_]f32{ -1, 1 }) |side| try b.blob(.head, mouth.add(V.init(side * 0.08 * H, -0.06 * H, 0.04 * H)), V.init(0.03 * H, 0.08 * H, 0.03 * H), tilt(x_axis, 0.3), ivory);
            for ([_]f32{ -1, 1 }) |side| for (0..2) |k| {
                const y = chest.y - 0.02 * h - @as(f32, @floatFromInt(k)) * 0.08 * h;
                const start = V.init(side * 0.13 * h, y, chest.z - 0.04 * h);
                _ = try b.chain(.chest, start, V.init(side, 0.35 - 0.3 * @as(f32, @floatFromInt(k)), -0.3), 0.5 * h, 6, 0.022 * h, 0.012 * h, V.init(0, 0, side), -0.38, coat, mark);
            };
        },
        .mantis => {
            try Parts.antennae(b, head.add(V.init(0, 0.36 * H, 0.1 * H)), 0.25 * hw, 0.7 * H, coat, null);
            inline for (.{ .{ sk.Joint.lower_arm_l, @as(f32, 1) }, .{ sk.Joint.lower_arm_r, @as(f32, -1) } }) |arm| {
                const at = s.worldPos(arm[0]);
                const dir = V.init(arm[1] * lm.arm_dir_l.x, lm.arm_dir_l.y, 0).normalize();
                try b.blob(arm[0], at.add(dir.scale(0.2 * h)).add(V.init(0, -0.02 * h, 0.02 * h)), V.init(0.02 * h, 0.2 * h, 0.05 * h), Q.fromTo(V.unit_y, dir), mark);
            }
            for ([_]f32{ -1, 1 }) |side| try b.blob(.chest, V.init(side * 0.08 * h, chest.y - 0.06 * h, back_z), V.init(0.06 * h, 0.3 * h, 0.01 * h), tilt(V.unit_z, side * 0.12), rgb(Profile.coat_colors[p.coat], 1.3));
        },
        .beetle => {
            try b.blob(.head, head.add(V.init(0, 0.25 * H, face_z * 0.7)), V.init(0.1 * H, 0.45 * H, 0.1 * H), tilt(x_axis, 0.55), mark);
            try Parts.antennae(b, head.add(V.init(0, 0.3 * H, 0.15 * H)), 0.4 * hw, 0.35 * H, dark, null);
            for ([_]f32{ -1, 1 }) |side| try b.blob(.chest, V.init(side * 0.1 * h, chest.y - 0.08 * h, back_z - 0.03 * h), V.init(0.11 * h, 0.27 * h, 0.08 * h), tilt(V.unit_z, side * 0.06), coat);
            try b.ball(.chest, V.init(0, chest.y - 0.08 * h, back_z), V.init(0.008 * h, 0.27 * h, 0.09 * h), dark);
        },
        .bee => {
            try Parts.antennae(b, head.add(V.init(0, 0.38 * H, 0.08 * H)), 0.3 * hw, 0.45 * H, dark, dark);
            // A striped abdomen behind the hips, with a stinger.
            for (0..4) |k| {
                const at = V.init(0, hips.y + 0.02 * h - 0.025 * h * @as(f32, @floatFromInt(k)), hips.z - 0.12 * h - 0.06 * h * @as(f32, @floatFromInt(k)));
                const r = 0.11 * h - 0.015 * h * @as(f32, @floatFromInt(k));
                try b.ball(.hips, at, V.init(r, r * 0.9, 0.05 * h), if (k % 2 == 0) coat else dark);
            }
            try b.blob(.hips, V.init(0, hips.y - 0.08 * h, hips.z - 0.38 * h), V.init(0.012 * h, 0.05 * h, 0.012 * h), tilt(x_axis, -1.2), dark);
            for ([_]f32{ -1, 1 }) |side| try b.blob(.chest, V.init(side * 0.16 * h, chest.y + 0.08 * h, back_z - 0.04 * h), V.init(0.13 * h, 0.2 * h, 0.01 * h), tilt(V.unit_z, -side * 0.7), spec.Rgb.hex(0xd8eef8));
        },
        .butterfly => {
            try Parts.antennae(b, head.add(V.init(0, 0.38 * H, 0.08 * H)), 0.3 * hw, 0.55 * H, dark, glow);
            for ([_]f32{ -1, 1 }) |side| {
                try b.blob(.chest, V.init(side * 0.28 * h, chest.y + 0.12 * h, back_z - 0.04 * h), V.init(0.24 * h, 0.2 * h, 0.01 * h), tilt(V.unit_z, -side * 0.45), coat);
                try b.blob(.chest, V.init(side * 0.3 * h, chest.y + 0.14 * h, back_z - 0.035 * h), V.init(0.1 * h, 0.08 * h, 0.012 * h), Q.identity, mark);
                try b.blob(.chest, V.init(side * 0.2 * h, chest.y - 0.16 * h, back_z - 0.04 * h), V.init(0.14 * h, 0.17 * h, 0.01 * h), tilt(V.unit_z, side * 0.5), mark);
                try b.ball(.chest, V.init(side * 0.36 * h, chest.y + 0.2 * h, back_z - 0.03 * h), V.init(0.04 * h, 0.04 * h, 0.014 * h), glow);
            }
        },
        .scorpion => {
            // A segmented tail arching up over the back, ending in a stinger; pincers at the hands.
            // A backward chain turns upward with a positive bend about +X.
            const end = try b.chain(.hips, tail_root.add(V.init(0, 0.02 * h, 0)), V.init(0, 0.55, -1), 1.05 * h, 8, 0.06 * h, 0.035 * h, x_axis, 0.42, coat, mark);
            try b.blob(.hips, end.add(V.init(0, -0.03 * h, 0.04 * h)), V.init(0.03 * h, 0.08 * h, 0.03 * h), tilt(x_axis, 2.4), glow);
            inline for (.{ sk.Joint.hand_l, sk.Joint.hand_r }) |hand| {
                const at = s.worldPos(hand);
                try b.ball(hand, at.add(V.init(0, -0.02 * h, 0.04 * h)), V.init(0.05 * h, 0.07 * h, 0.04 * h), mark);
                try b.blob(hand, at.add(V.init(0, -0.08 * h, 0.07 * h)), V.init(0.018 * h, 0.06 * h, 0.018 * h), tilt(x_axis, 0.5), mark);
            }
            try Parts.snout(b, mouth, 0.1 * H, 0.18 * H, 0.1 * H, coat, null);
        },
    }
}

test "every Wildkin form builds a clean, weighted character with its own features" {
    const Ranger = @import("Ranger.zig");
    const a = std.testing.allocator;
    var human = try Ranger.init(a, .{});
    defer human.deinit(a);
    for (1..Profile.species_count) |i| {
        const species: Profile.Species = @enumFromInt(i);
        var hero = try Ranger.init(a, .{ .species = species, .coat = @intCast(i % Profile.coat_colors.len), .marking = 2, .clothing = .undersuit, .armor = .none, .helmet = .open });
        defer hero.deinit(a);
        // Features add geometry; no hair is left on a Wildkin.
        try std.testing.expect(hero.character.mesh.vertices.items.len > human.character.mesh.vertices.items.len / 2);
        try std.testing.expect(hero.character.palette.items.len < 256);
        for (hero.mesh.indices) |idx| try std.testing.expect(hero.character.mesh.vertices.items[idx].material != .hair);
        for (hero.mesh.vertices) |v| for (v.position ++ v.normal) |value| try std.testing.expect(std.math.isFinite(value));
        for (hero.character.mesh.vertices.items) |v| {
            var total: f32 = 0;
            for (v.weights) |w| total += w;
            try std.testing.expectApproxEqAbs(@as(f32, 1), total, 0.001);
        }
        // It walks: the gait still moves the hands.
        const hand = hero.character.skeleton.worldPos(.hand_l);
        _ = hero.update(.{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_amount = 1, .walk_phase = 1.2, .motion = .run });
        try std.testing.expect(hero.instance.pose.global[sk.Joint.hand_l.idx()].translation.sub(hand).length() > 0.05);
    }
    try std.testing.expect(winged(.eagle) and winged(.bat) and !winged(.lion));
}
