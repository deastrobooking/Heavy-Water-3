//! The player's visible body, built from scaled blocks: a stylized ranger whose proportions,
//! colors, hair, and lumen accent come from the profile. Limbs swing from hip and shoulder
//! pivots with the walk phase.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Profile = @import("Profile.zig");
const Vec3 = Physics.Vec3;

pub const max_parts = 16;
pub const Pose = struct { feet: Vec3, yaw: f32, walk_phase: f32 = 0, walk_amount: f32 = 0 };

fn shade(c: [4]f32, k: f32) [4]f32 {
    return .{ c[0] * k, c[1] * k, c[2] * k, 1 };
}

/// Appends the avatar's parts to `out` and returns how many were written.
pub fn build(profile: Profile, pose: Pose, block: Catalog.MeshHandle, out: []World.Prop) usize {
    const h = profile.height;
    const w = profile.build;
    const facing = R.axisAngle(.{ 0, 1, 0 }, pose.yaw);
    const skin = Profile.skin_tones[profile.skin];
    const hair = Profile.hair_colors[profile.hair_color];
    const outfit = Profile.outfit_colors[profile.outfit];
    const accent = Profile.accent_colors[profile.accent];
    // Accent colors glow: brighter than lit surfaces.
    const lumen = @import("../render/Material.zig").emissive(shade(accent, 1.6), 1);
    const swing = @sin(pose.walk_phase) * 0.6 * pose.walk_amount;
    var n: usize = 0;
    const Emit = struct {
        fn part(o: []World.Prop, count: *usize, mesh: Catalog.MeshHandle, feet: Vec3, q: R.Quat, center: Vec3, size: Vec3, tint: [4]f32, local: R.Quat) void {
            if (count.* == o.len) return;
            o[count.*] = .{ .mesh = mesh, .transform = .{ .position = R.add(feet, R.rotate(q, center)) }, .tint = tint, .size = size, .rotation = R.mul(q, local) };
            count.* += 1;
        }
        /// A limb hanging from `pivot`, rotated about the body's X axis by `angle`.
        fn limb(o: []World.Prop, count: *usize, mesh: Catalog.MeshHandle, feet: Vec3, q: R.Quat, pivot: Vec3, length: f32, size: Vec3, tint: [4]f32, angle: f32) void {
            const swing_q = R.axisAngle(.{ 1, 0, 0 }, angle);
            const center = R.add(pivot, R.rotate(swing_q, .{ 0, -length / 2, 0 }));
            part(o, count, mesh, feet, q, center, size, tint, swing_q);
        }
    };
    const hip = 0.9 * h;
    const shoulder = 1.42 * h;
    // Legs (darker outfit), arms (outfit) with hands implied by skin cuffs.
    for ([_]f32{ -1, 1 }) |side| {
        Emit.limb(out, &n, block, pose.feet, facing, .{ side * 0.11 * w, hip, 0 }, 0.9 * h, .{ 0.16 * w, 0.9 * h, 0.18 }, shade(outfit, 0.55), swing * side);
        Emit.limb(out, &n, block, pose.feet, facing, .{ side * 0.29 * w, shoulder, 0 }, 0.62 * h, .{ 0.12 * w, 0.62 * h, 0.14 }, outfit, -swing * side * 0.8);
    }
    // Torso, belt (lumen), head, visor (lumen).
    Emit.part(out, &n, block, pose.feet, facing, .{ 0, 1.17 * h, 0 }, .{ 0.44 * w, 0.56 * h, 0.25 }, outfit, R.identity);
    Emit.part(out, &n, block, pose.feet, facing, .{ 0, 0.93 * h, 0 }, .{ 0.46 * w, 0.06, 0.27 }, lumen, R.identity);
    const head = 1.6 * h;
    Emit.part(out, &n, block, pose.feet, facing, .{ 0, head, 0 }, .{ 0.26, 0.28, 0.26 }, skin, R.identity);
    Emit.part(out, &n, block, pose.feet, facing, .{ 0, head + 0.02, 0.135 }, .{ 0.2, 0.045, 0.02 }, lumen, R.identity);
    // Hair by style; always a cap on top.
    Emit.part(out, &n, block, pose.feet, facing, .{ 0, head + 0.15, -0.01 }, .{ 0.28, 0.06, 0.28 }, hair, R.identity);
    switch (profile.hair_style) {
        .short => {},
        .ponytail => Emit.part(out, &n, block, pose.feet, facing, .{ 0, head + 0.02, -0.19 }, .{ 0.08, 0.26, 0.08 }, hair, R.axisAngle(.{ 1, 0, 0 }, 0.35)),
        .long => Emit.part(out, &n, block, pose.feet, facing, .{ 0, head - 0.1, -0.14 }, .{ 0.28, 0.42, 0.05 }, hair, R.identity),
        .crest => Emit.part(out, &n, block, pose.feet, facing, .{ 0, head + 0.24, -0.02 }, .{ 0.06, 0.16, 0.3 }, hair, R.axisAngle(.{ 1, 0, 0 }, -0.25)),
        .hood => {
            Emit.part(out, &n, block, pose.feet, facing, .{ 0, head + 0.02, -0.05 }, .{ 0.32, 0.36, 0.3 }, shade(outfit, 0.8), R.identity);
            Emit.part(out, &n, block, pose.feet, facing, .{ 0, 1.2 * h, -0.16 }, .{ 0.5 * w, 0.7 * h, 0.04 }, shade(outfit, 0.8), R.identity);
        },
    }
    return n;
}

test "avatar parts follow profile proportions, style, and facing" {
    var p: Profile = .{};
    var parts: [max_parts]World.Prop = undefined;
    const block: Catalog.MeshHandle = .{ .index = 3, .generation = 1 };
    const base = build(p, .{ .feet = .{ 0, 0, 0 }, .yaw = 0 }, block, &parts);
    try std.testing.expectEqual(@as(usize, 9), base);
    var top: f32 = 0;
    for (parts[0..base]) |part| top = @max(top, part.transform.position[1] + part.size[1] / 2);
    try std.testing.expectApproxEqAbs(@as(f32, 1.78), top, 0.02);

    p.height = 1.1;
    p.hair_style = .hood;
    const tall = build(p, .{ .feet = .{ 5, 2, 5 }, .yaw = std.math.pi / 2.0 }, block, &parts);
    try std.testing.expectEqual(@as(usize, 11), tall);
    top = 0;
    for (parts[0..tall]) |part| top = @max(top, part.transform.position[1] + part.size[1] / 2);
    try std.testing.expect(top > 2 + 1.9);
    // Facing +X: the visor sits on the +X side of the head.
    const visor = parts[7].transform.position;
    try std.testing.expect(visor[0] > 5.1 and @abs(visor[2] - 5) < 0.01);
    // Lumen accents carry both their palette and the opaque shader emission channel.
    try std.testing.expectEqual(@as(f32, 2), parts[5].tint[3]);
    try std.testing.expect(parts[5].tint[0] > Profile.accent_colors[0][0] or parts[5].tint[2] > Profile.accent_colors[0][2]);
    // Walking swings legs in opposite directions.
    _ = build(p, .{ .feet = .{ 0, 0, 0 }, .yaw = 0, .walk_phase = std.math.pi / 2.0, .walk_amount = 1 }, block, &parts);
    try std.testing.expect(parts[0].transform.position[2] * parts[2].transform.position[2] < 0);
}
