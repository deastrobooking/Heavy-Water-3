//! Combat feel: floating damage numbers and per-player camera shake, fed by what the Hive took
//! (`Enemies.hits`) and what each player took. Everything is per player, so one player's big hit
//! never shakes a teammate's screen. Fixed size, no allocation; the renderer and the HUD only
//! read it. Rumble is queued here per player and sent by the app to that player's controllers.
//! (Hitstop lives with the swing in `Combat`.)
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Enemies = @import("Enemies.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;

pub const max_players = 4;
pub const max_numbers = 24;
/// Seconds a number floats before it is gone, and how far it rises meanwhile.
pub const number_life: f32 = 0.9;
pub const number_rise: f32 = 1.4;
/// Shake reach: a hit this close to a player (metres) shakes that player's view.
pub const melee_reach: f32 = 6;
/// A hit at least this heavy shakes everyone within `blast_reach`.
pub const blast_damage: f32 = 60;
pub const blast_reach: f32 = 25;
/// Trauma (0 to 1) fades by this much per second; the screen moves by trauma squared.
pub const trauma_decay: f32 = 1.6;
/// The largest camera offset, in metres, at full trauma.
pub const max_shake: f32 = 0.32;

/// A queued controller buzz: 0 to 1 strength for some seconds.
pub const Pulse = struct { strength: f32 = 0, seconds: f32 = 0 };

/// `side` spreads numbers from one target sideways (metres) so a combo does not stack them.
pub const Number = struct { position: V, amount: f32, age: f32 = 0, killed: bool = false, side: f32 = 0 };

pub const State = struct {
    numbers: [max_numbers]Number = undefined,
    number_count: usize = 0,
    serial: u8 = 0,
    trauma: [max_players]f32 = @splat(0),
    /// The strongest buzz each player earned since the app last sent rumble.
    pulses: [max_players]Pulse = @splat(.{}),
    clock: f32 = 0,
    /// Settings: draw numbers, and how strong shaking is (0 turns it off).
    show_numbers: bool = true,
    shake_scale: f32 = 1,

    pub fn addNumber(self: *State, position: V, amount: f32, killed: bool) void {
        self.serial +%= 1;
        const side = (@as(f32, @floatFromInt(self.serial % 5)) - 2) * 0.35;
        // When full, the oldest number makes room.
        if (self.number_count == max_numbers) {
            var oldest: usize = 0;
            for (self.numbers[0..self.number_count], 0..) |n, i| if (n.age > self.numbers[oldest].age) {
                oldest = i;
            };
            self.numbers[oldest] = .{ .position = position, .amount = amount, .killed = killed, .side = side };
            return;
        }
        self.numbers[self.number_count] = .{ .position = position, .amount = amount, .killed = killed, .side = side };
        self.number_count += 1;
    }

    /// Adds shake to player `p`'s view, clamped to full.
    pub fn shake(self: *State, p: usize, amount: f32) void {
        if (p >= max_players) return;
        self.trauma[p] = std.math.clamp(self.trauma[p] + amount, 0, 1);
    }

    /// Queues a buzz for player `p`; within one frame the strongest wins.
    pub fn buzz(self: *State, p: usize, strength: f32, seconds: f32) void {
        if (p >= max_players or strength <= self.pulses[p].strength) return;
        self.pulses[p] = .{ .strength = @min(strength, 1), .seconds = seconds };
    }

    /// Hands over and clears player `p`'s queued buzz.
    pub fn takePulse(self: *State, p: usize) Pulse {
        if (p >= max_players) return .{};
        defer self.pulses[p] = .{};
        return self.pulses[p];
    }

    /// A player took `damage`: their own view shakes and their controller buzzes with it.
    pub fn hurt(self: *State, p: usize, damage: f32) void {
        self.shake(p, std.math.clamp(damage / 60, 0.08, 0.5));
        self.buzz(p, std.math.clamp(damage / 40, 0.3, 1), 0.16);
    }

    pub fn step(self: *State, dt: f32) void {
        self.clock += dt;
        var i: usize = 0;
        while (i < self.number_count) {
            self.numbers[i].age += dt;
            if (self.numbers[i].age >= number_life) {
                self.number_count -= 1;
                self.numbers[i] = self.numbers[self.number_count];
            } else i += 1;
        }
        for (&self.trauma) |*t| t.* = @max(0, t.* - trauma_decay * dt);
    }

    /// Player `p`'s camera offset this frame: smooth noise scaled by trauma squared.
    pub fn offset(self: *const State, p: usize) V {
        if (p >= max_players) return @splat(0);
        const amount = self.trauma[p] * self.trauma[p] * max_shake * self.shake_scale;
        if (amount <= 0) return @splat(0);
        const t = self.clock * 31 + @as(f32, @floatFromInt(p)) * 7.3;
        return .{ amount * @sin(t * 1.13), amount * @sin(t * 1.71 + 1.3) * 0.7, amount * @sin(t * 0.97 + 2.1) };
    }

    /// Where a number is drawn now (it rises as it ages) and how opaque it is.
    pub fn place(n: Number) struct { at: V, alpha: f32 } {
        const k = n.age / number_life;
        // Held solid for most of its life, then a quick fade.
        return .{ .at = R.add(n.position, .{ n.side, 0.6 + number_rise * k, 0 }), .alpha = 1 - k * k * k };
    }
};

/// Players' chests, by slot, for attributing nearby hits (null when the slot is empty).
pub const Chests = [max_players]?V;

/// Reads and clears the Hive's hit record: a number per hit, and shake for the players near it
/// (a heavy blast shakes everyone within `blast_reach`; any hit shakes those within
/// `melee_reach`, more when it kills).
pub fn consume(self: *State, enemies: *Enemies, chests: Chests) void {
    for (enemies.hits[0..enemies.hit_count]) |h| {
        if (self.show_numbers and h.damage >= 1) self.addNumber(h.position, h.damage, h.killed);
        for (chests, 0..) |chest, p| {
            const c = chest orelse continue;
            const d = R.length(R.sub(c, h.position));
            if (d < melee_reach) {
                self.shake(p, if (h.killed) 0.3 else 0.12);
                self.buzz(p, if (h.killed) 0.45 else 0.2, if (h.killed) 0.1 else 0.05);
            }
            if (h.damage >= blast_damage and d < blast_reach) {
                self.shake(p, 0.35 * (1 - d / blast_reach));
                self.buzz(p, 0.6 * (1 - d / blast_reach), 0.18);
            }
        }
    }
    enemies.hit_count = 0;
}

test "hits become numbers and shake only the players near them; both fade" {
    var enemies: Enemies = .{};
    var s: State = .{};
    enemies.hits[0] = .{ .position = .{ 0, 1, 0 }, .damage = 24, .killed = false };
    enemies.hits[1] = .{ .position = .{ 0, 1, 0 }, .damage = 90, .killed = true };
    enemies.hit_count = 2;
    // P1 is in the fight, P2 is 15 m away (inside the blast reach only), P3 far off, P4 absent.
    consume(&s, &enemies, .{ V{ 1, 1, 0 }, V{ 15, 1, 0 }, V{ 200, 1, 0 }, null });
    try std.testing.expectEqual(@as(u8, 0), enemies.hit_count);
    try std.testing.expectEqual(@as(usize, 2), s.number_count);
    try std.testing.expect(s.trauma[0] > s.trauma[1] and s.trauma[1] > 0);
    try std.testing.expectEqual(@as(f32, 0), s.trauma[2]);
    try std.testing.expectEqual(@as(f32, 0), s.trauma[3]);
    // The fighter's pad buzzes for the kill; the far player's does not.
    try std.testing.expect(s.takePulse(0).strength >= 0.45);
    try std.testing.expectEqual(@as(f32, 0), s.takePulse(0).strength);
    try std.testing.expectEqual(@as(f32, 0), s.takePulse(2).strength);
    // Shake is bounded and only on that player's view.
    try std.testing.expect(R.length(s.offset(0)) <= max_shake * 1.8 + 1e-4);
    try std.testing.expectEqual(V{ 0, 0, 0 }, s.offset(2));
    // Numbers rise and fade, then go; trauma fades to nothing.
    const early = State.place(s.numbers[0]);
    for (0..30) |_| s.step(1.0 / 60.0);
    const later = State.place(s.numbers[0]);
    try std.testing.expect(later.at[1] > early.at[1] and later.alpha < early.alpha);
    for (0..60) |_| s.step(1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 0), s.number_count);
    try std.testing.expectEqual(@as(f32, 0), s.trauma[0]);
}

test "a player's own hurt shakes their view, the number list never overflows, settings switch both off" {
    var s: State = .{};
    s.hurt(2, 30);
    try std.testing.expect(s.trauma[2] > 0 and s.trauma[0] == 0);
    s.hurt(2, 400);
    const pulse = s.takePulse(2);
    try std.testing.expect(pulse.strength <= 1 and pulse.seconds > 0);
    for (0..100) |i| s.addNumber(.{ 0, 0, 0 }, @floatFromInt(i), false);
    try std.testing.expectEqual(@as(usize, max_numbers), s.number_count);
    s.shake_scale = 0;
    try std.testing.expectEqual(V{ 0, 0, 0 }, s.offset(2));
    var off: State = .{ .show_numbers = false };
    var enemies: Enemies = .{};
    enemies.hits[0] = .{ .position = .{ 0, 0, 0 }, .damage = 50, .killed = false };
    enemies.hit_count = 1;
    consume(&off, &enemies, @splat(null));
    try std.testing.expectEqual(@as(usize, 0), off.number_count);
}
