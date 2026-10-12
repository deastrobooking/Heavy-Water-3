//! Bio-synth pets: wild animals the Hive fitted with cybernetic plates and a control collar.
//! Each waits somewhere on the meadow ring around the spawn, collar glowing Hive red. Territorial
//! animals retaliate when crowded; two energy-net hits weaken and snare them for a short time, so
//! a ranger can approach and catch one alive. Caught pets follow their ranger, fight the Hive,
//! gain levels from nearby takedowns, and do a happy trick when petted. Catch and progression
//! records are per-player; each ranger can have one pet out at a time.
//!
//! - **Plasma hound (GARU):** trots at heel and pounces, a short-range bite that hits hard.
//! - **Chitin falcon (SKYE):** circles overhead and dives with a lumen dart from range.
//! - **Root golem (MOSS):** lumbers close and slams the ground, catching every bot around it.
//! - **Lumen moth (LUMI):** flutters at the shoulder, zaps from range and mends nearby rangers.
//!
//! Bodies are cel-shaded puppets of spheres, plates and spikes (`draw`), animated procedurally:
//! a trotting gait, wing beats, a wagging tail, and attack and trick flourishes. Wild encounter
//! state is separate from the caught companion, so a net capture never uses lethal damage.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Physics = @import("../physics/Physics.zig");
const Enemies = @import("Enemies.zig");
const Skies = @import("Skies.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Seed = @import("../procedural/Seed.zig");
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Material = @import("../render/Material.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Q = [4]f32;
const Pets = @This();

pub const Species = enum(u8) { hound, falcon, golem, moth };
pub const count = enum_compat.fields(Species).len;
pub const max_level = 20;

pub const Info = struct {
    name: []const u8,
    kind: []const u8,
    flies: bool,
    /// Running pace (m/s) and how close it gets before attacking.
    speed: f32,
    reach: f32,
    cooldown: f32,
    /// Damage at level 1, and added per level.
    damage: f32,
    per_level: f32,
    coat: [3]f32,
    trim: [3]f32,
    plate: [3]f32,
    glow: [3]f32,
};

pub const roster = [count]Info{
    .{ .name = "GARU", .kind = "plasma hound", .flies = false, .speed = 8.5, .reach = 1.8, .cooldown = 0.9, .damage = 34, .per_level = 6, .coat = .{ 0.86, 0.52, 0.22 }, .trim = .{ 0.98, 0.84, 0.62 }, .plate = .{ 0.24, 0.28, 0.33 }, .glow = .{ 0.30, 0.92, 1.0 } },
    .{ .name = "SKYE", .kind = "chitin falcon", .flies = true, .speed = 11, .reach = 14, .cooldown = 1.2, .damage = 22, .per_level = 4, .coat = .{ 0.33, 0.42, 0.62 }, .trim = .{ 0.96, 0.92, 0.80 }, .plate = .{ 0.16, 0.62, 0.58 }, .glow = .{ 0.55, 1.0, 0.62 } },
    .{ .name = "MOSS", .kind = "root golem", .flies = false, .speed = 6, .reach = 2.6, .cooldown = 1.6, .damage = 40, .per_level = 7, .coat = .{ 0.50, 0.46, 0.40 }, .trim = .{ 0.36, 0.62, 0.28 }, .plate = .{ 0.34, 0.31, 0.28 }, .glow = .{ 0.62, 1.0, 0.35 } },
    .{ .name = "LUMI", .kind = "lumen moth", .flies = true, .speed = 9, .reach = 11, .cooldown = 1.4, .damage = 14, .per_level = 3, .coat = .{ 0.96, 0.93, 0.86 }, .trim = .{ 0.74, 0.62, 0.92 }, .plate = .{ 0.95, 0.62, 0.80 }, .glow = .{ 1.0, 0.82, 0.45 } },
};

pub fn info(s: Species) Info {
    return roster[@intFromEnum(s)];
}

/// Experience to reach `level + 1` from `level`: 60 per level, so level 2 takes 60, level 3 120
/// more, and so on.
pub fn levelFor(xp: u32) u8 {
    var level: u8 = 1;
    var need: u32 = 60;
    var left = xp;
    while (level < max_level and left >= need) {
        left -= need;
        level += 1;
        need += 60;
    }
    return level;
}

pub fn damage(s: Species, level: u8) f32 {
    const i = info(s);
    return i.damage + i.per_level * @as(f32, @floatFromInt(level -| 1));
}

/// Pet experience levels improve survivability alongside attack damage.
pub fn maxHealth(s: Species, level: u8) f32 {
    const base: f32 = switch (s) { .hound => 150, .falcon => 105, .golem => 240, .moth => 115 };
    return base + 12 * @as(f32, @floatFromInt(level -| 1));
}

/// Hover height of fliers over their ground.
pub const hover: f32 = 2.3;
/// Experience the pet earns for each Hive unit downed near it.
pub const xp_per_unit: u32 = 20;
pub const share_radius: f32 = 35;
/// First wild encounters are kept close enough to appear in the world around the starting meadow.
pub const encounter_radius_min: f32 = 48;
pub const encounter_radius_spread: f32 = 32;
pub const flee_radius: f32 = 22;
pub const flee_speed: f32 = 8.5;

pub const Spot = struct { position: V, yaw: f32 };

pub const Pet = struct {
    species: Species,
    position: V,
    velocity: V = @splat(0),
    yaw: f32 = 0,
    /// Stride phase and amount (0 standing, 1 full run), for the gait.
    gait: f32 = 0,
    stride: f32 = 0,
    /// Seconds left of an attack or trick flourish, and which one.
    action: f32 = 0,
    trick: bool = false,
    cooldown: f32 = 0.5,
    heal_timer: f32 = 4,
    health: f32 = 150,
    max_health: f32 = 150,
    hurt_cooldown: f32 = 0,
    engaged: bool = false,
};

pub const Event = union(enum) {
    /// An attack landed or swung, at a point (for a sound and a flash).
    attack: struct { species: Species, at: V },
    /// A nearby Hive flyer was hit, and may have been brought down.
    air_attack: struct { species: Species, at: V, downed: bool = false, raid_repelled: bool = false },
    hurt: struct { species: Species, at: V },
    /// The moth mended rangers within `radius` of `at` by `amount`.
    mend: struct { at: V, radius: f32, amount: f32 },
};

/// What a pet needs from its world each step: its ranger, the ground, and its level.
pub const Context = struct {
    owner: V,
    owner_yaw: f32,
    level: u8,
    seed: u64,
    physics: *const Physics,
    skies: *Skies,
};

pub const max_owners = 4;

spots: [count]Spot = undefined,
seed: u64 = 0,
placed: bool = false,
/// Shared wild encounters. Each ranger catches their own version of the animal.
wild_health: [count]f32 = @splat(100),
wild_attack_timer: [count]f32 = @splat(0),
wild_snared: [count]f32 = @splat(0),
/// Art review (`-Dshowcase=59`): draw the waiting pets as freed, in their ranger's colours.
showcase_free: bool = false,
/// The pet out with each player slot.
out: [max_owners]?Pet = @splat(null),

/// Seeded spots on a meadow ring near the spawn, each in its own sector.
pub fn place(self: *Pets, seed: u64, spawn: V) void {
    self.seed = seed;
    for (&self.spots, 0..) |*spot, i| {
        const salt = Seed.mix(seed ^ 0x5045545330 ^ @as(u64, i));
        const angle = (@as(f32, @floatFromInt(i)) + 0.25 + 0.5 * Seed.unit(salt)) * 2 * std.math.pi / count + 0.9;
        const r = encounter_radius_min + encounter_radius_spread * Seed.unit(Seed.mix(salt +% 1));
        const x = spawn[0] + @sin(angle) * r;
        const z = spawn[2] + @cos(angle) * r;
        spot.* = .{ .position = .{ x, Terrain.surface(seed, x, z).height, z }, .yaw = angle + std.math.pi };
    }
    self.wild_health = @splat(100);
    self.wild_attack_timer = @splat(0);
    self.wild_snared = @splat(0);
    self.placed = true;
}

/// Nets weaken a wild animal. Two hits leave it at capture health and briefly snared.
pub fn netHitWild(self: *Pets, species: Species, damage_amount: f32) bool {
    const k = @intFromEnum(species);
    if (self.wild_health[k] <= 0) return false;
    self.wild_health[k] = @max(1, self.wild_health[k] - @max(0, damage_amount));
    if (self.wild_health[k] <= 40) self.wild_snared[k] = 8;
    return true;
}

pub fn canCaptureWild(self: *const Pets, species: Species) bool {
    const k = @intFromEnum(species);
    return self.wild_health[k] <= 40 and self.wild_snared[k] > 0;
}

/// Wild animals flee when approached, then defend themselves if cornered. The net capture state
/// pins them in place while the player closes in to interact.
pub fn stepWild(self: *Pets, dt: f32, present: [max_owners]bool, owners: [max_owners]V, out: []Enemies.Event) usize {
    var n: usize = 0;
    if (!self.placed) return n;
    for (0..count) |k| {
        if (self.wild_health[k] <= 0) continue;
        self.wild_snared[k] = @max(0, self.wild_snared[k] - dt);
        self.wild_attack_timer[k] = @max(0, self.wild_attack_timer[k] - dt);
        var closest_player: ?usize = null;
        var closest_distance = std.math.inf(f32);
        for (present, 0..) |is_present, p| {
            if (!is_present) continue;
            const delta = R.sub(owners[p], self.spots[k].position);
            const distance = @sqrt(delta[0] * delta[0] + delta[2] * delta[2]);
            if (distance < closest_distance) {
                closest_distance = distance;
                closest_player = p;
            }
        }
        if (self.wild_snared[k] > 0 or closest_player == null) continue;
        if (closest_distance < 2.7 and self.wild_attack_timer[k] == 0) {
            const animal = R.add(self.spots[k].position, .{ 0, 0.9, 0 });
            const p = closest_player.?;
            if (n < out.len) out[n] = .{ .player_hit = .{ .player = @intCast(p), .damage = 8, .from = animal } };
            n += 1;
            self.wild_attack_timer[k] = 1.3;
        }
        if (closest_distance < flee_radius) {
            const ranger = owners[closest_player.?];
            const delta = R.sub(self.spots[k].position, ranger);
            var away = R.normalize(.{ delta[0], 0, delta[2] });
            if (R.length(away) < 0.1) away = .{ @sin(self.spots[k].yaw), 0, @cos(self.spots[k].yaw) };
            self.spots[k].position = R.add(self.spots[k].position, R.scale(away, flee_speed * dt));
            self.spots[k].position[1] = Terrain.surface(self.seed, self.spots[k].position[0], self.spots[k].position[2]).height;
            self.spots[k].yaw = std.math.atan2(-away[0], -away[2]);
            continue;
        }
    }
    return n;
}

/// Brings `species` out for player `owner` beside `at` (replacing any pet already out).
pub fn summon(self: *Pets, owner: usize, species: Species, at: V, level: u8) void {
    var p: V = R.add(at, .{ 1.2, 0, -1.2 });
    if (info(species).flies) p[1] += hover;
    const hp = maxHealth(species, level);
    self.out[owner] = .{ .species = species, .position = p, .health = hp, .max_health = hp };
}

/// A happy trick: a hop and a spin (or a loop, for fliers).
pub fn cheer(self: *Pets, owner: usize) void {
    if (self.out[owner]) |*p| {
        p.action = 0.9;
        p.trick = true;
    }
}

fn ground(ctx: Context, at: V) f32 {
    const terrain = Terrain.surface(ctx.seed, at[0], at[2]).height;
    // Decks, bridges and floors: the highest surface below a point a little above the ranger.
    const top = @max(at[1], ctx.owner[1]) + 2.5;
    if (ctx.physics.castRay(.{ at[0], top, at[2] }, .{ 0, -1, 0 }, 14, .none)) |hit| return @max(hit.point[1], terrain);
    return terrain;
}

/// One fixed step of player `owner`'s pet: follow, attack nearby Hive units or flyers, take
/// occasional close-range damage, recover after combat, and (the moth) mend.
pub fn step(self: *Pets, owner: usize, ctx: Context, enemies: *Enemies, dt: f32, hive: []Enemies.Event, hn: *usize, out: []Event) usize {
    var n: usize = 0;
    if (self.out[owner] == null) return 0;
    // Too far behind (a fast travel, a flight): catch up at once.
    if (R.length(R.sub(self.out[owner].?.position, ctx.owner)) > 60) self.summon(owner, self.out[owner].?.species, ctx.owner, ctx.level);
    const q = &self.out[owner].?;
    const i = info(q.species);
    const upgraded_max = maxHealth(q.species, ctx.level);
    if (upgraded_max > q.max_health) q.health = @min(upgraded_max, q.health + upgraded_max - q.max_health);
    q.max_health = upgraded_max;
    q.cooldown = @max(0, q.cooldown - dt);
    q.hurt_cooldown = @max(0, q.hurt_cooldown - dt);
    q.action = @max(0, q.action - dt);
    if (q.action == 0) q.trick = false;

    const owner_chest = R.add(ctx.owner, .{ 0, 1.2, 0 });
    var target = enemies.nearestUnit(owner_chest, 22);
    var target_wasp: ?u8 = null;
    if (ctx.skies.nearestWasp(owner_chest, 28)) |air| {
        const ground_distance = if (target) |g| R.length(R.sub(g, owner_chest)) else std.math.inf(f32);
        if (air.distance < ground_distance) {
            target = air.position;
            target_wasp = air.index;
        }
    }
    q.engaged = target != null and q.health > 0;
    const side: V = if (i.flies) .{ 0.9, 0, -0.9 } else .{ -1.1, 0, -1.4 };
    var goal = R.add(ctx.owner, R.rotate(R.axisAngle(.{ 0, 1, 0 }, ctx.owner_yaw), side));
    if (target) |t| {
        const away = R.sub(q.position, t);
        const flat = R.normalize(.{ away[0], 0, away[2] });
        goal = R.add(t, R.scale(flat, if (target_wasp != null) @as(f32, 6) else i.reach * 0.7));
    }
    const ground_at = ground(ctx, goal);
    goal[1] = if (i.flies) ground_at + hover + (if (target) |t| @max(0, t[1] - ground_at - 1) else 0) else ground_at;
    var to = R.sub(goal, q.position);
    if (!i.flies) to[1] = 0;
    const distance = R.length(to);
    const speed = if (distance > 12) i.speed * 1.8 else i.speed;
    const wish = if (distance > 0.25) R.scale(R.normalize(to), @min(speed, distance * 3)) else V{ 0, 0, 0 };
    q.velocity = R.add(q.velocity, R.scale(R.sub(wish, q.velocity), @min(1, 8 * dt)));
    q.position = R.add(q.position, R.scale(q.velocity, dt));
    if (!i.flies) q.position[1] = ground(ctx, q.position);
    const planar = @sqrt(q.velocity[0] * q.velocity[0] + q.velocity[2] * q.velocity[2]);
    q.stride = std.math.clamp(planar / i.speed, 0, 1);
    q.gait = @mod(q.gait + planar * dt * (if (q.species == .golem) @as(f32, 2.2) else 3.4), 2 * std.math.pi);
    // Face the way it runs, or the bot it fights.
    const look = if (target) |t| R.sub(t, q.position) else q.velocity;
    if (look[0] * look[0] + look[2] * look[2] > 0.01) {
        const want = std.math.atan2(look[0], look[2]);
        var turn = want - q.yaw;
        turn = @mod(turn + std.math.pi, 2 * std.math.pi) - std.math.pi;
        q.yaw += turn * @min(1, 10 * dt);
    }

    if (q.health > 0 and target_wasp != null and q.cooldown == 0) {
        const wasp_index = target_wasp.?;
        const wasp = ctx.skies.wasps[wasp_index] orelse return n;
        if (R.length(R.sub(wasp.position, q.position)) < 28) {
            const hit = ctx.skies.petStrikeWasp(wasp_index, damage(q.species, ctx.level) * 0.7) orelse return n;
            q.cooldown = i.cooldown;
            q.action = 0.45;
            q.trick = false;
            if (n < out.len) out[n] = .{ .air_attack = .{ .species = q.species, .at = hit.position, .downed = hit.downed, .raid_repelled = hit.raid_repelled } };
            n += 1;
        }
    } else if (q.health > 0) if (target) |t| if (q.cooldown == 0 and R.length(R.sub(t, q.position)) < i.reach + 1.2) {
        q.cooldown = i.cooldown;
        q.action = if (q.species == .golem) 0.7 else 0.45;
        q.trick = false;
        const dmg = damage(q.species, ctx.level);
        const dir = R.normalize(R.sub(t, q.position));
        switch (q.species) {
            .hound => _ = enemies.strikeArea(t, 1.6, dmg, null, hive, hn),
            .golem => _ = enemies.strikeArea(R.add(q.position, R.scale(.{ dir[0], 0, dir[2] }, 1.2)), 3.4, dmg, null, hive, hn),
            .falcon, .moth => _ = enemies.strikeAlong(q.position, dir, i.reach + 2, 0.6, dmg, hive, hn),
        }
        if (n < out.len) out[n] = .{ .attack = .{ .species = q.species, .at = t } };
        n += 1;
    };
    var threatened = target != null;
    for (enemies.units) |slot| if (slot) |u| {
        const distance_to_enemy = R.length(R.sub(u.center(), q.position));
        if (distance_to_enemy < 12) threatened = true;
        const melee = Enemies.stats(u.kind).melee_damage;
        if (q.health > 0 and q.hurt_cooldown == 0 and melee > 0 and u.state == .hunt and distance_to_enemy < 2.4) {
            q.health = @max(0, q.health - melee * 0.55);
            q.hurt_cooldown = 1.1;
            if (n < out.len) out[n] = .{ .hurt = .{ .species = q.species, .at = q.position } };
            n += 1;
            break;
        }
    };
    if (!threatened and q.hurt_cooldown == 0) q.health = @min(q.max_health, q.health + 10 * dt);
    if (q.species == .moth and q.health > 0) {
        q.heal_timer -= dt;
        if (q.heal_timer <= 0) {
            q.heal_timer = 5;
            if (n < out.len) out[n] = .{ .mend = .{ .at = q.position, .radius = 10, .amount = 8 + 1.5 * @as(f32, @floatFromInt(ctx.level)) } };
            n += 1;
        }
    }
    return n;
}

// ---------------------------------------------------------------- looks

/// Meshes the puppets are built from: a unit-diameter sphere, a unit cube and a unit spike
/// (base at the origin, tip at +y).
pub const Parts = struct { orb: Catalog.MeshHandle, block: Catalog.MeshHandle, spike: Catalog.MeshHandle };

pub const Pose = struct {
    position: V,
    yaw: f32,
    gait: f32 = 0,
    stride: f32 = 0,
    action: f32 = 0,
    trick: bool = false,
    engaged: bool = false,
    time: f32 = 0,
    /// Still wearing the Hive collar (red glow, spikes, dim eyes).
    wild: bool = false,
    /// The freed collar's glow: the ranger's accent.
    collar: [3]f32 = .{ 0.3, 0.9, 1.0 },
};

const Rig = struct {
    out: []World.Prop,
    n: usize,
    base: V,
    turn: Q,
    parts: Parts,

    fn put(r: *Rig, mesh: Catalog.MeshHandle, at: V, size: V, rot: Q, tint: [4]f32) void {
        if (r.n >= r.out.len) return;
        r.out[r.n] = .{ .mesh = mesh, .transform = .{ .position = R.add(r.base, R.rotate(r.turn, at)) }, .tint = tint, .size = size, .rotation = R.mul(r.turn, rot) };
        r.n += 1;
    }
    fn orb(r: *Rig, at: V, size: V, tint: [4]f32) void {
        r.put(r.parts.orb, at, size, R.identity, tint);
    }
    fn orbTurned(r: *Rig, at: V, size: V, rot: Q, tint: [4]f32) void {
        r.put(r.parts.orb, at, size, rot, tint);
    }
    fn block(r: *Rig, at: V, size: V, rot: Q, tint: [4]f32) void {
        r.put(r.parts.block, at, size, rot, tint);
    }
    /// A spike standing on `at`, pointing along `rot`'s +y.
    fn spike(r: *Rig, at: V, width: f32, length: f32, rot: Q, tint: [4]f32) void {
        r.put(r.parts.spike, at, .{ width, length, width }, rot, tint);
    }
    /// A limb segment hanging from `pivot`, swung by `rot`; returns its far end.
    fn limb(r: *Rig, mesh: Catalog.MeshHandle, pivot: V, rot: Q, length: f32, thick: V, tint: [4]f32) V {
        const end = R.add(pivot, R.rotate(rot, .{ 0, -length, 0 }));
        r.put(mesh, R.scale(R.add(pivot, end), 0.5), .{ thick[0], length + thick[1], thick[2] }, rot, tint);
        return end;
    }
};

fn solid(c: [3]f32, k: f32) [4]f32 {
    return .{ c[0] * k, c[1] * k, c[2] * k, 1 };
}

fn lit(c: [3]f32, strength: f32) [4]f32 {
    return Material.emissive(.{ c[0], c[1], c[2], 1 }, strength);
}

fn about(axis: V, angle: f32) Q {
    return R.axisAngle(axis, angle);
}

const x_axis: V = .{ 1, 0, 0 };
const y_axis: V = .{ 0, 1, 0 };
const z_axis: V = .{ 0, 0, 1 };
const hive_red: [3]f32 = .{ 1.0, 0.18, 0.32 };

/// Appends a pet's parts to `out` from `start`; returns the new count.
pub fn draw(species: Species, pose: Pose, parts: Parts, out: []World.Prop, start: usize) usize {
    // A trick: a hop and a full spin.
    var base = pose.position;
    var yaw = pose.yaw;
    if (pose.trick and pose.action > 0) {
        const k = 1 - pose.action / 0.9;
        base[1] += @sin(k * std.math.pi) * 0.45;
        yaw += k * 2 * std.math.pi;
    }
    var r: Rig = .{ .out = out, .n = start, .base = base, .turn = about(y_axis, yaw), .parts = parts };
    const i = info(species);
    const eye = if (pose.wild) lit(hive_red, 0.5) else lit(i.glow, 0.9);
    const collar = if (pose.wild) lit(hive_red, 0.8) else lit(pose.collar, 0.7);
    switch (species) {
        .hound => hound(&r, pose, i, eye, collar),
        .falcon => falcon(&r, pose, i, eye, collar),
        .golem => golem(&r, pose, i, eye, collar),
        .moth => moth(&r, pose, i, eye, collar),
    }
    return r.n;
}

fn hound(r: *Rig, pose: Pose, i: Info, eye: [4]f32, collar: [4]f32) void {
    const g = pose.gait;
    const s = pose.stride;
    const bob = @abs(@sin(g)) * 0.05 * s;
    // A pounce stretches forward and lunges.
    const lunge: f32 = if (!pose.trick and pose.action > 0) @sin((1 - pose.action / 0.45) * std.math.pi) * 0.35 else 0;
    const coat = solid(i.coat, 1);
    const belly = solid(i.trim, 1);
    const plate = solid(i.plate, 1);
    const dark = solid(.{ 0.1, 0.09, 0.1 }, 1);
    const y = 0.62 + bob;
    r.orb(.{ 0, y, -0.02 + lunge }, .{ 0.42, 0.40, 0.86 }, coat);
    r.orb(.{ 0, y + 0.03, 0.28 + lunge }, .{ 0.46, 0.46, 0.46 }, coat);
    r.orb(.{ 0, y - 0.07, 0.22 + lunge }, .{ 0.34, 0.3, 0.4 }, belly);
    // Cyber plates: a spine plate with a lit seam, and shoulder guards.
    r.block(.{ 0, y + 0.2, -0.04 + lunge }, .{ 0.28, 0.06, 0.6 }, about(x_axis, 0.05), plate);
    r.block(.{ 0, y + 0.235, -0.04 + lunge }, .{ 0.05, 0.02, 0.52 }, about(x_axis, 0.05), lit(i.glow, 0.8));
    for ([_]f32{ -1, 1 }) |side| r.block(.{ side * 0.215, y + 0.08, 0.3 + lunge }, .{ 0.07, 0.22, 0.28 }, about(z_axis, side * 0.15), plate);
    // Neck, collar and head.
    const head: V = .{ 0, y + 0.36 + 0.03 * @sin(pose.time * 3), 0.58 + lunge * 1.4 };
    r.orb(.{ 0, y + 0.2, 0.44 + lunge }, .{ 0.26, 0.34, 0.26 }, coat);
    r.orb(.{ 0, y + 0.18, 0.44 + lunge }, .{ 0.33, 0.1, 0.33 }, collar);
    if (pose.wild) for (0..5) |k| {
        const a = @as(f32, @floatFromInt(k)) / 5 * 2 * std.math.pi;
        r.spike(.{ @sin(a) * 0.16, y + 0.18, 0.44 + lunge + @cos(a) * 0.16 }, 0.05, 0.1, R.mul(about(y_axis, a), about(x_axis, std.math.pi / 2.0)), collar);
    };
    r.orb(head, .{ 0.36, 0.32, 0.36 }, coat);
    r.orb(R.add(head, .{ 0, -0.06, 0.2 }), .{ 0.2, 0.16, 0.26 }, belly);
    r.orb(R.add(head, .{ 0, -0.02, 0.33 }), .{ 0.08, 0.06, 0.06 }, dark);
    for ([_]f32{ -1, 1 }) |side| {
        r.orb(R.add(head, .{ side * 0.09, 0.05, 0.15 }), .{ 0.075, 0.075, 0.05 }, eye);
        // Tall, alert ears, with a lit inner edge.
        const ear = R.mul(about(z_axis, -side * 0.3), about(x_axis, -0.15));
        r.spike(R.add(head, .{ side * 0.1, 0.1, -0.02 }), 0.12, 0.24, ear, coat);
        r.spike(R.add(head, .{ side * 0.1, 0.11, 0.0 }), 0.05, 0.16, ear, lit(i.glow, 0.5));
    }
    // Legs: a trot (diagonal pairs together), armored shins and dark paws.
    const legs = [_]struct { at: V, phase: f32, knee: f32 }{
        .{ .at = .{ -0.15, y - 0.02, 0.3 }, .phase = 0, .knee = -0.35 },
        .{ .at = .{ 0.15, y - 0.02, 0.3 }, .phase = std.math.pi, .knee = -0.35 },
        .{ .at = .{ -0.15, y - 0.04, -0.3 }, .phase = std.math.pi, .knee = 0.45 },
        .{ .at = .{ 0.15, y - 0.04, -0.3 }, .phase = 0, .knee = 0.45 },
    };
    for (legs) |leg| {
        const swing = @sin(g + leg.phase) * 0.6 * s + (if (leg.at[2] > 0) -lunge * 1.2 else lunge * 0.8);
        const hip = R.add(leg.at, .{ 0, 0, lunge });
        const knee = r.limb(r.parts.orb, hip, about(x_axis, swing), 0.27, .{ 0.15, 0.1, 0.17 }, coat);
        const lift = @max(0, -@cos(g + leg.phase)) * 0.5 * s;
        const foot = r.limb(r.parts.block, knee, about(x_axis, swing + leg.knee * (0.4 + lift)), 0.27, .{ 0.1, 0.02, 0.11 }, plate);
        r.orb(R.add(foot, .{ 0, 0.02, 0.03 }), .{ 0.13, 0.07, 0.17 }, dark);
    }
    // A wagging tail, quicker when idle at heel, ending in a lit tuft.
    const wag = @sin(pose.time * (if (s < 0.2 and !pose.engaged) @as(f32, 11) else 5)) * (if (pose.wild) @as(f32, 0.15) else 0.55);
    var at: V = .{ 0, y + 0.1, -0.44 };
    for (0..4) |k| {
        const kf = @as(f32, @floatFromInt(k));
        const dir = R.rotate(about(y_axis, wag * (kf + 1) * 0.35), R.normalize(.{ 0, 0.55 - kf * 0.12, -0.8 }));
        at = R.add(at, R.scale(dir, 0.12));
        r.orb(at, @splat(0.13 - kf * 0.015), if (k == 3) lit(i.glow, 0.85) else coat);
    }
}

fn wing(r: *Rig, root: V, side: f32, flap: f32, sweep: f32, feathers: []const [3]f32, tints: []const [4]f32) void {
    // Each feather (span, chord, back offset) fans out from the root and beats with the flap,
    // pitched so the broad side faces the eye from the front as well as above.
    const rot = R.mul(R.mul(about(z_axis, side * flap), about(y_axis, side * sweep)), about(x_axis, -0.6));
    var reach: f32 = 0;
    for (feathers, 0..) |f, k| {
        const center = R.add(root, R.rotate(rot, .{ side * (reach + f[0] * 0.5), 0, -f[2] }));
        r.block(center, .{ f[0], 0.025, f[1] }, rot, tints[k]);
        reach += f[0] * 0.55;
    }
}

fn falcon(r: *Rig, pose: Pose, i: Info, eye: [4]f32, collar: [4]f32) void {
    const t = pose.time;
    // A dive: tuck the wings and pitch down.
    const dive: f32 = if (!pose.trick and pose.action > 0) @sin((1 - pose.action / 0.45) * std.math.pi) else 0;
    const beat = (if (pose.stride > 0.5) @as(f32, 13) else 9);
    const flap = @sin(t * beat) * 0.75 * (1 - dive) + 0.1;
    const coat = solid(i.coat, 1);
    const cream = solid(i.trim, 1);
    const plate = solid(i.plate, 1);
    const gold = solid(.{ 0.98, 0.76, 0.2 }, 1);
    const bob = @sin(t * beat) * 0.04;
    r.turn = R.mul(r.turn, about(x_axis, 0.15 + dive * 0.6));
    r.orb(.{ 0, bob, 0 }, .{ 0.3, 0.3, 0.56 }, coat);
    r.orb(.{ 0, bob - 0.04, 0.12 }, .{ 0.26, 0.26, 0.3 }, cream);
    r.block(.{ 0, bob + 0.13, -0.04 }, .{ 0.2, 0.05, 0.4 }, R.identity, plate);
    r.block(.{ 0, bob + 0.16, -0.04 }, .{ 0.04, 0.02, 0.34 }, R.identity, lit(i.glow, 0.8));
    r.orb(.{ 0, bob + 0.07, 0.22 }, .{ 0.24, 0.07, 0.2 }, collar);
    const head: V = .{ 0, bob + 0.16, 0.31 };
    r.orb(head, .{ 0.25, 0.23, 0.25 }, coat);
    r.orb(R.add(head, .{ 0, -0.05, 0.06 }), .{ 0.18, 0.12, 0.16 }, cream);
    r.spike(R.add(head, .{ 0, -0.01, 0.11 }), 0.09, 0.15, R.mul(about(x_axis, std.math.pi / 2.0 + 0.25), R.identity), gold);
    for ([_]f32{ -1, 1 }) |side| r.orb(R.add(head, .{ side * 0.085, 0.04, 0.08 }), .{ 0.065, 0.065, 0.05 }, eye);
    // A swept chitin crest.
    for (0..3) |k| {
        const kf = @as(f32, @floatFromInt(k));
        r.spike(R.add(head, .{ 0, 0.09 - kf * 0.02, -0.02 - kf * 0.05 }), 0.06, 0.18 - kf * 0.03, about(x_axis, -1.0 - kf * 0.25), if (k == 0) plate else coat);
    }
    const feathers = [_][3]f32{ .{ 0.38, 0.3, 0.02 }, .{ 0.34, 0.26, 0.06 }, .{ 0.3, 0.2, 0.1 } };
    const tints = [_][4]f32{ coat, plate, lit(i.glow, 0.45) };
    for ([_]f32{ -1, 1 }) |side| wing(r, .{ side * 0.13, bob + 0.06, 0.04 }, side, flap * (1 - dive) + dive * -0.9, 0.15 + dive * 0.8, &feathers, &tints);
    // Tail fan and talons.
    for ([_]f32{ -0.3, 0, 0.3 }) |spread| r.spike(.{ 0, bob, -0.25 }, 0.1, 0.3, R.mul(about(y_axis, spread), about(x_axis, -std.math.pi / 2.0 + 0.15)), if (spread == 0) plate else coat);
    for ([_]f32{ -1, 1 }) |side| r.orb(.{ side * 0.07, bob - 0.17, 0.02 }, .{ 0.06, 0.08, 0.08 }, gold);
}

fn golem(r: *Rig, pose: Pose, i: Info, eye: [4]f32, collar: [4]f32) void {
    const g = pose.gait;
    const s = pose.stride;
    const stone = solid(i.coat, 1);
    const moss = solid(i.trim, 1);
    const plate = solid(i.plate, 1);
    const core = lit(i.glow, 0.9);
    // A slam: arms up, then down.
    const k: f32 = if (!pose.trick and pose.action > 0) 1 - pose.action / 0.7 else 1;
    const raise: f32 = if (k < 0.6) k / 0.6 * 2.4 else 2.4 * (1 - (k - 0.6) / 0.4);
    const sway = @sin(g) * 0.05 * s;
    const bob = @abs(@sin(g)) * 0.04 * s;
    r.turn = R.mul(r.turn, about(z_axis, sway));
    // Stubby legs.
    for ([_]f32{ -1, 1 }) |side| {
        const swing = @sin(g + (if (side > 0) @as(f32, 0) else std.math.pi)) * 0.45 * s;
        const knee = r.limb(r.parts.orb, .{ side * 0.26, 0.62 + bob, 0 }, about(x_axis, swing), 0.26, .{ 0.3, 0.12, 0.3 }, stone);
        const foot = r.limb(r.parts.block, knee, about(x_axis, swing * 0.5), 0.24, .{ 0.3, 0.02, 0.32 }, plate);
        r.block(R.add(foot, .{ 0, 0.05, 0.05 }), .{ 0.34, 0.12, 0.42 }, R.identity, stone);
    }
    // A boulder body with plates, a lit core and a mossy back.
    r.orb(.{ 0, 1.05 + bob, 0 }, .{ 0.95, 0.82, 0.72 }, stone);
    for ([_]f32{ -1, 1 }) |side| r.block(.{ side * 0.2, 1.08 + bob, 0.3 }, .{ 0.34, 0.4, 0.1 }, about(y_axis, -side * 0.25), plate);
    r.orb(.{ 0, 1.1 + bob, 0.36 }, .{ 0.18, 0.18, 0.1 }, core);
    r.orb(.{ 0, 1.42 + bob, -0.08 }, .{ 0.62, 0.22, 0.5 }, moss);
    r.orb(.{ 0, 1.3 + bob, 0.18 }, .{ 0.5, 0.09, 0.4 }, collar);
    // A small head with a lit visor band and two sprouts.
    const head: V = .{ 0, 1.5 + bob, 0.18 };
    r.orb(head, .{ 0.36, 0.3, 0.34 }, stone);
    r.block(R.add(head, .{ 0, 0.02, 0.15 }), .{ 0.26, 0.055, 0.05 }, R.identity, eye);
    for ([_]f32{ -1, 1 }) |side| r.spike(R.add(head, .{ side * 0.06, 0.12, -0.02 }), 0.07, 0.22, about(z_axis, -side * 0.35), moss);
    // Long arms with plated forearms and big fists, swinging against the legs.
    for ([_]f32{ -1, 1 }) |side| {
        const swing = -@sin(g + (if (side > 0) @as(f32, 0) else std.math.pi)) * 0.4 * s - raise;
        const shoulder: V = .{ side * 0.55, 1.28 + bob, 0 };
        r.orb(shoulder, .{ 0.42, 0.26, 0.42 }, moss);
        const elbow = r.limb(r.parts.orb, shoulder, R.mul(about(x_axis, swing), about(z_axis, side * 0.18)), 0.36, .{ 0.24, 0.1, 0.24 }, stone);
        const hand = r.limb(r.parts.block, elbow, R.mul(about(x_axis, swing - 0.3), about(z_axis, side * 0.08)), 0.34, .{ 0.3, 0.02, 0.3 }, plate);
        r.orb(hand, .{ 0.34, 0.32, 0.34 }, stone);
    }
}

fn moth(r: *Rig, pose: Pose, i: Info, eye: [4]f32, collar: [4]f32) void {
    const t = pose.time;
    const flap = @sin(t * 14) * 0.65;
    const bob = @sin(t * 3) * 0.06;
    const fluff = solid(i.coat, 1);
    const lilac = solid(i.trim, 1);
    // A lumen moth's wings glow softly.
    const wing_tint = lit(i.plate, 0.3);
    const glow = lit(i.glow, 0.85);
    r.orb(.{ 0, bob, 0 }, .{ 0.3, 0.3, 0.32 }, fluff);
    r.orb(.{ 0, bob + 0.06, 0.1 }, .{ 0.34, 0.22, 0.22 }, lilac);
    r.orb(.{ 0, bob + 0.03, 0.11 }, .{ 0.3, 0.06, 0.2 }, collar);
    r.orb(.{ 0, bob - 0.04, -0.22 }, .{ 0.22, 0.22, 0.32 }, lilac);
    r.orb(.{ 0, bob - 0.05, -0.25 }, .{ 0.18, 0.05, 0.22 }, glow);
    const head: V = .{ 0, bob + 0.08, 0.24 };
    r.orb(head, .{ 0.24, 0.22, 0.22 }, fluff);
    // Big glossy eyes with a lit glint.
    for ([_]f32{ -1, 1 }) |side| {
        r.orb(R.add(head, .{ side * 0.075, 0.01, 0.07 }), .{ 0.11, 0.12, 0.08 }, if (pose.wild) eye else solid(.{ 0.22, 0.14, 0.34 }, 1));
        r.orb(R.add(head, .{ side * 0.06, 0.04, 0.11 }), @splat(0.03), lit(.{ 1, 1, 1 }, 0.9));
        // Feathery antennae with lit tips.
        const a = R.mul(about(z_axis, -side * 0.45), about(x_axis, 0.5));
        r.spike(R.add(head, .{ side * 0.05, 0.09, 0.03 }), 0.025, 0.24, a, lilac);
        r.orb(R.add(head, R.add(.{ side * 0.05, 0.09, 0.03 }, R.rotate(a, .{ 0, 0.24, 0 }))), @splat(0.05), glow);
    }
    // Four soft wings with lit eyespots, fore and hind beating together.
    for ([_]f32{ -1, 1 }) |side| {
        // Raised and pitched, so the broad wing faces the eye from the front as well as above.
        const fore = R.mul(R.mul(about(z_axis, side * (0.55 + flap)), about(y_axis, side * 0.25)), about(x_axis, -0.55));
        const hind = R.mul(R.mul(about(z_axis, side * (0.4 + flap * 0.85)), about(y_axis, -side * 0.35)), about(x_axis, -0.35));
        const fr: V = .{ side * 0.12, bob + 0.08, 0.04 };
        const hr: V = .{ side * 0.1, bob + 0.05, -0.08 };
        r.orbTurned(R.add(fr, R.rotate(fore, .{ side * 0.3, 0, 0.02 })), .{ 0.6, 0.03, 0.46 }, fore, wing_tint);
        r.orbTurned(R.add(fr, R.rotate(fore, .{ side * 0.36, 0.02, 0.02 })), .{ 0.16, 0.012, 0.16 }, fore, glow);
        r.orbTurned(R.add(hr, R.rotate(hind, .{ side * 0.22, 0, -0.08 })), .{ 0.42, 0.03, 0.32 }, hind, lilac);
    }
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "levels grow with experience and raise damage, capped" {
    try std.testing.expectEqual(@as(u8, 1), levelFor(0));
    try std.testing.expectEqual(@as(u8, 2), levelFor(60));
    try std.testing.expectEqual(@as(u8, 3), levelFor(180));
    try std.testing.expectEqual(@as(u8, max_level), levelFor(1_000_000));
    for (std.enums.values(Species)) |s| {
        try std.testing.expect(damage(s, 5) > damage(s, 1));
        try std.testing.expect(maxHealth(s, 5) > maxHealth(s, 1));
    }
}

test "wild pets wait on the meadow ring, apart from each other" {
    var pets: Pets = .{};
    pets.place(0x4845415659, .{ 0, 0, -58 });
    for (pets.spots, 0..) |a, i| {
        const d = @sqrt(a.position[0] * a.position[0] + (a.position[2] + 58) * (a.position[2] + 58));
        try std.testing.expect(d >= 149 and d <= 231);
        for (pets.spots[i + 1 ..]) |b| try std.testing.expect(R.length(R.sub(a.position, b.position)) > 60);
    }
}

test "a pet follows its ranger, fights the Hive near them, and the moth mends" {
    var physics = testPhysics();
    defer physics.deinit();
    for (std.enums.values(Species)) |species| {
        var pets: Pets = .{};
        pets.summon(0, species, .{ 0, 0, 0 }, 1);
        var enemies: Enemies = .{};
        var skies: Skies = .{};
        const ctx: Context = .{ .owner = .{ 20, 0, 0 }, .owner_yaw = 0, .level = 1, .seed = 1, .physics = &physics, .skies = &skies };
        var hive: [16]Enemies.Event = undefined;
        var hn: usize = 0;
        var events: [8]Event = undefined;
        // It catches up with the ranger and settles beside them.
        for (0..240) |_| _ = pets.step(0, ctx, &enemies, 1.0 / 60.0, &hive, &hn, &events);
        const p = pets.out[0].?;
        try std.testing.expect(R.length(R.sub(.{ p.position[0], 0, p.position[2] }, ctx.owner)) < 2.5);
        if (info(species).flies) try std.testing.expect(p.position[1] > 1.5) else try std.testing.expectApproxEqAbs(@as(f32, 0), p.position[1], 0.01);
        // A drone near the ranger is attacked until it falls.
        const nest = enemies.addArenaNest(.{ 60, 0, 60 });
        try std.testing.expect(enemies.spawnAt(.trooper, nest, .{ 26, 0, 4 }, 1));
        var attacks: usize = 0;
        var mends: usize = 0;
        var downed = false;
        for (0..60 * 30) |_| {
            hn = 0;
            const n = pets.step(0, ctx, &enemies, 1.0 / 60.0, &hive, &hn, &events);
            for (events[0..@min(n, events.len)]) |e| switch (e) {
                .attack => attacks += 1,
                .air_attack, .hurt => {},
                .mend => mends += 1,
            };
            for (hive[0..@min(hn, hive.len)]) |e| downed = downed or e == .unit_down;
            if (downed) break;
            // Keep the trooper in place: this tests the pet, not the Hive.
            for (&enemies.units) |*u| if (u.*) |*unit| {
                unit.position = .{ 26, 0, 4 };
                unit.cooldown = 10;
            };
        }
        try std.testing.expect(attacks > 0 and downed);
        if (species == .moth) try std.testing.expect(mends > 0);
    }
}

test "puppets are built from the three part meshes and differ by species and collar" {
    const parts: Parts = .{ .orb = .{ .index = 1, .generation = 1 }, .block = .{ .index = 2, .generation = 1 }, .spike = .{ .index = 3, .generation = 1 } };
    var out: [96]World.Prop = undefined;
    var tops: [count]f32 = undefined;
    for (std.enums.values(Species), 0..) |s, k| {
        const wild = draw(s, .{ .position = .{ 0, 0, 0 }, .yaw = 0, .wild = true }, parts, &out, 0);
        const free = draw(s, .{ .position = .{ 0, 0, 0 }, .yaw = 0 }, parts, &out, 0);
        try std.testing.expect(free > 15);
        // The Hive collar carries spikes on the hound; every wild pet glows Hive red.
        if (s == .hound) try std.testing.expect(wild > free);
        var red = false;
        _ = draw(s, .{ .position = .{ 0, 0, 0 }, .yaw = 0, .wild = true }, parts, &out, 0);
        for (out[0..wild]) |p| red = red or (p.tint[3] > 1 and p.tint[0] > 0.9 and p.tint[1] < 0.3);
        try std.testing.expect(red);
        // Every puppet is built from spheres and spikes.
        var orbs: usize = 0;
        var spikes: usize = 0;
        var top: f32 = -1;
        for (out[0..free]) |p| {
            orbs += @intFromBool(p.mesh.eql(parts.orb));
            spikes += @intFromBool(p.mesh.eql(parts.spike));
            top = @max(top, p.transform.position[1]);
        }
        try std.testing.expect(orbs > 5 and spikes > 0);
        tops[k] = top;
    }
    // The golem towers over the hound.
    try std.testing.expect(tops[@intFromEnum(Species.golem)] > 1.3 and tops[@intFromEnum(Species.hound)] > 0.8 and tops[@intFromEnum(Species.hound)] < tops[@intFromEnum(Species.golem)]);
}
