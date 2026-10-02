//! Character creator: edits a draft profile field by field; Enter confirms, Escape cancels.
//! Input arrives as abstract keys so the logic is testable without a window.
const std = @import("std");
const Profile = @import("Profile.zig");
const Creator = @This();

pub const Key = union(enum) { up, down, left, right, enter, escape, backspace, char: u8 };
pub const Line = struct {
    text: [64]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const Line) []const u8 {
        return self.text[0..self.len];
    }
};
const fields = std.meta.fields(Profile.Field);

open: bool = false,
field: Profile.Field = .name,
draft: Profile = .{},
/// Set once a profile has been confirmed; a new game starts with the creator open.
confirmed: bool = false,
/// Clothing the player owns, one bit per `Profile.Clothing`; others are skipped when cycling.
owned: u8 = 0xff,
/// Armor accents owned, one bit per `Profile.Armor`.
owned_armor: u8 = 0xff,

pub fn begin(self: *Creator, current: Profile) void {
    self.* = .{ .open = true, .draft = current, .confirmed = self.confirmed, .owned = self.owned, .owned_armor = self.owned_armor };
}

pub const Result = union(enum) { editing, confirmed: Profile, canceled };

pub fn key(self: *Creator, k: Key) Result {
    if (!self.open) return .editing;
    switch (k) {
        .up => self.field = @enumFromInt((@intFromEnum(self.field) + fields.len - 1) % fields.len),
        .down => self.field = @enumFromInt((@intFromEnum(self.field) + 1) % fields.len),
        .left => self.adjust(-1),
        .right => self.adjust(1),
        .backspace => if (self.field == .name) self.draft.backspace(),
        .char => |c| if (self.field == .name) self.draft.typeChar(c),
        .escape => {
            // Before the first confirmation there is nothing to go back to.
            if (!self.confirmed) return .editing;
            self.open = false;
            return .canceled;
        },
        .enter => {
            if (self.draft.name_len == 0) return .editing;
            self.open = false;
            self.confirmed = true;
            return .{ .confirmed = self.draft };
        },
    }
    return .editing;
}

/// Changes the selected field; clothing skips types not yet owned.
pub fn adjust(self: *Creator, delta: i32) void {
    self.draft.adjust(self.field, delta);
    if (self.field == .armor) {
        for (0..@typeInfo(Profile.Armor).@"enum".fields.len) |_| {
            if (self.owned_armor & (@as(u8, 1) << @intCast(@intFromEnum(self.draft.armor))) != 0) return;
            self.draft.adjust(.armor, delta);
        }
        return;
    }
    if (self.field != .clothing) return;
    for (0..@typeInfo(Profile.Clothing).@"enum".fields.len) |_| {
        if (self.owned & (@as(u8, 1) << @intCast(@intFromEnum(self.draft.clothing))) != 0) return;
        self.draft.adjust(.clothing, delta);
    }
}

pub fn value(self: *const Creator, field: Profile.Field, buffer: []u8) []const u8 {
    const p = self.draft;
    return switch (field) {
        .name => std.fmt.bufPrint(buffer, "{s}_", .{p.name()}) catch buffer,
        .presentation => @tagName(p.presentation),
        .height => std.fmt.bufPrint(buffer, "{d:.2} M", .{1.8 * p.height}) catch buffer,
        .build => std.fmt.bufPrint(buffer, "{d:.0}%", .{p.build * 100}) catch buffer,
        .skin => std.fmt.bufPrint(buffer, "TONE {d} OF {d}", .{ p.skin + 1, Profile.skin_tones.len }) catch buffer,
        .hair_style => @tagName(p.hair_style),
        .hair_color => std.fmt.bufPrint(buffer, "COLOR {d} OF {d}", .{ p.hair_color + 1, Profile.hair_colors.len }) catch buffer,
        .outfit => std.fmt.bufPrint(buffer, "COLOR {d} OF {d}", .{ p.outfit + 1, Profile.outfit_colors.len }) catch buffer,
        .clothing => @tagName(p.clothing),
        .armor => @tagName(p.armor),
        .helmet => @tagName(p.helmet),
        .accent => std.fmt.bufPrint(buffer, "LUMEN {d} OF {d}", .{ p.accent + 1, Profile.accent_colors.len }) catch buffer,
    };
}

/// Panel text: a title, one line per field (the selected one marked), and the controls.
pub fn lines(self: *const Creator, out: []Line) usize {
    var n: usize = 0;
    const Put = struct {
        fn line(o: []Line, count: *usize, comptime fmt: []const u8, args: anytype) void {
            if (count.* == o.len) return;
            const text = std.fmt.bufPrint(&o[count.*].text, fmt, args) catch o[count.*].text[0..];
            o[count.*].len = text.len;
            count.* += 1;
        }
    };
    Put.line(out, &n, "CREATE YOUR RANGER", .{});
    inline for (fields) |f| {
        const field: Profile.Field = @enumFromInt(f.value);
        var buffer: [40]u8 = undefined;
        Put.line(out, &n, "{s} {s}: {s}", .{ if (self.field == field) ">" else " ", f.name, self.value(field, &buffer) });
    }
    Put.line(out, &n, "UP DOWN FIELD  LEFT RIGHT CHANGE", .{});
    Put.line(out, &n, "TYPE NAME  ENTER DONE{s}", .{if (self.confirmed) "  ESC CANCEL" else ""});
    return n;
}

test "creator edits a draft, requires a name, confirms, and cancels only after a first confirmation" {
    var c: Creator = .{};
    c.begin(.{});
    try std.testing.expect(c.key(.escape) == .editing);
    while (c.draft.name_len > 0) _ = c.key(.backspace);
    try std.testing.expect(c.key(.enter) == .editing);
    for ("Mira-7") |ch| _ = c.key(.{ .char = ch });
    _ = c.key(.down);
    _ = c.key(.down);
    _ = c.key(.right);
    c.field = .accent;
    try std.testing.expectEqual(Profile.Field.accent, c.field);
    _ = c.key(.right);
    // Typing is ignored away from the name field.
    _ = c.key(.{ .char = 'x' });
    const result = c.key(.enter);
    try std.testing.expectEqualStrings("MIRA-7", result.confirmed.name());
    try std.testing.expectApproxEqAbs(@as(f32, 1.02), result.confirmed.height, 1e-5);
    try std.testing.expectEqual(@as(u8, 1), result.confirmed.accent);
    try std.testing.expect(!c.open);

    c.begin(result.confirmed);
    _ = c.key(.right);
    try std.testing.expect(c.key(.escape) == .canceled);
    var panel: [16]Line = undefined;
    c.begin(result.confirmed);
    const count = c.lines(&panel);
    try std.testing.expectEqual(@as(usize, 15), count);
    try std.testing.expectEqualStrings("> name: MIRA-7_", panel[1].slice());
}

test "clothing cycles only through owned types" {
    var c: Creator = .{ .owned = 0b00011 };
    c.begin(.{ .clothing = .undersuit });
    c.field = .clothing;
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.Clothing.field_jacket, c.draft.clothing);
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.Clothing.undersuit, c.draft.clothing);
    _ = c.key(.left);
    try std.testing.expectEqual(Profile.Clothing.field_jacket, c.draft.clothing);
    try std.testing.expectEqual(@as(u8, 0b00011), c.owned);
}
