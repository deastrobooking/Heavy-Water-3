//! Front-end and pause menus: the title screen, pause, settings, controls and quit
//! confirmation. Navigation is abstract (keys, pad, or mouse through `select`), so menu logic is
//! testable without a window; the application carries out the returned commands.
const std = @import("std");
const Settings = @import("../game/Settings.zig");
const Bindings = @import("../game/Bindings.zig");
const PadBindings = @import("../engine/PadBindings.zig");
const Menu = @This();

pub const Screen = enum { none, title, pause, settings, controls, pad_controls, quest_log, heroes, arena, party, player, world_map, confirm_quit };
pub const Key = enum { up, down, left, right, confirm, back };
pub const Command = enum { none, @"resume", new_game, continue_game, save, load, character, quit, settings_changed, pad_export, pad_import, play_hero, start_arena, leave_arena, party_toggle, party_controller, party_position, travel };
pub const Item = struct { label: []const u8, command: Command = .none, opens: Screen = .none };

pub const title_items = [_]Item{
    .{ .label = "CONTINUE", .command = .continue_game },
    .{ .label = "NEW GAME", .command = .new_game },
    .{ .label = "HERO ARENA", .opens = .arena },
    .{ .label = "SETTINGS", .opens = .settings },
    .{ .label = "CONTROLS", .opens = .controls },
    .{ .label = "QUIT", .opens = .confirm_quit },
    .{ .label = "LOCAL CO-OP SETUP", .opens = .party },
};
pub const pause_items = [_]Item{
    .{ .label = "RESUME", .command = .@"resume" },
    .{ .label = "HEROES", .opens = .heroes },
    .{ .label = "HERO ARENA", .opens = .arena },
    .{ .label = "CUSTOMIZE RANGER", .command = .character },
    .{ .label = "QUEST LOG", .opens = .quest_log },
    .{ .label = "SAVE GAME", .command = .save },
    .{ .label = "LOAD GAME", .command = .load },
    .{ .label = "SETTINGS", .opens = .settings },
    .{ .label = "CONTROLS", .opens = .controls },
    .{ .label = "QUIT GAME", .opens = .confirm_quit },
    .{ .label = "FOUR PLAYER SETUP", .opens = .party },
    .{ .label = "WORLD MAP / FAST TRAVEL", .opens = .world_map },
};
pub const confirm_items = [_]Item{
    .{ .label = "QUIT TO DESKTOP", .command = .quit },
    .{ .label = "CANCEL" },
};
pub const party_items = [_]Item{
    .{ .label = "PLAYER 1" },                                               .{ .label = "PLAYER 2" },                                             .{ .label = "PLAYER 3" },                                                   .{ .label = "PLAYER 4" },
    .{ .label = "JOIN / LEAVE SELECTED PLAYER", .command = .party_toggle }, .{ .label = "ASSIGN NEXT CONTROLLER", .command = .party_controller }, .{ .label = "SWAP WITH NEXT SCREEN POSITION", .command = .party_position }, .{ .label = "RESUME", .command = .@"resume" },
};
pub const player_items = [_]Item{
    .{ .label = "RESUME", .command = .@"resume" },
    .{ .label = "CHOOSE HERO", .opens = .heroes },
    .{ .label = "FOUR PLAYER SETUP", .opens = .party },
    .{ .label = "MAP / FAST TRAVEL", .opens = .world_map },
};
pub const map_items = [_]Item{
    .{ .label = "TRAVEL: BASE CAMP", .command = .travel },
    .{ .label = "TRAVEL: ROOTDEEP SHRINE 1", .command = .travel },
    .{ .label = "TRAVEL: ROOTDEEP SHRINE 2", .command = .travel },
    .{ .label = "FRAME DESTINATION / PLAYER" },
    .{ .label = "RESUME", .command = .@"resume" },
};
pub const quest_items = [_]Item{.{ .label = "BACK" }};
pub const arena_items = [_]Item{
    .{ .label = "START THE ARENA", .command = .start_arena },
    .{ .label = "LEAVE THE ARENA", .command = .leave_arena },
    .{ .label = "BACK" },
};
/// Heroes screen rows: four player tabs, your own ranger, every Wildkin, then BACK. Cards sit in
/// a grid `heroes_columns` wide.
pub const heroes_tabs = 4;
pub const heroes_ranger = heroes_tabs;
pub const heroes_first = heroes_ranger + 1;
pub const heroes_back = heroes_first + @import("../game/Heroes.zig").count;
pub const heroes_rows = heroes_back + 1;
pub const heroes_columns = 7;
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

const Parent = struct { screen: Screen, row: u8 };

screen: Screen = .none,
map_zoom: u8 = 1,
map_frame_destination: bool = false,
map_destination: u8 = 0,
travel_players: u8 = 15,
parents: [8]Parent = undefined,
parent_count: usize = 0,
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
/// Set by the application each frame: heroes on the roster (bit per roster index), local
/// players present (bit per player), and whether the party is in the arena.
heroes_unlocked: u32 = 0,
players_present: u8 = 1,
arena_active: bool = false,
/// The player a hero card is chosen for (Heroes screen tabs).
hero_player: u8 = 0,
controller_players: [4]u8 = .{ 0, 1, 2, 3 },
controllers_connected: [4]bool = @splat(false),

pub fn open(self: *Menu, screen: Screen) void {
    if (screen == .title or screen == .pause or screen == .none) {
        self.base = screen;
        self.parent_count = 0;
    } else if (screen != self.screen and self.screen != .none and self.parent_count < self.parents.len) {
        var parent_row = self.row;
        for (self.items(), 0..) |item, i| if (item.opens == screen) {
            parent_row = @intCast(i);
        };
        self.parents[self.parent_count] = .{ .screen = self.screen, .row = parent_row };
        self.parent_count += 1;
    }
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
        .arena => &arena_items,
        .party => &party_items,
        .player => &player_items,
        .world_map => &map_items,
        else => &.{},
    };
}

pub fn rows(self: *const Menu) u8 {
    return switch (self.screen) {
        .settings => settings_rows,
        .controls => controls_rows,
        .pad_controls => pad_controls_rows,
        .quest_log => 1,
        .heroes => heroes_rows,
        .none => 0,
        else => @intCast(self.items().len),
    };
}

/// Whether a row can be chosen (CONTINUE and LOAD need a save).
pub fn enabled(self: *const Menu, row: usize) bool {
    if (row >= self.rows()) return false;
    if (self.screen == .world_map and row < 3) return self.hero_player < 4 and self.travel_players & (@as(u8, 1) << @intCast(self.hero_player)) != 0;
    if (self.screen == .title and row == 0) return self.has_save;
    if (self.screen == .pause and pause_items[row].command == .load) return self.has_save;
    if (self.screen == .arena) return switch (arena_items[row].command) {
        .start_arena => !self.arena_active,
        .leave_arena => self.arena_active,
        else => true,
    };
    if (self.screen == .heroes) {
        if (row < heroes_tabs) return self.players_present & (@as(u8, 1) << @intCast(row)) != 0;
        if (row >= heroes_first and row < heroes_back) return self.heroes_unlocked & (@as(u32, 1) << @intCast(row - heroes_first)) != 0;
    }
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
    if (self.screen == .world_map and self.row < 3) self.map_destination = self.row;
}

/// Points at a row (mouse hover); disabled rows are ignored.
pub fn select(self: *Menu, row: u8) void {
    if (row < self.rows() and self.enabled(row)) {
        self.row = row;
        if (self.screen == .world_map and row < 3) self.map_destination = row;
    }
}

pub fn key(self: *Menu, k: Key) Command {
    if (self.screen == .none) return .none;
    if (self.screen == .controls) return self.controlsKey(k);
    if (self.screen == .pad_controls) return self.padControlsKey(k);
    if (self.screen == .world_map and self.row < 3) self.map_destination = self.row;
    if (self.screen == .world_map and k == .confirm and self.row == 3) {
        self.map_frame_destination = !self.map_frame_destination;
        return .none;
    }
    if (self.screen == .world_map and (k == .left or k == .right)) {
        self.map_zoom = @intCast(std.math.clamp(@as(i32, self.map_zoom) + @as(i32, if (k == .right) -1 else 1), 0, 2));
        return .none;
    }
    if (self.screen == .quest_log and k == .confirm) return self.back();
    if (self.screen == .heroes) return self.heroesKey(k);
    if (self.screen == .party and k == .confirm and self.row < 4) {
        self.hero_player = self.row;
        return .none;
    }
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
            if (self.screen == .party and self.base == .title and item.command == .@"resume") return .new_game;
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
/// The Heroes screen: tabs pick the player, the grid picks the hero (locked cards are skipped
/// for choosing but can be looked at), BACK leaves.
fn heroesKey(self: *Menu, k: Key) Command {
    const r: i32 = self.row;
    const columns: i32 = heroes_columns;
    const first: i32 = heroes_ranger;
    const last: i32 = heroes_back;
    switch (k) {
        .back => return self.back(),
        .left, .right => {
            const d: i32 = if (k == .left) -1 else 1;
            if (r < heroes_tabs) {
                var t = r;
                for (0..heroes_tabs) |_| {
                    t = @mod(t + d, heroes_tabs);
                    if (self.enabled(@intCast(t))) break;
                }
                self.row = @intCast(t);
                self.hero_player = self.row;
            } else if (r < last) self.row = @intCast(std.math.clamp(r + d, first, last - 1));
        },
        .up => self.row = if (r < heroes_tabs) self.row else if (r == last) @intCast(last - 1) else if (r - columns < first) self.hero_player else @intCast(r - columns),
        .down => self.row = if (r < heroes_tabs) @intCast(first) else if (r == last) self.row else @intCast(@min(last, r + columns)),
        .confirm => {
            if (r == last) return self.back();
            if (r < heroes_tabs) {
                if (self.enabled(self.row)) self.hero_player = self.row;
                self.row = heroes_ranger;
                return .none;
            }
            if (!self.enabled(self.row)) return .none;
            return .play_hero;
        },
    }
    return .none;
}

/// The hero chosen on the Heroes screen: null for the player's own ranger.
pub fn chosenHero(self: *const Menu) ?u8 {
    if (self.row >= heroes_first and self.row < heroes_back) return self.row - heroes_first;
    return null;
}

fn back(self: *Menu) Command {
    if (self.parent_count > 0) {
        self.parent_count -= 1;
        const parent = self.parents[self.parent_count];
        self.screen = parent.screen;
        self.row = parent.row;
        self.capturing = false;
        self.pad_capturing_action = null;
        return .none;
    }
    switch (self.screen) {
        .settings, .controls, .quest_log, .heroes, .arena, .party, .player, .world_map, .confirm_quit => {
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
    try std.testing.expectEqual(@as(u8, 6), m.row);
    m.row = 3;
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.settings, m.screen);
    try std.testing.expectEqual(Command.settings_changed, m.key(.right));
    try std.testing.expectEqual(@as(u8, 90), m.settings.master_volume);
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.title, m.screen);
    try std.testing.expectEqual(@as(u8, 3), m.row);
    m.row = 1;
    try std.testing.expectEqual(Command.new_game, m.key(.confirm));

    m.has_save = true;
    m.open(.title);
    try std.testing.expectEqual(Command.continue_game, m.key(.confirm));
}

test "quest log opens from pause and returns to its menu row" {
    var m: Menu = .{};
    m.open(.pause);
    m.row = 4;
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.quest_log, m.screen);
    try std.testing.expectEqual(Command.none, m.key(.back));
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 4), m.row);
}

test "heroes are chosen per player from unlocked cards, and the arena starts or leaves" {
    var m: Menu = .{ .heroes_unlocked = 0b101, .players_present = 0b11 };
    m.open(.pause);
    m.row = 1;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.heroes, m.screen);
    // Tabs: only present players can be chosen.
    _ = m.key(.right);
    try std.testing.expectEqual(@as(u8, 1), m.hero_player);
    _ = m.key(.right);
    try std.testing.expectEqual(@as(u8, 0), m.hero_player);
    _ = m.key(.down);
    try std.testing.expectEqual(@as(u8, heroes_ranger), m.row);
    try std.testing.expectEqual(Command.play_hero, m.key(.confirm));
    try std.testing.expectEqual(@as(?u8, null), m.chosenHero());
    // The first hero is unlocked; the second is not.
    _ = m.key(.right);
    try std.testing.expectEqual(Command.play_hero, m.key(.confirm));
    try std.testing.expectEqual(@as(?u8, 0), m.chosenHero());
    _ = m.key(.right);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 1), m.row);
    // Arena: start when outside, leave when in.
    m.open(.arena);
    try std.testing.expect(m.enabled(0) and !m.enabled(1));
    try std.testing.expectEqual(Command.start_arena, m.key(.confirm));
    m.arena_active = true;
    try std.testing.expect(!m.enabled(0) and m.enabled(1));
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
    m.row = 9;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.confirm_quit, m.screen);
    m.select(1);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    try std.testing.expectEqual(Screen.pause, m.screen);
    try std.testing.expectEqual(@as(u8, 9), m.row);
    _ = m.key(.confirm);
    try std.testing.expectEqual(Command.quit, m.key(.confirm));
    // LOAD is skipped without a save.
    m.open(.pause);
    m.row = 5;
    _ = m.key(.down);
    try std.testing.expectEqual(@as(u8, 7), m.row);
}

/// Exchange assignments rather than allowing two controllers to own one slot.
pub fn nextController(self: *Menu, player: u8) void {
    var current: usize = 0;
    for (self.controller_players, 0..) |owner, i| if (owner == player) {
        current = i;
    };
    const next = (current + 1) % 4;
    std.mem.swap(u8, &self.controller_players[current], &self.controller_players[next]);
}

test "party setup keeps four unique controller owners and selects empty slots" {
    var m: Menu = .{};
    m.open(.title);
    m.open(.party);
    m.row = 3;
    _ = m.key(.confirm);
    try std.testing.expectEqual(@as(u8, 3), m.hero_player);
    m.row = 4;
    try std.testing.expectEqual(Command.party_toggle, m.key(.confirm));
    for (0..12) |_| {
        m.nextController(3);
        var seen: u8 = 0;
        for (m.controller_players) |p| seen |= @as(u8, 1) << @intCast(p);
        try std.testing.expectEqual(@as(u8, 15), seen);
    }
    m.row = 7;
    try std.testing.expectEqual(Command.new_game, m.key(.confirm));
    m.open(.pause);
    m.open(.player);
    m.row = 3;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.world_map, m.screen);
    m.row = 2;
    try std.testing.expectEqual(Command.travel, m.key(.confirm));
    try std.testing.expectEqual(@as(u8, 3), m.hero_player);
}

test "map zoom stays bounded and preserves destination selection" {
    var m: Menu = .{};
    m.open(.world_map);
    m.row = 2;
    for (0..8) |_| _ = m.key(.right);
    try std.testing.expectEqual(@as(u8, 0), m.map_zoom);
    for (0..8) |_| _ = m.key(.left);
    try std.testing.expectEqual(@as(u8, 2), m.map_zoom);
    try std.testing.expectEqual(@as(u8, 2), m.row);
}

test "nested player map returns to its parent and blocked travel skips equally for every input" {
    var m: Menu = .{};
    m.open(.pause);
    m.open(.player);
    m.row = 3;
    _ = m.key(.confirm);
    try std.testing.expectEqual(Screen.world_map, m.screen);
    m.travel_players = 0;
    m.select(1);
    try std.testing.expectEqual(@as(u8, 0), m.row);
    try std.testing.expectEqual(Command.none, m.key(.confirm));
    _ = m.key(.down);
    try std.testing.expectEqual(@as(u8, 3), m.row);
    _ = m.key(.confirm);
    try std.testing.expect(m.map_frame_destination);
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.player, m.screen);
    try std.testing.expectEqual(@as(u8, 3), m.row);
    _ = m.key(.back);
    try std.testing.expectEqual(Screen.pause, m.screen);
}
