//! Raycast vehicle on a rigid chassis. Each wheel casts along the chassis' down axis against every
//! solid surface; a spring-damper supports the chassis, and tire forces (drive, brake, rolling
//! resistance, lateral grip) act at the contact point, limited to a friction circle of
//! grip × load. Surface velocity is subtracted, so wheels drive on moving platforms.
//! Uses only the public physics API.
const std = @import("std");
const Physics = @import("Physics.zig");
const R = Physics.Rotation;
const Vec3 = Physics.Vec3;
const Vehicle = @This();

pub const max_wheels = 6;

pub const Wheel = struct {
    /// Suspension top, in chassis space.
    mount: Vec3,
    radius: f32,
    /// Suspension travel below the mount at full extension.
    rest: f32,
    driven: bool,
    steered: bool,
};
pub const Tuning = struct {
    stiffness: f32,
    damping: f32,
    /// Friction coefficient for the tire friction circle.
    grip: f32,
    /// Total drive force at full throttle, split across driven wheels.
    max_force: f32,
    /// Brake force per wheel at full brake.
    max_brake: f32,
    max_steer: f32,
    /// Rolling resistance as a fraction of wheel load.
    rolling: f32 = 0.02,
    /// Radians per second the steering angle can change.
    steer_rate: f32 = 2.5,
    /// Drive force fades linearly to zero at this forward speed (m/s).
    max_speed: f32 = 14,
    /// Fraction of the contact point's depth below the center of mass at which tire forces
    /// act (1 = at the contact, 0 = at center-of-mass height). Lower values resist rollover.
    roll_influence: f32 = 0.25,
};
/// Control inputs: drive and steer in −1..1 (steer positive turns right), brake in 0..1.
pub const Controls = struct { drive: f32 = 0, steer: f32 = 0, brake: f32 = 0 };
pub const WheelState = struct {
    contact: bool = false,
    /// Distance from mount to wheel center.
    extension: f32 = 0,
    load: f32 = 0,
    spin: f32 = 0,
    steer: f32 = 0,
};

rigid: Physics.Rigid,
tuning: Tuning,
wheels: [max_wheels]Wheel = undefined,
wheel_count: usize = 0,
state: [max_wheels]WheelState = @splat(.{}),
steer: f32 = 0,

pub fn init(rigid: Physics.Rigid, tuning: Tuning, wheels: []const Wheel) Vehicle {
    var self: Vehicle = .{ .rigid = rigid, .tuning = tuning, .wheel_count = wheels.len };
    @memcpy(self.wheels[0..wheels.len], wheels);
    for (wheels, 0..) |w, i| self.state[i].extension = w.rest;
    return self;
}

/// Applies suspension and tire forces for one fixed step. Call before `Physics.step`.
pub fn step(self: *Vehicle, physics: *Physics, controls: Controls, dt: f32) void {
    const pose = physics.rigidPose(self.rigid) orelse return;
    const mass = physics.rigidMass(self.rigid).?;
    const up = R.rotate(pose.orientation, .{ 0, 1, 0 });
    const down = R.scale(up, -1);
    var driven: f32 = 0;
    for (self.wheels[0..self.wheel_count]) |w| driven += @floatFromInt(@intFromBool(w.driven));
    // Rate-limited steering.
    const goal = std.math.clamp(controls.steer, -1, 1) * self.tuning.max_steer;
    self.steer += std.math.clamp(goal - self.steer, -self.tuning.steer_rate * dt, self.tuning.steer_rate * dt);

    // Suspension first, so tire forces know how many wheels share the work.
    var hits: [max_wheels]?Physics.SurfaceHit = @splat(null);
    var contacts: f32 = 0;
    for (self.wheels[0..self.wheel_count], self.state[0..self.wheel_count], 0..) |w, *s, i| {
        s.steer = if (w.steered) self.steer else 0;
        const mount = R.add(pose.position, R.rotate(pose.orientation, w.mount));
        const hit = physics.castRay(mount, down, w.rest + w.radius, self.rigid) orelse {
            s.contact = false;
            s.load = 0;
            s.extension = w.rest;
            continue;
        };
        hits[i] = hit;
        contacts += 1;
        s.contact = true;
        s.extension = hit.distance - w.radius;
        const compression = w.rest + w.radius - hit.distance;
        const mount_velocity = R.sub(physics.rigidPointVelocity(self.rigid, mount).?, hit.velocity);
        const rate = -R.dot(mount_velocity, up);
        s.load = @max(0, self.tuning.stiffness * compression + self.tuning.damping * rate);
        // Pushing along the ground normal (not the chassis axis) leaks no tangential force
        // when the chassis pitches relative to a slope.
        physics.addForceAt(self.rigid, R.scale(hit.normal, s.load), mount);
    }
    if (contacts == 0) return;

    // Static friction must cancel both the sliding velocity and gravity's pull along the
    // contact plane, or a parked vehicle creeps down slopes. Velocity is cancelled with the
    // effective mass at the contact (so forces below the center of mass do not overshoot
    // into roll); gravity with the vehicle's share of its mass.
    const gravity: Vec3 = .{ 0, Physics.gravity, 0 };
    for (self.wheels[0..self.wheel_count], self.state[0..self.wheel_count], hits[0..self.wheel_count]) |w, *s, maybe| {
        const hit = maybe orelse continue;
        const heading = R.rotate(pose.orientation, R.rotate(R.axisAngle(.{ 0, 1, 0 }, s.steer), .{ 0, 0, 1 }));
        const forward = R.normalize(R.sub(heading, R.scale(hit.normal, R.dot(heading, hit.normal))));
        const side = R.cross(hit.normal, forward);
        const velocity = R.sub(physics.rigidPointVelocity(self.rigid, hit.point).?, hit.velocity);
        const v_long = R.dot(velocity, forward);
        const v_lat = R.dot(velocity, side);
        const m_long = physics.rigidEffectiveMass(self.rigid, hit.point, forward).? / contacts;
        const m_lat = physics.rigidEffectiveMass(self.rigid, hit.point, side).? / contacts;

        const throttle = std.math.clamp(controls.drive, -1, 1);
        const speed_fade = std.math.clamp(1 - @abs(v_long) / self.tuning.max_speed, 0, 1);
        // Full force when braking against motion; faded when accelerating toward top speed.
        const fade = if (throttle * v_long < 0) 1 else speed_fade;
        var f_long: f32 = if (w.driven and driven > 0) throttle * self.tuning.max_force / driven * fade else 0;
        // Brake and rolling resistance oppose rolling, never reversing it within a step.
        const stop = v_long / dt * m_long + R.dot(gravity, forward) * mass / contacts;
        const resist = std.math.clamp(controls.brake, 0, 1) * self.tuning.max_brake + self.tuning.rolling * s.load;
        f_long -= std.math.clamp(stop, -resist, resist);
        // Lateral grip cancels sideways sliding.
        var f_lat = -(v_lat / dt * m_lat + R.dot(gravity, side) * mass / contacts);
        const limit = self.tuning.grip * s.load;
        const magnitude = @sqrt(f_long * f_long + f_lat * f_lat);
        if (magnitude > limit) {
            f_long *= limit / magnitude;
            f_lat *= limit / magnitude;
        }
        const lift = R.dot(R.sub(pose.position, hit.point), up) * (1 - self.tuning.roll_influence);
        physics.addForceAt(self.rigid, R.add(R.scale(forward, f_long), R.scale(side, f_lat)), R.add(hit.point, R.scale(up, lift)));
        s.spin += v_long / w.radius * dt;
    }
}

/// Speed along the chassis' forward axis.
pub fn forwardSpeed(self: Vehicle, physics: *const Physics) f32 {
    const pose = physics.rigidPose(self.rigid) orelse return 0;
    const v = physics.rigidVelocity(self.rigid).?.linear;
    return R.dot(v, R.rotate(pose.orientation, .{ 0, 0, 1 }));
}

/// World pose of a wheel for rendering: suspension extension, steering, and spin.
pub fn wheelPose(self: Vehicle, physics: *const Physics, index: usize) Physics.Pose {
    const pose = physics.rigidPose(self.rigid).?;
    const w = self.wheels[index];
    const s = self.state[index];
    const center = R.add(w.mount, .{ 0, -s.extension, 0 });
    const local = R.mul(R.axisAngle(.{ 0, 1, 0 }, s.steer), R.axisAngle(.{ 1, 0, 0 }, s.spin));
    return .{ .position = R.add(pose.position, R.rotate(pose.orientation, center)), .orientation = R.mul(pose.orientation, local) };
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}

/// A 20° incline rising toward +Z.
fn slope(_: ?*const anyopaque, _: f32, z: f32) Physics.GroundSample {
    const t = @tan(@as(f32, 20.0) * std.math.pi / 180.0);
    const n = R.normalize(.{ 0, 1, -t });
    return .{ .height = z * t, .normal = n };
}

const test_wheels = [_]Wheel{
    .{ .mount = .{ -1, -0.35, 1.3 }, .radius = 0.4, .rest = 0.45, .driven = true, .steered = true },
    .{ .mount = .{ 1, -0.35, 1.3 }, .radius = 0.4, .rest = 0.45, .driven = true, .steered = true },
    .{ .mount = .{ -1, -0.35, -1.3 }, .radius = 0.4, .rest = 0.45, .driven = true, .steered = false },
    .{ .mount = .{ 1, -0.35, -1.3 }, .radius = 0.4, .rest = 0.45, .driven = true, .steered = false },
};
const test_tuning: Tuning = .{ .stiffness = 9000, .damping = 1400, .grip = 1.0, .max_force = 4000, .max_brake = 3000, .max_steer = 0.5 };

fn testRover(physics: *Physics) !Vehicle {
    const rigid = try physics.createRigid(.{ .half_extents = .{ 1.1, 0.35, 1.8 }, .position = .{ 0, 1.3, 0 }, .mass = 400 });
    return init(rigid, test_tuning, &test_wheels);
}

fn drive(vehicle: *Vehicle, physics: *Physics, controls: Controls, steps: usize) void {
    for (0..steps) |_| {
        vehicle.step(physics, controls, 1.0 / 60.0);
        physics.step(1.0 / 60.0);
    }
}

test "rover settles on its suspension, accelerates straight, turns, and brakes" {
    var physics = Physics.init(.{ .sample = flatGround });
    var rover = try testRover(&physics);
    drive(&rover, &physics, .{}, 240);
    // Ride height: radius + (rest − static compression) + chassis half height.
    const static_compression = 400 * 9.81 / 4.0 / test_tuning.stiffness;
    const ride = 0.4 + 0.45 - static_compression + 0.35 - 0.35;
    try std.testing.expectApproxEqAbs(ride + 0.35, physics.rigidPose(rover.rigid).?.position[1], 0.03);
    try std.testing.expect(R.length(physics.rigidVelocity(rover.rigid).?.linear) < 0.02);
    for (rover.state[0..4]) |s| try std.testing.expect(s.contact);

    drive(&rover, &physics, .{ .drive = 1 }, 180);
    const moved = physics.rigidPose(rover.rigid).?;
    try std.testing.expect(moved.position[2] > 5);
    try std.testing.expect(@abs(moved.position[0]) < 0.3);
    try std.testing.expect(rover.forwardSpeed(&physics) > 3);

    const before = R.yaw(moved.orientation);
    drive(&rover, &physics, .{ .drive = 0.5, .steer = 1 }, 180);
    const turned = R.yaw(physics.rigidPose(rover.rigid).?.orientation);
    try std.testing.expect(@abs(turned - before) > 0.5);
    // Still upright.
    try std.testing.expect(R.rotate(physics.rigidPose(rover.rigid).?.orientation, .{ 0, 1, 0 })[1] > 0.95);

    drive(&rover, &physics, .{ .brake = 1 }, 180);
    try std.testing.expect(R.length(physics.rigidVelocity(rover.rigid).?.linear) < 0.2);
}

test "no drive input means the rover stays put, and wheels lose contact in the air" {
    var physics = Physics.init(.{ .sample = flatGround });
    var rover = try testRover(&physics);
    drive(&rover, &physics, .{ .steer = 1 }, 240);
    try std.testing.expect(@abs(physics.rigidPose(rover.rigid).?.position[2]) < 0.05);
    physics.setRigidState(rover.rigid, .{ .position = .{ 0, 10, 0 }, .orientation = R.identity }, .{ 0, 0, 0 }, .{ 0, 0, 0 });
    drive(&rover, &physics, .{}, 1);
    for (rover.state[0..4]) |s| try std.testing.expect(!s.contact);
}

test "brakes hold the rover on a 20 degree slope, sideways too; released, it rolls" {
    for ([_]R.Quat{ R.identity, R.axisAngle(.{ 0, 1, 0 }, std.math.pi / 2.0) }) |heading| {
        var physics = Physics.init(.{ .sample = slope });
        var rover = try testRover(&physics);
        physics.setRigidState(rover.rigid, .{ .position = .{ 0, 1.6, 0 }, .orientation = heading }, .{ 0, 0, 0 }, .{ 0, 0, 0 });
        drive(&rover, &physics, .{ .brake = 1 }, 240);
        const settled = physics.rigidPose(rover.rigid).?.position;
        drive(&rover, &physics, .{ .brake = 1 }, 240);
        const later = physics.rigidPose(rover.rigid).?.position;
        try std.testing.expect(R.length(R.sub(later, settled)) < 0.02);
    }
    var physics = Physics.init(.{ .sample = slope });
    var rover = try testRover(&physics);
    physics.setRigidState(rover.rigid, .{ .position = .{ 0, 1.6, 0 }, .orientation = R.identity }, .{ 0, 0, 0 }, .{ 0, 0, 0 });
    drive(&rover, &physics, .{}, 240);
    try std.testing.expect(physics.rigidPose(rover.rigid).?.position[2] < -1);
}
