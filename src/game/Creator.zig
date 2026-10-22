//! Character creator: edits a draft profile field by field; Enter confirms, Escape cancels.
//! Input arrives as abstract keys so the logic is testable without a window.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Profile = @import("Profile.zig");
const CharacterContent = @import("CharacterContent.zig");
const Modifiers = @import("../asset/Modifiers.zig");
const EnemyDesign = @import("EnemyDesign.zig");
const Creator = @This();

const imported_history_capacity = 64;
const imported_rig_status_capacity = 96;
const all_clothing_owned = std.math.maxInt(u8);
const all_armor_owned = std.math.maxInt(u16);

pub const Key = union(enum) { up, down, left, right, enter, escape, backspace, undo, redo, char: u8 };
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
owned: u8 = all_clothing_owned,
/// Armor accents owned, one bit per `Profile.Armor`.
owned_armor: u16 = all_armor_owned,
/// Forms unlocked, one bit per `Profile.Species` (human always; a Wildkin form once its hero
/// has joined the roster).
owned_species: u32 = 1,
/// Installed mod content; its entries follow the built-in choices of the matching fields.
registry: ?*const CharacterContent.Registry = null,
/// Source-linked imported character library shown in the in-game Character Designer.
imported_doc: ?*Modifiers.Document = null,
imported_history: Modifiers.History(imported_history_capacity) = .{},
imported_dirty_ids: [imported_history_capacity]u32 = @splat(0),
imported_dirty_len: usize = 0,
imported_dirty_all: bool = false,
imported_open: bool = false,
/// The vertex tools replace the part list while editing the imported mesh itself.
vertex_tools: bool = false,
/// Owned by `App`; re-pointed every frame like `imported_doc`.
mesh_tools: ?*const @import("MeshTools.zig") = null,
imported_selected: usize = 0,
imported_filter: u8 = 0,
imported_palette: Modifiers.Palette = .eyes,
imported_palette_variant: u8 = 0,
imported_status: enum { ready, unsaved, saved } = .ready,
imported_rig_status: [imported_rig_status_capacity]u8 = @splat(0),
imported_rig_status_len: usize = 0,
/// Every uploaded mesh and the one in use (kept by `App`), the last import's outcome as shown
/// in the panel, and whether DELETE has been pressed once (a second press deletes).
imports: @import("ImportLibrary.zig").Library = .{},
import_message: [96]u8 = @splat(0),
import_message_len: u8 = 0,
import_message_ok: bool = true,
import_delete_armed: bool = false,

/// In-game villain assembly panel; its chosen kit skins transformer-scale Scalari frames.
enemy_design_open: bool = false,
enemy_design: EnemyDesign.Design = .{},
enemy_part: EnemyDesign.Part = .frame,

pub fn setImportMessage(self: *Creator, ok: bool, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&self.import_message, fmt, args) catch self.import_message[0..];
    self.import_message_len = @intCast(text.len);
    self.import_message_ok = ok;
}

pub fn begin(self: *Creator, current: Profile) void {
    self.* = .{
        .open = true,
        .draft = current,
        .confirmed = self.confirmed,
        .owned = self.owned,
        .owned_armor = self.owned_armor,
        .owned_species = self.owned_species | 1,
        .registry = self.registry,
        .imported_doc = self.imported_doc,
        .imported_history = self.imported_history,
        .imported_dirty_ids = self.imported_dirty_ids,
        .imported_dirty_len = self.imported_dirty_len,
        .imported_dirty_all = self.imported_dirty_all,
        .imported_selected = self.imported_selected,
        .imported_filter = self.imported_filter,
        .imported_palette = self.imported_palette,
        .imported_palette_variant = self.imported_palette_variant,
        .imported_status = self.imported_status,
        .imported_rig_status = self.imported_rig_status,
        .imported_rig_status_len = self.imported_rig_status_len,
        .imports = self.imports,
        .import_message = self.import_message,
        .import_message_len = self.import_message_len,
        .import_message_ok = self.import_message_ok,
        .enemy_design = self.enemy_design,
        .enemy_part = self.enemy_part,
    };
}

pub const Result = union(enum) { editing, confirmed: Profile, canceled };

pub fn key(self: *Creator, k: Key) Result {
    if (!self.open) return .editing;
    if (self.enemy_design_open) return self.handleEnemyKey(k);
    if (self.imported_open) return self.handleImportedKey(k);
    return self.handleProfileKey(k);
}

fn handleEnemyKey(self: *Creator, k: Key) Result {
    switch (k) {
        .up => self.enemy_part = @enumFromInt((@intFromEnum(self.enemy_part) + EnemyDesign.part_count - 1) % EnemyDesign.part_count),
        .down => self.enemy_part = @enumFromInt((@intFromEnum(self.enemy_part) + 1) % EnemyDesign.part_count),
        .left => self.enemy_design.cycle(self.enemy_part, -1),
        .right => self.enemy_design.cycle(self.enemy_part, 1),
        .char => |c| switch (std.ascii.toLower(c)) {
            'p' => self.enemy_design.cyclePalette(1),
            'l' => self.enemy_design.cycleLayerStyle(1),
            else => {},
        },
        .escape, .enter => self.enemy_design_open = false,
        else => {},
    }
    return .editing;
}

fn handleImportedKey(self: *Creator, k: Key) Result {
    switch (k) {
        .undo => self.undoImported(std.heap.page_allocator),
        .redo => self.redoImported(std.heap.page_allocator),
        .up => self.moveImported(-1),
        .down => self.moveImported(1),
        .left => self.cycleImportedSurface(-1),
        .right => self.cycleImportedSurface(1),
        .char => |c| switch (std.ascii.toLower(c)) {
            'p' => self.cycleImportedPalette(1),
            'c' => self.paintImportedPart(),
            'h' => self.toggleImportedPart(),
            else => {},
        },
        // Escape (pad B) leaves; Enter (pad A, Start) must not throw the panel away mid-edit.
        .escape => self.imported_open = false,
        else => {},
    }
    return .editing;
}

fn handleProfileKey(self: *Creator, k: Key) Result {
    switch (k) {
        .undo, .redo => {},
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

pub fn openImported(self: *Creator) void {
    if (self.imported_doc == null) return;
    self.imported_open = true;
    self.imported_selected = @min(self.imported_selected, self.imported_doc.?.parts.len -| 1);
}

pub fn moveImported(self: *Creator, delta: isize) void {
    const doc = self.imported_doc orelse return;
    if (doc.parts.len == 0) return;
    const count = doc.parts.len;
    const selected = self.imported_selected % count;
    if (delta >= 0) {
        const wrapped_step = @as(usize, @intCast(delta)) % count;
        const to_wrap = count - selected;
        self.imported_selected = if (wrapped_step >= to_wrap) wrapped_step - to_wrap else selected + wrapped_step;
    } else {
        // Add one before negating so the minimum isize value is representable.
        const magnitude: usize = @as(usize, @intCast(-(delta + 1))) + 1;
        const wrapped_step = magnitude % count;
        self.imported_selected = if (wrapped_step > selected) count - (wrapped_step - selected) else selected - wrapped_step;
    }
    self.alignImportedPalette();
}

/// Part lists can be longer than a hit row's byte: a clicked row is the part index modulo 256,
/// and the visible list is centred on the selection, so the matching part nearest the selection
/// (in list order, among those the filter shows) is the one that was clicked.
pub fn importedPartForRow(self: *const Creator, row: u8) usize {
    const doc = self.imported_doc orelse return row;
    var best: usize = row;
    var best_distance: usize = std.math.maxInt(usize);
    var candidate: usize = row;
    while (candidate < doc.parts.len) : (candidate += 256) {
        if (!self.matchesFilter(doc.parts[candidate].surface)) continue;
        const distance = if (candidate > self.imported_selected) candidate - self.imported_selected else self.imported_selected - candidate;
        if (distance < best_distance) {
            best = candidate;
            best_distance = distance;
        }
    }
    return best;
}

pub fn selectImported(self: *Creator, index: usize) void {
    const doc = self.imported_doc orelse return;
    if (index >= doc.parts.len) return;
    self.imported_selected = index;
    self.alignImportedPalette();
}

fn alignImportedPalette(self: *Creator) void {
    const doc = self.imported_doc orelse return;
    if (self.imported_selected >= doc.parts.len) return;
    self.imported_palette = switch (doc.parts[self.imported_selected].surface) {
        .skin => .skin,
        .eyes => .eyes,
        .armor, .neutral => .armor,
        .energy => .energy,
    };
}

pub fn cycleImportedFilter(self: *Creator, delta: i32) void {
    self.imported_filter = @intCast(@mod(@as(i32, self.imported_filter) + delta, 6));
    const doc = self.imported_doc orelse return;
    for (doc.parts, 0..) |part, i| if (self.matchesFilter(part.surface)) {
        self.imported_selected = i;
        self.alignImportedPalette();
        return;
    };
}

pub fn cycleImportedSurface(self: *Creator, delta: i32) void {
    const doc = self.imported_doc orelse return;
    if (self.imported_selected >= doc.parts.len) return;
    const part = &doc.parts[self.imported_selected];
    const surface_count: i32 = @intCast(enum_compat.fields(Modifiers.Surface).len);
    const before = part.surface;
    const after: Modifiers.Surface = @enumFromInt(@mod(@as(i32, @intCast(@intFromEnum(part.surface))) + delta, surface_count));
    self.recordImported(.{ .surface = .{ .id = part.id, .before = before, .after = after } });
    self.imported_palette = switch (part.surface) {
        .skin => .skin,
        .eyes => .eyes,
        .armor, .neutral => .armor,
        .energy => .energy,
    };
}

pub fn cycleImportedPalette(self: *Creator, delta: i32) void {
    const doc = self.imported_doc orelse return;
    const count: i32 = @intCast(paletteColorCount(self.imported_palette));
    self.imported_palette_variant = @intCast(@mod(@as(i32, self.imported_palette_variant) + delta, count));
    const color = paletteColor(self.imported_palette, self.imported_palette_variant);
    const before = importedPaletteColor(doc, self.imported_palette);
    self.recordImported(.{ .palette = .{ .slot = self.imported_palette, .before = before, .after = color } });
}

pub fn adjustImportedColor(self: *Creator, channel: usize, delta: f32) void {
    const doc = self.imported_doc orelse return;
    if (channel >= 3) return;
    const before = importedPaletteColor(doc, self.imported_palette);
    var after = before;
    after[channel] = std.math.clamp(after[channel] + delta, 0, 1);
    if (std.mem.eql(f32, &before, &after)) return;
    self.recordImported(.{ .palette = .{ .slot = self.imported_palette, .before = before, .after = after } });
}

fn importedPaletteColor(doc: *const Modifiers.Document, slot: Modifiers.Palette) [3]f32 {
    return switch (slot) { .skin => doc.skin_color, .eyes => doc.eye_color, .armor => doc.armor_color, .energy => doc.energy_color };
}

fn recordImported(self: *Creator, command: Modifiers.Command) void {
    const doc = self.imported_doc orelse return;
    self.imported_history.applyAndPush(std.heap.page_allocator, doc, command) catch return;
    self.markImportedDirty(command);
    self.imported_status = .unsaved;
}

pub fn undoImported(self: *Creator, allocator: std.mem.Allocator) void {
    const doc = self.imported_doc orelse return;
    const command = self.imported_history.undo() orelse return;
    command.apply(allocator, doc, .before) catch {
        self.imported_history.cursor += 1;
        return;
    };
    self.markImportedDirty(command);
    self.alignImportedPalette();
    self.imported_status = .unsaved;
}

pub fn redoImported(self: *Creator, allocator: std.mem.Allocator) void {
    const doc = self.imported_doc orelse return;
    const command = self.imported_history.redo() orelse return;
    command.apply(allocator, doc, .after) catch {
        self.imported_history.cursor -= 1;
        return;
    };
    self.markImportedDirty(command);
    self.alignImportedPalette();
    self.imported_status = .unsaved;
}

pub fn clearImportedHistory(self: *Creator) void {
    self.imported_history = .{};
    self.imported_dirty_len = 0;
    self.imported_dirty_all = false;
}

pub const DirtySnapshot = struct { ids: [imported_history_capacity]u32, len: usize, all: bool };

pub fn takeImportedDirty(self: *Creator) DirtySnapshot {
    const result: DirtySnapshot = .{ .ids = self.imported_dirty_ids, .len = self.imported_dirty_len, .all = self.imported_dirty_all };
    self.imported_dirty_len = 0;
    self.imported_dirty_all = false;
    return result;
}

fn markImportedDirty(self: *Creator, command: Modifiers.Command) void {
    const id: ?u32 = switch (command) {
        .surface => |c| c.id,
        .color => |c| c.id,
        .enabled => |c| c.id,
        .scale => |c| c.id,
        .offset => |c| c.id,
        .palette => {
            self.imported_dirty_all = true;
            return;
        },
    };
    if (self.imported_dirty_all) return;
    for (self.imported_dirty_ids[0..self.imported_dirty_len]) |existing| if (existing == id.?) return;
    if (self.imported_dirty_len == self.imported_dirty_ids.len) {
        self.imported_dirty_all = true;
        return;
    }
    self.imported_dirty_ids[self.imported_dirty_len] = id.?;
    self.imported_dirty_len += 1;
}

fn paletteColorCount(slot: Modifiers.Palette) usize {
    return switch (slot) {
        .skin => Profile.skin_tones.len,
        .eyes, .energy => Profile.accent_colors.len,
        .armor => Profile.outfit_colors.len,
    };
}

fn paletteColor(slot: Modifiers.Palette, index: usize) [3]f32 {
    const source = switch (slot) {
        .skin => Profile.skin_tones[index % Profile.skin_tones.len],
        .eyes, .energy => Profile.accent_colors[index % Profile.accent_colors.len],
        .armor => Profile.outfit_colors[index % Profile.outfit_colors.len],
    };
    return .{ source[0], source[1], source[2] };
}

pub fn paintImportedPart(self: *Creator) void {
    const doc = self.imported_doc orelse return;
    if (self.imported_selected >= doc.parts.len) return;
    const part = &doc.parts[self.imported_selected];
    const before = part.color;
    const after: ?[3]f32 = if (part.color != null) null else switch (self.imported_palette) {
        .skin => doc.skin_color,
        .eyes => doc.eye_color,
        .armor => doc.armor_color,
        .energy => doc.energy_color,
    };
    self.recordImported(.{ .color = .{ .id = part.id, .before = before, .after = after } });
}

pub fn toggleImportedPart(self: *Creator) void {
    const doc = self.imported_doc orelse return;
    if (self.imported_selected >= doc.parts.len) return;
    const part = doc.parts[self.imported_selected];
    self.recordImported(.{ .enabled = .{ .id = part.id, .before = part.enabled, .after = !part.enabled } });
}

pub fn matchesFilter(self: *const Creator, surface: Modifiers.Surface) bool {
    return self.imported_filter == 0 or @intFromEnum(surface) + 1 == self.imported_filter;
}

/// Changes the selected field; clothing skips types not yet owned.
pub fn adjust(self: *Creator, delta: i32) void {
    if (self.adjustWithMods(delta)) return;
    self.draft.adjust(self.field, delta);
    if (self.field == .species) {
        for (0..Profile.species_count) |_| {
            if (isOwned(self.owned_species, self.draft.species)) return;
            self.draft.adjust(.species, delta);
        }
        return;
    }
    if (self.field == .armor) {
        for (0..enum_compat.fields(Profile.Armor).len) |_| {
            if (isOwned(self.owned_armor, self.draft.armor)) return;
            self.draft.adjust(.armor, delta);
        }
        return;
    }
    if (self.field != .clothing) return;
    for (0..enum_compat.fields(Profile.Clothing).len) |_| {
        if (isOwned(self.owned, self.draft.clothing)) return;
        self.draft.adjust(.clothing, delta);
    }
}

fn isOwned(mask: anytype, item: anytype) bool {
    const bit = @as(@TypeOf(mask), 1) << @intCast(@intFromEnum(item));
    return mask & bit != 0;
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
        if (self.field == .armor and !isOwned(self.owned_armor, @as(Profile.Armor, @enumFromInt(choice)))) continue;
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
            .imported_glb => if (self.imported_rig_status_len > 0) "IMPORTED GLB (PREVIEW READY)" else "IMPORTED GLB (IMPORT FIRST)",
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
        .armor_metal_r => colorChannelLabel(buffer, "METAL RED", p.armor_metal_color, p.armor, 0),
        .armor_metal_g => colorChannelLabel(buffer, "METAL GREEN", p.armor_metal_color, p.armor, 1),
        .armor_metal_b => colorChannelLabel(buffer, "METAL BLUE", p.armor_metal_color, p.armor, 2),
        .armor_secondary_r => colorChannelLabel(buffer, "SECONDARY RED", p.armor_secondary_color, p.armor, 0),
        .armor_secondary_g => colorChannelLabel(buffer, "SECONDARY GREEN", p.armor_secondary_color, p.armor, 1),
        .armor_secondary_b => colorChannelLabel(buffer, "SECONDARY BLUE", p.armor_secondary_color, p.armor, 2),
        .armor_trim_r => colorChannelLabel(buffer, "TRIM RED", p.armor_trim_color, p.armor, 0),
        .armor_trim_g => colorChannelLabel(buffer, "TRIM GREEN", p.armor_trim_color, p.armor, 1),
        .armor_trim_b => colorChannelLabel(buffer, "TRIM BLUE", p.armor_trim_color, p.armor, 2),
    };
}

fn colorChannelLabel(buffer: []u8, label: []const u8, custom: ?[3]f32, armor: Profile.Armor, channel: usize) []const u8 {
    const ArmorDef = @import("../character/armor.zig");
    const def = ArmorDef.find(&ArmorDef.builtin_sets, @tagName(armor)) orelse &ArmorDef.builtin_sets[1];
    const defaults: [3]f32 = switch (label[0]) {
        'M' => .{ def.metal.r, def.metal.g, def.metal.b },
        'S' => .{ def.secondary.r, def.secondary.g, def.secondary.b },
        else => .{ def.trim.r, def.trim.g, def.trim.b },
    };
    const base = custom orelse defaults;
    return std.fmt.bufPrint(buffer, "{s} {d:.2}", .{ label, base[channel] }) catch buffer;
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
    // Select height directly so adding a field earlier in the list cannot change this edit.
    c.field = .height;
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

test "imported designer keyboard undo restores the saved sidecar state and redo reapplies it" {
    var parts = [_]Modifiers.Part{.{ .id = 0, .label = "Body", .center = .{ 0, 0, 0 }, .vertex_count = 3 }};
    var doc: Modifiers.Document = .{ .source_hash = "fixture", .parts = &parts };
    var c: Creator = .{ .open = true, .imported_doc = &doc, .imported_open = true };
    const before = try std.json.Stringify.valueAlloc(std.testing.allocator, doc, .{});
    defer std.testing.allocator.free(before);
    _ = c.key(.right);
    try std.testing.expectEqual(Modifiers.Surface.skin, doc.parts[0].surface);
    _ = c.key(.undo);
    const undone = try std.json.Stringify.valueAlloc(std.testing.allocator, doc, .{});
    defer std.testing.allocator.free(undone);
    try std.testing.expectEqualStrings(before, undone);
    _ = c.key(.redo);
    try std.testing.expectEqual(Modifiers.Surface.skin, doc.parts[0].surface);
    try std.testing.expectEqual(@as(usize, 1), c.imported_history.cursor);
}

test "imported selection wraps safely for extreme signed navigation deltas" {
    var parts = [_]Modifiers.Part{
        .{ .id = 0, .label = "A", .center = .{ 0, 0, 0 }, .vertex_count = 3 },
        .{ .id = 1, .label = "B", .center = .{ 0, 0, 0 }, .vertex_count = 3 },
        .{ .id = 2, .label = "C", .center = .{ 0, 0, 0 }, .vertex_count = 3 },
    };
    var doc: Modifiers.Document = .{ .source_hash = "fixture", .parts = &parts };
    var c: Creator = .{ .imported_doc = &doc };

    c.moveImported(std.math.minInt(isize));
    try std.testing.expectEqual(@as(usize, 1), c.imported_selected);
    c.moveImported(std.math.maxInt(isize));
    try std.testing.expectEqual(@as(usize, 2), c.imported_selected);
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
