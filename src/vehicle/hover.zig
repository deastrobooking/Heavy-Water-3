//! Hover physics and flight control for ducted-fan vehicles.
//!
//! Thrust comes from actuator-disk momentum theory. A ducted fan with
//! exit-area ratio sigma needs ideal power
//!   P = T^1.5 / sqrt(4 rho A sigma)
//! so a power limit gives each fan's maximum thrust
//!   T_max = (P_max * sqrt(4 rho A sigma))^(2/3).
//! Near the ground the Cheeseman–Bennett correction raises thrust at equal
//! power:  T_ige / T_oge = 1 / (1 - (R / 4z)^2), clamped.
//!
//! The flight computer holds a ride height over whatever is below (or the
//! last known altitude over a gap, sinking slowly). It levels the body with
//! PD control mixed into per-fan thrust, yaws with differential vane torque,
//! and drives forward with the rear nozzles. Contacts are a spring-damper
//! "skid" at each fan pad plus a wall probe along the velocity, so the
//! module needs only a `probe` (ray cast) from its caller.

const std = @import("std");
const m = @import("../character/math.zig");
const dyn = @import("dynamics.zig");
const Vec3 = m.Vec3;
const Quat = m.Quat;

pub const rho: f32 = 1.225;
pub const gravity: f32 = 9.81;

/// Ideal induced velocity at the disk for thrust `t` (N) over disk area `a` (m²).
pub fn inducedVelocity(t: f32, a: f32) f32 {
    return @sqrt(@max(t, 0) / (2 * rho * a));
}

/// Ideal power for thrust `t` from a ducted fan of disk area `a` and exit-area ratio `sigma`.
pub fn ductedPower(t: f32, a: f32, sigma: f32) f32 {
    return std.math.pow(f32, @max(t, 0), 1.5) / @sqrt(4 * rho * a * sigma);
}

/// The thrust a power budget buys (inverse of `ductedPower`).
pub fn thrustForPower(p: f32, a: f32, sigma: f32) f32 {
    return std.math.pow(f32, @max(p, 0) * @sqrt(4 * rho * a * sigma), 2.0 / 3.0);
}

/// Ground-effect thrust multiplier at height `z` above the ground for rotor radius `r`.
pub fn groundEffect(z: f32, r: f32) f32 {
    const k = r / (4 * @max(z, r * 0.3));
    return @min(1.6, 1 / (1 - k * k));
}

pub const Hit = struct { distance: f32, normal: Vec3 };
/// Local road frame for magnetically guided stunts such as vertical loop sections.
pub const TrackFrame = struct { center: Vec3, tangent: Vec3, up: Vec3, radius: f32 = 0 };

pub const Input = struct {
    /// Forward (+) / reverse (-) thrust demand.
    forward: f32 = 0,
    /// Yaw rate demand, + turns left (counter-clockwise from above).
    turn: f32 = 0,
    /// Sideways drift demand, + is to the car's right.
    strafe: f32 = 0,
    /// Ride height adjust: + climbs, - descends.
    lift: f32 = 0,
    boost: bool = false,
    /// Set only while inside a generated stunt section; regular flight remains free-flight.
    track_frame: ?TrackFrame = null,
};

pub const Config = struct {
    /// Fan pads relative to the COM, body frame (+Z forward, +Y up).
    pads: [4]Vec3,
    fan_radius: f32,
    disk_area: f32,
    /// Duct exit-area ratio.
    sigma: f32 = 1.15,
    /// Shaft power per fan (W). Momentum theory is unforgiving for small ducts: four 0.6 m fans
    /// need about 280 kW each to lift a 1.1 t car with margin, and climbing hard takes more,
    /// which the fusion cells supply.
    fan_power: f32 = 300_000,
    /// Rear nozzle thrust (N) at full forward, and with boost.
    cruise_thrust: f32 = 9_000,
    boost_thrust: f32 = 18_000,
    /// A full capacitor sustains boost for this long; passive recharge is slower than pad recharge.
    boost_duration: f32 = 2.8,
    boost_recharge_time: f32 = 7.0,
    ride_height: f32 = 1.1,
    min_ride: f32 = 0.5,
    max_ride: f32 = 6,
    /// Probe reach below the pads; beyond it the car holds altitude.
    probe_reach: f32 = 30,
    /// Lowest point of the body below the COM (for wall probes and skids).
    skid_depth: f32 = 0.45,
    /// Horizontal half-length of the body (wall probe reach).
    half_length: f32 = 2.4,
    /// Turn rate at full input (rad/s) and the max lean into a manoeuvre.
    turn_rate: f32 = 1.6,
    max_lean: f32 = m.radians(14),
    /// Quadratic drag area (Cd·A). Large because it includes the fans' ram drag: four ducts
    /// swallowing air at speed. It caps a cruising car near 30 m/s and a boosting one near 45.
    drag_area: f32 = 16,
    side_grip: f32 = 2.2,
};

/// Each pad's share of the lift so the shares balance about the COM: front and rear split by
/// their lever arms, left and right likewise. A car with its COM aft of center (nozzles and a
/// wing at the tail) needs more rear thrust just to hang level.
pub fn liftShares(pads: [4]Vec3) [4]f32 {
    var front: f32 = 0;
    var rear: f32 = 0;
    var left: f32 = 0;
    var right: f32 = 0;
    for (pads) |p| {
        if (p.z >= 0) front += p.z else rear -= p.z;
        if (p.x >= 0) left += p.x else right -= p.x;
    }
    var shares: [4]f32 = undefined;
    for (pads, &shares) |p, *w| {
        const along = if (p.z >= 0) rear / @max(front + rear, 1e-3) else front / @max(front + rear, 1e-3);
        const across = if (p.x >= 0) right / @max(left + right, 1e-3) else left / @max(left + right, 1e-3);
        w.* = along * across;
    }
    return shares;
}

pub const HoverCar = struct {
    body: dyn.RigidBody,
    cfg: Config,
    /// Altitude the computer is holding (world Y of the COM).
    target_altitude: f32 = 0,
    ride: f32 = 0,
    /// Per-fan commanded thrust (N), for effects and tests.
    thrust: [4]f32 = @splat(0),
    /// Rotor angle (rad) for rendering spinning blades.
    rotor_angle: f32 = 0,
    grounded: bool = false,
    boost_charge: f32 = 1,
    boost_active: bool = false,
    /// Integrated attitude error (trim), clamped.
    trim_x: f32 = 0,
    trim_z: f32 = 0,

    pub fn init(props: dyn.MassProps, cfg: Config, position: Vec3, yaw: f32) HoverCar {
        var body = dyn.RigidBody.init(props);
        body.pos = position;
        body.rot = Quat.fromAxisAngle(Vec3.unit_y, yaw);
        return .{ .body = body, .cfg = cfg, .target_altitude = position.y, .ride = cfg.ride_height };
    }

    pub fn maxFanThrust(self: *const HoverCar) f32 {
        return thrustForPower(self.cfg.fan_power, self.cfg.disk_area, self.cfg.sigma);
    }

    pub fn forward(self: *const HoverCar) Vec3 {
        return self.body.toWorld(Vec3.unit_z);
    }
    pub fn up(self: *const HoverCar) Vec3 {
        return self.body.toWorld(Vec3.unit_y);
    }
    /// Heading (yaw about +Y), 0 facing +Z.
    pub fn heading(self: *const HoverCar) f32 {
        const f = self.forward();
        return std.math.atan2(f.x, f.z);
    }

    /// One fixed step. `probe(context, origin, direction, reach) ?Hit` casts a ray into the world.
    pub fn step(self: *HoverCar, dt: f32, input: Input, context: anytype, comptime probe: anytype) void {
        const b = &self.body;
        const cfg = self.cfg;
        const body_up = self.up();
        const track = input.track_frame;
        const up_w = if (track) |frame| frame.up else body_up;
        const fwd = self.forward();
        // Right-handed body frame: +X is the car's left, so right = forward × track-up.
        const right = fwd.cross(up_w).normalizeOr(Vec3.unit_x.neg());
        const down = Vec3.init(0, -1, 0);

        // Ground below each pad. Rays start 2 m up, so a pad that dips into a slope still finds
        // the surface (its height is then negative, and the skids push back).
        const lift_off: f32 = 2;
        var ground_sum: f32 = 0;
        var ground_count: f32 = 0;
        var pad_height: [4]?f32 = @splat(null);
        if (track == null) {
            for (cfg.pads, 0..) |pad, i| {
                const p = b.pointWorld(pad);
                if (probe(context, p.add(Vec3.init(0, lift_off, 0)), down, cfg.probe_reach + lift_off)) |hit| {
                    pad_height[i] = hit.distance - lift_off;
                    ground_sum += p.y - (hit.distance - lift_off);
                    ground_count += 1;
                }
            }
        }
        // Look ahead along the horizontal velocity: climb before a rising slope arrives.
        var ahead_ground: ?f32 = null;
        const flat_v = Vec3.init(b.vel.x, 0, b.vel.z);
        if (track == null and flat_v.length() > 3) {
            const look = b.pos.add(flat_v.scale(0.9)).add(Vec3.init(0, lift_off + 1, 0));
            if (probe(context, look, down, cfg.probe_reach + lift_off + 1)) |hit| ahead_ground = look.y - hit.distance;
        }
        self.ride = std.math.clamp(self.ride + input.lift * 2.5 * dt, cfg.min_ride, cfg.max_ride);
        if (ground_count > 0) {
            var ground = ground_sum / ground_count;
            if (ahead_ground) |a| ground = @max(ground, a);
            self.target_altitude = ground + cfg.skid_depth + self.ride;
        } else {
            // Over a gap: hold altitude, sinking gently so the car comes down eventually.
            self.target_altitude -= 0.6 * dt;
        }

        // Lift: hold altitude (PD) plus weight, divided over the tilt.
        const weight = b.mass * gravity;
        const height_error = self.target_altitude - b.pos.y;
        const climb = std.math.clamp(height_error * 5.0 - b.vel.y * 3.2, -6, 14);
        const lift_total = if (track == null) (weight + b.mass * climb) / @max(0.5, up_w.y) else 0;

        const kp = 9.0;
        const kd = 3.2;
        var tau_x: f32 = 0;
        var tau_z: f32 = 0;
        if (track) |frame| {
            // Match both the track normal and tangent. Aligning only the normal leaves a 180°
            // ambiguity at the loop crown, where the car could point backward after flipping.
            var delta = Quat.lookRotation(frame.tangent, frame.up).mul(b.rot.conjugate()).normalize();
            if (delta.w < 0) delta = .{ .x = -delta.x, .y = -delta.y, .z = -delta.z, .w = -delta.w };
            const rotation_error = Vec3.init(delta.x, delta.y, delta.z).scale(2);
            b.addTorque(rotation_error.scale(kp * b.inertia.m[1][1]).sub(b.omega.scale(kd * b.inertia.m[1][1])));
        } else {
            // Attitude from world up. Lean into acceleration, strafing, and turns.
            const local_up = b.toBody(Vec3.unit_y);
            const theta_x = std.math.atan2(-local_up.z, local_up.y);
            const theta_z = std.math.atan2(local_up.x, local_up.y);
            const speed_factor = std.math.clamp(b.vel.dot(fwd) / 20, -1, 1);
            const target_x = input.forward * cfg.max_lean * 0.5;
            const target_z = input.strafe * cfg.max_lean - input.turn * cfg.max_lean * 0.4 * speed_factor;
            const w_b = b.toBody(b.omega);
            self.trim_x = std.math.clamp(self.trim_x + (theta_x - target_x) * dt, -0.3, 0.3);
            self.trim_z = std.math.clamp(self.trim_z + (theta_z - target_z) * dt, -0.3, 0.3);
            const ki = 3.0;
            tau_x = (-kp * (theta_x - target_x) - ki * self.trim_x - kd * w_b.x) * b.inertia.m[0][0];
            tau_z = (-kp * (theta_z - target_z) - ki * self.trim_z - kd * w_b.z) * b.inertia.m[2][2];
        }
        const shares = liftShares(cfg.pads);

        // Mix into the four fans. Thrust T along body up at pad (x, z) gives torque
        // (-z·T) about X and (x·T) about Z, so each pad takes its share of both.
        const t_max = self.maxFanThrust();
        for (cfg.pads, 0..) |pad, i| {
            const lz = @max(@abs(pad.z), 0.1);
            const lx = @max(@abs(pad.x), 0.1);
            // Pairs of pads share each torque; with two pads per side, each takes a quarter.
            var t = lift_total * shares[i];
            t += -std.math.sign(pad.z) * tau_x / (4 * lz);
            t += std.math.sign(pad.x) * tau_z / (4 * lx);
            const ge = if (pad_height[i]) |h| groundEffect(h, cfg.fan_radius) else 1;
            t = std.math.clamp(t, 0, t_max * ge);
            self.thrust[i] = t;
            b.addForceAt(up_w.scale(t), b.pointWorld(pad));
        }

        // Yaw: vane torque toward the demanded turn rate.
        const yaw_rate = b.omega.dot(up_w);
        const yaw_target = input.turn * cfg.turn_rate;
        b.addTorque(up_w.scale((yaw_target - yaw_rate) * 4.0 * b.inertia.m[1][1]));

        // Propulsion: rear nozzles push along the heading, flattened to the horizontal.
        const flat_fwd = Vec3.init(fwd.x, 0, fwd.z).normalizeOr(Vec3.unit_z);
        self.boost_active = input.boost and input.forward > 0 and self.boost_charge > 0;
        if (self.boost_active) {
            self.boost_charge = @max(0, self.boost_charge - dt / cfg.boost_duration);
        } else if (!input.boost or input.forward <= 0) {
            self.boost_charge = @min(1, self.boost_charge + dt / cfg.boost_recharge_time);
        }
        const thrust = if (self.boost_active) cfg.boost_thrust else cfg.cruise_thrust;
        b.addForce((if (track != null) fwd else flat_fwd).scale(input.forward * thrust));
        b.addForce(right.scale(input.strafe * cfg.cruise_thrust * 0.5));

        // Aerodynamic drag and sideslip grip (the ducts act like keels).
        const speed = b.vel.length();
        if (speed > 1e-3) b.addForce(b.vel.scale(-0.5 * rho * cfg.drag_area * speed));
        const side_speed = b.vel.dot(right);
        b.addForce(right.scale(-side_speed * cfg.side_grip * b.mass * (1 - @abs(input.strafe))));
        // Gravity.
        b.addForce(Vec3.init(0, -weight, 0));

        // Magnetic guide force supplies both centripetal acceleration and adhesion on the
        // inverted half of a loop. Lateral/normal PD pulls toward the road ribbon while leaving
        // the driver's velocity along the track free. The signed normal term can pull as well as
        // push, which ordinary hover fans cannot do once the car is upside down.
        if (track) |frame| {
            const target = frame.center.add(frame.up.scale(cfg.skid_depth + self.ride));
            const offset_error = target.sub(b.pos);
            const tangent_error = offset_error.sub(frame.tangent.scale(offset_error.dot(frame.tangent)));
            const tangent_speed = b.vel.dot(frame.tangent);
            const lateral_velocity = b.vel.sub(frame.tangent.scale(tangent_speed));
            var accel = tangent_error.scale(14).sub(lateral_velocity.scale(8));
            const curvature_accel = if (frame.radius > 0) tangent_speed * tangent_speed / frame.radius else 0;
            const normal_accel = std.math.clamp(curvature_accel + gravity * frame.up.y, -80, 100);
            accel = accel.add(frame.up.scale(normal_accel));
            const accel_len = accel.length();
            if (accel_len > 140) accel = accel.scale(140 / accel_len);
            b.addForce(accel.scale(b.mass));
        }

        // Skids: a stiff spring-damper wherever a pad would dip below the ground.
        self.grounded = track != null;
        for (cfg.pads, 0..) |pad, i| {
            const h = pad_height[i] orelse continue;
            const gap = h - cfg.skid_depth * 0.5;
            if (gap < 0) {
                self.grounded = true;
                const p = b.pointWorld(pad);
                const v = b.pointVelocity(p).y;
                b.addForceAt(Vec3.init(0, (-gap * 60 - v * 6) * b.mass / 4, 0), p);
            }
        }

        b.integrate(dt);
        // Angular damping keeps the airframe calm.
        b.omega = b.omega.scale(1 / (1 + 1.5 * dt));

        // Hard floor: the keel never goes through the ground, whatever the speed. Springs alone
        // cannot stop a tonne at 40 m/s meeting a crest.
        if (track == null) {
            if (probe(context, b.pos.add(Vec3.init(0, 3, 0)), down, cfg.probe_reach + 3)) |hit| {
                const floor = b.pos.y + 3 - hit.distance + cfg.skid_depth * 0.8;
                if (b.pos.y < floor) {
                    b.pos.y = floor;
                    if (b.vel.y < 0) b.vel.y = 0;
                    self.grounded = true;
                }
            }
        }

        // Walls: probe along the horizontal velocity; stop the component into the wall.
        const flat_vel = Vec3.init(b.vel.x, 0, b.vel.z);
        const flat_speed = flat_vel.length();
        if (track == null and flat_speed > 0.05) {
            const dir = flat_vel.scale(1 / flat_speed);
            const reach = cfg.half_length + flat_speed * dt;
            if (probe(context, b.pos, dir, reach)) |hit| {
                if (hit.normal.y < 0.6) {
                    const into = b.vel.dot(hit.normal);
                    if (into < 0) b.vel = b.vel.sub(hit.normal.scale(into * 1.3));
                    if (hit.distance < cfg.half_length) b.pos = b.pos.add(hit.normal.scale(cfg.half_length - hit.distance));
                }
            }
        }

        const total = self.thrust[0] + self.thrust[1] + self.thrust[2] + self.thrust[3];
        self.rotor_angle = @mod(self.rotor_angle + dt * (20 + total / @max(t_max * 4, 1) * 80), m.tau);
    }
};

// ---------------------------------------------------------------- tests
const testing = std.testing;

test "lift shares balance about the COM for an aft-heavy layout" {
    const pads = [4]Vec3{ Vec3.init(1, 0, 1.7), Vec3.init(-1, 0, 1.7), Vec3.init(1, 0, -0.8), Vec3.init(-1, 0, -0.8) };
    const w = liftShares(pads);
    var total: f32 = 0;
    var moment_z: f32 = 0;
    var moment_x: f32 = 0;
    for (pads, w) |p, s| {
        total += s;
        moment_z += s * p.z;
        moment_x += s * p.x;
    }
    try testing.expectApproxEqAbs(@as(f32, 1), total, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0), moment_z, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0), moment_x, 1e-5);
    try testing.expect(w[2] > w[0]);
}

test "momentum theory: induced velocity, power, and its inverse" {
    // T = 1000 N over 1 m²: v = sqrt(1000 / (2 · 1.225)) ≈ 20.2 m/s.
    try testing.expectApproxEqAbs(@as(f32, 20.2), inducedVelocity(1000, 1), 0.05);
    // An open rotor (sigma = 0.5) needs P = T·v_i.
    try testing.expectApproxEqRel(1000 * inducedVelocity(1000, 1), ductedPower(1000, 1, 0.5), 1e-4);
    try testing.expectApproxEqRel(@as(f32, 4321), thrustForPower(ductedPower(4321, 0.3, 1.1), 0.3, 1.1), 1e-3);
    // A duct (sigma 1) buys more thrust than an open rotor for the same power.
    try testing.expect(thrustForPower(50_000, 0.25, 1.0) > thrustForPower(50_000, 0.25, 0.5));
}

test "ground effect boosts thrust near the ground and fades away" {
    try testing.expect(groundEffect(0.3, 0.3) > 1.05);
    try testing.expectApproxEqAbs(@as(f32, 1), groundEffect(20, 0.3), 1e-3);
    try testing.expect(groundEffect(0.01, 0.3) <= 1.6);
}

const Flat = struct {
    height: f32,
    wall_z: ?f32 = null,
    fn probe(self: *const Flat, origin: Vec3, dir: Vec3, reach: f32) ?Hit {
        if (dir.y < -0.5) {
            const d = (origin.y - self.height) / -dir.y;
            return if (d >= -1 and d <= reach) .{ .distance = d, .normal = Vec3.unit_y } else null;
        }
        if (self.wall_z) |z| if (dir.z > 0.1) {
            const d = (z - origin.z) / dir.z;
            return if (d >= 0 and d <= reach) .{ .distance = d, .normal = Vec3.init(0, 0, -1) } else null;
        };
        return null;
    }
};

fn testCar(position: Vec3) HoverCar {
    const props: dyn.MassProps = .{ .mass = 1100, .com = Vec3.zero, .inertia = m.Mat3.diag(Vec3.init(2100, 2600, 900)) };
    return HoverCar.init(props, .{
        .pads = .{ Vec3.init(1.2, -0.2, 1.4), Vec3.init(-1.2, -0.2, 1.4), Vec3.init(1.2, -0.2, -1.4), Vec3.init(-1.2, -0.2, -1.4) },
        .fan_radius = 0.3,
        .disk_area = 0.26,
    }, position, 0);
}

test "the car settles level at its ride height and can lift its weight" {
    var car = testCar(Vec3.init(0, 4, 0));
    const ground: Flat = .{ .height = 0 };
    try testing.expect(4 * car.maxFanThrust() > 1.4 * car.body.mass * gravity);
    for (0..60 * 8) |_| car.step(1.0 / 60.0, .{}, &ground, Flat.probe);
    const expected = car.cfg.skid_depth + car.cfg.ride_height;
    try testing.expectApproxEqAbs(expected, car.body.pos.y, 0.08);
    try testing.expect(car.up().y > 0.995);
    try testing.expect(car.body.vel.length() < 0.1);
    for (car.thrust) |t| try testing.expect(t > 0);
}

test "forward drives along the heading, turning yaws, and walls stop it" {
    var car = testCar(Vec3.init(0, 1.6, 0));
    const ground: Flat = .{ .height = 0 };
    for (0..60 * 3) |_| car.step(1.0 / 60.0, .{ .forward = 1 }, &ground, Flat.probe);
    try testing.expect(car.body.pos.z > 8 and @abs(car.body.pos.x) < 0.5);
    const before = car.heading();
    for (0..60) |_| car.step(1.0 / 60.0, .{ .turn = 1 }, &ground, Flat.probe);
    try testing.expect(car.heading() > before + 0.6);

    var walled = testCar(Vec3.init(0, 1.6, 0));
    const box: Flat = .{ .height = 0, .wall_z = 15 };
    for (0..60 * 6) |_| walled.step(1.0 / 60.0, .{ .forward = 1, .boost = true }, &box, Flat.probe);
    try testing.expect(walled.body.pos.z < 15);
}

test "drag caps cruise and boost speeds" {
    var car = testCar(Vec3.init(0, 1.6, 0));
    const ground: Flat = .{ .height = 0 };
    for (0..60 * 20) |_| car.step(1.0 / 60.0, .{ .forward = 1 }, &ground, Flat.probe);
    const cruise = car.body.vel.length();
    for (0..60 * 3) |_| car.step(1.0 / 60.0, .{ .forward = 1, .boost = true }, &ground, Flat.probe);
    const boost = car.body.vel.length();
    try testing.expect(cruise > 20 and cruise < 35);
    try testing.expect(boost > cruise + 5 and boost < 50);
    try testing.expectEqual(@as(f32, 0), car.boost_charge);
    for (0..60 * 7) |_| car.step(1.0 / 60.0, .{ .forward = 1 }, &ground, Flat.probe);
    try testing.expect(car.boost_charge > 0.95);
}

test "a fast car follows rolling ground without losing it" {
    var car = testCar(Vec3.init(0, 1.6, 0));
    const Hills = struct {
        fn height(z: f32) f32 {
            return 6 * @sin(z / 25);
        }
        fn probe(_: *const u8, origin: Vec3, dir: Vec3, reach: f32) ?Hit {
            if (dir.y > -0.5) return null;
            const d = origin.y - height(origin.z);
            return if (d >= 0 and d <= reach) .{ .distance = d, .normal = Vec3.unit_y } else null;
        }
    };
    const unused: u8 = 0;
    var lowest: f32 = 100;
    for (0..60 * 15) |_| {
        car.step(1.0 / 60.0, .{ .forward = 1, .boost = true }, &unused, Hills.probe);
        lowest = @min(lowest, car.body.pos.y - Hills.height(car.body.pos.z));
    }
    try testing.expect(car.body.pos.z > 200);
    // The COM never sinks to the ground.
    try testing.expect(lowest > 0.3);
}

test "over a gap the car holds altitude and sinks slowly instead of falling" {
    var car = testCar(Vec3.init(0, 30, 0));
    const none: Flat = .{ .height = -1000 };
    for (0..60 * 2) |_| car.step(1.0 / 60.0, .{}, &none, Flat.probe);
    try testing.expect(car.body.pos.y > 27.5 and car.body.pos.y < 30.2);
}

test "magnetic track guidance holds an inverted racer through the loop crown" {
    var car = testCar(Vec3.init(0, -1.1, 0));
    const none: Flat = .{ .height = -1000 };
    const inverted: TrackFrame = .{
        .center = Vec3.zero,
        .tangent = Vec3.unit_z,
        .up = Vec3.init(0, -1, 0),
        .radius = 19,
    };
    for (0..60 * 5) |_| car.step(1.0 / 60.0, .{ .track_frame = inverted }, &none, Flat.probe);
    try testing.expect(car.up().y < -0.95);
    try testing.expectApproxEqAbs(@as(f32, -1.1), car.body.pos.y, 0.5);
    try testing.expect(car.grounded);
}
