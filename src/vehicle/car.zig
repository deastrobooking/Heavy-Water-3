//! A complete hover car from one `CarSpec`: the wedge hull, four outboard
//! ducted fans on struts, a rear downforce wing on pylons, twin nozzles and
//! light strips. `build` returns the meshes split by how they are drawn
//! (static body, one rotor to spin at every fan pivot, emissive lights)
//! plus the combined mass properties, and `flyer` turns them into a
//! `hover.HoverCar`.
//!
//! Masses come from a budget per part rather than one density, since the
//! meshes are solid shells of very different real construction.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const hull = @import("hull.zig");
const airfoil = @import("airfoil.zig");
const prims = @import("prims.zig");
const fan = @import("fan.zig");
const nozzle = @import("nozzle.zig");
const dyn = @import("dynamics.zig");
const hover = @import("hover.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Transform = m.Transform;
const Mesh = mesh_mod.Mesh;
const Allocator = std.mem.Allocator;

pub const CarSpec = struct {
    hull: hull.HullSpec = .{},
    fan: fan.FanSpec = .{},
    wing: ?airfoil.WingSpec = airfoil.WingSpec{},
    nozzle: nozzle.NozzleSpec = .{},
    /// Fan centers (car frame), front-left, front-right, rear-left, rear-right.
    pad_pos: [4]Vec3 = .{ Vec3.init(1.32, 0.42, 1.30), Vec3.init(-1.32, 0.42, 1.30), Vec3.init(1.32, 0.42, -1.25), Vec3.init(-1.32, 0.42, -1.25) },
    /// Twin nozzle exits at the tail (x = ±nozzle_x).
    nozzle_x: f32 = 0.34,
    nozzle_y: f32 = 0.56,
    /// Mass budget (kg).
    hull_mass: f32 = 820,
    fan_mass: f32 = 38,
    wing_mass: f32 = 22,
    nozzle_mass: f32 = 26,
    /// Hover tuning.
    fan_power: f32 = 300_000,
    cruise_thrust: f32 = 9_500,
    boost_thrust: f32 = 19_000,
    ride_height: f32 = 1.0,
};

pub const Parts = struct {
    /// Hull, wing and pylons, ducts, hubs, struts, nozzles: drawn as one static mesh.
    body: Mesh = .{},
    /// One rotor centered on its axis at the origin; draw it at each `pivots` entry, spinning.
    rotor: Mesh = .{},
    pivots: [4]Vec3 = undefined,
    /// Light strips, drawn emissive.
    lights: Mesh = .{},
    mass: dyn.MassProps = undefined,

    pub fn deinit(self: *Parts, gpa: Allocator) void {
        self.body.deinit(gpa);
        self.rotor.deinit(gpa);
        self.lights.deinit(gpa);
    }
};

fn partMass(mesh: *const Mesh, first_index: usize, budget: f32) dyn.MassProps {
    // Mass properties of the triangles added since `first_index`.
    const view: Mesh = .{ .vertices = mesh.vertices, .indices = .{ .items = mesh.indices.items[first_index..], .capacity = 0 } };
    const p = dyn.massProperties(&view, 1);
    return p.scaleMass(budget);
}

pub fn build(gpa: Allocator, spec: CarSpec) !Parts {
    var parts: Parts = .{};
    errdefer parts.deinit(gpa);
    const body = &parts.body;

    try hull.buildHull(gpa, body, spec.hull);
    var mass = partMass(body, 0, spec.hull_mass);

    // Outboard fans with struts back to the hull sides.
    for (spec.pad_pos, 0..) |pad, i| {
        const start = body.indices.items.len;
        const xf: Transform = .{ .translation = pad };
        try fan.buildDuct(gpa, body, spec.fan, xf);
        try fan.buildHub(gpa, body, spec.fan, xf);
        try fan.buildStruts(gpa, body, spec.fan, xf);
        const side: f32 = if (pad.x > 0) 1 else -1;
        const inner = Vec3.init(pad.x - side * (spec.fan.radius + 0.04), pad.y - 0.02, pad.z);
        const u = (pad.z / spec.hull.length) + 0.5;
        const anchor = hull.surfacePoint(spec.hull, std.math.clamp(u, 0.05, 0.95), side, 3, 0.5);
        try prims.strut(gpa, body, inner, anchor.add(Vec3.init(-side * 0.05, 0, 0)), Vec3.unit_y, 0.06, 0.05, .metal);
        mass = mass.combine(partMass(body, start, spec.fan_mass));
        parts.pivots[i] = pad;
    }

    // Rear wing on two pylons.
    if (spec.wing) |w| {
        const start = body.indices.items.len;
        try airfoil.buildWing(gpa, body, w);
        for ([_]f32{ 1, -1 }) |side| {
            const top = Vec3.init(side * w.span * 0.28, w.root_le.y - 0.02, w.root_le.z - w.root_chord * 0.5);
            const u = (top.z / spec.hull.length) + 0.5;
            const base = hull.surfacePoint(spec.hull, std.math.clamp(u, 0.02, 0.98), side, 5, 0.5);
            try prims.strut(gpa, body, base.add(Vec3.init(0, -0.05, 0)), top, Vec3.unit_z, 0.035, 0.12, .carbon);
        }
        mass = mass.combine(partMass(body, start, spec.wing_mass));
    }

    // Supercar aero detailing: a swept front splitter, floating side blades around the
    // intake panels, twin canopy spines, and a three-fin rear diffuser. These hard edges make
    // the low wedge read as a track racer instead of a smooth generic hover pod.
    const nose_l = Vec3.init(-0.92, 0.17, spec.hull.length * 0.5 - 0.08);
    const nose_r = Vec3.init(0.92, 0.17, spec.hull.length * 0.5 - 0.08);
    try prims.strut(gpa, body, nose_l, nose_r, Vec3.unit_y, 0.11, 0.075, .carbon);
    for ([_]f32{ -1, 1 }) |side| {
        try prims.strut(gpa, body, Vec3.init(side * 0.82, 0.2, spec.hull.length * 0.5 - 0.1), Vec3.init(side * 1.16, 0.24, spec.hull.length * 0.5 - 0.52), Vec3.unit_y, 0.07, 0.055, .paint_accent);
        // Two recessed louvers follow each flank and frame the fan ducts.
        for (0..2) |louver| {
            const u = 0.56 + @as(f32, @floatFromInt(louver)) * 0.055;
            const p0 = hull.surfacePoint(spec.hull, u, side, 3, 0.72);
            const p1 = hull.surfacePoint(spec.hull, u + 0.035, side, 3, 0.72);
            const normal = hull.surfaceNormal(spec.hull, u, side, 3);
            try prims.strut(gpa, body, p0.add(normal.scale(0.018)), p1.add(normal.scale(0.018)), Vec3.unit_y, 0.035, 0.025, .carbon);
        }
    }
    // Paired centerline blades sharpen the glass canopy and carry the paint accent rearward.
    for ([_]f32{ -0.12, 0.12 }) |x| {
        var spine: [5]Vec3 = undefined;
        for (&spine, 0..) |*p, i| {
            const u = 0.42 + 0.14 * @as(f32, @floatFromInt(i)) / 4;
            const roof = hull.section(spec.hull, u)[6];
            p.* = Vec3.init(x, roof.y + 0.012, roof.z);
        }
        try prims.lightStrip(gpa, body, &spine, Vec3.unit_y, 0.025, 0.012, .paint_accent);
    }
    const tail = -spec.hull.length * 0.5 + 0.12;
    for ([_]f32{ -0.44, 0, 0.44 }) |x| try prims.strut(gpa, body, Vec3.init(x, 0.17, tail), Vec3.init(x, 0.39, tail), Vec3.unit_z, 0.035, 0.04, .carbon);

    // Twin nozzles at the tail, exhausting backward (lathe +Y upstream → car +Z).
    const tail_z = -spec.hull.length * 0.5;
    for ([_]f32{ 1, -1 }) |side| {
        const start = body.indices.items.len;
        const xf: Transform = .{ .translation = Vec3.init(side * spec.nozzle_x, spec.nozzle_y, tail_z + 0.02), .rotation = Quat.fromAxisAngle(Vec3.unit_x, m.pi / 2.0) };
        try nozzle.buildNozzle(gpa, body, spec.nozzle, xf);
        mass = mass.combine(partMass(body, start, spec.nozzle_mass));
    }
    body.computeNormals();

    // One rotor at the origin; the game spins and places a copy at each pivot.
    try fan.buildRotor(gpa, &parts.rotor, spec.fan, .{});
    parts.rotor.computeNormals();

    // Light strips: shoulder crease on both sides, a nose bar and a tail bar.
    for ([_]f32{ 1, -1 }) |side| {
        var line: [7]Vec3 = undefined;
        for (&line, 0..) |*p, i| {
            const u = 0.12 + 0.8 * @as(f32, @floatFromInt(i)) / 6;
            const n = hull.surfaceNormal(spec.hull, u, side, 3);
            p.* = hull.surfacePoint(spec.hull, u, side, 3, 1).add(n.scale(0.012));
        }
        try prims.lightStrip(gpa, &parts.lights, &line, Vec3.unit_y, 0.025, 0.018, .emissive);
    }
    for ([_]f32{ 0.995, 0.005 }) |u| {
        const left = hull.surfacePoint(spec.hull, u, 1, 3, 0.5);
        const right = hull.surfacePoint(spec.hull, u, -1, 3, 0.5);
        const out: f32 = if (u > 0.5) 0.015 else -0.015;
        try prims.strut(gpa, &parts.lights, left.add(Vec3.init(-0.08, 0, out)), right.add(Vec3.init(0.08, 0, out)), Vec3.unit_y, 0.03, 0.03, .emissive);
    }
    parts.mass = mass;
    return parts;
}

/// The flyable car at `position` (its COM) facing `yaw`.
pub fn flyer(spec: CarSpec, parts: *const Parts, position: Vec3, yaw: f32) hover.HoverCar {
    var pads: [4]Vec3 = undefined;
    for (&pads, spec.pad_pos) |*p, pad| p.* = pad.sub(parts.mass.com);
    return hover.HoverCar.init(parts.mass, .{
        .pads = pads,
        .fan_radius = spec.fan.radius,
        .disk_area = spec.fan.diskArea(),
        .fan_power = spec.fan_power,
        .cruise_thrust = spec.cruise_thrust,
        .boost_thrust = spec.boost_thrust,
        .ride_height = spec.ride_height,
        // The keel sits this far below the COM.
        .skid_depth = parts.mass.com.y,
        .half_length = spec.hull.length * 0.5,
    }, position, yaw);
}

test "the car is car-sized, closed, weighs its budget, and balances" {
    const gpa = std.testing.allocator;
    var parts = try build(gpa, .{});
    defer parts.deinit(gpa);
    const bb = parts.body.bounds();
    try std.testing.expect(bb.max.z - bb.min.z > 4.5 and bb.max.z - bb.min.z < 5.5);
    try std.testing.expect(bb.max.x - bb.min.x > 3 and bb.max.x - bb.min.x < 3.6);
    // Every part is closed, so the whole body is.
    try airfoil.expectWatertight(&parts.body);
    try airfoil.expectWatertight(&parts.rotor);
    const spec: CarSpec = .{};
    const budget = spec.hull_mass + 4 * spec.fan_mass + spec.wing_mass + 2 * spec.nozzle_mass;
    try std.testing.expectApproxEqRel(budget, parts.mass.mass, 1e-3);
    // Symmetric left/right; the COM sits low between the axles.
    try std.testing.expectApproxEqAbs(@as(f32, 0), parts.mass.com.x, 0.02);
    try std.testing.expect(parts.mass.com.y > 0.2 and parts.mass.com.y < 0.8);
    try std.testing.expect(@abs(parts.mass.com.z) < 0.5);
    // Inertia is positive definite and yaw is the largest moment for a long flat car.
    const I = parts.mass.inertia;
    try std.testing.expect(I.m[0][0] > 0 and I.m[1][1] > 0 and I.m[2][2] > 0 and I.determinant() > 0);
    try std.testing.expect(I.m[1][1] > I.m[2][2]);
    try std.testing.expect(parts.lights.indices.items.len > 0);
}

test "the built car hovers over flat ground" {
    const gpa = std.testing.allocator;
    var parts = try build(gpa, .{});
    defer parts.deinit(gpa);
    var car = flyer(.{}, &parts, Vec3.init(0, 3, 0), 0);
    const Ground = struct {
        fn probe(_: *const u8, origin: Vec3, dir: Vec3, reach: f32) ?hover.Hit {
            if (dir.y > -0.5) return null;
            const d = origin.y / -dir.y;
            return if (d <= reach) .{ .distance = d, .normal = Vec3.unit_y } else null;
        }
    };
    const unused: u8 = 0;
    for (0..60 * 8) |_| car.step(1.0 / 60.0, .{}, &unused, Ground.probe);
    try std.testing.expect(car.up().y > 0.995);
    try std.testing.expectApproxEqAbs(car.cfg.skid_depth + car.cfg.ride_height, car.body.pos.y, 0.1);
}
