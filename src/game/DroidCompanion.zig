//! The player's fabricated field droid. It follows and fights independently of the biological
//! pet, has its own health and XP track, and uses only fixed-capacity state in the frame loop.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Enemies = @import("Enemies.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const DroidCompanion = @This();

pub const max_owners = 4;
pub const max_level = 20;
pub const xp_per_unit: u32 = 18;
pub const share_radius: f32 = 35;

pub const Droid = struct {
    position: V,
    velocity: V = @splat(0),
    yaw: f32 = 0,
    health: f32 = 160,
    max_health: f32 = 160,
    cooldown: f32 = 0.5,
    hurt_cooldown: f32 = 0,
    flash: f32 = 0,
    engaged: bool = false,
};

pub const Event = union(enum) {
    attack: V,
    hurt: V,
};

pub const Context = struct {
    owner: V,
    owner_yaw: f32,
    level: u8,
    seed: u64,
    physics: *const Physics,
};

pub const tuning = .{
    .base_health = 160.0,
    .health_per_level = 14.0,
    .base_damage = 24.0,
    .damage_per_level = 4.0,
    .fire_interval = 0.82,
    .fire_range = 28.0,
    .follow_speed = 8.0,
    .fire_radius = 0.7,
};

pub fn levelFor(xp: u32) u8 {
    var level: u8 = 1;
    var need: u32 = 45;
    var left = xp;
    while (level < max_level and left >= need) {
        left -= need;
        need += 45;
        level += 1;
    }
    return level;
}

pub fn maxHealth(level: u8) f32 {
    return tuning.base_health + tuning.health_per_level * @as(f32, @floatFromInt(level -| 1));
}

pub fn damage(level: u8) f32 {
    return tuning.base_damage + tuning.damage_per_level * @as(f32, @floatFromInt(level -| 1));
}

out: [max_owners]?Droid = @splat(null),

pub fn summonFor(self: *DroidCompanion, owner_index: usize, owner: V, owner_yaw: f32, level: u8, seed: u64) void {
    const side = R.rotate(R.axisAngle(.{ 0, 1, 0 }, owner_yaw), .{ 1.6, 0, -1.5 });
    const at = R.add(owner, side);
    const hp = maxHealth(level);
    self.out[owner_index] = .{ .position = .{ at[0], Terrain.surface(seed, at[0], at[2]).height, at[2] }, .health = hp, .max_health = hp };
}

fn ground(ctx: Context, at: V) f32 {
    const terrain = Terrain.surface(ctx.seed, at[0], at[2]).height;
    const top = @max(at[1], ctx.owner[1]) + 2.5;
    if (ctx.physics.castRay(.{ at[0], top, at[2] }, .{ 0, -1, 0 }, 14, .none)) |hit| return @max(hit.point[1], terrain);
    return terrain;
}

pub fn step(self: *DroidCompanion, owner_index: usize, ctx: Context, enemies: *Enemies, dt: f32, hive: []Enemies.Event, hn: *usize, events: []Event) usize {
    var n: usize = 0;
    const existing = self.out[owner_index] orelse return 0;
    if (R.length(R.sub(existing.position, ctx.owner)) > 60) self.summonFor(owner_index, ctx.owner, ctx.owner_yaw, ctx.level, ctx.seed);
    const bot = &self.out[owner_index].?;
    const hp = maxHealth(ctx.level);
    if (hp > bot.max_health) bot.health = @min(hp, bot.health + hp - bot.max_health);
    bot.max_health = hp;
    bot.cooldown = @max(0, bot.cooldown - dt);
    bot.hurt_cooldown = @max(0, bot.hurt_cooldown - dt);
    bot.flash = @max(0, bot.flash - dt);

    const target = enemies.nearestUnit(R.add(ctx.owner, .{ 0, 1.1, 0 }), tuning.fire_range);
    bot.engaged = target != null and bot.health > 0;
    var goal = R.add(ctx.owner, R.rotate(R.axisAngle(.{ 0, 1, 0 }, ctx.owner_yaw), .{ 1.6, 0, -1.5 }));
    if (target) |t| {
        const away = R.normalize(.{ bot.position[0] - t[0], 0, bot.position[2] - t[2] });
        goal = R.add(t, R.scale(away, 7));
    }
    goal[1] = ground(ctx, goal);
    var to = R.sub(goal, bot.position);
    to[1] = 0;
    const distance = R.length(to);
    const wish = if (distance > 0.25) R.scale(R.normalize(to), @min(tuning.follow_speed, distance * 3)) else V{ 0, 0, 0 };
    bot.velocity = R.add(bot.velocity, R.scale(R.sub(wish, bot.velocity), @min(1, 7 * dt)));
    bot.position = R.add(bot.position, R.scale(bot.velocity, dt));
    bot.position[1] = ground(ctx, bot.position);

    if (target) |t| {
        const look = R.sub(t, bot.position);
        if (look[0] * look[0] + look[2] * look[2] > 0.01) bot.yaw = std.math.atan2(look[0], look[2]);
        if (bot.health > 0 and bot.cooldown == 0) {
            const dir = R.normalize(R.sub(t, R.add(bot.position, .{ 0, 0.9, 0 })));
            bot.cooldown = tuning.fire_interval;
            _ = enemies.strikeAlong(R.add(bot.position, .{ 0, 0.9, 0 }), dir, @min(tuning.fire_range, R.length(look) + 1), tuning.fire_radius, damage(ctx.level), hive, hn);
            if (n < events.len) events[n] = .{ .attack = R.add(bot.position, .{ 0, 1, 0 }) };
            n += 1;
        }
    }

    var threatened = target != null;
    for (enemies.units) |slot| if (slot) |unit| {
        const d = R.length(R.sub(unit.center(), bot.position));
        if (d < 12) threatened = true;
        if (bot.health > 0 and bot.hurt_cooldown == 0 and Enemies.stats(unit.kind).melee_damage > 0 and unit.state == .hunt and d < 2.4) {
            bot.health = @max(0, bot.health - Enemies.stats(unit.kind).melee_damage * 0.45);
            bot.hurt_cooldown = 1.2;
            bot.flash = 0.18;
            if (n < events.len) events[n] = .{ .hurt = bot.position };
            n += 1;
            break;
        }
    };
    if (!threatened and bot.hurt_cooldown == 0) bot.health = @min(bot.max_health, bot.health + 12 * dt);
    return n;
}
