const std = @import("std");
const Blueprint = @import("Blueprint.zig");
const Device = @import("Device.zig");
const Graph = @import("Graph.zig");
const R = @import("../physics/Rotation.zig");
const Machine = @This();

/// One placed blueprint instance. Simulation is fixed-step, allocation-free, and deterministic:
/// every signal input reads the previous step's outputs (one step of latency per hop, so wiring
/// cycles are allowed), then each power network shares its supply among consumers.
/// The machine knows nothing about physics; callers move actuator bodies to `devicePosition`
/// and, for vehicles, keep `origin`/`rotation` on the chassis and read the motor and steering.
pub const max_devices = Blueprint.max_devices;
const none: u8 = 0xFF;

/// What the machine can sense this step.
pub const Environment = struct {
    player_feet: [3]f32 = .{ 0, -1e9, 0 },
    /// Device index of a button pressed this step.
    pressed: ?u8 = null,
    /// Driver input for this machine's seat, when occupied.
    controls: ?Controls = null,
};
pub const Controls = struct { throttle: f32 = 0, steer: f32 = 0, brake: f32 = 0 };
pub const Network = struct { supply: f32 = 0, demand: f32 = 0, satisfaction: f32 = 1 };

blueprint: *const Blueprint,
origin: [3]f32,
/// Frame orientation; identity for placed structures, the chassis pose for vehicles.
rotation: R.Quat = R.identity,
outputs: [max_devices][Device.max_ports]f32 = @splat(@splat(0)),
previous: [max_devices][Device.max_ports]f32 = @splat(@splat(0)),
/// Persistent per-device state: latch value, actuator position (0..1 along travel).
state: [max_devices]f32 = @splat(0),
/// Last `toggle` input per latch, for rising-edge detection.
last_input: [max_devices]f32 = @splat(0),
drivers: [max_devices][Device.max_ports]?Blueprint.PortRef = @splat(@splat(null)),
/// Power network index per device, or `none`.
network_of: [max_devices]u8 = @splat(none),
networks: [max_devices]Network = @splat(.{}),
network_count: usize = 0,

pub fn init(blueprint: *const Blueprint, origin: [3]f32) Machine {
    var self: Machine = .{ .blueprint = blueprint, .origin = origin };
    for (blueprint.wires[0..blueprint.wire_count]) |w| {
        if (Device.ports(blueprint.devices[w.to.device].kind)[w.to.port].kind == .signal) self.drivers[w.to.device][w.to.port] = w.from;
    }
    // Union-find over power wires; every device with a power port gets a network.
    var parent: [max_devices]u8 = undefined;
    for (&parent, 0..) |*p, i| p.* = @intCast(i);
    for (blueprint.wires[0..blueprint.wire_count]) |w| {
        if (Device.ports(blueprint.devices[w.from.device].kind)[w.from.port].kind != .power) continue;
        const a = find(&parent, w.from.device);
        const b = find(&parent, w.to.device);
        parent[@max(a, b)] = @min(a, b);
    }
    for (0..blueprint.device_count) |d| {
        if (Device.powerPort(blueprint.devices[d].kind) == null) continue;
        const root = find(&parent, @intCast(d));
        if (self.network_of[root] == none) {
            self.network_of[root] = @intCast(self.network_count);
            self.network_count += 1;
        }
        self.network_of[d] = self.network_of[root];
    }
    return self;
}

fn find(parent: *[max_devices]u8, x: u8) u8 {
    var i = x;
    while (parent[i] != i) i = parent[i];
    return i;
}

fn input(self: *const Machine, device: usize, port: u8) f32 {
    if (self.drivers[device][port]) |from| return self.previous[from.device][from.port];
    return Device.ports(self.blueprint.devices[device].kind)[port].default;
}

pub fn step(self: *Machine, env: Environment, dt: f32) void {
    const bp = self.blueprint;
    self.previous = self.outputs;
    for (self.networks[0..self.network_count]) |*n| n.* = .{};
    // Sensors, controllers, and power bookkeeping.
    for (bp.devices[0..bp.device_count], 0..) |def, d| {
        switch (def.kind) {
            .generator => {
                const supply = if (self.input(d, 1) > 0.5) def.watts else 0;
                self.networks[self.network_of[d]].supply += supply;
                self.outputs[d][0] = supply;
            },
            .button => self.outputs[d][0] = if (env.pressed == @as(u8, @intCast(d))) 1 else 0,
            .proximity => {
                const local = R.inverseRotate(self.rotation, R.sub(env.player_feet, self.worldOffset(def.offset)));
                var inside = true;
                for (0..3) |k| inside = inside and @abs(local[k]) <= def.size[k] / 2;
                self.outputs[d][0] = if (inside) 1 else 0;
            },
            .seat => {
                const c = env.controls orelse Controls{};
                self.outputs[d] = .{ @floatFromInt(@intFromBool(env.controls != null)), std.math.clamp(c.throttle, -1, 1), std.math.clamp(c.steer, -1, 1), std.math.clamp(c.brake, 0, 1), 0 };
            },
            .motor => self.networks[self.network_of[d]].demand += def.watts * @abs(std.math.clamp(self.input(d, 1), -1, 1)),
            .steering => self.outputs[d][1] = std.math.clamp(self.input(d, 0), -1, 1),
            .latch => {
                const toggle = self.input(d, 0);
                if (toggle > 0.5 and self.last_input[d] <= 0.5) self.state[d] = 1 - self.state[d];
                self.last_input[d] = toggle;
                self.outputs[d][1] = self.state[d];
            },
            .logic => {
                var inputs: [4]f32 = undefined;
                for (&inputs, 0..) |*v, i| v.* = self.input(d, @intCast(i));
                var values: [Blueprint.max_nodes]f32 = undefined;
                const nodes = bp.logicNodes(def);
                Graph.evaluateNodes(nodes, values[0..nodes.len], &inputs);
                self.outputs[d][4] = values[nodes.len - 1];
            },
            .actuator => {
                const target = std.math.clamp(self.input(d, 1), 0, 1);
                if (@abs(target - self.state[d]) > 1e-4) self.networks[self.network_of[d]].demand += def.watts;
            },
        }
    }
    for (self.networks[0..self.network_count]) |*n| {
        // No supply means nothing on the network runs, whatever its rating.
        n.satisfaction = if (n.supply <= 0) 0 else if (n.demand <= 0) 1 else @min(1, n.supply / n.demand);
    }
    // Actuators move and motors drive at rated output scaled by satisfaction (brownout).
    for (bp.devices[0..bp.device_count], 0..) |def, d| {
        if (def.kind == .motor) self.outputs[d][2] = std.math.clamp(self.input(d, 1), -1, 1) * self.satisfaction(d);
        if (def.kind != .actuator) continue;
        const target = std.math.clamp(self.input(d, 1), 0, 1);
        const max_step = def.speed / Blueprint.length(def.travel) * dt * self.satisfaction(d);
        const delta = target - self.state[d];
        self.state[d] += std.math.clamp(delta, -max_step, max_step);
        self.outputs[d][2] = self.state[d];
    }
}

pub fn satisfaction(self: *const Machine, device: usize) f32 {
    const n = self.network_of[device];
    return if (n == none) 0 else self.networks[n].satisfaction;
}

pub fn network(self: *const Machine, device: usize) ?Network {
    const n = self.network_of[device];
    return if (n == none) null else self.networks[n];
}

/// Frame-relative offset to world space.
pub fn worldOffset(self: *const Machine, offset: [3]f32) [3]f32 {
    return R.add(self.origin, R.rotate(self.rotation, offset));
}

/// World-space center of a device's body, including actuator travel.
pub fn devicePosition(self: *const Machine, device: usize) [3]f32 {
    const def = self.blueprint.devices[device];
    var offset = def.offset;
    if (def.kind == .actuator) for (0..3) |k| {
        offset[k] += def.travel[k] * self.state[device];
    };
    return self.worldOffset(offset);
}

/// Restores persistent state (from a save) and re-derives outputs that depend on it.
pub fn restore(self: *Machine, saved: []const f32) error{InvalidMachineState}!void {
    const bp = self.blueprint;
    if (saved.len != bp.device_count) return error.InvalidMachineState;
    for (saved, bp.devices[0..bp.device_count]) |s, def| {
        const valid = switch (def.kind) {
            .latch => s == 0 or s == 1,
            .actuator => s >= 0 and s <= 1,
            else => s == 0,
        };
        if (!valid) return error.InvalidMachineState;
    }
    self.outputs = @splat(@splat(0));
    self.last_input = @splat(0);
    for (saved, bp.devices[0..bp.device_count], 0..) |s, def, d| {
        self.state[d] = s;
        switch (def.kind) {
            .latch => self.outputs[d][1] = s,
            .actuator => self.outputs[d][2] = s,
            else => {},
        }
    }
    self.previous = self.outputs;
}

pub fn states(self: *const Machine) []const f32 {
    return self.state[0..self.blueprint.device_count];
}

fn run(machine: *Machine, env: Machine.Environment, steps: usize) void {
    for (0..steps) |_| machine.step(env, 1.0 / 60.0);
}

test "button toggles a latch that drives a powered actuator open and closed" {
    const bp = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"door","devices":[
        \\ {"id":"gen","kind":"generator","watts":100},
        \\ {"id":"button","kind":"button"},
        \\ {"id":"toggle","kind":"latch"},
        \\ {"id":"door","kind":"actuator","travel":[2,0,0],"speed":2,"watts":100}],
        \\ "wires":[["gen.power","door.power"],["button.pressed","toggle.toggle"],["toggle.state","door.target"]]}
    );
    var m = Machine.init(&bp, .{ 10, 0, 0 });
    run(&m, .{}, 10);
    try std.testing.expectEqual(@as(f32, 0), m.state[3]);
    m.step(.{ .pressed = 1 }, 1.0 / 60.0);
    // Two hops of latency, then 2 m at 2 m/s takes one second.
    run(&m, .{}, 62);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.state[3], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), m.devicePosition(3)[0], 0.0001);
    // Idle actuators draw nothing.
    try std.testing.expectEqual(@as(f32, 0), m.network(3).?.demand);
    m.step(.{ .pressed = 1 }, 1.0 / 60.0);
    run(&m, .{}, 30);
    try std.testing.expect(m.state[3] > 0.4 and m.state[3] < 0.6);
}

test "shared power browns out, disabled generators stop actuators, and logic combines sensors" {
    const bp = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"pair","devices":[
        \\ {"id":"gen","kind":"generator","watts":100},
        \\ {"id":"near","kind":"proximity","offset":[0,1,0],"size":[2,2,2]},
        \\ {"id":"any","kind":"logic","nodes":[{"input":0},{"input":1},{"add":{"a":0,"b":1}},{"constant":0.5},{"greater":{"a":2,"b":3}}]},
        \\ {"id":"left","kind":"actuator","travel":[0,1,0],"speed":1,"watts":100},
        \\ {"id":"right","kind":"actuator","travel":[0,1,0],"speed":1,"watts":100}],
        \\ "wires":[["gen.power","left.power"],["gen.power","right.power"],["near.present","any.b"],["any.out","left.target"],["any.out","right.target"]]}
    );
    var m = Machine.init(&bp, .{ 0, 0, 0 });
    try std.testing.expectEqual(@as(usize, 1), m.network_count);
    run(&m, .{ .player_feet = .{ 0, 0.5, 0 } }, 2 + 60);
    // 100 W shared by two 100 W actuators: half speed, half travel after one second.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), m.state[3], 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), m.network(3).?.satisfaction, 0.0001);
    // Player leaves: targets drop to 0 and both return.
    run(&m, .{}, 200);
    try std.testing.expectEqual(@as(f32, 0), m.state[4]);

    const off = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"off","devices":[
        \\ {"id":"gen","kind":"generator","watts":100},
        \\ {"id":"zero","kind":"logic","nodes":[{"constant":0}]},
        \\ {"id":"one","kind":"logic","nodes":[{"constant":1}]},
        \\ {"id":"arm","kind":"actuator","travel":[1,0,0],"speed":1,"watts":10}],
        \\ "wires":[["gen.power","arm.power"],["zero.out","gen.enable"],["one.out","arm.target"]]}
    );
    var dark = Machine.init(&off, .{ 0, 0, 0 });
    run(&dark, .{}, 120);
    try std.testing.expectEqual(@as(f32, 0), dark.state[3]);
    try std.testing.expectEqual(@as(f32, 0), dark.network(3).?.satisfaction);
}

test "machine state restores and rejects invalid values" {
    const bp = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"door","devices":[
        \\ {"id":"toggle","kind":"latch"},
        \\ {"id":"door","kind":"actuator","travel":[2,0,0],"speed":2,"watts":0}],
        \\ "wires":[["toggle.state","door.target"]]}
    );
    var m = Machine.init(&bp, .{ 0, 0, 0 });
    try m.restore(&.{ 1, 0.25 });
    try std.testing.expectEqual(@as(f32, 0.5), m.devicePosition(1)[0]);
    // No generator on its network: the actuator never moves.
    run(&m, .{}, 60);
    try std.testing.expectEqual(@as(f32, 0.25), m.state[1]);
    try std.testing.expectError(error.InvalidMachineState, m.restore(&.{ 0.5, 0 }));
    try std.testing.expectError(error.InvalidMachineState, m.restore(&.{1}));
}

test "seat controls drive a powered motor and steering; power limits drive output" {
    const bp = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"cart","devices":[
        \\ {"id":"cell","kind":"generator","watts":50},
        \\ {"id":"seat","kind":"seat","offset":[0,1,0]},
        \\ {"id":"motor","kind":"motor","watts":100},
        \\ {"id":"wheel","kind":"steering"}],
        \\ "wires":[["cell.power","motor.power"],["seat.throttle","motor.throttle"],["seat.steer","wheel.command"]],
        \\ "vehicle":{"size":[2,1,3],"mass":300,"stiffness":8000,"damping":1000,"grip":1,"max_force":3000,"max_brake":2000,"max_steer":0.5,
        \\  "wheels":[{"offset":[-1,-0.5,1],"radius":0.4,"rest":0.4,"driven":true},{"offset":[1,-0.5,1],"radius":0.4,"rest":0.4},{"offset":[0,-0.5,-1],"radius":0.4,"rest":0.4}]}}
    );
    var m = Machine.init(&bp, .{ 0, 0, 0 });
    run(&m, .{ .controls = .{ .throttle = 1, .steer = -0.5, .brake = 1 } }, 3);
    try std.testing.expectEqual(@as(f32, 1), m.outputs[1][0]);
    // 50 W supply for a 100 W motor at full throttle: half drive.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), m.outputs[2][2], 0.0001);
    try std.testing.expectEqual(@as(f32, -0.5), m.outputs[3][1]);
    // Half throttle fits within the supply: full requested drive.
    run(&m, .{ .controls = .{ .throttle = 0.5 } }, 3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), m.outputs[2][2], 0.0001);
    run(&m, .{}, 3);
    try std.testing.expectEqual(@as(f32, 0), m.outputs[1][0]);
    try std.testing.expectEqual(@as(f32, 0), m.outputs[2][2]);
    // A rotated frame carries device positions with it.
    m.rotation = R.axisAngle(.{ 1, 0, 0 }, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), m.devicePosition(1)[2], 1e-5);
}
