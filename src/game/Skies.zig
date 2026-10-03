//! The air war. Two Brood carriers (90 m insect ships) circle high over the outskirts beyond the
//! Hive nests, launching Hive wasps while anyone comes within 650 m. Wasps are agile insect fighters:
//!
//! - **Flight:** they fly at a speed with a limited turn rate. They avoid the ground by
//!   looking ahead and below, and never go under a floor height.
//! - **Targets:** they hunt the Kestrel if it is airborne within range, otherwise rangers on
//!   the ground.
//! - **Attack:** lead pursuit, firing stinger bursts when lined up. They break off past the
//!   target and come round again, and jink when hit.
//!
//! Carriers carry four flak turrets whose shells burst near the jet (proximity fuse), and four
//! glowing launch bays that take extra damage. A destroyed carrier drops a rich cache below and
//! stays down in the save (flag `carrier_N_down`).
//!
//! The Kestrel's weapons live here too:
//! - **Cannons:** twin guns firing alternately while held, limited by heat.
//! - **Missiles:** they lock onto the Hive target nearest the nose in a 25° cone (air or
//!   ground) while the alternate is held, fire on release, and home.
//! - **Hits:** shots strike wasps, carriers, ground Hive units (through `Enemies`) and the
//!   world.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Seed = @import("../procedural/Seed.zig");
const Enemies = @import("Enemies.zig");
const Terrain = @import("../procedural/Terrain.zig");
const ShipMeshes = @import("../vehicle/ShipMeshes.zig");
const m = @import("../character/math.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Skies = @This();

/// Air encounter and Kestrel weapon balance. Adjust these after the flight/combat playtest.
pub const tuning = .{
    .max_wasps = 14,
    .max_carriers = 2,
    .max_shots = 128,
    .wasps_per_carrier = 6,
    .carrier_health = 4200.0,
    .carrier_turret_health = 180.0,
    .carrier_bay_health = 240.0,
    .carrier_core_radius = 7.0,
    .carrier_crash_spin = 1.5,
    .wasp_health = 70.0,
    .wasp_radius = 3.2,
    .wasp_separation = 16.0,
    .jet_collision_radius = 5.0,
    .ram_damage_speed = 18.0,
    .ram_jet_damage_per_speed = 0.22,
    .ram_target_damage_per_speed = 0.48,
    .ram_damage_cooldown = 0.45,
    .carrier_wake_distance = 650.0,
    .carrier_speed = 16.0,
    .carrier_first_launch_delay = 4.0,
    .carrier_launch_interval = 6.0,
    .flak_range = 650.0,
    .flak_cooldown_min = 1.1,
    .flak_cooldown_jitter = 0.6,
    .flak_speed = 170.0,
    .flak_spread = 0.06,
    .flak_damage = 14.0,
    .flak_fuse_distance = 14.0,
    .flak_hit_distance = 16.0,
    .wasp_player_range = 900.0,
    .wasp_ground_range = 500.0,
    .wasp_attack_speed = 115.0,
    .wasp_patrol_speed = 85.0,
    .wasp_breakoff_speed = 120.0,
    .wasp_breakoff_range = 65.0,
    .wasp_breakoff_time = 2.2,
    .wasp_attack_lead_speed = 300.0,
    .wasp_attack_lead_factor = 0.9,
    .wasp_attack_range = 380.0,
    .wasp_aim_cosine = 0.985,
    .wasp_burst_count = 3,
    .wasp_burst_cooldown = 1.6,
    .wasp_turn_attack = 1.5,
    .wasp_turn_other = 1.9,
    .wasp_sting_speed = 300.0,
    .wasp_sting_spread = 0.04,
    .wasp_sting_jet_damage = 7.0,
    .wasp_sting_player_damage = 5.0,
    .cannon_rate = 12.0,
    .cannon_heat_per_shot = 6.0,
    .cannon_heat_cool_rate = 32.0,
    .cannon_overheat = 100.0,
    .cannon_resume_heat = 35.0,
    .cannon_speed = 520.0,
    .cannon_damage = 9.0,
    .cannon_lifetime = 1.8,
    .missile_lock_degrees = 25.0,
    .missile_lock_range = 1000.0,
    .missile_lock_time = 0.7,
    .missile_reload = 2.4,
    .missile_speed = 230.0,
    .missile_turn_rate = 3.2,
    .missile_damage = 150.0,
    .missile_lifetime = 6.0,
};

pub const max_wasps = tuning.max_wasps;
pub const max_carriers = tuning.max_carriers;
pub const max_shots = tuning.max_shots;
pub const wasps_per_carrier = tuning.wasps_per_carrier;
pub const carrier_health: f32 = tuning.carrier_health;
pub const wasp_health: f32 = tuning.wasp_health;
pub const wasp_radius: f32 = tuning.wasp_radius;
/// A carrier wakes (launches, shoots) only with a player this close.
pub const wake_distance: f32 = tuning.carrier_wake_distance;

pub const WaspState = enum { patrol, attack, breakoff, evade };
pub const WingKind = enum { wasp, dragonfly, beetle_bomber };
pub const AssaultStage = enum { turrets, bays, core, crashing };
pub const CarrierPart = union(enum) { turret: u8, bay: u8, core };
pub const Wasp = struct {
    kind: WingKind = .wasp,
    position: V,
    forward: V = .{ 0, 0, 1 },
    speed: f32 = 80,
    health: f32 = wasp_health,
    state: WaspState = .patrol,
    timer: f32 = 0,
    cooldown: f32 = 2,
    burst: u8 = 0,
    burst_timer: f32 = 0,
    carrier: u8,
    /// Target: 0 is the jet, 1–4 are players 1–4 on foot.
    target: u8 = 0,
    orbit: f32 = 0,
    flap: f32 = 0,
    flash: f32 = 0,
    jink: V = @splat(0),
    /// Staggers the structure ray.
    check: u8 = 0,
    raid_target: V = @splat(0),
    bomb_timer: f32 = 2.5,
};
pub const Carrier = struct {
    alive: bool = true,
    health: f32 = carrier_health,
    center: V,
    radius: f32,
    altitude: f32,
    angle: f32,
    /// Direction around the circuit (+1 counter-clockwise).
    direction: f32 = 1,
    launch: f32 = tuning.carrier_first_launch_delay,
    turret_cooldown: [4]f32 = @splat(1),
    turret_health: [4]f32 = @splat(tuning.carrier_turret_health),
    bay_health: [4]f32 = @splat(tuning.carrier_bay_health),
    flash: f32 = 0,
    crashing: bool = false,
    crash_origin: V = @splat(0),
    crash_velocity: V = @splat(0),
    crash_time: f32 = 0,
    crash_yaw: f32 = 0,
    debris_timer: f32 = 0,

    pub fn stage(c: Carrier) AssaultStage {
        if (c.crashing) return .crashing;
        for (c.turret_health) |health| if (health > 0) return .turrets;
        for (c.bay_health) |health| if (health > 0) return .bays;
        return .core;
    }

    pub fn activeTurrets(c: Carrier) usize {
        var count: usize = 0;
        for (c.turret_health) |health| count += @intFromBool(health > 0);
        return count;
    }

    pub fn activeBays(c: Carrier) usize {
        var count: usize = 0;
        for (c.bay_health) |health| count += @intFromBool(health > 0);
        return count;
    }

    pub fn lockPoint(c: Carrier) ?V {
        return switch (c.stage()) {
            .turrets => for (c.turret_health, 0..) |health, i| {
                if (health > 0) break c.point(ShipMeshes.carrier_turrets[i]);
            } else null,
            .bays => for (c.bay_health, 0..) |health, i| {
                if (health > 0) break c.point(ShipMeshes.carrier_bays[i]);
            } else null,
            .core => blk: {
                const p = c.point(m.Vec3.init(0, -10, -4));
                break :blk .{ p[0], p[1], p[2] };
            },
            .crashing => null,
        };
    }

    pub fn position(c: Carrier) V {
        if (c.crashing) return .{ c.crash_origin[0] + c.crash_velocity[0] * c.crash_time, c.crash_origin[1] - 5 * c.crash_time - 2.4 * c.crash_time * c.crash_time, c.crash_origin[2] + c.crash_velocity[2] * c.crash_time };
        return .{ c.center[0] + @sin(c.angle) * c.radius, c.altitude, c.center[2] + @cos(c.angle) * c.radius };
    }
    /// Heading: along the circuit's tangent.
    pub fn yaw(c: Carrier) f32 {
        if (c.crashing) return c.crash_yaw + c.crash_time * tuning.carrier_crash_spin;
        return c.angle + c.direction * std.math.pi / 2.0;
    }
    pub fn velocity(c: Carrier) V {
        const s = c.direction * carrier_speed;
        return .{ @cos(c.angle) * s, 0, -@sin(c.angle) * s };
    }
    /// A body-frame point of the ship in the world.
    pub fn point(c: Carrier, local: m.Vec3) V {
        const q = m.Quat.fromAxisAngle(m.Vec3.unit_y, c.yaw());
        const p = q.rotate(local);
        const o = c.position();
        return .{ o[0] + p.x, o[1] + p.y, o[2] + p.z };
    }
};
pub const carrier_speed: f32 = tuning.carrier_speed;

pub const ShotKind = enum { cannon, missile, sting, flak };
pub const Shot = struct {
    kind: ShotKind,
    position: V,
    velocity: V,
    damage: f32,
    life: f32,
    /// Missiles: what they home on.
    homing: ?Ref = null,
};
/// Something a missile can lock: a wasp, a carrier, or a specific ground Hive unit lifetime.
pub const Ref = union(enum) {
    wasp: u8,
    carrier: u8,
    ground: struct { slot: u8, generation: u32 },
};

/// The jet as the Hive sees it.
pub const Jet = struct { position: V, velocity: V, forward: V, airborne: bool };

pub const Event = union(enum) {
    sound: struct { kind: ShotKind, position: V },
    burst: V,
    jet_hit: f32,
    jet_collision: struct { normal: V, penetration: f32, other_velocity: V, damage: f32 },
    player_hit: struct { player: u8, damage: f32 },
    wasp_down: V,
    raid_started: struct { plaza: u8, position: V },
    raid_bomb: struct { plaza: u8, position: V, hit: u8 },
    raid_repelled: u8,
    raid_lost: u8,
    carrier_stage: struct { carrier: u8, stage: AssaultStage },
    carrier_debris: V,
    carrier_down: struct { carrier: u8, position: V },
    hive: Enemies.Event,
};

/// The Kestrel's guns and missile lock (P1).
pub const Guns = struct {
    cooldown: f32 = 0,
    heat: f32 = 0,
    overheated: bool = false,
    side: u1 = 0,
    missile_cooldown: f32 = 0,
    lock: ?Ref = null,
    lock_progress: f32 = 0,
    was_alt: bool = false,
    missile_ammo: u8 = 2,
    missile_capacity: u8 = 2,
    missile_rearm: f32 = 0,
};

seed: u64 = 0,
wasps: [max_wasps]?Wasp = @splat(null),
market_plazas: [3]V = @splat(.{ 0, 0, 0 }),
launch_serial: u32 = 0,
raid_active: bool = false,
raid_plaza: u8 = 0,
raid_hits: u8 = 0,
carriers: [max_carriers]Carrier = undefined,
shots: [max_shots]?Shot = @splat(null),
guns: Guns = .{},
ram_cooldown: f32 = 0,
rng: std.Random.DefaultPrng = .init(0),

/// Carrier circuits: beyond the first two nests as seen from `spawn` (or around `spawn` with no
/// nests), so the air war happens over the Hive's ground, not the city.
pub fn init(seed: u64, spawn: V, nests: []const V) Skies {
    var self: Skies = .{ .seed = seed, .rng = .init(Seed.mix(seed ^ 0x534b494553)) };
    self.market_plazas = .{ R.add(spawn, .{ 80, 0, 60 }), R.add(spawn, .{ -90, 0, 40 }), R.add(spawn, .{ 20, 0, -110 }) };
    for (&self.carriers, 0..) |*c, i| {
        var center = spawn;
        var radius: f32 = 640 + 180 * @as(f32, @floatFromInt(i));
        if (i < nests.len) {
            const away = R.normalize(.{ nests[i][0] - spawn[0], 0, nests[i][2] - spawn[2] });
            center = R.add(nests[i], R.scale(away, 260));
            radius = 230;
        }
        const ground = Terrain.surface(seed, center[0], center[2]).height;
        c.* = .{ .center = center, .radius = radius, .altitude = ground + 260 + 60 * @as(f32, @floatFromInt(i)), .angle = 0.8 + 3.1 * @as(f32, @floatFromInt(i)), .direction = if (i == 0) 1 else -1 };
    }
    return self;
}

fn push(out: []Event, n: *usize, e: Event) void {
    if (n.* < out.len) out[n.*] = e;
    n.* += 1;
}

fn addShot(self: *Skies, s: Shot) void {
    for (&self.shots) |*slot| if (slot.* == null) {
        slot.* = s;
        return;
    };
}

pub fn waspCount(self: *const Skies, carrier: ?u8) usize {
    var n: usize = 0;
    for (self.wasps) |slot| if (slot) |w| {
        n += @intFromBool(carrier == null or w.carrier == carrier.?);
    };
    return n;
}

pub fn configureKestrel(self: *Skies, upgrades: [4]u8) void {
    const capacity: u8 = 2 + upgrades[@intFromEnum(@import("Progress.zig").KestrelUpgrade.missile_rack)] * 2;
    if (capacity > self.guns.missile_capacity) self.guns.missile_ammo += capacity - self.guns.missile_capacity;
    self.guns.missile_capacity = capacity;
}

fn separation(self: *const Skies, index: usize, position: V) V {
    var steer: V = @splat(0);
    for (self.wasps, 0..) |slot, other| {
        if (other == index or slot == null) continue;
        const offset = R.sub(position, slot.?.position);
        const d = R.length(offset);
        if (d >= tuning.wasp_separation) continue;
        const away: V = if (d > 1e-3) R.scale(offset, 1 / d) else .{ if (index < other) @as(f32, 1) else -1, 0, 0 };
        steer = R.add(steer, R.scale(away, 1 - d / tuning.wasp_separation));
    }
    return steer;
}

fn dist(a: V, b: V) f32 {
    return R.length(R.sub(a, b));
}

/// Turns `forward` toward `desired` by at most `rate * dt` radians.
fn turnToward(forward: V, desired: V, rate: f32, dt: f32) V {
    const d = R.normalize(desired);
    const cos = std.math.clamp(R.dot(forward, d), -1, 1);
    const angle = std.math.acos(cos);
    const max = rate * dt;
    if (angle <= max or angle < 1e-4) return d;
    // Slerp a fraction of the way.
    const t = max / angle;
    return R.normalize(R.add(R.scale(forward, 1 - t), R.scale(d, t)));
}

/// One fixed step of the Hive's air forces and every airborne shot.
/// `players` are chest positions of local players on foot (alive or not).
pub fn step(self: *Skies, physics: *const Physics, enemies: *Enemies, jet: ?Jet, players: []const Enemies.Target, dt: f32, out: []Event) usize {
    var n: usize = 0;
    const random = self.rng.random();
    var anyone: bool = jet != null;
    for (players) |p| anyone = anyone or p.alive;

    // Carriers: circle, launch while someone is near, and throw flak at the jet.
    for (&self.carriers, 0..) |*c, ci| {
        if (!c.alive) continue;
        c.flash = @max(0, c.flash - dt);
        if (c.crashing) {
            c.crash_time += dt;
            c.debris_timer -= dt;
            const at = c.position();
            if (c.debris_timer <= 0) {
                c.debris_timer = 0.22;
                push(out, &n, .{ .carrier_debris = R.add(at, .{ (random.float(f32) - 0.5) * 34, (random.float(f32) - 0.5) * 20, (random.float(f32) - 0.5) * 48 }) });
            }
            const ground = Terrain.surface(self.seed, at[0], at[2]).height;
            if (at[1] <= ground + 12 or c.crash_time >= 12) {
                c.alive = false;
                push(out, &n, .{ .carrier_down = .{ .carrier = @intCast(ci), .position = at } });
            }
            continue;
        }
        c.angle += c.direction * carrier_speed / c.radius * dt;
        const pos = c.position();
        var near = false;
        if (jet) |j| near = near or dist(j.position, pos) < wake_distance;
        for (players) |p| near = near or (p.alive and dist(p.chest, pos) < wake_distance);
        if (!near) continue;
        c.launch -= dt;
        if (c.launch <= 0 and self.waspCount(@intCast(ci)) < wasps_per_carrier) {
            c.launch = tuning.carrier_launch_interval;
            const bay = ShipMeshes.carrier_bays[random.uintLessThan(usize, 4)];
            const kind: WingKind = switch (self.launch_serial % 5) {
                2 => .dragonfly,
                4 => .beetle_bomber,
                else => .wasp,
            };
            self.launch_serial +%= 1;
            for (&self.wasps) |*slot| if (slot.* == null) {
                const plaza: u8 = @intCast(self.launch_serial % self.market_plazas.len);
                if (kind == .beetle_bomber and !self.raid_active) {
                    self.raid_active = true;
                    self.raid_plaza = plaza;
                    self.raid_hits = 0;
                    push(out, &n, .{ .raid_started = .{ .plaza = plaza, .position = self.market_plazas[plaza] } });
                }
                slot.* = .{ .kind = kind, .position = c.point(bay), .forward = R.normalize(R.add(c.velocity(), .{ 0, -8, 0 })), .carrier = @intCast(ci), .orbit = random.float(f32) * 6.28, .raid_target = self.market_plazas[if (kind == .beetle_bomber and self.raid_active) self.raid_plaza else plaza], .health = if (kind == .dragonfly) wasp_health * 0.55 else if (kind == .beetle_bomber) wasp_health * 2.2 else wasp_health };
                break;
            };
        }
        if (jet) |j| if (j.airborne) for (ShipMeshes.carrier_turrets, c.turret_health, &c.turret_cooldown) |t, health, *cd| {
            if (health <= 0) continue;
            cd.* = @max(0, cd.* - dt);
            const muzzle = c.point(t);
            const d = dist(j.position, muzzle);
            if (cd.* > 0 or d > tuning.flak_range) continue;
            cd.* = tuning.flak_cooldown_min + random.float(f32) * tuning.flak_cooldown_jitter;
            const speed: f32 = tuning.flak_speed;
            const lead = R.add(j.position, R.scale(j.velocity, d / speed));
            var dir = R.normalize(R.sub(lead, muzzle));
            dir = R.normalize(R.add(dir, .{ (random.float(f32) - 0.5) * tuning.flak_spread, (random.float(f32) - 0.5) * tuning.flak_spread, (random.float(f32) - 0.5) * tuning.flak_spread }));
            self.addShot(.{ .kind = .flak, .position = muzzle, .velocity = R.scale(dir, speed), .damage = tuning.flak_damage, .life = d / speed + 0.4 });
            push(out, &n, .{ .sound = .{ .kind = .flak, .position = muzzle } });
        };
    }

    // Wasps.
    for (&self.wasps, 0..) |*slot, wi| {
        const w = &(slot.* orelse continue);
        const home = self.carriers[w.carrier];
        w.flash = @max(0, w.flash - dt);
        w.flap = @mod(w.flap + dt * 38, 2 * std.math.pi);
        w.cooldown = @max(0, w.cooldown - dt);
        w.timer = @max(0, w.timer - dt);
        if (!anyone) continue;
        // Choose a target: the jet if it flies within 900 m, else the nearest ranger on foot.
        var target_pos: ?V = null;
        var target_vel: V = @splat(0);
        if (jet) |j| if (j.airborne and dist(j.position, w.position) < tuning.wasp_player_range) {
            w.target = 0;
            target_pos = j.position;
            target_vel = j.velocity;
        };
        if (target_pos == null) {
            var best: f32 = tuning.wasp_ground_range;
            for (players, 0..) |p, pi| if (p.alive) {
                const d = dist(p.chest, w.position);
                if (d < best) {
                    best = d;
                    w.target = @intCast(pi + 1);
                    target_pos = p.chest;
                    target_vel = p.velocity;
                }
            };
        }
        if (w.kind == .beetle_bomber and self.raid_active and self.raid_plaza < self.market_plazas.len) {
            target_pos = w.raid_target;
            target_vel = @splat(0);
            w.state = .attack;
        }
        if (target_pos == null and w.state == .attack) w.state = .patrol;
        if (target_pos != null and w.state == .patrol) w.state = .attack;

        var desired: V = w.forward;
        var speed: f32 = if (w.kind == .dragonfly) tuning.wasp_patrol_speed * 1.7 else if (w.kind == .beetle_bomber) tuning.wasp_patrol_speed * 0.7 else tuning.wasp_patrol_speed;
        switch (w.state) {
            .patrol => {
                w.orbit += dt * 0.35;
                const c = if (home.alive) home.position() else R.add(w.position, R.scale(w.forward, 50));
                desired = R.sub(R.add(c, .{ @sin(w.orbit) * 140, -20 + @sin(w.orbit * 1.9) * 15, @cos(w.orbit) * 140 }), w.position);
            },
            .attack => {
                const t = target_pos.?;
                const d = dist(t, w.position);
                const lead = R.add(t, R.scale(target_vel, d / tuning.wasp_attack_lead_speed * tuning.wasp_attack_lead_factor));
                desired = R.sub(lead, w.position);
                speed = if (w.kind == .dragonfly) tuning.wasp_attack_speed * 1.55 else if (w.kind == .beetle_bomber) tuning.wasp_attack_speed * (if (d < 110) @as(f32, 0.24) else 0.72) else tuning.wasp_attack_speed;
                if (w.kind == .beetle_bomber) {
                    w.bomb_timer -= dt;
                    if (d < 110 and w.bomb_timer <= 0) {
                        w.bomb_timer = 2.5;
                        self.raid_hits += 1;
                        push(out, &n, .{ .raid_bomb = .{ .plaza = self.raid_plaza, .position = w.raid_target, .hit = self.raid_hits } });
                        if (self.raid_hits >= 3) {
                            self.raid_active = false;
                            push(out, &n, .{ .raid_lost = self.raid_plaza });
                            w.state = .breakoff;
                            w.timer = 3;
                            w.jink = R.normalize(R.add(w.forward, .{ 0, 1, 0 }));
                        }
                    }
                }
                if (w.kind != .beetle_bomber and d < tuning.wasp_breakoff_range) {
                    w.state = .breakoff;
                    w.timer = tuning.wasp_breakoff_time;
                    const away = R.normalize(R.sub(w.position, t));
                    w.jink = R.normalize(R.add(R.add(away, .{ 0, 0.7, 0 }), R.scale(R.cross(w.forward, .{ 0, 1, 0 }), if (random.boolean()) @as(f32, 0.8) else -0.8)));
                }
                // Fire when lined up.
                const aim = R.normalize(desired);
                if (R.dot(aim, w.forward) > tuning.wasp_aim_cosine and d < tuning.wasp_attack_range and w.cooldown == 0 and w.burst == 0) {
                    w.burst = tuning.wasp_burst_count;
                    w.burst_timer = 0;
                    w.cooldown = tuning.wasp_burst_cooldown;
                }
            },
            .breakoff, .evade => {
                desired = w.jink;
                speed = tuning.wasp_breakoff_speed;
                if (w.timer == 0) w.state = if (target_pos != null) .attack else .patrol;
            },
        }
        desired = R.add(desired, R.scale(separation(self, wi, w.position), 2.5));
        // Ground avoidance, cheaply: the terrain under and ahead of the wasp (analytic), and a
        // short ray for structures every fourth step (staggered across wasps).
        const here = Terrain.surface(self.seed, w.position[0], w.position[2]).height;
        var floor = here;
        for ([_]f32{ 40, 80, 120 }) |d| {
            const p = R.add(w.position, R.scale(w.forward, d));
            floor = @max(floor, Terrain.surface(self.seed, p[0], p[2]).height);
        }
        var blocked = false;
        w.check +%= 1;
        if (w.check % 4 == 0) blocked = physics.castRay(w.position, w.forward, 40, .none) != null;
        if (blocked or w.position[1] < floor + 24) desired = R.add(R.normalize(desired), .{ 0, 2.5, 0 });
        const turn_scale: f32 = switch (w.kind) {
            .wasp => 1,
            .dragonfly => 1.45,
            .beetle_bomber => 0.72,
        };
        const base_turn: f32 = if (w.state == .attack) tuning.wasp_turn_attack else tuning.wasp_turn_other;
        const turn_rate = base_turn * turn_scale;
        w.forward = turnToward(w.forward, desired, turn_rate, dt);
        w.speed += (speed - w.speed) * @min(1, dt * 1.5);
        w.position = R.add(w.position, R.scale(w.forward, w.speed * dt));
        w.position[1] = @max(w.position[1], here + 8);

        if (w.burst > 0) {
            w.burst_timer -= dt;
            if (w.burst_timer <= 0) {
                w.burst -= 1;
                w.burst_timer = 0.11;
                const muzzle = R.add(w.position, R.scale(w.forward, 3));
                var dir = w.forward;
                dir = R.normalize(R.add(dir, .{ (random.float(f32) - 0.5) * tuning.wasp_sting_spread, (random.float(f32) - 0.5) * tuning.wasp_sting_spread, (random.float(f32) - 0.5) * tuning.wasp_sting_spread }));
                self.addShot(.{ .kind = .sting, .position = muzzle, .velocity = R.add(R.scale(dir, tuning.wasp_sting_speed), R.scale(w.forward, w.speed)), .damage = if (w.target == 0) tuning.wasp_sting_jet_damage else tuning.wasp_sting_player_damage, .life = 2 });
                push(out, &n, .{ .sound = .{ .kind = .sting, .position = muzzle } });
            }
        }
    }

    if (jet) |j| self.collideJet(j, dt, out, &n);

    // Shots.
    for (&self.shots) |*slot| {
        const s = &(slot.* orelse continue);
        s.life -= dt;
        if (s.kind == .missile) {
            if (s.homing) |h| if (self.refPosition(enemies, h)) |p| {
                const speed = R.length(s.velocity);
                var aim = R.sub(p, s.position);
                if (h == .wasp) if (self.wasps[h.wasp]) |w| if (w.kind == .dragonfly) {
                    const phase = @as(f32, @floatFromInt(h.wasp)) * 1.7 + s.life * 5;
                    aim = R.add(aim, R.scale(R.cross(R.normalize(aim), .{ 0, 1, 0 }), 42 * @sin(phase)));
                };
                s.velocity = R.scale(turnToward(R.scale(s.velocity, 1 / speed), aim, tuning.missile_turn_rate, dt), speed);
            };
        }
        const travel = R.scale(s.velocity, dt);
        const length = R.length(travel);
        const dir = R.scale(travel, 1 / @max(length, 1e-4));
        const player_shot = s.kind == .cannon or s.kind == .missile;
        var consumed = false;
        if (player_shot) {
            consumed = self.strikeAlong(enemies, s.position, dir, length, if (s.kind == .missile) 2 else 0.6, s.damage, out, &n);
            if (consumed and s.kind == .missile) push(out, &n, .{ .burst = s.position });
        } else if (s.kind == .flak) {
            // Proximity fuse near the jet, or at the end of its flight.
            if (jet) |j| if (dist(s.position, j.position) < tuning.flak_fuse_distance or s.life <= 0) {
                if (dist(s.position, j.position) < tuning.flak_hit_distance) push(out, &n, .{ .jet_hit = s.damage });
                push(out, &n, .{ .burst = s.position });
                consumed = true;
            };
        } else {
            // Stingers hit the jet (a 4 m sphere) or rangers' chests.
            if (jet) |j| if (Enemies.segmentSphere(s.position, dir, length, j.position, 4) != null) {
                push(out, &n, .{ .jet_hit = s.damage });
                consumed = true;
            };
            if (!consumed) for (players, 0..) |p, pi| if (p.alive) {
                if (Enemies.segmentSphere(s.position, dir, length, p.chest, 0.7) != null) {
                    push(out, &n, .{ .player_hit = .{ .player = @intCast(pi), .damage = s.damage } });
                    consumed = true;
                    break;
                }
            };
        }
        if (!consumed) if (physics.castRay(s.position, dir, length, .none)) |hit| {
            if (s.kind == .missile) {
                push(out, &n, .{ .burst = hit.point });
                var hn: usize = 0;
                var hive: [8]Enemies.Event = undefined;
                _ = enemies.strikeArea(hit.point, 6, s.damage * 0.5, null, &hive, &hn);
                for (hive[0..@min(hn, hive.len)]) |e| push(out, &n, .{ .hive = e });
            }
            consumed = true;
        };
        if (consumed or s.life <= 0) {
            slot.* = null;
            continue;
        }
        s.position = R.add(s.position, travel);
    }
    return n;
}

fn collideJet(self: *Skies, jet: Jet, dt: f32, out: []Event, n: *usize) void {
    self.ram_cooldown = @max(0, self.ram_cooldown - dt);
    const Candidate = struct { normal: V, penetration: f32, other_velocity: V, relative_speed: f32, wasp: ?usize = null, carrier: ?usize = null };
    var best: ?Candidate = null;

    for (self.wasps, 0..) |slot, wi| if (slot) |w| {
        const delta = R.sub(jet.position, w.position);
        const d = R.length(delta);
        const radius = tuning.jet_collision_radius + tuning.wasp_radius;
        if (d >= radius) continue;
        const normal = if (d > 1e-3) R.scale(delta, 1 / d) else R.scale(w.forward, -1);
        const other_velocity = R.scale(w.forward, w.speed);
        const candidate: Candidate = .{ .normal = normal, .penetration = radius - d, .other_velocity = other_velocity, .relative_speed = R.length(R.sub(jet.velocity, other_velocity)), .wasp = wi };
        if (best == null or candidate.penetration > best.?.penetration) best = candidate;
    };

    for (self.carriers, 0..) |c, ci| if (c.alive and !c.crashing) {
        const other_velocity = c.velocity();
        for (ShipMeshes.carrier_hull) |sphere| {
            const center = c.point(sphere[0]);
            const delta = R.sub(jet.position, .{ center[0], center[1], center[2] });
            const d = R.length(delta);
            const radius = tuning.jet_collision_radius + sphere[1].x;
            if (d >= radius) continue;
            const normal = if (d > 1e-3) R.scale(delta, 1 / d) else R.scale(R.sub(jet.velocity, other_velocity), -1);
            const candidate: Candidate = .{ .normal = normal, .penetration = radius - d, .other_velocity = other_velocity, .relative_speed = R.length(R.sub(jet.velocity, other_velocity)), .carrier = ci };
            if (best == null or candidate.penetration > best.?.penetration) best = candidate;
        }
    };

    const hit = best orelse return;
    const jet_damage = if (self.ram_cooldown == 0) @max(0, hit.relative_speed - tuning.ram_damage_speed) * tuning.ram_jet_damage_per_speed else 0;
    const target_damage = if (self.ram_cooldown == 0) @max(0, hit.relative_speed - tuning.ram_damage_speed) * tuning.ram_target_damage_per_speed else 0;
    push(out, n, .{ .jet_collision = .{ .normal = hit.normal, .penetration = hit.penetration, .other_velocity = hit.other_velocity, .damage = jet_damage } });
    if (self.ram_cooldown == 0 and target_damage > 0) {
        self.ram_cooldown = tuning.ram_damage_cooldown;
        if (hit.wasp) |wi| if (self.wasps[wi]) |*w| {
            // A glancing airframe contact hurts, but should not erase a whole interceptor in a
            // single pass. The lighter dragonfly keeps its low hull pool and still dies sooner.
            w.health -= target_damage * (if (w.kind == .dragonfly) @as(f32, 1) else 0.55);
            w.flash = 0.16;
            if (w.health <= 0) {
                const at = w.position;
                if (w.kind == .beetle_bomber and self.raid_active) {
                    self.raid_active = false;
                    push(out, n, .{ .raid_repelled = self.raid_plaza });
                }
                self.wasps[wi] = null;
                push(out, n, .{ .wasp_down = at });
            }
        };
        if (hit.carrier) |ci| {
            const c = &self.carriers[ci];
            const old_stage = c.stage();
            switch (old_stage) {
                .turrets => for (&c.turret_health) |*health| if (health.* > 0) {
                    health.* = @max(0, health.* - target_damage);
                    break;
                },
                .bays => for (&c.bay_health) |*health| if (health.* > 0) {
                    health.* = @max(0, health.* - target_damage);
                    break;
                },
                .core => c.health -= target_damage,
                .crashing => {},
            }
            c.flash = 0.16;
            if (c.health <= 0 and !c.crashing) {
                c.crashing = true;
                c.crash_origin = c.position();
                c.crash_velocity = c.velocity();
                c.crash_yaw = c.yaw();
                c.crash_time = 0;
                c.debris_timer = 0;
            }
            if (old_stage != c.stage()) push(out, n, .{ .carrier_stage = .{ .carrier = @intCast(ci), .stage = c.stage() } });
        }
    }
}

fn refPosition(self: *const Skies, enemies: *const Enemies, r: Ref) ?V {
    return switch (r) {
        .wasp => |i| if (self.wasps[i]) |w| w.position else null,
        .carrier => |i| if (self.carriers[i].alive) self.carriers[i].lockPoint() else null,
        .ground => |target| if (enemies.units[target.slot]) |u|
            if (u.generation == target.generation) u.center() else null
        else
            null,
    };
}

/// A player shot along a segment: the nearest wasp, carrier part, or ground Hive unit takes it.
fn strikeAlong(self: *Skies, enemies: *Enemies, origin: V, dir: V, length: f32, pad: f32, damage: f32, out: []Event, n: *usize) bool {
    var best = length;
    var hit: ?Ref = null;
    var part: ?CarrierPart = null;
    var weak = false;
    for (self.wasps, 0..) |slot, i| if (slot) |w| {
        if (Enemies.segmentSphere(origin, dir, best, w.position, wasp_radius + pad)) |t| {
            best = t;
            hit = .{ .wasp = @intCast(i) };
        }
    };
    for (self.carriers, 0..) |c, ci| if (c.alive) {
        if (c.crashing) continue;
        switch (c.stage()) {
            .turrets => for (ShipMeshes.carrier_turrets, c.turret_health, 0..) |turret, health, ti| {
                if (health <= 0) continue;
                if (Enemies.segmentSphere(origin, dir, best, c.point(turret), 3.8 + pad)) |t| {
                    best = t;
                    hit = .{ .carrier = @intCast(ci) };
                    part = .{ .turret = @intCast(ti) };
                    weak = false;
                }
            },
            .bays => for (ShipMeshes.carrier_bays, c.bay_health, 0..) |bay, health, bi| {
                if (health <= 0) continue;
                if (Enemies.segmentSphere(origin, dir, best, c.point(bay), 4.5 + pad)) |t| {
                    best = t;
                    hit = .{ .carrier = @intCast(ci) };
                    part = .{ .bay = @intCast(bi) };
                    weak = true;
                }
            },
            .core => if (Enemies.segmentSphere(origin, dir, best, c.point(m.Vec3.init(0, -10, -4)), tuning.carrier_core_radius + pad)) |t| {
                best = t;
                hit = .{ .carrier = @intCast(ci) };
                part = .core;
                weak = true;
            },
            .crashing => {},
        }
    };
    var hive: [8]Enemies.Event = undefined;
    var hn: usize = 0;
    if (enemies.strikeAlong(origin, dir, best, pad, damage, &hive, &hn) != null) {
        for (hive[0..@min(hn, hive.len)]) |e| push(out, n, .{ .hive = e });
        return true;
    }
    const target = hit orelse return false;
    switch (target) {
        .wasp => |i| {
            const w = &self.wasps[i].?;
            w.health -= damage;
            w.flash = 0.12;
            if (w.state != .breakoff) {
                w.state = .evade;
                w.timer = 0.9;
                w.jink = R.normalize(R.add(w.forward, R.scale(R.cross(w.forward, .{ 0, 1, 0 }), if (self.rng.random().boolean()) @as(f32, 1.2) else -1.2)));
            }
            if (w.health <= 0) {
                if (w.kind == .beetle_bomber and self.raid_active) {
                    self.raid_active = false;
                    push(out, n, .{ .raid_repelled = self.raid_plaza });
                }
                push(out, n, .{ .wasp_down = w.position });
                self.wasps[i] = null;
            }
        },
        .carrier => |i| {
            const c = &self.carriers[i];
            const old_stage = c.stage();
            const amount = damage * (if (weak) @as(f32, 2.5) else 1);
            switch (part orelse return false) {
                .turret => |ti| c.turret_health[ti] = @max(0, c.turret_health[ti] - amount),
                .bay => |bi| c.bay_health[bi] = @max(0, c.bay_health[bi] - amount),
                .core => c.health -= amount,
            }
            c.flash = 0.12;
            if (c.health <= 0 and !c.crashing) {
                c.crashing = true;
                c.crash_origin = c.position();
                c.crash_velocity = c.velocity();
                c.crash_yaw = c.yaw();
                c.crash_time = 0;
                c.debris_timer = 0;
            }
            const new_stage = c.stage();
            if (old_stage != new_stage) {
                push(out, n, .{ .carrier_stage = .{ .carrier = i, .stage = new_stage } });
            }
        },
        .ground => {},
    }
    return true;
}

/// An aimed ground weapon beam can hit a Hive flyer along the ranger's existing aim ray.
pub fn fireRanger(self: *Skies, origin: V, dir: V, damage: f32) void {
    self.addShot(.{ .kind = .cannon, .position = origin, .velocity = R.scale(R.normalize(dir), 800), .damage = damage, .life = 0.9 });
}

/// The Kestrel's weapons for one step: cannons while `fire` is held, missile lock while `alt`
/// is held (fired on release). `guns` are the muzzles in the world; `nose` the jet's forward.
pub fn fireJet(self: *Skies, enemies: *const Enemies, jet: Jet, guns: [2]V, fire: bool, alt: bool, dt: f32, out: []Event, n: *usize) void {
    self.fireJetUpgraded(enemies, jet, guns, fire, alt, dt, @splat(0), out, n);
}

pub fn fireJetUpgraded(self: *Skies, enemies: *const Enemies, jet: Jet, guns: [2]V, fire: bool, alt: bool, dt: f32, upgrades: [4]u8, out: []Event, n: *usize) void {
    const g = &self.guns;
    const Progress = @import("Progress.zig");
    const rack_level = upgrades[@intFromEnum(Progress.KestrelUpgrade.missile_rack)];
    const cooling_level = upgrades[@intFromEnum(Progress.KestrelUpgrade.gun_cooling)];
    self.configureKestrel(upgrades);
    g.cooldown = @max(0, g.cooldown - dt);
    g.missile_cooldown = @max(0, g.missile_cooldown - dt);
    if (g.missile_ammo == 0 and g.missile_rearm > 0) {
        g.missile_rearm = @max(0, g.missile_rearm - dt);
        if (g.missile_rearm == 0) g.missile_ammo = g.missile_capacity;
    }
    const cooling: f32 = 1 + @as(f32, @floatFromInt(cooling_level)) * 0.3;
    const overheat_limit: f32 = tuning.cannon_overheat + @as(f32, @floatFromInt(cooling_level)) * 12;
    g.heat = @max(0, g.heat - tuning.cannon_heat_cool_rate * cooling * dt);
    if (g.overheated and g.heat < tuning.cannon_resume_heat * cooling) g.overheated = false;
    if (fire and !g.overheated and g.cooldown == 0) {
        g.cooldown = 1.0 / (tuning.cannon_rate * cooling);
        g.heat += tuning.cannon_heat_per_shot;
        if (g.heat >= overheat_limit) g.overheated = true;
        const muzzle = guns[g.side];
        g.side +%= 1;
        self.addShot(.{ .kind = .cannon, .position = muzzle, .velocity = R.add(R.scale(jet.forward, tuning.cannon_speed), jet.velocity), .damage = tuning.cannon_damage, .life = tuning.cannon_lifetime });
        push(out, n, .{ .sound = .{ .kind = .cannon, .position = muzzle } });
    }
    // Missile lock: the Hive target nearest the nose within 25° and 1 km.
    if (alt) {
        const best = self.lockCandidate(enemies, jet);
        if (best != null and g.lock != null and std.meta.eql(best.?, g.lock.?)) {
            g.lock_progress = @min(1, g.lock_progress + dt / tuning.missile_lock_time);
        } else {
            g.lock = best;
            g.lock_progress = 0;
        }
    }
    if (!alt and g.was_alt and g.missile_cooldown == 0 and g.missile_ammo > 0) {
        g.missile_cooldown = tuning.missile_reload;
        g.missile_ammo -= 1;
        if (g.missile_ammo == 0) g.missile_rearm = 10 / (1 + @as(f32, @floatFromInt(rack_level)) * 0.15);
        const homing = if (g.lock_progress >= 1) g.lock else null;
        const launch = R.scale(R.add(guns[0], guns[1]), 0.5);
        self.addShot(.{ .kind = .missile, .position = R.add(launch, .{ 0, -0.6, 0 }), .velocity = R.add(R.scale(jet.forward, tuning.missile_speed), jet.velocity), .damage = tuning.missile_damage, .life = tuning.missile_lifetime, .homing = homing });
        push(out, n, .{ .sound = .{ .kind = .missile, .position = launch } });
        g.lock = null;
        g.lock_progress = 0;
    }
    if (!alt and !g.was_alt) {
        g.lock = null;
        g.lock_progress = 0;
    }
    g.was_alt = alt;
}

pub fn lockCandidate(self: *const Skies, enemies: *const Enemies, jet: Jet) ?Ref {
    var best: ?Ref = null;
    var best_cos: f32 = @cos(m.radians(tuning.missile_lock_degrees));
    const consider = struct {
        fn f(p: V, j: Jet, ref: Ref, b: *?Ref, bc: *f32) void {
            const d = R.sub(p, j.position);
            const l = R.length(d);
            if (l > tuning.missile_lock_range or l < 5) return;
            const c = R.dot(R.scale(d, 1 / l), j.forward);
            if (c > bc.*) {
                bc.* = c;
                b.* = ref;
            }
        }
    }.f;
    for (self.wasps, 0..) |slot, i| if (slot) |w| consider(w.position, jet, .{ .wasp = @intCast(i) }, &best, &best_cos);
    for (self.carriers, 0..) |c, i| if (c.alive) if (c.lockPoint()) |target| consider(target, jet, .{ .carrier = @intCast(i) }, &best, &best_cos);
    for (enemies.units, 0..) |slot, i| if (slot) |u| consider(u.center(), jet, .{ .ground = .{ .slot = @intCast(i), .generation = u.generation } }, &best, &best_cos);
    return best;
}

/// Where the current lock (or lock candidate) is in the world, for the HUD reticle.
pub fn lockPosition(self: *const Skies, enemies: *const Enemies) ?V {
    return self.refPosition(enemies, self.guns.lock orelse return null);
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "a ground lock and missile never follow a replacement enemy in the same slot" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    enemies.units[0] = .{ .generation = 7, .kind = .drone, .nest = 0, .position = .{ 0, 100, 100 }, .health = 60, .orbit = 0 };
    var sky = Skies.init(12, .{ 0, 0, 0 }, &.{});
    sky.carriers[0].alive = false;
    sky.carriers[1].alive = false;

    const jet: Jet = .{ .position = .{ 0, 100, 0 }, .velocity = @splat(0), .forward = .{ 0, 0, 1 }, .airborne = true };
    const old_target: Ref = .{ .ground = .{ .slot = 0, .generation = 7 } };
    try std.testing.expectEqual(@as(?V, .{ 0, 100, 100 }), sky.refPosition(&enemies, old_target));
    try std.testing.expect(std.meta.eql(old_target, sky.lockCandidate(&enemies, jet).?));
    sky.guns.lock = old_target;
    sky.guns.lock_progress = 1;
    sky.shots[0] = .{ .kind = .missile, .position = .{ 0, 100, 0 }, .velocity = .{ 0, 0, 60 }, .damage = 150, .life = 5, .homing = old_target };

    // The former unit dies and another unit takes slot zero at a different location.
    enemies.units[0] = .{ .generation = 8, .kind = .drone, .nest = 0, .position = .{ 100, 100, 0 }, .health = 60, .orbit = 0 };
    try std.testing.expect(sky.refPosition(&enemies, old_target) == null);
    try std.testing.expect(sky.lockPosition(&enemies) == null);
    const new_jet: Jet = .{ .position = .{ 100, 100, -100 }, .velocity = @splat(0), .forward = .{ 0, 0, 1 }, .airborne = true };
    const new_target = sky.lockCandidate(&enemies, new_jet).?;
    try std.testing.expect(std.meta.eql(new_target, Ref{ .ground = .{ .slot = 0, .generation = 8 } }));

    var events: [16]Event = undefined;
    _ = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
    try std.testing.expectApproxEqAbs(@as(f32, 0), sky.shots[0].?.velocity[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), sky.shots[0].?.velocity[2], 0.001);
}

test "nearby wasps steer away from each other" {
    var sky = Skies.init(4, .{ 0, 0, 0 }, &.{});
    sky.wasps[0] = .{ .position = .{ 0, 200, 0 }, .carrier = 0 };
    sky.wasps[1] = .{ .position = .{ 8, 200, 0 }, .carrier = 0 };
    try std.testing.expect(separation(&sky, 0, sky.wasps[0].?.position)[0] < 0);
    try std.testing.expect(separation(&sky, 1, sky.wasps[1].?.position)[0] > 0);
    sky.wasps[0] = .{ .position = .{ 5, 200, 0 }, .carrier = 0 };
    sky.wasps[1] = .{ .position = .{ 5, 200, 0 }, .carrier = 0 };
    const exact_a = separation(&sky, 0, sky.wasps[0].?.position);
    const exact_b = separation(&sky, 1, sky.wasps[1].?.position);
    try std.testing.expectEqual(@as(f32, 1), exact_a[0]);
    try std.testing.expectEqual(@as(f32, -1), exact_b[0]);
}

test "ramming a wasp and carrier damages both sides of the collision" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(12, .{ 0, 0, 0 }, &.{});
    sky.carriers[1].alive = false;
    sky.wasps[0] = .{ .position = .{ 0, 300, 0 }, .forward = .{ 0, 0, -1 }, .speed = 0, .carrier = 0 };
    const ram_jet: Jet = .{ .position = .{ 0, 300, -3 }, .velocity = .{ 0, 0, 100 }, .forward = .{ 0, 0, 1 }, .airborne = false };
    var events: [16]Event = undefined;
    var n = sky.step(&physics, &enemies, ram_jet, &.{}, 1.0 / 60.0, &events);
    var damage_to_jet = false;
    for (events[0..n]) |event| switch (event) {
        .jet_collision => |hit| damage_to_jet = hit.damage > 0 and hit.penetration > 0,
        else => {},
    };
    try std.testing.expect(damage_to_jet);
    try std.testing.expect(sky.wasps[0] == null or sky.wasps[0].?.health < wasp_health);

    sky = Skies.init(12, .{ 0, 0, 0 }, &.{});
    sky.carriers[1].alive = false;
    sky.carriers[0].launch = 1000;
    const hull = ShipMeshes.carrier_hull[0];
    const center = sky.carriers[0].point(hull[0]);
    const carrier_jet: Jet = .{ .position = .{ center[0], center[1], center[2] - 4 }, .velocity = .{ 0, 0, 100 }, .forward = .{ 0, 0, 1 }, .airborne = false };
    n = sky.step(&physics, &enemies, carrier_jet, &.{}, 1.0 / 60.0, &events);
    damage_to_jet = false;
    for (events[0..n]) |event| switch (event) {
        .jet_collision => |hit| damage_to_jet = hit.damage > 0 and hit.penetration > 0,
        else => {},
    };
    try std.testing.expect(damage_to_jet);
    try std.testing.expect(sky.carriers[0].turret_health[0] < tuning.carrier_turret_health);
}

test "carrier assault advances through turrets, bays, core, and a crashing wreck" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(27, .{ 0, 0, 0 }, &.{});
    sky.carriers[1].alive = false;
    sky.carriers[0].launch = 1000;
    const c = &sky.carriers[0];
    var events: [64]Event = undefined;
    var n: usize = 0;

    for (ShipMeshes.carrier_turrets) |turret| {
        const p = c.point(turret);
        const side = m.Quat.fromAxisAngle(m.Vec3.unit_y, c.yaw()).rotate(m.Vec3.unit_x);
        const dir: V = .{ side.x, side.y, side.z };
        try std.testing.expect(sky.strikeAlong(&enemies, R.sub(p, R.scale(dir, 100)), dir, 200, 0, 200, &events, &n));
    }
    try std.testing.expectEqual(AssaultStage.bays, c.stage());
    try std.testing.expectEqual(@as(usize, 0), c.activeTurrets());

    for (ShipMeshes.carrier_bays) |bay| {
        const p = c.point(bay);
        const side = m.Quat.fromAxisAngle(m.Vec3.unit_y, c.yaw()).rotate(m.Vec3.unit_x);
        const dir: V = .{ side.x, side.y, side.z };
        try std.testing.expect(sky.strikeAlong(&enemies, R.sub(p, R.scale(dir, 100)), dir, 200, 0, 100, &events, &n));
    }
    try std.testing.expectEqual(AssaultStage.core, c.stage());
    try std.testing.expectEqual(@as(usize, 0), c.activeBays());

    const core = c.point(m.Vec3.init(0, -10, -4));
    try std.testing.expect(sky.strikeAlong(&enemies, .{ core[0], core[1] + 100, core[2] }, .{ 0, -1, 0 }, 200, 0, 2000, &events, &n));
    try std.testing.expectEqual(AssaultStage.crashing, c.stage());
    try std.testing.expect(c.alive);
    for (0..60 * 12) |_| _ = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
    try std.testing.expect(!c.alive);
}

test "carriers circle, launch wasps near a player, and the wasps attack and hit" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(5, .{ 0, 0, 0 }, &.{});
    const c0 = sky.carriers[0].position();
    // A jet flying level near the first carrier.
    var jet: Jet = .{ .position = R.add(c0, .{ 0, -40, 250 }), .velocity = .{ 0, 0, 60 }, .forward = .{ 0, 0, 1 }, .airborne = true };
    var events: [64]Event = undefined;
    var hits: usize = 0;
    var flak: usize = 0;
    for (0..60 * 40) |_| {
        jet.position = R.add(jet.position, R.scale(jet.velocity, 1.0 / 60.0));
        if (jet.position[2] > c0[2] + 600) jet.velocity = .{ 0, 0, -60 };
        if (jet.position[2] < c0[2] - 100) jet.velocity = .{ 0, 0, 60 };
        const count = sky.step(&physics, &enemies, jet, &.{}, 1.0 / 60.0, &events);
        for (events[0..@min(count, events.len)]) |e| switch (e) {
            .jet_hit => hits += 1,
            .sound => |s| flak += @intFromBool(s.kind == .flak),
            else => {},
        };
    }
    try std.testing.expect(sky.waspCount(null) >= 3);
    try std.testing.expect(hits > 0 and flak > 0);
    // The carrier moved along its circuit at its speed.
    try std.testing.expect(dist(sky.carriers[0].position(), c0) > 300);
    // Wasps stay well above the ground.
    for (sky.wasps) |slot| if (slot) |w| try std.testing.expect(w.position[1] > Terrain.surface(5, w.position[0], w.position[2]).height + 5);
}

test "a wasp in front of a carrier bay takes the shot" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(2, .{ 0, 0, 0 }, &.{});
    sky.carriers[1].alive = false;
    const bay = sky.carriers[0].point(ShipMeshes.carrier_bays[0]);
    // Shoot straight up into the bay, with a wasp 6 m below it in the way.
    sky.wasps[0] = .{ .position = R.sub(bay, .{ 0, 6, 0 }), .carrier = 0 };
    var events: [8]Event = undefined;
    var n: usize = 0;
    const before = sky.carriers[0].health;
    try std.testing.expect(sky.strikeAlong(&enemies, R.sub(bay, .{ 0, 40, 0 }), .{ 0, 1, 0 }, 60, 0, 10, &events, &n));
    try std.testing.expectEqual(before, sky.carriers[0].health);
    try std.testing.expect(sky.wasps[0].?.health < wasp_health);
}

test "the jet's cannons down a wasp and a locked missile homes onto a carrier bay" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(9, .{ 0, 0, 0 }, &.{});
    sky.carriers[1].alive = false;
    sky.wasps[0] = .{ .position = .{ 0, 300, 120 }, .forward = .{ 0, 0, 1 }, .speed = 0, .carrier = 0 };
    const jet: Jet = .{ .position = .{ 0, 300, 0 }, .velocity = .{ 0, 0, 0 }, .forward = .{ 0, 0, 1 }, .airborne = false };
    var events: [64]Event = undefined;
    var down = false;
    for (0..120) |_| {
        var n: usize = 0;
        sky.wasps[0] = if (sky.wasps[0]) |w| blk: {
            var still = w;
            still.position = .{ 0, 300, 120 };
            still.speed = 0;
            break :blk still;
        } else null;
        sky.fireJet(&enemies, jet, .{ .{ 1, 300, 2 }, .{ -1, 300, 2 } }, true, false, 1.0 / 60.0, &events, &n);
        const count = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
        for (events[0..@min(count, events.len)]) |e| down = down or e == .wasp_down;
    }
    try std.testing.expect(down);

    // Lock the carrier: point at it, hold, release.
    const c = sky.carriers[0];
    const target = c.lockPoint().?;
    const from = R.add(target, .{ 0, 0, -400 });
    const at_carrier: Jet = .{ .position = from, .velocity = @splat(0), .forward = R.normalize(R.sub(target, from)), .airborne = true };
    var n: usize = 0;
    for (0..60) |_| sky.fireJet(&enemies, at_carrier, .{ from, from }, false, true, 1.0 / 60.0, &events, &n);
    try std.testing.expect(sky.guns.lock != null and sky.guns.lock_progress >= 1);
    sky.fireJet(&enemies, at_carrier, .{ from, from }, false, false, 1.0 / 60.0, &events, &n);
    const before = sky.carriers[0].turret_health[0];
    for (0..60 * 4) |_| _ = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
    try std.testing.expect(sky.carriers[0].turret_health[0] < before);
}

test "dragonflies are fragile interceptors and bomber raids can be defended or lost" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var sky = Skies.init(71, .{ 0, 0, 0 }, &.{});
    sky.carriers[0].alive = false;
    sky.carriers[1].alive = false;
    sky.wasps[0] = .{ .kind = .dragonfly, .position = .{ 0, 100, 100 }, .carrier = 0, .health = wasp_health * 0.55 };
    var events: [16]Event = undefined;
    var n: usize = 0;
    try std.testing.expect(sky.strikeAlong(&enemies, .{ 0, 100, 0 }, .{ 0, 0, 1 }, 150, 0, 40, &events, &n));
    try std.testing.expect(sky.wasps[0] == null); // one accurate rifle hit, versus three for a wasp

    sky = Skies.init(72, .{ 0, 0, 0 }, &.{});
    sky.carriers[0].alive = false;
    sky.carriers[1].alive = false;
    const plaza = sky.market_plazas[1];
    sky.raid_active = true;
    sky.raid_plaza = 1;
    sky.wasps[0] = .{ .kind = .beetle_bomber, .position = R.add(plaza, .{ 0, 24, -5 }), .forward = .{ 0, 0, 1 }, .speed = 0, .carrier = 0, .health = wasp_health * 2.2, .raid_target = plaza, .bomb_timer = 0 };
    sky.fireRanger(R.add(plaza, .{ 0, 24, -100 }), .{ 0, 0, 1 }, wasp_health * 3);
    n = 0;
    var defended = false;
    for (0..12) |_| {
        n = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
        for (events[0..n]) |event| defended = defended or event == .raid_repelled;
        if (defended) break;
    }
    try std.testing.expect(defended);

    sky.raid_active = true;
    sky.raid_plaza = 2;
    sky.raid_hits = 0;
    const target = sky.market_plazas[2];
    sky.wasps[0] = .{ .kind = .beetle_bomber, .position = R.add(target, .{ 0, 28, -2 }), .forward = .{ 0, 0, 1 }, .speed = 20, .carrier = 0, .health = wasp_health * 2.2, .raid_target = target, .bomb_timer = 0 };
    const players = [_]Enemies.Target{.{ .chest = target, .velocity = .{ 0, 0, 0 }, .alive = true }};
    var lost = false;
    for (0..900) |_| {
        n = sky.step(&physics, &enemies, null, &players, 1.0 / 60.0, &events);
        for (events[0..n]) |event| lost = lost or event == .raid_lost;
        if (lost) break;
    }
    try std.testing.expect(lost);
}

test "Kestrel missile rack capacity and cannon cooling scale with upgrades" {
    const Progress = @import("Progress.zig");
    var sky = Skies.init(91, .{ 0, 0, 0 }, &.{});
    var levels: [Progress.kestrel_upgrade_count]u8 = @splat(0);
    levels[@intFromEnum(Progress.KestrelUpgrade.missile_rack)] = 2;
    levels[@intFromEnum(Progress.KestrelUpgrade.gun_cooling)] = 2;
    sky.configureKestrel(levels);
    try std.testing.expectEqual(@as(u8, 6), sky.guns.missile_capacity);
    try std.testing.expectEqual(@as(u8, 6), sky.guns.missile_ammo);

    var enemies: Enemies = .{};
    const jet: Jet = .{ .position = .{ 0, 300, 0 }, .velocity = .{ 0, 0, 0 }, .forward = .{ 0, 0, 1 }, .airborne = true };
    var events: [8]Event = undefined;
    var n: usize = 0;
    sky.guns.heat = 80;
    sky.fireJetUpgraded(&enemies, jet, .{ .{ 0, 300, 0 }, .{ 0, 300, 0 } }, false, false, 1, levels, &events, &n);
    const upgraded_heat = sky.guns.heat;
    sky.guns.heat = 80;
    sky.fireJet(&enemies, jet, .{ .{ 0, 300, 0 }, .{ 0, 300, 0 } }, false, false, 1, &events, &n);
    try std.testing.expect(upgraded_heat < sky.guns.heat);
}
