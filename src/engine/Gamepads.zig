const std = @import("std");
const Input = @import("Input.zig");
const Gamepads = @This();
pub const Sample = extern struct { lx: f32 = 0, ly: f32 = 0, rx: f32 = 0, ry: f32 = 0, buttons: u32 = 0, connected: u32 = 0 };
pub const Command = struct { input: Input = .{}, join: bool = false, view: bool = false, interact: bool = false };
extern fn hw_gamepads(out: [*]Sample) void;
previous: [4]u32 = @splat(0),
commands: [4]Command = @splat(.{}),
pub fn poll(self: *Gamepads) void {
    var samples: [4]Sample = @splat(.{});
    if (@import("builtin").os.tag == .macos) hw_gamepads(&samples);
    self.sample(samples);
}
fn stick(x: f32, y: f32) [2]f32 {
    const length = @sqrt(x * x + y * y);
    if (length <= 0.18 or !std.math.isFinite(length)) return .{ 0, 0 };
    const amount = @min(1, (length - 0.18) / 0.82);
    return .{ x / length * amount, y / length * amount };
}
pub fn sample(self: *Gamepads, samples: [4]Sample) void {
    for (samples, 0..) |s, i| {
        const buttons = if (s.connected != 0) s.buttons else 0;
        const edges = buttons & ~self.previous[i];
        self.previous[i] = buttons;
        const move = stick(if (s.connected != 0) s.lx else 0, if (s.connected != 0) s.ly else 0);
        const look = stick(if (s.connected != 0) s.rx else 0, if (s.connected != 0) s.ry else 0);
        const cmd = &self.commands[i];
        cmd.input.forward = move[1];
        cmd.input.right = move[0];
        cmd.input.look_x = look[0];
        cmd.input.look_y = -look[1];
        cmd.input.jump = buttons & 1 != 0;
        cmd.input.fast = buttons & (1 << 6) != 0;
        cmd.input.dodge_held = buttons & 2 != 0;
        cmd.input.mantle = buttons & (1 << 2) != 0;
        cmd.input.jump_pressed = cmd.input.jump_pressed or edges & 1 != 0;
        cmd.input.dodge = cmd.input.dodge or edges & 2 != 0;
        cmd.input.stomp = cmd.input.stomp or edges & (1 << 10) != 0;
        cmd.input.grapple = cmd.input.grapple or edges & (1 << 4) != 0;
        cmd.input.cycle_mode = cmd.input.cycle_mode or edges & (1 << 5) != 0;
        cmd.view = cmd.view or edges & (1 << 3) != 0;
        cmd.interact = cmd.interact or edges & (1 << 2) != 0;
        cmd.join = cmd.join or edges & (1 << 8) != 0;
        if (s.connected == 0) cmd.* = .{};
    }
}
pub fn consume(self: *Gamepads) void {
    for (&self.commands) |*c| {
        c.input.clearEdges();
        c.view = false;
        c.interact = false;
        c.join = false;
    }
}
/// Three guests first; a fourth controller operates P1 alongside the keyboard.
pub fn playerIndex(controller: usize) usize {
    return (controller + 1) % 4;
}

test "pads preserve ownership, radial deadzone, once-only edges and disconnect neutralization" {
    var pads: Gamepads = .{};
    var samples: [4]Sample = @splat(.{});
    samples[1] = .{ .connected = 1, .lx = 0.1, .ly = 0.1, .buttons = 1 };
    pads.sample(samples);
    try std.testing.expectEqual(@as(f32, 0), pads.commands[1].input.forward);
    try std.testing.expect(pads.commands[1].input.jump_pressed);
    pads.sample(samples); // A render frame with no fixed step must retain the edge.
    try std.testing.expect(pads.commands[1].input.jump_pressed);
    pads.consume();
    pads.sample(samples);
    try std.testing.expect(!pads.commands[1].input.jump_pressed);
    samples[1].connected = 0;
    pads.sample(samples);
    try std.testing.expect(!pads.commands[1].input.jump);
    try std.testing.expectEqual(@as(usize, 2), playerIndex(1));
}
