//! The Starbowl: a four-player co-op arena floating high above the Frontier, entered from the
//! menu (Pause > HERO ARENA, or the title). The party fights waves of Hive bots on a walled
//! platform; every cleared wave pays out loot (pickups on the floor, scrap to the wallet), and
//! every third wave a Wildkin arena champion, impressed, joins the roster. The best wave is
//! saved. Players who fall off are caught and set back on the floor; players knocked out get
//! back up at the centre. Leaving returns everyone to where they were.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Enemies = @import("Enemies.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Arena = @This();

/// Half the floor's side, the wall height, and how high the bowl floats over the ground.
pub const half: f32 = 28;
pub const wall_height: f32 = 3;
pub const altitude: f32 = 150;
/// Seconds between a cleared wave and the next.
pub const intermission: f32 = 6;
pub const max_players = 4;

pub const Mix = struct { drones: u8, troopers: u8, sentinels: u8 };

/// Wave `wave` (from 1) for `party` players: more bots, and tougher ones, as waves go on.
pub fn mix(wave: u16, party: u8) Mix {
    const w: u32 = wave;
    const p: u32 = @max(1, party);
    return .{
        .troopers = @intCast(@min(10, 1 + w / 2 + (p - 1))),
        .drones = @intCast(@min(8, w + p - 1)),
        .sentinels = @intCast(@min(3, w / 4)),
    };
}

/// Health multiplier for bots in wave `wave`.
pub fn toughness(wave: u16) f32 {
    return 1 + 0.12 * @as(f32, @floatFromInt(wave -| 1));
}

pub const Reward = struct { scrap: u32, lumen: u8, alloy: u8, rotor: u8, vital: u8 };

pub fn reward(wave: u16) Reward {
    return .{
        .scrap = 20 + 15 * @as(u32, wave),
        .lumen = @intCast(@min(6, 1 + wave / 2)),
        .alloy = @intCast(@min(4, wave / 2)),
        .rotor = @intFromBool(wave % 3 == 0),
        .vital = @intFromBool(wave % 5 == 0),
    };
}

pub const Event = union(enum) {
    wave_started: u16,
    wave_cleared: struct { wave: u16, reward: Reward },
};

active: bool = false,
center: V = @splat(0),
wave: u16 = 0,
/// Counting down to the next wave (0 while a wave is being fought).
waiting: f32 = 0,
/// Where each player stood before entering, to return them on leaving.
returns: [max_players]?V = @splat(null),
colliders: [5]Physics.MeshCollider = @splat(.none),

/// The bowl's floor centre for a world: floating over the meadow beside the spawn.
pub fn site(seed: u64, origin: V) V {
    const x = origin[0] - 140;
    const z = origin[2] - 120;
    return .{ x, Terrain.surface(seed, x, z).height + altitude, z };
}

/// A spot on the floor for player `p`, around the centre.
pub fn standing(self: *const Arena, p: usize) V {
    const a = @as(f32, @floatFromInt(p)) * std.math.pi / 2 + 0.4;
    return R.add(self.center, .{ @sin(a) * 4, 0, @cos(a) * 4 });
}

/// Builds the floor and walls; `at` is the floor centre.
pub fn open(self: *Arena, allocator: std.mem.Allocator, physics: *Physics, at: V, user: u32) !void {
    self.center = at;
    const boxes = [_]struct { c: V, h: V }{
        .{ .c = R.add(at, .{ 0, -1, 0 }), .h = .{ half, 1, half } },
        .{ .c = R.add(at, .{ half, wall_height / 2, 0 }), .h = .{ 0.6, wall_height / 2, half } },
        .{ .c = R.add(at, .{ -half, wall_height / 2, 0 }), .h = .{ 0.6, wall_height / 2, half } },
        .{ .c = R.add(at, .{ 0, wall_height / 2, half }), .h = .{ half, wall_height / 2, 0.6 } },
        .{ .c = R.add(at, .{ 0, wall_height / 2, -half }), .h = .{ half, wall_height / 2, 0.6 } },
    };
    for (boxes, 0..) |b, i| {
        if (!self.colliders[i].eql(.none)) continue;
        self.colliders[i] = try physics.createBox(allocator, b.c, b.h, R.identity, user);
    }
    self.active = true;
    self.wave = 0;
    self.waiting = 3;
}

/// Removes the floor and walls and ends the run (bots of the arena are the caller's to clear).
pub fn close(self: *Arena, physics: *Physics) void {
    for (&self.colliders) |*c| if (!c.eql(.none)) {
        physics.destroyMesh(c.*);
        c.* = .none;
    };
    self.active = false;
}

/// Whether `p` has fallen off the bowl (to be set back on the floor).
pub fn fallen(self: *const Arena, p: V) bool {
    return p[1] < self.center[1] - 25;
}

/// Inside the bowl's walls (and not far above the floor).
pub fn inside(self: *const Arena, p: V) bool {
    return @abs(p[0] - self.center[0]) < half + 2 and @abs(p[2] - self.center[2]) < half + 2 and p[1] > self.center[1] - 25 and p[1] < self.center[1] + 60;
}

/// One fixed step: start the next wave after the intermission, or notice a cleared one.
/// `bots` is how many arena bots are still standing.
pub fn step(self: *Arena, enemies: *Enemies, nest: u8, party: u8, bots: usize, dt: f32, out: []Event) usize {
    var n: usize = 0;
    if (!self.active) return 0;
    if (self.waiting > 0) {
        self.waiting -= dt;
        if (self.waiting <= 0) {
            self.waiting = 0;
            self.wave += 1;
            self.spawnWave(enemies, nest, party);
            if (n < out.len) out[n] = .{ .wave_started = self.wave };
            n += 1;
        }
        return n;
    }
    if (bots == 0 and self.wave > 0) {
        if (n < out.len) out[n] = .{ .wave_cleared = .{ .wave = self.wave, .reward = reward(self.wave) } };
        n += 1;
        self.waiting = intermission;
    }
    return n;
}

fn spawnWave(self: *Arena, enemies: *Enemies, nest: u8, party: u8) void {
    const m = mix(self.wave, party);
    const tough = toughness(self.wave);
    var k: usize = 0;
    const total: usize = @as(usize, m.drones) + m.troopers + m.sentinels;
    for (0..total) |i| {
        const kind: Enemies.Kind = if (i < m.sentinels) .sentinel else if (i < @as(usize, m.sentinels) + m.troopers) .trooper else .drone;
        // Around the rim, facing in; fliers above it.
        const a = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(total)) * 2 * std.math.pi + @as(f32, @floatFromInt(self.wave)) * 0.7;
        k += 1;
        const r = half - 4;
        const lift: f32 = switch (kind) {
            .trooper => 0.2,
            .drone => 7,
            .sentinel => 10,
        };
        _ = enemies.spawnAt(kind, nest, R.add(self.center, .{ @sin(a) * r, lift, @cos(a) * r }), tough);
    }
}

test "waves grow with the wave and the party, pay out, and the bowl opens and closes" {
    try std.testing.expect(mix(1, 1).troopers >= 1 and mix(1, 1).drones >= 1 and mix(1, 1).sentinels == 0);
    try std.testing.expect(mix(4, 4).troopers > mix(4, 1).troopers);
    try std.testing.expect(mix(8, 1).sentinels > 0);
    try std.testing.expect(reward(3).rotor == 1 and reward(5).vital == 1 and reward(4).scrap > reward(1).scrap);

    var physics = Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
    defer physics.deinit();
    var arena: Arena = .{};
    try arena.open(std.testing.allocator, &physics, .{ 0, 150, 0 }, 0);
    // The floor holds a body up there.
    const stand = physics.moveCharacter(.{}, .{ 3, 150.2, 3 }, .{ 0, -0.5, 0 }, false);
    try std.testing.expect(stand.grounded and @abs(stand.feet[1] - 150) < 0.01);
    var enemies: Enemies = .{};
    const nest = enemies.addArenaNest(arena.center);
    var events: [4]Event = undefined;
    var started = false;
    for (0..240) |_| {
        const k = arena.step(&enemies, nest, 2, enemies.unitCount(nest), 1.0 / 60.0, &events);
        for (events[0..@min(k, events.len)]) |e| started = started or e == .wave_started;
    }
    try std.testing.expect(started and arena.wave == 1 and enemies.unitCount(nest) >= 3);
    // Every bot down: the wave is cleared, with its reward, and the next comes after a pause.
    for (&enemies.units) |*u| u.* = null;
    const k = arena.step(&enemies, nest, 2, 0, 1.0 / 60.0, &events);
    try std.testing.expect(k == 1 and events[0] == .wave_cleared and events[0].wave_cleared.wave == 1);
    try std.testing.expect(arena.waiting > 0);
    arena.close(&physics);
    try std.testing.expect(!arena.active);
    for (arena.colliders) |c| try std.testing.expect(c.eql(.none));
}
