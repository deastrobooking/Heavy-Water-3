const mach = @import("mach");
const Input = @This();
forward: f32 = 0,
right: f32 = 0,
up: f32 = 0,
fast: bool = false,
look_x: f32 = 0,
look_y: f32 = 0,

pub fn sample(self: *Input, core: *mach.Core) void {
    self.forward = axis(core, .w, .s);
    self.right = axis(core, .d, .a);
    self.up = axis(core, .e, .q);
    self.fast = core.keyPressed(.left_shift) or core.keyPressed(.right_shift);
}

fn axis(core: *mach.Core, positive: mach.Core.KeyButtonID, negative: mach.Core.KeyButtonID) f32 {
    return @as(f32, @floatFromInt(@intFromBool(core.keyPressed(positive)))) - @as(f32, @floatFromInt(@intFromBool(core.keyPressed(negative))));
}
