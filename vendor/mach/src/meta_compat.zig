const builtin = @import("builtin");
const std = @import("std");

pub const Field = struct {
    name: []const u8,
    type: type = void,
    value: comptime_int = 0,
};

pub fn fieldCount(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len,
        .@"union" => |info| if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len,
        .@"enum" => |info| if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len,
        else => @compileError("expected a struct, union, or enum"),
    };
}

pub fn fields(comptime T: type) [fieldCount(T)]Field {
    const info = @typeInfo(T);
    var result: [fieldCount(T)]Field = undefined;
    inline for (0..fieldCount(T)) |i| {
        result[i] = switch (info) {
            .@"struct" => |fields_info| .{
                .name = if (builtin.zig_version.minor >= 17) fields_info.field_names[i] else fields_info.fields[i].name,
                .type = if (builtin.zig_version.minor >= 17) fields_info.field_types[i] else fields_info.fields[i].type,
            },
            .@"union" => |fields_info| .{
                .name = if (builtin.zig_version.minor >= 17) fields_info.field_names[i] else fields_info.fields[i].name,
                .type = if (builtin.zig_version.minor >= 17) fields_info.field_types[i] else fields_info.fields[i].type,
            },
            .@"enum" => |fields_info| .{
                .name = if (builtin.zig_version.minor >= 17) fields_info.field_names[i] else fields_info.fields[i].name,
                .value = if (builtin.zig_version.minor >= 17) fields_info.field_values[i] else fields_info.fields[i].value,
            },
            else => unreachable,
        };
    }
    return result;
}

/// Integer-type constructor across Zig's std.meta.Int to @Int transition.
pub fn Int(comptime signedness: anytype, comptime bits: u16) type {
    return if (builtin.zig_version.minor >= 17)
        @Int(signedness, bits)
    else
        std.meta.Int(signedness, bits);
}

/// Whether this is a Debug build. Zig 0.17 renamed the optimize modes to lowercase.
pub const is_debug = if (builtin.zig_version.minor >= 17) builtin.mode == .debug else builtin.mode == .Debug;
