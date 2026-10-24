//! The tool registry: every player tool (keys 1 to 8) as one entry with its name, number key,
//! input action, per-step update, HUD hint and select hook. `Build.update`, `Build.hint`,
//! `Build.selectTool` and the key and pad routing in `App.zig` read this table instead of
//! switching on the tool, so a new tool (or a structure tool, see
//! docs/plans/automation-and-defense.md) is one entry here plus its own file.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Camera = @import("../world/Camera.zig");
const Sandbox = @import("Sandbox.zig");
const Build = @import("Build.zig");
const Bindings = @import("Bindings.zig");
const BlockTool = @import("BlockTool.zig");
const BridgeTool = @import("BridgeTool.zig");
const TerrainTool = @import("TerrainTool.zig");
const BuildTips = @import("BuildTips.zig");
const Mining = @import("Mining.zig");

pub const Tool = Build.Tool;
pub const UpdateFn = *const fn (*Sandbox, Camera, bool, Sandbox.Actions) anyerror!void;
pub const HintFn = *const fn (*const Sandbox, []u8) []const u8;

pub const Module = struct {
    tool: Tool,
    /// Shown as "<name> tool" when selected.
    name: []const u8,
    /// The key binding that selects it.
    action: Bindings.Action,
    update: ?UpdateFn = null,
    hint: HintFn = noHint,
    /// Runs once when the tool is selected (a tip, a reset).
    selected: ?*const fn (*Sandbox) void = null,
};

/// In `Tool` enum order: a tool's number key is its index plus one (`Sandbox.Actions.select_tool`).
pub const modules = [_]Module{
    .{ .tool = .hands, .name = "hands", .action = .tool_hands },
    .{ .tool = .build, .name = "build", .action = .tool_build, .update = Build.updateBuild, .hint = Build.buildHint },
    .{ .tool = .wire, .name = "wire", .action = .tool_wire, .update = Build.updateWire, .hint = Build.wireHint },
    .{ .tool = .bridge, .name = "bridge", .action = .tool_bridge, .update = bridgeUpdate, .hint = BridgeTool.hint },
    .{ .tool = .weapon, .name = "weapon", .action = .tool_weapon, .hint = Build.weaponHint },
    .{ .tool = .terrain, .name = "terrain", .action = .tool_terrain, .update = terrainUpdate, .hint = TerrainTool.hint },
    .{ .tool = .blocks, .name = "blocks", .action = .tool_blocks, .update = blocksUpdate, .hint = BlockTool.hint, .selected = blocksSelected },
    .{ .tool = .cutter, .name = "cutter", .action = .tool_cutter, .update = Mining.cutterUpdate, .hint = Mining.cutterHint },
};

pub fn of(tool: Tool) *const Module {
    return &modules[@intFromEnum(tool)];
}

/// The tool a number key (1-based) selects.
pub fn fromNumber(n: u8) ?Tool {
    if (n == 0 or n > modules.len) return null;
    return modules[n - 1].tool;
}

/// The number key of a tool, 1-based.
pub fn number(tool: Tool) u4 {
    return @as(u4, @intFromEnum(tool)) + 1;
}

/// The tool a key-binding action selects, if it is a tool action.
pub fn fromAction(action: Bindings.Action) ?Tool {
    for (modules) |m| if (m.action == action) return m.tool;
    return null;
}

fn noHint(_: *const Sandbox, _: []u8) []const u8 {
    return "";
}

fn terrainUpdate(sb: *Sandbox, camera: Camera, _: bool, actions: Sandbox.Actions) anyerror!void {
    try TerrainTool.update(sb, camera, actions);
}

fn blocksUpdate(sb: *Sandbox, camera: Camera, primary: bool, actions: Sandbox.Actions) anyerror!void {
    try BlockTool.update(sb, camera, primary, actions, actions.box_modifier);
}

fn bridgeUpdate(sb: *Sandbox, camera: Camera, primary: bool, actions: Sandbox.Actions) anyerror!void {
    if (actions.next_item) BridgeTool.cycleStyle(sb);
    try BridgeTool.update(sb, camera, primary, actions.secondary);
}

fn blocksSelected(sb: *Sandbox) void {
    BuildTips.intro(sb, 0);
}

test "every tool has exactly one entry, in enum order, with a distinct key action" {
    try std.testing.expectEqual(enum_compat.fields(Tool).len, modules.len);
    for (modules, 0..) |m, i| {
        try std.testing.expectEqual(@as(usize, i), @intFromEnum(m.tool));
        try std.testing.expectEqualStrings(@tagName(m.tool), m.name);
        try std.testing.expectEqual(m.tool, fromNumber(number(m.tool)).?);
        try std.testing.expectEqual(m.tool, fromAction(m.action).?);
        for (modules[0..i]) |other| try std.testing.expect(other.action != m.action);
    }
    try std.testing.expect(fromNumber(0) == null);
    try std.testing.expect(fromNumber(modules.len + 1) == null);
    // The number key stays in the four bits `Actions.select_tool` has.
    try std.testing.expect(modules.len <= 15);
}
