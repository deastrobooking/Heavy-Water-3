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

pub const Tool = enum { hands, build, wire, bridge };
/// Palette: crates, prefab machines, then loose devices that join the workshop circuit.
pub const Item = enum { crate, powered_door, elevator, rover, generator, button, latch, logic_or, lamp, transmitter, receiver, sap_tap, sap_beacon, root_sender, root_listener };
pub const build_reach: f32 = 14;
pub const grid: f32 = 0.5;
pub const max_candidates = 16;

pub const builtin_count = std.meta.fields(Item).len;
const Market = @import("../city/Market.zig");
/// A palette entry: a built-in item, a market kit, or a captured prefab (index into
/// `Sandbox.prefabs`).
pub const Entry = union(enum) { item: Item, kit: Market.Ware, prefab: usize };
pub const Preview = struct { entry: Entry, origin: Vec3, center: Vec3, half: Vec3, yaw: u2, valid: bool };
pub const State = struct {
    tool: Tool = .hands,
    /// Palette position: built-in items, then market kits, then prefabs.
    slot: usize = 0,
    yaw: u2 = 0,
    preview: ?Preview = null,
    wire_from: ?Sandbox.DeviceRef = null,
    wire_choice: usize = 0,
    kit_serial: u32 = 0,
    prefab_serial: u32 = 0,
    bridge_from: ?u8 = null,
    bridge_hover: ?u8 = null,
};

pub fn paletteLen(sb: *const Sandbox) usize {
    return builtin_count + Market.ware_count + sb.prefab_count;
}

pub fn current(sb: *const Sandbox) Entry {
    const slot = sb.tools.slot % paletteLen(sb);
    if (slot < builtin_count) return .{ .item = @enumFromInt(slot) };
    if (slot < builtin_count + Market.ware_count) return .{ .kit = @enumFromInt(slot - builtin_count) };
    return .{ .prefab = slot - builtin_count - Market.ware_count };
}

pub fn entryName(sb: *const Sandbox, e: Entry) []const u8 {
    return switch (e) {
        .item => |item| itemName(item),
        .kit => |ware| sb.catalog.content.wares[@intFromEnum(ware)].name(),
        .prefab => |i| sb.prefabs[i].name(),
    };
}

/// The blueprint an entry places as a whole machine, if it is one.
fn blueprintOf(sb: *const Sandbox, e: Entry) ?*const Blueprint {
    return switch (e) {
        .item => |item| prefab(sb, item),
        .kit => |ware| sb.catalog.content.wares[@intFromEnum(ware)],
        .prefab => |i| &sb.prefabs[i],
    };
}
pub const Bounds = struct { lo: Vec3, hi: Vec3 };

pub fn itemName(item: Item) []const u8 {
    return switch (item) {
        .logic_or => "logic or",
        .powered_door => "powered door",
        .sap_tap => "sap tap",
        .root_sender => "root sender",
        .root_listener => "root listener",
        .sap_beacon => "sap beacon",
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
        .sap_tap => .{ .id = id, .kind = .sap_tap, .size = .{ 0.6, 1, 0.6 }, .color = .{ 0.2, 0.9, 0.75, 1 }, .watts = 200, .body = true },
        .generator => .{ .id = id, .kind = .generator, .size = .{ 0.8, 1, 0.8 }, .color = .{ 0.85, 0.7, 0.2, 1 }, .watts = 200, .body = true },
        .button => .{ .id = id, .kind = .button, .size = .{ 0.35, 0.35, 0.35 }, .color = .{ 0.9, 0.25, 0.2, 1 }, .body = true },
        .latch => .{ .id = id, .kind = .latch, .size = .{ 0.5, 0.5, 0.5 }, .color = .{ 0.55, 0.35, 0.75, 1 }, .body = true },
        .logic_or => .{ .id = id, .kind = .logic, .size = .{ 0.5, 0.5, 0.5 }, .color = .{ 0.2, 0.7, 0.65, 1 }, .nodes = &or_nodes, .body = true },
        .lamp => .{ .id = id, .kind = .lamp, .size = .{ 0.35, 1.2, 0.35 }, .color = .{ 1, 0.9, 0.6, 1 }, .watts = 25, .body = true },
        .transmitter => .{ .id = id, .kind = .transmitter, .size = .{ 0.3, 1.4, 0.3 }, .color = .{ 0.95, 0.45, 0.8, 1 }, .channel = 1, .body = true },
        .receiver => .{ .id = id, .kind = .receiver, .size = .{ 0.5, 0.3, 0.5 }, .color = .{ 0.45, 0.55, 0.95, 1 }, .channel = 1, .body = true },
        .root_sender => .{ .id = id, .kind = .root_sender, .size = .{ 0.5, 0.9, 0.5 }, .color = .{ 0.55, 0.95, 0.45, 1 }, .channel = 1, .body = true },
        .root_listener => .{ .id = id, .kind = .root_listener, .size = .{ 0.7, 0.4, 0.7 }, .color = .{ 0.35, 0.8, 0.4, 1 }, .channel = 1, .body = true },
        .crate, .powered_door, .elevator, .rover, .sap_beacon => unreachable,
    };
}

fn prefab(sb: *const Sandbox, item: Item) ?*const Blueprint {
    return switch (item) {
        .powered_door => sb.catalog.content.powered_door,
        .elevator => sb.catalog.content.elevator,
        .rover => sb.catalog.content.rover,
        .sap_beacon => sb.catalog.content.sap_beacon,
        else => null,
    };
}

pub fn selectTool(sb: *Sandbox, tool: Tool) void {
    sb.tools.tool = tool;
    sb.tools.preview = null;
    sb.tools.wire_from = null;
    sb.tools.wire_choice = 0;
    sb.tools.bridge_from = null;
    sb.tools.bridge_hover = null;
    if (tool != .hands) sb.release();
    sb.say("{s} tool", .{@tagName(tool)});
}

pub fn update(sb: *Sandbox, camera: Camera, primary: bool, actions: Sandbox.Actions) !void {
    const st = &sb.tools;
    switch (st.tool) {
        .hands => {},
        .bridge => try @import("BridgeTool.zig").update(sb, camera, primary, actions.secondary),
        .build => {
            if (actions.next_item) {
                st.slot = (st.slot + 1) % paletteLen(sb);
                sb.say("{s}", .{entryName(sb, current(sb))});
            }
            if (actions.rotate) st.yaw +%= 1;
            st.preview = preview(sb, camera);
            if (primary) {
                if (st.preview) |p| {
                    if (p.valid) {
                        try place(sb, p);
                    } else {
                        const wood_item = p.entry == .item and switch (p.entry.item) {
                            .sap_tap, .sap_beacon, .root_sender, .root_listener => true,
                            else => false,
                        };
                        if (wood_item) sb.say("blocked: needs clear space within 4 m of wood", .{}) else sb.say("blocked", .{});
                    }
                } else sb.say("aim at the ground within {d:.0} m", .{build_reach});
            }
            if (actions.secondary) remove(sb, sb.target);
            if (actions.capture) capture(sb);
        },
        .wire => {
            if (actions.next_item) st.wire_choice += 1;
            if (actions.capture) capture(sb);
            if (primary) wireClick(sb);
            if (actions.secondary) {
                if (st.wire_from != null) {
                    st.wire_from = null;
                    sb.say("wire canceled", .{});
                } else if (sb.target == .device) {
                    const d = sb.target.device;
                    if (sb.machines[d.machine].shrine != null) return sb.say("shrine machines cannot be rewired", .{});
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
    const e = current(sb);
    var result: Preview = .{ .entry = e, .origin = undefined, .center = undefined, .half = undefined, .yaw = st.yaw, .valid = true };
    if (blueprintOf(sb, e)) |bp| {
        result.origin = sb.groundOrigin(bp, x, z, st.yaw);
        var bounds = footprint(bp, st.yaw);
        if (hit.point[1] > Terrain.surface(sb.seed, x, z).height + 1) {
            // Elevated construction must be supported across its whole footprint. Start rays
            // just above the selected deck so upper floors cannot steal the placement.
            var top = -std.math.inf(f32);
            for (0..5) |ix| for (0..5) |iz| {
                const px = x + bounds.lo[0] + (bounds.hi[0] - bounds.lo[0]) * @as(f32, @floatFromInt(ix)) / 4;
                const pz = z + bounds.lo[2] + (bounds.hi[2] - bounds.lo[2]) * @as(f32, @floatFromInt(iz)) / 4;
                const support = sb.physics.castRay(.{ px, hit.point[1] + 0.6, pz }, .{ 0, -1, 0 }, 1.2, .none);
                if (support) |s| {
                    top = @max(top, s.point[1]);
                    if (s.normal[1] < 0.95) result.valid = false;
                } else result.valid = false;
            };
            if (!std.math.isFinite(top)) top = hit.point[1];
            const lift = if (bp.vehicle) |v| v.wheels[0].radius + v.wheels[0].rest - v.wheels[0].offset[1] + 0.1 else -bounds.lo[1] + 0.01;
            result.origin = .{ x, top + lift, z };
            if (hit.normal[1] < 0.95) result.valid = false;
        }
        // Foundations may sink into the terrain; only the part above ground must be clear.
        bounds.lo[1] = @max(bounds.lo[1], 0.05);
        if (bounds.hi[1] <= bounds.lo[1]) bounds.hi[1] = bounds.lo[1] + 0.1;
        for (0..3) |k| {
            result.center[k] = result.origin[k] + (bounds.lo[k] + bounds.hi[k]) / 2;
            result.half[k] = (bounds.hi[k] - bounds.lo[k]) / 2;
        }
    } else {
        result.half = if (e.item == .crate) sb.crateHalf() else Sandbox.halve(kitDevice(e.item, "x").size);
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
    result.valid = result.valid and !sb.physics.overlapsBox(result.center, clear) and !inside_player;
    // Nothing is built inside a shrine: its crates and plates are the puzzle.
    for (0..Sandbox.shrine_count) |k| if (sb.shrines[k].machine != null and sb.insideShrine(k, result.center)) {
        result.valid = false;
    };
    if (blueprintOf(sb, e)) |bp| {
        for (bp.devices[0..bp.device_count]) |d| {
            if (d.kind == .sap_tap and sb.sapAttachment(R.add(result.origin, R.rotate(Sandbox.yawRotation(st.yaw), d.offset))) == null) result.valid = false;
        }
    } else if ((e.item == .sap_tap or e.item == .root_sender or e.item == .root_listener) and sb.sapAttachment(result.center) == null) result.valid = false;
    return result;
}

pub fn place(sb: *Sandbox, p: Preview) !void {
    if (blueprintOf(sb, p.entry)) |bp| {
        if (p.entry == .kit and sb.wallet.kits[@intFromEnum(p.entry.kit)] == 0) return sb.say("no {s} kits: buy one at a market", .{entryName(sb, p.entry)});
        const m = sb.spawnMachine(null, bp.*, p.origin, p.yaw, false) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)});
        if (p.entry == .kit) {
            sb.wallet.kits[@intFromEnum(p.entry.kit)] -= 1;
            sb.machines[m].kit = p.entry.kit;
        }
        return sb.say("placed {s}", .{entryName(sb, p.entry)});
    }
    const item = p.entry.item;
    switch (item) {
        .crate => _ = sb.spawnCrate(p.center, .{ 0, 0, 0 }) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)}),
        .powered_door, .elevator, .rover, .sap_beacon => unreachable,
        .generator, .sap_tap, .button, .latch, .logic_or, .lamp, .transmitter, .receiver, .root_sender, .root_listener => {
            sb.tools.kit_serial += 1;
            var id_buffer: [Blueprint.id_len]u8 = undefined;
            const tag = switch (item) {
                .generator => "gen",
                .logic_or => "or",
                .transmitter => "tx",
                .receiver => "rx",
                .root_sender => "song",
                .root_listener => "hear",
                else => @tagName(item),
            };
            const id = std.fmt.bufPrint(&id_buffer, "{s}{d}", .{ tag, sb.tools.kit_serial }) catch unreachable;
            _ = sb.addWorkshopDevice(kitDevice(item, id), p.center) catch |err| return sb.say("cannot place: {s}", .{@errorName(err)});
        },
    }
    sb.say("placed {s}", .{itemName(item)});
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
            if (placed.shrine != null) return sb.say("shrines are part of the Rootdeep", .{});
            if (placed.workshop) {
                const name = placed.blueprint.devices[d.device].id;
                sb.removeWorkshopDevice(d) catch |err| return sb.say("cannot remove: {s}", .{@errorName(err)});
                sb.say("removed {s}", .{std.mem.sliceTo(&name, 0)});
            } else removeMachine(sb, d.machine);
        },
        .structure => |m| removeMachine(sb, m),
        .bridge => |i| {
            if (!sb.closeBridge(i)) return sb.say("bridge closed: removed once traffic clears", .{});
            sb.say("removed bridge", .{});
        },
        .relic, .stall, .none => sb.say("nothing to remove", .{}),
    }
}

fn removeMachine(sb: *Sandbox, m: u8) void {
    if (sb.seated == m) return sb.say("leave the vehicle first", .{});
    if (sb.machines[m].shrine != null) return sb.say("shrines are part of the Rootdeep", .{});
    var name: [Blueprint.name_len]u8 = sb.machines[m].blueprint.name_buffer;
    const kit = sb.machines[m].kit;
    sb.removeMachine(m);
    if (kit) |ware| {
        sb.wallet.kits[@intFromEnum(ware)] +|= 1;
        return sb.say("removed {s}: kit returned", .{std.mem.sliceTo(&name, 0)});
    }
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
    if (sb.machines[to.machine].shrine != null) return sb.say("shrine machines cannot be rewired", .{});
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

/// Steps the aimed transmitter, receiver, or Rootsong device through channels 1..max, wrapping. The machine
/// reads the new channel on its next step.
pub fn adjustChannel(sb: *Sandbox, delta: i32) void {
    if (sb.target != .device) return;
    const d = sb.target.device;
    const def = &sb.machines[d.machine].blueprint.devices[d.device];
    if (sb.machines[d.machine].shrine != null) return;
    if (def.channel == 0) return sb.say("only transmitters, receivers, and root devices have channels", .{});
    const count: i32 = Device.max_channels;
    def.channel = @intCast(@mod(@as(i32, def.channel) - 1 + delta, count) + 1);
    sb.say("{s} channel {d}", .{ def.name(), def.channel });
}

/// Copies the aimed machine's blueprint (with its current wiring) into the prefab library,
/// selects it in the build palette, and flags it for export. Loose workshop devices are
/// recentred so the copy's lowest device sits on the placement origin.
pub fn capture(sb: *Sandbox) void {
    const m: u8 = switch (sb.target) {
        .device => |d| d.machine,
        .structure => |x| x,
        else => return sb.say("aim at a machine to capture it", .{}),
    };
    const placed = &sb.machines[m];
    if (placed.kit != null) return sb.say("market designs cannot be captured", .{});
    if (placed.shrine != null) return sb.say("shrines cannot be captured", .{});
    var bp = placed.blueprint;
    if (placed.workshop) recenter(&bp);
    const base_full = if (placed.workshop) "circuit" else placed.blueprint.name();
    const base = base_full[0..@min(base_full.len, Blueprint.name_len - 6)];
    var name_buffer: [Blueprint.name_len]u8 = undefined;
    // Pick the first free "<base>_<n>" name.
    while (true) {
        sb.tools.prefab_serial += 1;
        const name = std.fmt.bufPrint(&name_buffer, "{s}_{d}", .{ base, sb.tools.prefab_serial }) catch unreachable;
        const taken = for (sb.prefabs[0..sb.prefab_count]) |*existing| {
            if (std.mem.eql(u8, existing.name(), name)) break true;
        } else false;
        if (taken) continue;
        bp.setName(name) catch unreachable;
        break;
    }
    const index = sb.addPrefab(bp) catch |err| return sb.say("cannot capture: {s}", .{@errorName(err)});
    sb.exported = index;
    sb.tools.tool = .build;
    sb.tools.wire_from = null;
    sb.tools.slot = builtin_count + Market.ware_count + index;
    sb.say("captured {s}: now in the build palette", .{sb.prefabs[index].name()});
}

fn recenter(bp: *Blueprint) void {
    var center: [2]f32 = .{ 0, 0 };
    var bottom = std.math.inf(f32);
    const n: f32 = @floatFromInt(bp.device_count);
    for (bp.devices[0..bp.device_count]) |d| {
        center[0] += d.offset[0] / n;
        center[1] += d.offset[2] / n;
        bottom = @min(bottom, d.offset[1] - d.size[1] / 2);
    }
    for (bp.devices[0..bp.device_count]) |*d| {
        d.offset[0] = snap(d.offset[0] - center[0]);
        d.offset[2] = snap(d.offset[2] - center[1]);
        d.offset[1] -= bottom;
    }
}

pub const PanelLine = struct {
    text: [64]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const PanelLine) []const u8 {
        return self.text[0..self.len];
    }

    pub fn set(self: *PanelLine, comptime fmt: []const u8, args: anytype) void {
        const written: []const u8 = std.fmt.bufPrint(&self.text, fmt, args) catch &self.text;
        self.len = written.len;
    }
};

/// Inspection text for the aimed machine: identity, power networks, device outputs, wires.
/// Returns the number of lines written (the last says how many were cut when full).
pub fn inspect(sb: *const Sandbox, lines: []PanelLine) usize {
    const m: u8 = switch (sb.target) {
        .device => |d| d.machine,
        .structure => |x| x,
        else => return 0,
    };
    const placed = &sb.machines[m];
    const bp = &placed.blueprint;
    const machine = &placed.machine;
    var n: usize = 0;
    const Writer = struct {
        fn line(out: []PanelLine, count: *usize, comptime fmt: []const u8, args: anytype) void {
            if (count.* >= out.len) return;
            const text = std.fmt.bufPrint(&out[count.*].text, fmt, args) catch out[count.*].text[0..];
            out[count.*].len = text.len;
            count.* += 1;
        }
    };
    Writer.line(lines, &n, "{s}  SLOT {d}  DEVICES {d}  WIRES {d}", .{ bp.name(), m, bp.device_count, bp.wire_count });
    for (machine.networks[0..machine.network_count], 0..) |net, i| {
        Writer.line(lines, &n, "NET {d}  SUPPLY {d:.0} W  DEMAND {d:.0} W  {d:.0}%", .{ i, net.supply, net.demand, net.satisfaction * 100 });
    }
    const reserve = @min(bp.wire_count, 4);
    var shown: usize = 0;
    for (bp.devices[0..bp.device_count], 0..) |*d, i| {
        if (n + reserve + 1 >= lines.len) break;
        var values: [48]u8 = undefined;
        var used: usize = 0;
        for (Device.ports(d.kind), 0..) |port, k| {
            if (port.direction != .output) continue;
            const text = std.fmt.bufPrint(values[used..], " {s} {d:.2}", .{ port.name, machine.outputs[i][k] }) catch break;
            used += text.len;
        }
        if (d.channel != 0) {
            const text = std.fmt.bufPrint(values[used..], " ch {d}", .{d.channel}) catch "";
            used += text.len;
        }
        if (d.kind == .script) {
            const text = std.fmt.bufPrint(values[used..], " {s}{s}", .{ d.scriptName(), if (sb.scripts.find(d.scriptName()) == null) " missing" else "" }) catch "";
            used += text.len;
        }
        if (d.kind == .root_sender or d.kind == .root_listener) {
            const text = if (machine.root_group[i]) |g| std.fmt.bufPrint(values[used..], " root group {d}", .{g}) catch "" else std.fmt.bufPrint(values[used..], " unrooted", .{}) catch "";
            used += text.len;
        }
        if (d.kind == .sap_tap) {
            if (sb.tap_links[m][i]) |link| {
                const text = std.fmt.bufPrint(values[used..], " tree {d} node {d}", .{ link.tree, link.node }) catch "";
                used += text.len;
            } else {
                const text = std.fmt.bufPrint(values[used..], " detached", .{}) catch "";
                used += text.len;
            }
        }
        Writer.line(lines, &n, "{s} {s}:{s}", .{ d.name(), @tagName(d.kind), values[0..used] });
        shown += 1;
    }
    for (bp.wires[0..bp.wire_count], 0..) |w, i| {
        if (n + 1 >= lines.len and i + 1 < bp.wire_count) {
            Writer.line(lines, &n, "... {d} MORE WIRES", .{bp.wire_count - i});
            break;
        }
        const a = bp.devices[w.from.device];
        const b = bp.devices[w.to.device];
        Writer.line(lines, &n, "{s}.{s} > {s}.{s}", .{ a.name(), Device.ports(a.kind)[w.from.port].name, b.name(), Device.ports(b.kind)[w.to.port].name });
    }
    if (shown < bp.device_count and n < lines.len) Writer.line(lines, &n, "... {d} MORE DEVICES", .{bp.device_count - shown});
    return n;
}

/// One HUD line describing the active tool.
pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const st = sb.tools;
    return switch (st.tool) {
        .hands => "",
        .bridge => @import("BridgeTool.zig").hint(sb, buffer),
        .build => switch (current(sb)) {
            .kit => |ware| std.fmt.bufPrint(buffer, "BUILD {s} KIT  {d} HELD  TAB NEXT  T TURN  CLICK PLACE", .{ entryName(sb, current(sb)), sb.wallet.kits[@intFromEnum(ware)] }) catch buffer,
            else => std.fmt.bufPrint(buffer, "BUILD {s}  TAB NEXT  T TURN  CLICK PLACE  RMB REMOVE  P CAPTURE", .{entryName(sb, current(sb))}) catch buffer,
        },
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
    if (st.tool == .bridge) return @import("BridgeTool.zig").publish(sb, out, start);
    if (st.tool == .build) if (st.preview) |p| {
        const tint: [4]f32 = if (p.valid) .{ 0.35, 1.0, 0.45, 1 } else .{ 1.0, 0.3, 0.25, 1 };
        if (blueprintOf(sb, p.entry)) |bp| {
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
            out[n] = if (p.entry.item == .crate)
                .{ .mesh = sb.catalog.content.crate, .transform = .{ .position = p.center }, .tint = tint }
            else
                .{ .mesh = block, .transform = .{ .position = p.center }, .tint = tint, .size = kitDevice(p.entry.item, "x").size };
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
    try sb.init(std.testing.allocator, 310399555161, catalog, camera);
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
    sb.tools.slot = @intFromEnum(item);
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
    defer sb.deinit();
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
    var rendered: [256]@import("../world/World.zig").Prop = undefined;
    const lit_count = sb.publishProps(&rendered);
    var lit_found = false;
    for (rendered[0..lit_count]) |prop| if (std.meta.eql(prop.transform.position, lamp_position)) {
        try std.testing.expectEqual(@as(f32, 2), prop.tint[3]);
        lit_found = true;
    };
    try std.testing.expect(lit_found);

    // The whole placed circuit, its wires, and the latch state survive a reload.
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    var other_camera: Camera = .{};
    var other: Sandbox = undefined;
    try other.init(std.testing.allocator, sb.seed, &catalog, &other_camera);
    defer other.deinit();
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
    const dark_count = sb.publishProps(&rendered);
    var dark_found = false;
    for (rendered[0..dark_count]) |prop| if (std.meta.eql(prop.transform.position, lamp_position)) {
        try std.testing.expectEqual(@as(f32, 1), prop.tint[3]);
        dark_found = true;
    };
    try std.testing.expect(dark_found);
    // Re-tagged bodies still pick the right device.
    try aimDevice(&sb, &camera, .{ .machine = w, .device = 2 });
}

test "prefabs snap and rotate, overlapping placements are refused, and removal frees the slot" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
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
    sb.tools.slot = @intFromEnum(Item.powered_door);
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

/// Builds generator → lamp power and button → latch → lamp signal in the workshop directly.
fn benchCircuit(sb: *Sandbox, dx: f32) ![4]Sandbox.DeviceRef {
    const kits = [_]Item{ .generator, .button, .latch, .lamp };
    var refs: [4]Sandbox.DeviceRef = undefined;
    for (kits, 0..) |item, i| {
        const x = Sandbox.spawn[0] + dx + @as(f32, @floatFromInt(i)) * 1.5;
        const z = Sandbox.spawn[2] - 3;
        var id: [8]u8 = undefined;
        refs[i] = try sb.addWorkshopDevice(kitDevice(item, try std.fmt.bufPrint(&id, "k{d}", .{i})), .{ x, Terrain.surface(sb.seed, x, z).height + 0.7, z });
    }
    const placed = &sb.machines[refs[0].machine];
    try placed.blueprint.connect(.{ .device = refs[0].device, .port = 0 }, .{ .device = refs[3].device, .port = 0 });
    try placed.blueprint.connect(.{ .device = refs[1].device, .port = 0 }, .{ .device = refs[2].device, .port = 0 });
    try placed.blueprint.connect(.{ .device = refs[2].device, .port = 1 }, .{ .device = refs[3].device, .port = 1 });
    placed.machine.reconfigure();
    return refs;
}

test "capture a circuit as a prefab, place an independent copy, inspect it, and keep prefabs in saves" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const refs = try benchCircuit(&sb, 3);
    try tick(&sb, &camera, .{ .select_tool = 2 });
    try aimDevice(&sb, &camera, refs[3]);
    try tick(&sb, &camera, .{ .capture = true });
    try std.testing.expectEqual(@as(usize, 1), sb.prefab_count);
    try std.testing.expectEqual(@as(?usize, 0), sb.exported);
    try std.testing.expectEqualStrings("circuit_1", sb.prefabs[0].name());
    try std.testing.expect(current(&sb) == .prefab);
    // Recentered: the lowest device rests on the origin.
    var bottom = std.math.inf(f32);
    for (sb.prefabs[0].devices[0..4]) |d| bottom = @min(bottom, d.offset[1] - d.size[1] / 2);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bottom, 1e-5);

    // Place a copy elsewhere: a separate machine with its own generator and wiring.
    const before = sb.machineCount();
    const x = Sandbox.spawn[0] + 4;
    const z = Sandbox.spawn[2] - 9;
    aim(&camera, .{ x, Terrain.surface(sb.seed, x, z).height, z });
    try tick(&sb, &camera, .{});
    try std.testing.expect(sb.tools.preview.?.valid);
    try tick(&sb, &camera, .{ .interact = true });
    try std.testing.expectEqual(before + 1, sb.machineCount());
    const copy: u8 = for (sb.machines, 0..) |placed, i| {
        if (placed.active and std.mem.eql(u8, placed.blueprint.name(), "circuit_1")) break @intCast(i);
    } else return error.TestUnexpectedResult;
    try std.testing.expect(!sb.machines[copy].workshop);
    try std.testing.expectEqual(@as(usize, 3), sb.machines[copy].blueprint.wire_count);

    // Walk up to the copy and press its button: only the copy's lamp lights.
    try tick(&sb, &camera, .{ .select_tool = 1 });
    sb.player.feet = .{ x, Terrain.surface(sb.seed, x, z + 3).height, z + 3 };
    camera.position = sb.player.eye();
    try aimDevice(&sb, &camera, .{ .machine = copy, .device = 1 });
    try tick(&sb, &camera, .{ .interact = true });
    for (0..5) |_| try tick(&sb, &camera, .{});
    try std.testing.expectEqual(@as(f32, 1), sb.machines[copy].machine.outputs[3][2]);
    try std.testing.expectEqual(@as(f32, 0), sb.machines[refs[0].machine].machine.outputs[3][2]);

    // Inspection reports supply and demand and lists devices and wires.
    try aimDevice(&sb, &camera, .{ .machine = copy, .device = 3 });
    var lines: [14]PanelLine = @splat(.{});
    const count = inspect(&sb, &lines);
    try std.testing.expect(count >= 1 + 1 + 4 + 3);
    try std.testing.expectEqualStrings("NET 0  SUPPLY 200 W  DEMAND 25 W  100%", lines[1].slice());
    try std.testing.expect(std.mem.indexOf(u8, lines[5].slice(), "lit 1.00") != null);

    // Rewiring the copy leaves the prefab intact.
    _ = sb.machines[copy].blueprint.disconnectInputs(3);
    try std.testing.expectEqual(@as(usize, 3), sb.prefabs[0].wire_count);

    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    var other_camera: Camera = .{};
    var other: Sandbox = undefined;
    try other.init(std.testing.allocator, sb.seed, &catalog, &other_camera);
    defer other.deinit();
    try other.restore(std.testing.allocator, bytes, &other_camera);
    try std.testing.expectEqual(@as(usize, 1), other.prefab_count);
    try std.testing.expectEqualStrings("circuit_1", other.prefabs[0].name());
    try std.testing.expectEqual(@as(usize, 1), other.machines[copy].blueprint.wire_count);
}

test "a button on one machine lights a lamp on another over a bus channel, and channels persist" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    // Sender: workshop button → latch → transmitter.
    const kits = [_]Item{ .button, .latch, .transmitter };
    var refs: [3]Sandbox.DeviceRef = undefined;
    for (kits, 0..) |item, i| {
        const x = Sandbox.spawn[0] + 3 + @as(f32, @floatFromInt(i)) * 1.5;
        const z = Sandbox.spawn[2] - 3;
        var id: [8]u8 = undefined;
        refs[i] = try sb.addWorkshopDevice(kitDevice(item, try std.fmt.bufPrint(&id, "s{d}", .{i})), .{ x, Terrain.surface(sb.seed, x, z).height + 0.8, z });
    }
    const w = refs[0].machine;
    try sb.machines[w].blueprint.connect(.{ .device = 0, .port = 0 }, .{ .device = 1, .port = 0 });
    try sb.machines[w].blueprint.connect(.{ .device = 1, .port = 1 }, .{ .device = 2, .port = 0 });
    sb.machines[w].machine.reconfigure();
    // Receiver: a separate placed machine with its own generator.
    const lamp_bp = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"beacon","devices":[
        \\ {"id":"gen","kind":"generator","watts":50,"offset":[0,0.5,0]},{"id":"rx","kind":"receiver","channel":1,"offset":[1,0.2,0]},{"id":"lamp","kind":"lamp","watts":10,"offset":[2,0.6,0]}],
        \\ "wires":[["gen.power","lamp.power"],["rx.out","lamp.on"]]}
    );
    const bx = Sandbox.spawn[0] + 3;
    const bz = Sandbox.spawn[2] - 7;
    const beacon = try sb.spawnMachine(null, lamp_bp, sb.groundOrigin(&lamp_bp, bx, bz, 0), 0, false);

    // Stand beside the sender so nothing (such as a relic) sits between eye and button.
    const bp0 = sb.devicePosition(refs[0]);
    sb.player.feet = .{ bp0[0] + 1.5, Terrain.surface(sb.seed, bp0[0] + 1.5, bp0[2] + 1.5).height, bp0[2] + 1.5 };
    camera.position = sb.player.eye();
    try aimDevice(&sb, &camera, refs[0]);
    try tick(&sb, &camera, .{ .interact = true });
    for (0..6) |_| try tick(&sb, &camera, .{});
    try std.testing.expectEqual(@as(f32, 1), sb.bus[0]);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[beacon].machine.outputs[2][2]);

    // Retune the transmitter: the beacon hears nothing and goes dark.
    try aimDevice(&sb, &camera, refs[2]);
    try tick(&sb, &camera, .{ .channel_up = true });
    try std.testing.expectEqual(@as(u16, 2), sb.machines[w].blueprint.devices[2].channel);
    for (0..4) |_| try tick(&sb, &camera, .{});
    try std.testing.expectEqual(@as(f32, 0), sb.machines[beacon].machine.outputs[2][2]);
    try tick(&sb, &camera, .{ .channel_down = true });
    try tick(&sb, &camera, .{ .channel_down = true });
    try std.testing.expectEqual(@as(u16, Device.max_channels), sb.machines[w].blueprint.devices[2].channel);

    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    var other_camera: Camera = .{};
    var other: Sandbox = undefined;
    try other.init(std.testing.allocator, sb.seed, &catalog, &other_camera);
    defer other.deinit();
    try other.restore(std.testing.allocator, bytes, &other_camera);
    try std.testing.expectEqual(@as(u16, Device.max_channels), other.machines[other.workshop.?].blueprint.devices[2].channel);
}

test "sap beacon palette placement requires nearby wood and produces a powered inspectable machine" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.player.mode = .fly;
    selectTool(&sb, .build);
    sb.tools.slot = @intFromEnum(Item.sap_beacon);
    const origin = sb.treeOrigin(1);
    const x = origin[0] + sb.tree(1).genome.base_radius + 2;
    const z = origin[2];
    const y = Terrain.surface(sb.seed, x, z).height;
    camera.position = @import("mach").math.vec3(x, y + 5, z - 8);
    aim(&camera, .{ x, y, z });
    try tick(&sb, &camera, .{});
    try std.testing.expect(sb.tools.preview != null and sb.tools.preview.?.valid);
    const before = sb.machineCount();
    try tick(&sb, &camera, .{ .interact = true });
    try std.testing.expectEqual(before + 1, sb.machineCount());
    for (0..4) |_| try tick(&sb, &camera, .{});
    const m: u8 = @intCast(before);
    try std.testing.expectEqual(@as(u8, 1), sb.tap_links[m][0].?.tree);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[m].machine.outputs[2][2]);
    sb.target = .{ .device = .{ .machine = m, .device = 0 } };
    var lines: [16]PanelLine = undefined;
    const count = inspect(&sb, &lines);
    var named_tree = false;
    for (lines[0..count]) |line| if (std.mem.indexOf(u8, line.slice(), "tree 1") != null) {
        named_tree = true;
    };
    try std.testing.expect(named_tree);
    // The same palette item is invalid away from wood, even over otherwise clear terrain.
    const far_x = x + 45;
    const far_y = Terrain.surface(sb.seed, far_x, z).height;
    camera.position = @import("mach").math.vec3(far_x, far_y + 5, z - 8);
    aim(&camera, .{ far_x, far_y, z });
    try tick(&sb, &camera, .{});
    try std.testing.expect(sb.tools.preview != null and !sb.tools.preview.?.valid);
}

test "place a rover on an elevated plaza and reject unsupported placement at its edge" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const plaza = catalog.district.nodes[1].position;
    sb.player.mode = .fly;
    camera.position = @import("mach").math.vec3(plaza[0], plaza[1] + 9, plaza[2] - 4);
    selectTool(&sb, .build);
    sb.tools.slot = @intFromEnum(Item.rover);
    aim(&camera, plaza);
    const p = preview(&sb, camera).?;
    try std.testing.expect(p.valid);
    try std.testing.expect(p.origin[1] > plaza[1] + 1);
    const count = sb.machineCount();
    try place(&sb, p);
    try std.testing.expectEqual(count + 1, sb.machineCount());
    for (0..120) |_| try tick(&sb, &camera, .{});
    const vehicle = sb.machines[count].vehicle.?;
    try std.testing.expectApproxEqAbs(plaza[1] + 1.09, sb.physics.rigidPose(vehicle.rigid).?.position[1], 0.15);
    for (vehicle.state[0..4]) |wheel| try std.testing.expect(wheel.contact);
    camera.position = @import("mach").math.vec3(plaza[0] + 19.5, plaza[1] + 8, plaza[2]);
    aim(&camera, R.add(plaza, .{ 19.5, 0, 0 }));
    try std.testing.expect(!preview(&sb, camera).?.valid);
}

test "bridge tool selects two visible plaza anchors, builds, cancels, and removes" {
    const Bridge = @import("BridgeTool.zig");
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testWorld(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.player.mode = .fly;
    selectTool(&sb, .bridge);
    for ([_]u8{ 0, 3 }) |node| {
        const point = Bridge.anchor(catalog.district.nodes[node]);
        camera.position = @import("mach").math.vec3(point[0], point[1] + 8, point[2] - 8);
        aim(&camera, point);
        try Bridge.update(&sb, camera, true, false);
    }
    try std.testing.expectEqualDeep(@import("../procedural/District.zig").Edge{ .a = 0, .b = 3 }, sb.bridges[0].?.edge);
    try std.testing.expect(sb.tools.bridge_from == null);
    try Bridge.update(&sb, camera, true, false);
    try std.testing.expectEqual(@as(?u8, 3), sb.tools.bridge_from);
    const source = Bridge.anchor(catalog.district.nodes[3]);
    camera.position = @import("mach").math.vec3(source[0], source[1] + 0.12, source[2]);
    aim(&camera, Bridge.anchor(catalog.district.nodes[0]));
    try std.testing.expectEqual(@as(?u8, 0), Bridge.aimedAnchor(&sb, camera));
    try Bridge.update(&sb, camera, false, true);
    try std.testing.expect(sb.tools.bridge_from == null);
    sb.target = .{ .bridge = 0 };
    try Bridge.update(&sb, camera, false, true);
    try std.testing.expect(sb.bridges[0] == null);
}
