//! The sun's shadow map for one view: an orthographic box around the player, looking down the
//! sun's rays, with depth reversed like the camera (1 nearest the sun, 0 farthest). Its centre
//! snaps to whole texels so shadow edges hold still while the player moves.
const std = @import("std");
const math = @import("mach").math;

/// Shadow map size in texels (square), the box's half-width across the rays, and its half-depth
/// along them (tall trees and towers well beyond the box still cast into it).
pub const size: u32 = 2048;
pub const half_width: f32 = 160;
pub const half_depth: f32 = 700;
pub const texel: f32 = 2 * half_width / @as(f32, @floatFromInt(size));
/// Below this sun height (the y of its unit direction) shadows fade out, and they are gone at 0.
pub const fade_elevation: f32 = 0.12;

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn normalize(v: [3]f32) [3]f32 {
    const l = @sqrt(dot(v, v));
    return .{ v[0] / l, v[1] / l, v[2] / l };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

/// The light's view-projection for a view centred on `center`, with `to_sun` the unit direction
/// toward the sun.
pub fn viewProjection(to_sun: [3]f32, center: [3]f32) math.Mat4x4 {
    const f = normalize(.{ -to_sun[0], -to_sun[1], -to_sun[2] });
    const reference: [3]f32 = if (@abs(f[1]) < 0.99) .{ 0, 1, 0 } else .{ 1, 0, 0 };
    const r = normalize(cross(reference, f));
    const u = cross(f, r);
    // Snap the centre across the rays to whole texels; along them it does not matter.
    const cx = @floor(dot(r, center) / texel) * texel;
    const cy = @floor(dot(u, center) / texel) * texel;
    const cz = dot(f, center);
    return math.Mat4x4.init(
        &math.vec4(r[0] / half_width, r[1] / half_width, r[2] / half_width, -cx / half_width),
        &math.vec4(u[0] / half_width, u[1] / half_width, u[2] / half_width, -cy / half_width),
        &math.vec4(-f[0] / (2 * half_depth), -f[1] / (2 * half_depth), -f[2] / (2 * half_depth), 0.5 + cz / (2 * half_depth)),
        &math.vec4(0, 0, 0, 1),
    );
}

/// The box's centre for a camera at `eye` looking along unit `forward`: pushed ahead, so the box
/// covers the ground in view rather than as much behind the player, and kept from climbing far
/// above or below the eye when looking up or down.
pub fn focus(eye: [3]f32, forward: [3]f32) [3]f32 {
    const ahead = 0.6 * half_width;
    return .{ eye[0] + forward[0] * ahead, eye[1] + std.math.clamp(forward[1], -0.6, 0.2) * ahead, eye[2] + forward[2] * ahead };
}

/// How strongly shadows show for a sun at this direction: full by day, fading out at dusk.
pub fn strength(to_sun: [3]f32) f32 {
    return std.math.clamp(to_sun[1] / fade_elevation, 0, 1);
}

fn project(m: math.Mat4x4, p: [3]f32) [3]f32 {
    const v = m.mulVec(&math.vec4(p[0], p[1], p[2], 1));
    return .{ v.x() / v.w(), v.y() / v.w(), v.z() / v.w() };
}

test "the sun's box centres on the view, keeps depth reversed, and holds still within a texel" {
    const sun = normalize(.{ 0.4, 0.8, 0.3 });
    const center: [3]f32 = .{ 1234.5, 110, -987.25 };
    const m = viewProjection(sun, center);
    const c = project(m, center);
    try std.testing.expect(@abs(c[0]) <= 2 * texel / half_width and @abs(c[1]) <= 2 * texel / half_width);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c[2], 1e-4);
    // A point toward the sun is nearer it: a larger reversed depth.
    const above = project(m, .{ center[0] + sun[0] * 50, center[1] + sun[1] * 50, center[2] + sun[2] * 50 });
    try std.testing.expect(above[2] > c[2]);
    // The box edge sits at the edge of clip space.
    const reference: [3]f32 = .{ 0, 1, 0 };
    const r = normalize(cross(reference, normalize(.{ -sun[0], -sun[1], -sun[2] })));
    const edge = project(m, .{ center[0] + r[0] * half_width, center[1] + r[1] * half_width, center[2] + r[2] * half_width });
    try std.testing.expectApproxEqAbs(@as(f32, 1), edge[0], 2 * texel / half_width);
    // Moving the view less than a texel leaves the matrix, and so every shadow edge, unchanged
    // unless it crosses a texel boundary; a fixed world point moves by whole texels only.
    const p: [3]f32 = .{ 1250, 100, -990 };
    for (0..20) |k| {
        const shift = @as(f32, @floatFromInt(k)) * 0.37;
        const moved = viewProjection(sun, .{ center[0] + shift, center[1], center[2] });
        const q = project(moved, p);
        const steps = (q[0] - project(m, p)[0]) * half_width / texel;
        try std.testing.expectApproxEqAbs(@round(steps), steps, 1e-2);
    }
}

test "the box sits ahead of the camera" {
    const at = focus(.{ 0, 100, 0 }, .{ 0, 0, 1 });
    try std.testing.expect(at[2] > 50 and at[1] == 100);
    // Looking straight down from a height, the box drops toward the ground below.
    const down = focus(.{ 0, 300, 0 }, .{ 0, -1, 0 });
    try std.testing.expect(down[1] < 300 and down[1] > 300 - half_width);
}

test "shadows fade with the sun at dusk and are gone at night" {
    try std.testing.expectEqual(@as(f32, 1), strength(.{ 0, 1, 0 }));
    try std.testing.expect(strength(normalize(.{ 1, 0.06, 0 })) < 1);
    try std.testing.expectEqual(@as(f32, 0), strength(.{ 1, -0.2, 0 }));
}
