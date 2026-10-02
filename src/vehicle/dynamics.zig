//! Rigid-body dynamics: mesh mass properties (divergence theorem), parallel
//! axis composition, and a 6-DOF body with exponential-map quaternion
//! integration and gyroscopic torque.

const std = @import("std");
const m = @import("../character/math.zig");
const mesh_mod = @import("../character/mesh.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;
const Mat3 = m.Mat3;
const Mesh = mesh_mod.Mesh;

pub const MassProps = struct {
    mass: f32,
    /// Center of mass.
    com: Vec3,
    /// Inertia tensor about the COM, in the mesh's frame.
    inertia: Mat3,

    /// Combine two bodies (parallel axis theorem: I + m(|d|^2 E - d d^T)).
    pub fn combine(a: MassProps, b: MassProps) MassProps {
        const mt = a.mass + b.mass;
        if (mt <= 0) return a;
        const com = a.com.scale(a.mass / mt).add(b.com.scale(b.mass / mt));
        return .{ .mass = mt, .com = com, .inertia = shift(a, com).add(shift(b, com)) };
    }
    /// Inertia of `p` about point `o` instead of its COM.
    pub fn shift(p: MassProps, o: Vec3) Mat3 {
        const d = p.com.sub(o);
        const pa = Mat3.diag(Vec3.splat(d.dot(d))).add(Mat3.outer(d, d).scale(-1));
        return p.inertia.add(pa.scale(p.mass));
    }
    pub fn scaleMass(p: MassProps, new_mass: f32) MassProps {
        const k = if (p.mass > 0) new_mass / p.mass else 0;
        return .{ .mass = new_mass, .com = p.com, .inertia = p.inertia.scale(k) };
    }
};

/// Mass, COM and inertia of a closed, outward-wound triangle mesh with
/// uniform density. Each triangle forms a tetrahedron with the origin; the
/// second-moment (covariance) of each tet is A * C_canon * A^T * det(A),
/// with C_canon = (1/120) [[2,1,1],[1,2,1],[1,1,2]] (Blow & Binstock).
/// Duplicated vertices are fine — only triangle positions are used.
pub fn massProperties(mesh: *const Mesh, density: f32) MassProps {
    const canon = Mat3{ .m = .{ .{ 2, 1, 1 }, .{ 1, 2, 1 }, .{ 1, 1, 2 } } };
    var vol6: f64 = 0; // sum of det = 6 * volume
    var com_acc = [3]f64{ 0, 0, 0 };
    var cov = [3][3]f64{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const vs = mesh.vertices.items;
    const idx = mesh.indices.items;
    var i: usize = 0;
    while (i + 2 < idx.len) : (i += 3) {
        const a = vs[idx[i]].pos;
        const b = vs[idx[i + 1]].pos;
        const c = vs[idx[i + 2]].pos;
        // determinant in f64: big coordinates + thin parts cancel badly in f32
        const det64 = det3(a, b, c);
        const det: f32 = @floatCast(det64);
        vol6 += det64;
        const s = a.add(b).add(c); // centroid*4 (4th vertex = origin)
        com_acc[0] += det64 * s.x;
        com_acc[1] += det64 * s.y;
        com_acc[2] += det64 * s.z;
        const A = Mat3.fromColumns(a, b, c);
        const ct = A.mul(canon).mul(A.transpose()).scale(det / 120.0);
        inline for (0..3) |col| inline for (0..3) |row| {
            cov[col][row] += ct.m[col][row];
        };
    }
    if (@abs(vol6) < 1e-12) return .{ .mass = 0, .com = Vec3.zero, .inertia = Mat3.zero };
    const volume = vol6 / 6.0;
    const mass = volume * density;
    const com = Vec3.init(
        @floatCast(com_acc[0] / (vol6 * 4)),
        @floatCast(com_acc[1] / (vol6 * 4)),
        @floatCast(com_acc[2] / (vol6 * 4)),
    );
    var C: Mat3 = undefined;
    inline for (0..3) |col| inline for (0..3) |row| {
        C.m[col][row] = @floatCast(cov[col][row] * density);
    };
    // move covariance to the COM, then I = tr(C) E - C
    C = C.add(Mat3.outer(com, com).scale(-@as(f32, @floatCast(mass))));
    const I = Mat3.diag(Vec3.splat(C.trace())).add(C.scale(-1));
    return .{ .mass = @floatCast(mass), .com = com, .inertia = I };
}

fn det3(a: Vec3, b: Vec3, c: Vec3) f64 {
    const ax: f64 = a.x;
    const ay: f64 = a.y;
    const az: f64 = a.z;
    const bx: f64 = b.x;
    const by: f64 = b.y;
    const bz: f64 = b.z;
    const cx: f64 = c.x;
    const cy: f64 = c.y;
    const cz: f64 = c.z;
    return ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx);
}

// ---------------------------------------------------------------- body
pub const RigidBody = struct {
    mass: f32,
    inv_mass: f32,
    /// Body-frame inertia about the COM and its inverse.
    inertia: Mat3,
    inv_inertia: Mat3,
    /// World-space state. `pos` is the COM.
    pos: Vec3 = Vec3.zero,
    rot: Quat = Quat.identity,
    vel: Vec3 = Vec3.zero,
    /// Angular velocity, world frame.
    omega: Vec3 = Vec3.zero,
    force: Vec3 = Vec3.zero,
    torque: Vec3 = Vec3.zero,

    pub fn init(props: MassProps) RigidBody {
        return .{
            .mass = props.mass,
            .inv_mass = 1.0 / props.mass,
            .inertia = props.inertia,
            .inv_inertia = props.inertia.inverse(),
        };
    }

    /// Body-frame vector -> world.
    pub fn toWorld(b: *const RigidBody, v: Vec3) Vec3 {
        return b.rot.rotate(v);
    }
    pub fn toBody(b: *const RigidBody, v: Vec3) Vec3 {
        return b.rot.conjugate().rotate(v);
    }
    /// Body-frame point (relative to COM) -> world position.
    pub fn pointWorld(b: *const RigidBody, p_body: Vec3) Vec3 {
        return b.pos.add(b.rot.rotate(p_body));
    }
    /// Velocity of a body point: v + w x r.
    pub fn pointVelocity(b: *const RigidBody, p_world: Vec3) Vec3 {
        return b.vel.add(b.omega.cross(p_world.sub(b.pos)));
    }

    pub fn addForce(b: *RigidBody, f: Vec3) void {
        b.force = b.force.add(f);
    }
    pub fn addForceAt(b: *RigidBody, f: Vec3, p_world: Vec3) void {
        b.force = b.force.add(f);
        b.torque = b.torque.add(p_world.sub(b.pos).cross(f));
    }
    pub fn addTorque(b: *RigidBody, t: Vec3) void {
        b.torque = b.torque.add(t);
    }

    /// World-frame inverse inertia R I^-1 R^T.
    pub fn invInertiaWorld(b: *const RigidBody) Mat3 {
        const R = Mat3.fromQuat(b.rot);
        return R.mul(b.inv_inertia).mul(R.transpose());
    }

    /// Semi-implicit Euler for velocities; Euler's rigid-body equation with
    /// the gyroscopic term in the body frame:  I w' = t - w x (I w);
    /// orientation advanced with the exact exponential map of w*dt.
    pub fn integrate(b: *RigidBody, dt: f32) void {
        b.vel = b.vel.addScaled(b.force, b.inv_mass * dt);

        const w_b = b.toBody(b.omega);
        const t_b = b.toBody(b.torque);
        const gyro = w_b.cross(b.inertia.mulVec(w_b));
        const w_dot = b.inv_inertia.mulVec(t_b.sub(gyro));
        b.omega = b.toWorld(w_b.addScaled(w_dot, dt));

        b.pos = b.pos.addScaled(b.vel, dt);
        const ang = b.omega.length() * dt;
        if (ang > 1e-9) {
            b.rot = Quat.fromAxisAngle(b.omega, ang).mul(b.rot).normalize();
        }
        b.force = Vec3.zero;
        b.torque = Vec3.zero;
    }

    pub fn kineticEnergy(b: *const RigidBody) f32 {
        const w_b = b.toBody(b.omega);
        return 0.5 * b.mass * b.vel.dot(b.vel) + 0.5 * w_b.dot(b.inertia.mulVec(w_b));
    }
};

// ---------------------------------------------------------------- tests
const testing = std.testing;

fn boxMesh(gpa: std.mem.Allocator, mesh: *Mesh, h: Vec3, c: Vec3) !void {
    const base = mesh.vertexCount();
    for (0..8) |i| {
        const p = Vec3.init(
            if (i & 1 != 0) h.x else -h.x,
            if (i & 2 != 0) h.y else -h.y,
            if (i & 4 != 0) h.z else -h.z,
        );
        _ = try mesh.addVertex(gpa, .{ .pos = p.add(c) });
    }
    // outward CCW faces
    const f = [_][4]u32{ .{ 0, 2, 3, 1 }, .{ 4, 5, 7, 6 }, .{ 0, 1, 5, 4 }, .{ 2, 6, 7, 3 }, .{ 0, 4, 6, 2 }, .{ 1, 3, 7, 5 } };
    for (f) |q| try mesh.addQuad(gpa, base + q[0], base + q[1], base + q[2], base + q[3]);
}

test "box mass properties match closed form" {
    const gpa = testing.allocator;
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    const hx: f32 = 1;
    const hy: f32 = 0.5;
    const hz: f32 = 2;
    try boxMesh(gpa, &mesh, Vec3.init(hx, hy, hz), Vec3.init(3, -1, 2));
    const mp = massProperties(&mesh, 10);
    const mass: f32 = 8 * hx * hy * hz * 10;
    try testing.expectApproxEqRel(mass, mp.mass, 1e-4);
    try testing.expect(mp.com.approxEq(Vec3.init(3, -1, 2), 1e-4));
    const ixx = mass / 3 * (hy * hy + hz * hz);
    const iyy = mass / 3 * (hx * hx + hz * hz);
    try testing.expectApproxEqRel(ixx, mp.inertia.m[0][0], 1e-3);
    try testing.expectApproxEqRel(iyy, mp.inertia.m[1][1], 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 0), mp.inertia.m[0][1], 1e-3);
}

test "combine two boxes == one long box" {
    const gpa = testing.allocator;
    var a: Mesh = .{};
    defer a.deinit(gpa);
    var b: Mesh = .{};
    defer b.deinit(gpa);
    var c: Mesh = .{};
    defer c.deinit(gpa);
    try boxMesh(gpa, &a, Vec3.init(1, 1, 1), Vec3.init(-1, 0, 0));
    try boxMesh(gpa, &b, Vec3.init(1, 1, 1), Vec3.init(1, 0, 0));
    try boxMesh(gpa, &c, Vec3.init(2, 1, 1), Vec3.zero);
    const ab = massProperties(&a, 1).combine(massProperties(&b, 1));
    const cc = massProperties(&c, 1);
    try testing.expectApproxEqRel(cc.inertia.m[1][1], ab.inertia.m[1][1], 1e-4);
    try testing.expectApproxEqRel(cc.inertia.m[0][0], ab.inertia.m[0][0], 1e-4);
}

test "torque-free spin conserves energy (gyroscopic term)" {
    var b = RigidBody.init(.{ .mass = 2, .com = Vec3.zero, .inertia = Mat3.diag(Vec3.init(1, 2, 3)) });
    b.omega = Vec3.init(0.05, 0.05, 2.0);
    const e0 = b.kineticEnergy();
    for (0..2000) |_| b.integrate(1.0 / 240.0);
    // Spin about the major axis is stable: energy stays put and the spin stays near +Z.
    try testing.expectApproxEqRel(e0, b.kineticEnergy(), 0.02);
    try testing.expect(b.omega.normalize().dot(Vec3.unit_z) > 0.95);
}

test "a force at an offset point spins the body the right way" {
    var b = RigidBody.init(.{ .mass = 1, .com = Vec3.zero, .inertia = Mat3.diag(Vec3.splat(1)) });
    // Push +Z at +X: torque r x F = (1,0,0) x (0,0,1) = (0,-1,0).
    b.addForceAt(Vec3.init(0, 0, 1), Vec3.init(1, 0, 0));
    b.integrate(0.1);
    try testing.expect(b.omega.y < 0 and b.vel.z > 0);
}
