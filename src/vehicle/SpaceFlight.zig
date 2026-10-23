//! Bounded arcade flight for orbital trials. Atmospheric jet dynamics stay in `jet.zig`.
const std = @import("std");
const m = @import("../character/math.zig");
const Jet = @import("jet.zig");

pub const half_extent: f32 = 112;
pub const max_speed: f32 = 150;
pub const boost_speed: f32 = 245;
pub const Input = struct {
    lateral: f32 = 0,
    forward: f32 = 0,
    vertical: f32 = 0,
    boost: bool = false,
    brake: bool = false,
};

/// Moves a fighter inside a square orbital arena with no gravity, lift or terrain probes.
pub fn step(fighter: *Jet.Fighter, center: m.Vec3, input: Input, dt: f32) void {
    const b = &fighter.body;
    const demand = m.Vec3.init(input.lateral, input.vertical, input.forward);
    const magnitude = @min(1, demand.length());
    const drive = if (input.boost and !input.brake) @as(f32, 190) else 92;
    if (!input.brake) b.vel = b.vel.add(demand.normalizeOr(m.Vec3.zero).scale(drive * magnitude * dt));
    b.vel = b.vel.scale(if (input.brake) @max(0, 1 - dt * 4.8) else @max(0, 1 - dt * 0.26));
    const speed_limit = if (input.boost and !input.brake) boost_speed else max_speed;
    const speed = b.vel.length();
    if (speed > speed_limit) b.vel = b.vel.scale(speed_limit / speed);
    b.pos = b.pos.add(b.vel.scale(dt));

    // Reflect softly from the arena edge instead of allowing a fighter to leave the encounter.
    const relative = b.pos.sub(center);
    var p = relative;
    var v = b.vel;
    inline for (.{ "x", "z" }) |axis| {
        const coordinate = @field(p, axis);
        if (coordinate > half_extent) {
            @field(p, axis) = half_extent;
            if (@field(v, axis) > 0) @field(v, axis) *= -0.32;
        } else if (coordinate < -half_extent) {
            @field(p, axis) = -half_extent;
            if (@field(v, axis) < 0) @field(v, axis) *= -0.32;
        }
    }
    if (p.y > 34) {
        p.y = 34;
        if (v.y > 0) v.y *= -0.32;
    } else if (p.y < -34) {
        p.y = -34;
        if (v.y < 0) v.y *= -0.32;
    }
    b.pos = center.add(p);
    b.vel = v;
    fighter.grounded = false;
    fighter.throttle = if (input.brake) 0 else @max(input.forward, 0);
    fighter.burn = if (input.boost and !input.brake and magnitude > 0) 1 else 0;
    if (@abs(v.x) + @abs(v.z) > 0.4) {
        const yaw = std.math.atan2(v.x, v.z);
        b.rot = m.Quat.fromAxisAngle(m.Vec3.unit_y, yaw);
    }
}
