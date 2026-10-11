const builtin = @import("builtin");
const std = @import("std");

pub const Field = struct { name: []const u8, type: type };
pub const FnParam = struct { type: ?type };

pub const ParamAttributes = if (builtin.zig_version.minor >= 17)
    std.builtin.Type.Fn.ParamAttributes
else
    std.builtin.Type.Fn.Param.Attributes;

pub const StructFieldAttributes = if (builtin.zig_version.minor >= 17)
    std.builtin.Type.Struct.FieldAttributes
else
    std.builtin.Type.StructField.Attributes;

pub fn structFieldCount(comptime T: type) usize {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len;
}

pub fn structFieldName(comptime T: type, comptime index: usize) []const u8 {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.field_names[index] else info.fields[index].name;
}

pub fn structFieldType(comptime T: type, comptime index: usize) type {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.field_types[index] else info.fields[index].type;
}

pub fn enumFieldCount(comptime T: type) usize {
    const info = @typeInfo(T).@"enum";
    return if (builtin.zig_version.minor >= 17) info.field_names.len else info.fields.len;
}

pub fn fnParamCount(comptime Fn: type) usize {
    const info = @typeInfo(Fn).@"fn";
    return if (builtin.zig_version.minor >= 17) info.param_types.len else info.params.len;
}

/// A function type's parameters as an array, indexable the way `Type.Fn.params` was before 0.17.
pub fn fnParams(comptime Fn: type) [fnParamCount(Fn)]FnParam {
    var out: [fnParamCount(Fn)]FnParam = undefined;
    for (&out, 0..) |*p, i| p.* = fnParam(Fn, i);
    return out;
}

pub fn fnParam(comptime Fn: type, comptime index: usize) FnParam {
    const info = @typeInfo(Fn).@"fn";
    return .{ .type = if (builtin.zig_version.minor >= 17) info.param_types[index] else info.params[index].type };
}

pub fn fnCallConv(comptime Fn: type) std.builtin.CallingConvention {
    const info = @typeInfo(Fn).@"fn";
    return if (builtin.zig_version.minor >= 17) info.attrs.@"callconv" else info.calling_convention;
}

pub fn declCount(comptime T: type) usize {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.decl_names.len else info.decls.len;
}

pub fn declName(comptime T: type, comptime index: usize) []const u8 {
    const info = @typeInfo(T).@"struct";
    return if (builtin.zig_version.minor >= 17) info.decl_names[index] else info.decls[index].name;
}

/// Declaration names of a struct (a namespace of methods), in order.
pub fn declNames(comptime T: type) [declCount(T)][]const u8 {
    var out: [declCount(T)][]const u8 = undefined;
    for (&out, 0..) |*name, i| name.* = declName(T, i);
    return out;
}
