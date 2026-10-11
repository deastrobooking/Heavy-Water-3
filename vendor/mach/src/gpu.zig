const m = @import("math/main.zig");

/// GPU-compatible data types backed by plain arrays rather than @Vector SIMD types.
//
/// @Vector does not have a guaranteed byte layout, so these types must be used
/// for any data uploaded to the GPU (uniforms, storage buffers, vertex data, etc.)
pub fn Vec2T(comptime Scalar: type) type {
    return extern struct {
        v: [2]Scalar,

        pub inline fn init(xs: Scalar, ys: Scalar) @This() {
            return .{ .v = .{ xs, ys } };
        }

        pub inline fn math(v: @This()) m.Vec2 {
            return .{ .v = @as(@Vector(2, Scalar), v.v) };
        }
    };
}

pub fn Vec3T(comptime Scalar: type) type {
    return extern struct {
        v: [3]Scalar,

        pub inline fn init(xs: Scalar, ys: Scalar, zs: Scalar) @This() {
            return .{ .v = .{ xs, ys, zs } };
        }

        pub inline fn math(v: @This()) m.Vec3 {
            return .{ .v = @as(@Vector(3, Scalar), v.v) };
        }
    };
}

pub fn Vec4T(comptime Scalar: type) type {
    return extern struct {
        v: [4]Scalar,

        pub inline fn init(xs: Scalar, ys: Scalar, zs: Scalar, ws: Scalar) @This() {
            return .{ .v = .{ xs, ys, zs, ws } };
        }

        pub inline fn math(v: @This()) m.Vec4 {
            return .{ .v = @as(@Vector(4, Scalar), v.v) };
        }
    };
}

pub fn Mat3x3T(comptime Scalar: type) type {
    const Vec = Vec3T(Scalar);

    return extern struct {
        v: [3]Vec,

        pub inline fn init(r0: *const Vec, r1: *const Vec, r2: *const Vec) @This() {
            return .{ .v = .{
                Vec.init(r0.v[0], r1.v[0], r2.v[0]),
                Vec.init(r0.v[1], r1.v[1], r2.v[1]),
                Vec.init(r0.v[2], r1.v[2], r2.v[2]),
            } };
        }

        pub inline fn math(v: @This()) m.Mat3x3 {
            return .{ .v = .{
                v.v[0].math(),
                v.v[1].math(),
                v.v[2].math(),
            } };
        }
    };
}

pub fn Mat4x4T(comptime Scalar: type) type {
    const Vec = Vec4T(Scalar);

    return extern struct {
        v: [4]Vec,

        pub inline fn init(r0: *const Vec, r1: *const Vec, r2: *const Vec, r3: *const Vec) @This() {
            return .{ .v = .{
                Vec.init(r0.v[0], r1.v[0], r2.v[0], r3.v[0]),
                Vec.init(r0.v[1], r1.v[1], r2.v[1], r3.v[1]),
                Vec.init(r0.v[2], r1.v[2], r2.v[2], r3.v[2]),
                Vec.init(r0.v[3], r1.v[3], r2.v[3], r3.v[3]),
            } };
        }

        pub inline fn math(v: @This()) m.Mat4x4 {
            return .{ .v = .{
                v.v[0].math(),
                v.v[1].math(),
                v.v[2].math(),
                v.v[3].math(),
            } };
        }
    };
}

/// Standard f32 precision GPU types
pub const Vec2 = Vec2T(f32);
pub const Vec3 = Vec3T(f32);
pub const Vec4 = Vec4T(f32);
pub const Mat3x3 = Mat3x3T(f32);
pub const Mat4x4 = Mat4x4T(f32);

/// Standard f32 precision initializers
pub const vec2 = Vec2.init;
pub const vec3 = Vec3.init;
pub const vec4 = Vec4.init;
pub const mat3x3 = Mat3x3.init;
pub const mat4x4 = Mat4x4.init;
