const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Camera = @import("../world/Camera.zig");
const Input = @import("../engine/Input.zig");
const Player = @This();

pub const Mode = enum { walk, fly };
pub const eye_height: f32 = 1.62;
pub const walk_speed: f32 = 5;
pub const sprint_speed: f32 = 9;
pub const jump_speed: f32 = 5.2;
const ground_accel: f32 = 45;
const air_accel: f32 = 8;

feet: Physics.Vec3 = .{ 0, 0, 0 },
velocity: Physics.Vec3 = .{ 0, 0, 0 },
grounded: bool = false,
mode: Mode = .walk,
shape: Physics.Character = .{},

pub fn eye(self: Player) math.Vec3 {
    return math.vec3(self.feet[0], self.feet[1] + eye_height, self.feet[2]);
}

pub fn setMode(self: *Player, mode: Mode, camera: Camera) void {
    self.mode = mode;
    self.velocity = .{ 0, 0, 0 };
    self.grounded = false;
    self.feet = .{ camera.position.x(), camera.position.y() - eye_height, camera.position.z() };
}

/// One fixed step. Walk mode drives the character through physics; fly mode keeps the free camera.
pub fn step(self: *Player, physics: *Physics, camera: *Camera, input: Input, dt: f32) void {
    if (self.mode == .fly) {
        camera.move(input, dt);
        self.feet = .{ camera.position.x(), camera.position.y() - eye_height, camera.position.z() };
        return;
    }
    const forward = [2]f32{ @sin(camera.yaw), @cos(camera.yaw) };
    const right = [2]f32{ @cos(camera.yaw), -@sin(camera.yaw) };
    var wish = [2]f32{ forward[0] * input.forward + right[0] * input.right, forward[1] * input.forward + right[1] * input.right };
    const length = @sqrt(wish[0] * wish[0] + wish[1] * wish[1]);
    const speed = if (input.fast) sprint_speed else walk_speed;
    if (length > 0) wish = .{ wish[0] / length * speed, wish[1] / length * speed };
    // Accelerate toward the wished velocity; less control in the air.
    const accel = (if (self.grounded) ground_accel else air_accel) * dt;
    const dx = wish[0] - self.velocity[0];
    const dz = wish[1] - self.velocity[2];
    const delta = @sqrt(dx * dx + dz * dz);
    const apply = if (delta > accel) accel / delta else 1;
    self.velocity[0] += dx * apply;
    self.velocity[2] += dz * apply;
    self.velocity[1] += Physics.gravity * dt;
    if (input.jump and self.grounded) self.velocity[1] = jump_speed;

    const result = physics.moveCharacter(self.shape, self.feet, .{ self.velocity[0] * dt, self.velocity[1] * dt, self.velocity[2] * dt }, self.grounded and self.velocity[1] <= 0);
    // Blocked motion loses the velocity that could not be applied.
    const moved_x = (result.feet[0] - self.feet[0]) / dt;
    const moved_z = (result.feet[2] - self.feet[2]) / dt;
    if (@abs(moved_x) < @abs(self.velocity[0])) self.velocity[0] = moved_x;
    if (@abs(moved_z) < @abs(self.velocity[2])) self.velocity[2] = moved_z;
    if (result.grounded and self.velocity[1] < 0) self.velocity[1] = 0;
    if (result.hit_ceiling and self.velocity[1] > 0) self.velocity[1] = 0;
    self.feet = result.feet;
    self.grounded = result.grounded;
    camera.position = self.eye();
}
