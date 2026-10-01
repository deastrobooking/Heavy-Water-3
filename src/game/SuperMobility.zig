//! Super-mobility mechanics: Sonic-style fast dash, Superman/DBZ 3D aerial flight,
//! charged high-altitude flying jumps, and shadow-strike warp teleportation.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Camera = @import("../world/Camera.zig");
const Input = @import("../engine/Input.zig");

pub const FlightState = struct {
    active: bool = false,
    boost: bool = false,
    hover: bool = false,
    speed: f32 = 0,
    cruise_speed: f32 = 24.0,
    boost_speed: f32 = 48.0,
    acceleration: f32 = 35.0,
    energy: f32 = 100.0,
    max_energy: f32 = 100.0,

    pub fn toggle(self: *FlightState) void {
        self.active = !self.active;
        if (!self.active) {
            self.boost = false;
            self.hover = false;
        }
    }

    pub fn update(
        self: *FlightState,
        feet: *V,
        velocity: *V,
        cam_forward: V,
        cam_right: V,
        cam_up: V,
        input_fwd: f32,
        input_right: f32,
        input_up: f32,
        is_fast: bool,
        dt: f32,
    ) void {
        if (!self.active) {
            self.energy = @min(self.max_energy, self.energy + 20.0 * dt);
            return;
        }

        self.boost = is_fast and (self.energy > 5.0);
        const target_speed = if (self.boost) self.boost_speed else self.cruise_speed;

        if (self.boost) {
            self.energy = @max(0, self.energy - 15.0 * dt);
            if (self.energy == 0) self.boost = false;
        } else {
            self.energy = @min(self.max_energy, self.energy + 8.0 * dt);
        }

        // 3D Direction vector from camera orientation
        var wish = R.add(R.scale(cam_forward, input_fwd), R.scale(cam_right, input_right));
        wish = R.add(wish, R.scale(cam_up, input_up));
        const wish_len = R.length(wish);

        if (wish_len > 0.1) {
            const wish_dir = R.scale(wish, 1.0 / wish_len);
            self.speed = @min(target_speed, self.speed + self.acceleration * dt);
            velocity.* = R.scale(wish_dir, self.speed);
        } else {
            // Hover brake: rapidly damp velocity to stop in mid-air
            self.speed = @max(0, self.speed - 40.0 * dt);
            velocity.* = R.scale(velocity.*, @exp(-8.0 * dt));
        }

        feet.* = R.add(feet.*, R.scale(velocity.*, dt));
    }
};

pub const SonicDash = struct {
    active_timer: f32 = 0,
    cooldown: f32 = 0,
    duration: f32 = 0.22,
    dash_speed: f32 = 42.0,
    direction: V = .{ 0, 0, 1 },
    afterimage_count: u8 = 0,

    pub fn canDash(self: *const SonicDash) bool {
        return self.active_timer == 0 and self.cooldown == 0;
    }

    pub fn trigger(self: *SonicDash, forward_dir: V) bool {
        if (self.active_timer > 0 or self.cooldown > 0) return false;
        self.active_timer = self.duration;
        self.cooldown = 0.45;
        self.direction = R.normalize(forward_dir);
        self.afterimage_count = 3;
        return true;
    }

    pub fn update(self: *SonicDash, feet: *V, velocity: *V, dt: f32) bool {
        self.cooldown = @max(0, self.cooldown - dt);
        if (self.active_timer > 0) {
            self.active_timer = @max(0, self.active_timer - dt);
            velocity.* = R.scale(self.direction, self.dash_speed);
            feet.* = R.add(feet.*, R.scale(velocity.*, dt));
            return true;
        }
        return false;
    }
};

pub const FlyingJump = struct {
    charge: f32 = 0,
    is_charging: bool = false,
    max_charge: f32 = 1.0,

    pub fn startCharge(self: *FlyingJump) void {
        self.is_charging = true;
        self.charge = 0;
    }

    pub fn update(self: *FlyingJump, dt: f32) void {
        if (self.is_charging) {
            self.charge = @min(self.max_charge, self.charge + dt * 2.0);
        }
    }

    pub fn release(self: *FlyingJump, velocity: *V, forward: V) bool {
        if (!self.is_charging or self.charge < 0.2) {
            self.is_charging = false;
            self.charge = 0;
            return false;
        }
        const power = self.charge;
        // Superman leap: huge vertical velocity plus forward explosion
        velocity.* = R.add(
            R.scale(forward, 12.0 + power * 22.0),
            .{ 0, 18.0 + power * 32.0, 0 },
        );
        self.is_charging = false;
        self.charge = 0;
        return true;
    }
};

pub const WarpStrikeController = struct {
    pub fn executeWarp(
        feet: *V,
        velocity: *V,
        target_pos: V,
    ) void {
        // Teleport to 1.5m above target point and initialize high-speed down-slash
        feet.* = R.add(target_pos, .{ 0, 1.5, 0 });
        velocity.* = .{ 0, -28.0, 0 }; // Downward execution dive
    }
};

test "Sonic dash burst speed and cooldown" {
    var dash: SonicDash = .{};
    try std.testing.expect(dash.canDash());

    var feet: V = .{ 0, 0, 0 };
    var vel: V = .{ 0, 0, 0 };
    const success = dash.trigger(.{ 0, 0, 1 });
    try std.testing.expect(success);
    try std.testing.expect(!dash.canDash());

    const active = dash.update(&feet, &vel, 0.1);
    try std.testing.expect(active);
    try std.testing.expect(feet[2] > 3.0);
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), vel[2], 0.001);
}

test "Superman/DBZ 3D aerial flight controls, speed, and hover" {
    var flight: FlightState = .{};
    flight.toggle();
    try std.testing.expect(flight.active);

    var feet: V = .{ 0, 100, 0 };
    var vel: V = .{ 0, 0, 0 };
    const fwd: V = .{ 0, 0, 1 };
    const right: V = .{ 1, 0, 0 };
    const up: V = .{ 0, 1, 0 };

    // Fly forward with boost
    flight.update(&feet, &vel, fwd, right, up, 1.0, 0, 0, true, 0.1);
    try std.testing.expect(feet[2] > 0);
    try std.testing.expect(flight.boost);
    try std.testing.expect(flight.energy < 100.0);

    // Release wish to trigger hover brake
    flight.update(&feet, &vel, fwd, right, up, 0, 0, 0, false, 0.2);
    try std.testing.expect(vel[2] < 48.0);
}

test "flying jump charging and release velocity" {
    var leap: FlyingJump = .{};
    leap.startCharge();
    leap.update(0.8);
    try std.testing.expect(leap.charge > 0.5);

    var vel: V = .{ 0, 0, 0 };
    const released = leap.release(&vel, .{ 0, 0, 1 });
    try std.testing.expect(released);
    try std.testing.expect(vel[1] > 30.0); // High vertical launch
    try std.testing.expect(vel[2] > 20.0); // Forward launch
}

test "warp strike teleport execution snaps position and sets down-thrust" {
    var feet: V = .{ 0, 0, 0 };
    var vel: V = .{ 0, 0, 0 };
    const target: V = .{ 150, 45, 200 };

    WarpStrikeController.executeWarp(&feet, &vel, target);
    try std.testing.expectApproxEqAbs(@as(f32, 150.0), feet[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 46.5), feet[1], 0.001); // 1.5m above target
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), feet[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -28.0), vel[1], 0.001);
}
