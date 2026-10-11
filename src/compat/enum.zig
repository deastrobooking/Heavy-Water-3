const builtin = @import("builtin");

pub const Field = struct {
    name: []const u8,
    value: usize,
};

pub const StructField = struct {
    name: []const u8,
    type: type,
};

/// Return enum field names and values across the Zig 0.16/0.17 type-info layouts.
pub fn fields(comptime T: type) [fieldCount(T)]Field {
    const info = @typeInfo(T).@"enum";
    return comptime blk: {
        var result: [fieldCount(T)]Field = undefined;
        if (builtin.zig_version.minor >= 17) {
            for (info.field_names, info.field_values, 0..) |name, value, i| {
                result[i] = .{ .name = name, .value = @intCast(value) };
            }
        } else {
            for (info.fields, 0..) |field, i| {
                result[i] = .{ .name = field.name, .value = @intCast(field.value) };
            }
        }
        break :blk result;
    };
}

/// Return struct field names and types across the Zig 0.16/0.17 type-info layouts.
pub fn structFields(comptime T: type) [structFieldCount(T)]StructField {
    const info = @typeInfo(T).@"struct";
    return comptime blk: {
        var result: [structFieldCount(T)]StructField = undefined;
        if (builtin.zig_version.minor >= 17) {
            for (info.field_names, info.field_types, 0..) |name, field_type, i| {
                result[i] = .{ .name = name, .type = field_type };
            }
        } else {
            for (info.fields, 0..) |field, i| {
                result[i] = .{ .name = field.name, .type = field.type };
            }
        }
        break :blk result;
    };
}

fn fieldCount(comptime T: type) usize {
    const info = @typeInfo(T).@"enum";
    return if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len;
}

fn structFieldCount(comptime T: type) usize {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len;
}
