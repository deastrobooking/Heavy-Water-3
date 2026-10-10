const std = @import("std");
const Input = @import("Input.zig");
const PadBindings = @import("PadBindings.zig");
const Gamepads = @This();
pub const Sample = extern struct {
    lx: f32 = 0,
    ly: f32 = 0,
    rx: f32 = 0,
    ry: f32 = 0,
    lt: f32 = 0,
    rt: f32 = 0,
    buttons: u32 = 0,
    connected: u32 = 0,
    vendor: [48]u8 = @splat(0),
    product: [64]u8 = @splat(0),
};
/// `join` (Menu) joins or opens party setup; `respawn` (Select/Options) opens the player menu.
/// `up` / `down` / `left` / `right` are D-pad edges (menus, panels, market stalls); `fire` is
/// the right trigger, held; `alt` is the right bumper saber action, held.
/// `held` is the D-pad as held right now (up, down, left, right), for menu repeat.
pub const Command = struct { input: Input = .{}, connected: bool = false, join: bool = false, view: bool = false, interact: bool = false, respawn: bool = false, up: bool = false, down: bool = false, left: bool = false, right: bool = false, fire: bool = false, alt: bool = false, held: [4]bool = @splat(false) };
extern fn hw_gamepads(out: [*]Sample) void;
previous: [4]u32 = @splat(0),
button_edges: [4]u32 = @splat(0),
commands: [4]Command = @splat(.{}),
mapping: PadBindings.Mapping = .{},
samples: [4]Sample = @splat(.{}),
pub fn poll(self: *Gamepads) void {
    var samples: [4]Sample = @splat(.{});
    if (@import("builtin").os.tag == .macos) hw_gamepads(&samples);
    self.sample(samples);
}
fn stick(x: f32, y: f32, deadzone: f32) [2]f32 {
    const length = @sqrt(x * x + y * y);
    if (length <= deadzone or !std.math.isFinite(length)) return .{ 0, 0 };
    const amount = @min(1, (length - deadzone) / (1 - deadzone));
    return .{ x / length * amount, y / length * amount };
}
pub fn sample(self: *Gamepads, samples: [4]Sample) void {
    self.samples = samples;
    for (samples, 0..) |s, i| {
        var buttons = if (s.connected != 0) s.buttons else 0;
        if (s.connected != 0) {
            // Trigger switches follow the user threshold, not the platform's fixed pressed cutoff.
            buttons &= ~((@as(u32, 1) << 6) | (@as(u32, 1) << 7));
            if (s.lt > 0.001 and s.lt >= self.mapping.trigger_threshold) buttons |= 1 << 6;
            if (s.rt > 0.001 and s.rt >= self.mapping.trigger_threshold) buttons |= 1 << 7;
        }
        const edges = buttons & ~self.previous[i];
        self.previous[i] = buttons;
        self.button_edges[i] = edges;
        const raw: [4]f32 = if (s.connected != 0) .{ s.lx, s.ly, s.rx, s.ry } else @splat(0);
        const move = stick(self.mapping.axis(0, raw), self.mapping.axis(1, raw), self.mapping.deadzone);
        const look = stick(self.mapping.axis(2, raw), self.mapping.axis(3, raw), self.mapping.deadzone);
        const cmd = &self.commands[i];
        cmd.input.forward = move[1];
        cmd.input.right = move[0];
        cmd.input.look_x = look[0];
        cmd.input.look_y = -look[1];
        const down = self.mapping;
        cmd.input.jump = down.isDown(.jump, buttons);
        cmd.input.fast = down.isDown(.sprint, buttons);
        cmd.fire = down.isDown(.fire, buttons);
        cmd.alt = down.isDown(.alt, buttons);
        cmd.input.dodge_held = down.isDown(.dodge, buttons);
        cmd.input.mantle = down.isDown(.interact, buttons);
        cmd.input.jump_pressed = cmd.input.jump_pressed or down.isDown(.jump, edges);
        cmd.input.dodge = cmd.input.dodge or down.isDown(.dodge, edges);
        cmd.input.stomp = cmd.input.stomp or down.isDown(.stomp, edges);
        cmd.input.grapple = cmd.input.grapple or down.isDown(.grapple, edges);
        cmd.input.cycle_mode = cmd.input.cycle_mode or down.isDown(.traversal, edges);
        cmd.view = cmd.view or down.isDown(.view, edges);
        cmd.interact = cmd.interact or down.isDown(.interact, edges);
        cmd.join = cmd.join or down.isDown(.join, edges);
        cmd.respawn = cmd.respawn or down.isDown(.respawn, edges);
        cmd.held = .{ down.isDown(.up, buttons), down.isDown(.down, buttons), down.isDown(.left, buttons), down.isDown(.right, buttons) };
        cmd.up = cmd.up or down.isDown(.up, edges);
        cmd.down = cmd.down or down.isDown(.down, edges);
        cmd.left = cmd.left or down.isDown(.left, edges);
        cmd.right = cmd.right or down.isDown(.right, edges);
        cmd.connected = s.connected != 0;
        if (s.connected == 0) {
            cmd.* = .{};
            self.button_edges[i] = 0;
        }
    }
}

pub fn deviceLabel(self: *const Gamepads, index: usize, buffer: []u8) []const u8 {
    if (index >= self.samples.len) return "Unknown controller";
    const sample_ = &self.samples[index];
    const vendor = std.mem.sliceTo(&sample_.vendor, 0);
    const product = std.mem.sliceTo(&sample_.product, 0);
    if (vendor.len == 0 and product.len == 0) return "Unknown controller";
    if (vendor.len == 0) return product;
    if (product.len == 0) return vendor;
    return std.fmt.bufPrint(buffer, "{s} {s}", .{ vendor, product }) catch buffer;
}
pub fn consume(self: *Gamepads) void {
    for (&self.commands) |*c| {
        c.input.clearEdges();
        c.view = false;
        c.interact = false;
        c.join = false;
        c.respawn = false;
        c.up = false;
        c.down = false;
        c.left = false;
        c.right = false;
    }
}
/// Default controller order; the party menu can assign any controller to any player.
pub fn playerIndex(controller: usize) usize {
    return controller;
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
    try std.testing.expect(!pads.commands[1].input.jump and !pads.commands[1].connected);
    try std.testing.expectEqual(@as(usize, 1), playerIndex(1));
}

test "remapped gamepad actions and soft analog trigger reach the logical command" {
    var pads: Gamepads = .{};
    pads.mapping.buttons[@intFromEnum(PadBindings.Action.jump)] = 2;
    pads.mapping.buttons[@intFromEnum(PadBindings.Action.fire)] = 7;
    pads.mapping.trigger_threshold = 0.12;
    var samples: [4]Sample = @splat(.{});
    samples[0] = .{ .connected = 1, .buttons = 1 << 2, .rt = 0.13 };
    pads.sample(samples);
    try std.testing.expect(pads.commands[0].input.jump and pads.commands[0].input.jump_pressed);
    try std.testing.expect(pads.commands[0].fire);
    pads.mapping.axes = .{ 2, 3, 0, 1 };
    samples[0].lx = -1;
    samples[0].ry = 1;
    pads.sample(samples);
    try std.testing.expect(pads.commands[0].input.forward > 0.99);
    try std.testing.expect(pads.commands[0].input.look_x < -0.99);
}

test "the held D-pad is reported every poll for menu repeat, alongside its press edge" {
    var pads: Gamepads = .{};
    var samples: [4]Sample = @splat(.{});
    samples[0] = .{ .connected = 1, .buttons = 1 << 13 };
    pads.sample(samples);
    try std.testing.expect(pads.commands[0].down and pads.commands[0].held[1]);
    pads.consume();
    pads.sample(samples);
    // Still held, but no new press.
    try std.testing.expect(!pads.commands[0].down and pads.commands[0].held[1]);
    samples[0].buttons = 0;
    pads.sample(samples);
    try std.testing.expect(!pads.commands[0].held[1]);
}
