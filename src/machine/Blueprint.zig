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
    /// Explicit `"body": true` gives any device a pickable static body (workshop kits).
    body: bool = false,
    /// Bus channel (1..max_channels) for transmitters, receivers, and Rootsong devices; 0 otherwise.
    channel: u16 = 0,

    pub fn name(self: *const DeviceDef) []const u8 {
        return std.mem.sliceTo(&self.id, 0);
    }

    /// Generators, buttons, actuators, and lamps are physical by default; sensors and
    /// controllers only when the blueprint asks.
    pub fn hasBody(self: DeviceDef) bool {
        return self.body or switch (self.kind) {
            .generator, .sap_tap, .button, .actuator, .lamp, .transmitter, .receiver, .root_sender, .root_listener, .plate => true,
            .proximity, .latch, .logic, .seat, .motor, .steering => false,
        };
    }

    /// Rendered as a block at its offset.
    pub fn visible(self: DeviceDef) bool {
        return self.body or switch (self.kind) {
            .generator, .sap_tap, .button, .actuator, .seat, .motor, .lamp, .transmitter, .receiver, .root_sender, .root_listener, .plate => true,
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

pub const DocPart = struct { offset: [3]f32, size: [3]f32, color: [4]f32 = .{ 0.45, 0.47, 0.5, 1 } };
pub const DocDevice = struct {
    id: []const u8,
    kind: Device.Kind,
    offset: [3]f32 = .{ 0, 0, 0 },
    size: [3]f32 = .{ 0.4, 0.4, 0.4 },
    color: [4]f32 = .{ 0.6, 0.62, 0.65, 1 },
    watts: f32 = 0,
    speed: f32 = 0,
    travel: [3]f32 = .{ 0, 0, 0 },
    nodes: []const Node = &.{},
    body: bool = false,
    channel: u16 = 0,
};
pub const DocWheel = struct { offset: [3]f32, radius: f32, rest: f32, driven: bool = false, steered: bool = false };
pub const DocVehicle = struct {
    size: [3]f32,
    mass: f32,
    stiffness: f32,
    damping: f32,
    grip: f32,
    max_force: f32,
    max_brake: f32,
    max_steer: f32,
    wheels: []const DocWheel,
};
/// The JSON document shape. Saves embed it to persist placed and rewired machines.
pub const Doc = struct {
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
    DifferentMachines,
    NoSuchWire,
    OutOfMemory,
};

/// `allocator` is used only for temporary JSON parsing.
pub fn parse(allocator: std.mem.Allocator, json: []const u8) Error!Blueprint {
    const parsed = std.json.parseFromSlice(Doc, allocator, json, .{}) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidJson,
    };
    defer parsed.deinit();
    return fromDoc(parsed.value);
}

/// Validates a parsed document. Runtime edits go through the same `addDevice` and `connect`.
pub fn fromDoc(doc: Doc) Error!Blueprint {
    if (doc.format != format_version) return error.UnsupportedBlueprintFormat;
    var result: Blueprint = .{};
    try result.setName(doc.name);
    if (doc.parts.len > max_parts) return error.TooManyParts;
    for (doc.parts, 0..) |p, i| {
        try finite(&(p.offset ++ p.size ++ p.color));
        try positive(p.size);
        result.parts[i] = .{ .offset = p.offset, .size = p.size, .color = p.color };
    }
    result.part_count = doc.parts.len;
    if (doc.devices.len == 0) return error.TooManyDevices;
    for (doc.devices) |d| _ = try result.addDeviceChecked(d, doc.vehicle != null);
    if (doc.wires.len > max_wires) return error.TooManyWires;
    for (doc.wires) |w| try result.connect(try result.resolve(w[0]), try result.resolve(w[1]));
    try result.parseVehicle(doc.vehicle);
    return result;
}

pub fn setName(self: *Blueprint, text: []const u8) Error!void {
    if (text.len == 0 or text.len >= name_len) return error.InvalidName;
    self.name_buffer = @splat(0);
    @memcpy(self.name_buffer[0..text.len], text);
}

/// Appends a validated device; vehicle-only kinds are rejected outside vehicles and
/// stationary actuating kinds inside them.
pub fn addDevice(self: *Blueprint, d: DocDevice) Error!u8 {
    return self.addDeviceChecked(d, self.vehicle != null);
}

fn addDeviceChecked(self: *Blueprint, d: DocDevice, vehicle: bool) Error!u8 {
    if (self.device_count == max_devices) return error.TooManyDevices;
    if (d.id.len == 0 or d.id.len >= id_len or std.mem.indexOfScalar(u8, d.id, '.') != null) return error.InvalidName;
    if (self.findDevice(d.id) != null) return error.DuplicateDevice;
    try finite(&(d.offset ++ d.size ++ d.color ++ d.travel ++ [_]f32{ d.watts, d.speed }));
    try positive(d.size);
    switch (d.kind) {
        .generator, .sap_tap, .motor, .lamp => if (!(d.watts > 0) or d.speed != 0 or length(d.travel) != 0) return error.InvalidDeviceParameters,
        .actuator => if (d.watts < 0 or !(d.speed > 0) or length(d.travel) == 0) return error.InvalidDeviceParameters,
        else => if (d.watts != 0 or d.speed != 0 or length(d.travel) != 0) return error.InvalidDeviceParameters,
    }
    switch (d.kind) {
        .seat, .motor, .steering => if (!vehicle) return error.InvalidVehicle,
        .actuator, .button, .proximity, .plate => if (vehicle) return error.InvalidVehicle,
        else => {},
    }
    const bus = switch (d.kind) {
        .transmitter, .receiver, .root_sender, .root_listener => true,
        else => false,
    };
    if (if (bus) d.channel == 0 or d.channel > Device.max_channels else d.channel != 0) return error.InvalidDeviceParameters;
    if ((d.kind == .logic) != (d.nodes.len > 0)) return error.InvalidLogic;
    if (self.node_count + d.nodes.len > max_nodes) return error.TooManyNodes;
    Graph.validate(d.nodes) catch return error.InvalidLogic;
    @memcpy(self.nodes[self.node_count..][0..d.nodes.len], d.nodes);
    var def: DeviceDef = .{
        .id = @splat(0),
        .kind = d.kind,
        .offset = d.offset,
        .size = d.size,
        .color = d.color,
        .watts = d.watts,
        .speed = d.speed,
        .travel = d.travel,
        .first_node = @intCast(self.node_count),
        .node_count = @intCast(d.nodes.len),
        .body = d.body,
        .channel = d.channel,
    };
    @memcpy(def.id[0..d.id.len], d.id);
    self.devices[self.device_count] = def;
    self.node_count += d.nodes.len;
    self.device_count += 1;
    return @intCast(self.device_count - 1);
}

/// Adds a wire after the same checks the file format gets: output to input, matching port
/// kinds, and at most one driver per signal input.
pub fn connect(self: *Blueprint, from: PortRef, to: PortRef) Error!void {
    if (from.device >= self.device_count or to.device >= self.device_count) return error.UnknownPort;
    const out_ports = Device.ports(self.devices[from.device].kind);
    const in_ports = Device.ports(self.devices[to.device].kind);
    if (from.port >= out_ports.len or to.port >= in_ports.len) return error.UnknownPort;
    const out = out_ports[from.port];
    const in = in_ports[to.port];
    if (out.direction != .output or in.direction != .input) return error.WrongDirection;
    if (out.kind != in.kind) return error.PortKindMismatch;
    if (in.kind == .signal and self.driverOf(to) != null) return error.MultipleDrivers;
    if (self.wire_count == max_wires) return error.TooManyWires;
    self.wires[self.wire_count] = .{ .from = from, .to = to };
    self.wire_count += 1;
}

pub fn driverOf(self: *const Blueprint, to: PortRef) ?usize {
    for (self.wires[0..self.wire_count], 0..) |w, i| if (w.to.device == to.device and w.to.port == to.port) return i;
    return null;
}

/// Removes every wire into `device`; returns how many.
pub fn disconnectInputs(self: *Blueprint, device_index: u8) usize {
    var kept: usize = 0;
    for (self.wires[0..self.wire_count]) |w| {
        if (w.to.device == device_index) continue;
        self.wires[kept] = w;
        kept += 1;
    }
    defer self.wire_count = kept;
    return self.wire_count - kept;
}

/// Removes a device, its wires, and its logic nodes; later device indices shift down by one.
/// Vehicles keep their fixed component set.
pub fn removeDevice(self: *Blueprint, index: u8) Error!void {
    if (index >= self.device_count) return error.UnknownPort;
    if (self.vehicle != null) return error.InvalidVehicle;
    var kept: usize = 0;
    for (self.wires[0..self.wire_count]) |w| {
        if (w.from.device == index or w.to.device == index) continue;
        var moved = w;
        if (moved.from.device > index) moved.from.device -= 1;
        if (moved.to.device > index) moved.to.device -= 1;
        self.wires[kept] = moved;
        kept += 1;
    }
    self.wire_count = kept;
    const removed = self.devices[index];
    if (removed.node_count > 0) {
        const first = removed.first_node;
        const count = removed.node_count;
        std.mem.copyForwards(Node, self.nodes[first..], self.nodes[first + count .. self.node_count]);
        self.node_count -= count;
        for (self.devices[0..self.device_count]) |*d| if (d.first_node > first) {
            d.first_node -= count;
        };
    }
    std.mem.copyForwards(DeviceDef, self.devices[index..], self.devices[index + 1 .. self.device_count]);
    self.device_count -= 1;
}

/// Converts back to the document shape (for saves). Strings and slices live in `arena`.
pub fn toDoc(self: *const Blueprint, arena: std.mem.Allocator) error{OutOfMemory}!Doc {
    const parts = try arena.alloc(DocPart, self.part_count);
    for (parts, self.parts[0..self.part_count]) |*out, p| out.* = .{ .offset = p.offset, .size = p.size, .color = p.color };
    const devices = try arena.alloc(DocDevice, self.device_count);
    for (devices, self.devices[0..self.device_count]) |*out, *d| out.* = .{
        .id = try arena.dupe(u8, d.name()),
        .kind = d.kind,
        .offset = d.offset,
        .size = d.size,
        .color = d.color,
        .watts = d.watts,
        .speed = d.speed,
        .travel = d.travel,
        .nodes = try arena.dupe(Node, self.logicNodes(d.*)),
        .body = d.body,
        .channel = d.channel,
    };
    const wires = try arena.alloc([2][]const u8, self.wire_count);
    for (wires, self.wires[0..self.wire_count]) |*out, w| out.* = .{ try self.portName(arena, w.from), try self.portName(arena, w.to) };
    const vehicle: ?DocVehicle = if (self.vehicle) |v| blk: {
        const wheels = try arena.alloc(DocWheel, v.wheel_count);
        for (wheels, v.wheels[0..v.wheel_count]) |*out, w| out.* = .{ .offset = w.offset, .radius = w.radius, .rest = w.rest, .driven = w.driven, .steered = w.steered };
        break :blk .{ .size = v.size, .mass = v.mass, .stiffness = v.stiffness, .damping = v.damping, .grip = v.grip, .max_force = v.max_force, .max_brake = v.max_brake, .max_steer = v.max_steer, .wheels = wheels };
    } else null;
    return .{ .format = format_version, .name = try arena.dupe(u8, self.name()), .parts = parts, .devices = devices, .wires = wires, .vehicle = vehicle };
}

pub fn portName(self: *const Blueprint, arena: std.mem.Allocator, ref: PortRef) error{OutOfMemory}![]const u8 {
    const def = &self.devices[ref.device];
    return std.fmt.allocPrint(arena, "{s}.{s}", .{ def.name(), Device.ports(def.kind)[ref.port].name });
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
            else => continue,
        };
        if (slot.* != null) return error.InvalidVehicle;
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

pub fn resolve(self: *const Blueprint, text: []const u8) Error!PortRef {
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

test "runtime edits use the file format's validation and round-trip through documents" {
    const allocator = std.testing.allocator;
    var bp = try parse(allocator, door_json);
    const lamp = try bp.addDevice(.{ .id = "lamp", .kind = .lamp, .watts = 20, .body = true });
    try bp.connect(.{ .device = 0, .port = 0 }, .{ .device = lamp, .port = 0 });
    try bp.connect(.{ .device = 2, .port = 1 }, .{ .device = lamp, .port = 1 });
    try std.testing.expectError(error.MultipleDrivers, bp.connect(.{ .device = 1, .port = 0 }, .{ .device = lamp, .port = 1 }));
    try std.testing.expectError(error.PortKindMismatch, bp.connect(.{ .device = 0, .port = 0 }, .{ .device = lamp, .port = 1 }));
    try std.testing.expectError(error.WrongDirection, bp.connect(.{ .device = lamp, .port = 1 }, .{ .device = 2, .port = 0 }));
    try std.testing.expectError(error.DuplicateDevice, bp.addDevice(.{ .id = "lamp", .kind = .lamp, .watts = 1 }));
    try std.testing.expectError(error.InvalidVehicle, bp.addDevice(.{ .id = "seat", .kind = .seat }));
    try std.testing.expect(bp.devices[lamp].hasBody());

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const doc = try bp.toDoc(arena_state.allocator());
    const json = try std.json.Stringify.valueAlloc(allocator, doc, .{});
    defer allocator.free(json);
    const back = try parse(allocator, json);
    try std.testing.expectEqual(bp.wire_count, back.wire_count);
    try std.testing.expectEqualDeep(bp.wires[0..bp.wire_count], back.wires[0..back.wire_count]);
    try std.testing.expect(back.devices[lamp].body);

    // Removing the latch drops its wires and shifts later indices.
    try bp.removeDevice(2);
    try std.testing.expectEqual(@as(usize, 4), bp.device_count);
    try std.testing.expectEqualStrings("lamp", bp.devices[3].name());
    for (bp.wires[0..bp.wire_count]) |w| try std.testing.expect(w.from.device < 4 and w.to.device < 4);
    try std.testing.expectEqual(@as(usize, 2), bp.wire_count);
    try std.testing.expectEqual(@as(usize, 1), bp.disconnectInputs(3));
}

test "removing a logic device compacts the shared node table" {
    var bp = try parse(std.testing.allocator,
        \\{"format":1,"name":"two","devices":[
        \\ {"id":"a","kind":"logic","nodes":[{"constant":1},{"constant":2}]},
        \\ {"id":"b","kind":"logic","nodes":[{"constant":3}]}]}
    );
    try bp.removeDevice(0);
    try std.testing.expectEqual(@as(usize, 1), bp.node_count);
    try std.testing.expectEqual(@as(f32, 3), bp.logicNodes(bp.devices[0])[0].constant);
}
