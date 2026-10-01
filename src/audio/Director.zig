//! Turns what happens in the game into sound. Each frame the application takes a `Snapshot` of
//! the session (players, wallet, flags, conversation) and the director compares it with the
//! previous one: footsteps on stride, jumps and landings, rolls and dashes, grapple shots,
//! purchases, salvage, an opened vault, the dawn restock, dialogue blips and refusals. Guests are
//! placed in stereo and attenuated by distance from P1's camera. Ambient loops (wind by speed and
//! height, jets while flying, the canopy pad) follow continuously.
const std = @import("std");
const Mixer = @import("Mixer.zig");
const Player = @import("../game/Player.zig");
const Sandbox = @import("../game/Sandbox.zig");
const Camera = @import("../world/Camera.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Director = @This();

pub const max_bodies = Sandbox.max_players;
pub const Body = struct {
    active: bool = false,
    position: [3]f32 = @splat(0),
    velocity: [3]f32 = @splat(0),
    motion: Player.Motion = .idle,
    grounded: bool = true,
    walk_phase: f32 = 0,
    walk_amount: f32 = 0,
    grapple_windup: bool = false,
};
pub const Snapshot = struct {
    listener: [3]f32 = @splat(0),
    yaw: f32 = 0,
    /// P1 first, then guests by slot.
    bodies: [max_bodies]Body = @splat(.{}),
    /// P1's height above the terrain, for the wind.
    clearance: f32 = 0,
    flying: bool = false,
    scrap: u32 = 0,
    parts: u32 = 0,
    vault_opened: bool = false,
    market_day: u64 = 0,
    /// Characters of the current conversation line revealed, and the speaker's accent.
    talk_reveal: ?usize = null,
    talk_accent: u8 = 0,
    /// Changes whenever a new notice is posted; `refusal` when it reports a failure.
    notice_serial: u64 = 0,
    refusal: bool = false,
    /// The world is paused (menus): ambience dips and nothing steps.
    paused: bool = false,
};
pub const Ui = enum { move, confirm, back, refuse };

previous: Snapshot = .{},
primed: bool = false,

pub fn snapshot(sb: *const Sandbox, camera: Camera, paused: bool) Snapshot {
    var s: Snapshot = .{
        .listener = .{ camera.position.x(), camera.position.y(), camera.position.z() },
        .yaw = camera.yaw,
        .scrap = sb.wallet.scrap,
        .parts = sb.wallet.parts,
        .vault_opened = sb.progress.hasFlag("shrine_complete"),
        .market_day = sb.market.day,
        .notice_serial = sb.notice_until,
        .refusal = std.mem.startsWith(u8, sb.noticeText(), "cannot"),
        .flying = sb.player.mode == .fly or sb.seated != null,
        .paused = paused,
    };
    const p = sb.player;
    if (sb.seated == null) s.bodies[0] = body(p, sb.walk_phase, sb.walk_amount);
    s.clearance = p.feet[1] - Terrain.surface(sb.seed, p.feet[0], p.feet[2]).height;
    for (sb.guests, 1..) |g, i| if (g.active) {
        s.bodies[i] = body(g.player, g.walk_phase, g.walk_amount);
    };
    if (sb.talk) |t| {
        s.talk_reveal = @intFromFloat(@min(t.reveal, @as(f32, @floatFromInt(sb.dialogue.node(t).text.len))));
        s.talk_accent = sb.dialogue.speaker(t).accent;
    }
    return s;
}

fn body(p: Player, phase: f32, amount: f32) Body {
    return .{ .active = true, .position = p.feet, .velocity = p.velocity, .motion = p.motion, .grounded = p.grounded, .walk_phase = phase, .walk_amount = amount, .grapple_windup = p.grapple.mode == .windup };
}

/// Distance attenuation and stereo pan of a point heard from the listener.
pub fn place(s: Snapshot, point: [3]f32) struct { gain: f32, pan: f32 } {
    const d: [3]f32 = .{ point[0] - s.listener[0], point[1] - s.listener[1], point[2] - s.listener[2] };
    const distance = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    if (distance > 45) return .{ .gain = 0, .pan = 0 };
    const right: [3]f32 = .{ @cos(s.yaw), 0, -@sin(s.yaw) };
    const pan = if (distance < 0.5) 0 else (d[0] * right[0] + d[2] * right[2]) / distance;
    return .{ .gain = 1 / (1 + distance / 6), .pan = pan * 0.8 };
}

/// Menu and panel feedback, on the interface bus.
pub fn ui(sink: anytype, event: Ui) void {
    sink.send(.{ .play = .{ .sound = switch (event) {
        .move => .ui_move,
        .confirm => .ui_confirm,
        .back => .ui_back,
        .refuse => .ui_error,
    }, .bus = .interface, .gain = if (event == .move) 0.6 else 1 } });
}

fn play(sink: anytype, sound: Mixer.Sound, gain: f32, pan: f32, pitch: f32) void {
    if (gain <= 0.01) return;
    sink.send(.{ .play = .{ .sound = sound, .gain = gain, .pan = pan, .pitch = pitch } });
}

pub fn update(self: *Director, sink: anytype, now: Snapshot) void {
    defer {
        self.previous = now;
        self.primed = true;
    }
    const was = self.previous;
    // Loops follow continuously, even on the first frame.
    const p1 = now.bodies[0];
    const speed = @sqrt(p1.velocity[0] * p1.velocity[0] + p1.velocity[1] * p1.velocity[1] + p1.velocity[2] * p1.velocity[2]);
    const pause_dip: f32 = if (now.paused) 0.35 else 1;
    const wind = std.math.clamp(0.12 + speed / 45 + std.math.clamp(now.clearance, 0, 300) / 300, 0, 0.9);
    sink.send(.{ .loop = .{ .sound = .wind, .gain = wind * pause_dip } });
    sink.send(.{ .loop = .{ .sound = .canopy, .gain = 0.3 * pause_dip } });
    const jet: f32 = if (now.paused or !p1.active) 0 else switch (p1.motion) {
        .jet, .hover, .board => 0.55,
        .glide => 0.25,
        else => 0,
    };
    sink.send(.{ .loop = .{ .sound = .jet, .gain = jet, .bus = .effects } });
    if (!self.primed or now.paused) return;

    for (now.bodies, was.bodies, 0..) |b, before, i| {
        if (!b.active or !before.active) continue;
        const where = if (i == 0) @TypeOf(place(now, b.position)){ .gain = 1, .pan = 0 } else place(now, b.position);
        // A footfall each half stride while running on the ground.
        const step_now: i32 = @intFromFloat(@floor(b.walk_phase / std.math.pi));
        const step_was: i32 = @intFromFloat(@floor(before.walk_phase / std.math.pi));
        if (step_now != step_was and b.grounded and b.walk_amount > 0.25 and (b.motion == .run or b.motion == .sprint or b.motion == .board))
            play(sink, .footstep, where.gain * (0.35 + 0.25 * b.walk_amount), where.pan, if (@mod(step_now, 2) == 0) 1 else 0.92);
        if (before.grounded and !b.grounded and b.velocity[1] > 2) play(sink, .jump, where.gain * 0.5, where.pan, 1);
        if (!before.grounded and b.grounded and before.velocity[1] < -4) play(sink, .land, where.gain * std.math.clamp(-before.velocity[1] / 18, 0.25, 1), where.pan, 1);
        if (b.motion != before.motion) switch (b.motion) {
            .roll => play(sink, .dash, where.gain * 0.45, where.pan, 1.2),
            .dash => play(sink, .dash, where.gain * 0.7, where.pan, 1),
            .stomp => play(sink, .dash, where.gain * 0.7, where.pan, 0.6),
            else => {},
        };
        if (b.grapple_windup and !before.grapple_windup) play(sink, .grapple, where.gain * 0.7, where.pan, 1);
    }
    if (now.scrap < was.scrap) play(sink, .purchase, 0.7, 0, 1);
    if (now.scrap > was.scrap) play(sink, .purchase, 0.6, 0, 1.25);
    if (now.parts > was.parts) play(sink, .salvage, 0.7, 0, 1);
    if (now.vault_opened and !was.vault_opened) play(sink, .vault, 0.9, 0, 1);
    if (now.market_day != was.market_day) play(sink, .restock, 0.5, 0, 1);
    if (now.notice_serial != was.notice_serial and now.refusal) ui(sink, .refuse);
    // Dialogue: a soft blip every third revealed character, pitched by the speaker.
    if (now.talk_reveal) |shown| {
        const before = if (was.talk_reveal) |w| (if (w <= shown) w else 0) else 0;
        if (shown / 3 != before / 3 and shown > before)
            sink.send(.{ .play = .{ .sound = .talk_blip, .bus = .interface, .gain = 0.35, .pitch = 0.85 + 0.09 * @as(f32, @floatFromInt(now.talk_accent)) } });
    }
}

const Recorder = struct {
    commands: [64]Mixer.Command = undefined,
    len: usize = 0,
    fn send(self: *Recorder, c: Mixer.Command) void {
        if (self.len < self.commands.len) self.commands[self.len] = c;
        self.len += 1;
    }
    fn played(self: *const Recorder, sound: Mixer.Sound) usize {
        var n: usize = 0;
        for (self.commands[0..@min(self.len, self.commands.len)]) |c| if (c == .play and c.play.sound == sound) {
            n += 1;
        };
        return n;
    }
};

test "game changes become sounds once, with guests placed by distance and side" {
    var d: Director = .{};
    var r: Recorder = .{};
    var s: Snapshot = .{ .scrap = 50 };
    s.bodies[0] = .{ .active = true, .motion = .run, .walk_amount = 1, .walk_phase = 3.0 };
    d.update(&r, s);
    // The first frame only sets the loops.
    try std.testing.expectEqual(@as(usize, 0), r.played(.footstep));
    r = .{};
    s.bodies[0].walk_phase = 3.3; // crosses pi: a footfall
    s.scrap = 30;
    s.parts = 1;
    d.update(&r, s);
    try std.testing.expectEqual(@as(usize, 1), r.played(.footstep));
    try std.testing.expectEqual(@as(usize, 1), r.played(.purchase));
    try std.testing.expectEqual(@as(usize, 1), r.played(.salvage));
    r = .{};
    d.update(&r, s);
    try std.testing.expectEqual(@as(usize, 0), r.played(.footstep) + r.played(.purchase) + r.played(.salvage));

    // Jump, then a hard landing.
    s.bodies[0].grounded = false;
    s.bodies[0].velocity = .{ 0, 7, 0 };
    d.update(&r, s);
    s.bodies[0].velocity = .{ 0, -12, 0 };
    d.update(&r, s);
    s.bodies[0].grounded = true;
    s.bodies[0].velocity = .{ 0, 0, 0 };
    d.update(&r, s);
    try std.testing.expectEqual(@as(usize, 1), r.played(.jump));
    try std.testing.expectEqual(@as(usize, 1), r.played(.land));

    // A guest to the camera's right is panned right and quieter with distance.
    const near = place(.{ .yaw = 0 }, .{ 3, 0, 0 });
    const far = place(.{ .yaw = 0 }, .{ 30, 0, 0 });
    try std.testing.expect(near.pan > 0.7 and near.gain > far.gain and far.gain > 0);
    try std.testing.expectEqual(@as(f32, 0), place(.{}, .{ 100, 0, 0 }).gain);

    // Dialogue blips as text reveals; paused worlds make no event sounds.
    r = .{};
    s.talk_reveal = 0;
    d.update(&r, s);
    s.talk_reveal = 7;
    d.update(&r, s);
    try std.testing.expectEqual(@as(usize, 1), r.played(.talk_blip));
    s.paused = true;
    s.parts = 9;
    d.update(&r, s);
    try std.testing.expectEqual(@as(usize, 0), r.played(.salvage));
}
