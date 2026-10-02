//! Keyboard bindings: one key per gameplay action, rebindable from the controls screen and
//! saved with the settings. Escape and Enter are reserved for menus. Binding a key that another
//! action uses swaps the two, so every action always keeps exactly one key.
const std = @import("std");
const mach = @import("mach");
const Bindings = @This();

pub const Key = mach.Core.KeyButtonID;
pub const Action = enum { forward, back, left, right, jump, sprint, roll, stomp, grapple, traversal, mantle, ascend, descend, walk_fly, reset, camera_view, customize, inspect, capture_prefab, rotate, next_item, tool_hands, tool_build, tool_wire, tool_bridge, channel_down, channel_up, quicksave, quickload, add_guest, metrics, culling, tool_weapon };
pub const count = @typeInfo(Action).@"enum".fields.len;
pub const defaults = [count]Key{ .w, .s, .a, .d, .space, .left_shift, .left_control, .x, .g, .b, .f, .e, .q, .v, .r, .f2, .f4, .i, .p, .t, .tab, .one, .two, .three, .four, .left_bracket, .right_bracket, .f5, .f9, .f6, .f1, .c, .five };
pub const reserved = [_]Key{ .escape, .enter, .kp_enter };

keys: [count]Key = defaults,

pub fn key(self: Bindings, a: Action) Key {
    return self.keys[@intFromEnum(a)];
}

pub fn action(self: Bindings, k: Key) ?Action {
    for (self.keys, 0..) |bound, i| if (bound == k) return @enumFromInt(i);
    return null;
}

/// Binds `k` to `a`. If another action had `k`, it takes `a`'s old key and is returned.
pub fn bind(self: *Bindings, a: Action, k: Key) error{Reserved}!?Action {
    for (reserved) |r| if (k == r) return error.Reserved;
    const old = self.key(a);
    const other = self.action(k);
    self.keys[@intFromEnum(a)] = k;
    if (other) |o| if (o != a) {
        self.keys[@intFromEnum(o)] = old;
        return o;
    };
    return null;
}

pub fn label(a: Action) []const u8 {
    return switch (a) {
        .forward => "MOVE FORWARD",
        .back => "MOVE BACK",
        .left => "MOVE LEFT",
        .right => "MOVE RIGHT",
        .jump => "JUMP / JET",
        .sprint => "SPRINT / BOOST",
        .roll => "ROLL / DASH",
        .stomp => "STOMP",
        .grapple => "GRAPPLE",
        .traversal => "CYCLE TRAVERSAL",
        .mantle => "MANTLE",
        .ascend => "FLY UP",
        .descend => "FLY DOWN",
        .walk_fly => "WALK / FLY",
        .reset => "RETURN TO SPAWN",
        .camera_view => "FIRST / THIRD PERSON",
        .customize => "CUSTOMIZE",
        .inspect => "INSPECT MACHINE",
        .capture_prefab => "CAPTURE PREFAB",
        .rotate => "ROTATE",
        .next_item => "NEXT ITEM",
        .tool_hands => "TOOL: HANDS",
        .tool_build => "TOOL: BUILD",
        .tool_wire => "TOOL: WIRE",
        .tool_bridge => "TOOL: BRIDGE",
        .channel_down => "CHANNEL DOWN",
        .channel_up => "CHANNEL UP",
        .quicksave => "QUICK SAVE",
        .quickload => "QUICK LOAD",
        .add_guest => "ADD / REMOVE GUEST",
        .metrics => "PERFORMANCE",
        .culling => "CULLING",
        .tool_weapon => "TOOL: WEAPON",
    };
}

/// A key's display name ("left_shift" → "LEFT SHIFT", "one" → "1", "left_bracket" → "[").
pub fn keyName(k: Key, buffer: []u8) []const u8 {
    const names = .{ .{ "zero", "0" }, .{ "one", "1" }, .{ "two", "2" }, .{ "three", "3" }, .{ "four", "4" }, .{ "five", "5" }, .{ "six", "6" }, .{ "seven", "7" }, .{ "eight", "8" }, .{ "nine", "9" }, .{ "left_bracket", "[" }, .{ "right_bracket", "]" }, .{ "minus", "-" }, .{ "equal", "=" }, .{ "semicolon", ";" }, .{ "comma", "," }, .{ "period", "." }, .{ "slash", "/" }, .{ "apostrophe", "'" }, .{ "left_control", "LEFT CTRL" }, .{ "right_control", "RIGHT CTRL" } };
    const tag = @tagName(k);
    inline for (names) |pair| if (std.mem.eql(u8, tag, pair[0])) return pair[1];
    const n = @min(buffer.len, tag.len);
    for (buffer[0..n], tag[0..n]) |*o, ch| o.* = if (ch == '_') ' ' else std.ascii.toUpper(ch);
    return buffer[0..n];
}

/// Saved shape: action and key by name, so reordering either enum keeps old settings.
pub const Entry = struct { action: []const u8, key: []const u8 };

pub fn toEntries(self: Bindings, out: *[count]Entry) []const Entry {
    for (out, 0..) |*e, i| e.* = .{ .action = @tagName(@as(Action, @enumFromInt(i))), .key = @tagName(self.keys[i]) };
    return out;
}

/// Applies saved entries over the defaults in order; unknown names and reserved keys are skipped.
pub fn fromEntries(entries: []const Entry) Bindings {
    var result: Bindings = .{};
    for (entries) |e| {
        const a = std.meta.stringToEnum(Action, e.action) orelse continue;
        const k = std.meta.stringToEnum(Key, e.key) orelse continue;
        _ = result.bind(a, k) catch continue;
    }
    return result;
}

test "binding swaps conflicts, refuses reserved keys, and round-trips by name" {
    var b: Bindings = .{};
    try std.testing.expectEqual(@as(?Action, .jump), b.action(.space));
    // G to jump: grapple takes space.
    try std.testing.expectEqual(@as(?Action, .grapple), try b.bind(.jump, .g));
    try std.testing.expectEqual(Key.g, b.key(.jump));
    try std.testing.expectEqual(Key.space, b.key(.grapple));
    try std.testing.expectError(error.Reserved, b.bind(.jump, .escape));
    try std.testing.expectEqual(@as(?Action, null), try b.bind(.stomp, .z));
    // Every action still has a distinct key.
    for (b.keys, 0..) |k, i| for (b.keys[0..i]) |o| try std.testing.expect(k != o);
    var entries: [count]Entry = undefined;
    const back = fromEntries(b.toEntries(&entries));
    try std.testing.expectEqual(b.keys, back.keys);
    const partial = fromEntries(&.{ .{ .action = "stomp", .key = "z" }, .{ .action = "nonsense", .key = "q" }, .{ .action = "jump", .key = "escape" } });
    try std.testing.expectEqual(Key.z, partial.key(.stomp));
    try std.testing.expectEqual(Key.space, partial.key(.jump));
    var buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings("LEFT SHIFT", keyName(.left_shift, &buffer));
    try std.testing.expectEqualStrings("[", keyName(.left_bracket, &buffer));
}
