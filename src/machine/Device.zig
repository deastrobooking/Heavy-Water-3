const std = @import("std");

/// Device kinds shared by every machine. Sensors produce signals, controllers transform them,
/// actuators consume power and signals, and generators feed power networks.
pub const Kind = enum { generator, button, proximity, latch, logic, actuator };
pub const PortKind = enum { power, signal };
pub const Direction = enum { input, output };
pub const Port = struct {
    name: []const u8,
    kind: PortKind,
    direction: Direction,
    /// Value read by an unconnected signal input.
    default: f32 = 0,
};
pub const max_ports = 5;

/// Fixed port table per kind; a port's index in this table is its stable address.
pub fn ports(kind: Kind) []const Port {
    return switch (kind) {
        .generator => &.{
            .{ .name = "power", .kind = .power, .direction = .output },
            .{ .name = "enable", .kind = .signal, .direction = .input, .default = 1 },
        },
        .button => &.{.{ .name = "pressed", .kind = .signal, .direction = .output }},
        .proximity => &.{.{ .name = "present", .kind = .signal, .direction = .output }},
        .latch => &.{
            .{ .name = "toggle", .kind = .signal, .direction = .input },
            .{ .name = "state", .kind = .signal, .direction = .output },
        },
        .logic => &.{
            .{ .name = "a", .kind = .signal, .direction = .input },
            .{ .name = "b", .kind = .signal, .direction = .input },
            .{ .name = "c", .kind = .signal, .direction = .input },
            .{ .name = "d", .kind = .signal, .direction = .input },
            .{ .name = "out", .kind = .signal, .direction = .output },
        },
        .actuator => &.{
            .{ .name = "power", .kind = .power, .direction = .input },
            .{ .name = "target", .kind = .signal, .direction = .input },
            .{ .name = "position", .kind = .signal, .direction = .output },
        },
    };
}

pub fn portIndex(kind: Kind, name: []const u8) ?u8 {
    for (ports(kind), 0..) |port, i| if (std.mem.eql(u8, port.name, name)) return @intCast(i);
    return null;
}

/// Index of the device's single power port, if it has one.
pub fn powerPort(kind: Kind) ?u8 {
    for (ports(kind), 0..) |port, i| if (port.kind == .power) return @intCast(i);
    return null;
}

test "port tables fit the fixed capacity and have at most one power port" {
    inline for (std.meta.fields(Kind)) |field| {
        const kind: Kind = @enumFromInt(field.value);
        try std.testing.expect(ports(kind).len <= max_ports);
        var power: usize = 0;
        for (ports(kind)) |port| power += @intFromBool(port.kind == .power);
        try std.testing.expect(power <= 1);
    }
    try std.testing.expectEqual(@as(?u8, 1), portIndex(.actuator, "target"));
    try std.testing.expectEqual(@as(?u8, null), portIndex(.button, "power"));
}
