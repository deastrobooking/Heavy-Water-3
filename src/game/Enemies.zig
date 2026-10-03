//! The Hive's forces in the outskirts. Three nests (dark spires) stand on seeded sites away from
//! the city and the grove; each fabricates drones and a sentinel while a player is in range.
//!
//! Drones and sentinels fly; troopers (the character generator in dark red Hive plate) walk the
//! ground, sliding along walls. Each unit patrols an orbit around its nest, and turns hostile when a player comes
//! within sight: close enough and with a clear line (a physics ray). It then circles at a
//! standoff distance, shooting bolts with lead and spread. It retreats to its nest when badly
//! hurt (drones only), and returns home past its leash. Units keep clear of the ground and
//! climb over whatever is ahead. Drones shoot single bolts; sentinels are slower and tougher,
//! and fire three-bolt bursts. Defeated units drop Hive alloy. A destroyed nest stops spawning,
//! drops a cache, and stays destroyed in the save (a story flag).
//!
//! Units far from every player stop thinking, so idle nests cost almost nothing.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Seed = @import("../procedural/Seed.zig");
const Terrain = @import("../procedural/Terrain.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Enemies = @This();

pub const Kind = enum { drone, sentinel, trooper };
/// Three nests on the surface, then one in the heart of each cave system.
pub const surface_nests = 3;
pub const max_nests = surface_nests + @import("../procedural/Caves.zig").max_systems;
pub const max_units = 24;
/// Cave nests field troopers only (fliers have no room), at most this many.
pub const cave_troopers = 4;
pub const max_bolts = 48;
pub const units_per_nest = 6;
pub const troopers_per_nest = 2;
pub const nest_radius: f32 = 4;
pub const nest_health: f32 = 900;
/// Players beyond this distance from a nest leave it dormant.
pub const wake_distance: f32 = 170;

pub const Stats = struct { health: f32, speed: f32, accel: f32, radius: f32, standoff: f32, sight: f32, cooldown: f32, burst: u8, damage: f32, bolt_speed: f32 };
pub fn stats(k: Kind) Stats {
    return switch (k) {
        .drone => .{ .health = 60, .speed = 11, .accel = 14, .radius = 0.7, .standoff = 13, .sight = 48, .cooldown = 1.3, .burst = 1, .damage = 5, .bolt_speed = 34 },
        .sentinel => .{ .health = 260, .speed = 6, .accel = 6, .radius = 1.6, .standoff = 22, .sight = 60, .cooldown = 2.8, .burst = 3, .damage = 8, .bolt_speed = 28 },
        .trooper => .{ .health = 120, .speed = 4.5, .accel = 12, .radius = 0.7, .standoff = 16, .sight = 45, .cooldown = 1.8, .burst = 2, .damage = 6, .bolt_speed = 32 },
    };
}

pub const State = enum { patrol, hunt, retreat };
pub const Unit = struct {
    kind: Kind,
    nest: u8,
    position: V,
    velocity: V = @splat(0),
    yaw: f32 = 0,
    health: f32,
    state: State = .patrol,
    /// Player index being hunted.
    target: u8 = 0,
    orbit: f32,
    cooldown: f32 = 1,
    burst_left: u8 = 0,
    burst_timer: f32 = 0,
    state_timer: f32 = 0,
    /// Seconds of hit flash left (rendering).
    flash: f32 = 0,
    /// Seconds stunned (by a saber finisher, an arc grenade or a slam): no thinking or shooting.
    stun: f32 = 0,
    /// Troopers: stride phase and amount for the walk animation.
    walk_phase: f32 = 0,
    walk_amount: f32 = 0,

    /// Where the unit is hit and shoots from: troopers' chests, other units' centres.
    pub fn center(u: Unit) V {
        return if (u.kind == .trooper) R.add(u.position, .{ 0, 1.2, 0 }) else u.position;
    }
};
/// `cave`: a nest in a cave's heart chamber (smaller; fields troopers only).
pub const Nest = struct { position: V, health: f32 = nest_health, alive: bool = true, spawn_timer: f32 = 2, flash: f32 = 0, cave: bool = false };
pub const Bolt = struct { position: V, velocity: V, damage: f32, life: f32 };

/// A player the Hive can see and shoot. A raised guard (saber or shield) facing the bolt takes a
/// quarter of its damage; a guard raised just in time parries it straight back.
pub const Target = struct { chest: V, velocity: V, alive: bool = true, guard: Guard = .none, facing: V = .{ 0, 0, 1 } };
pub const Guard = enum { none, guard, parry };
pub const Event = union(enum) {
    shot: V,
    player_hit: struct { player: u8, damage: f32, from: V },
    unit_down: struct { kind: Kind, position: V },
    nest_down: struct { nest: u8, position: V },
    /// A parried bolt flies back (the caller turns it into a player shot).
    deflected: struct { player: u8, position: V, velocity: V },
};

seed: u64 = 0,
nests: [max_nests]Nest = undefined,
nest_count: usize = 0,
units: [max_units]?Unit = @splat(null),
bolts: [max_bolts]?Bolt = @splat(null),
rng: std.Random.DefaultPrng = .init(0),

/// Picks nest sites on the terrain at least `clear` metres from every point in `avoid`
/// (Arbors, plazas, shrines, the spawn), on a ring around the spawn.
pub fn init(seed: u64, spawn: V, avoid: []const V, clear: f32) Enemies {
    var self: Enemies = .{ .seed = seed, .rng = .init(Seed.mix(seed ^ 0x48495645)) };
    const random = self.rng.random();
    var attempts: usize = 0;
    while (self.nest_count < surface_nests and attempts < 400) : (attempts += 1) {
        const angle = (@as(f32, @floatFromInt(self.nest_count)) + random.float(f32) * 0.7) * 2 * std.math.pi / surface_nests + 0.6;
        const r = 380 + random.float(f32) * 160;
        const x = spawn[0] + @sin(angle) * r;
        const z = spawn[2] + @cos(angle) * r;
        var ok = true;
        for (avoid) |p| {
            const dx = p[0] - x;
            const dz = p[2] - z;
            if (dx * dx + dz * dz < clear * clear) ok = false;
        }
        if (!ok) continue;
        self.nests[self.nest_count] = .{ .position = .{ x, Terrain.surface(seed, x, z).height, z } };
        self.nest_count += 1;
    }
    return self;
}

/// A nest in a cave's heart chamber, standing on its floor.
pub fn addCaveNest(self: *Enemies, floor: V) void {
    if (self.nest_count == max_nests) return;
    self.nests[self.nest_count] = .{ .position = floor, .cave = true, .health = nest_health * 0.7 };
    self.nest_count += 1;
}

pub fn unitCount(self: *const Enemies, nest: ?u8) usize {
    var n: usize = 0;
    for (self.units) |slot| if (slot) |u| {
        n += @intFromBool(nest == null or u.nest == nest.?);
    };
    return n;
}

fn spawnUnit(self: *Enemies, nest: u8) void {
    const random = self.rng.random();
    var sentinels: usize = 0;
    var troopers: usize = 0;
    for (self.units) |slot| if (slot) |u| if (u.nest == nest) {
        sentinels += @intFromBool(u.kind == .sentinel);
        troopers += @intFromBool(u.kind == .trooper);
    };
    const n = self.nests[nest];
    if (n.cave and troopers >= cave_troopers) return;
    const kind: Kind = if (n.cave) .trooper else if (sentinels == 0) .sentinel else if (troopers < troopers_per_nest) .trooper else .drone;
    const spread: f32 = if (n.cave) 3.5 else 7;
    for (&self.units) |*slot| if (slot.* == null) {
        // Fliers launch from the spire tip; troopers march out of its foot.
        const angle = random.float(f32) * 2 * std.math.pi;
        slot.* = .{
            .kind = kind,
            .nest = nest,
            .position = if (kind == .trooper) R.add(n.position, .{ @sin(angle) * spread, 0.5, @cos(angle) * spread }) else R.add(n.position, .{ 0, 24, 0 }),
            .health = stats(kind).health,
            .orbit = random.float(f32) * 2 * std.math.pi,
        };
        return;
    };
}

fn horizontal(v: V) f32 {
    return @sqrt(v[0] * v[0] + v[2] * v[2]);
}

fn sees(physics: *const Physics, from: V, to: V) bool {
    const d = R.sub(to, from);
    const length = R.length(d);
    if (length < 0.1) return true;
    return physics.castRay(from, R.scale(d, 1 / length), length - 0.6, .none) == null;
}

/// One fixed step. Events (shots, hits on players, units and nests destroyed) go to `out`.
pub fn step(self: *Enemies, physics: *const Physics, players: []const Target, dt: f32, out: []Event) usize {
    var n: usize = 0;
    const push = struct {
        fn f(o: []Event, count: *usize, e: Event) void {
            if (count.* < o.len) o[count.*] = e;
            count.* += 1;
        }
    }.f;
    const random = self.rng.random();

    // Nests: wake near players and fabricate up to their quota.
    for (self.nests[0..self.nest_count], 0..) |*nest, ni| {
        nest.flash = @max(0, nest.flash - dt);
        if (!nest.alive or !nearAny(players, nest.position, wake_distance)) continue;
        nest.spawn_timer -= dt;
        if (nest.spawn_timer <= 0 and self.unitCount(@intCast(ni)) < units_per_nest) {
            self.spawnUnit(@intCast(ni));
            nest.spawn_timer = 9;
        }
    }

    for (&self.units) |*slot| {
        const u = &(slot.* orelse continue);
        const s = stats(u.kind);
        const nest = self.nests[u.nest];
        // Dormant when no player is anywhere near (keeps distant nests free).
        if (!nearAny(players, u.position, wake_distance + 40)) continue;
        u.flash = @max(0, u.flash - dt);
        if (u.stun > 0) {
            // Reeling: carried by the knockback, slowing, no thought or fire.
            u.stun = @max(0, u.stun - dt);
            u.burst_left = 0;
            u.position = R.add(u.position, R.scale(u.velocity, dt));
            u.velocity = R.scale(u.velocity, 1 / (1 + 3 * dt));
            if (u.kind == .trooper) {
                if (physics.castRay(R.add(u.position, .{ 0, 1.2, 0 }), .{ 0, -1, 0 }, 30, .none)) |floor| u.position[1] = floor.point[1];
                u.walk_amount = 0;
            }
            continue;
        }
        u.cooldown = @max(0, u.cooldown - dt);
        u.state_timer = @max(0, u.state_timer - dt);

        // Senses: the nearest visible living player within sight.
        var seen: ?u8 = null;
        var seen_distance: f32 = s.sight;
        for (players, 0..) |p, pi| {
            if (!p.alive) continue;
            const d = R.length(R.sub(p.chest, u.center()));
            if (d < seen_distance and sees(physics, u.center(), p.chest)) {
                seen = @intCast(pi);
                seen_distance = d;
            }
        }
        const from_nest = horizontal(R.sub(u.position, nest.position));
        switch (u.state) {
            .patrol => if (seen) |pi| {
                u.state = .hunt;
                u.target = pi;
                u.cooldown = @max(u.cooldown, 0.6);
            },
            .hunt => {
                if (u.kind == .drone and u.health < s.health * 0.3) {
                    u.state = .retreat;
                    u.state_timer = 4;
                } else if (from_nest > 110 or !players[u.target].alive or (seen == null and u.state_timer == 0 and R.length(R.sub(players[u.target].chest, u.position)) > s.sight * 1.4)) {
                    u.state = .patrol;
                } else if (seen) |pi| {
                    u.target = pi;
                    u.state_timer = 3;
                }
            },
            .retreat => if (u.state_timer == 0) {
                u.state = if (seen != null) .hunt else .patrol;
            },
        }

        // Where to go.
        u.orbit += dt * (if (u.state == .hunt) @as(f32, 0.45) else 0.25) * (if (u.kind == .drone) @as(f32, 1) else 0.6);
        var goal: V = undefined;
        switch (u.state) {
            .patrol, .retreat => {
                const r: f32 = if (u.state == .retreat) 6 else 20 + @as(f32, @floatFromInt(u.nest % 3)) * 3;
                goal = R.add(nest.position, .{ @sin(u.orbit) * r, 16 + @sin(u.orbit * 2.3) * 3, @cos(u.orbit) * r });
            },
            .hunt => {
                const p = players[u.target].chest;
                goal = R.add(p, .{ @sin(u.orbit) * s.standoff, 5 + @sin(u.orbit * 1.7) * 2, @cos(u.orbit) * s.standoff });
            },
        }
        if (u.kind == .trooper) {
            walkGround(physics, u, goal, s, dt);
        } else {
            flyToward(physics, u, goal, s, dt);
        }
        // Face the target while hunting, the direction of travel otherwise.
        const facing = if (u.state == .hunt) R.sub(players[u.target].chest, u.center()) else u.velocity;
        if (horizontal(facing) > 0.1) u.yaw = std.math.atan2(facing[0], facing[2]);
        self.shoot(u, s, players, seen, seen_distance, dt, random, out, &n);
    }

    // Bolts: fly, hit players (a 0.6 m chest sphere) or the world, or fade.
    for (&self.bolts) |*slot| {
        const b = &(slot.* orelse continue);
        b.life -= dt;
        if (b.life <= 0) {
            slot.* = null;
            continue;
        }
        const travel = R.scale(b.velocity, dt);
        const length = R.length(travel);
        const dir = R.scale(travel, 1 / @max(length, 1e-4));
        var hit_player: ?u8 = null;
        var best = length;
        for (players, 0..) |p, pi| {
            if (!p.alive) continue;
            if (segmentSphere(b.position, dir, length, p.chest, 0.6)) |t| if (t < best) {
                best = t;
                hit_player = @intCast(pi);
            };
        }
        const wall = physics.castRay(b.position, dir, best, .none);
        if (wall == null) if (hit_player) |pi| {
            const p = players[pi];
            const facing_bolt = R.dot(R.scale(dir, -1), p.facing) > 0.2;
            if (p.guard == .parry and facing_bolt) {
                // Straight back the way it came.
                push(out, &n, .{ .deflected = .{ .player = pi, .position = R.sub(b.position, R.scale(dir, 0.5)), .velocity = R.scale(b.velocity, -1.2) } });
            } else {
                const damage = if (p.guard == .guard and facing_bolt) b.damage * 0.25 else b.damage;
                push(out, &n, .{ .player_hit = .{ .player = pi, .damage = damage, .from = R.sub(b.position, R.scale(dir, 5)) } });
            }
            slot.* = null;
            continue;
        };
        if (wall != null) {
            slot.* = null;
            continue;
        }
        b.position = R.add(b.position, travel);
    }
    return n;
}

/// Fliers: steer toward the goal within their acceleration and speed, keep clear of the ground,
/// and climb over whatever is ahead.
fn flyToward(physics: *const Physics, u: *Unit, goal: V, s: Stats, dt: f32) void {
    const to_goal = R.sub(goal, u.position);
    const dist = R.length(to_goal);
    const desired = if (dist > 0.01) R.scale(to_goal, @min(s.speed, dist * 1.2) / dist) else @as(V, @splat(0));
    var dv = R.sub(desired, u.velocity);
    const dv_len = R.length(dv);
    if (dv_len > s.accel * dt) dv = R.scale(dv, s.accel * dt / dv_len);
    u.velocity = R.add(u.velocity, dv);
    if (physics.castRay(u.position, .{ 0, -1, 0 }, 4, .none) != null) u.velocity[1] = @max(u.velocity[1], 4);
    const speed = R.length(u.velocity);
    if (speed > 0.5) {
        if (physics.castRay(u.position, R.scale(u.velocity, 1 / speed), 2 + speed * 0.6, .none)) |hit| {
            u.velocity = R.add(R.scale(u.velocity, 0.6), R.add(R.scale(hit.normal, 3), .{ 0, 5, 0 }));
        }
    }
    u.position = R.add(u.position, R.scale(u.velocity, dt));
}

/// Troopers: walk the horizontal part of the way to the goal on whatever floor is below, and
/// slide along walls instead of walking into them.
fn walkGround(physics: *const Physics, u: *Unit, goal: V, s: Stats, dt: f32) void {
    var to_goal = R.sub(goal, u.position);
    to_goal[1] = 0;
    const dist = horizontal(to_goal);
    const desired = if (dist > 0.4) R.scale(to_goal, @min(s.speed, dist) / dist) else @as(V, @splat(0));
    var dv = R.sub(desired, .{ u.velocity[0], 0, u.velocity[2] });
    const dv_len = R.length(dv);
    if (dv_len > s.accel * dt) dv = R.scale(dv, s.accel * dt / dv_len);
    u.velocity = .{ u.velocity[0] + dv[0], 0, u.velocity[2] + dv[2] };
    const speed = horizontal(u.velocity);
    if (speed > 0.1) {
        const dir = R.scale(u.velocity, 1 / speed);
        if (physics.castRay(u.center(), dir, 0.9 + speed * dt, .none)) |hit| {
            // Remove the part of the motion into the wall.
            const into = R.dot(u.velocity, hit.normal);
            if (into < 0) u.velocity = R.sub(u.velocity, R.scale(hit.normal, into));
            u.velocity[1] = 0;
        }
    }
    var next = R.add(u.position, R.scale(u.velocity, dt));
    // Stand on the floor below (decks, roofs or terrain), stepping up small ledges.
    if (physics.castRay(R.add(next, .{ 0, 1.2, 0 }), .{ 0, -1, 0 }, 30, .none)) |floor| {
        next[1] = floor.point[1];
    } else {
        next = u.position;
        u.velocity = @splat(0);
    }
    u.position = next;
    u.walk_amount = @min(1, horizontal(u.velocity) / s.speed);
    u.walk_phase = @mod(u.walk_phase + horizontal(u.velocity) * dt * 2.4, 2 * std.math.pi);
}

/// Starts a burst when hunting a visible target, and fires its bolts with lead and spread.
fn shoot(self: *Enemies, u: *Unit, s: Stats, players: []const Target, seen: ?u8, seen_distance: f32, dt: f32, random: std.Random, out: []Event, n: *usize) void {
    if (u.state == .hunt and seen != null and seen.? == u.target and seen_distance < s.sight) {
        if (u.burst_left == 0 and u.cooldown == 0) {
            u.burst_left = s.burst;
            u.burst_timer = 0;
            u.cooldown = s.cooldown;
        }
    }
    if (u.burst_left == 0) return;
    u.burst_timer -= dt;
    if (u.burst_timer > 0) return;
    u.burst_left -= 1;
    u.burst_timer = 0.18;
    const p = players[u.target];
    const muzzle = if (u.kind == .trooper) R.add(u.center(), .{ 0, 0.2, 0 }) else R.add(u.position, .{ 0, -0.2, 0 });
    const t = R.length(R.sub(p.chest, muzzle)) / s.bolt_speed;
    const aim = R.add(p.chest, R.scale(p.velocity, t * 0.8));
    var dir = R.normalize(R.sub(aim, muzzle));
    // Spread wide enough that a moving ranger dodges much of a volley.
    dir = R.normalize(R.add(dir, .{ (random.float(f32) - 0.5) * 0.14, (random.float(f32) - 0.5) * 0.08, (random.float(f32) - 0.5) * 0.14 }));
    self.fire(muzzle, R.scale(dir, s.bolt_speed), s.damage);
    if (n.* < out.len) out[n.*] = .{ .shot = muzzle };
    n.* += 1;
}

fn fire(self: *Enemies, from: V, velocity: V, damage: f32) void {
    for (&self.bolts) |*slot| if (slot.* == null) {
        slot.* = .{ .position = from, .velocity = velocity, .damage = damage, .life = 3 };
        return;
    };
}

fn nearAny(players: []const Target, p: V, d: f32) bool {
    for (players) |t| {
        const x = R.sub(t.chest, p);
        if (x[0] * x[0] + x[2] * x[2] < d * d) return true;
    }
    return false;
}

/// Distance along a unit ray to a sphere, if it is hit within `length`.
pub fn segmentSphere(origin: V, dir: V, length: f32, center: V, radius: f32) ?f32 {
    const oc = R.sub(origin, center);
    const b = R.dot(oc, dir);
    const c = R.dot(oc, oc) - radius * radius;
    if (c <= 0) return 0;
    const disc = b * b - c;
    if (disc < 0) return null;
    const t = -b - @sqrt(disc);
    return if (t >= 0 and t <= length) t else null;
}

/// Damage to whatever a player attack hits: the nearest unit or nest along a segment (radius
/// `pad` widens it, for big shots). Returns the distance hit, or null.
pub fn strikeAlong(self: *Enemies, origin: V, dir: V, length: f32, pad: f32, damage: f32, out: []Event, n: *usize) ?f32 {
    var done: u32 = 0;
    return self.strikeThrough(origin, dir, length, pad, damage, 1, &done, out, n);
}

/// A piercing attack: damage to the first `count` units along the segment, skipping those in
/// `done` (and adding the ones it hits); a nest stops it. Returns the distance of the last hit.
pub fn strikeThrough(self: *Enemies, origin: V, dir: V, length: f32, pad: f32, damage: f32, count: u8, done: *u32, out: []Event, n: *usize) ?f32 {
    var last: ?f32 = null;
    for (0..count) |_| {
        var best = length;
        var unit: ?usize = null;
        var nest: ?usize = null;
        for (self.units, 0..) |slot, i| if (slot) |u| {
            if (done.* & (@as(u32, 1) << @intCast(i)) != 0) continue;
            if (segmentSphere(origin, dir, best, u.center(), stats(u.kind).radius + pad)) |t| {
                best = t;
                unit = i;
            }
        };
        for (self.nests[0..self.nest_count], 0..) |nst, i| {
            if (!nst.alive) continue;
            // The spire as a stack of spheres up its lower half.
            var k: f32 = 0;
            while (k < 3) : (k += 1) {
                const c = R.add(nst.position, .{ 0, 3 + k * 4, 0 });
                if (segmentSphere(origin, dir, best, c, nest_radius - k + pad)) |t| {
                    best = t;
                    nest = i;
                    unit = null;
                }
            }
        }
        if (unit == null and nest == null) break;
        last = best;
        if (nest) |i| {
            self.damageNest(@intCast(i), damage, out, n);
            break;
        }
        done.* |= @as(u32, 1) << @intCast(unit.?);
        self.damageUnit(unit.?, damage, out, n);
    }
    return last;
}

/// A blade: damage, knockback and stun to every unit (and nest) within `radius` of the segment,
/// each at most once per swing (`units_hit`/`nests_hit` remember who was cut).
pub fn strikeBlade(self: *Enemies, origin: V, dir: V, length: f32, radius: f32, damage: f32, knock: V, stun: f32, units_hit: *u32, nests_hit: *u16, out: []Event, n: *usize) usize {
    var hits: usize = 0;
    for (&self.units, 0..) |*slot, i| if (slot.*) |u| {
        const bit = @as(u32, 1) << @intCast(i);
        if (units_hit.* & bit != 0) continue;
        if (distanceToSegment(u.center(), origin, dir, length) > radius + stats(u.kind).radius) continue;
        units_hit.* |= bit;
        hits += 1;
        self.damageUnit(i, damage, out, n);
        if (slot.*) |*alive| {
            // Heavier units are pushed less.
            const mass: f32 = switch (alive.kind) {
                .drone => 1,
                .trooper => 1.6,
                .sentinel => 4,
            };
            alive.velocity = R.add(alive.velocity, R.scale(knock, 1 / mass));
            alive.stun = @max(alive.stun, stun / mass);
        }
    };
    for (self.nests[0..self.nest_count], 0..) |nst, i| {
        const bit = @as(u16, 1) << @intCast(i);
        if (!nst.alive or nests_hit.* & bit != 0) continue;
        if (distanceToSegment(R.add(nst.position, .{ 0, 3, 0 }), origin, dir, length) > radius + nest_radius) continue;
        nests_hit.* |= bit;
        hits += 1;
        self.damageNest(@intCast(i), damage, out, n);
    }
    return hits;
}

/// Bolts within `radius` of a swinging blade are cut out of the air. Returns how many.
pub fn cutBolts(self: *Enemies, origin: V, dir: V, length: f32, radius: f32) usize {
    var cut: usize = 0;
    for (&self.bolts) |*slot| if (slot.*) |b| {
        if (distanceToSegment(b.position, origin, dir, length) <= radius) {
            slot.* = null;
            cut += 1;
        }
    };
    return cut;
}

/// Stun (and push away from `center`) every unit within `radius`: arc grenades and slams.
pub fn shock(self: *Enemies, center: V, radius: f32, stun: f32, push_speed: f32) usize {
    var n: usize = 0;
    for (&self.units) |*slot| if (slot.*) |*u| {
        const d = R.sub(u.center(), center);
        const dist = R.length(d);
        if (dist > radius) continue;
        const away = if (dist > 0.1) R.scale(d, 1 / dist) else @as(V, .{ 0, 1, 0 });
        u.velocity = R.add(u.velocity, R.scale(R.add(away, .{ 0, 0.4, 0 }), push_speed * (1 - dist / radius)));
        u.stun = @max(u.stun, stun);
        n += 1;
    };
    return n;
}

/// Damage to everything within `half_width` of the segment from `origin` along `dir` (beams).
pub fn strikeCapsule(self: *Enemies, origin: V, dir: V, length: f32, half_width: f32, damage: f32, out: []Event, n: *usize) usize {
    var hits: usize = 0;
    for (&self.units, 0..) |*slot, i| if (slot.*) |u| {
        if (distanceToSegment(u.center(), origin, dir, length) <= half_width + stats(u.kind).radius) {
            self.damageUnit(i, damage, out, n);
            hits += 1;
        }
    };
    for (self.nests[0..self.nest_count], 0..) |nst, i| {
        if (nst.alive and distanceToSegment(R.add(nst.position, .{ 0, 6, 0 }), origin, dir, length) <= half_width + nest_radius) {
            self.damageNest(@intCast(i), damage, out, n);
            hits += 1;
        }
    }
    return hits;
}

fn distanceToSegment(p: V, origin: V, dir: V, length: f32) f32 {
    const t = std.math.clamp(R.dot(R.sub(p, origin), dir), 0, length);
    return R.length(R.sub(p, R.add(origin, R.scale(dir, t))));
}

/// Damage to every unit and nest within `radius` of `center` (blasts, saber arcs).
pub fn strikeArea(self: *Enemies, center: V, radius: f32, damage: f32, facing: ?V, out: []Event, n: *usize) usize {
    var hits: usize = 0;
    for (&self.units, 0..) |*slot, i| if (slot.*) |u| {
        const d = R.sub(u.center(), center);
        const dist = R.length(d);
        if (dist > radius + stats(u.kind).radius) continue;
        // A saber only cuts in front.
        if (facing) |f| if (dist > 0.5 and R.dot(R.scale(d, 1 / dist), f) < 0.2) continue;
        self.damageUnit(i, damage, out, n);
        hits += 1;
    };
    for (self.nests[0..self.nest_count], 0..) |nst, i| {
        if (!nst.alive) continue;
        const d = R.sub(R.add(nst.position, .{ 0, 3, 0 }), center);
        if (horizontal(d) < radius + nest_radius and @abs(d[1]) < 8) {
            self.damageNest(@intCast(i), damage, out, n);
            hits += 1;
        }
    }
    return hits;
}

fn damageUnit(self: *Enemies, i: usize, damage: f32, out: []Event, n: *usize) void {
    const u = &(self.units[i] orelse return);
    u.health -= damage;
    u.flash = 0.15;
    // Being shot reveals the shooter.
    if (u.state == .patrol) {
        u.state = .hunt;
        u.state_timer = 4;
    }
    if (u.health <= 0) {
        if (n.* < out.len) out[n.*] = .{ .unit_down = .{ .kind = u.kind, .position = u.center() } };
        n.* += 1;
        self.units[i] = null;
    }
}

fn damageNest(self: *Enemies, i: u8, damage: f32, out: []Event, n: *usize) void {
    const nest = &self.nests[i];
    if (!nest.alive) return;
    nest.health -= damage;
    nest.flash = 0.15;
    if (nest.health <= 0) {
        nest.alive = false;
        if (n.* < out.len) out[n.*] = .{ .nest_down = .{ .nest = i, .position = nest.position } };
        n.* += 1;
    }
}

/// The nearest living unit to `p` within `reach`, for homing missiles.
pub fn nearestUnit(self: *const Enemies, p: V, reach: f32) ?V {
    var best: ?V = null;
    var best_d = reach;
    for (self.units) |slot| if (slot) |u| {
        const d = R.length(R.sub(u.center(), p));
        if (d < best_d) {
            best_d = d;
            best = u.center();
        }
    };
    return best;
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "nest sites avoid landmarks and sleep until a player comes near" {
    const e = Enemies.init(42, .{ 0, 0, 0 }, &.{.{ 400, 0, 0 }}, 150);
    try std.testing.expect(e.nest_count == surface_nests);
    for (e.nests[0..e.nest_count]) |nest| {
        try std.testing.expect(horizontal(nest.position) > 370);
        try std.testing.expect(horizontal(R.sub(nest.position, .{ 400, 0, 0 })) >= 150);
    }
    var physics = testPhysics();
    defer physics.deinit();
    var far = e;
    var events: [16]Event = undefined;
    for (0..600) |_| _ = far.step(&physics, &.{.{ .chest = .{ 0, 1.4, 0 }, .velocity = @splat(0) }}, 1.0 / 60.0, &events);
    try std.testing.expectEqual(@as(usize, 0), far.unitCount(null));
}

test "a woken nest fabricates units that hunt, shoot, and can be destroyed" {
    var physics = testPhysics();
    defer physics.deinit();
    var e: Enemies = .{ .seed = 1, .rng = .init(1) };
    e.nests[0] = .{ .position = .{ 0, 0, 0 } };
    e.nest_count = 1;
    const player: Target = .{ .chest = .{ 30, 1.4, 0 }, .velocity = @splat(0) };
    var events: [64]Event = undefined;
    var hits: usize = 0;
    var shots: usize = 0;
    for (0..60 * 30) |_| {
        const count = e.step(&physics, &.{player}, 1.0 / 60.0, &events);
        for (events[0..@min(count, events.len)]) |ev| switch (ev) {
            .player_hit => hits += 1,
            .shot => shots += 1,
            else => {},
        };
    }
    try std.testing.expect(e.unitCount(0) >= 3);
    try std.testing.expect(shots > 5 and hits > 0);
    var hunting: usize = 0;
    for (e.units) |slot| if (slot) |u| {
        hunting += @intFromBool(u.state == .hunt);
    };
    try std.testing.expect(hunting > 0);

    // Strike every unit until it falls, then the nest.
    var n: usize = 0;
    for (e.units) |slot| if (slot) |u| {
        while (e.strikeArea(u.position, 0.5, 50, null, &events, &n) > 0 and e.unitCount(0) > 0) {}
    };
    while (e.nests[0].alive) _ = e.strikeArea(.{ 0, 3, 0 }, 1, 100, null, &events, &n);
    try std.testing.expect(!e.nests[0].alive);
    // A dead nest fabricates nothing more.
    for (&e.units) |*slot| slot.* = null;
    for (0..60 * 20) |_| _ = e.step(&physics, &.{player}, 1.0 / 60.0, &events);
    try std.testing.expectEqual(@as(usize, 0), e.unitCount(0));
}

test "troopers march out of the nest, keep to the ground, and hunt" {
    var physics = testPhysics();
    defer physics.deinit();
    var e: Enemies = .{ .seed = 3, .rng = .init(3) };
    e.nests[0] = .{ .position = .{ 0, 0, 0 } };
    e.nest_count = 1;
    var events: [64]Event = undefined;
    const player: Target = .{ .chest = .{ 25, 1.4, 0 }, .velocity = @splat(0) };
    for (0..60 * 40) |_| _ = e.step(&physics, &.{player}, 1.0 / 60.0, &events);
    var troopers: usize = 0;
    for (e.units) |slot| if (slot) |u| if (u.kind == .trooper) {
        troopers += 1;
        try std.testing.expectApproxEqAbs(@as(f32, 0), u.position[1], 0.01);
        try std.testing.expect(u.state == .hunt);
        try std.testing.expect(horizontal(R.sub(u.position, .{ 25, 0, 0 })) < 30);
    };
    try std.testing.expectEqual(@as(usize, troopers_per_nest), troopers);
}

test "a blade cuts each unit once per swing, knocks it back and stuns it; guards parry bolts" {
    var physics = testPhysics();
    defer physics.deinit();
    var e: Enemies = .{};
    e.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 0, 1, 1 }, .health = 200, .orbit = 0 };
    var events: [8]Event = undefined;
    var n: usize = 0;
    var hit: u32 = 0;
    var nests: u16 = 0;
    try std.testing.expectEqual(@as(usize, 1), e.strikeBlade(.{ -1, 1, 1 }, .{ 1, 0, 0 }, 2, 0.3, 40, .{ 0, 0, 8 }, 1, &hit, &nests, &events, &n));
    try std.testing.expectEqual(@as(usize, 0), e.strikeBlade(.{ -1, 1, 1 }, .{ 1, 0, 0 }, 2, 0.3, 40, .{ 0, 0, 8 }, 1, &hit, &nests, &events, &n));
    const u = e.units[0].?;
    try std.testing.expectEqual(@as(f32, 160), u.health);
    try std.testing.expect(u.velocity[2] > 5 and u.stun > 0.5);
    // A stunned unit does not shoot.
    e.units[0].?.state = .hunt;
    e.units[0].?.cooldown = 0;
    const player: Target = .{ .chest = .{ 0, 1.4, 6 }, .velocity = @splat(0), .guard = .parry, .facing = .{ 0, 0, -1 } };
    var shots: usize = 0;
    for (0..30) |_| {
        const c = e.step(&physics, &.{player}, 1.0 / 60.0, &events);
        for (events[0..@min(c, events.len)]) |ev| shots += @intFromBool(ev == .shot);
    }
    try std.testing.expectEqual(@as(usize, 0), shots);
    // A bolt into a parrying player comes back.
    e.bolts[0] = .{ .position = .{ 0, 1.4, 2 }, .velocity = .{ 0, 0, 30 }, .damage = 6, .life = 2 };
    var deflected = false;
    for (0..20) |_| {
        const c = e.step(&physics, &.{player}, 1.0 / 60.0, &events);
        for (events[0..@min(c, events.len)]) |ev| deflected = deflected or ev == .deflected;
    }
    try std.testing.expect(deflected);
    // A swinging blade cuts bolts.
    e.bolts[1] = .{ .position = .{ 0.5, 1, 1 }, .velocity = .{ 0, 0, -30 }, .damage = 6, .life = 2 };
    try std.testing.expectEqual(@as(usize, 1), e.cutBolts(.{ -1, 1, 1 }, .{ 1, 0, 0 }, 2, 0.4));
}

test "segment-sphere and line strikes find the nearest target" {
    try std.testing.expectApproxEqAbs(@as(f32, 4), segmentSphere(.{ 0, 0, 0 }, .{ 1, 0, 0 }, 10, .{ 5, 0, 0 }, 1).?, 1e-5);
    try std.testing.expect(segmentSphere(.{ 0, 0, 0 }, .{ 1, 0, 0 }, 3, .{ 5, 0, 0 }, 1) == null);
    var e: Enemies = .{};
    e.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ 10, 0, 0 }, .health = 60, .orbit = 0 };
    e.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 20, 0, 0 }, .health = 60, .orbit = 0 };
    var events: [4]Event = undefined;
    var n: usize = 0;
    try std.testing.expect(e.strikeAlong(.{ 0, 0, 0 }, .{ 1, 0, 0 }, 50, 0, 100, &events, &n) != null);
    try std.testing.expect(e.units[0] == null and e.units[1] != null);
    try std.testing.expectEqual(@as(usize, 1), n);
}
