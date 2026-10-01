//! Front-end and pause menus: the title screen, pause, settings, controls and quit
//! confirmation. Navigation is abstract (keys, pad, or mouse through `select`), so menu logic is
//! testable without a window; the application carries out the returned commands.
const std = @import("std");
const Settings = @import("../game/Settings.zig");
const Bindings = @import("../game/Bindings.zig");
const Menu = @This();

pub const Screen = enum { none, title, pause, settings, controls, confirm_quit };
pub const Key = enum { up, down, left, right, confirm, back };
pub const Command = enum { none, @"resume", new_game, continue_game, save, load, character, quit, settings_changed };
pub const Item = struct { label: []const u8, command: Command = .none, opens: Screen = .none };

pub const title_items = [_]Item{
    .{ .label = "CONTINUE", .command = .continue_game },
    .{ .label = "NEW GAME", .command = .new_game },
    .{ .label = "SETTINGS", .opens = .settings },
    .{ .label = "CONTROLS", .opens = .controls },
    .{ .label = "QUIT", .opens = .confirm_quit },
};
pub const pause_items = [_]Item{
    .{ .label = "RESUME", .command = .@"resume" },
    .{ .label = "CUSTOMIZE RANGER", .command = .character },
    .{ .label = "SAVE GAME", .command = .save },
    .{ .label = "LOAD GAME", .command = .load },
    .{ .label = "SETTINGS", .opens = .settings },
    .{ .label = "CONTROLS", .opens = .controls },
    .{ .label = "QUIT GAME", .opens = .confirm_quit },
};
pub const confirm_items = [_]Item{
    .{ .label = "QUIT TO DESKTOP", .command = .quit },
    .{ .label = "CANCEL" },
};
/// Settings rows are the fields, then "BACK".
pub const settings_rows = Settings.field_count + 1;
/// Controls rows are the actions (two columns of `controls_column`), then "RESET", then "BACK".
pub const controls_rows = Bindings.count + 2;
pub const controls_column = (Bindings.count + 1) / 2;
pub const controls_reset = Bindings.count;
pub const controls_back = Bindings.count + 1;

screen: Screen = .none,
/// The screen "back" returns to from settings, controls and quit (title or pause).
base: Screen = .none,
row: u8 = 0,
/// A save file exists, so CONTINUE and LOAD are offered.
has_save: bool = false,
settings: Settings = .{},
/// Controls screen: waiting for the key to bind to the selected action.
capturing: bool = false,
/// Seconds since start (blinking prompts), set by the application.
seconds: f32 = 0,
/// The action that gave up its key in the last rebind (shown as a note).
swapped: ?Bindings.Action = null,

pub fn open(self: *Menu, screen: Screen) void {
    if (screen == .title or screen == .pause or screen == .none) self.base = screen;
    self.screen = screen;
    self.row = 0;
    self.capturing = false;
    self.swapped = null;
    if (screen == .title and !self.has_save) self.row = 1;
}

pub fn items(self: *const Menu) []const Item {
    return switch (self.screen) {
        .title => &title_items,
        .pause => &pause_items,
        .confirm_quit => &confirm_items,
        else => &.{},
    };
}

pub fn rows(self: *const Menu) u8 {
    return switch (self.screen) {
        .settings => settings_rows,
        .controls => controls_rows,
        .none => 0,
        else => @intCast(self.items().len),
    };
}

/// Whether a row can be chosen (CONTINUE and LOAD need a save).
pub fn enabled(self: *const Menu, row: usize) bool {
    if (self.screen == .title and row == 0) return self.has_save;
    if (self.screen == .pause and pause_items[row].command == .load) return self.has_save;
    return true;
}

fn step(self: *Menu, delta: i32) void {
    const n: i32 = self.rows();
    if (n == 0) return;
    var r: i32 = self.row;
    for (0..@intCast(n)) |_| {
        r = @mod(r + delta, n);
        if (self.enabled(@intCast(r))) break;
    }
    self.row = @intCast(r);
}

/// Points at a row (mouse hover); disabled rows are ignored.
pub fn select(self: *Menu, row: u8) void {
    if (row < self.rows() and self.enabled(row)) self.row = row;
}

pub fn key(self: *Menu, k: Key) Command {
    if (self.screen == .none) return .none;
    if (self.screen == .controls) return self.controlsKey(k);
    switch (k) {
        .up => self.step(-1),
        .down => self.step(1),
        .left, .right => if (self.screen == .settings and self.row < Settings.field_count) {
            self.settings.adjust(@enumFromInt(self.row), if (k == .left) -1 else 1);
            return .settings_changed;
        },
        .back => return self.back(),
        .confirm => {
            if (self.screen == .settings) {
                if (self.row == Settings.field_count) return self.back();
                self.settings.adjust(@enumFromInt(self.row), 1);
                return .settings_changed;
            }
            if (!self.enabled(self.row)) return .none;
            const item = self.items()[self.row];
            if (item.opens != .none) {
                self.open(item.opens);
                return .none;
            }
            if (self.screen == .confirm_quit and item.command == .none) return self.back();
            return item.command;
        },
    }
    return .none;
}

fn controlsKey(self: *Menu, k: Key) Command {
    if (self.capturing) {
        if (k == .back) self.capturing = false;
        return .none;
    }
    const r: i32 = self.row;
    switch (k) {
        .up => self.row = @intCast(@mod(r - 1, @as(i32, controls_rows))),
        .down => self.row = @intCast(@mod(r + 1, @as(i32, controls_rows))),
        // Left and right jump between the two columns of actions.
        .left, .right => if (self.row < Bindings.count) {
            const column: i32 = controls_column;
            const moved = if (k == .left) r - column else r + column;
            self.row = @intCast(std.math.clamp(moved, 0, @as(i32, Bindings.count - 1)));
        },
        .back => return self.back(),
        .confirm => switch (self.row) {
            controls_reset => {
                self.settings.bindings = .{};
                self.swapped = null;
                return .settings_changed;
            },
            controls_back => return self.back(),
            else => {
                self.capturing = true;
                self.swapped = null;
            },
        },
    }
    return .none;
}

/// The key pressed while capturing: binds it (swapping with any action that had it). Escape
/// cancels; Enter is reserved for menus and is ignored.
pub fn bindKey(self: *Menu, k: Bindings.Key) Command {
    if (!self.capturing) return .none;
    if (k == .escape) {
        self.capturing = false;
        return .none;
    }
    self.swapped = self.settings.bindings.bind(@enumFromInt(self.row), k) catch return .none;
    self.capturing = false;
    return .settings_changed;
}

/// Back out one level: sub-screens return to their base; pause resumes; the title stays.
fn back(self: *Menu) Command {
    switch (self.screen) {
        .settings, .controls, .confirm_quit => {
            const from = self.screen;
            self.open(self.base);
            // Land on the entry that opened the sub-screen.
            for (self.items(), 0..) |item, i| if (item.opens == from) {
                self.row = @intCast(i);
            };
        },
        .pause => return .@"resume",
        else => {},
    }
    return .none;
}

test "title skips continue without a save, and sub-screens return to their entry" {
    var m: Menu = .{};
    m.open(.title);
    try std.testing.expectEqual(@as(u8, 1), m.row);
    _ = m.key(.up);
    // Wraps past the disabled CONTINUE to QUIT.
    try std.testing.expectEqual(@as(u8, 4), m.row);
    m.row = 2;
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.settings, m.screen);
    try std.testing.expectEqual(Command.settings_changed, m.key(.right));
    try std.testing.expectEqual(@as(f32, 1.25), m.settings.sensitivity);
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.title, m.screen);
    try std.testing.expectEqual(@as(u8, 2), m.row);
    m.row = 1;
    try std.testing.expectEqual(Command.new_game, m.key(.confirm));

    m.has_save = true;
    m.open(.title);
    try std.testing.expectEqual(Command.continue_game, m.key(.confirm));
}

test "controls rebind by capture, swap conflicts, cancel, and reset" {
    var m: Menu = .{};
    m.open(.pause);
    m.open(.controls);
    m.row = @intFromEnum(Bindings.Action.jump);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expect(m.capturing);
    try std.testing.expectEqual(Command.settings_changed, m.bindKey(.g));
    try std.testing.expectEqual(Bindings.Key.g, m.settings.bindings.key(.jump));
    try std.testing.expectEqual(@as(?Bindings.Action, .grapple), m.swapped);
    _ = m.key(.confirm);
    try std.testing.expectEqual(Command.none, m.bindKey(.escape));
    try std.testing.expect(!m.capturing);
    _ = m.key(.right);
    try std.testing.expectEqual(@as(u8, @intFromEnum(Bindings.Action.jump) + controls_column), m.row);
    m.row = controls_reset;
    try std.testing.expectEqual(Command.settings_changed, m.key(.confirm));
    try std.testing.expectEqual(Bindings.Key.space, m.settings.bindings.key(.jump));
    m.row = controls_back;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.pause, m.screen);
}

test "pause resumes on back, confirms quit, and cancels back to pause" {
    var m: Menu = .{};
    m.open(.pause);
    try std.testing.expectEqual(Command.@"resume", m.key(.back));
    m.row = 6;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.confirm_quit, m.screen);
    m.select(1);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 6), m.row);
    _ = m.key(.confirm);
    try std.testing.expectEqual(Command.quit, m.key(.confirm));
    // LOAD is skipped without a save.
    m.open(.pause);
    m.row = 2;
    _ = m.key(.down);
    try std.testing.expectEqual(@as(u8, 4), m.row);
}
