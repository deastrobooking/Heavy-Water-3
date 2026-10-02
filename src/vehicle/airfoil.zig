//! NACA 4-digit airfoils, thin-airfoil theory, finite-wing aerodynamics
//! (Helmbold lift slope + flat-plate post-stall blend), and a swept /
//! tapered / twisted wing mesher. Used for spoilers, canards and the
//! ring-wing ducts around the hover fans.
//!
//! Conventions: airfoil-local x = chord (0 = leading edge, 1 = trailing edge),
//! y = thickness/camber up. Angles in radians.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Allocator = std.mem.Allocator;

pub const Naca4 = struct {
    /// max camber (fraction of chord), e.g. 0.02 for "2412"
    m: f32,
    /// position of max camber (fraction of chord), e.g. 0.4
    p: f32,
    /// max thickness (fraction of chord), e.g. 0.12
    t: f32,

    pub fn fromDigits(comptime code: *const [4]u8) Naca4 {
        return .{
            .m = @as(f32, @floatFromInt(code[0] - '0')) / 100.0,
            .p = @as(f32, @floatFromInt(code[1] - '0')) / 10.0,
            .t = @as(f32, @floatFromInt((code[2] - '0') * 10 + (code[3] - '0'))) / 100.0,
        };
    }

    /// Half-thickness distribution (closed trailing edge coefficient -0.1036).
    pub fn thickness(a: Naca4, x: f32) f32 {
        const sx = @sqrt(@max(x, 0));
        return 5 * a.t * (0.2969 * sx - 0.1260 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x);
    }
    pub fn camber(a: Naca4, x: f32) f32 {
        if (a.m == 0 or a.p == 0) return 0;
        if (x < a.p) return a.m / (a.p * a.p) * (2 * a.p * x - x * x);
        const q = 1 - a.p;
        return a.m / (q * q) * ((1 - 2 * a.p) + 2 * a.p * x - x * x);
    }
    pub fn camberSlope(a: Naca4, x: f32) f32 {
        if (a.m == 0 or a.p == 0) return 0;
        if (x < a.p) return 2 * a.m / (a.p * a.p) * (a.p - x);
        const q = 1 - a.p;
        return 2 * a.m / (q * q) * (a.p - x);
    }
    /// Upper/lower surface points at chord station x (thickness applied
    /// perpendicular to the camber line).
    pub fn surface(a: Naca4, x: f32) struct { upper: Vec2, lower: Vec2 } {
        const yt = a.thickness(x);
        const yc = a.camber(x);
        const th = std.math.atan(a.camberSlope(x));
        const s = @sin(th);
        const c = @cos(th);
        return .{
            .upper = .{ .x = x - yt * s, .y = yc + yt * c },
            .lower = .{ .x = x + yt * s, .y = yc - yt * c },
        };
    }

    /// Closed outline with cosine spacing (dense at LE/TE), counter-clockwise:
    /// TE -> upper -> LE -> lower -> (TE). `n` stations per side, output len 2n-2.
    pub fn outline(a: Naca4, n: usize, out: []Vec2) void {
        std.debug.assert(out.len == 2 * n - 2);
        var k: usize = 0;
        // upper surface from TE (i = n-1) to LE (i = 0)
        var i: usize = n - 1;
        while (true) : (i -= 1) {
            out[k] = a.surface(cosSpace(i, n)).upper;
            k += 1;
            if (i == 0) break;
        }
        // lower surface from just after LE to just before TE
        for (1..n - 1) |j| {
            out[k] = a.surface(cosSpace(j, n)).lower;
            k += 1;
        }
    }

    /// Thin-airfoil zero-lift angle:
    ///   alpha_L0 = -(1/pi) * integral_0^pi dyc/dx (cos t - 1) dt,  x = (1 - cos t)/2
    /// evaluated with composite Simpson's rule.
    pub fn zeroLiftAngle(a: Naca4) f32 {
        const n = 400; // even
        const h = m.pi / @as(f32, n);
        var sum: f32 = 0;
        for (0..n + 1) |i| {
            const t = @as(f32, @floatFromInt(i)) * h;
            const x = (1 - @cos(t)) / 2;
            const f = a.camberSlope(x) * (@cos(t) - 1);
            const w: f32 = if (i == 0 or i == n) 1 else if (i % 2 == 1) 4 else 2;
            sum += w * f;
        }
        return -(sum * h / 3) / m.pi;
    }
};

fn cosSpace(i: usize, n: usize) f32 {
    const b = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1)) * m.pi;
    return 0.5 * (1 - @cos(b));
}

// ---------------------------------------------------------------- aero
/// Finite-wing coefficients from aspect ratio and section.
pub const WingAero = struct {
    /// 3D lift-curve slope (per radian).
    a: f32,
    alpha0: f32,
    aspect: f32,
    /// Oswald efficiency.
    e: f32 = 0.85,
    cd0: f32 = 0.012,
    stall: f32 = m.radians(14),

    /// Helmbold's equation: valid from very low aspect ratio (spoilers,
    /// canards) up to the high-AR Prandtl limit a0 / (1 + a0/(pi AR)).
    pub fn init(section: Naca4, aspect: f32) WingAero {
        const a0 = m.tau; // thin-airfoil 2*pi per radian
        const k = a0 / (m.pi * aspect);
        return .{
            .a = a0 / (@sqrt(1 + k * k) + k),
            .alpha0 = section.zeroLiftAngle(),
            .aspect = aspect,
        };
    }

    /// Lift & drag coefficients. Attached flow below stall; blends to a
    /// flat-plate model (CL = sin 2a, CD = 2 sin^2 a) beyond it so the
    /// coefficients stay sane at any angle (sideways sliding, reversing).
    pub fn coefficients(w: WingAero, alpha: f32) struct { cl: f32, cd: f32 } {
        const ae = alpha - w.alpha0;
        const cl_lin = w.a * ae;
        const cd_lin = w.cd0 + cl_lin * cl_lin / (m.pi * w.e * w.aspect);
        const cl_fp = @sin(2 * ae);
        const cd_fp = 2 * @sin(ae) * @sin(ae) + w.cd0;
        // smooth logistic switch around the stall angle
        const s = 1.0 / (1.0 + @exp(-(@abs(ae) - w.stall) / m.radians(2)));
        return .{ .cl = m.lerp(cl_lin, cl_fp, s), .cd = m.lerp(cd_lin, cd_fp, s) };
    }
};

// ---------------------------------------------------------------- wing mesh
pub const WingSpec = struct {
    section: Naca4 = Naca4.fromDigits("4412"),
    /// Tip to tip.
    span: f32 = 1.9,
    root_chord: f32 = 0.38,
    tip_chord: f32 = 0.30,
    /// Leading-edge sweep (positive = tips further back).
    sweep: f32 = m.radians(12),
    dihedral: f32 = m.radians(-3),
    /// Incidence at root and tip (washout = tip < root).
    twist_root: f32 = m.radians(6),
    twist_tip: f32 = m.radians(3),
    /// Downforce wing (camber flipped).
    inverted: bool = true,
    /// Root leading-edge position (car frame: +Z forward, +Y up, X span).
    root_le: Vec3 = Vec3.init(0, 1.15, -1.75),
    stations: usize = 9,
    profile_points: usize = 24,
    material: mesh_mod.Material = .carbon,

    pub fn area(s: WingSpec) f32 {
        return 0.5 * (s.root_chord + s.tip_chord) * s.span;
    }
    pub fn aspect(s: WingSpec) f32 {
        return s.span * s.span / s.area();
    }
};

/// Map airfoil-local (x along chord, y up) to car frame at span station
/// eta in [-1, 1]. Incidence rotates about the quarter chord.
fn placeSection(spec: WingSpec, p: Vec2, eta: f32) Vec3 {
    const semi = spec.span * 0.5;
    const ae = @abs(eta);
    const chord = m.lerp(spec.root_chord, spec.tip_chord, ae);
    const inc0 = m.lerp(spec.twist_root, spec.twist_tip, ae);
    // a downforce wing is "nose-down" relative to the flow
    const inc = if (spec.inverted) -inc0 else inc0;
    const xc = (p.x - 0.25) * chord; // rearward from quarter chord
    const yc = (if (spec.inverted) -p.y else p.y) * chord;
    const x_r = xc * @cos(inc) + yc * @sin(inc);
    const y_r = yc * @cos(inc) - xc * @sin(inc);
    const z_le = spec.root_le.z - ae * semi * @tan(spec.sweep);
    return Vec3.init(
        eta * semi,
        spec.root_le.y + ae * semi * @tan(spec.dihedral) + y_r,
        z_le - 0.25 * chord - x_r,
    );
}

/// Mesh a full-span wing as one closed loft (tip caps included).
pub fn buildWing(gpa: Allocator, mesh: *Mesh, spec: WingSpec) !void {
    const n = spec.profile_points;
    const ring = 2 * n - 2;
    const outline = try gpa.alloc(Vec2, ring);
    defer gpa.free(outline);
    spec.section.outline(n, outline);

    const first = mesh.vertexCount();
    const st = spec.stations;
    for (0..st) |i| {
        const eta = m.lerp(-1, 1, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(st - 1)));
        for (outline, 0..) |p, k| {
            _ = try mesh.addVertex(gpa, .{
                .pos = placeSection(spec, p, eta),
                .uv = .{ .x = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(ring)), .y = (eta + 1) * 0.5 },
                .material = spec.material,
                .region = .garment,
            });
        }
    }
    // Rows run -X -> +X; mirroring the profile (inverted) reverses orientation.
    const flip = spec.inverted;
    try mesh.stitchRings(gpa, first, @intCast(st), @intCast(ring), true, flip);
    // tip caps: fan around the chord-mid point
    for ([_]usize{ 0, st - 1 }) |row| {
        const eta: f32 = if (row == 0) -1 else 1;
        const center = try mesh.addVertex(gpa, .{ .pos = placeSection(spec, .{ .x = 0.5, .y = spec.section.camber(0.5) }, eta), .material = spec.material, .region = .garment });
        const cap_flip = (row == 0) != flip;
        try mesh.capRing(gpa, first + @as(u32, @intCast(row * ring)), @intCast(ring), center, cap_flip);
    }
}

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "NACA 0012 is symmetric with zero lift at zero alpha" {
    const a = Naca4.fromDigits("0012");
    try testing.expectApproxEqAbs(@as(f32, 0), a.zeroLiftAngle(), 1e-5);
    // max thickness ~12% near x = 0.3
    try testing.expectApproxEqAbs(@as(f32, 0.06), a.thickness(0.3), 0.001);
}

test "NACA 2412 zero-lift angle matches thin-airfoil theory (~ -2.08 deg)" {
    const a = Naca4.fromDigits("2412");
    try testing.expectApproxEqAbs(@as(f32, -2.08), a.zeroLiftAngle() * 180 / m.pi, 0.05);
}

test "Helmbold slope: low AR << 2pi, high AR -> 2pi" {
    const s = Naca4.fromDigits("0012");
    try testing.expect(WingAero.init(s, 1.0).a < 1.6);
    try testing.expect(WingAero.init(s, 1000).a > 6.2);
    const w = WingAero.init(s, 5);
    // post-stall continuity: no jumps across stall
    var prev = w.coefficients(0).cl;
    var al: f32 = 0;
    while (al < 1.5) : (al += 0.01) {
        const c = w.coefficients(al).cl;
        try testing.expect(@abs(c - prev) < 0.08);
        prev = c;
    }
}

/// A closed, consistently wound mesh has positive volume that does not
/// change when translated (open or flipped patches break this).
pub fn expectWatertight(mesh: *Mesh) !void {
    const dyn = @import("dynamics.zig");
    const v0 = dyn.massProperties(mesh, 1).mass;
    try testing.expect(v0 > 0);
    for (mesh.vertices.items) |*v| v.pos = v.pos.add(Vec3.init(7, -3, 5));
    const v1 = dyn.massProperties(mesh, 1).mass;
    for (mesh.vertices.items) |*v| v.pos = v.pos.sub(Vec3.init(7, -3, 5));
    try testing.expectApproxEqRel(v0, v1, 1e-3);
}

test "wing mesh is watertight for both orientations" {
    const gpa = testing.allocator;
    for ([_]bool{ true, false }) |inv| {
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try buildWing(gpa, &mesh, .{ .inverted = inv });
        try expectWatertight(&mesh);
    }
}
