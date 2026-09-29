const std = @import("std");
const Device = @import("Device.zig");
const Node = @import("Node.zig").Node;
const Graph = @import("Graph.zig");
const Blueprint = @This();

/// JSON blueprint format. A blueprint is data only: static structure parts, typed devices,
/// wires between named ports ("device.port"), and for vehicles a chassis and wheels.
/// The optional `vehicle` section and the seat/motor/steering kinds were added without a
/// format bump: every earlier blueprint still parses with the same meaning. Parsing validates everything and produces a
/// fixed-capacity value with resolved indices, so instancing and simulation never allocate.
pub const format_version: u32 = 1;
pub const max_devices = 24;
pub const max_parts = 16;
pub const max_wires = 48;
pub const max_nodes = 64;
pub const name_len = 32;
pub const id_len = 16;

pub const Part = struct { offset: [3]f32, size: [3]f32, color: [4]f32 };
pub const PortRef = struct { device: u8, port: u8 };
pub const Wire = struct { from: PortRef, to: PortRef };
pub const max_wheels = 6;
pub const Wheel = struct { offset: [3]f32, radius: f32, rest: f32, driven: bool, steered: bool };
/// Chassis and suspension of a vehicle blueprint. Parts and devices are then chassis-relative.
pub const Vehicle = struct {
    size: [3]f32,
    mass: f32,
    stiffness: f32,
    damping: f32,
    grip: f32,
    max_force: f32,
    max_brake: f32,
    max_steer: f32,
    wheels: [max_wheels]Wheel,
    wheel_count: usize,
    seat: u8,
    motor: u8,
    steering: u8,
};
pub const DeviceDef = struct {
    id: [id_len]u8,
    kind: Device.Kind,
    /// Body or sensor-region center relative to the machine origin.
    offset: [3]f32,
    size: [3]f32,
    color: [4]f32,
    watts: f32,
    /// Actuators: meters per second along `travel`.
    speed: f32,
    travel: [3]f32,
    first_node: u16,
    node_count: u16,

    pub fn name(self: *const DeviceDef) []const u8 {
        return std.mem.sliceTo(&self.id, 0);
    }

    /// Generators, buttons, and actuators are physical; sensors and controllers are not.
    pub fn hasBody(self: DeviceDef) bool {
        return switch (self.kind) {
            .generator, .button, .actuator => true,
            .proximity, .latch, .logic, .seat, .motor, .steering => false,
        };
    }

    /// Rendered as a block at its offset.
    pub fn visible(self: DeviceDef) bool {
        return switch (self.kind) {
            .generator, .button, .actuator, .seat, .motor => true,
            .proximity, .latch, .logic, .steering => false,
        };
    }
};

name_buffer: [name_len]u8 = @splat(0),
parts: [max_parts]Part = undefined,
part_count: usize = 0,
devices: [max_devices]DeviceDef = undefined,
device_count: usize = 0,
wires: [max_wires]Wire = undefined,
wire_count: usize = 0,
nodes: [max_nodes]Node = undefined,
node_count: usize = 0,
vehicle: ?Vehicle = null,

pub fn name(self: *const Blueprint) []const u8 {
    return std.mem.sliceTo(&self.name_buffer, 0);
}

pub fn device(self: *const Blueprint, index: usize) *const DeviceDef {
    return &self.devices[index];
}

pub fn logicNodes(self: *const Blueprint, def: DeviceDef) []const Node {
    return self.nodes[def.first_node..][0..def.node_count];
}

pub fn findDevice(self: *const Blueprint, id: []const u8) ?u8 {
    for (self.devices[0..self.device_count], 0..) |*d, i| if (std.mem.eql(u8, d.name(), id)) return @intCast(i);
    return null;
}

const DocPart = struct { offset: [3]f32, size: [3]f32, color: [4]f32 = .{ 0.45, 0.47, 0.5, 1 } };
const DocDevice = struct {
    id: []const u8,
    kind: Device.Kind,
    offset: [3]f32 = .{ 0, 0, 0 },
    size: [3]f32 = .{ 0.4, 0.4, 0.4 },
    color: [4]f32 = .{ 0.6, 0.62, 0.65, 1 },
    watts: f32 = 0,
    speed: f32 = 0,
    travel: [3]f32 = .{ 0, 0, 0 },
    nodes: []const Node = &.{},
};
const DocVehicle = struct {
    size: [3]f32,
    mass: f32,
    stiffness: f32,
    damping: f32,
    grip: f32,
    max_force: f32,
    max_brake: f32,
    max_steer: f32,
    wheels: []const struct { offset: [3]f32, radius: f32, rest: f32, driven: bool = false, steered: bool = false },
};
const Doc = struct {
    format: u32,
    name: []const u8,
    parts: []const DocPart = &.{},
    devices: []const DocDevice,
    wires: []const [2][]const u8 = &.{},
    vehicle: ?DocVehicle = null,
};

pub const Error = error{
    InvalidJson,
    UnsupportedBlueprintFormat,
    InvalidName,
    TooManyParts,
    TooManyDevices,
    TooManyWires,
    TooManyNodes,
    DuplicateDevice,
    NonFiniteValue,
    InvalidSize,
    InvalidDeviceParameters,
    InvalidLogic,
    InvalidVehicle,
    UnknownPort,
    WrongDirection,
    PortKindMismatch,
    MultipleDrivers,
    OutOfMemory,
};

/// `allocator` is used only for temporary JSON parsing.
pub fn parse(allocator: std.mem.Allocator, json: []const u8) Error!Blueprint {
    const parsed = std.json.parseFromSlice(Doc, allocator, json, .{}) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidJson,
    };
    defer parsed.deinit();
    const doc = parsed.value;
    if (doc.format != format_version) return error.UnsupportedBlueprintFormat;
    var result: Blueprint = .{};
    if (doc.name.len == 0 or doc.name.len >= name_len) return error.InvalidName;
    @memcpy(result.name_buffer[0..doc.name.len], doc.name);

    if (doc.parts.len > max_parts) return error.TooManyParts;
    for (doc.parts, 0..) |p, i| {
        try finite(&(p.offset ++ p.size ++ p.color));
        try positive(p.size);
        result.parts[i] = .{ .offset = p.offset, .size = p.size, .color = p.color };
    }
    result.part_count = doc.parts.len;

    if (doc.devices.len == 0 or doc.devices.len > max_devices) return error.TooManyDevices;
    for (doc.devices, 0..) |d, i| {
        if (d.id.len == 0 or d.id.len >= id_len or std.mem.indexOfScalar(u8, d.id, '.') != null) return error.InvalidName;
        for (doc.devices[0..i]) |other| if (std.mem.eql(u8, other.id, d.id)) return error.DuplicateDevice;
        try finite(&(d.offset ++ d.size ++ d.color ++ d.travel ++ [_]f32{ d.watts, d.speed }));
        try positive(d.size);
        switch (d.kind) {
            .generator, .motor => if (!(d.watts > 0) or d.speed != 0 or length(d.travel) != 0) return error.InvalidDeviceParameters,
            .actuator => if (d.watts < 0 or !(d.speed > 0) or length(d.travel) == 0) return error.InvalidDeviceParameters,
            else => if (d.watts != 0 or d.speed != 0 or length(d.travel) != 0) return error.InvalidDeviceParameters,
        }
        if ((d.kind == .logic) != (d.nodes.len > 0)) return error.InvalidLogic;
        if (result.node_count + d.nodes.len > max_nodes) return error.TooManyNodes;
        Graph.validate(d.nodes) catch return error.InvalidLogic;
        @memcpy(result.nodes[result.node_count..][0..d.nodes.len], d.nodes);
        var def: DeviceDef = .{
            .id = @splat(0),
            .kind = d.kind,
            .offset = d.offset,
            .size = d.size,
            .color = d.color,
            .watts = d.watts,
            .speed = d.speed,
            .travel = d.travel,
            .first_node = @intCast(result.node_count),
            .node_count = @intCast(d.nodes.len),
        };
        @memcpy(def.id[0..d.id.len], d.id);
        result.devices[i] = def;
        result.node_count += d.nodes.len;
    }
    result.device_count = doc.devices.len;

    if (doc.wires.len > max_wires) return error.TooManyWires;
    for (doc.wires, 0..) |w, i| {
        const from = try result.resolve(w[0]);
        const to = try result.resolve(w[1]);
        const out = Device.ports(result.devices[from.device].kind)[from.port];
        const in = Device.ports(result.devices[to.device].kind)[to.port];
        if (out.direction != .output or in.direction != .input) return error.WrongDirection;
        if (out.kind != in.kind) return error.PortKindMismatch;
        // A signal input has exactly one driver; power inputs join a shared network.
        if (in.kind == .signal) for (result.wires[0..i]) |other| {
            if (other.to.device == to.device and other.to.port == to.port) return error.MultipleDrivers;
        };
        result.wires[i] = .{ .from = from, .to = to };
    }
    result.wire_count = doc.wires.len;
    try result.parseVehicle(doc.vehicle);
    return result;
}

/// A vehicle needs exactly one seat, motor, and steering device, and stationary kinds that
/// move bodies in world space (actuators, buttons, proximity) are not allowed on a chassis.
fn parseVehicle(self: *Blueprint, doc: ?DocVehicle) Error!void {
    var seat: ?u8 = null;
    var motor: ?u8 = null;
    var steering: ?u8 = null;
    for (self.devices[0..self.device_count], 0..) |d, i| {
        const slot = switch (d.kind) {
            .seat => &seat,
            .motor => &motor,
            .steering => &steering,
            .actuator, .button, .proximity => if (doc != null) return error.InvalidVehicle else continue,
            else => continue,
        };
        if (doc == null or slot.* != null) return error.InvalidVehicle;
        slot.* = @intCast(i);
    }
    const v = doc orelse return;
    try finite(&(v.size ++ [_]f32{ v.mass, v.stiffness, v.damping, v.grip, v.max_force, v.max_brake, v.max_steer }));
    try positive(v.size);
    if (!(v.mass > 0) or !(v.stiffness > 0) or v.damping < 0 or !(v.grip > 0) or !(v.max_force > 0) or v.max_brake < 0 or v.max_steer < 0 or v.max_steer > 1.2) return error.InvalidVehicle;
    if (v.wheels.len < 3 or v.wheels.len > max_wheels) return error.InvalidVehicle;
    var result: Vehicle = .{
        .size = v.size,
        .mass = v.mass,
        .stiffness = v.stiffness,
        .damping = v.damping,
        .grip = v.grip,
        .max_force = v.max_force,
        .max_brake = v.max_brake,
        .max_steer = v.max_steer,
        .wheels = undefined,
        .wheel_count = v.wheels.len,
        .seat = seat orelse return error.InvalidVehicle,
        .motor = motor orelse return error.InvalidVehicle,
        .steering = steering orelse return error.InvalidVehicle,
    };
    var driven = false;
    for (v.wheels, 0..) |w, i| {
        try finite(&(w.offset ++ [_]f32{ w.radius, w.rest }));
        if (!(w.radius > 0) or !(w.rest > 0)) return error.InvalidVehicle;
        driven = driven or w.driven;
        result.wheels[i] = .{ .offset = w.offset, .radius = w.radius, .rest = w.rest, .driven = w.driven, .steered = w.steered };
    }
    if (!driven) return error.InvalidVehicle;
    self.vehicle = result;
}

fn resolve(self: *const Blueprint, text: []const u8) Error!PortRef {
    const dot = std.mem.indexOfScalar(u8, text, '.') orelse return error.UnknownPort;
    const index = self.findDevice(text[0..dot]) orelse return error.UnknownPort;
    const port = Device.portIndex(self.devices[index].kind, text[dot + 1 ..]) orelse return error.UnknownPort;
    return .{ .device = index, .port = port };
}

fn finite(values: []const f32) Error!void {
    for (values) |v| if (!std.math.isFinite(v) or @abs(v) > 1e4) return error.NonFiniteValue;
}

fn positive(size: [3]f32) Error!void {
    for (size) |v| if (!(v > 0)) return error.InvalidSize;
}

pub fn length(v: [3]f32) f32 {
    return @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

const door_json =
    \\{"format":1,"name":"test_door","devices":[
    \\ {"id":"gen","kind":"generator","watts":100},
    \\ {"id":"button","kind":"button"},
    \\ {"id":"toggle","kind":"latch"},
    \\ {"id":"door","kind":"actuator","size":[2,2,0.2],"travel":[2,0,0],"speed":1,"watts":50}],
    \\ "wires":[["gen.power","door.power"],["button.pressed","toggle.toggle"],["toggle.state","door.target"]]}
;

test "blueprint parses, resolves wires, and rejects invalid machines" {
    const allocator = std.testing.allocator;
    const bp = try parse(allocator, door_json);
    try std.testing.expectEqualStrings("test_door", bp.name());
    try std.testing.expectEqual(@as(usize, 3), bp.wire_count);
    try std.testing.expectEqual(PortRef{ .device = 3, .port = 1 }, bp.wires[2].to);

    const cases = [_]struct { from: []const u8, to: []const u8, err: Error }{
        .{ .from = "\"format\":1", .to = "\"format\":2", .err = error.UnsupportedBlueprintFormat },
        .{ .from = "[\"toggle.state\",\"door.target\"]", .to = "[\"door.target\",\"toggle.state\"]", .err = error.WrongDirection },
        .{ .from = "[\"toggle.state\",\"door.target\"]", .to = "[\"gen.power\",\"door.target\"]", .err = error.PortKindMismatch },
        .{ .from = "[\"toggle.state\",\"door.target\"]", .to = "[\"toggle.state\",\"door.target\"],[\"button.pressed\",\"door.target\"]", .err = error.MultipleDrivers },
        .{ .from = "\"button.pressed\"", .to = "\"button.clicked\"", .err = error.UnknownPort },
        .{ .from = "\"id\":\"toggle\"", .to = "\"id\":\"button\"", .err = error.DuplicateDevice },
        .{ .from = "\"watts\":100", .to = "\"watts\":0", .err = error.InvalidDeviceParameters },
        .{ .from = "\"size\":[2,2,0.2]", .to = "\"size\":[2,0,0.2]", .err = error.InvalidSize },
        .{ .from = "\"kind\":\"latch\"", .to = "\"kind\":\"logic\"", .err = error.InvalidLogic },
        .{ .from = "\"devices\"", .to = "\"devicez\"", .err = error.InvalidJson },
    };
    for (cases) |case| {
        const broken = try std.mem.replaceOwned(u8, allocator, door_json, case.from, case.to);
        defer allocator.free(broken);
        try std.testing.expectError(case.err, parse(allocator, broken));
    }
    const cyclic = try std.mem.replaceOwned(u8, allocator, door_json, "{\"id\":\"toggle\",\"kind\":\"latch\"}", "{\"id\":\"toggle\",\"kind\":\"logic\",\"nodes\":[{\"add\":{\"a\":0,\"b\":0}}]}");
    defer allocator.free(cyclic);
    try std.testing.expectError(error.InvalidLogic, parse(allocator, cyclic));
}

const cart_json =
    \\{"format":1,"name":"cart","devices":[
    \\ {"id":"cell","kind":"generator","watts":100},
    \\ {"id":"seat","kind":"seat"},
    \\ {"id":"motor","kind":"motor","watts":80},
    \\ {"id":"wheel","kind":"steering"}],
    \\ "wires":[["cell.power","motor.power"],["seat.throttle","motor.throttle"],["seat.steer","wheel.command"]],
    \\ "vehicle":{"size":[2,1,3],"mass":300,"stiffness":8000,"damping":1000,"grip":1,"max_force":3000,"max_brake":2000,"max_steer":0.5,
    \\  "wheels":[{"offset":[-1,-0.5,1],"radius":0.4,"rest":0.4,"driven":true,"steered":true},{"offset":[1,-0.5,1],"radius":0.4,"rest":0.4,"steered":true},{"offset":[0,-0.5,-1],"radius":0.4,"rest":0.4,"driven":true}]}}
;

test "vehicle blueprints resolve their seat, motor, and steering and reject invalid chassis" {
    const allocator = std.testing.allocator;
    const cart = try parse(allocator, cart_json);
    const v = cart.vehicle.?;
    try std.testing.expectEqual(@as(u8, 1), v.seat);
    try std.testing.expectEqual(@as(u8, 3), v.steering);
    try std.testing.expectEqual(@as(usize, 3), v.wheel_count);
    try std.testing.expect(v.wheels[0].driven and !v.wheels[1].driven);

    const cases = [_]struct { from: []const u8, to: []const u8 }{
        .{ .from = "{\"id\":\"wheel\",\"kind\":\"steering\"}", .to = "{\"id\":\"wheel\",\"kind\":\"steering\"},{\"id\":\"b\",\"kind\":\"button\"}" },
        .{ .from = "\"driven\":true", .to = "\"driven\":false" },
        .{ .from = "\"max_steer\":0.5", .to = "\"max_steer\":2" },
        .{ .from = "\"mass\":300", .to = "\"mass\":0" },
    };
    for (cases) |case| {
        const broken = try std.mem.replaceOwned(u8, allocator, cart_json, case.from, case.to);
        defer allocator.free(broken);
        try std.testing.expectError(error.InvalidVehicle, parse(allocator, broken));
    }
    // Driving components without a vehicle section are rejected.
    const seat_only = try std.mem.replaceOwned(u8, allocator, door_json, "{\"id\":\"toggle\",\"kind\":\"latch\"}", "{\"id\":\"toggle\",\"kind\":\"latch\"},{\"id\":\"s\",\"kind\":\"seat\"}");
    defer allocator.free(seat_only);
    try std.testing.expectError(error.InvalidVehicle, parse(allocator, seat_only));
}
