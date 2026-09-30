/// Linear RGB tint. The opaque shader uses alpha = 1 + emission (0..1), not opacity.
pub const terrain: [4]f32 = .{ 0.22, 0.43, 0.40, 1 };
pub const relic: [4]f32 = .{ 0.34, 0.68, 0.74, 1 };
pub const accent: [4]f32 = .{ 0.92, 0.52, 0.20, 1 };

/// Pack emission into the instance material channel; ordinary surfaces keep alpha 1.
pub fn emissive(tint: [4]f32, strength: f32) [4]f32 {
    return .{ tint[0], tint[1], tint[2], 1 + @min(1, @max(0, strength)) };
}
