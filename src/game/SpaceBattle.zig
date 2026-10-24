//! Orbital battles and the asteroid mining run: a top-down, twin-stick arena around the space
//! centre. The fighter moves with the movement keys (screen relative) and aims with the mouse or
//! right stick, firing the four systems of `SpaceArsenal`. Enemies enter in the level's
//! formations (`SpaceLevels`) and fight back with slow, readable shots after a visible
//! telegraph; heavy ships fire rings, and the mother ship changes pattern in three phases. Hits
//! are tested on the horizontal plane, since the camera looks straight down.
//!
//! Rewards follow the save rules: each kill pays the pilot's own kit (the air war's loot table),
//! a level clear pays every present player and sets a shared story flag, and mined ore goes to
//! the pilot's kit to be deposited at a colony store. Fixed capacities, no allocation.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Colony = @import("Colony.zig");
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Material = @import("../render/Material.zig");
const SpaceFlight = @import("../vehicle/SpaceFlight.zig");
const Skies = @import("Skies.zig");
const Loot = @import("Loot.zig");
const Levels = @import("SpaceLevels.zig");
const Arsenal = @import("SpaceArsenal.zig");
const Sandbox = @import("Sandbox.zig");
const ShipMeshes = @import("../vehicle/ShipMeshes.zig");
const m = @import("../character/math.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;

pub const Location = Levels.Location;
pub const Kind = Levels.Kind;
pub const location_count = Levels.location_count;
pub const levels = Levels.levels;
pub const name = Levels.name;
pub const cleared = Levels.cleared;
pub const nextLevel = Levels.nextLevel;

pub const max_enemies = 24;
pub const max_player_shots = 96;
pub const max_hostile_shots = 160;
pub const max_bursts = 16;
pub const max_rocks = 10;
/// Enemies keep inside this square (the fighter's own bound is `SpaceFlight.half_extent`).
pub const bound: f32 = 108;
/// Seconds between a cleared wave and the next.
pub const wave_gap: f32 = 2.5;
/// Seconds the fighter shrugs off further hits after one lands.
pub const invulnerable_time: f32 = 0.7;
pub const ship_radius: f32 = 3;
/// A kill chain ends this long after the last kill.
pub const chain_window: f32 = 2.5;

pub const Enemy = struct {
    active: bool = false,
    kind: Kind = .drone,
    position: V = .{ 0, 0, 0 },
    velocity: V = .{ 0, 0, 0 },
    health: f32 = 0,
    max_health: f32 = 1,
    /// Free-running wobble.
    phase: f32 = 0,
    /// Counts down to the next attack; while `telegraph` runs the attack is announced.
    fire_clock: f32 = 0,
    telegraph: f32 = 0,
    /// Transformer: 0 cruising, 1 winding up, 2 dashing. Mother ship: phase 1 to 3.
    mode: u8 = 0,
    mode_clock: f32 = 0,
    dash: V = .{ 0, 0, 1 },
    spin: f32 = 0,
    flash: f32 = 0,
};

pub const ShotKind = enum { bolt, blast, missile, bomb, orb };
pub const Shot = struct {
    active: bool = false,
    kind: ShotKind = .bolt,
    position: V = .{ 0, 0, 0 },
    velocity: V = .{ 0, 0, 0 },
    life: f32 = 0,
    damage: f32 = 0,
    radius: f32 = 1,
    target: ?u8 = null,
    /// Enemies a piercing blast already struck (bit per enemy slot).
    struck: u32 = 0,
};

pub const Burst = struct { active: bool = false, position: V = .{ 0, 0, 0 }, age: f32 = 0, life: f32 = 0.4, radius: f32 = 4, color: [3]f32 = .{ 1, 1, 1 } };
pub const Rock = struct { active: bool = false, position: V = .{ 0, 0, 0 }, health: f32 = 0, ore: Colony.Ore = .iron, size: f32 = 6, respawn: f32 = 0 };
pub const Result = enum { fighting, won };

pub const Controls = struct { fire: bool = false, alt: bool = false, missile: bool = false, bomb: bool = false, next: bool = false };

pub const State = struct {
    active: bool = false,
    mining: bool = false,
    location: Location = .moon,
    level: u8 = 1,
    wave: u8 = 0,
    result: Result = .fighting,
    enemies: [max_enemies]Enemy = @splat(.{}),
    shots: [max_player_shots]Shot = @splat(.{}),
    hostile: [max_hostile_shots]Shot = @splat(.{}),
    bursts: [max_bursts]Burst = @splat(.{}),
    rocks: [max_rocks]Rock = @splat(.{}),
    frame: Arsenal.Frame = .kestrel,
    profile: Arsenal.Profile = Arsenal.base(.kestrel),
    weapons: Arsenal.Weapons = .{},
    /// Where the fighter points (radians about +Y; 0 is up the screen, +Z).
    aim: f32 = 0,
    /// The enemy a missile would lock now, for the HUD.
    lock: ?u8 = null,
    invulnerable: f32 = 0,
    gap: f32 = 0,
    clock: f32 = 0,
    harass: f32 = 0,
    warning: bool = false,
    hit_flash: f32 = 0,
    kills: u16 = 0,
    score: u32 = 0,
    chain: u16 = 0,
    chain_clock: f32 = 0,
    deaths: u16 = 0,
    /// What this run paid the pilot, for the closing line.
    earned_scrap: u32 = 0,
    earned_xp: u32 = 0,
    ore: [Colony.ore_count]u32 = @splat(0),
    seed: u64 = 0,
    rng: std.Random.DefaultPrng = std.Random.DefaultPrng.init(0),

    pub fn begin(self: *State, location: Location, level: u8, mining: bool, seed: u64, frame: Arsenal.Frame, upgrades: [@import("Progress.zig").kestrel_upgrade_count]u8) void {
        const p = Arsenal.profile(frame, upgrades);
        self.* = .{ .active = true, .mining = mining, .location = location, .level = std.math.clamp(level, 1, levels), .seed = seed, .frame = frame, .profile = p, .weapons = Arsenal.Weapons.init(p), .rng = std.Random.DefaultPrng.init(seed) };
        if (mining) {
            for (0..max_rocks) |i| self.placeRock(i);
            self.harass = 20;
        } else self.spawnWave(1);
    }

    pub fn liveEnemies(self: *const State) usize {
        var n: usize = 0;
        for (self.enemies) |e| n += @intFromBool(e.active);
        return n;
    }

    /// The boss or midboss on the field, for the HUD bar.
    pub fn heavy(self: *const State) ?*const Enemy {
        for (&self.enemies) |*e| if (e.active and (e.kind == .mother_ship or e.kind == .battleship)) return e;
        return null;
    }

    fn placeRock(self: *State, i: usize) void {
        const r = self.rng.random();
        const ore: Colony.Ore = if (i % 5 == 4) .crystal else if (i % 5 >= 2) .copper else .iron;
        const angle = @as(f32, @floatFromInt(i)) * 2.399 + r.float(f32);
        const dist = 35 + r.float(f32) * 60;
        self.rocks[i] = .{ .active = true, .ore = ore, .position = .{ @cos(angle) * dist, -2, @sin(angle) * dist }, .health = 60 + @as(f32, @floatFromInt(@intFromEnum(ore))) * 40, .size = 5 + r.float(f32) * 3 };
    }

    pub fn spawnWave(self: *State, index: u8) void {
        self.wave = index;
        self.enemies = @splat(.{});
        self.hostile = @splat(.{});
        const plan = Levels.wave(self.location, self.level, index);
        for (plan.groups) |g| if (g) |group| self.spawnGroup(group);
    }

    fn spawnGroup(self: *State, group: Levels.Group) void {
        const n: usize = group.count;
        for (0..n) |k| {
            const t = if (n == 1) 0.5 else @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n - 1));
            const at: V = switch (group.pattern) {
                .line => .{ (t - 0.5) * 150, 0, bound - 4 },
                .column => .{ 0, 0, bound - 4 + @as(f32, @floatFromInt(k)) * 9 },
                .pincer => .{ if (k % 2 == 0) -bound + 4 else bound - 4, 0, 60 - @as(f32, @floatFromInt(k / 2)) * 22 },
                .ring => .{ @cos(@as(f32, @floatFromInt(k)) * 2 * std.math.pi / @as(f32, @floatFromInt(n))) * 92, 0, @sin(@as(f32, @floatFromInt(k)) * 2 * std.math.pi / @as(f32, @floatFromInt(n))) * 92 },
                .escort => .{ (t - 0.5) * 50, 0, bound - 14 },
            };
            _ = self.add(group.kind, at);
        }
    }

    fn add(self: *State, kind: Kind, at: V) ?usize {
        for (&self.enemies, 0..) |*e, i| if (!e.active) {
            const s = Levels.scale(self.location, self.level);
            const hp = baseHealth(kind) * s.health;
            const r = self.rng.random();
            e.* = .{ .active = true, .kind = kind, .position = at, .health = hp, .max_health = hp, .phase = r.float(f32) * 6.283, .fire_clock = 1.5 + r.float(f32) * 2, .mode = if (kind == .mother_ship) 1 else 0, .mode_clock = 5 + r.float(f32) * 2 };
            return i;
        };
        return null;
    }

    fn fireRate(self: *const State) f32 {
        return Levels.scale(self.location, self.level).fire;
    }

    fn hostileDamage(self: *const State, base: f32) f32 {
        return base * Levels.scale(self.location, self.level).damage;
    }

    fn shoot(self: *State, from: V, dir: V, speed: f32, damage: f32, radius: f32) void {
        for (&self.hostile) |*s| if (!s.active) {
            s.* = .{ .active = true, .kind = .orb, .position = from, .velocity = R.scale(flat(dir), speed), .life = 7, .damage = damage, .radius = radius };
            return;
        };
    }

    fn ring(self: *State, from: V, count: usize, offset: f32, speed: f32, damage: f32, radius: f32) void {
        for (0..count) |k| {
            const a = offset + @as(f32, @floatFromInt(k)) * 2 * std.math.pi / @as(f32, @floatFromInt(count));
            self.shoot(from, .{ @sin(a), 0, @cos(a) }, speed, damage, radius);
        }
    }

    fn fan(self: *State, from: V, toward: V, count: usize, spread: f32, speed: f32, damage: f32) void {
        const d = flat(R.sub(toward, from));
        const base = std.math.atan2(d[0], d[2]);
        for (0..count) |k| {
            const t = if (count == 1) 0 else @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(count - 1)) - 0.5;
            const a = base + t * spread;
            self.shoot(from, .{ @sin(a), 0, @cos(a) }, speed, damage, 1.4);
        }
    }

    fn burst(self: *State, at: V, radius: f32, life: f32, color: [3]f32) void {
        var oldest: usize = 0;
        for (&self.bursts, 0..) |*b, i| {
            if (!b.active) {
                oldest = i;
                break;
            }
            if (b.age / b.life > self.bursts[oldest].age / self.bursts[oldest].life) oldest = i;
        }
        self.bursts[oldest] = .{ .active = true, .position = at, .radius = radius, .life = life, .color = color };
    }

    fn clearHostile(self: *State, at: V, radius: f32) u32 {
        var n: u32 = 0;
        for (&self.hostile) |*s| if (s.active and flatDistance(s.position, at) <= radius) {
            s.active = false;
            n += 1;
        };
        return n;
    }

    /// The hostile best placed for a missile: inside 40° of the aim, nearest; else the nearest.
    pub fn lockTarget(self: *const State, ship: V) ?u8 {
        const aim: V = .{ @sin(self.aim), 0, @cos(self.aim) };
        var best: ?u8 = null;
        var best_score: f32 = std.math.inf(f32);
        for (self.enemies, 0..) |e, i| if (e.active) {
            const d = flat(R.sub(e.position, ship));
            const dist = R.length(d);
            if (dist < 1 or dist > 220) continue;
            const facing = R.dot(R.scale(d, 1 / dist), aim);
            // Inside the cone always beats outside it.
            const score = dist + (if (facing > 0.766) @as(f32, 0) else 1000);
            if (score < best_score) {
                best = @intCast(i);
                best_score = score;
            }
        };
        return best;
    }

    fn launch(self: *State, kind: ShotKind, from: V, dir: V, speed: f32, damage: f32, radius: f32, life: f32, target: ?u8) void {
        for (&self.shots) |*s| if (!s.active) {
            s.* = .{ .active = true, .kind = kind, .position = from, .velocity = R.scale(flat(dir), speed), .damage = damage, .radius = radius, .life = life, .target = target };
            return;
        };
    }

    /// One fixed step. `ship` is the fighter's position relative to the arena centre.
    pub fn step(self: *State, sb: *Sandbox, controls: Controls, dt: f32) void {
        if (!self.active) return;
        const fighter = if (sb.hangar.fighter) |*f| f else return;
        const c = sb.hangar.space_center;
        const ship: V = .{ fighter.body.pos.x - c.x, fighter.body.pos.y - c.y, fighter.body.pos.z - c.z };
        self.clock += dt;
        self.hit_flash = @max(0, self.hit_flash - dt);
        self.invulnerable = @max(0, self.invulnerable - dt);
        self.chain_clock = @max(0, self.chain_clock - dt);
        if (self.chain_clock == 0) self.chain = 0;
        for (&self.bursts) |*b| if (b.active) {
            b.age += dt;
            if (b.age >= b.life) b.active = false;
        };
        self.warning = @abs(ship[0]) > SpaceFlight.half_extent - 10 or @abs(ship[2]) > SpaceFlight.half_extent - 10;

        if (self.result == .won) {
            if (controls.next and !self.mining) {
                const next = Levels.nextLevel(&sb.progress, self.location);
                self.begin(self.location, next, false, self.seed +% 1, self.frame, sb.progress.kestrel_levels);
                sb.say("{s} LEVEL {d}/10", .{ Levels.name(self.location), next });
            }
            return;
        }

        self.fireWeapons(sb, ship, controls, dt);
        self.moveShots(sb, dt);
        self.stepEnemies(sb, ship, dt);
        self.hostileHits(sb, ship, dt);
        if (self.mining) {
            self.stepRocks(sb, dt);
            return;
        }
        if (fighter.hull <= 0) return self.downed(sb);

        if (self.liveEnemies() == 0) {
            if (self.gap == 0) {
                self.gap = wave_gap;
                self.weapons.waveCleared(self.profile);
                if (self.wave < Levels.waves) sb.say("WAVE {d} CLEAR", .{self.wave});
            }
            self.gap = @max(0, self.gap - dt);
            if (self.gap > 0) return;
            if (self.wave < Levels.waves) {
                self.spawnWave(self.wave + 1);
                self.gap = 0;
            } else self.win(sb);
        }
    }

    fn fireWeapons(self: *State, sb: *Sandbox, ship: V, controls: Controls, dt: f32) void {
        const p = self.profile;
        const aim: V = .{ @sin(self.aim), 0, @cos(self.aim) };
        const right: V = .{ aim[2], 0, -aim[0] };
        self.lock = self.lockTarget(ship);
        const fired = self.weapons.step(p, controls.fire, controls.alt, dt);
        if (fired.gun) |side| {
            const offset: f32 = if (side == 0) -1.6 else 1.6;
            self.launch(.bolt, R.add(R.add(ship, R.scale(aim, 3)), R.scale(right, offset)), aim, 220, p.gun_damage, 1.2, 0.6, null);
            if (side == 0) sb.cue(.zap, null);
        }
        if (fired.blast) |share| {
            self.launch(.blast, R.add(ship, R.scale(aim, 4)), aim, 160, p.charge_damage * share, 1 + p.charge_radius * share, 0.9, null);
            sb.cuePitch(.zap, null, 0.6);
        }
        if (controls.missile and self.lock != null and self.weapons.takeMissile()) {
            self.launch(.missile, R.add(ship, R.scale(aim, 3)), aim, 70, p.missile_damage, 2, 4, self.lock);
            sb.cue(.dash, null);
        }
        if (controls.bomb and self.weapons.takeBomb()) {
            self.launch(.bomb, R.add(ship, R.scale(aim, 4)), aim, 34, p.bomb_damage, 3, 5, self.lock);
            sb.cuePitch(.dash, null, 0.6);
        }
    }

    fn moveShots(self: *State, sb: *Sandbox, dt: f32) void {
        for (&self.shots) |*s| if (s.active) {
            s.life -= dt;
            if (s.kind == .missile or s.kind == .bomb) self.home(s, dt);
            s.position = R.add(s.position, R.scale(s.velocity, dt));
            if (s.life <= 0 or @abs(s.position[0]) > 140 or @abs(s.position[2]) > 140) {
                if (s.kind == .bomb) self.detonate(sb, s.*);
                s.active = false;
                continue;
            }
            if (self.mining) for (&self.rocks) |*rock| if (rock.active and flatDistance(rock.position, s.position) < rock.size + s.radius) {
                rock.health -= s.damage;
                if (s.kind != .blast) s.active = false;
                if (rock.health <= 0) self.breakRock(sb, rock);
                break;
            };
            if (!s.active) continue;
            for (&self.enemies, 0..) |*e, i| if (e.active) {
                const bit = @as(u32, 1) << @intCast(i);
                if (s.struck & bit != 0) continue;
                if (flatDistance(e.position, s.position) > radiusOf(e.kind) + s.radius) continue;
                switch (s.kind) {
                    .bomb => {
                        self.detonate(sb, s.*);
                        s.active = false;
                    },
                    .blast => {
                        s.struck |= bit;
                        self.strike(sb, i, s.damage);
                        // A blast eats the hostile shots in its path as it goes.
                        _ = self.clearHostile(s.position, s.radius + 1);
                    },
                    else => {
                        self.strike(sb, i, s.damage);
                        if (s.kind == .missile) self.burst(s.position, 5, 0.3, .{ 1, 0.8, 0.4 });
                        s.active = false;
                    },
                }
                if (!s.active) break;
            };
        };
    }

    fn home(self: *State, s: *Shot, dt: f32) void {
        if (s.target) |t| {
            if (!self.enemies[t].active) s.target = self.nearest(s.position);
        } else s.target = self.nearest(s.position);
        const speed: f32 = if (s.kind == .missile) @min(130, R.length(s.velocity) + 90 * dt) else R.length(s.velocity);
        const turn: f32 = if (s.kind == .missile) 4 else 1.6;
        var dir = R.normalize(s.velocity);
        if (s.target) |t| {
            const want = R.normalize(flat(R.sub(self.enemies[t].position, s.position)));
            dir = R.normalize(R.add(dir, R.scale(R.sub(want, dir), @min(1, turn * dt))));
        }
        s.velocity = R.scale(dir, speed);
    }

    fn nearest(self: *const State, at: V) ?u8 {
        var best: ?u8 = null;
        var best_d: f32 = 260;
        for (self.enemies, 0..) |e, i| if (e.active) {
            const d = flatDistance(e.position, at);
            if (d < best_d) {
                best = @intCast(i);
                best_d = d;
            }
        };
        return best;
    }

    fn detonate(self: *State, sb: *Sandbox, s: Shot) void {
        const radius = self.profile.bomb_radius;
        for (&self.enemies, 0..) |*e, i| if (e.active) {
            const d = flatDistance(e.position, s.position);
            if (d > radius + radiusOf(e.kind)) continue;
            self.strike(sb, i, s.damage * (1 - 0.5 * @min(1, d / radius)));
        };
        if (self.mining) for (&self.rocks) |*rock| if (rock.active and flatDistance(rock.position, s.position) < radius + rock.size) {
            rock.health -= s.damage;
            if (rock.health <= 0) self.breakRock(sb, rock);
        };
        const wiped = self.clearHostile(s.position, radius);
        self.score += wiped * 10;
        self.burst(s.position, radius, 0.6, .{ 0.55, 0.9, 1 });
        sb.cue(.boom, null);
    }

    fn strike(self: *State, sb: *Sandbox, i: usize, amount: f32) void {
        const e = &self.enemies[i];
        e.health -= amount;
        e.flash = 0.08;
        if (e.health > 0) return;
        e.active = false;
        self.kills += 1;
        self.chain += 1;
        self.chain_clock = chain_window;
        const multiplier = @min(3, 1 + @as(f32, @floatFromInt(self.chain - 1)) * 0.1);
        self.score += @intFromFloat(@as(f32, @floatFromInt(points(e.kind))) * multiplier);
        self.burst(e.position, radiusOf(e.kind) * 1.6, if (e.kind == .mother_ship) 1.2 else 0.45, if (Levels.faction(self.location) == .armada) .{ 0.3, 0.75, 1 } else .{ 1, 0.4, 0.15 });
        sb.cue(.boom, null);
        self.credit(sb, e.kind);
        if (e.kind == .mother_ship) _ = self.clearHostile(e.position, 400);
    }

    /// The pilot's own kit gets the kill: the air war's loot for fighters, fixed pay for heavies.
    fn credit(self: *State, sb: *Sandbox, kind: Kind) void {
        const kit = &sb.kits[0];
        const wing: Skies.WingKind = switch (Levels.faction(self.location)) {
            .armada => if (kind == .transformer) .robot_lancer else .robot_fighter,
            else => switch (kind) {
                .drone => .wasp,
                .fighter => .dragonfly,
                else => .beetle_bomber,
            },
        };
        var reward = Loot.rollAir(wing, sb.skies.rng.random());
        switch (kind) {
            .battleship => {
                reward.scrap += 20;
                reward.parts += 3;
                reward.combat_xp += 30;
            },
            .mother_ship => {
                reward.scrap += 60;
                reward.parts += 8;
                reward.combat_xp += 80;
            },
            else => {},
        }
        kit.wallet.scrap +|= reward.scrap;
        kit.wallet.parts +|= reward.parts;
        kit.wallet.gold +|= reward.gold;
        self.earned_scrap +|= reward.scrap;
        self.earned_xp +|= reward.combat_xp;
        if (kit.awardCombatXP(reward.combat_xp)) sb.say("P1 combat level {d}!", .{kit.combatLevel()});
    }

    fn stepEnemies(self: *State, sb: *Sandbox, ship: V, dt: f32) void {
        const rate = self.fireRate();
        for (&self.enemies) |*e| if (e.active) {
            e.phase += dt;
            e.spin += dt;
            e.flash = @max(0, e.flash - dt);
            const to = flat(R.sub(ship, e.position));
            const dist = @max(0.01, R.length(to));
            const dir = R.scale(to, 1 / dist);
            const side: V = .{ dir[2], 0, -dir[0] };
            var want: V = .{ 0, 0, 0 };
            switch (e.kind) {
                .drone => want = R.add(R.scale(dir, 24), R.scale(side, @sin(e.phase * 2) * 10)),
                .fighter => want = R.add(R.scale(dir, (dist - 50) * 0.8), R.scale(side, 14)),
                .transformer => switch (e.mode) {
                    0 => {
                        want = R.add(R.scale(dir, (dist - 60) * 0.7), R.scale(side, -12));
                        e.mode_clock -= dt;
                        if (e.mode_clock <= 0) {
                            e.mode = 1;
                            e.mode_clock = 0.9;
                        }
                    },
                    1 => {
                        e.dash = dir;
                        e.mode_clock -= dt;
                        if (e.mode_clock <= 0) {
                            e.mode = 2;
                            e.mode_clock = 1.1;
                        }
                    },
                    else => {
                        want = R.scale(e.dash, 75);
                        e.mode_clock -= dt;
                        if (e.mode_clock <= 0) {
                            e.mode = 0;
                            e.mode_clock = 5;
                        }
                    },
                },
                .battleship => want = R.scale(flat(R.sub(R.add(ship, .{ 0, 0, 55 }), e.position)), 0.12),
                .mother_ship => want = R.scale(flat(R.sub(.{ @sin(self.clock * 0.3) * 50, 0, 72 }, e.position)), 0.5),
            }
            // Snappy for small craft, ponderous for heavies.
            const response: f32 = switch (e.kind) {
                .drone, .fighter => 3,
                .transformer => if (e.mode == 2) 20 else 3,
                else => 1,
            };
            e.velocity = R.add(e.velocity, R.scale(R.sub(want, e.velocity), @min(1, response * dt)));
            e.position = R.add(e.position, R.scale(e.velocity, dt));
            e.position[0] = std.math.clamp(e.position[0], -bound, bound);
            e.position[2] = std.math.clamp(e.position[2], -bound, bound);
            e.position[1] = @sin(e.phase * 0.7) * 1.5;

            // Ramming: drones spend themselves, dashing transformers hit hard and keep going.
            if (dist < radiusOf(e.kind) + ship_radius) switch (e.kind) {
                .drone => {
                    self.hurt(sb, self.hostileDamage(15));
                    e.active = false;
                    self.burst(e.position, 4, 0.3, .{ 1, 0.4, 0.15 });
                    continue;
                },
                .transformer => if (e.mode == 2) self.hurt(sb, self.hostileDamage(30)),
                else => self.hurt(sb, self.hostileDamage(8) * dt * 10),
            };
            if (e.kind == .mother_ship) {
                const next = phaseOf(e);
                if (next != e.mode) {
                    // A new phase starts on a clear field: the old pattern goes first.
                    e.mode = next;
                    e.telegraph = 0;
                    e.fire_clock = 1.5;
                    _ = self.clearHostile(e.position, 400);
                    sb.say("THE MOTHER SHIP CHANGES PATTERN: PHASE {d} OF 3", .{next});
                }
            }
            self.attack(e, ship, rate, dt);
        };
        if (self.mining) {
            self.harass -= dt;
            if (self.harass <= 0) {
                self.harass = 25;
                _ = self.add(.drone, .{ -bound + 4, 0, bound - 4 });
                _ = self.add(.drone, .{ bound - 4, 0, bound - 4 });
            }
        }
    }

    /// Every attack is announced: the enemy glows for `telegraph` seconds, then fires.
    fn attack(self: *State, e: *Enemy, ship: V, rate: f32, dt: f32) void {
        if (e.kind == .transformer and e.mode != 0) return;
        if (e.telegraph > 0) {
            e.telegraph -= dt;
            if (e.telegraph > 0) return;
            const hit = self.hostileDamage(12);
            switch (e.kind) {
                .drone => self.fan(e.position, ship, 1, 0, 28, hit),
                .fighter => self.fan(e.position, ship, 3, 0.2, 30, hit),
                .transformer => self.fan(e.position, ship, 5, 0.7, 26, hit),
                .battleship => {
                    self.ring(e.position, 12, e.spin * 0.6, 22, hit, 2);
                    self.fan(e.position, ship, 2, 0.1, 32, hit);
                },
                .mother_ship => switch (e.mode) {
                    1 => {
                        self.ring(e.position, 16, e.spin * 0.4, 20, hit, 2);
                        for (0..2) |_| _ = self.add(.drone, R.add(e.position, .{ (self.rng.random().float(f32) - 0.5) * 30, 0, -12 }));
                    },
                    2 => self.ring(e.position, 3, e.spin * 2.2, 24, hit, 1.6),
                    else => {
                        self.fan(e.position, ship, 7, 0.9, 30, hit);
                        self.ring(e.position, 4, e.spin * 1.5, 22, hit, 1.6);
                    },
                },
            }
            return;
        }
        e.fire_clock -= dt * rate;
        if (e.fire_clock > 0) return;
        e.fire_clock = switch (e.kind) {
            .drone => 2.6,
            .fighter => 3.2,
            .transformer => 2.5,
            .battleship => 3.6,
            .mother_ship => switch (e.mode) {
                1 => 3.0,
                2 => 0.25,
                else => 1.6,
            },
        };
        e.telegraph = switch (e.kind) {
            .drone => 0.35,
            .fighter, .transformer => 0.6,
            .battleship => 0.8,
            .mother_ship => if (e.mode == 2) 0.02 else 0.7,
        };
    }

    fn hostileHits(self: *State, sb: *Sandbox, ship: V, dt: f32) void {
        for (&self.hostile) |*s| if (s.active) {
            s.life -= dt;
            s.position = R.add(s.position, R.scale(s.velocity, dt));
            if (s.life <= 0 or @abs(s.position[0]) > 140 or @abs(s.position[2]) > 140) {
                s.active = false;
                continue;
            }
            if (flatDistance(s.position, ship) < ship_radius + s.radius) {
                s.active = false;
                self.hurt(sb, s.damage);
            }
        };
    }

    fn hurt(self: *State, sb: *Sandbox, amount: f32) void {
        if (self.invulnerable > 0) return;
        const f = &(sb.hangar.fighter orelse return);
        f.hull = @max(0, f.hull - amount);
        self.invulnerable = invulnerable_time;
        self.hit_flash = 0.25;
        self.chain = 0;
        sb.cue(.hurt, null);
    }

    /// Knocked out: back at the relay with half the hull, the wave from the start.
    fn downed(self: *State, sb: *Sandbox) void {
        const f = &(sb.hangar.fighter orelse return);
        f.hull = f.hull_max * 0.5;
        f.body.pos = sb.hangar.space_center;
        f.body.vel = @import("../character/math.zig").Vec3.zero;
        self.deaths += 1;
        self.weapons = Arsenal.Weapons.init(self.profile);
        self.shots = @splat(.{});
        self.spawnWave(self.wave);
        sb.say("FIGHTER DOWN: BACK AT THE RELAY, WAVE {d} AGAIN", .{self.wave});
    }

    fn win(self: *State, sb: *Sandbox) void {
        self.result = .won;
        var buf: [24]u8 = undefined;
        sb.progress.setFlag(Levels.flag(self.location, self.level, &buf));
        const pay = Levels.reward(self.location, self.level);
        for (0..Sandbox.max_players) |p| if (sb.present(p)) {
            sb.kits[p].wallet.scrap +|= pay.scrap;
            sb.kits[p].wallet.gold +|= pay.gold;
        };
        if (self.level == Levels.boss_level) sb.progress.setFlag(Levels.bossFlag(self.location));
        if (self.level == Levels.gate_level and self.location != .kuiper_belt) {
            const next: Location = @enumFromInt(@intFromEnum(self.location) + 1);
            sb.say("{s} IS OPEN ON THE SOLAR MAP", .{Levels.name(next)});
        }
        sb.say("{s} LEVEL {d} CLEAR  SCORE {d}  +{d} SCRAP EACH  H NEXT LEVEL, F RETURN", .{ Levels.name(self.location), self.level, self.score, pay.scrap });
    }

    fn stepRocks(self: *State, sb: *Sandbox, dt: f32) void {
        _ = sb;
        for (&self.rocks, 0..) |*rock, i| if (!rock.active) {
            rock.respawn -= dt;
            if (rock.respawn <= 0) self.placeRock(i);
        };
    }

    fn breakRock(self: *State, sb: *Sandbox, rock: *Rock) void {
        const amount: u32 = 2 + self.rng.random().uintLessThan(u32, 3);
        sb.kits[0].ore[@intFromEnum(rock.ore)] += amount;
        self.ore[@intFromEnum(rock.ore)] += amount;
        self.burst(rock.position, rock.size * 1.4, 0.5, .{ 0.85, 0.75, 0.6 });
        rock.active = false;
        rock.respawn = 8;
        sb.cue(.pickup, null);
    }

    pub fn publish(self: *const State, center: V, catalog: *const Catalog.Content, out: []World.Prop, start: usize, time: f32) usize {
        var n = start;
        if (!self.active) return n;
        const at = struct {
            fn f(cen: V, p: V) V {
                return .{ cen[0] + p[0], cen[1] + p[1], cen[2] + p[2] };
            }
        }.f;
        const faction = Levels.faction(self.location);
        for (self.rocks) |rock| if (rock.active and n + 2 <= out.len) {
            const glow: [3]f32 = switch (rock.ore) {
                .iron => .{ 1, 0.48, 0.2 },
                .copper => .{ 0.25, 0.95, 0.62 },
                .crystal => .{ 0.62, 0.55, 1 },
            };
            out[n] = .{ .mesh = catalog.boulders[@intFromEnum(rock.ore) % catalog.boulders.len], .transform = .{ .position = at(center, rock.position), .scale = rock.size }, .tint = .{ 0.4, 0.37, 0.35, 1 }, .rotation = yawQuat(time * 0.2 + rock.size) };
            out[n + 1] = .{ .mesh = catalog.gem, .transform = .{ .position = at(center, R.add(rock.position, .{ 0, rock.size * 0.8, 0 })) }, .tint = Material.emissive(.{ glow[0], glow[1], glow[2], 1 }, 1.4), .size = @splat(rock.size * 0.35) };
            n += 2;
        };
        for (self.enemies) |e| if (e.active and n + 7 <= out.len) {
            const l = look(catalog, faction, e);
            const facing = std.math.atan2(-e.position[0], -e.position[2]);
            const yaw = if (e.kind == .mother_ship or e.kind == .battleship) std.math.pi else if (R.length(e.velocity) > 1) std.math.atan2(e.velocity[0], e.velocity[2]) else facing;
            const rotation = yawQuat(yaw);
            const announce = e.telegraph > 0 or (e.kind == .transformer and e.mode == 1);
            const body: [4]f32 = if (e.flash > 0) .{ 1.6, 1.6, 1.6, 1 } else l.tint;
            out[n] = .{ .mesh = l.mesh, .transform = .{ .position = at(center, e.position), .scale = l.scale }, .rotation = rotation, .tint = body };
            out[n + 1] = .{ .mesh = l.glow, .transform = out[n].transform, .rotation = rotation, .tint = Material.emissive(.{ l.light[0], l.light[1], l.light[2], 1 }, if (announce) 2.4 else 0.7) };
            // Seen from straight above, hulls alone read as rocks: a hostile disc in the
            // faction's colour sits under each one and flares while it winds up an attack.
            const r = radiusOf(e.kind) * 1.25;
            out[n + 2] = .{ .mesh = catalog.orb, .transform = .{ .position = at(center, R.sub(e.position, .{ 0, 1.5, 0 })) }, .tint = Material.emissive(.{ l.light[0], l.light[1], l.light[2], 1 }, if (announce) 1.6 else 0.55), .size = .{ r * 2, 0.15, r * 2 } };
            n += 3;
            if (l.mesh.eql(catalog.wasp)) for (ShipMeshes.wasp_wings, 0..) |root, k| {
                const s: f32 = if (root.x > 0) 1 else -1;
                const beat = @sin(time * 40 + @as(f32, @floatFromInt(k / 2)) * 1.4) * 0.7;
                const hull_turn = m.Quat.fromAxisAngle(m.Vec3.unit_y, yaw);
                const local = m.Quat.fromAxisAngle(m.Vec3.unit_y, if (s > 0) 0 else std.math.pi).mul(m.Quat.fromAxisAngle(m.Vec3.unit_z, beat * s * s));
                const q = hull_turn.mul(local);
                const off = hull_turn.rotate(root.scale(l.scale));
                out[n] = .{ .mesh = catalog.wasp_wing, .transform = .{ .position = at(center, R.add(e.position, .{ off.x, off.y, off.z })), .scale = l.scale }, .tint = .{ 1, 1, 1, 1 }, .rotation = .{ q.x, q.y, q.z, q.w } };
                n += 1;
            };
        };
        for (self.shots) |s| if (s.active and n + 1 <= out.len) {
            const p = at(center, s.position);
            out[n] = switch (s.kind) {
                .bolt => .{ .mesh = catalog.block, .transform = .{ .position = p }, .tint = Material.emissive(.{ 0.45, 1, 0.9, 1 }, 1.6), .size = .{ 0.5, 0.5, 4 }, .rotation = yawQuat(std.math.atan2(s.velocity[0], s.velocity[2])) },
                .blast => .{ .mesh = catalog.orb, .transform = .{ .position = p }, .tint = Material.emissive(.{ 0.6, 0.85, 1, 1 }, 2.2), .size = @splat(s.radius * 2) },
                .missile => .{ .mesh = catalog.block, .transform = .{ .position = p }, .tint = Material.emissive(.{ 1, 0.85, 0.5, 1 }, 1.3), .size = .{ 0.8, 0.8, 3 }, .rotation = yawQuat(std.math.atan2(s.velocity[0], s.velocity[2])) },
                .bomb => .{ .mesh = catalog.orb, .transform = .{ .position = p }, .tint = Material.emissive(.{ 0.4, 0.9, 1, 1 }, 1.4 + 0.6 * @sin(time * 14)), .size = @splat(3.6) },
                .orb => unreachable,
            };
            n += 1;
        };
        for (self.hostile) |s| if (s.active and n + 1 <= out.len) {
            const hue: [3]f32 = if (faction == .armada) .{ 0.85, 0.35, 1 } else .{ 1, 0.35, 0.2 };
            out[n] = .{ .mesh = catalog.orb, .transform = .{ .position = at(center, s.position) }, .tint = Material.emissive(.{ hue[0], hue[1], hue[2], 1 }, 1.8), .size = @splat(s.radius * 2.2) };
            n += 1;
        };
        for (self.bursts) |b| if (b.active and n + 1 <= out.len) {
            const k = b.age / b.life;
            out[n] = .{ .mesh = catalog.orb, .transform = .{ .position = at(center, b.position) }, .tint = Material.emissive(.{ b.color[0], b.color[1], b.color[2], 1 }, 1.8 * (1 - k)), .size = .{ b.radius * 2 * (0.3 + k), 0.4, b.radius * 2 * (0.3 + k) } };
            n += 1;
        };
        return n;
    }
};

// The mother ship moves to its next phase as its health falls, clearing the old pattern first.
fn phaseOf(e: *const Enemy) u8 {
    const share = e.health / e.max_health;
    return if (share > 0.6) 1 else if (share > 0.25) 2 else 3;
}

fn flat(v: V) V {
    return .{ v[0], 0, v[2] };
}

fn flatDistance(a: V, b: V) f32 {
    const dx = a[0] - b[0];
    const dz = a[2] - b[2];
    return @sqrt(dx * dx + dz * dz);
}

fn yawQuat(yaw: f32) [4]f32 {
    return .{ 0, @sin(yaw * 0.5), 0, @cos(yaw * 0.5) };
}

pub fn baseHealth(kind: Kind) f32 {
    return switch (kind) {
        .drone => 28,
        .fighter => 60,
        .transformer => 85,
        .battleship => 600,
        .mother_ship => 2400,
    };
}

pub fn radiusOf(kind: Kind) f32 {
    return switch (kind) {
        .drone => 2.5,
        .fighter => 3,
        .transformer => 3.2,
        .battleship => 10,
        .mother_ship => 16,
    };
}

pub fn points(kind: Kind) u32 {
    return switch (kind) {
        .drone => 100,
        .fighter => 250,
        .transformer => 400,
        .battleship => 2000,
        .mother_ship => 10000,
    };
}

const Look = struct { mesh: Catalog.MeshHandle, glow: Catalog.MeshHandle, scale: f32, tint: [4]f32, light: [3]f32 };

/// Each faction's craft for each role: the Brood fly insects, the armada robots, and the belt
/// sees both. A transformer of the armada shows its lancer form while it winds up and dashes.
fn look(catalog: *const Catalog.Content, faction: Levels.Faction, e: Enemy) Look {
    const insect = faction == .brood or (faction == .mixed and (e.kind == .drone or e.kind == .battleship));
    const brood_tint: [4]f32 = .{ 1, 0.85, 0.78, 1 };
    const robot_tint: [4]f32 = .{ 0.62, 0.74, 0.9, 1 };
    const ember: [3]f32 = .{ 1, 0.3, 0.1 };
    const ion: [3]f32 = .{ 0.2, 0.65, 1 };
    if (insect) return switch (e.kind) {
        .drone => .{ .mesh = catalog.wasp, .glow = catalog.wasp_glow, .scale = 2.4, .tint = brood_tint, .light = ember },
        .fighter => .{ .mesh = catalog.dragonfly, .glow = catalog.dragonfly_glow, .scale = 2.6, .tint = .{ 0.55, 1, 1.3, 1 }, .light = .{ 0.2, 0.75, 1 } },
        .transformer => .{ .mesh = catalog.beetle_bomber, .glow = catalog.beetle_bomber_glow, .scale = 2.7, .tint = .{ 1.3, 0.8, 0.4, 1 }, .light = ember },
        .battleship => .{ .mesh = catalog.carrier, .glow = catalog.carrier_glow, .scale = 0.42, .tint = brood_tint, .light = ember },
        .mother_ship => .{ .mesh = catalog.brood_crown, .glow = catalog.brood_crown_glow, .scale = 0.38, .tint = brood_tint, .light = ember },
    };
    return switch (e.kind) {
        .drone => .{ .mesh = catalog.robot_fighter, .glow = catalog.robot_fighter_glow, .scale = 2.2, .tint = robot_tint, .light = ion },
        .fighter => .{ .mesh = catalog.robot_fighter, .glow = catalog.robot_fighter_glow, .scale = 2.5, .tint = robot_tint, .light = ion },
        .transformer => if (e.mode == 0)
            .{ .mesh = catalog.robot_fighter, .glow = catalog.robot_fighter_glow, .scale = 2.6, .tint = .{ 0.8, 0.88, 1, 1 }, .light = ion }
        else
            .{ .mesh = catalog.robot_lancer, .glow = catalog.robot_lancer_glow, .scale = 2.6, .tint = .{ 0.8, 0.88, 1, 1 }, .light = .{ 0.9, 0.4, 1 } },
        .battleship => .{ .mesh = catalog.carrier, .glow = catalog.carrier_glow, .scale = 0.42, .tint = .{ 0.42, 0.55, 0.72, 1 }, .light = ion },
        .mother_ship => .{ .mesh = catalog.robot_forge_ark, .glow = catalog.robot_forge_ark_glow, .scale = 0.32, .tint = .{ 0.8, 0.88, 1, 1 }, .light = ion },
    };
}

fn testBattle(sandbox: *Sandbox, catalog: *Catalog, camera: *@import("../world/Camera.zig")) !void {
    try Sandbox.testSandbox(sandbox, catalog, camera);
    sandbox.hangar.placeWithFrame(sandbox.seed, Sandbox.spawn, null, 0, sandbox.progress.kestrel_levels, .kestrel);
    sandbox.hangar.enterSpaceTrial(.{ 0, 900, 0 }, Sandbox.spawn, camera);
}

/// Runs `seconds` of battle with the fighter held at the arena centre.
fn hold(sandbox: *Sandbox, controls: Controls, seconds: f32) void {
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < seconds) : (t += dt) {
        sandbox.hangar.fighter.?.body.pos = sandbox.hangar.space_center;
        sandbox.space_battle.step(sandbox, controls, dt);
    }
}

test "guns down a drone ahead, hostile shots cost hull with a grace window, and a bomb wipes them" {
    var catalog: Catalog = undefined;
    var camera: @import("../world/Camera.zig") = .{};
    var sandbox: Sandbox = undefined;
    try testBattle(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const battle = &sandbox.space_battle;
    battle.begin(.moon, 1, false, 9, .kestrel, @splat(0));
    try std.testing.expect(battle.liveEnemies() >= 4);
    // One drone straight ahead, nothing else.
    battle.enemies = @splat(.{});
    _ = battle.add(.drone, .{ 0, 0, 30 });
    battle.enemies[0].fire_clock = 99;
    battle.aim = 0;
    const scrap = sandbox.kits[0].wallet.scrap;
    hold(&sandbox, .{ .fire = true }, 0.4);
    try std.testing.expectEqual(@as(usize, 0), battle.liveEnemies());
    try std.testing.expectEqual(@as(u16, 1), battle.kills);
    try std.testing.expect(battle.score >= points(.drone));
    try std.testing.expect(sandbox.kits[0].wallet.scrap >= scrap);

    // Two orbs on the fighter in the same moment: only the first one counts.
    const f = &sandbox.hangar.fighter.?;
    const hull = f.hull;
    battle.shoot(.{ 0, 0, 2 }, .{ 0, 0, -1 }, 1, 12, 1.4);
    battle.shoot(.{ 0, 0, 2 }, .{ 0, 0, -1 }, 1, 12, 1.4);
    battle.hostileHits(&sandbox, .{ 0, 0, 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(hull - 12, f.hull);

    // A bomb's burst clears the hostile shots around it.
    battle.ring(.{ 0, 0, 40 }, 12, 0, 0.01, 12, 1.4);
    battle.detonate(&sandbox, .{ .kind = .bomb, .position = .{ 0, 0, 40 }, .damage = 1 });
    for (battle.hostile) |s| try std.testing.expect(!s.active);
}

test "the mother ship changes pattern as it weakens, and a cleared level pays everyone and opens the route" {
    var catalog: Catalog = undefined;
    var camera: @import("../world/Camera.zig") = .{};
    var sandbox: Sandbox = undefined;
    try testBattle(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const battle = &sandbox.space_battle;
    battle.begin(.moon, Levels.boss_level, false, 3, .bulwark, @splat(0));
    battle.spawnWave(Levels.waves);
    var boss: ?usize = null;
    for (battle.enemies, 0..) |e, i| if (e.active and e.kind == .mother_ship) {
        boss = i;
    };
    const b = &battle.enemies[boss.?];
    try std.testing.expectEqual(@as(u8, 1), b.mode);
    b.health = b.max_health * 0.5;
    sandbox.hangar.fighter.?.hull = 1e6;
    hold(&sandbox, .{}, 0.05);
    try std.testing.expectEqual(@as(u8, 2), b.mode);

    // Every hostile gone: after the gap the level is won and paid.
    for (&battle.enemies) |*e| e.active = false;
    const scrap = sandbox.kits[0].wallet.scrap;
    hold(&sandbox, .{}, wave_gap + 0.1);
    try std.testing.expectEqual(Result.won, battle.result);
    try std.testing.expect(Levels.cleared(&sandbox.progress, .moon, Levels.boss_level));
    try std.testing.expect(sandbox.progress.hasFlag("luna_rescued"));
    try std.testing.expectEqual(scrap + Levels.reward(.moon, Levels.boss_level).scrap, sandbox.kits[0].wallet.scrap);
}

test "the mining run breaks ore rocks into the pilot's own held ore" {
    var catalog: Catalog = undefined;
    var camera: @import("../world/Camera.zig") = .{};
    var sandbox: Sandbox = undefined;
    try testBattle(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const battle = &sandbox.space_battle;
    battle.begin(.asteroid_belt, 1, true, 5, .kestrel, @splat(0));
    battle.rocks[0] = .{ .active = true, .position = .{ 0, -2, 20 }, .health = 30, .ore = .copper, .size = 5 };
    for (battle.rocks[1..]) |*r| r.active = false;
    battle.aim = 0;
    const stockpile = sandbox.mining.colony.stockpile;
    hold(&sandbox, .{ .fire = true }, 0.6);
    try std.testing.expect(!battle.rocks[0].active);
    try std.testing.expect(sandbox.kits[0].ore[@intFromEnum(Colony.Ore.copper)] >= 2);
    // Nothing reaches the shared stockpile until the pilot deposits it.
    try std.testing.expectEqual(stockpile, sandbox.mining.colony.stockpile);
}
