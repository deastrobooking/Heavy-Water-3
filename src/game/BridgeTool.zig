//! Two-click construction between stable district plazas. Validation drives both preview color
//! and commit; only player-added spans can be removed. No new GPU resources are needed.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const District = @import("../procedural/District.zig");
const R = @import("../physics/Rotation.zig");
pub fn anchor(node: District.Node) R.Vec3 {
    return R.add(node.position, .{ 0, 1.5, 0 });
}

pub fn aimedAnchor(sb: *const Sandbox, camera: Camera) ?u8 {
    const eye: R.Vec3 = .{ camera.position.x(), camera.position.y(), camera.position.z() };
    const f = camera.forward();
    const direction: R.Vec3 = .{ f.x(), f.y(), f.z() };
    var nearest: f32 = 1000;
    var result: ?u8 = null;
    for (sb.catalog.district.nodes, 0..) |node, i| {
        // A source marker beside the player's eyes must not mask a distant destination.
        if (sb.tools.bridge_from == @as(u8, @intCast(i))) continue;
        const delta = R.sub(anchor(node), eye);
        const along = R.dot(delta, direction);
        if (along < 0 or along > nearest) continue;
        const radius = @max(2.5, along * 0.008);
        if (R.length(R.sub(delta, R.scale(direction, along))) > radius) continue;
        if (sb.physics.castRay(eye, direction, along, .none)) |hit| if (hit.distance < along - radius) continue;
        nearest = along;
        result = @intCast(i);
    }
    return result;
}

pub fn candidate(sb: *const Sandbox) ?District.Edge {
    return .{ .a = sb.tools.bridge_from orelse return null, .b = sb.tools.bridge_hover orelse return null };
}

pub fn update(sb: *Sandbox, camera: Camera, primary: bool, secondary: bool) !void {
    sb.tools.bridge_hover = aimedAnchor(sb, camera);
    if (secondary) {
        if (sb.tools.bridge_from != null) {
            sb.tools.bridge_from = null;
            sb.say("bridge canceled", .{});
        } else if (sb.target == .bridge) {
            sb.removeBridge(sb.target.bridge);
            sb.say("removed bridge", .{});
        } else sb.say("aim at your bridge to remove it", .{});
        return;
    }
    if (!primary) return;
    const node = sb.tools.bridge_hover orelse return sb.say("aim at a plaza marker", .{});
    if (sb.tools.bridge_from == null) {
        sb.tools.bridge_from = node;
        return sb.say("plaza {d}: choose a destination", .{node});
    }
    _ = sb.addBridge(candidate(sb).?) catch |err| return sb.say("{s}", .{reason(err)});
    sb.tools.bridge_from = null;
    sb.say("bridge built", .{});
}

fn reason(err: anyerror) []const u8 {
    return switch (err) {
        error.DuplicateBridge => "ROAD ALREADY EXISTS",
        error.BridgeTooSteep => "ROAD TOO STEEP: MAX 6%",
        error.TreeClearance => "TRUNK BLOCKS THIS ROUTE",
        error.PlazaClearance => "ANOTHER PLAZA BLOCKS THIS ROUTE",
        error.MarketClearance => "MARKET BAY BLOCKS THIS APPROACH",
        error.JunctionClearance => "ROAD APPROACHES TOO CLOSE TOGETHER",
        error.RoadCrossing => "ROUTE CROSSES ANOTHER ROAD",
        error.GroundClearance => "NOT ENOUGH SPACE ABOVE GROUND",
        error.TooManyBridges => "BRIDGE LIMIT REACHED: REMOVE A SPAN",
        error.InvalidSpan => "SPAN TOO SHORT OR TOO LONG",
        error.InvalidAnchor => "CHOOSE TWO DIFFERENT PLAZAS",
        error.OutOfMemory => "NOT ENOUGH MEMORY TO BUILD",
        else => "BRIDGE CANNOT BE BUILT",
    };
}

pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    if (sb.tools.bridge_from) |from| {
        if (sb.tools.bridge_hover) |to| {
            sb.validateBridge(.{ .a = from, .b = to }) catch |err| return reason(err);
            return std.fmt.bufPrint(buffer, "BRIDGE {d} > {d}  CLICK BUILD  RMB CANCEL", .{ from, to }) catch buffer;
        }
        return std.fmt.bufPrint(buffer, "FROM PLAZA {d}  AIM AT DESTINATION  RMB CANCEL", .{from}) catch buffer;
    }
    if (sb.tools.bridge_hover) |node| return std.fmt.bufPrint(buffer, "PLAZA {d}  CLICK START BRIDGE", .{node}) catch buffer;
    return "BRIDGE: CLICK TWO PLAZA MARKERS  RMB REMOVE YOUR SPAN";
}

pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    var n = start;
    for (sb.catalog.district.nodes, 0..) |node, i| {
        if (n == out.len) return n;
        const selected = sb.tools.bridge_from == @as(u8, @intCast(i));
        out[n] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = anchor(node) }, .size = .{ 1.5, 2.5, 1.5 }, .tint = if (selected) .{ 1, 0.7, 0.15, 2 } else .{ 0.2, 0.8, 0.95, 2 } };
        n += 1;
    }
    if (candidate(sb)) |edge| {
        if (edge.a == edge.b) return n;
        const valid = if (sb.validateBridge(edge)) |_| true else |_| false;
        const tint: [4]f32 = if (valid) .{ 0.3, 0.95, 0.4, 1 } else .{ 1, 0.25, 0.2, 1 };
        const parts = District.bridgeParts(District.span(&sb.catalog.district, edge)) catch return n;
        // Outline the road with the deck and rails; do not obscure the world with cable previews.
        for (parts.slice()) |p| {
            if (!p.solid) continue;
            if (n == out.len) return n;
            out[n] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = p.center }, .size = p.size, .rotation = p.rotation, .tint = tint };
            n += 1;
        }
    }
    return n;
}
