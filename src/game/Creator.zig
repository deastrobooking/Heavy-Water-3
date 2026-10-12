//! Character creator: edits a draft profile field by field; Enter confirms, Escape cancels.
//! Input arrives as abstract keys so the logic is testable without a window.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Profile = @import("Profile.zig");
const CharacterContent = @import("CharacterContent.zig");
const Creator = @This();

pub const Key = union(enum) { up, down, left, right, enter, escape, backspace, char: u8 };
pub const Line = struct {
    text: [64]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const Line) []const u8 {
        return self.text[0..self.len];
    }
};
const fields = enum_compat.fields(Profile.Field);

open: bool = false,
field: Profile.Field = .name,
draft: Profile = .{},
/// Set once a profile has been confirmed; a new game starts with the creator open.
confirmed: bool = false,
/// Clothing the player owns, one bit per `Profile.Clothing`; others are skipped when cycling.
owned: u8 = 0xff,
/// Armor accents owned, one bit per `Profile.Armor`.
owned_armor: u16 = 0xffff,
/// Forms unlocked, one bit per `Profile.Species` (human always; a Wildkin form once its hero
/// has joined the roster).
owned_species: u32 = 1,
/// Installed mod content; its entries follow the built-in choices of the matching fields.
registry: ?*const CharacterContent.Registry = null,

pub fn begin(self: *Creator, current: Profile) void {
    self.* = .{ .open = true, .draft = current, .confirmed = self.confirmed, .owned = self.owned, .owned_armor = self.owned_armor, .owned_species = self.owned_species | 1, .registry = self.registry };
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
    if (self.adjustWithMods(delta)) return;
    self.draft.adjust(self.field, delta);
    if (self.field == .species) {
        for (0..Profile.species_count) |_| {
            if (self.owned_species & (@as(u32, 1) << @intCast(@intFromEnum(self.draft.species))) != 0) return;
            self.draft.adjust(.species, delta);
        }
        return;
    }
    if (self.field == .armor) {
        for (0..enum_compat.fields(Profile.Armor).len) |_| {
            if (self.owned_armor & (@as(u16, 1) << @intCast(@intFromEnum(self.draft.armor))) != 0) return;
            self.draft.adjust(.armor, delta);
        }
        return;
    }
    if (self.field != .clothing) return;
    for (0..enum_compat.fields(Profile.Clothing).len) |_| {
        if (self.owned & (@as(u8, 1) << @intCast(@intFromEnum(self.draft.clothing))) != 0) return;
        self.draft.adjust(.clothing, delta);
    }
}

/// The mod content slot a field offers, if any: mod entries are extra options after the built-ins.
fn modSlot(field: Profile.Field) ?CharacterContent.Slot {
    return switch (field) {
        .hair_style => .hair_style,
        .face_style => .face_preset,
        .armor => .armor_set,
        .outfit => .palette,
        .cel_style => .cel_style,
        else => null,
    };
}

/// How many built-in choices a field has before the mod entries start (cel styles have one:
/// "default", meaning the game's own look).
fn builtinCount(field: Profile.Field) usize {
    return switch (field) {
        .hair_style => enum_compat.fields(Profile.HairStyle).len,
        .face_style => enum_compat.fields(Profile.FaceStyle).len,
        .armor => enum_compat.fields(Profile.Armor).len,
        .outfit => Profile.outfit_colors.len,
        else => 1,
    };
}

fn builtinIndex(draft: *const Profile, field: Profile.Field) usize {
    return switch (field) {
        .hair_style => @intFromEnum(draft.hair_style),
        .face_style => @intFromEnum(draft.face_style),
        .armor => @intFromEnum(draft.armor),
        .outfit => draft.outfit,
        else => 0,
    };
}

/// The selected mod entry for a field, if its mod is installed.
pub fn selectedMod(self: *const Creator, field: Profile.Field) ?CharacterContent.Handle {
    const slot = modSlot(field) orelse return null;
    return self.draft.mod.resolve(slot, self.registry);
}

/// Cycles a field through its built-in choices and then the registry's entries. Returns false
/// when the field has no mod entries, leaving the built-in logic (and its ownership rules).
fn adjustWithMods(self: *Creator, delta: i32) bool {
    const slot = modSlot(self.field) orelse return false;
    const registry = self.registry orelse return false;
    const entries = registry.list(slot.kind());
    if (entries.len == 0) return false;
    const builtin = builtinCount(self.field);
    const total: i32 = @intCast(builtin + entries.len);
    var at: i32 = @intCast(if (self.selectedMod(self.field)) |h| builtin + (registry.position(slot.kind(), h) orelse 0) else builtinIndex(&self.draft, self.field));
    for (0..@intCast(total)) |_| {
        at = @mod(at + delta, total);
        const choice: usize = @intCast(at);
        if (choice >= builtin) {
            self.draft.mod.set(slot, registry.get(entries[choice - builtin]).id());
            return true;
        }
        // Built-in choice: respect what the player owns.
        if (self.field == .armor and self.owned_armor & (@as(u8, 1) << @intCast(choice)) == 0) continue;
        self.draft.mod.clear(slot);
        if (self.field != .cel_style) self.draft.adjust(self.field, @as(i32, @intCast(choice)) - @as(i32, @intCast(builtinIndex(&self.draft, self.field))));
        return true;
    }
    return true;
}

pub fn value(self: *const Creator, field: Profile.Field, buffer: []u8) []const u8 {
    const p = self.draft;
    if (self.selectedMod(field)) |h| return self.registry.?.get(h).name();
    return switch (field) {
        .cel_style => if (p.mod.get(.cel_style) != null) "default (mod missing)" else "default",
        .name => std.fmt.bufPrint(buffer, "{s}_", .{p.name()}) catch buffer,
        .class => switch (p.class) {
            .ranger => "ranger: tech",
            .synthetic => "synthetic: powers",
        },
        .body_style => switch (p.body_style) {
            .procedural => "procedural ranger",
            .captain_test => "CAPTAIN GLB (STATIC POSE)",
        },
        .species => if (p.species == .human) "human" else std.fmt.bufPrint(buffer, "{s} form", .{@tagName(p.species)}) catch buffer,
        .coat => std.fmt.bufPrint(buffer, "COAT {d} OF {d}", .{ p.coat + 1, Profile.coat_colors.len }) catch buffer,
        .marking => std.fmt.bufPrint(buffer, "MARKING {d} OF {d}", .{ p.marking + 1, Profile.coat_colors.len }) catch buffer,
        .presentation => @tagName(p.presentation),
        .face_style => @tagName(p.face_style),
        .height => std.fmt.bufPrint(buffer, "{d:.2} M", .{1.8 * p.height}) catch buffer,
        .build => std.fmt.bufPrint(buffer, "{d:.0}%", .{p.build * 100}) catch buffer,
        .skin => std.fmt.bufPrint(buffer, "TONE {d} OF {d}", .{ p.skin + 1, Profile.skin_tones.len }) catch buffer,
        .hair_style => @tagName(p.hair_style),
        .hair_spike => std.fmt.bufPrint(buffer, "SPIKES {d:.0}%", .{Profile.hairFactor(p.hair_spike) * 100}) catch buffer,
        .hair_volume => std.fmt.bufPrint(buffer, "VOLUME {d:.0}%", .{Profile.hairFactor(p.hair_volume) * 100}) catch buffer,
        .hair_length => std.fmt.bufPrint(buffer, "LENGTH {d:.0}%", .{Profile.hairFactor(p.hair_length) * 100}) catch buffer,
        .hair_color => std.fmt.bufPrint(buffer, "COLOR {d} OF {d}", .{ p.hair_color + 1, Profile.hair_colors.len }) catch buffer,
        .hair_highlight => if (p.hair_highlight == 0) (if (p.class == .synthetic) "AUTO LUMEN" else "OFF") else std.fmt.bufPrint(buffer, "COLOR {d}", .{p.hair_highlight}) catch buffer,
        .outfit => std.fmt.bufPrint(buffer, "COLOR {d} OF {d}", .{ p.outfit + 1, Profile.outfit_colors.len }) catch buffer,
        .clothing => @tagName(p.clothing),
        .armor => @tagName(p.armor),
        .helmet => @tagName(p.helmet),
        .boot_style => @tagName(p.boot_style),
        .accent => std.fmt.bufPrint(buffer, "LUMEN {d} OF {d}", .{ p.accent + 1, Profile.accent_colors.len }) catch buffer,
        .gemstone => @tagName(p.gemstone),
        .gem_cut => @tagName(p.gem_cut),
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
    // Name, class, species, presentation, face style, height.
    for (0..5) |_| _ = c.key(.down);
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
    var panel: [25]Line = undefined;
    c.begin(result.confirmed);
    const count = c.lines(&panel);
    try std.testing.expectEqual(@as(usize, 25), count);
    try std.testing.expectEqualStrings("> name: MIRA-7_", panel[1].slice());
}

test "forms cycle only through unlocked Wildkin, and human is always available" {
    var c: Creator = .{ .owned_species = (1 << @intFromEnum(Profile.Species.fox)) | (1 << @intFromEnum(Profile.Species.bat)) };
    c.begin(.{});
    c.field = .species;
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.Species.fox, c.draft.species);
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.Species.bat, c.draft.species);
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.Species.human, c.draft.species);
    _ = c.key(.left);
    try std.testing.expectEqual(Profile.Species.bat, c.draft.species);
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

fn testRegistry(allocator: std.mem.Allocator) !CharacterContent.Registry {
    const json =
        \\{ "format": 1,
        \\  "hair_styles": [ { "id": "flame", "name": "Flame Crest", "clumps": [ { "az": 0, "el": 1.2 } ] }, { "id": "wisp", "name": "Wisp", "clumps": [ { "az": 0.5, "el": 1 } ] } ],
        \\  "palettes": [ { "id": "ember", "name": "Ember", "role": "outfit", "colors": ["#ff0000"] } ],
        \\  "cel_styles": [ { "id": "ink", "name": "Ink Wash" } ] }
    ;
    var report: CharacterContent.Report = .{};
    const batch = try CharacterContent.Batch.create(allocator, "testmod");
    defer batch.destroy();
    try batch.addFile("t.json", json, &report);
    try batch.finish(&report);
    var registry = try CharacterContent.Registry.init(allocator, 8);
    _ = registry.install(batch);
    return registry;
}

test "mod entries follow the built-ins in the creator, and leaving them restores the built-in" {
    var registry = try testRegistry(std.testing.allocator);
    defer registry.deinit();
    var c: Creator = .{ .registry = &registry };
    const last_style = std.enums.values(Profile.HairStyle)[std.enums.values(Profile.HairStyle).len - 1];
    c.begin(.{ .hair_style = last_style });
    c.field = .hair_style;
    var buffer: [40]u8 = undefined;
    // The last built-in style comes before the mod entries; the next option is the first mod entry.
    _ = c.key(.right);
    try std.testing.expectEqualStrings("testmod.flame", c.draft.mod.get(.hair_style).?.slice());
    try std.testing.expectEqualStrings("Flame Crest", c.value(.hair_style, &buffer));
    // The built-in stays as the fallback underneath.
    try std.testing.expectEqual(last_style, c.draft.hair_style);
    _ = c.key(.right);
    try std.testing.expectEqualStrings("Wisp", c.value(.hair_style, &buffer));
    _ = c.key(.right);
    try std.testing.expect(c.draft.mod.get(.hair_style) == null);
    try std.testing.expectEqual(Profile.HairStyle.short, c.draft.hair_style);
    _ = c.key(.left);
    try std.testing.expectEqualStrings("Wisp", c.value(.hair_style, &buffer));
    // Palettes extend the outfit colors; cel styles start at "default".
    c.field = .outfit;
    _ = c.key(.left);
    try std.testing.expectEqualStrings("Ember", c.value(.outfit, &buffer));
    c.field = .cel_style;
    try std.testing.expectEqualStrings("default", c.value(.cel_style, &buffer));
    _ = c.key(.right);
    try std.testing.expectEqualStrings("Ink Wash", c.value(.cel_style, &buffer));
    _ = c.key(.right);
    try std.testing.expectEqualStrings("default", c.value(.cel_style, &buffer));
    // Fields with no mod entries behave exactly as before.
    c.field = .face_style;
    _ = c.key(.right);
    try std.testing.expectEqual(Profile.FaceStyle.soft, c.draft.face_style);
    // Confirming keeps the mod choice in the profile.
    c.field = .hair_style;
    const before = c.draft.mod.get(.hair_style).?.slice();
    try std.testing.expect(std.mem.startsWith(u8, before, "testmod."));
    const result = c.key(.enter);
    try std.testing.expectEqualStrings(before, result.confirmed.mod.get(.hair_style).?.slice());
}

test "a profile that names a missing mod falls back to the built-in and keeps the id" {
    var registry = try testRegistry(std.testing.allocator);
    defer registry.deinit();
    var p: Profile = .{ .hair_style = .bun };
    p.mod.set(.hair_style, CharacterContent.Id.parse("removed.curls").?);
    p.mod.set(.cel_style, CharacterContent.Id.parse("removed.ink").?);
    try std.testing.expect(p.mod.resolve(.hair_style, &registry) == null);
    var c: Creator = .{ .registry = &registry };
    c.begin(p);
    var buffer: [40]u8 = undefined;
    try std.testing.expectEqualStrings("bun", c.value(.hair_style, &buffer));
    try std.testing.expectEqualStrings("default (mod missing)", c.value(.cel_style, &buffer));
    // Without any registry the creator is the built-in creator.
    var plain: Creator = .{};
    plain.begin(p);
    plain.field = .hair_style;
    _ = plain.key(.right);
    try std.testing.expectEqual(Profile.HairStyle.braids, plain.draft.hair_style);
    // The id survives a save round trip even though nothing resolves it.
    const back = try Profile.fromDoc(p.toDoc());
    try std.testing.expectEqualStrings("removed.curls", back.mod.get(.hair_style).?.slice());
}
