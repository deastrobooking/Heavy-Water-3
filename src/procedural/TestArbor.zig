//! A hand-authored test Arbor for measuring collision, streaming, and the look before trees
//! are generated (roadmap phase 6). Geometry is relative to the tree's origin (trunk center at
//! ground level): a tapered trunk, a spiral ramp to a branch platform at 40 m, and a 14 m
//! bridge road descending to a tower top at 36 m. One description feeds both the render mesh
//! and the colliders, so what is drawn is what is walked on.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const Vec3 = Physics.Vec3;

pub const height: f32 = 320;
/// Trunk and tower extend this far below the origin so uneven terrain never shows a gap.
pub const bury: f32 = 14;
pub const base_radius: f32 = 22;
pub const top_radius: f32 = 10;
pub const segments = 40;
pub const ring_spacing: f32 = 10;
pub const ramp_width: f32 = 4;
pub const ramp_clearance: f32 = 0.3;
pub const ramp_turns: f32 = 2.5;
pub const ramp_steps = 150;
pub const curb_height: f32 = 1.1;
pub const platform_height: f32 = 40;
pub const tower_top: f32 = 36;

pub const Box = struct { center: Vec3, half: Vec3, rotation: R.Quat, color: [3]f32 };

const bark: [3]f32 = .{ 0.36, 0.25, 0.17 };
const wood: [3]f32 = .{ 0.56, 0.41, 0.26 };
const moss: [3]f32 = .{ 0.31, 0.46, 0.26 };
const deck: [3]f32 = .{ 0.33, 0.33, 0.35 };
const tower_color: [3]f32 = .{ 0.56, 0.63, 0.70 };

pub fn trunkRadius(y: f32) f32 {
    const t = std.math.clamp(y / height, 0, 1);
    return base_radius + (top_radius - base_radius) * t;
}

/// Angle at which the ramp ends (and the platform points).
pub fn rampEndAngle() f32 {
    return ramp_turns * 2 * std.math.pi;
}

/// Fraction of the sweep over which the ramp climbs; the rest runs level at platform height
/// so the ramp meets the platform's side flush instead of arriving below its top.
pub const climb_fraction: f32 = 0.92;

/// Center line of the ramp at parameter s ∈ [0, 1].
pub fn rampPoint(s: f32) Vec3 {
    const y = @min(1, s / climb_fraction) * platform_height;
    const r = trunkRadius(y) + ramp_clearance + ramp_width / 2;
    const a = s * rampEndAngle();
    return .{ @cos(a) * r, y, @sin(a) * r };
}

/// Platform, bridge, and tower as oriented boxes.
pub fn boxes() [3]Box {
    const a = rampEndAngle();
    const out: Vec3 = .{ @cos(a), 0, @sin(a) };
    const yaw = std.math.atan2(out[0], out[2]);
    const facing = R.axisAngle(.{ 0, 1, 0 }, yaw);
    const trunk_r = trunkRadius(platform_height);
    // Platform: 30 m long along `out`, starting 2 m inside the bark, top at 40 m.
    const platform_start = trunk_r - 2;
    const platform_len: f32 = 30;
    const platform = Box{ .center = R.add(R.scale(out, platform_start + platform_len / 2), .{ 0, platform_height - 0.75, 0 }), .half = .{ 7, 0.75, platform_len / 2 }, .rotation = facing, .color = moss };
    // Bridge: 40 m from the platform end down 4 m to the tower, 14 m wide, 0.8 m thick.
    const bridge_start = platform_start + platform_len;
    const bridge_len: f32 = 40;
    const drop = platform_height - tower_top;
    const pitch = std.math.atan2(drop, bridge_len);
    const top_mid = R.add(R.scale(out, bridge_start + bridge_len / 2), .{ 0, platform_height - drop / 2, 0 });
    // Descending away from the trunk: pitch down about the box's local X axis.
    const bridge_rotation = R.mul(facing, R.axisAngle(.{ 1, 0, 0 }, pitch));
    const bridge = Box{ .center = R.sub(top_mid, R.rotate(bridge_rotation, .{ 0, 0.4, 0 })), .half = .{ 7, 0.4, @sqrt(bridge_len * bridge_len + drop * drop) / 2 }, .rotation = bridge_rotation, .color = deck };
    // Tower: 20 m square beyond the bridge, top at 36 m, buried like the trunk.
    const tower_center = R.add(R.scale(out, bridge_start + bridge_len + 10), .{ 0, (tower_top - bury) / 2, 0 });
    const tower = Box{ .center = tower_center, .half = .{ 10, (tower_top + bury) / 2, 10 }, .rotation = facing, .color = tower_color };
    return .{ platform, bridge, tower };
}

/// Trunk wall and ramp walking surface (with an outer curb) as positions and indices.
pub fn surfaces(allocator: std.mem.Allocator) !struct { trunk: Mesh, ramp: Mesh } {
    const trunk = try trunkMesh(allocator);
    errdefer trunk.deinit(allocator);
    const ramp = try rampMesh(allocator);
    return .{ .trunk = trunk, .ramp = ramp };
}

fn trunkMesh(allocator: std.mem.Allocator) !Mesh {
    const rings: usize = @intFromFloat((height + bury) / ring_spacing + 1);
    const vertices = try allocator.alloc(Mesh.Vertex, rings * (segments + 1));
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, (rings - 1) * segments * 6);
    for (0..rings) |ring| {
        const y = -bury + @as(f32, @floatFromInt(ring)) * ring_spacing;
        const r = trunkRadius(y);
        for (0..segments + 1) |i| {
            const a = @as(f32, @floatFromInt(i)) / segments * 2 * std.math.pi;
            // Bark ridges: a slight color ripple around the trunk.
            const ridge = 0.85 + 0.15 * @sin(a * 18);
            vertices[ring * (segments + 1) + i] = .{
                .position = .{ @cos(a) * r, y, @sin(a) * r },
                .normal = R.normalize(.{ @cos(a), (base_radius - top_radius) / height, @sin(a) }),
                .uv = .{ a * r / 4, y / 4 },
                .color = .{ bark[0] * ridge, bark[1] * ridge, bark[2] * ridge },
            };
        }
    }
    var n: usize = 0;
    for (0..rings - 1) |ring| for (0..segments) |i| {
        const a: u32 = @intCast(ring * (segments + 1) + i);
        const up: u32 = a + segments + 1;
        // Outward-facing (counter-clockwise seen from outside).
        for ([_]u32{ a, up, a + 1, a + 1, up, up + 1 }) |index| {
            indices[n] = index;
            n += 1;
        }
    };
    return .{ .vertices = vertices, .indices = indices };
}

fn rampMesh(allocator: std.mem.Allocator) !Mesh {
    // Per step: deck inner, deck outer, curb top.
    const vertices = try allocator.alloc(Mesh.Vertex, (ramp_steps + 1) * 3);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, ramp_steps * 12);
    for (0..ramp_steps + 1) |i| {
        const s = @as(f32, @floatFromInt(i)) / ramp_steps;
        const center = rampPoint(s);
        const a = s * rampEndAngle();
        const radial: Vec3 = .{ @cos(a), 0, @sin(a) };
        const inner = R.sub(center, R.scale(radial, ramp_width / 2));
        const outer = R.add(center, R.scale(radial, ramp_width / 2));
        const uv_v = s * rampEndAngle() * 24 / 4;
        vertices[i * 3] = .{ .position = inner, .normal = .{ 0, 1, 0 }, .uv = .{ 0, uv_v }, .color = wood };
        vertices[i * 3 + 1] = .{ .position = outer, .normal = .{ 0, 1, 0 }, .uv = .{ 1, uv_v }, .color = wood };
        vertices[i * 3 + 2] = .{ .position = R.add(outer, .{ 0, curb_height, 0 }), .normal = R.scale(radial, -1), .uv = .{ 1.3, uv_v }, .color = bark };
    }
    var n: usize = 0;
    for (0..ramp_steps) |i| {
        const b: u32 = @intCast(i * 3);
        const next = b + 3;
        // Deck (facing up: inner → next inner → outer, counter-clockwise from above), then curb
        // (a wall facing the trunk so it blocks walking off the edge).
        for ([_]u32{ b, next, b + 1, b + 1, next, next + 1, b + 1, next + 1, b + 2, b + 2, next + 1, next + 2 }) |index| {
            indices[n] = index;
            n += 1;
        }
    }
    // Keep deck triangles facing up regardless of the spiral's handedness.
    var t: usize = 0;
    while (t < 6 * ramp_steps) : (t += 6) for ([_]usize{ 0, 3 }) |k| {
        const ia = indices[t * 2 + k];
        const ib = indices[t * 2 + k + 1];
        const ic = indices[t * 2 + k + 2];
        const nrm = R.cross(R.sub(vertices[ib].position, vertices[ia].position), R.sub(vertices[ic].position, vertices[ia].position));
        if (nrm[1] < 0) std.mem.swap(u32, &indices[t * 2 + k + 1], &indices[t * 2 + k + 2]);
    };
    return .{ .vertices = vertices, .indices = indices };
}

/// Appends an oriented box with flat face normals to a render mesh builder.
fn appendBox(vertices: *std.ArrayList(Mesh.Vertex), indices: *std.ArrayList(u32), allocator: std.mem.Allocator, box: Box) !void {
    const unit = try Mesh.block(allocator);
    defer unit.deinit(allocator);
    const base: u32 = @intCast(vertices.items.len);
    for (unit.vertices) |v| {
        const local: Vec3 = .{ v.position[0] * box.half[0] * 2, v.position[1] * box.half[1] * 2, v.position[2] * box.half[2] * 2 };
        const p = R.add(box.center, R.rotate(box.rotation, local));
        try vertices.append(allocator, .{ .position = p, .normal = R.rotate(box.rotation, v.normal), .uv = .{ (p[0] + p[1]) / 4, (p[2] + p[1]) / 4 }, .color = box.color });
    }
    for (unit.indices) |i| try indices.append(allocator, base + i);
}

/// The whole test Arbor as one render mesh (vertex colors carry the materials).
pub fn renderMesh(allocator: std.mem.Allocator) !Mesh {
    const parts = try surfaces(allocator);
    defer parts.trunk.deinit(allocator);
    defer parts.ramp.deinit(allocator);
    var vertices: std.ArrayList(Mesh.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    for ([_]Mesh{ parts.trunk, parts.ramp }) |m| {
        const base: u32 = @intCast(vertices.items.len);
        try vertices.appendSlice(allocator, m.vertices);
        for (m.indices) |i| try indices.append(allocator, base + i);
    }
    for (boxes()) |box| try appendBox(&vertices, &indices, allocator, box);
    const v = try allocator.dupe(Mesh.Vertex, vertices.items);
    errdefer allocator.free(v);
    return .{ .vertices = v, .indices = try allocator.dupe(u32, indices.items) };
}

/// Coarse silhouette-only proxy for distant viewing (roadmap phase 6, LOD for tall placed
/// content): a low-segment tapered trunk with no ramp, platform, bridge, or tower detail.
pub fn lodMesh(allocator: std.mem.Allocator) !Mesh {
    const lod_segments = 8;
    const rings = [_]f32{ -bury, 0, platform_height, height };
    const vertices = try allocator.alloc(Mesh.Vertex, rings.len * (lod_segments + 1));
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, (rings.len - 1) * lod_segments * 6);
    for (rings, 0..) |y, ring| {
        const r = trunkRadius(y);
        for (0..lod_segments + 1) |i| {
            const a = @as(f32, @floatFromInt(i)) / lod_segments * 2 * std.math.pi;
            vertices[ring * (lod_segments + 1) + i] = .{
                .position = .{ @cos(a) * r, y, @sin(a) * r },
                .normal = R.normalize(.{ @cos(a), (base_radius - top_radius) / height, @sin(a) }),
                .uv = .{ a * r / 4, y / 4 },
                .color = bark,
            };
        }
    }
    var n: usize = 0;
    for (0..rings.len - 1) |ring| for (0..lod_segments) |i| {
        const a: u32 = @intCast(ring * (lod_segments + 1) + i);
        const up: u32 = a + lod_segments + 1;
        for ([_]u32{ a, up, a + 1, a + 1, up, up + 1 }) |index| {
            indices[n] = index;
            n += 1;
        }
    };
    return .{ .vertices = vertices, .indices = indices };
}

/// Creates the colliders at `origin`: trunk and ramp as meshes, the rest as oriented boxes.
/// Returns how many handles were written to `out`.
pub fn createColliders(allocator: std.mem.Allocator, physics: *Physics, origin: Vec3, user: u32, out: *[5]Physics.MeshCollider) !usize {
    const parts = try surfaces(allocator);
    defer parts.trunk.deinit(allocator);
    defer parts.ramp.deinit(allocator);
    var n: usize = 0;
    errdefer for (out[0..n]) |m| physics.destroyMesh(m);
    for ([_]Mesh{ parts.trunk, parts.ramp }) |m| {
        const positions = try allocator.alloc(Vec3, m.vertices.len);
        defer allocator.free(positions);
        for (positions, m.vertices) |*p, v| p.* = R.add(origin, v.position);
        out[n] = try physics.createMesh(allocator, positions, m.indices, user);
        n += 1;
    }
    for (boxes()) |box| {
        out[n] = try physics.createBox(allocator, R.add(origin, box.center), box.half, box.rotation, user);
        n += 1;
    }
    return n;
}

test "test Arbor geometry: ramp grade, platform and bridge heights, and faces" {
    const allocator = std.testing.allocator;
    // Ramp grade stays gentle enough to walk (under 12%).
    const a = rampPoint(0.5);
    const b = rampPoint(0.5 + 1.0 / @as(f32, ramp_steps));
    const run = @sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[2] - a[2]) * (b[2] - a[2]));
    try std.testing.expect((b[1] - a[1]) / run < 0.12);
    // The ramp ends on top of the platform.
    const end = rampPoint(1);
    try std.testing.expectApproxEqAbs(platform_height, end[1], 1e-3);
    const parts = boxes();
    try std.testing.expectApproxEqAbs(platform_height, parts[0].center[1] + parts[0].half[1], 1e-3);
    // The bridge deck's top meets the platform (40 m) and the tower (36 m).
    const bridge = parts[1];
    const near_top = R.add(bridge.center, R.rotate(bridge.rotation, .{ 0, bridge.half[1], -bridge.half[2] }));
    const far_top = R.add(bridge.center, R.rotate(bridge.rotation, .{ 0, bridge.half[1], bridge.half[2] }));
    try std.testing.expectApproxEqAbs(platform_height, near_top[1], 0.01);
    try std.testing.expectApproxEqAbs(tower_top, far_top[1], 0.01);
    try std.testing.expectApproxEqAbs(tower_top, parts[2].center[1] + parts[2].half[1], 1e-3);
    const mesh = try renderMesh(allocator);
    defer mesh.deinit(allocator);
    try std.testing.expect(mesh.vertices.len > 1000 and mesh.indices.len % 3 == 0);
    for (mesh.indices) |i| try std.testing.expect(i < mesh.vertices.len);
}

test "the LOD proxy is a much cheaper valid mesh spanning the same height" {
    const allocator = std.testing.allocator;
    const full = try renderMesh(allocator);
    defer full.deinit(allocator);
    const lod = try lodMesh(allocator);
    defer lod.deinit(allocator);
    try std.testing.expect(lod.vertices.len < full.vertices.len / 10);
    try std.testing.expect(lod.indices.len % 3 == 0);
    for (lod.indices) |i| try std.testing.expect(i < lod.vertices.len);
    var min_y: f32 = std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    for (lod.vertices) |v| {
        min_y = @min(min_y, v.position[1]);
        max_y = @max(max_y, v.position[1]);
    }
    try std.testing.expectApproxEqAbs(-bury, min_y, 1e-3);
    try std.testing.expectApproxEqAbs(height, max_y, 1e-3);
}

