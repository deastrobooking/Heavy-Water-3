const std = @import("std");

/// Device kinds shared by every machine. Sensors produce signals, controllers transform them,
/// actuators consume power and signals, and generators feed power networks.
/// `seat`, `motor`, and `steering` exist only in vehicle blueprints.
pub const Kind = enum { generator, sap_tap, button, proximity, latch, logic, actuator, seat, motor, steering, lamp, transmitter, receiver };
/// Channels of the world signal bus shared by transmitters and receivers on any machine.
pub const max_channels = 64;
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
        .generator, .sap_tap => &.{
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
        // Driver controls while occupied; all zero when empty.
        .seat => &.{
            .{ .name = "occupied", .kind = .signal, .direction = .output },
            .{ .name = "throttle", .kind = .signal, .direction = .output },
            .{ .name = "steer", .kind = .signal, .direction = .output },
            .{ .name = "brake", .kind = .signal, .direction = .output },
        },
        // Draws watts × |throttle|; `drive` is throttle scaled by power satisfaction.
        .motor => &.{
            .{ .name = "power", .kind = .power, .direction = .input },
            .{ .name = "throttle", .kind = .signal, .direction = .input },
            .{ .name = "drive", .kind = .signal, .direction = .output },
        },
        // Draws watts while `on`; `lit` is the supplied fraction (0..1), exposing brownouts.
        .lamp => &.{
            .{ .name = "power", .kind = .power, .direction = .input },
            .{ .name = "on", .kind = .signal, .direction = .input },
            .{ .name = "lit", .kind = .signal, .direction = .output },
        },
        // Publishes its input on its channel; receivers anywhere read it one step later.
        .transmitter => &.{.{ .name = "in", .kind = .signal, .direction = .input }},
        .receiver => &.{.{ .name = "out", .kind = .signal, .direction = .output }},
        // Clamps the steering command to −1..1; the vehicle reads `angle`.
        .steering => &.{
            .{ .name = "command", .kind = .signal, .direction = .input },
            .{ .name = "angle", .kind = .signal, .direction = .output },
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
    // Port names are unique within a kind, so "device.port" is unambiguous.
    inline for (std.meta.fields(Kind)) |field| {
        const list = ports(@enumFromInt(field.value));
        for (list, 0..) |a, i| for (list[0..i]) |b| try std.testing.expect(!std.mem.eql(u8, a.name, b.name));
    }
}
