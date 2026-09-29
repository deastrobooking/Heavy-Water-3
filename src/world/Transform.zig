/// Initial renderer supports translation and positive uniform scale.
/// Rotation and non-uniform scale require a corresponding normal transform.
const Transform = @This();
position: [3]f32 = .{ 0, 0, 0 },
scale: f32 = 1,

pub fn toInstance(self: Transform) [4]f32 {
    return .{ self.position[0], self.position[1], self.position[2], self.scale };
}
