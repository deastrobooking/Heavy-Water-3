//! Fighter flight: a six-degree-of-freedom rigid body with real wing aerodynamics (Helmbold lift
//! slope and the stall blend from `airfoil.WingAero`), drag, sideslip and weathervaning, a main
//! engine with afterburner, and VTOL lift jets that hold a hover at low speed so the fighter
//! can rise straight off a pad and transition to wingborne flight.
//!
//! Control is mouse-aim fly-by-wire: the pilot points (the camera's aim) and the flight
//! computer turns that direction into commanded body rates: pitch the nose toward it, roll the
//! lift vector onto it when it is far off the nose, level the wings when it is close, and a
//! little yaw. A rate loop (PD on angular velocity) then commands torques whose authority grows
//! with dynamic pressure (with a floor from thrust vectoring and the lift jets).
//!
//! Body frame: +Z forward (nose), +Y up, +X left (right-handed). Rotation about +X is nose
//! down; about +Z is right side down; about +Y turns the nose left.
const std = @import("std");
const m = @import("../character/math.zig");
const dyn = @import("dynamics.zig");
const airfoil = @import("airfoil.zig");
const hover = @import("hover.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;

pub const rho = hover.rho;
pub const gravity = hover.gravity;
pub const Hit = hover.Hit;

pub const Config = struct {
    wing_area: f32 = 26,
    aero: airfoil.WingAero,
    /// Fuselage and stores: extra zero-lift drag area (Cd·A, m²).
    body_drag: f32 = 1.4,
    /// Side-force area for sideslip.
    side_area: f32 = 9,
    thrust: f32 = 58_000,
    afterburner: f32 = 95_000,
    /// Lift jets: the most they can hold, as a multiple of the weight.
    vtol: f32 = 1.25,
    /// Below `vtol_full` m/s the lift jets carry the whole weight; above `vtol_off` none.
    vtol_full: f32 = 22,
    vtol_off: f32 = 55,
    /// Maximum commanded body rates (rad/s).
    max_pitch: f32 = 1.6,
    max_roll: f32 = 3.2,
    max_yaw: f32 = 0.7,
    /// Gear contact points (body frame, from the COM) and the hull's horizontal half length.
    gear: [3]Vec3 = .{ Vec3.init(0, -1.4, 3.2), Vec3.init(1.6, -1.4, -1.2), Vec3.init(-1.6, -1.4, -1.2) },
    half_length: f32 = 7,
};

pub const Input = struct {
    /// World-space direction the pilot is pointing (normalized).
    aim: Vec3 = Vec3.unit_z,
    /// Throttle change demand (-1..1): W raises, S lowers.
    throttle: f32 = 0,
    /// Manual roll (+ rolls right) added to the fly-by-wire.
    roll: f32 = 0,
    /// Hover climb demand (-1..1) while the lift jets are working.
    climb: f32 = 0,
    afterburner: bool = false,
    /// Fly-by-wire follows `aim` only while true (otherwise it just holds attitude).
    steer: bool = true,
};

pub const Fighter = struct {
    body: dyn.RigidBody,
    cfg: Config,
    throttle: f32 = 0,
    grounded: bool = true,
    /// Hull integrity; hard landings and crashes cost it.
    hull: f32 = 300,
    /// Engine nozzle glow (0–1), for effects.
    burn: f32 = 0,
    /// The largest impact this step (m/s), for effects and damage.
    impact: f32 = 0,

    pub fn init(props: dyn.MassProps, cfg: Config, position: Vec3, yaw: f32) Fighter {
        var body = dyn.RigidBody.init(props);
        body.pos = position;
        body.rot = Quat.fromAxisAngle(Vec3.unit_y, yaw);
        return .{ .body = body, .cfg = cfg };
    }

    pub fn forward(self: *const Fighter) Vec3 {
        return self.body.toWorld(Vec3.unit_z);
    }
    pub fn up(self: *const Fighter) Vec3 {
        return self.body.toWorld(Vec3.unit_y);
    }
    pub fn heading(self: *const Fighter) f32 {
        const f = self.forward();
        return std.math.atan2(f.x, f.z);
    }
    pub fn airspeed(self: *const Fighter) f32 {
        return self.body.vel.length();
    }
    /// Angle of attack (rad): positive when the air meets the wing from below.
    pub fn alpha(self: *const Fighter) f32 {
        const vb = self.body.toBody(self.body.vel);
        return std.math.atan2(-vb.y, @max(vb.z, 0.1));
    }

    /// One fixed step. `probe(context, origin, direction, reach) ?Hit` casts a ray into the world.
    pub fn step(self: *Fighter, dt: f32, input: Input, context: anytype, comptime probe: anytype) void {
        const b = &self.body;
        const cfg = self.cfg;
        const weight = b.mass * gravity;
        const speed = b.vel.length();
        const q = 0.5 * rho * speed * speed;

        // ---- engine
        self.throttle = std.math.clamp(self.throttle + input.throttle * 0.7 * dt, 0, 1);
        const thrust = if (input.afterburner) cfg.afterburner else cfg.thrust * self.throttle;
        self.burn += ((if (input.afterburner) @as(f32, 1) else self.throttle * 0.6) - self.burn) * @min(1, dt * 6);
        b.addForce(self.forward().scale(thrust));

        // ---- aerodynamics (only meaningful with airflow)
        if (speed > 1) {
            const v_dir = b.vel.scale(1 / speed);
            const vb = b.toBody(b.vel);
            const a = std.math.atan2(-vb.y, @max(@abs(vb.z), 0.1)) * std.math.sign(vb.z + 1e-4);
            const c = cfg.aero.coefficients(a);
            const span_axis = b.toWorld(Vec3.unit_x);
            const lift_dir = v_dir.cross(span_axis).normalizeOr(self.up());
            b.addForce(lift_dir.scale(q * cfg.wing_area * c.cl));
            b.addForce(v_dir.scale(-(q * cfg.wing_area * c.cd + q * cfg.body_drag)));
            // Sideslip: a side force and a weathervane torque swinging the nose into the wind.
            const beta = std.math.atan2(vb.x, @max(@abs(vb.z), 0.1));
            b.addForce(span_axis.scale(-q * cfg.side_area * 1.2 * beta));
            b.addTorque(self.up().scale(q * cfg.side_area * 0.8 * beta));
        }

        // ---- lift jets: full hover at low speed, fading out as the wings take over
        const k = std.math.clamp((speed - cfg.vtol_full) / (cfg.vtol_off - cfg.vtol_full), 0, 1);
        // Parked on the gear, the lift jets idle until the pilot climbs.
        const engaged: f32 = if (self.grounded and input.climb <= 0) 0 else 1;
        const hover_share = (1 - k * k * (3 - 2 * k)) * engaged;
        if (hover_share > 0) {
            const up_w = self.up();
            const want = weight + b.mass * (input.climb * 6 - b.vel.y * 1.6);
            const lift = std.math.clamp(want / @max(0.4, up_w.y), 0, weight * cfg.vtol) * hover_share;
            b.addForce(up_w.scale(lift));
            // In a hover, sideways drift bleeds away; so does forward drift once the engine idles.
            // While the engine pushes, the jet accelerates freely into wingborne flight.
            const flat_fwd = Vec3.init(self.forward().x, 0, self.forward().z).normalizeOr(Vec3.unit_z);
            const drift = Vec3.init(b.vel.x, 0, b.vel.z);
            const along = flat_fwd.scale(drift.dot(flat_fwd));
            const pushing = input.afterburner or self.throttle > 0.2;
            const bleed = if (pushing) drift.sub(along) else drift;
            b.addForce(bleed.scale(-b.mass * 0.6 * hover_share));
        }
        b.addForce(Vec3.init(0, -weight, 0));

        // ---- fly-by-wire: desired body rates from the aim, then a rate loop
        const local_target = b.toBody(input.aim.normalizeOr(self.forward()));
        const local_up = b.toBody(Vec3.unit_y);
        const off = std.math.acos(std.math.clamp(local_target.z, -1, 1));
        var rate = Vec3.zero;
        if (input.steer) {
            rate.x = -std.math.atan2(local_target.y, @max(local_target.z, 0.05)) * 4;
            rate.y = std.math.atan2(local_target.x, @max(local_target.z, 0.05)) * 2;
            // Far off the nose: roll the lift vector onto the target; close: level the wings.
            const aim_roll = -std.math.atan2(local_target.x, @max(local_target.y, -0.2)) * 3;
            const level_roll = -std.math.atan2(local_up.x, local_up.y) * 2.5;
            const t = std.math.clamp((off - m.radians(6)) / m.radians(20), 0, 1);
            rate.z = m.lerp(level_roll, aim_roll, t);
        } else {
            rate.z = -std.math.atan2(local_up.x, local_up.y) * 2.5;
        }
        rate.z += input.roll * cfg.max_roll;
        rate.x = std.math.clamp(rate.x, -cfg.max_pitch, cfg.max_pitch);
        rate.y = std.math.clamp(rate.y, -cfg.max_yaw, cfg.max_yaw);
        rate.z = std.math.clamp(rate.z, -cfg.max_roll, cfg.max_roll);
        if (self.grounded) {
            // On the gear: no rolling or pitching into the ground, only taxi turns.
            rate.x = @min(rate.x, 0) * 0.3;
            rate.z = -std.math.atan2(local_up.x, local_up.y) * 4;
        }
        const w_b = b.toBody(b.omega);
        // Authority: aerodynamic surfaces scale with dynamic pressure; vectoring and the lift
        // jets give a floor so the fighter answers in a hover.
        const authority = std.math.clamp(q / 9000, 0.35, 1.5);
        const gain = 7.0 * authority;
        const torque_b = Vec3.init(
            (rate.x - w_b.x) * gain * b.inertia.m[0][0],
            (rate.y - w_b.y) * gain * b.inertia.m[1][1],
            (rate.z - w_b.z) * gain * b.inertia.m[2][2],
        );
        b.addTorque(b.toWorld(torque_b));

        // ---- gear: spring-dampers with rolling friction (brakes at low throttle)
        self.grounded = false;
        self.impact = 0;
        const down = Vec3.init(0, -1, 0);
        for (cfg.gear) |g| {
            const p = b.pointWorld(g);
            const hit = probe(context, p.add(Vec3.init(0, 2, 0)), down, 4) orelse continue;
            const depth = 2 - hit.distance;
            if (depth <= 0) continue;
            self.grounded = true;
            const v = b.pointVelocity(p);
            self.impact = @max(self.impact, -v.y);
            const normal = (depth * 9 - v.y * 1.4) * b.mass / 3 * 9.81 / 9;
            b.addForceAt(Vec3.init(0, @max(0, normal), 0), p);
            const brake: f32 = if (self.throttle < 0.15 and !input.afterburner) 0.9 else 0.08;
            b.addForceAt(Vec3.init(-v.x, 0, -v.z).scale(b.mass / 3 * brake), p);
        }

        b.integrate(dt);
        b.omega = b.omega.scale(1 / (1 + 0.4 * dt));

        // ---- hard floor and walls (a crash costs hull)
        if (probe(context, b.pos.add(Vec3.init(0, 4, 0)), down, 60)) |hit| {
            const floor = b.pos.y + 4 - hit.distance + 1.2;
            if (b.pos.y < floor) {
                if (b.vel.y < -12) self.hull -= (-b.vel.y - 12) * 6;
                b.pos.y = floor;
                if (b.vel.y < 0) b.vel.y = 0;
            }
        }
        if (speed > 0.5) {
            const dir = b.vel.scale(1 / speed);
            if (probe(context, b.pos, dir, cfg.half_length + speed * dt)) |hit| {
                if (hit.normal.y < 0.7) {
                    const into = -b.vel.dot(hit.normal);
                    if (into > 25) self.hull -= (into - 25) * 4;
                    if (into > 0) b.vel = b.vel.add(hit.normal.scale(into * 1.3));
                    if (hit.distance < cfg.half_length) b.pos = b.pos.add(hit.normal.scale(cfg.half_length - hit.distance));
                }
            }
        }
    }
};

// ---------------------------------------------------------------- tests
const testing = std.testing;

fn testFighter(position: Vec3, yaw: f32) Fighter {
    const props: dyn.MassProps = .{ .mass = 6500, .com = Vec3.zero, .inertia = m.Mat3.diag(Vec3.init(32_000, 46_000, 16_000)) };
    return Fighter.init(props, .{ .aero = airfoil.WingAero.init(airfoil.Naca4.fromDigits("2408"), 3.2) }, position, yaw);
}

const Flat = struct {
    height: f32,
    fn probe(self: *const Flat, origin: Vec3, dir: Vec3, reach: f32) ?Hit {
        if (dir.y > -0.5) return null;
        const d = (origin.y - self.height) / -dir.y;
        return if (d >= -1 and d <= reach) .{ .distance = d, .normal = Vec3.unit_y } else null;
    }
};

test "a fighter lifts off vertically on its lift jets and rests on its gear" {
    var f = testFighter(Vec3.init(0, 1.4, 0), 0);
    const ground: Flat = .{ .height = 0 };
    for (0..60 * 3) |_| f.step(1.0 / 60.0, .{}, &ground, Flat.probe);
    try testing.expect(f.grounded and f.body.pos.y < 2.2 and f.body.pos.y > 0.8);
    for (0..60 * 4) |_| f.step(1.0 / 60.0, .{ .climb = 1 }, &ground, Flat.probe);
    try testing.expect(f.body.pos.y > 10 and !f.grounded);
    try testing.expect(f.up().y > 0.98);
    try testing.expect(f.body.vel.length() < 8);
}

test "wingborne cruise: lift holds altitude at a small angle of attack, and drag caps speed" {
    var f = testFighter(Vec3.init(0, 400, 0), 0);
    f.body.vel = Vec3.init(0, 0, 150);
    f.throttle = 0.8;
    const sky: Flat = .{ .height = -1000 };
    const aim = Vec3.unit_z;
    for (0..60 * 20) |_| f.step(1.0 / 60.0, .{ .aim = aim }, &sky, Flat.probe);
    try testing.expect(@abs(f.body.pos.y - 400) < 60);
    // A cambered wing lifts at zero incidence, so a fast cruise may sit a touch below zero.
    try testing.expect(f.alpha() > m.radians(-4) and f.alpha() < m.radians(10));
    try testing.expect(f.airspeed() > 120 and f.airspeed() < 230);
    // Full afterburner levels off below a sane top speed.
    for (0..60 * 30) |_| f.step(1.0 / 60.0, .{ .aim = aim, .afterburner = true }, &sky, Flat.probe);
    try testing.expect(f.airspeed() < 300);
}

test "mouse aim: the fighter turns to fly where the pilot points" {
    var f = testFighter(Vec3.init(0, 500, 0), 0);
    f.body.vel = Vec3.init(0, 0, 150);
    f.throttle = 0.8;
    const sky: Flat = .{ .height = -1000 };
    // Point 90° to the left (+X), level.
    const aim = Vec3.unit_x;
    for (0..60 * 8) |_| f.step(1.0 / 60.0, .{ .aim = aim }, &sky, Flat.probe);
    try testing.expect(f.forward().dot(aim) > 0.95);
    try testing.expect(f.body.vel.normalize().dot(aim) > 0.85);
    // ...then back to level wings once on target.
    for (0..60 * 3) |_| f.step(1.0 / 60.0, .{ .aim = aim }, &sky, Flat.probe);
    try testing.expect(f.up().y > 0.9);
    // Pointing up on afterburner climbs.
    const before = f.body.pos.y;
    for (0..60 * 4) |_| f.step(1.0 / 60.0, .{ .aim = Vec3.init(1, 0.6, 0).normalize(), .afterburner = true }, &sky, Flat.probe);
    try testing.expect(f.body.pos.y > before + 80);
}

test "a hard crash into the ground costs hull" {
    var f = testFighter(Vec3.init(0, 40, 0), 0);
    f.body.vel = Vec3.init(0, -40, 10);
    const ground: Flat = .{ .height = 0 };
    for (0..60 * 2) |_| f.step(1.0 / 60.0, .{}, &ground, Flat.probe);
    try testing.expect(f.hull < 300);
    try testing.expect(f.body.pos.y > 0.5);
}
