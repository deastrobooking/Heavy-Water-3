//! Logical controller actions mapped onto Apple's standardized extended-gamepad controls.
//! Keeping the physical source indices in the preset lets players remap unfamiliar pads without
//! changing gameplay code; the platform bridge translates each discovered device into this raw
//! axis/button vocabulary.
const std = @import("std");

pub const Action = enum { jump, dodge, interact, grapple, traversal, view, sprint, fire, alt, stomp, join, respawn, up, down, left, right };
pub const action_count = @typeInfo(Action).@"enum".fields.len;
pub const axis_count = 4;
pub const physical_button_count = 16;
pub const trigger_threshold_default: f32 = 0.15;
pub const deadzone_default: f32 = 0.18;

/// Axis ids follow the standardized profile: left X/Y, then right X/Y. Button ids are documented
/// in `buttonName`; triggers remain analog in Sample and can be activated with a lighter pull.
pub const Mapping = struct {
    buttons: [action_count]u8 = .{ 0, 1, 2, 4, 3, 11, 6, 7, 5, 10, 8, 9, 12, 13, 14, 15 },
    axes: [axis_count]u8 = .{ 0, 1, 2, 3 },
    invert: [axis_count]bool = .{ false, false, false, false },
    deadzone: f32 = deadzone_default,
    trigger_threshold: f32 = trigger_threshold_default,

    pub fn validate(self: Mapping) bool {
        for (self.buttons) |physical| if (physical >= physical_button_count) return false;
        for (self.axes) |physical_axis| if (physical_axis >= axis_count) return false;
        return std.math.isFinite(self.deadzone) and self.deadzone >= 0 and self.deadzone < 0.8 and
            std.math.isFinite(self.trigger_threshold) and self.trigger_threshold >= 0 and self.trigger_threshold <= 1;
    }

    pub fn button(self: Mapping, action: Action) u8 {
        return self.buttons[@intFromEnum(action)];
    }

    pub fn isDown(self: Mapping, action: Action, buttons: u32) bool {
        return buttons & (@as(u32, 1) << @as(u5, @intCast(self.button(action)))) != 0;
    }

    pub fn axis(self: Mapping, logical: usize, raw: [axis_count]f32) f32 {
        const v = raw[self.axes[logical]] * (if (self.invert[logical]) @as(f32, -1) else 1);
        return if (std.math.isFinite(v)) std.math.clamp(v, -1, 1) else 0;
    }
};

pub fn buttonName(index: u8) []const u8 {
    return switch (index) {
        0 => "BTN 1 / A",
        1 => "BTN 2 / B",
        2 => "BTN 3 / X",
        3 => "BTN 4 / Y",
        4 => "BTN 5 / LB",
        5 => "BTN 6 / RB",
        6 => "BTN 7 / LT",
        7 => "BTN 8 / RT",
        8 => "BTN 9 / MENU",
        9 => "BTN 10 / OPT",
        10 => "BTN 11 / L3",
        11 => "BTN 12 / R3",
        12 => "BTN 13 / UP",
        13 => "BTN 14 / DOWN",
        14 => "BTN 15 / LEFT",
        15 => "BTN 16 / RIGHT",
        else => "Unknown",
    };
}

pub fn actionName(action: Action) []const u8 {
    return switch (action) {
        .jump => "JUMP",
        .dodge => "ROLL / DASH",
        .interact => "USE / MANTLE",
        .grapple => "GRAPPLE",
        .traversal => "CYCLE TRAVERSAL",
        .view => "CAMERA VIEW",
        .sprint => "SPRINT / BOOST",
        .fire => "FIRE",
        .alt => "BEAM SABER",
        .stomp => "STOMP",
        .join => "MENU / JOIN",
        .respawn => "PLAYER MENU / SELECT",
        .up => "UI UP",
        .down => "UI DOWN",
        .left => "UI LEFT",
        .right => "UI RIGHT",
    };
}

pub fn axisName(index: u8) []const u8 {
    return switch (index) {
        0 => "AXIS 1 / X",
        1 => "AXIS 2 / Y",
        2 => "AXIS 3 / RX",
        3 => "AXIS 4 / RY",
        else => "UNKNOWN AXIS",
    };
}

test "controller maps validate, remap axes and preserve documented button indices" {
    var mapping: Mapping = .{};
    try std.testing.expect(mapping.validate());
    mapping.axes = .{ 2, 3, 0, 1 };
    mapping.invert[1] = true;
    try std.testing.expectEqual(@as(f32, -0.75), mapping.axis(1, .{ 0, 0, 0.2, 0.75 }));
    mapping.buttons[@intFromEnum(Action.fire)] = 4;
    try std.testing.expect(mapping.isDown(.fire, 1 << 4));
    mapping.buttons[@intFromEnum(Action.fire)] = 16;
    try std.testing.expect(!mapping.validate());
    try std.testing.expectEqualStrings("BTN 8 / RT", buttonName(7));
}
