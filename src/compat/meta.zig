const builtin = @import("builtin");
const std = @import("std");

/// Integer-type constructor across Zig's std.meta.Int to @Int transition.
pub fn Int(comptime signedness: anytype, comptime bits: u16) type {
    return if (builtin.zig_version.minor >= 17)
        @Int(signedness, bits)
    else
        std.meta.Int(signedness, bits);
}
