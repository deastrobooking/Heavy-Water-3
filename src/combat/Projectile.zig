//! Projectile pool and simulation for blasters, arrows, tracking missiles, and warp bolts.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Weapon = @import("Weapon.zig");
const V = Physics.Vec3;
const R = Physics.Rotation;

pub const ProjectileKind = enum(u8) {
    blaster_bolt,
    charged_plasma,
    energy_arrow,
    warp_arrow,
    tracking_missile,
};

pub const Projectile = struct {
    active: bool = false,
    kind: ProjectileKind = .blaster_bolt,
    position: V = @splat(0),
    velocity: V = @splat(0),
    damage: f32 = 0,
    element: Weapon.Element = .kinetic,
    lifetime: f32 = 0,
    max_lifetime: f32 = 3.0,
    radius: f32 = 0.2,
    homing_target: ?V = null,
    homing_turn_rate: f32 = 12.0,
    homing_speed: f32 = 38.0,
    owner_is_player: bool = true,
};

pub const HitEvent = struct {
    projectile_index: usize,
    kind: ProjectileKind,
    position: V,
    normal: V,
    damage: f32,
    element: Weapon.Element,
    is_warp: bool,
};

pub const capacity = 128;

pub const ProjectilePool = struct {
    items: [capacity]Projectile = @splat(.{}),
    active_count: usize = 0,

    pub fn spawn(
        self: *ProjectilePool,
        kind: ProjectileKind,
        origin: V,
        direction: V,
        speed: f32,
        damage: f32,
        element: Weapon.Element,
        lifetime: f32,
        target: ?V,
    ) ?usize {
        for (&self.items, 0..) |*p, i| {
            if (!p.active) {
                const norm_dir = R.normalize(direction);
                p.* = .{
                    .active = true,
                    .kind = kind,
                    .position = origin,
                    .velocity = R.scale(norm_dir, speed),
                    .damage = damage,
                    .element = element,
                    .lifetime = lifetime,
                    .max_lifetime = lifetime,
                    .radius = if (kind == .charged_plasma) 0.8 else if (kind == .tracking_missile) 0.4 else 0.2,
                    .homing_target = target,
                    .homing_turn_rate = 14.0,
                    .homing_speed = speed,
                    .owner_is_player = true,
                };
                self.active_count += 1;
                return i;
            }
        }
        return null;
    }

    pub fn step(self: *ProjectilePool, physics: *const Physics, dt: f32, hits_out: []HitEvent) usize {
        var hit_count: usize = 0;
        for (&self.items, 0..) |*p, i| {
            if (!p.active) continue;
            p.lifetime -= dt;
            if (p.lifetime <= 0) {
                p.active = false;
                self.active_count -|= 1;
                continue;
            }

            // Homing steering
            if (p.kind == .tracking_missile and p.homing_target != null) {
                const to_target = R.sub(p.homing_target.?, p.position);
                const dist = R.length(to_target);
                if (dist > 0.1) {
                    const desired = R.normalize(to_target);
                    const current_dir = R.normalize(p.velocity);
                    // Smoothly interpolate direction
                    const turn_amount = @min(1.0, p.homing_turn_rate * dt);
                    const new_dir = R.normalize(R.add(R.scale(current_dir, 1.0 - turn_amount), R.scale(desired, turn_amount)));
                    p.velocity = R.scale(new_dir, p.homing_speed);
                }
            }

            // Physics raycast along trajectory
            const step_vec = R.scale(p.velocity, dt);
            const dist = R.length(step_vec);
            const dir = R.normalize(step_vec);

            if (physics.castRay(p.position, dir, dist, .none)) |hit| {
                if (hit_count < hits_out.len) {
                    hits_out[hit_count] = .{
                        .projectile_index = i,
                        .kind = p.kind,
                        .position = hit.point,
                        .normal = hit.normal,
                        .damage = p.damage,
                        .element = p.element,
                        .is_warp = (p.kind == .warp_arrow),
                    };
                    hit_count += 1;
                }
                p.active = false;
                self.active_count -|= 1;
                continue;
            }

            // Advance position
            p.position = R.add(p.position, step_vec);
        }
        return hit_count;
    }
};
