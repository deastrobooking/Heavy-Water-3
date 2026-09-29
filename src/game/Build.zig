//! In-world creation: the build tool (place and remove crates, prefab machines, and loose
//! workshop devices with grid and surface snapping and quarter-turn rotation) and the wire
//! tool (connect and disconnect device ports with the same validation blueprint files get).
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const Blueprint = @import("../machine/Blueprint.zig");
const Device = @import("../machine/Device.zig");
const Node = @import("../machine/Node.zig").Node;
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Sandbox = @import("Sandbox.zig");
const Vec3 = Physics.Vec3;

pub const Tool = enum { hands, build, wire };
/// Palette: crates, prefab machines, then loose devices that join the workshop circuit.
pub const Item = enum { crate, powered_door, elevator, rover, generator, button, latch, logic_or, lamp };
pub const build_reach: f32 = 14;
pub const grid: f32 = 0.5;
pub const max_candidates = 16;

pub const Preview = struct { item: Item, origin: Vec3, center: Vec3, half: Vec3, yaw: u2, valid: bool };
pub const State = struct {
    tool: Tool = .hands,
    item: Item = .crate,
    yaw: u2 = 0,
    preview: ?Preview = null,
    wire_from: ?Sandbox.DeviceRef = null,
    wire_choice: usize = 0,
    kit_serial: u32 = 0,
};
pub const Bounds = struct { lo: Vec3, hi: Vec3 };

pub fn itemName(item: Item) []const u8 {
    return switch (item) {
        .logic_or => "logic or",
        .powered_door => "powered door",
        else => @tagName(item),
    };
}

/// Structure bounds in the machine's rotated frame, relative to its origin: parts, bodied
/// devices, and both ends of actuator travel.
pub fn footprint(bp: *const Blueprint, yaw: u2) Bounds {
    var lo: Vec3 = @splat(std.math.inf(f32));
    var hi: Vec3 = @splat(-std.math.inf(f32));
    const q = Sandbox.yawRotation(yaw);
    const Grow = struct {
        fn box(l: *Vec3, h: *Vec3, center: Vec3, half: Vec3) void {
            for (0..3) |k| {
                l[k] = @min(l[k], center[k] - half[k]);
                h[k] = @max(h[k], center[k] + half[k]);
            }
        }
    };
    for (bp.parts[0..bp.part_count]) |part| Grow.box(&lo, &hi, R.rotate(q, part.offset), Sandbox.turnedHalf(part.size, yaw));
    for (bp.devices[0..bp.device_count]) |d| {
        if (!d.hasBody()) continue;
        Grow.box(&lo, &hi, R.rotate(q, d.offset), Sandbox.turnedHalf(d.size, yaw));
        if (d.kind == .actuator) Grow.box(&lo, &hi, R.rotate(q, R.add(d.offset, d.travel)), Sandbox.turnedHalf(d.size, yaw));
    }
    if (bp.vehicle) |v| {
        Grow.box(&lo, &hi, .{ 0, 0, 0 }, Sandbox.turnedHalf(v.size, yaw));
        for (v.wheels[0..v.wheel_count]) |w| Grow.box(&lo, &hi, R.rotate(q, w.offset), .{ w.radius, w.rest + w.radius, w.radius });
    }
    if (!std.math.isFinite(lo[0])) return .{ .lo = .{ -0.25, 0, -0.25 }, .hi = .{ 0.25, 0.5, 0.25 } };
    return .{ .lo = lo, .hi = hi };
}

const or_nodes = [_]Node{ .{ .input = 0 }, .{ .input = 1 }, .{ .add = .{ .a = 0, .b = 1 } }, .{ .constant = 0.5 }, .{ .greater = .{ .a = 2, .b = 3 } } };

/// Loose-device definitions; every one gets a pickable body so it can be wired.
pub fn kitDevice(item: Item, id: []const u8) Blueprint.DocDevice {
    return switch (item) {
        .generator => .{ .id = id, .kind = .generator, .size = .{ 0.8, 1, 0.8 }, .color = .{ 0.85, 0.7, 0.2, 1 }, .watts = 200, .body = true },
        .button => .{ .id = id, .kind = .button, .size = .{ 0.35, 0.35, 0.35 }, .color = .{ 0.9, 0.25, 0.2, 1 }, .body = true },
        .latch => .{ .id = id, .kind = .latch, .size = .{ 0.5, 0.5, 0.5 }, .color = .{ 0.55, 0.35, 0.75, 1 }, .body = true },
        .logic_or => .{ .id = id, .kind = .logic, .size = .{ 0.5, 0.5, 0.5 }, .color = .{ 0.2, 0.7, 0.65, 1 }, .nodes = &or_nodes, .body = true },
        .lamp => .{ .id = id, .kind = .lamp, .size = .{ 0.35, 1.2, 0.35 }, .color = .{ 1, 0.9, 0.6, 1 }, .watts = 25, .body = true },
        .crate, .powered_door, .elevator, .rover => unreachable,
    };
}

fn prefab(sb: *const Sandbox, item: Item) ?*const Blueprint {
    return switch (item) {
        .powered_door => sb.catalog.content.powered_door,
        .elevator => sb.catalog.content.elevator,
        .rover => sb.catalog.content.rover,
        else => null,
    };
}

pub fn selectTool(sb: *Sandbox, tool: Tool) void {
    sb.tools.tool = tool;
    sb.tools.preview = null;
    sb.tools.wire_from = null;
    sb.tools.wire_choice = 0;
    if (tool != .hands) sb.release();
    sb.say("{s} tool", .{@tagName(tool)});
}

pub fn update(sb: *Sandbox, camera: Camera, primary: bool, actions: Sandbox.Actions) !void {
    const st = &sb.tools;
    switch (st.tool) {
        .hands => {},
        .build => {
            if (actions.next_item) {
                st.item = @enumFromInt((@intFromEnum(st.item) + 1) % std.meta.fields(Item).len);
                sb.say("{s}", .{itemName(st.item)});
            }
            if (actions.rotate) st.yaw +%= 1;
            st.preview = preview(sb, camera);
            if (primary) {
                if (st.preview) |p| {
                    if (p.valid) try place(sb, p) else sb.say("blocked", .{});
                } else sb.say("aim at the ground within {d:.0} m", .{build_reach});
            }
            if (actions.secondary) remove(sb, sb.target);
        },
        .wire => {
            if (actions.next_item) st.wire_choice += 1;
            if (primary) wireClick(sb);
            if (actions.secondary) {
                if (st.wire_from != null) {
                    st.wire_from = null;
                    sb.say("wire canceled", .{});
                } else if (sb.target == .device) {
                    const d = sb.target.device;
                    const placed = &sb.machines[d.machine];
                    const removed = placed.blueprint.disconnectInputs(d.device);
                    placed.machine.reconfigure();
                    sb.say("disconnected {d} inputs of {s}", .{ removed, placed.blueprint.devices[d.device].name() });
                }
            }
        },
    }
}

fn snap(v: f32) f32 {
    return @round(v / grid) * grid;
}

/// Top of whatever solid surface lies under (x, z) near `y`.
fn supportAt(sb: *const Sandbox, x: f32, y: f32, z: f32) f32 {
    const hit = sb.physics.castRay(.{ x, y + 4, z }, .{ 0, -1, 0 }, 12, .none) orelse return y;
    return hit.point[1];
}

/// Where the selected item would go: the view ray's first surface, snapped to the grid, set
/// on the surface below (crates and devices) or on the terrain footprint (prefabs). Invalid
/// if it would overlap any body or the player.
pub fn preview(sb: *const Sandbox, camera: Camera) ?Preview {
    const f = camera.forward();
    const eye: Vec3 = .{ camera.position.x(), camera.position.y(), camera.position.z() };
    const hit = sb.physics.castRay(eye, .{ f.x(), f.y(), f.z() }, build_reach, .none) orelse return null;
    const x = snap(hit.point[0]);
    const z = snap(hit.point[2]);
    const st = sb.tools;
    var result: Preview = .{ .item = st.item, .origin = undefined, .center = undefined, .half = undefined, .yaw = st.yaw, .valid = true };
    if (prefab(sb, st.item)) |bp| {
        result.origin = sb.groundOrigin(bp, x, z, st.yaw);
        var bounds = footprint(bp, st.yaw);
        // Foundations may sink into the terrain; only the part above ground must be clear.
        bounds.lo[1] = @max(bounds.lo[1], 0.05);
        if (bounds.hi[1] <= bounds.lo[1]) bounds.hi[1] = bounds.lo[1] + 0.1;
        for (0..3) |k| {
            result.center[k] = result.origin[k] + (bounds.lo[k] + bounds.hi[k]) / 2;
            result.half[k] = (bounds.hi[k] - bounds.lo[k]) / 2;
        }
    } else {
        result.half = if (st.item == .crate) sb.crateHalf() else Sandbox.halve(kitDevice(st.item, "x").size);
        const top = supportAt(sb, x, hit.point[1], z);
        result.center = .{ x, top + result.half[1] + 0.01, z };
        result.origin = result.center;
    }
    const clear: Vec3 = .{ result.half[0] * 0.98, result.half[1] * 0.98, result.half[2] * 0.98 };
    const feet = sb.player.feet;
    const shape = sb.player.shape;
    var inside_player = true;
    for ([_]f32{ feet[0], feet[1] + shape.height / 2, feet[2] }, [_]f32{ shape.radius, shape.height / 2, shape.radius }, 0..) |c, h, k| {
        inside_player = inside_player and @abs(c - result.center[k]) < h + result.half[k];
    }
    result.valid = !sb.physics.overlapsBox(result.center, clear) and !inside_player;
    return result;
}

pub fn place(sb: *Sandbox, p: Preview) !void {
    switch (p.item) {
        .crate => _ = sb.spawnCrate(p.center, .{ 0, 0, 0 }) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)}),
        .powered_door, .elevator, .rover => _ = sb.spawnMachine(null, prefab(sb, p.item).?.*, p.origin, p.yaw, false) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)}),
        .generator, .button, .latch, .logic_or, .lamp => {
            sb.tools.kit_serial += 1;
            var id_buffer: [Blueprint.id_len]u8 = undefined;
            const tag = switch (p.item) {
                .generator => "gen",
                .logic_or => "or",
                else => @tagName(p.item),
            };
            const id = std.fmt.bufPrint(&id_buffer, "{s}{d}", .{ tag, sb.tools.kit_serial }) catch unreachable;
            _ = sb.addWorkshopDevice(kitDevice(p.item, id), p.center) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)});
        },
    }
    sb.say("placed {s}", .{itemName(p.item)});
}

/// Removes a crate, a workshop device, or a whole placed machine. A vehicle being driven
/// cannot be removed.
pub fn remove(sb: *Sandbox, target: Sandbox.Target) void {
    switch (target) {
        .prop => |i| {
            sb.removeCrate(i);
            sb.say("removed crate", .{});
        },
        .device => |d| {
            const placed = &sb.machines[d.machine];
            if (placed.workshop) {
                const name = placed.blueprint.devices[d.device].id;
                sb.removeWorkshopDevice(d) catch |err| return sb.say("cannot remove: {s}", .{@errorName(err)});
                sb.say("removed {s}", .{std.mem.sliceTo(&name, 0)});
            } else removeMachine(sb, d.machine);
        },
        .structure => |m| removeMachine(sb, m),
        .relic, .none => sb.say("nothing to remove", .{}),
    }
}

fn removeMachine(sb: *Sandbox, m: u8) void {
    if (sb.seated == m) return sb.say("leave the vehicle first", .{});
    var name: [Blueprint.name_len]u8 = sb.machines[m].blueprint.name_buffer;
    sb.removeMachine(m);
    sb.say("removed {s}", .{std.mem.sliceTo(&name, 0)});
}

/// Every output of `from` that could feed an input of `to` right now: same machine, same
/// port kind, and a signal input that has no driver yet.
pub fn candidates(sb: *const Sandbox, from: Sandbox.DeviceRef, to: Sandbox.DeviceRef, out: *[max_candidates]Blueprint.Wire) usize {
    if (from.machine != to.machine or from.device == to.device) return 0;
    const bp = &sb.machines[from.machine].blueprint;
    var n: usize = 0;
    for (Device.ports(bp.devices[from.device].kind), 0..) |o, op| {
        if (o.direction != .output) continue;
        for (Device.ports(bp.devices[to.device].kind), 0..) |i, ip| {
            if (i.direction != .input or i.kind != o.kind or n == out.len) continue;
            const wire: Blueprint.Wire = .{ .from = .{ .device = from.device, .port = @intCast(op) }, .to = .{ .device = to.device, .port = @intCast(ip) } };
            if (i.kind == .signal and bp.driverOf(wire.to) != null) continue;
            out[n] = wire;
            n += 1;
        }
    }
    return n;
}

/// The wire a click would make now, if any.
pub fn pendingWire(sb: *const Sandbox) ?Blueprint.Wire {
    const from = sb.tools.wire_from orelse return null;
    if (sb.target != .device) return null;
    var buffer: [max_candidates]Blueprint.Wire = undefined;
    const n = candidates(sb, from, sb.target.device, &buffer);
    return if (n == 0) null else buffer[sb.tools.wire_choice % n];
}

fn wireClick(sb: *Sandbox) void {
    const st = &sb.tools;
    if (sb.target != .device) return sb.say("aim at a device", .{});
    const to = sb.target.device;
    const from = st.wire_from orelse {
        st.wire_from = to;
        st.wire_choice = 0;
        return sb.say("from {s}: aim at a target", .{sb.machines[to.machine].blueprint.devices[to.device].name()});
    };
    if (from.machine == to.machine and from.device == to.device) {
        st.wire_from = null;
        return sb.say("wire canceled", .{});
    }
    if (from.machine != to.machine) return sb.say("devices are on different machines", .{});
    const wire = pendingWire(sb) orelse return sb.say("no compatible free ports", .{});
    const placed = &sb.machines[from.machine];
    placed.blueprint.connect(wire.from, wire.to) catch |err| return sb.say("cannot wire: {s}", .{@errorName(err)});
    placed.machine.reconfigure();
    const a = placed.blueprint.devices[wire.from.device];
    const b = placed.blueprint.devices[wire.to.device];
    sb.say("wired {s}.{s} to {s}.{s}", .{ a.name(), Device.ports(a.kind)[wire.from.port].name, b.name(), Device.ports(b.kind)[wire.to.port].name });
    st.wire_from = null;
    st.wire_choice = 0;
}

/// One HUD line describing the active tool.
pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const st = sb.tools;
    return switch (st.tool) {
        .hands => "",
        .build => std.fmt.bufPrint(buffer, "BUILD {s}  TAB NEXT  T TURN  CLICK PLACE  RMB REMOVE", .{itemName(st.item)}) catch buffer,
        .wire => if (pendingWire(sb)) |w| blk: {
            const bp = &sb.machines[st.wire_from.?.machine].blueprint;
            const a = bp.devices[w.from.device];
            const b = bp.devices[w.to.device];
            break :blk std.fmt.bufPrint(buffer, "{s}.{s} TO {s}.{s}  CLICK WIRE  TAB NEXT", .{ a.name(), Device.ports(a.kind)[w.from.port].name, b.name(), Device.ports(b.kind)[w.to.port].name }) catch buffer;
        } else if (st.wire_from != null) "WIRE: AIM AT A TARGET DEVICE  RMB CANCEL" else "WIRE: CLICK A SOURCE DEVICE  RMB DISCONNECT INPUTS",
    };
}

fn fromTo(a: Vec3, b: Vec3) R.Quat {
    const d = R.normalize(b);
    const axis = R.cross(a, d);
    const s = R.length(axis);
    const c = R.dot(a, d);
    if (s < 1e-6) return if (c > 0) R.identity else R.axisAngle(.{ 1, 0, 0 }, std.math.pi);
    return R.axisAngle(axis, std.math.atan2(s, c));
}

/// Placement preview (build) or every wire as a thin colored bar (wire).
pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    const st = sb.tools;
    const block = sb.catalog.content.block;
    if (st.tool == .build) if (st.preview) |p| {
        const tint: [4]f32 = if (p.valid) .{ 0.35, 1.0, 0.45, 1 } else .{ 1.0, 0.3, 0.25, 1 };
        if (prefab(sb, p.item)) |bp| {
            const q = Sandbox.yawRotation(p.yaw);
            for (bp.parts[0..bp.part_count]) |part| {
                if (n == out.len) return n;
                out[n] = .{ .mesh = block, .transform = .{ .position = R.add(p.origin, R.rotate(q, part.offset)) }, .tint = tint, .size = part.size, .rotation = q };
                n += 1;
            }
            if (bp.vehicle) |v| if (n < out.len) {
                out[n] = .{ .mesh = block, .transform = .{ .position = p.origin }, .tint = tint, .size = v.size, .rotation = q };
                n += 1;
            };
        } else if (n < out.len) {
            out[n] = if (p.item == .crate)
                .{ .mesh = sb.catalog.content.crate, .transform = .{ .position = p.center }, .tint = tint }
            else
                .{ .mesh = block, .transform = .{ .position = p.center }, .tint = tint, .size = kitDevice(p.item, "x").size };
            n += 1;
        }
    };
    if (st.tool == .wire) for (&sb.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        const bp = &placed.blueprint;
        for (bp.wires[0..bp.wire_count]) |w| {
            if (n == out.len) return n;
            const a = sb.devicePosition(.{ .machine = @intCast(m), .device = w.from.device });
            const b = sb.devicePosition(.{ .machine = @intCast(m), .device = w.to.device });
            const d = R.sub(b, a);
            const power = Device.ports(bp.devices[w.from.device].kind)[w.from.port].kind == .power;
            out[n] = .{ .mesh = block, .transform = .{ .position = R.scale(R.add(a, b), 0.5) }, .tint = if (power) .{ 1.0, 0.8, 0.2, 1 } else .{ 0.25, 0.9, 1.0, 1 }, .size = .{ 0.06, 0.06, @max(0.01, R.length(d)) }, .rotation = fromTo(.{ 0, 0, 1 }, d) };
            n += 1;
        }
    };
    return n;
}

const Catalog = @import("../asset/Catalog.zig");
const Terrain = @import("../procedural/Terrain.zig");

fn testWorld(sb: *Sandbox, catalog: *Catalog, camera: *Camera) !void {
    try catalog.load(std.testing.allocator);
    errdefer catalog.deinit(std.testing.allocator);
    try sb.init(310399555161, catalog, camera);
}

fn tick(sb: *Sandbox, camera: *Camera, actions: Sandbox.Actions) !void {
    try sb.step(camera, .{}, actions, 1.0 / 60.0);
}

fn aim(camera: *Camera, point: Vec3) void {
    const dx = point[0] - camera.position.x();
    const dy = point[1] - camera.position.y();
    const dz = point[2] - camera.position.z();
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(dy, @sqrt(dx * dx + dz * dz));
}

/// Aims at a ground point relative to the spawn and places the selected palette item there.
fn placeAt(sb: *Sandbox, camera: *Camera, item: Item, dx: f32, dz: f32) !void {
    sb.tools.item = item;
    const x = Sandbox.spawn[0] + dx;
    const z = Sandbox.spawn[2] + dz;
    aim(camera, .{ x, Terrain.surface(sb.seed, x, z).height, z });
    try tick(sb, camera, .{});
    try std.testing.expect(sb.tools.preview.?.valid);
    try tick(sb, camera, .{ .interact = true });
}

fn aimDevice(sb: *Sandbox, camera: *Camera, ref: Sandbox.DeviceRef) !void {
    aim(camera, sb.devicePosition(ref));
    try tick(sb, camera, .{});
    try std.testing.expect(sb.target == .device and sb.target.device.device == ref.device);
}

test "build a workshop circuit from the palette, wire it in the world, light it, and reload it" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    try tick(&sb, &camera, .{ .select_tool = 2 });
    try std.testing.expectEqual(Tool.build, sb.tools.tool);
    try placeAt(&sb, &camera, .generator, 3, -3);
    try placeAt(&sb, &camera, .button, 4.5, -3);
    try placeAt(&sb, &camera, .latch, 6, -3);
    try placeAt(&sb, &camera, .lamp, 7.5, -3);
    const w = sb.workshop.?;
    try std.testing.expectEqual(@as(usize, 4), sb.machines[w].blueprint.device_count);
    // Snapped to the half-meter grid.
    const lamp_position = sb.devicePosition(.{ .machine = w, .device = 3 });
    try std.testing.expectEqual(@round(lamp_position[0] * 2) / 2, lamp_position[0]);

    try tick(&sb, &camera, .{ .select_tool = 3 });
    const pairs = [_][2]u8{ .{ 0, 3 }, .{ 1, 2 }, .{ 2, 3 } };
    for (pairs) |pair| {
        try aimDevice(&sb, &camera, .{ .machine = w, .device = pair[0] });
        try tick(&sb, &camera, .{ .interact = true });
        try aimDevice(&sb, &camera, .{ .machine = w, .device = pair[1] });
        try std.testing.expect(pendingWire(&sb) != null);
        try tick(&sb, &camera, .{ .interact = true });
    }
    try std.testing.expectEqual(@as(usize, 3), sb.machines[w].blueprint.wire_count);
    // The lamp's `on` input is now driven, so a second source is refused.
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 1 });
    try tick(&sb, &camera, .{ .interact = true });
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 3 });
    try std.testing.expect(pendingWire(&sb) == null);
    try tick(&sb, &camera, .{ .secondary = true });

    // Hands: press the button; the latch turns the powered lamp on.
    try tick(&sb, &camera, .{ .select_tool = 1 });
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 1 });
    try tick(&sb, &camera, .{ .interact = true });
    for (0..5) |_| try tick(&sb, &camera, .{});
    try std.testing.expectEqual(@as(f32, 1), sb.machines[w].machine.outputs[3][2]);

    // The whole placed circuit, its wires, and the latch state survive a reload.
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    var other_camera: Camera = .{};
    var other: Sandbox = undefined;
    try other.init(sb.seed, &catalog, &other_camera);
    try std.testing.expectEqual(@as(?u8, null), other.workshop);
    try other.restore(std.testing.allocator, bytes, &other_camera);
    const ow = other.workshop.?;
    try std.testing.expectEqual(@as(usize, 3), other.machines[ow].blueprint.wire_count);
    for (0..3) |_| try other.step(&other_camera, .{}, .{}, 1.0 / 60.0);
    try std.testing.expectEqual(@as(f32, 1), other.machines[ow].machine.outputs[3][2]);

    // Build tool: removing the latch drops its wires; the lamp goes dark.
    try tick(&sb, &camera, .{ .select_tool = 2 });
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 2 });
    try tick(&sb, &camera, .{ .secondary = true });
    try std.testing.expectEqual(@as(usize, 3), sb.machines[w].blueprint.device_count);
    try std.testing.expectEqual(@as(usize, 1), sb.machines[w].blueprint.wire_count);
    for (0..3) |_| try tick(&sb, &camera, .{});
    try std.testing.expectEqual(@as(f32, 0), sb.machines[w].machine.outputs[2][2]);
    // Re-tagged bodies still pick the right device.
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 2 });
}

test "prefabs snap and rotate, overlapping placements are refused, and removal frees the slot" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    const before = sb.machineCount();
    try tick(&sb, &camera, .{ .select_tool = 2 });
    try tick(&sb, &camera, .{ .rotate = true });
    try placeAt(&sb, &camera, .powered_door, 8, -8);
    try std.testing.expectEqual(before + 1, sb.machineCount());
    const m = for (sb.machines, 0..) |placed, i| {
        if (placed.active and placed.yaw == 1) break i;
    } else return error.TestUnexpectedResult;
    const placed = &sb.machines[m];
    try std.testing.expectEqual(@round(placed.machine.origin[0] * 2) / 2, placed.machine.origin[0]);
    // A quarter turn about +Y maps the door's +X travel to −Z.
    const door = placed.blueprint.findDevice("door").?;
    const closed = placed.machine.devicePosition(door);
    placed.machine.state[door] = 1;
    const open = placed.machine.devicePosition(door);
    placed.machine.state[door] = 0;
    try std.testing.expectApproxEqAbs(@as(f32, -2.9), open[2] - closed[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), open[0] - closed[0], 1e-4);

    // Same spot again: the preview is red and nothing is placed.
    sb.tools.item = .powered_door;
    try tick(&sb, &camera, .{});
    try std.testing.expect(!sb.tools.preview.?.valid);
    try tick(&sb, &camera, .{ .interact = true });
    try std.testing.expectEqual(before + 1, sb.machineCount());

    // Remove it by aiming at its structure.
    aim(&camera, placed.machine.worldOffset(placed.blueprint.parts[1].offset));
    try tick(&sb, &camera, .{});
    try std.testing.expect(sb.target == .structure);
    try tick(&sb, &camera, .{ .secondary = true });
    try std.testing.expectEqual(before, sb.machineCount());
    try std.testing.expect(!sb.machines[m].active);
}
