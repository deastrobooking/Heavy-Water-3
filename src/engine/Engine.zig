const Time = @import("Time.zig");
const Input = @import("Input.zig");
const Camera = @import("../world/Camera.zig");
const Engine = @This();
time: Time = .{},
input: Input = .{},
camera: Camera = .{},

pub fn update(self: *Engine, elapsed: f32) void {
    self.camera.look(self.input.look_x, self.input.look_y);
    self.input.look_x = 0;
    self.input.look_y = 0;
    const steps = self.time.advance(elapsed);
    for (0..steps) |_| self.camera.move(self.input, Time.fixed_dt);
}
