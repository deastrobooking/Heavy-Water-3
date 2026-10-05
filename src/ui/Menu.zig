//! Front-end and pause menus: the title screen, pause, settings, controls and quit
//! confirmation. Navigation is abstract (keys, pad, or mouse through `select`), so menu logic is
//! testable without a window; the application carries out the returned commands.
const std = @import("std");
const Settings = @import("../game/Settings.zig");
const Bindings = @import("../game/Bindings.zig");
const PadBindings = @import("../engine/PadBindings.zig");
const Menu = @This();

pub const Screen = enum { none, title, pause, settings, controls, pad_controls, quest_log, confirm_quit };
pub const Key = enum { up, down, left, right, confirm, back };
pub const Command = enum { none, @"resume", new_game, continue_game, save, load, character, quit, settings_changed, pad_export, pad_import };
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
    .{ .label = "QUEST LOG", .opens = .quest_log },
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
pub const quest_items = [_]Item{.{ .label = "BACK" }};
/// Settings rows are the fields, then "BACK".
pub const settings_rows = Settings.field_count + 1;
/// Keyboard actions, reset, gamepad setup, then back.
pub const controls_rows = Bindings.count + 3;
pub const controls_column = (Bindings.count + 1) / 2;
pub const controls_reset = Bindings.count;
pub const controls_gamepad = Bindings.count + 1;
pub const controls_back = Bindings.count + 2;
pub const pad_axis_start = PadBindings.action_count;
pub const pad_deadzone = pad_axis_start + PadBindings.axis_count;
pub const pad_trigger_threshold = pad_deadzone + 1;
pub const pad_preset_slot = pad_trigger_threshold + 1;
pub const pad_export = pad_preset_slot + 1;
pub const pad_import = pad_export + 1;
pub const pad_reset = pad_import + 1;
pub const pad_back = pad_reset + 1;
pub const pad_controls_rows = pad_back + 1;
pub const pad_controls_column = (PadBindings.action_count + 1) / 2;

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
pad_capturing_action: ?PadBindings.Action = null,
pad_preset_slot_index: u8 = 0,
pad_preset_label: [64]u8 = @splat(0),

pub fn open(self: *Menu, screen: Screen) void {
    if (screen == .title or screen == .pause or screen == .none) self.base = screen;
    self.screen = screen;
    self.row = 0;
    self.capturing = false;
    self.pad_capturing_action = null;
    self.swapped = null;
    if (screen == .title and !self.has_save) self.row = 1;
}

pub fn items(self: *const Menu) []const Item {
    return switch (self.screen) {
        .title => &title_items,
        .pause => &pause_items,
        .confirm_quit => &confirm_items,
        .quest_log => &quest_items,
        else => &.{},
    };
}

pub fn rows(self: *const Menu) u8 {
    return switch (self.screen) {
        .settings => settings_rows,
        .controls => controls_rows,
        .pad_controls => pad_controls_rows,
        .quest_log => 1,
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
    if (self.screen == .pad_controls) return self.padControlsKey(k);
    if (self.screen == .quest_log and k == .confirm) return self.back();
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
            controls_gamepad => {
                self.open(.pad_controls);
                return .none;
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

fn padControlsKey(self: *Menu, k: Key) Command {
    if (self.pad_capturing_action != null) {
        if (k == .back) self.pad_capturing_action = null;
        return .none;
    }
    const row: usize = self.row;
    const row_count: i32 = @intCast(pad_controls_rows);
    switch (k) {
        .up => self.row = @intCast(@mod(@as(i32, self.row) - 1, row_count)),
        .down => self.row = @intCast((row + 1) % pad_controls_rows),
        .left, .right => {
            const delta: i32 = if (k == .left) -1 else 1;
            if (row < PadBindings.action_count) {
                const old = self.settings.pad_mapping.buttons[row];
                self.settings.pad_mapping.buttons[row] = @intCast(@mod(@as(i32, old) + delta, @as(i32, PadBindings.physical_button_count)));
                return .settings_changed;
            }
            if (row >= pad_axis_start and row < pad_deadzone) {
                const axis = row - pad_axis_start;
                const old = self.settings.pad_mapping.axes[axis];
                self.settings.pad_mapping.axes[axis] = @intCast(@mod(@as(i32, old) + delta, @as(i32, PadBindings.axis_count)));
                return .settings_changed;
            }
            if (row == pad_deadzone) {
                self.settings.pad_mapping.deadzone = std.math.clamp(self.settings.pad_mapping.deadzone + 0.02 * @as(f32, @floatFromInt(delta)), 0, 0.6);
                return .settings_changed;
            }
            if (row == pad_trigger_threshold) {
                self.settings.pad_mapping.trigger_threshold = std.math.clamp(self.settings.pad_mapping.trigger_threshold + 0.05 * @as(f32, @floatFromInt(delta)), 0, 1);
                return .settings_changed;
            }
            if (row == pad_preset_slot) {
                self.pad_preset_slot_index = @intCast(@mod(@as(i32, self.pad_preset_slot_index) + delta, 8));
                self.pad_preset_label = @splat(0);
            }
        },
        .back => return self.back(),
        .confirm => switch (row) {
            0...PadBindings.action_count - 1 => self.pad_capturing_action = @enumFromInt(row),
            pad_axis_start...pad_deadzone - 1 => {
                const axis = row - pad_axis_start;
                self.settings.pad_mapping.invert[axis] = !self.settings.pad_mapping.invert[axis];
                return .settings_changed;
            },
            pad_export => return .pad_export,
            pad_import => return .pad_import,
            pad_reset => {
                self.settings.pad_mapping = .{};
                self.pad_preset_label = @splat(0);
                self.pad_capturing_action = null;
                return .settings_changed;
            },
            pad_back => return self.back(),
            else => {},
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
        .settings, .controls, .quest_log, .confirm_quit => {
            const from = self.screen;
            self.open(self.base);
            // Land on the entry that opened the sub-screen.
            for (self.items(), 0..) |item, i| if (item.opens == from) {
                self.row = @intCast(i);
            };
        },
        .pad_controls => {
            self.open(.controls);
            self.row = controls_gamepad;
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
    try std.testing.expectEqual(@as(u8, 90), m.settings.master_volume);
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.title, m.screen);
    try std.testing.expectEqual(@as(u8, 2), m.row);
    m.row = 1;
    try std.testing.expectEqual(Command.new_game, m.key(.confirm));

    m.has_save = true;
    m.open(.title);
    try std.testing.expectEqual(Command.continue_game, m.key(.confirm));
}

test "quest log opens from pause and returns to its menu row" {
    var m: Menu = .{};
    m.open(.pause);
    m.row = 2;
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.quest_log, m.screen);
    try std.testing.expectEqual(Command.none, m.key(.back));
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 2), m.row);
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

test "gamepad setup captures logical buttons, adjusts axes and opens preset exchange actions" {
    var m: Menu = .{};
    m.open(.pause);
    m.open(.controls);
    m.row = controls_gamepad;
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.pad_controls, m.screen);
    m.row = @intCast(@intFromEnum(PadBindings.Action.fire));
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(PadBindings.Action.fire, m.pad_capturing_action.?);
    _ = m.key(.back);
    try std.testing.expect(m.pad_capturing_action == null);
    m.row = pad_axis_start + 2;
    try std.testing.expectEqual(Command.settings_changed, m.key(.confirm));
    try std.testing.expect(m.settings.pad_mapping.invert[2]);
    m.row = pad_preset_slot;
    _ = m.key(.left);
    try std.testing.expectEqual(@as(u8, 7), m.pad_preset_slot_index);
    m.row = pad_export;
    try std.testing.expectEqual(Command.pad_export, m.key(.confirm));
    m.row = pad_import;
    try std.testing.expectEqual(Command.pad_import, m.key(.confirm));
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.controls, m.screen);
    try std.testing.expectEqual(controls_gamepad, m.row);
}

test "pause resumes on back, confirms quit, and cancels back to pause" {
    var m: Menu = .{};
    m.open(.pause);
    try std.testing.expectEqual(Command.@"resume", m.key(.back));
    m.row = 7;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.confirm_quit, m.screen);
    m.select(1);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 7), m.row);
    _ = m.key(.confirm);
    try std.testing.expectEqual(Command.quit, m.key(.confirm));
    // LOAD is skipped without a save.
    m.open(.pause);
    m.row = 4;
    _ = m.key(.down);
    try std.testing.expectEqual(@as(u8, 5), m.row);
}
