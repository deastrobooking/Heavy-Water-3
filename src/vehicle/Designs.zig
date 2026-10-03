//! The hover car designs the player can fabricate, and their render assets. Each design is a
//! `car.CarSpec` variation; its generator meshes become render meshes with per-vertex colors
//! from the design's palette (paint, accent, glass, carbon, metal), and the catalog keeps the
//! body, the rotor and the light strips as separate meshes so the game can spin the rotors and
//! light the strips.
const std = @import("std");
const car = @import("car.zig");
const dyn = @import("dynamics.zig");
const cm = @import("../character/mesh.zig");
const m = @import("../character/math.zig");
const RenderMesh = @import("../render/Mesh.zig");

pub const Design = enum { skimmer, dart, courier };
pub const count = @typeInfo(Design).@"enum".fields.len;

pub const Palette = struct { paint: [3]f32, accent: [3]f32, lights: [3]f32 };

pub fn name(d: Design) []const u8 {
    return switch (d) {
        .skimmer => "SKIMMER",
        .dart => "DART",
        .courier => "COURIER",
    };
}

pub fn about(d: Design) []const u8 {
    return switch (d) {
        .skimmer => "Balanced wedge with a downforce wing. The canopy rangers' favourite.",
        .dart => "Short, light and fierce: small fans, a huge boost, no wing.",
        .courier => "Long hauler: big fans, a high ride and steady handling.",
    };
}

pub fn palette(d: Design) Palette {
    return switch (d) {
        .skimmer => .{ .paint = .{ 0.85, 0.32, 0.12 }, .accent = .{ 0.12, 0.13, 0.15 }, .lights = .{ 0.3, 0.95, 0.9 } },
        .dart => .{ .paint = .{ 0.92, 0.88, 0.2 }, .accent = .{ 0.08, 0.08, 0.1 }, .lights = .{ 1, 0.35, 0.6 } },
        .courier => .{ .paint = .{ 0.2, 0.42, 0.7 }, .accent = .{ 0.85, 0.85, 0.82 }, .lights = .{ 1, 0.75, 0.3 } },
    };
}

/// Handling and physical design values stay together by car so the playtest can tune each ride.
pub const tuning = .{
    .skimmer = car.CarSpec{},
    .dart = blk: {
        var s: car.CarSpec = .{};
        s.hull.length = 4.1;
        s.wing = null;
        s.fan.radius = 0.26;
        s.fan.blades = 9;
        s.pad_pos = .{ m.Vec3.init(1.22, 0.4, 1.1), m.Vec3.init(-1.22, 0.4, 1.1), m.Vec3.init(1.22, 0.4, -1.05), m.Vec3.init(-1.22, 0.4, -1.05) };
        s.hull_mass = 640;
        s.fan_mass = 30;
        s.fan_power = 260_000;
        s.cruise_thrust = 10_500;
        s.boost_thrust = 26_000;
        s.ride_height = 0.8;
        break :blk s;
    },
    .courier = blk: {
        var s: car.CarSpec = .{};
        s.hull.length = 5.4;
        s.fan.radius = 0.36;
        s.fan.blades = 6;
        s.pad_pos = .{ m.Vec3.init(1.42, 0.5, 1.6), m.Vec3.init(-1.42, 0.5, 1.6), m.Vec3.init(1.42, 0.5, -1.5), m.Vec3.init(-1.42, 0.5, -1.5) };
        s.wing.?.root_le = m.Vec3.init(0, 1.2, -2.1);
        s.wing.?.span = 2.2;
        s.hull_mass = 1050;
        s.fan_mass = 46;
        s.fan_power = 420_000;
        s.cruise_thrust = 9_000;
        s.boost_thrust = 15_000;
        s.ride_height = 1.5;
        break :blk s;
    },
};

pub fn spec(d: Design) car.CarSpec {
    return switch (d) {
        .skimmer => tuning.skimmer,
        .dart => tuning.dart,
        .courier => tuning.courier,
    };
}

fn color(material: cm.Material, p: Palette) [3]f32 {
    return switch (material) {
        .paint => p.paint,
        .paint_accent => p.accent,
        .glass => .{ 0.08, 0.16, 0.22 },
        .carbon => .{ 0.1, 0.1, 0.11 },
        .metal => .{ 0.62, 0.64, 0.66 },
        .emissive => p.lights,
        .rubber => .{ 0.05, 0.05, 0.05 },
        else => .{ 1, 1, 1 },
    };
}

/// Converts a generator mesh to a render mesh, coloring vertices by material.
pub fn renderMesh(allocator: std.mem.Allocator, source: *const cm.Mesh, p: Palette) !RenderMesh {
    const vertices = try allocator.alloc(RenderMesh.Vertex, source.vertices.items.len);
    errdefer allocator.free(vertices);
    const indices = try allocator.dupe(u32, source.indices.items);
    for (vertices, source.vertices.items) |*out, v| out.* = .{
        .position = .{ v.pos.x, v.pos.y, v.pos.z },
        .normal = .{ v.normal.x, v.normal.y, v.normal.z },
        .uv = .{ v.uv.x, v.uv.y },
        .color = color(v.material, p),
    };
    return .{ .vertices = vertices, .indices = indices };
}

/// What the simulation needs from a built design (the catalog keeps the meshes).
pub const Physical = struct { mass: dyn.MassProps, pivots: [4]m.Vec3 };

test "every design builds, converts, and can lift itself" {
    const a = std.testing.allocator;
    for (0..count) |i| {
        const d: Design = @enumFromInt(i);
        const s = spec(d);
        var parts = try car.build(a, s);
        defer parts.deinit(a);
        const body = try renderMesh(a, &parts.body, palette(d));
        defer body.deinit(a);
        try std.testing.expectEqual(parts.body.vertices.items.len, body.vertices.len);
        const flyer = car.flyer(s, &parts, m.Vec3.init(0, 2, 0), 0);
        try std.testing.expect(4 * flyer.maxFanThrust() > 1.35 * parts.mass.mass * 9.81);
    }
}
