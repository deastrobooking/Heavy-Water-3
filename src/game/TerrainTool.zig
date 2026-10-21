//! The sculpt tool: hold the primary button to shape the ground under the crosshair. It drives
//! `TerrainBrush` on the world's `TerrainEdit` layer and owns only the brush choice and stroke.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Sandbox = @import("Sandbox.zig");
const Camera = @import("../world/Camera.zig");
const TerrainBrush = @import("../procedural/TerrainBrush.zig");
const CityHeightmaps = @import("../procedural/CityHeightmaps.zig");
const Terrain = @import("../procedural/Terrain.zig");
const World = @import("../world/World.zig");

pub const reach: f32 = 60;
/// Sculpting stays this far from a cave mouth, so the cave's opening in the mesh keeps matching.
pub const cave_clearance: f32 = 60;
/// Fixed ticks between dabs while the button is held.
const dab_interval = 6;

pub const State = struct {
    kind: TerrainBrush.Kind = .raise,
    radius: f32 = 8,
    stroking: bool = false,
    ticks: u32 = 0,
    /// Where the crosshair meets the ground, for the cursor ring and the dab.
    aim: ?[3]f32 = null,
    /// Height the level brush pulls toward, fixed where the stroke began.
    target: f32 = 0,
};

/// Whether the ground at (x, z) may be reshaped, with the reason when it may not.
pub fn refusal(sb: *const Sandbox, x: f32, z: f32, radius: f32) ?[]const u8 {
    for (sb.caves.systems[0..sb.caves.count]) |system| {
        if (std.math.hypot(system.entrance[0] - x, system.entrance[2] - z) < cave_clearance + radius) return "too close to a cave mouth";
    }
    return null;
}

pub fn update(sb: *Sandbox, camera: Camera, actions: Sandbox.Actions) !void {
    const st = &sb.tools.terrain;
    if (actions.next_item) {
        st.kind = @enumFromInt((@intFromEnum(st.kind) + 1) % enum_compat.fields(TerrainBrush.Kind).len);
        sb.say("brush: {s}", .{@tagName(st.kind)});
    }
    if (actions.channel_up) st.radius = @min(TerrainBrush.max_radius, st.radius + 2);
    if (actions.channel_down) st.radius = @max(TerrainBrush.min_radius, st.radius - 2);
    if (actions.secondary and !sb.trigger.fire) {
        if (sb.terrain_edit.undo()) sb.say("sculpt undone", .{}) else sb.say("nothing to undo", .{});
    }
    if (actions.rotate) {
        if (sb.terrain_edit.redo()) sb.say("sculpt redone", .{}) else sb.say("nothing to redo", .{});
    }

    const f = camera.forward();
    const eye: [3]f32 = .{ camera.position.x(), camera.position.y(), camera.position.z() };
    st.aim = if (sb.physics.castRay(eye, .{ f.x(), f.y(), f.z() }, reach, .none)) |hit| hit.point else null;

    if (!sb.trigger.fire or st.aim == null) {
        st.stroking = false;
        return;
    }
    const aim = st.aim.?;
    if (refusal(sb, aim[0], aim[2], st.radius)) |why| {
        if (!st.stroking) sb.say("{s}", .{why});
        st.stroking = true; // say it once per press
        return;
    }
    if (!st.stroking) {
        st.stroking = true;
        st.ticks = 0;
        st.target = CityHeightmaps.heightAt(sb.seed, aim[0], aim[2]);
        sb.terrain_edit.beginStroke();
    }
    if (st.ticks % dab_interval == 0) {
        const strength: f32 = switch (st.kind) {
            .raise, .lower => 0.25,
            .level, .smooth => 0.35,
        };
        _ = TerrainBrush.apply(sb.terrain_edit, sb.seed, .{ .kind = st.kind, .x = aim[0], .z = aim[2], .radius = st.radius, .strength = strength, .target = st.target }) catch |err| {
            if (err == error.TerrainEditFull) sb.say("sculpt budget full: undo or flatten somewhere else", .{});
        };
    }
    st.ticks += 1;
}

pub fn hint(sb: *const Sandbox, buffer: []u8) []const u8 {
    const st = sb.tools.terrain;
    return std.fmt.bufPrint(buffer, "SCULPT {s} {d:.0} M  HOLD CLICK  TAB BRUSH  [ ] SIZE  RMB UNDO  T REDO", .{ @tagName(st.kind), st.radius }) catch buffer;
}

/// A ring of markers on the ground around the aim point, sized to the brush.
pub fn publish(sb: *const Sandbox, out: []World.Prop, start: usize) usize {
    const st = sb.tools.terrain;
    const aim = st.aim orelse return start;
    const tint: [4]f32 = switch (st.kind) {
        .raise => .{ 0.4, 1.0, 0.5, 1 },
        .lower => .{ 1.0, 0.55, 0.3, 1 },
        .level => .{ 0.5, 0.8, 1.0, 1 },
        .smooth => .{ 0.9, 0.9, 0.5, 1 },
    };
    const bad: [4]f32 = .{ 1.0, 0.3, 0.25, 1 };
    const refused = refusal(sb, aim[0], aim[2], st.radius) != null;
    const markers = 24;
    var n = start;
    for (0..markers) |i| {
        if (n == out.len) return n;
        const angle = std.math.tau * @as(f32, @floatFromInt(i)) / markers;
        const x = aim[0] + @cos(angle) * st.radius;
        const z = aim[2] + @sin(angle) * st.radius;
        const y = Terrain.surface(sb.seed, x, z).height + 0.15;
        out[n] = .{ .mesh = sb.catalog.content.block, .transform = .{ .position = .{ x, y, z } }, .tint = if (refused) bad else tint, .size = .{ 0.5, 0.3, 0.5 } };
        n += 1;
    }
    return n;
}
