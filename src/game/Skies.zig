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

pub const max_wasps = 14;
pub const max_carriers = 2;
pub const max_shots = 128;
pub const wasps_per_carrier = 6;
pub const carrier_health: f32 = 4200;
pub const wasp_health: f32 = 70;
pub const wasp_radius: f32 = 3.2;
/// A carrier wakes (launches, shoots) only with a player this close.
pub const wake_distance: f32 = 650;

pub const WaspState = enum { patrol, attack, breakoff, evade };
pub const Wasp = struct {
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
    launch: f32 = 4,
    turret_cooldown: [4]f32 = @splat(1),
    flash: f32 = 0,

    pub fn position(c: Carrier) V {
        return .{ c.center[0] + @sin(c.angle) * c.radius, c.altitude, c.center[2] + @cos(c.angle) * c.radius };
    }
    /// Heading: along the circuit's tangent.
    pub fn yaw(c: Carrier) f32 {
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
pub const carrier_speed: f32 = 16;

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
/// Something a missile can lock: a wasp, a carrier, or a ground Hive unit (by slot).
pub const Ref = union(enum) { wasp: u8, carrier: u8, ground: u8 };

/// The jet as the Hive sees it.
pub const Jet = struct { position: V, velocity: V, forward: V, airborne: bool };

pub const Event = union(enum) {
    sound: struct { kind: ShotKind, position: V },
    burst: V,
    jet_hit: f32,
    player_hit: struct { player: u8, damage: f32 },
    wasp_down: V,
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
};

seed: u64 = 0,
wasps: [max_wasps]?Wasp = @splat(null),
carriers: [max_carriers]Carrier = undefined,
shots: [max_shots]?Shot = @splat(null),
guns: Guns = .{},
rng: std.Random.DefaultPrng = .init(0),

/// Carrier circuits: beyond the first two nests as seen from `spawn` (or around `spawn` with no
/// nests), so the air war happens over the Hive's ground, not the city.
pub fn init(seed: u64, spawn: V, nests: []const V) Skies {
    var self: Skies = .{ .seed = seed, .rng = .init(Seed.mix(seed ^ 0x534b494553)) };
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
        c.angle += c.direction * carrier_speed / c.radius * dt;
        const pos = c.position();
        var near = false;
        if (jet) |j| near = near or dist(j.position, pos) < wake_distance;
        for (players) |p| near = near or (p.alive and dist(p.chest, pos) < wake_distance);
        if (!near) continue;
        c.launch -= dt;
        if (c.launch <= 0 and self.waspCount(@intCast(ci)) < wasps_per_carrier) {
            c.launch = 6;
            const bay = ShipMeshes.carrier_bays[random.uintLessThan(usize, 4)];
            for (&self.wasps) |*slot| if (slot.* == null) {
                slot.* = .{ .position = c.point(bay), .forward = R.normalize(R.add(c.velocity(), .{ 0, -8, 0 })), .carrier = @intCast(ci), .orbit = random.float(f32) * 6.28 };
                break;
            };
        }
        if (jet) |j| if (j.airborne) for (ShipMeshes.carrier_turrets, &c.turret_cooldown) |t, *cd| {
            cd.* = @max(0, cd.* - dt);
            const muzzle = c.point(t);
            const d = dist(j.position, muzzle);
            if (cd.* > 0 or d > 650) continue;
            cd.* = 1.1 + random.float(f32) * 0.6;
            const speed: f32 = 170;
            const lead = R.add(j.position, R.scale(j.velocity, d / speed));
            var dir = R.normalize(R.sub(lead, muzzle));
            dir = R.normalize(R.add(dir, .{ (random.float(f32) - 0.5) * 0.06, (random.float(f32) - 0.5) * 0.06, (random.float(f32) - 0.5) * 0.06 }));
            self.addShot(.{ .kind = .flak, .position = muzzle, .velocity = R.scale(dir, speed), .damage = 14, .life = d / speed + 0.4 });
            push(out, &n, .{ .sound = .{ .kind = .flak, .position = muzzle } });
        };
    }

    // Wasps.
    for (&self.wasps) |*slot| {
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
        if (jet) |j| if (j.airborne and dist(j.position, w.position) < 900) {
            w.target = 0;
            target_pos = j.position;
            target_vel = j.velocity;
        };
        if (target_pos == null) {
            var best: f32 = 500;
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
        if (target_pos == null and w.state == .attack) w.state = .patrol;
        if (target_pos != null and w.state == .patrol) w.state = .attack;

        var desired: V = w.forward;
        var speed: f32 = 85;
        switch (w.state) {
            .patrol => {
                w.orbit += dt * 0.35;
                const c = if (home.alive) home.position() else R.add(w.position, R.scale(w.forward, 50));
                desired = R.sub(R.add(c, .{ @sin(w.orbit) * 140, -20 + @sin(w.orbit * 1.9) * 15, @cos(w.orbit) * 140 }), w.position);
            },
            .attack => {
                const t = target_pos.?;
                const d = dist(t, w.position);
                const lead = R.add(t, R.scale(target_vel, d / 300 * 0.9));
                desired = R.sub(lead, w.position);
                speed = 115;
                if (d < 65) {
                    w.state = .breakoff;
                    w.timer = 2.2;
                    const away = R.normalize(R.sub(w.position, t));
                    w.jink = R.normalize(R.add(R.add(away, .{ 0, 0.7, 0 }), R.scale(R.cross(w.forward, .{ 0, 1, 0 }), if (random.boolean()) @as(f32, 0.8) else -0.8)));
                }
                // Fire when lined up.
                const aim = R.normalize(desired);
                if (R.dot(aim, w.forward) > 0.985 and d < 380 and w.cooldown == 0 and w.burst == 0) {
                    w.burst = 3;
                    w.burst_timer = 0;
                    w.cooldown = 1.6;
                }
            },
            .breakoff, .evade => {
                desired = w.jink;
                speed = 120;
                if (w.timer == 0) w.state = if (target_pos != null) .attack else .patrol;
            },
        }
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
        w.forward = turnToward(w.forward, desired, if (w.state == .attack) 1.5 else 1.9, dt);
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
                dir = R.normalize(R.add(dir, .{ (random.float(f32) - 0.5) * 0.04, (random.float(f32) - 0.5) * 0.04, (random.float(f32) - 0.5) * 0.04 }));
                self.addShot(.{ .kind = .sting, .position = muzzle, .velocity = R.add(R.scale(dir, 300), R.scale(w.forward, w.speed)), .damage = if (w.target == 0) 7 else 5, .life = 2 });
                push(out, &n, .{ .sound = .{ .kind = .sting, .position = muzzle } });
            }
        }
    }

    // Shots.
    for (&self.shots) |*slot| {
        const s = &(slot.* orelse continue);
        s.life -= dt;
        if (s.kind == .missile) {
            if (s.homing) |h| if (self.refPosition(enemies, h)) |p| {
                const speed = R.length(s.velocity);
                s.velocity = R.scale(turnToward(R.scale(s.velocity, 1 / speed), R.sub(p, s.position), 3.2, dt), speed);
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
            if (jet) |j| if (dist(s.position, j.position) < 14 or s.life <= 0) {
                if (dist(s.position, j.position) < 16) push(out, &n, .{ .jet_hit = s.damage });
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

fn refPosition(self: *const Skies, enemies: *const Enemies, r: Ref) ?V {
    return switch (r) {
        .wasp => |i| if (self.wasps[i]) |w| w.position else null,
        .carrier => |i| if (self.carriers[i].alive) self.carriers[i].point(m.Vec3.init(0, 0, 6)) else null,
        .ground => |i| if (enemies.units[i]) |u| u.center() else null,
    };
}

/// A player shot along a segment: the nearest wasp, carrier part, or ground Hive unit takes it.
fn strikeAlong(self: *Skies, enemies: *Enemies, origin: V, dir: V, length: f32, pad: f32, damage: f32, out: []Event, n: *usize) bool {
    var best = length;
    var hit: ?Ref = null;
    var weak = false;
    for (self.wasps, 0..) |slot, i| if (slot) |w| {
        if (Enemies.segmentSphere(origin, dir, best, w.position, wasp_radius + pad)) |t| {
            best = t;
            hit = .{ .wasp = @intCast(i) };
        }
    };
    for (self.carriers, 0..) |c, ci| if (c.alive) {
        for (ShipMeshes.carrier_hull) |sphere| if (Enemies.segmentSphere(origin, dir, best, c.point(sphere[0]), sphere[1].x + pad)) |t| {
            best = t;
            hit = .{ .carrier = @intCast(ci) };
            weak = false;
        };
        for (ShipMeshes.carrier_bays) |bay| if (Enemies.segmentSphere(origin, dir, best + 4, c.point(bay), 4.5 + pad)) |t| if (t <= best + 4) {
            best = @min(best, t);
            hit = .{ .carrier = @intCast(ci) };
            weak = true;
        };
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
                push(out, n, .{ .wasp_down = w.position });
                self.wasps[i] = null;
            }
        },
        .carrier => |i| {
            const c = &self.carriers[i];
            c.health -= damage * (if (weak) @as(f32, 2.5) else 1);
            c.flash = 0.12;
            if (c.health <= 0) {
                c.alive = false;
                push(out, n, .{ .carrier_down = .{ .carrier = i, .position = c.position() } });
                // Its wasps lose their mother and keep fighting where they are.
            }
        },
        .ground => {},
    }
    return true;
}

/// The Kestrel's weapons for one step: cannons while `fire` is held, missile lock while `alt`
/// is held (fired on release). `guns` are the muzzles in the world; `nose` the jet's forward.
pub fn fireJet(self: *Skies, enemies: *const Enemies, jet: Jet, guns: [2]V, fire: bool, alt: bool, dt: f32, out: []Event, n: *usize) void {
    const g = &self.guns;
    g.cooldown = @max(0, g.cooldown - dt);
    g.missile_cooldown = @max(0, g.missile_cooldown - dt);
    g.heat = @max(0, g.heat - 32 * dt);
    if (g.overheated and g.heat < 35) g.overheated = false;
    if (fire and !g.overheated and g.cooldown == 0) {
        g.cooldown = 1.0 / 12.0;
        g.heat += 6;
        if (g.heat >= 100) g.overheated = true;
        const muzzle = guns[g.side];
        g.side +%= 1;
        self.addShot(.{ .kind = .cannon, .position = muzzle, .velocity = R.add(R.scale(jet.forward, 520), jet.velocity), .damage = 9, .life = 1.8 });
        push(out, n, .{ .sound = .{ .kind = .cannon, .position = muzzle } });
    }
    // Missile lock: the Hive target nearest the nose within 25° and 1 km.
    if (alt) {
        const best = self.lockCandidate(enemies, jet);
        if (best != null and g.lock != null and std.meta.eql(best.?, g.lock.?)) {
            g.lock_progress = @min(1, g.lock_progress + dt / 0.7);
        } else {
            g.lock = best;
            g.lock_progress = 0;
        }
    }
    if (!alt and g.was_alt and g.missile_cooldown == 0) {
        g.missile_cooldown = 2.4;
        const homing = if (g.lock_progress >= 1) g.lock else null;
        const launch = R.scale(R.add(guns[0], guns[1]), 0.5);
        self.addShot(.{ .kind = .missile, .position = R.add(launch, .{ 0, -0.6, 0 }), .velocity = R.add(R.scale(jet.forward, 230), jet.velocity), .damage = 150, .life = 6, .homing = homing });
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
    var best_cos: f32 = @cos(m.radians(25));
    const consider = struct {
        fn f(p: V, j: Jet, ref: Ref, b: *?Ref, bc: *f32) void {
            const d = R.sub(p, j.position);
            const l = R.length(d);
            if (l > 1000 or l < 5) return;
            const c = R.dot(R.scale(d, 1 / l), j.forward);
            if (c > bc.*) {
                bc.* = c;
                b.* = ref;
            }
        }
    }.f;
    for (self.wasps, 0..) |slot, i| if (slot) |w| consider(w.position, jet, .{ .wasp = @intCast(i) }, &best, &best_cos);
    for (self.carriers, 0..) |c, i| if (c.alive) consider(c.position(), jet, .{ .carrier = @intCast(i) }, &best, &best_cos);
    for (enemies.units, 0..) |slot, i| if (slot) |u| consider(u.center(), jet, .{ .ground = @intCast(i) }, &best, &best_cos);
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
    const target = c.point(m.Vec3.init(0, 0, 6));
    const from = R.add(target, .{ 0, 0, -400 });
    const at_carrier: Jet = .{ .position = from, .velocity = @splat(0), .forward = R.normalize(R.sub(target, from)), .airborne = true };
    var n: usize = 0;
    for (0..60) |_| sky.fireJet(&enemies, at_carrier, .{ from, from }, false, true, 1.0 / 60.0, &events, &n);
    try std.testing.expect(sky.guns.lock != null and sky.guns.lock_progress >= 1);
    sky.fireJet(&enemies, at_carrier, .{ from, from }, false, false, 1.0 / 60.0, &events, &n);
    const before = sky.carriers[0].health;
    for (0..60 * 4) |_| _ = sky.step(&physics, &enemies, null, &.{}, 1.0 / 60.0, &events);
    try std.testing.expect(sky.carriers[0].health < before);
}
