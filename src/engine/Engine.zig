const Time = @import("Time.zig");
const Input = @import("Input.zig");
const Camera = @import("../world/Camera.zig");
const Engine = @This();
time: Time = .{},
input: Input = .{},
camera: Camera = .{},

/// Applies accumulated look input once per frame and returns how many fixed steps to simulate.
pub fn advance(self: *Engine, elapsed: f32) u32 {
    self.camera.look(self.input.look_x, self.input.look_y);
    self.input.look_x = 0;
    self.input.look_y = 0;
    return self.time.advance(elapsed);
}
