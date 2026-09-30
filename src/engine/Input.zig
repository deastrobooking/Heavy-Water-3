const mach = @import("mach");
const Input = @This();
forward: f32 = 0,
right: f32 = 0,
up: f32 = 0,
fast: bool = false,
jump: bool = false,
jump_pressed: bool = false,
dodge: bool = false,
dodge_held: bool = false,
stomp: bool = false,
grapple: bool = false,
mantle: bool = false,
cycle_mode: bool = false,
look_x: f32 = 0,
look_y: f32 = 0,

pub fn sample(self: *Input, core: *mach.Core) void {
    self.forward = axis(core, .w, .s);
    self.right = axis(core, .d, .a);
    self.up = axis(core, .e, .q);
    self.fast = core.keyPressed(.left_shift) or core.keyPressed(.right_shift);
    self.jump = core.keyPressed(.space);
    self.dodge_held = core.keyPressed(.left_control);
    self.mantle = core.keyPressed(.f);
}

fn axis(core: *mach.Core, positive: mach.Core.KeyButtonID, negative: mach.Core.KeyButtonID) f32 {
    return @as(f32, @floatFromInt(@intFromBool(core.keyPressed(positive)))) - @as(f32, @floatFromInt(@intFromBool(core.keyPressed(negative))));
}

/// Edges remain latched across frames with no simulation step, then are consumed once.
pub fn clearEdges(self: *Input) void {
    self.jump_pressed = false;
    self.dodge = false;
    self.stomp = false;
    self.grapple = false;
    self.cycle_mode = false;
}
