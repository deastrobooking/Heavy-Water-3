//! A short guided start for building, per player: each tip appears when the player has done the
//! thing the previous one taught (place a block, fill a box, change style, lay a prefab). Session
//! only; a player who already knows simply does things in any order and the tips catch up.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");

pub const Step = enum(u8) { place, box, style, prefab, done };

pub const State = struct {
    step: [Sandbox.max_players]Step = @splat(.place),
};

fn text(step: Step) []const u8 {
    return switch (step) {
        .place => "BUILD: aim at the ground and click (pad RT) to place a block; right click (RB) removes it",
        .box => "TIP: hold Shift (pad LT) and click two corners to fill a whole box",
        .style => "TIP: Shift+Tab (pad LT + right) changes style: castle, dungeon, eco city, farm, platformer",
        .prefab => "TIP: Tab past the shapes for ready-made pieces like the tower; the farm style has seeds",
        .done => "You know the basics. Shift+T restyles a box, Shift+P copies one to paste",
    };
}

/// A player started building: show the tip they are on.
pub fn intro(sb: *Sandbox, slot: usize) void {
    const step = sb.build_tips.step[slot];
    if (step != .done) sb.sayTo(slot, "{s}", .{text(step)});
}

/// The player did `event`; if it was the lesson of the moment, move on and show the next tip.
pub fn advance(sb: *Sandbox, slot: usize, event: Step) void {
    const step = &sb.build_tips.step[slot];
    if (step.* != event or step.* == .done) return;
    step.* = @enumFromInt(@intFromEnum(step.*) + 1);
    sb.sayTo(slot, "{s}", .{text(step.*)});
}

test "every tip fits the notice line" {
    for (std.enums.values(Step)) |s| try std.testing.expect(text(s).len + "P4: ".len <= 96);
}
