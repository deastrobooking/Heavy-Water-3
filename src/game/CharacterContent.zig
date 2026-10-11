//! Mod-declared character content: hairstyles, faces, armor sets, palettes and cel styles. A mod
//! lists JSON files under `"character"` in its manifest; each file is validated and becomes
//! entries in a `Registry`.
//!
//! The schemas map 1:1 onto the real data structs the character systems already draw from, so a
//! key is a field name and a value has that field's type:
//! - hair style  -> `hair_style.StyleDef` (`clumps` are `ClumpDef`, `cap` is `CapDef`)
//! - face preset -> `spec.FacePreset` (`masculine` and `feminine` are `spec.HeadSpec`)
//! - armor set   -> `armor.ArmorSetDef` (`pieces` are `armor.Piece`, `shape` is `spec.ShapeSpec`)
//! - cel style   -> `CelStyle.CelStyle` (`materials.<name>` are `MaterialStyle`)
//! Struct fields are read by reflection, so a field added to one of those structs becomes a valid
//! key without touching this file. Palettes (creator swatches) have no struct of their own.
//!
//! Loading parses into typed payloads and then runs the real `validate()` of each struct; a
//! failure is reported against the key that caused it. The conversion functions near the bottom
//! (`hairStyle`, `facePreset`, `armorSet`, `celStyle`) re-run the same validation and are what the
//! game calls, so nothing unvalidated reaches the generators.
//!
//! Rules (docs/mods.md, "Character content"):
//! - **Namespaced.** An entry is `<mod>.<id>`; a mod cannot define another mod's ids.
//! - **All or nothing.** A file with any problem rejects the whole mod, with one `Diagnostic`
//!   (file, key path, reason) per problem. Validation never panics on mod data.
//! - **Bounded.** Fixed counts and lengths; allocation happens when a mod loads, never per frame.
//! - **Stable.** Handles never change during a run; listing order is mod name, then declaration
//!   order, so it does not depend on directory order.
const std = @import("std");
const enum_compat = @import("enum_compat");
const spec = @import("../character/spec.zig");
const armor = @import("../character/armor.zig");
const hair_style = @import("../character/hair_style.zig");
const cel = @import("../character/CelStyle.zig");

const Rgb = spec.Rgb;
const CharacterContent = @This();

pub const format_version: u32 = 1;
/// Mirrors `script/Host.name_len`; `mod/Mod.zig` asserts they agree.
pub const mod_name_len = 24;
pub const id_len = 24;
pub const qualified_len = 48;
pub const display_len = 32;
pub const max_per_mod = 64;
pub const max_registry_entries = 256;
pub const max_diagnostics = 16;
pub const max_palette_colors = 8;

pub const Kind = enum { hair_style, face_preset, armor_set, palette, cel_style };
pub const kind_count = 5;

/// The JSON array that holds a kind's entries.
pub fn sectionKey(kind: Kind) []const u8 {
    return switch (kind) {
        .hair_style => "hair_styles",
        .face_preset => "face_presets",
        .armor_set => "armor_sets",
        .palette => "palettes",
        .cel_style => "cel_styles",
    };
}

// ---- Diagnostics -----------------------------------------------------------------------------

pub const Code = enum {
    invalid_json,
    wrong_type,
    missing_key,
    unknown_key,
    out_of_range,
    bad_choice,
    bad_id,
    bad_name,
    bad_color,
    bad_format,
    duplicate_id,
    too_many,
    too_long,
    inconsistent,
    mod_conflict,
    registry_full,

    pub fn text(self: Code) []const u8 {
        return switch (self) {
            .invalid_json => "not valid JSON",
            .wrong_type => "wrong JSON type",
            .missing_key => "required key is missing",
            .unknown_key => "unknown key (typo?)",
            .out_of_range => "value out of range",
            .bad_choice => "not one of the allowed values",
            .bad_id => "bad id (lowercase letters, digits, underscores)",
            .bad_name => "bad display name (printable ASCII)",
            .bad_color => "bad color (\"#rrggbb\" or [r,g,b])",
            .bad_format => "unsupported content format",
            .duplicate_id => "id already declared in this mod",
            .too_many => "too many entries or items",
            .too_long => "text too long",
            .inconsistent => "values contradict each other",
            .mod_conflict => "mod already installed with different content",
            .registry_full => "character content registry is full",
        };
    }
};

pub const Diagnostic = struct {
    file: [48]u8 = @splat(0),
    file_len: u8 = 0,
    key: [64]u8 = @splat(0),
    key_len: u8 = 0,
    detail: [192]u8 = @splat(0),
    detail_len: u8 = 0,
    code: Code = .invalid_json,

    pub fn fileName(self: *const Diagnostic) []const u8 {
        return self.file[0..self.file_len];
    }
    pub fn keyPath(self: *const Diagnostic) []const u8 {
        return self.key[0..self.key_len];
    }
    pub fn detailText(self: *const Diagnostic) []const u8 {
        return self.detail[0..self.detail_len];
    }
    /// "file: key: reason (detail)".
    pub fn format(self: *const Diagnostic, buffer: []u8) []const u8 {
        const key = if (self.key_len == 0) "(file)" else self.keyPath();
        const detail = self.detailText();
        return (if (detail.len == 0)
            std.fmt.bufPrint(buffer, "{s}: {s}: {s}", .{ self.fileName(), key, self.code.text() })
        else
            std.fmt.bufPrint(buffer, "{s}: {s}: {s} ({s})", .{ self.fileName(), key, self.code.text(), detail })) catch buffer[0..0];
    }
};

pub const Report = struct {
    items: [max_diagnostics]Diagnostic = undefined,
    count: usize = 0,
    /// Problems beyond `max_diagnostics`, counted but not kept.
    dropped: usize = 0,

    pub fn ok(self: *const Report) bool {
        return self.count == 0 and self.dropped == 0;
    }
    pub fn add(self: *Report, file: []const u8, key: []const u8, code: Code, comptime fmt: []const u8, args: anytype) void {
        if (self.count == max_diagnostics) {
            self.dropped += 1;
            return;
        }
        var d: Diagnostic = .{ .code = code };
        d.file_len = @intCast(copyInto(&d.file, file));
        d.key_len = @intCast(copyInto(&d.key, key));
        const detail = std.fmt.bufPrint(&d.detail, fmt, args) catch d.detail[0..];
        d.detail_len = @intCast(detail.len);
        self.items[self.count] = d;
        self.count += 1;
    }
    pub fn slice(self: *const Report) []const Diagnostic {
        return self.items[0..self.count];
    }
    fn total(self: *const Report) usize {
        return self.count + self.dropped;
    }
};

fn copyInto(dest: []u8, text: []const u8) usize {
    const n = @min(dest.len, text.len);
    @memcpy(dest[0..n], text[0..n]);
    return n;
}

// ---- Ids -------------------------------------------------------------------------------------

pub fn validIdentifier(text: []const u8, limit: usize) bool {
    if (text.len == 0 or text.len >= limit) return false;
    for (text) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}

/// "<mod>.<id>", at most 47 bytes.
pub const Id = struct {
    buf: [qualified_len]u8 = @splat(0),
    len: u8 = 0,

    pub const empty: Id = .{};

    pub fn slice(self: *const Id) []const u8 {
        return self.buf[0..self.len];
    }
    pub fn isEmpty(self: *const Id) bool {
        return self.len == 0;
    }
    pub fn make(mod: []const u8, local: []const u8) Id {
        var id: Id = .{};
        const text = std.fmt.bufPrint(&id.buf, "{s}.{s}", .{ mod, local }) catch unreachable;
        id.len = @intCast(text.len);
        return id;
    }
    /// Parses a namespaced id from a save or the command line: `null` unless well formed.
    pub fn parse(text: []const u8) ?Id {
        const dot = std.mem.indexOfScalar(u8, text, '.') orelse return null;
        if (!validIdentifier(text[0..dot], mod_name_len) or !validIdentifier(text[dot + 1 ..], id_len)) return null;
        return make(text[0..dot], text[dot + 1 ..]);
    }
    pub fn eql(a: *const Id, b: *const Id) bool {
        return std.mem.eql(u8, a.slice(), b.slice());
    }
};

// ---- Entries ---------------------------------------------------------------------------------

const placeholder_clump: hair_style.ClumpDef = .{ .az = 0, .el = 0 };
const placeholder_piece: armor.Piece = .{ .kind = .blob, .anchor = .chest };

/// The `StyleDef` fields that are plain values; `name` is the entry id and `clumps` is a list.
pub const HairLook = struct { cap: hair_style.CapDef = .{} };
pub const HairData = struct {
    look: HairLook = .{},
    count: u8 = 0,
    clumps: [hair_style.max_clumps]hair_style.ClumpDef = @splat(placeholder_clump),
};
/// The `ArmorSetDef` fields that are plain values; `name` is the entry id, `title` the display
/// name and `pieces` a list.
pub const ArmorLook = struct {
    metal: Rgb = Rgb.hex(0xffffff),
    secondary: Rgb = Rgb.hex(0xffffff),
    trim: Rgb = Rgb.hex(0xffffff),
    dark: Rgb = Rgb.hex(0x17242f),
    shape: spec.ShapeSpec = .{},
    visor: armor.VisorShape = .wrap,
};
pub const ArmorData = struct {
    look: ArmorLook = .{},
    count: u8 = 0,
    pieces: [armor.max_pieces]armor.Piece = @splat(placeholder_piece),
};
pub const PaletteRole = enum { hair, outfit, accent, skin, coat };
pub const PaletteData = struct {
    role: PaletteRole = .outfit,
    count: u8 = 0,
    colors: [max_palette_colors][3]f32 = @splat(.{ 0, 0, 0 }),
};

comptime {
    // The schemas are the structs themselves; a new field on one of them must be classified here.
    std.debug.assert(enum_compat.structFields(hair_style.StyleDef).len == 3);
    std.debug.assert(enum_compat.structFields(armor.ArmorSetDef).len == enum_compat.structFields(ArmorLook).len + 3);
    for (enum_compat.structFields(ArmorLook)) |f| std.debug.assert(@hasField(armor.ArmorSetDef, f.name));
    std.debug.assert(cel.presets.len == enum_compat.fields(CelBase).len);
}

pub const Data = union(Kind) {
    hair_style: HairData,
    /// The preset's `name` is a slice, so the payload keeps it empty; `facePreset` fills it in.
    face_preset: spec.FacePreset,
    armor_set: ArmorData,
    palette: PaletteData,
    cel_style: cel.CelStyle,
};

pub const Entry = struct {
    mod: [mod_name_len]u8 = @splat(0),
    mod_len: u8 = 0,
    local: [id_len]u8 = @splat(0),
    local_len: u8 = 0,
    display: [display_len]u8 = @splat(0),
    display_len: u8 = 0,
    /// Position within the mod's declarations of this kind (the stable list order).
    index: u16 = 0,
    data: Data,

    pub fn kind(self: *const Entry) Kind {
        return std.meta.activeTag(self.data);
    }
    pub fn modName(self: *const Entry) []const u8 {
        return self.mod[0..self.mod_len];
    }
    pub fn localId(self: *const Entry) []const u8 {
        return self.local[0..self.local_len];
    }
    pub fn name(self: *const Entry) []const u8 {
        return self.display[0..self.display_len];
    }
    pub fn id(self: *const Entry) Id {
        return Id.make(self.modName(), self.localId());
    }
    /// Color `i` of a palette entry.
    pub fn paletteColor(self: *const Entry, i: usize) ?[3]f32 {
        const p = switch (self.data) {
            .palette => |*p| p,
            else => return null,
        };
        return if (i < p.count) p.colors[i] else null;
    }
};

pub const Handle = u16;

// ---- Reading JSON into the real structs ------------------------------------------------------

/// Any number past this is a typo, not a design; the struct's own validator sets the real range.
const value_bound = 1.0e6;

const Ctx = struct {
    report: *Report,
    file: []const u8,
    path: [64]u8 = undefined,
    len: usize = 0,

    fn append(self: *Ctx, text: []const u8) void {
        const n = @min(self.path.len - self.len, text.len);
        @memcpy(self.path[self.len..][0..n], text[0..n]);
        self.len += n;
    }
    /// Descends into `segment`; pass the result to `reset` to climb back.
    fn push(self: *Ctx, segment: []const u8) usize {
        const mark = self.len;
        if (self.len > 0) self.append(".");
        self.append(segment);
        return mark;
    }
    fn pushIndex(self: *Ctx, i: usize) usize {
        const mark = self.len;
        var buf: [12]u8 = undefined;
        self.append(std.fmt.bufPrint(&buf, "[{d}]", .{i}) catch "[?]");
        return mark;
    }
    fn reset(self: *Ctx, mark: usize) void {
        self.len = mark;
    }
    fn fail(self: *Ctx, code: Code, comptime fmt: []const u8, args: anytype) void {
        self.report.add(self.file, self.path[0..self.len], code, fmt, args);
    }
    fn failKey(self: *Ctx, key: []const u8, code: Code, comptime fmt: []const u8, args: anytype) void {
        const mark = self.push(key);
        defer self.reset(mark);
        self.fail(code, fmt, args);
    }
};

fn number(v: std.json.Value) ?f64 {
    const n: f64 = switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => return null,
    };
    return if (std.math.isFinite(n)) n else null;
}

fn clip(text: []const u8) []const u8 {
    return text[0..@min(text.len, 24)];
}

fn parseColor(raw: std.json.Value, max: f64) ?[3]f32 {
    switch (raw) {
        .string => |s| {
            if (s.len != 7 or s[0] != '#') return null;
            var out: [3]f32 = undefined;
            for (&out, 0..) |*c, i| {
                const byte = std.fmt.parseInt(u8, s[1 + i * 2 ..][0..2], 16) catch return null;
                c.* = @as(f32, @floatFromInt(byte)) / 255;
            }
            return out;
        },
        .array => |a| {
            if (a.items.len != 3) return null;
            var out: [3]f32 = undefined;
            for (a.items, &out) |item, *c| {
                const n = number(item) orelse return null;
                if (n < 0 or n > max) return null;
                c.* = @floatCast(n);
            }
            return out;
        },
        else => return null,
    }
}

fn contains(comptime list: []const []const u8, name: []const u8) bool {
    inline for (list) |item| if (std.mem.eql(u8, item, name)) return true;
    return false;
}

fn readable(comptime F: type) bool {
    return @typeInfo(F) != .pointer;
}

fn enumNames(comptime E: type) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (enum_compat.fields(E), 0..) |f, i| s = s ++ (if (i == 0) "" else "|") ++ f.name;
        return s;
    }
}

const StructOpts = struct {
    /// Fields without a usable default: absent means a `missing_key` problem.
    required: []const []const u8 = &.{},
    /// Keys the caller reads itself (`id`, `name`, lists).
    extra: []const []const u8 = &.{},
    /// Struct fields the caller reads itself.
    skip: []const []const u8 = &.{},
};

fn keyList(comptime T: type, comptime opts: StructOpts) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (enum_compat.structFields(T)) |f| {
            if (!readable(f.type) or contains(opts.skip, f.name)) continue;
            s = s ++ (if (s.len == 0) "" else ", ") ++ f.name;
        }
        for (opts.extra) |e| s = s ++ (if (s.len == 0) "" else ", ") ++ e;
        return s;
    }
}

fn isKnown(comptime T: type, comptime opts: StructOpts, key: []const u8) bool {
    inline for (enum_compat.structFields(T)) |f| {
        if (comptime readable(f.type)) if (std.mem.eql(u8, f.name, key)) return true;
    }
    inline for (opts.extra) |e| if (std.mem.eql(u8, e, key)) return true;
    return false;
}

/// Reads a JSON object into `out` field by field. Fields absent from the JSON keep the value
/// `out` already holds (the struct's default, or a preset it was started from).
fn readStruct(comptime T: type, ctx: *Ctx, raw: std.json.Value, out: *T, comptime opts: StructOpts) void {
    const obj = switch (raw) {
        .object => |o| o,
        else => return ctx.fail(.wrong_type, "expected an object", .{}),
    };
    var it = obj.iterator();
    while (it.next()) |kv| {
        const key = kv.key_ptr.*;
        if (!isKnown(T, opts, key)) ctx.failKey(key, .unknown_key, "accepts: {s}", .{comptime keyList(T, opts)});
    }
    inline for (enum_compat.structFields(T)) |f| {
        if (comptime (!readable(f.type) or contains(opts.skip, f.name))) continue;
        if (obj.get(f.name)) |v| {
            const mark = ctx.push(f.name);
            defer ctx.reset(mark);
            readField(f.type, ctx, v, &@field(out, f.name));
        } else if (comptime contains(opts.required, f.name)) {
            ctx.failKey(f.name, .missing_key, "", .{});
        }
    }
}

fn readField(comptime F: type, ctx: *Ctx, raw: std.json.Value, out: *F) void {
    switch (@typeInfo(F)) {
        .float => if (number(raw)) |n| {
            if (@abs(n) > value_bound) return ctx.fail(.out_of_range, "{d} is far outside any usable range", .{n});
            out.* = @floatCast(n);
        } else ctx.fail(.wrong_type, "expected a number", .{}),
        .int => switch (raw) {
            .integer => |n| {
                if (n < 0 or n > std.math.maxInt(F)) return ctx.fail(.out_of_range, "{d} not in 0..{d}", .{ n, std.math.maxInt(F) });
                out.* = @intCast(n);
            },
            else => ctx.fail(.wrong_type, "expected a whole number", .{}),
        },
        .bool => switch (raw) {
            .bool => |b| out.* = b,
            else => ctx.fail(.wrong_type, "expected true or false", .{}),
        },
        .@"enum" => readEnum(F, ctx, raw, out),
        .optional => |o| switch (raw) {
            .null => out.* = null,
            else => {
                var inner: o.child = out.* orelse std.mem.zeroInit(o.child, .{});
                readField(o.child, ctx, raw, &inner);
                out.* = inner;
            },
        },
        .array => |a| {
            if (a.child != f32) @compileError("unsupported array field " ++ @typeName(F));
            const items = switch (raw) {
                .array => |arr| arr.items,
                else => return ctx.fail(.wrong_type, "expected {d} numbers", .{a.len}),
            };
            if (items.len != a.len) return ctx.fail(.wrong_type, "expected exactly {d} numbers, got {d}", .{ a.len, items.len });
            var tmp: F = undefined;
            for (items, &tmp, 0..) |item, *slot, i| {
                const n = number(item) orelse return ctx.fail(.wrong_type, "item {d} is not a number", .{i});
                if (@abs(n) > value_bound) return ctx.fail(.out_of_range, "item {d} = {d} is far outside any usable range", .{ i, n });
                slot.* = @floatCast(n);
            }
            out.* = tmp;
        },
        .@"struct" => if (F == Rgb) {
            const c = parseColor(raw, 2) orelse return ctx.fail(.bad_color, "channels 0 to 2", .{});
            out.* = .{ .r = c[0], .g = c[1], .b = c[2] };
        } else readStruct(F, ctx, raw, out, .{}),
        else => @compileError("unsupported field type " ++ @typeName(F)),
    }
}

fn readEnum(comptime E: type, ctx: *Ctx, raw: std.json.Value, out: *E) void {
    const text = switch (raw) {
        .string => |s| s,
        else => return ctx.fail(.wrong_type, "expected a string", .{}),
    };
    inline for (enum_compat.fields(E)) |f| {
        if (std.mem.eql(u8, f.name, text)) {
            out.* = @enumFromInt(f.value);
            return;
        }
    }
    ctx.fail(.bad_choice, "\"{s}\"; one of {s}", .{ clip(text), comptime enumNames(E) });
}

/// Reads a JSON array of objects into `out[0..count]`, each starting from `init`.
fn readList(comptime T: type, ctx: *Ctx, raw: std.json.Value, out: []T, count: *u8, init: T, comptime required: []const []const u8) void {
    const items = switch (raw) {
        .array => |a| a.items,
        else => return ctx.fail(.wrong_type, "expected an array", .{}),
    };
    if (items.len > out.len) return ctx.fail(.too_many, "{d} items; at most {d}", .{ items.len, out.len });
    count.* = @intCast(items.len);
    for (items, 0..) |item, i| {
        const mark = ctx.pushIndex(i);
        defer ctx.reset(mark);
        out[i] = init;
        readStruct(T, ctx, item, &out[i], .{ .required = required });
    }
}

// ---- Per-kind parsing ------------------------------------------------------------------------

const CelBase = enum { heavy_water, watercolor, comic_ink, flat };

fn parseHair(ctx: *Ctx, item: std.json.Value, d: *HairData) void {
    readStruct(HairLook, ctx, item, &d.look, .{ .extra = &.{ "id", "name", "clumps" } });
    const obj = item.object;
    if (obj.get("clumps")) |v| {
        const mark = ctx.push("clumps");
        defer ctx.reset(mark);
        readList(hair_style.ClumpDef, ctx, v, &d.clumps, &d.count, placeholder_clump, &.{ "az", "el" });
    } else ctx.failKey("clumps", .missing_key, "a hairstyle is a list of clumps", .{});
}

fn parseFace(ctx: *Ctx, item: std.json.Value, fp: *spec.FacePreset) void {
    readStruct(spec.FacePreset, ctx, item, fp, .{ .extra = &.{ "id", "name" } });
}

fn parseArmor(ctx: *Ctx, item: std.json.Value, d: *ArmorData) void {
    readStruct(ArmorLook, ctx, item, &d.look, .{ .required = &.{ "metal", "secondary", "trim" }, .extra = &.{ "id", "name", "pieces" } });
    if (item.object.get("pieces")) |v| {
        const mark = ctx.push("pieces");
        defer ctx.reset(mark);
        readList(armor.Piece, ctx, v, &d.pieces, &d.count, placeholder_piece, &.{ "kind", "anchor" });
    }
}

fn parsePalette(ctx: *Ctx, item: std.json.Value, d: *PaletteData) void {
    const obj = item.object;
    const Keys = struct { role: PaletteRole = .outfit };
    var keys: Keys = .{};
    readStruct(Keys, ctx, item, &keys, .{ .required = &.{"role"}, .extra = &.{ "id", "name", "colors" } });
    d.role = keys.role;
    const raw = obj.get("colors") orelse return ctx.failKey("colors", .missing_key, "", .{});
    const items = switch (raw) {
        .array => |a| a.items,
        else => return ctx.failKey("colors", .wrong_type, "expected an array of colors", .{}),
    };
    if (items.len == 0) return ctx.failKey("colors", .missing_key, "at least one color", .{});
    if (items.len > max_palette_colors) return ctx.failKey("colors", .too_many, "at most {d} colors", .{max_palette_colors});
    d.count = @intCast(items.len);
    for (items, 0..) |c, i| {
        d.colors[i] = parseColor(c, 1) orelse {
            const mark = ctx.push("colors");
            defer ctx.reset(mark);
            const inner = ctx.pushIndex(i);
            defer ctx.reset(inner);
            return ctx.fail(.bad_color, "channels 0 to 1", .{});
        };
    }
}

fn parseCel(ctx: *Ctx, item: std.json.Value, style: *cel.CelStyle) void {
    const obj = item.object;
    if (obj.get("base")) |b| {
        var which: CelBase = .heavy_water;
        const mark = ctx.push("base");
        readEnum(CelBase, ctx, b, &which);
        ctx.reset(mark);
        style.* = cel.presets[@intFromEnum(which)].style.*;
    }
    readStruct(cel.CelStyle, ctx, item, style, .{ .extra = &.{ "id", "name", "base", "materials" }, .skip = &.{"materials"} });
    const materials = obj.get("materials") orelse return;
    const mats = switch (materials) {
        .object => |o| o,
        else => return ctx.failKey("materials", .wrong_type, "expected an object keyed by material", .{}),
    };
    const outer = ctx.push("materials");
    defer ctx.reset(outer);
    var it = mats.iterator();
    while (it.next()) |kv| {
        const key = kv.key_ptr.*;
        const index = for (enum_compat.fields(cel.Material)) |f| {
            if (std.mem.eql(u8, f.name, key)) break f.value;
        } else {
            ctx.failKey(key, .unknown_key, "materials: {s}", .{comptime enumNames(cel.Material)});
            continue;
        };
        const mark = ctx.push(key);
        defer ctx.reset(mark);
        readStruct(cel.MaterialStyle, ctx, kv.value_ptr.*, &style.materials[index], .{});
    }
}

// ---- Validation with the real validators, reported per key -------------------------------------

const Hint = struct { []const u8, []const u8 };

fn hintFor(comptime table: []const Hint, name: []const u8) []const u8 {
    inline for (table) |h| if (std.mem.eql(u8, h[0], name)) return h[1];
    return "";
}

/// The first field of `bad` that makes `ok` fail when set on `good`, or "".
fn offender(comptime T: type, bad: T, good: T, comptime ok: fn (T) bool) []const u8 {
    inline for (enum_compat.structFields(T)) |f| {
        var probe = good;
        @field(probe, f.name) = @field(bad, f.name);
        if (!ok(probe)) return f.name;
    }
    return "";
}

fn clumpOk(c: hair_style.ClumpDef) bool {
    const one = [_]hair_style.ClumpDef{c};
    hair_style.validate(.{ .name = "x", .clumps = &one }) catch return false;
    return true;
}
const clump_hints = [_]Hint{
    .{ "el", "-1.4 to pi/2" },
    .{ "az", "|az| <= 2 pi" },
    .{ "yaw", "|yaw| <= 2 pi" },
    .{ "pitch", "|pitch| <= pi/2" },
    .{ "length", "0.02 to 4 head heights" },
    .{ "width", "0.01 to 1" },
    .{ "thickness", "0 to 1" },
    .{ "taper", "0.4 to 6" },
    .{ "curl", "|curl| <= 2 pi" },
    .{ "flick", "|flick| <= pi" },
    .{ "stand", "0 to 1" },
    .{ "spike", "0 to 1" },
    .{ "layer", "0 to 3" },
};

fn capOk(c: hair_style.CapDef) bool {
    const one = [_]hair_style.ClumpDef{placeholder_clump};
    hair_style.validate(.{ .name = "x", .clumps = &one, .cap = c }) catch return false;
    return true;
}
const cap_hints = [_]Hint{
    .{ "hairline", "five elevations, each -1.5 to pi/2" },
    .{ "lift", "0 to 0.5" },
};

fn checkHair(ctx: *Ctx, e: *const Entry) void {
    if (hairStyle(e)) |_| return else |_| {}
    const d = &e.data.hair_style;
    const before = ctx.report.total();
    if (d.count == 0) ctx.failKey("clumps", .missing_key, "a hairstyle needs at least one clump", .{});
    for (d.clumps[0..d.count], 0..) |c, i| {
        if (clumpOk(c)) continue;
        const outer = ctx.push("clumps");
        defer ctx.reset(outer);
        const mark = ctx.pushIndex(i);
        defer ctx.reset(mark);
        const field = offender(hair_style.ClumpDef, c, placeholder_clump, clumpOk);
        if (field.len == 0) ctx.fail(.inconsistent, "clump is not valid", .{}) else ctx.failKey(field, .out_of_range, "valid range: {s}", .{hintFor(&clump_hints, field)});
    }
    if (!capOk(d.look.cap)) {
        const outer = ctx.push("cap");
        defer ctx.reset(outer);
        const field = offender(hair_style.CapDef, d.look.cap, .{}, capOk);
        ctx.failKey(field, .out_of_range, "valid range: {s}", .{hintFor(&cap_hints, field)});
    }
    if (ctx.report.total() == before) ctx.failKey("clumps", .too_many, "at most {d} clumps counting mirrored twins twice", .{hair_style.max_clumps});
}

fn pieceOk(p: armor.Piece) bool {
    const one = [_]armor.Piece{p};
    (armor.ArmorSetDef{ .name = "x", .metal = Rgb.hex(0xffffff), .secondary = Rgb.hex(0xffffff), .trim = Rgb.hex(0xffffff), .pieces = &one }).validate() catch return false;
    return true;
}
const piece_hints = [_]Hint{
    .{ "offset", "each component within 1 meter" },
    .{ "size", "each component above 0 and at most 0.6 meters" },
    .{ "tilt", "each component within pi radians" },
    .{ "scale", "0.1 to 3" },
    .{ "exponent", "0.3 to 1.5" },
    .{ "taper", "-0.9 to 0.9" },
    .{ "shape", "see shape" },
};

fn shapeOk(s: spec.ShapeSpec) bool {
    (armor.ArmorSetDef{ .name = "x", .metal = Rgb.hex(0xffffff), .secondary = Rgb.hex(0xffffff), .trim = Rgb.hex(0xffffff), .shape = s }).validate() catch return false;
    return true;
}
const shape_hints = [_]Hint{
    .{ "flare", "0 to 1.5" },
    .{ "crest", "0 to 0.25 meters" },
    .{ "roundness", "0 to 1" },
    .{ "overlap", "0 to 1" },
};

fn failShape(ctx: *Ctx, s: spec.ShapeSpec) void {
    const field = offender(spec.ShapeSpec, s, .{}, shapeOk);
    if (field.len == 0) return ctx.fail(.inconsistent, "shape is not valid", .{});
    ctx.failKey(field, .out_of_range, "valid range: {s}", .{hintFor(&shape_hints, field)});
}

fn checkArmor(ctx: *Ctx, e: *const Entry) void {
    if (armorSet(e)) |_| return else |_| {}
    const d = &e.data.armor_set;
    const before = ctx.report.total();
    if (!shapeOk(d.look.shape)) {
        const mark = ctx.push("shape");
        defer ctx.reset(mark);
        failShape(ctx, d.look.shape);
    }
    for (d.pieces[0..d.count], 0..) |p, i| {
        if (pieceOk(p)) continue;
        const outer = ctx.push("pieces");
        defer ctx.reset(outer);
        const mark = ctx.pushIndex(i);
        defer ctx.reset(mark);
        const sided = switch (p.anchor) {
            .upper_arm, .forearm, .hand, .thigh, .shin => true,
            else => false,
        };
        if (sided and p.sides == .center) {
            ctx.failKey("sides", .inconsistent, "center is only for chest, hips, neck and head anchors", .{});
            continue;
        }
        const field = offender(armor.Piece, p, placeholder_piece, pieceOk);
        if (std.mem.eql(u8, field, "shape")) {
            const inner = ctx.push("shape");
            defer ctx.reset(inner);
            failShape(ctx, p.shape.?);
        } else if (field.len == 0) {
            ctx.fail(.inconsistent, "piece is not valid", .{});
        } else ctx.failKey(field, .out_of_range, "valid range: {s}", .{hintFor(&piece_hints, field)});
    }
    if (ctx.report.total() == before) ctx.fail(.inconsistent, "armor set is not valid", .{});
}

const Limit = struct { []const u8, f32, f32 };
/// Ranges a head can take and still produce a face; every built-in preset lies inside them
/// (a test keeps it so).
const head_limits = [_]Limit{
    .{ "cranium_width", 0.6, 1.1 },
    .{ "cranium_depth", 0.7, 1.15 },
    .{ "cranium_size", 0.85, 1.2 },
    .{ "cheek_width", 0.85, 1.15 },
    .{ "cheek_height", 0.15, 0.5 },
    .{ "jaw_taper", 0, 1 },
    .{ "chin_width", 0.2, 0.65 },
    .{ "chin_point", 0, 1 },
    .{ "chin_jut", -0.05, 0.08 },
    .{ "neck_length", 0.1, 0.45 },
    .{ "neck_thickness", 0.7, 1.4 },
    .{ "brow_ridge", 0, 0.03 },
    .{ "cheek_fullness", 0, 0.03 },
    .{ "nose_bridge", 0, 0.02 },
    .{ "nose_tip", 0, 0.03 },
};
const face_limits = [_]Limit{
    .{ "head_ratio", 5.4, 6.6 },
    .{ "eye_size_scale", 0.7, 1.4 },
    .{ "eye_aspect_scale", 0.7, 1.4 },
    .{ "eye_tilt", -0.2, 0.3 },
    .{ "eye_height_add", -0.08, 0.08 },
    .{ "brow_weight", 0.003, 0.025 },
    .{ "brow_tilt", -0.4, 0.5 },
    .{ "brow_gap", 0.015, 0.09 },
    .{ "nose_mark", 0, 1 },
    .{ "mouth_width", 0.02, 0.09 },
};

fn withinLimits(comptime T: type, v: T, comptime limits: []const Limit) bool {
    inline for (limits) |l| {
        const x = @field(v, l[0]);
        if (!(x >= l[1] and x <= l[2])) return false;
    }
    return true;
}

fn failLimits(comptime T: type, ctx: *Ctx, v: T, comptime limits: []const Limit) void {
    inline for (limits) |l| {
        const x = @field(v, l[0]);
        if (!(x >= l[1] and x <= l[2])) ctx.failKey(l[0], .out_of_range, "{d} not in {d}..{d}", .{ x, l[1], l[2] });
    }
}

/// Whether `h` yields an ordered, sane head outline (the geometry `HeadSpec.profile` feeds).
pub fn headOk(h: spec.HeadSpec) bool {
    if (!withinLimits(spec.HeadSpec, h, &head_limits)) return false;
    const p = h.profile();
    for (0..spec.HeadSpec.key_count) |i| {
        if (i > 0 and !(p.us[i] > p.us[i - 1])) return false;
        if (!(p.half_w[i] > 0.05 and p.half_w[i] < 0.6)) return false;
        if (!(p.front[i] > p.back[i] + 0.1)) return false;
    }
    return p.half_w[0] < p.half_w[3];
}

fn faceOk(fp: spec.FacePreset) bool {
    return withinLimits(spec.FacePreset, fp, &face_limits) and headOk(fp.masculine) and headOk(fp.feminine);
}

fn checkFace(ctx: *Ctx, fp: *const spec.FacePreset) void {
    if (faceOk(fp.*)) return;
    failLimits(spec.FacePreset, ctx, fp.*, &face_limits);
    inline for (.{ "masculine", "feminine" }) |side| {
        const head = @field(fp, side);
        const mark = ctx.push(side);
        defer ctx.reset(mark);
        if (!withinLimits(spec.HeadSpec, head, &head_limits)) {
            failLimits(spec.HeadSpec, ctx, head, &head_limits);
        } else if (!headOk(head)) {
            ctx.fail(.inconsistent, "these proportions give a degenerate head outline (check cranium size against width and depth)", .{});
        }
    }
}

fn celOk(s: cel.CelStyle) bool {
    s.validate() catch return false;
    return true;
}

const cel_hints = [_]Hint{
    .{ "ramp", "threshold, deep_threshold -1..1 (deep <= threshold); softness 0.001..0.5; tints 0..2" },
    .{ "rim", "width 0..0.6; strength 0..2" },
    .{ "specular", "threshold 0..1; softness 0.001..0.5; strength 0..2; tint 0..2" },
    .{ "outline", "width_px 0..12; tint 0..2" },
    .{ "emissive", "0 to 1" },
    .{ "face_softness", "0.001 to 0.5" },
    .{ "outline_scale", "0 to 8" },
    .{ "outline_min_world", "0 to 0.1" },
    .{ "outline_max_world", "min to 0.1" },
};

fn checkCel(ctx: *Ctx, style: *const cel.CelStyle) void {
    if (celOk(style.*)) return;
    const before = ctx.report.total();
    const good = cel.heavy_water;
    inline for (.{ "face_softness", "outline_scale", "outline_min_world", "outline_max_world" }) |field| {
        var probe = good;
        @field(probe, field) = @field(style, field);
        if (!celOk(probe)) ctx.failKey(field, .out_of_range, "valid range: {s}", .{hintFor(&cel_hints, field)});
    }
    for (0..cel.material_count) |i| {
        inline for (.{ "ramp", "rim", "specular", "outline", "emissive" }) |part| {
            var probe = good;
            @field(probe.materials[i], part) = @field(style.materials[i], part);
            if (!celOk(probe)) {
                const outer = ctx.push("materials");
                defer ctx.reset(outer);
                const mark = ctx.push(enum_compat.fields(cel.Material)[i].name);
                defer ctx.reset(mark);
                ctx.failKey(part, .out_of_range, "valid range: {s}", .{hintFor(&cel_hints, part)});
            }
        }
    }
    if (ctx.report.total() == before) ctx.fail(.inconsistent, "cel style is not valid", .{});
}

// ---- Conversions: entry -> the struct the generator takes ------------------------------------

pub const ConvertError = error{ WrongKind, InvalidContent };

/// The entry as a `StyleDef`, validated. Borrows the entry's storage: the registry (or batch)
/// must outlive anything built from it.
pub fn hairStyle(e: *const Entry) ConvertError!hair_style.StyleDef {
    if (e.data != .hair_style) return error.WrongKind;
    const d = &e.data.hair_style;
    const def: hair_style.StyleDef = .{ .name = e.localId(), .clumps = d.clumps[0..d.count], .cap = d.look.cap };
    hair_style.validate(def) catch return error.InvalidContent;
    return def;
}

/// The entry as a `FacePreset` (both heads checked), named after the entry.
pub fn facePreset(e: *const Entry) ConvertError!spec.FacePreset {
    if (e.data != .face_preset) return error.WrongKind;
    var fp = e.data.face_preset;
    fp.name = e.localId();
    if (!faceOk(fp)) return error.InvalidContent;
    return fp;
}

/// One head of a face preset, checked.
pub fn headSpec(e: *const Entry, feminine: bool) ConvertError!spec.HeadSpec {
    const fp = try facePreset(e);
    return if (feminine) fp.feminine else fp.masculine;
}

/// The entry as an `ArmorSetDef`, validated. Borrows the entry's storage like `hairStyle`.
pub fn armorSet(e: *const Entry) ConvertError!armor.ArmorSetDef {
    if (e.data != .armor_set) return error.WrongKind;
    const d = &e.data.armor_set;
    var def: armor.ArmorSetDef = .{ .name = e.localId(), .title = e.name(), .metal = d.look.metal, .secondary = d.look.secondary, .trim = d.look.trim, .pieces = d.pieces[0..d.count] };
    inline for (enum_compat.structFields(ArmorLook)) |f| @field(def, f.name) = @field(d.look, f.name);
    def.validate() catch return error.InvalidContent;
    return def;
}

/// The entry's cel style, validated, ready for `CelStyle.pack`.
pub fn celStyle(e: *const Entry) ConvertError!cel.CelStyle {
    if (e.data != .cel_style) return error.WrongKind;
    e.data.cel_style.validate() catch return error.InvalidContent;
    return e.data.cel_style;
}

// ---- Batch: one mod's validated content ------------------------------------------------------

pub const Batch = struct {
    allocator: std.mem.Allocator,
    mod: [mod_name_len]u8 = @splat(0),
    mod_len: u8 = 0,
    count: usize = 0,
    next_index: [kind_count]u16 = @splat(0),
    entries: [max_per_mod]Entry = undefined,

    pub fn create(allocator: std.mem.Allocator, mod_name: []const u8) !*Batch {
        std.debug.assert(validIdentifier(mod_name, mod_name_len));
        const self = try allocator.create(Batch);
        // Field by field: a struct literal would build the whole entry table on the stack first.
        self.allocator = allocator;
        self.mod = @splat(0);
        self.count = 0;
        self.next_index = @splat(0);
        @memcpy(self.mod[0..mod_name.len], mod_name);
        self.mod_len = @intCast(mod_name.len);
        return self;
    }
    pub fn destroy(self: *Batch) void {
        self.allocator.destroy(self);
    }
    pub fn modName(self: *const Batch) []const u8 {
        return self.mod[0..self.mod_len];
    }
    pub fn slice(self: *const Batch) []const Entry {
        return self.entries[0..self.count];
    }

    /// Validates one file's bytes and appends its entries. Problems go to `report`; the batch is
    /// unusable (call `finish`, which fails) once any were reported. Only allocation can fail.
    pub fn addFile(self: *Batch, file: []const u8, bytes: []const u8, report: *Report) error{OutOfMemory}!void {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return report.add(file, "", .invalid_json, "{s}", .{@errorName(err)}),
        };
        const root = switch (parsed) {
            .object => |o| o,
            else => return report.add(file, "", .wrong_type, "top level must be an object", .{}),
        };
        var it = root.iterator();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            if (std.mem.eql(u8, key, "format")) continue;
            if (!isSection(key)) report.add(file, key, .unknown_key, "sections: hair_styles, face_presets, armor_sets, palettes, cel_styles", .{});
        }
        switch (root.get("format") orelse .null) {
            .integer => |n| if (n != format_version) report.add(file, "format", .bad_format, "got {d}, want {d}", .{ n, format_version }),
            else => report.add(file, "format", .missing_key, "expected {d}", .{format_version}),
        }
        for (std.enums.values(Kind)) |kind| {
            const section = root.get(sectionKey(kind)) orelse continue;
            const array = switch (section) {
                .array => |a| a.items,
                else => {
                    report.add(file, sectionKey(kind), .wrong_type, "expected an array", .{});
                    continue;
                },
            };
            for (array, 0..) |item, i| self.addEntry(report, file, kind, i, item);
        }
    }

    fn addEntry(self: *Batch, report: *Report, file: []const u8, kind: Kind, index: usize, item: std.json.Value) void {
        var ctx: Ctx = .{ .report = report, .file = file };
        _ = ctx.push(sectionKey(kind));
        _ = ctx.pushIndex(index);
        if (item != .object) return ctx.fail(.wrong_type, "expected an object", .{});
        if (self.count == max_per_mod) return ctx.fail(.too_many, "at most {d} entries per mod", .{max_per_mod});
        const obj = item.object;
        const problems_before = report.total();
        var entry: Entry = .{ .index = self.next_index[@intFromEnum(kind)], .data = switch (kind) {
            .hair_style => .{ .hair_style = .{} },
            .face_preset => .{ .face_preset = .{ .name = "" } },
            .armor_set => .{ .armor_set = .{} },
            .palette => .{ .palette = .{} },
            .cel_style => .{ .cel_style = cel.heavy_water },
        } };
        @memcpy(entry.mod[0..self.mod_len], self.modName());
        entry.mod_len = self.mod_len;

        var valid_header = true;
        if (obj.get("id")) |v| switch (v) {
            .string => |s| if (validIdentifier(s, id_len)) {
                @memcpy(entry.local[0..s.len], s);
                entry.local_len = @intCast(s.len);
            } else {
                valid_header = false;
                ctx.failKey("id", .bad_id, "\"{s}\", at most {d} characters", .{ clip(s), id_len - 1 });
            },
            else => {
                valid_header = false;
                ctx.failKey("id", .wrong_type, "expected a string", .{});
            },
        } else {
            valid_header = false;
            ctx.failKey("id", .missing_key, "", .{});
        }
        if (obj.get("name")) |v| switch (v) {
            .string => |s| if (validName(s)) {
                @memcpy(entry.display[0..s.len], s);
                entry.display_len = @intCast(s.len);
            } else ctx.failKey("name", if (s.len >= display_len) .too_long else .bad_name, "1 to {d} printable ASCII characters", .{display_len - 1}),
            else => ctx.failKey("name", .wrong_type, "expected a string", .{}),
        } else ctx.failKey("name", .missing_key, "the label shown in the creator", .{});

        if (valid_header) for (self.entries[0..self.count]) |*other| {
            if (other.kind() == kind and std.mem.eql(u8, other.localId(), entry.localId())) {
                ctx.failKey("id", .duplicate_id, "\"{s}\"", .{entry.localId()});
                valid_header = false;
                break;
            }
        };

        switch (kind) {
            .hair_style => parseHair(&ctx, item, &entry.data.hair_style),
            .face_preset => parseFace(&ctx, item, &entry.data.face_preset),
            .armor_set => parseArmor(&ctx, item, &entry.data.armor_set),
            .palette => parsePalette(&ctx, item, &entry.data.palette),
            .cel_style => parseCel(&ctx, item, &entry.data.cel_style),
        }
        // The real validators run only on content that parsed, so one typo is one diagnostic.
        if (report.total() == problems_before) switch (kind) {
            .hair_style => checkHair(&ctx, &entry),
            .face_preset => checkFace(&ctx, &entry.data.face_preset),
            .armor_set => checkArmor(&ctx, &entry),
            .palette => {},
            .cel_style => checkCel(&ctx, &entry.data.cel_style),
        };
        if (!valid_header) return;
        self.entries[self.count] = entry;
        self.count += 1;
        self.next_index[@intFromEnum(kind)] += 1;
    }

    /// Fails when `report` holds any problem from this batch's files.
    pub fn finish(self: *Batch, report: *Report) error{InvalidCharacterContent}!void {
        _ = self;
        if (!report.ok()) return error.InvalidCharacterContent;
    }
};

fn isSection(key: []const u8) bool {
    for (std.enums.values(Kind)) |k| if (std.mem.eql(u8, key, sectionKey(k))) return true;
    return false;
}

fn validName(text: []const u8) bool {
    if (text.len == 0 or text.len >= display_len or text[0] == ' ') return false;
    for (text) |c| if (c < 0x20 or c > 0x7e) return false;
    return true;
}

// ---- Registry --------------------------------------------------------------------------------

pub const InstallOutcome = enum { installed, unchanged };

/// Every installed entry, with stable handles and a sorted listing per kind.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,
    count: usize = 0,
    /// Handles per kind, sorted by (mod name, declaration index); `order[k * capacity ..]`.
    order: []Handle,
    order_counts: [kind_count]u16 = @splat(0),

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Registry {
        std.debug.assert(capacity <= std.math.maxInt(Handle));
        const entries = try allocator.alloc(Entry, capacity);
        errdefer allocator.free(entries);
        const order = try allocator.alloc(Handle, capacity * kind_count);
        return .{ .allocator = allocator, .entries = entries, .order = order };
    }
    pub fn deinit(self: *Registry) void {
        self.allocator.free(self.entries);
        self.allocator.free(self.order);
        self.* = undefined;
    }
    pub fn get(self: *const Registry, handle: Handle) *const Entry {
        std.debug.assert(handle < self.count);
        return &self.entries[handle];
    }
    /// Handles of one kind, in stable display order.
    pub fn list(self: *const Registry, kind: Kind) []const Handle {
        const k = @intFromEnum(kind);
        return self.order[k * self.entries.len ..][0..self.order_counts[k]];
    }
    pub fn find(self: *const Registry, kind: Kind, id: *const Id) ?Handle {
        for (self.list(kind)) |h| {
            const e = &self.entries[h];
            const dot = std.mem.indexOfScalar(u8, id.slice(), '.') orelse return null;
            if (std.mem.eql(u8, e.modName(), id.slice()[0..dot]) and std.mem.eql(u8, e.localId(), id.slice()[dot + 1 ..])) return h;
        }
        return null;
    }
    /// Position of `handle` within `list(kind)`.
    pub fn position(self: *const Registry, kind: Kind, handle: Handle) ?usize {
        return std.mem.indexOfScalar(Handle, self.list(kind), handle);
    }
    fn modBase(self: *const Registry, mod: []const u8) ?usize {
        for (self.entries[0..self.count], 0..) |*e, i| if (std.mem.eql(u8, e.modName(), mod)) return i;
        return null;
    }

    /// Whether `install` would succeed (or do nothing), without changing anything.
    pub fn canInstall(self: *const Registry, batch: *const Batch, report: *Report) error{ModConflict}!void {
        if (batch.count == 0) return;
        if (self.modBase(batch.modName())) |base| {
            if (!self.sameContent(base, batch)) {
                report.add(batch.modName(), "", .mod_conflict, "mod \"{s}\" is already installed", .{batch.modName()});
                return error.ModConflict;
            }
            return;
        }
        if (self.count + batch.count > self.entries.len) {
            report.add(batch.modName(), "", .registry_full, "capacity {d}", .{self.entries.len});
            return error.ModConflict;
        }
    }
    fn sameContent(self: *const Registry, base: usize, batch: *const Batch) bool {
        if (base + batch.count > self.count) return false;
        for (batch.slice(), 0..) |*b, i| {
            if (!std.meta.eql(self.entries[base + i], b.*)) return false;
        }
        return base + batch.count == self.count or !std.mem.eql(u8, self.entries[base + batch.count].modName(), batch.modName());
    }

    /// Adds a mod's entries. Call `canInstall` first; this asserts instead of failing.
    pub fn install(self: *Registry, batch: *const Batch) InstallOutcome {
        if (batch.count == 0) return .unchanged;
        if (self.modBase(batch.modName()) != null) return .unchanged;
        std.debug.assert(self.count + batch.count <= self.entries.len);
        for (batch.slice()) |*e| {
            self.entries[self.count] = e.*;
            const handle: Handle = @intCast(self.count);
            self.count += 1;
            self.insertSorted(e.kind(), handle);
        }
        return .installed;
    }

    fn insertSorted(self: *Registry, kind: Kind, handle: Handle) void {
        const k = @intFromEnum(kind);
        const slice = self.order[k * self.entries.len ..];
        const n = self.order_counts[k];
        var at: usize = n;
        while (at > 0 and self.before(handle, slice[at - 1])) at -= 1;
        std.mem.copyBackwards(Handle, slice[at + 1 .. n + 1], slice[at..n]);
        slice[at] = handle;
        self.order_counts[k] += 1;
    }
    fn before(self: *const Registry, a: Handle, b: Handle) bool {
        const x = &self.entries[a];
        const y = &self.entries[b];
        return switch (std.mem.order(u8, x.modName(), y.modName())) {
            .lt => true,
            .gt => false,
            .eq => x.index < y.index,
        };
    }
};

// ---- Per-player selection --------------------------------------------------------------------

/// Where a profile can use mod content. Each slot falls back to the profile's built-in choice.
pub const Slot = enum {
    hair_style,
    face_preset,
    armor_set,
    palette,
    cel_style,

    pub fn kind(self: Slot) Kind {
        return switch (self) {
            .hair_style => .hair_style,
            .face_preset => .face_preset,
            .armor_set => .armor_set,
            .palette => .palette,
            .cel_style => .cel_style,
        };
    }
};
pub const slot_count = 5;

/// Namespaced ids chosen by a profile. An id whose mod is not installed is kept (so the choice
/// returns when the mod does) but resolves to nothing, and the built-in choice is used.
pub const Selection = struct {
    ids: [slot_count]Id = @splat(.empty),

    pub fn get(self: *const Selection, slot: Slot) ?*const Id {
        const id = &self.ids[@intFromEnum(slot)];
        return if (id.isEmpty()) null else id;
    }
    pub fn set(self: *Selection, slot: Slot, id: Id) void {
        self.ids[@intFromEnum(slot)] = id;
    }
    pub fn clear(self: *Selection, slot: Slot) void {
        self.ids[@intFromEnum(slot)] = .empty;
    }
    /// The installed entry for this slot, or null (use the built-in).
    pub fn resolve(self: *const Selection, slot: Slot, registry: ?*const Registry) ?Handle {
        const reg = registry orelse return null;
        const id = self.get(slot) orelse return null;
        return reg.find(slot.kind(), id);
    }

    pub const Doc = struct {
        hair_style: ?[]const u8 = null,
        face_preset: ?[]const u8 = null,
        armor_set: ?[]const u8 = null,
        palette: ?[]const u8 = null,
        cel_style: ?[]const u8 = null,
    };
    fn text(self: *const Selection, slot: Slot) ?[]const u8 {
        return if (self.get(slot)) |id| id.slice() else null;
    }
    /// Borrows from `self`; valid while the selection is.
    pub fn toDoc(self: *const Selection) Doc {
        return .{ .hair_style = self.text(.hair_style), .face_preset = self.text(.face_preset), .armor_set = self.text(.armor_set), .palette = self.text(.palette), .cel_style = self.text(.cel_style) };
    }
    fn setText(self: *Selection, slot: Slot, value: ?[]const u8) error{InvalidModContent}!void {
        if (value) |t| self.set(slot, Id.parse(t) orelse return error.InvalidModContent);
    }
    /// Ill-formed ids are rejected; ids of missing mods are fine.
    pub fn fromDoc(doc: Doc) error{InvalidModContent}!Selection {
        var result: Selection = .{};
        try result.setText(.hair_style, doc.hair_style);
        try result.setText(.face_preset, doc.face_preset);
        try result.setText(.armor_set, doc.armor_set);
        try result.setText(.palette, doc.palette);
        try result.setText(.cel_style, doc.cel_style);
        return result;
    }
};

// ---- Tests -----------------------------------------------------------------------------------

const testing = std.testing;

fn loadOne(mod: []const u8, files: []const [2][]const u8, report: *Report) !*Batch {
    const batch = try Batch.create(testing.allocator, mod);
    errdefer batch.destroy();
    for (files) |f| try batch.addFile(f[0], f[1], report);
    try batch.finish(report);
    return batch;
}

const sample =
    \\{ "format": 1,
    \\  "hair_styles": [ { "id": "flame", "name": "Flame Crest", "clumps": [ { "az": 0, "el": 1.2, "pitch": 1.2, "length": 0.9, "layer": 2, "sway": true, "mirror": true } ], "cap": { "lift": 0.01 } } ],
    \\  "face_presets": [ { "id": "sharp", "name": "Sharp", "masculine": { "jaw_taper": 0.9 }, "head_ratio": 6.2, "eye_tilt": 0.1 } ],
    \\  "palettes": [ { "id": "ember", "name": "Ember", "role": "outfit", "colors": ["#220000", [0.9, 0.3, 0.1]] } ],
    \\  "armor_sets": [ { "id": "phoenix", "name": "Phoenix", "metal": "#aa4422", "secondary": [0.1, 0.1, 0.2], "trim": "#ffcc00", "visor": "twin",
    \\      "shape": { "silhouette": "finned", "crest": 0.1 },
    \\      "pieces": [ { "kind": "dome_pauldron", "anchor": "upper_arm", "offset": [0.05, -0.03, 0], "shape": { "silhouette": "angular", "flare": 0.5 } },
    \\                  { "kind": "blob", "anchor": "head", "sides": "center", "when": "sealed", "size": [0.1, 0.1, 0.1], "color": "glow", "fit": false } ] } ],
    \\  "cel_styles": [ { "id": "ink", "name": "Ink Wash", "base": "flat", "outline_scale": 2, "materials": { "armor": { "outline": { "width_px": 4 }, "rim": { "strength": 0.9 } } } } ] }
;

fn installSample(reg: *Registry) !void {
    var report: Report = .{};
    const batch = try loadOne("testmod", &.{.{ "a.json", sample }}, &report);
    defer batch.destroy();
    try testing.expect(report.ok());
    try reg.canInstall(batch, &report);
    try testing.expectEqual(InstallOutcome.installed, reg.install(batch));
}

fn entryFor(reg: *const Registry, kind: Kind, id: []const u8) *const Entry {
    return reg.get(reg.find(kind, &Id.parse(id).?).?);
}

test "a valid file loads into the real structs, with defaults and nested overrides" {
    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try installSample(&reg);
    try testing.expectEqual(@as(usize, 5), reg.count);

    const hair = try hairStyle(entryFor(&reg, .hair_style, "testmod.flame"));
    try testing.expectEqualStrings("flame", hair.name);
    try testing.expectEqual(@as(usize, 1), hair.clumps.len);
    try testing.expectEqual(@as(u8, 2), hair.clumps[0].layer);
    try testing.expect(hair.clumps[0].sway and hair.clumps[0].mirror);
    // Unlisted fields keep the struct's own defaults.
    try testing.expectEqual((hair_style.ClumpDef{ .az = 0, .el = 0 }).taper, hair.clumps[0].taper);
    try testing.expectEqual(@as(f32, 0.01), hair.cap.lift);
    try testing.expectEqual((hair_style.CapDef{}).hairline, hair.cap.hairline);

    const face = try facePreset(entryFor(&reg, .face_preset, "testmod.sharp"));
    try testing.expectEqualStrings("sharp", face.name);
    try testing.expectEqual(@as(f32, 0.9), face.masculine.jaw_taper);
    try testing.expectEqual((spec.HeadSpec{}).cranium_width, face.masculine.cranium_width);
    try testing.expectEqual(@as(f32, 6.2), face.head_ratio);
    try testing.expectEqual(@as(f32, 1), face.eye_size_scale);

    const set = try armorSet(entryFor(&reg, .armor_set, "testmod.phoenix"));
    try testing.expectEqualStrings("phoenix", set.name);
    try testing.expectEqualStrings("Phoenix", set.title);
    try testing.expectEqual(armor.VisorShape.twin, set.visor);
    try testing.expectEqual(spec.Silhouette.finned, set.shape.silhouette);
    try testing.expectApproxEqAbs(@as(f32, 0xaa) / 255, set.metal.r, 1e-6);
    try testing.expectEqual(@as(f32, 0.1), set.secondary.g);
    try testing.expectEqual(@as(usize, 2), set.pieces.len);
    try testing.expectEqual(spec.Silhouette.angular, set.pieces[0].shape.?.silhouette);
    try testing.expect(set.pieces[1].shape == null);
    try testing.expectEqual(armor.ColorSlot.glow, set.pieces[1].color);
    try testing.expectEqual(false, set.pieces[1].fit);
    try testing.expectEqual(armor.Fit.sealed, set.pieces[1].when);

    // A cel style starts from its base preset and overrides only what it names.
    const ink = try celStyle(entryFor(&reg, .cel_style, "testmod.ink"));
    try testing.expectEqual(@as(f32, 2), ink.outline_scale);
    try testing.expectEqual(@as(f32, 4), ink.get(.armor).outline.width_px);
    try testing.expectEqual(@as(f32, 0.9), ink.get(.armor).rim.strength);
    try testing.expectEqual(cel.flat.get(.armor).rim.width, ink.get(.armor).rim.width);
    try testing.expectEqual(cel.flat.get(.skin).*, ink.get(.skin).*);

    const palette = entryFor(&reg, .palette, "testmod.ember");
    try testing.expectApproxEqAbs(@as(f32, 0.9), palette.paletteColor(1).?[0], 1e-6);
    try testing.expect(palette.paletteColor(2) == null);
}

test "every field of the real structs is a key, and values land unchanged" {
    var reg = try Registry.init(testing.allocator, 8);
    defer reg.deinit();
    const json =
        \\{ "format": 1,
        \\  "hair_styles": [ { "id": "h", "name": "H", "clumps": [ { "az": 0.1, "el": 0.2, "yaw": 0.3, "pitch": 0.4, "length": 0.5, "width": 0.6, "thickness": 0.7, "taper": 1.5, "curl": 0.8, "flick": 0.9, "stand": 0.35, "layer": 3, "spike": 0.45, "sway": true, "mirror": true } ],
        \\      "cap": { "hairline": [0.5, 0.4, 0.0, -0.5, -0.9], "lift": 0.02 } } ],
        \\  "face_presets": [ { "id": "f", "name": "F",
        \\      "masculine": { "cranium_width": 0.8, "cranium_depth": 0.9, "cranium_size": 1.05, "cheek_width": 0.95, "cheek_height": 0.3, "jaw_taper": 0.5, "chin_width": 0.45, "chin_point": 0.3, "chin_jut": 0.01, "neck_length": 0.2, "neck_thickness": 1.1, "brow_ridge": 0.012, "cheek_fullness": 0.015, "nose_bridge": 0.007, "nose_tip": 0.013 },
        \\      "feminine": { "jaw_taper": 0.6 },
        \\      "head_ratio": 6.1, "eye_size_scale": 1.1, "eye_aspect_scale": 0.9, "eye_tilt": 0.05, "eye_height_add": 0.01, "brow_weight": 0.01, "brow_tilt": 0.2, "brow_gap": 0.05, "nose_mark": 0.4, "mouth_width": 0.055 } ],
        \\  "armor_sets": [ { "id": "a", "name": "A", "metal": "#102030", "secondary": "#405060", "trim": "#708090", "dark": "#0a0b0c", "visor": "scouter",
        \\      "shape": { "silhouette": "wedge", "flare": 0.2, "crest": 0.05, "roundness": 0.4, "overlap": 0.3 },
        \\      "pieces": [ { "kind": "gem", "anchor": "forearm", "sides": "left", "when": "suited", "offset": [0.1, -0.2, 0.3], "size": [0.05, 0.06, 0.07], "scale": 1.5, "tilt": [0.1, 0.2, 0.3], "exponent": 0.8, "taper": -0.2, "color": "dark", "material": "metal", "fit": false,
        \\          "shape": { "silhouette": "dome", "flare": 0.1, "crest": 0.02, "roundness": 0.9, "overlap": 0.5 } } ] } ] }
    ;
    var report: Report = .{};
    const batch = try loadOne("m", &.{.{ "f.json", json }}, &report);
    defer batch.destroy();
    _ = reg.install(batch);

    const clump = (try hairStyle(entryFor(&reg, .hair_style, "m.h"))).clumps[0];
    try testing.expectEqual(hair_style.ClumpDef{ .az = 0.1, .el = 0.2, .yaw = 0.3, .pitch = 0.4, .length = 0.5, .width = 0.6, .thickness = 0.7, .taper = 1.5, .curl = 0.8, .flick = 0.9, .stand = 0.35, .layer = 3, .spike = 0.45, .sway = true, .mirror = true }, clump);
    try testing.expectEqual([5]f32{ 0.5, 0.4, 0.0, -0.5, -0.9 }, (try hairStyle(entryFor(&reg, .hair_style, "m.h"))).cap.hairline);

    const face = try facePreset(entryFor(&reg, .face_preset, "m.f"));
    try testing.expectEqual(spec.HeadSpec{ .cranium_width = 0.8, .cranium_depth = 0.9, .cranium_size = 1.05, .cheek_width = 0.95, .cheek_height = 0.3, .jaw_taper = 0.5, .chin_width = 0.45, .chin_point = 0.3, .chin_jut = 0.01, .neck_length = 0.2, .neck_thickness = 1.1, .brow_ridge = 0.012, .cheek_fullness = 0.015, .nose_bridge = 0.007, .nose_tip = 0.013 }, face.masculine);
    try testing.expectEqual(@as(f32, 0.6), face.feminine.jaw_taper);
    try testing.expectEqual(@as(f32, 0.01), face.eye_height_add);
    try testing.expectEqual(@as(f32, 0.055), face.mouth_width);
    try testing.expectEqual(@as(f32, 6.1), face.head_ratio);

    const set = try armorSet(entryFor(&reg, .armor_set, "m.a"));
    try testing.expectEqual(spec.ShapeSpec{ .silhouette = .wedge, .flare = 0.2, .crest = 0.05, .roundness = 0.4, .overlap = 0.3 }, set.shape);
    try testing.expectEqual(armor.Piece{ .kind = .gem, .anchor = .forearm, .sides = .left, .when = .suited, .offset = .{ 0.1, -0.2, 0.3 }, .size = .{ 0.05, 0.06, 0.07 }, .scale = 1.5, .tilt = .{ 0.1, 0.2, 0.3 }, .exponent = 0.8, .taper = -0.2, .color = .dark, .material = .metal, .fit = false, .shape = .{ .silhouette = .dome, .flare = 0.1, .crest = 0.02, .roundness = 0.9, .overlap = 0.5 } }, set.pieces[0]);
    try testing.expectApproxEqAbs(@as(f32, 0x0a) / 255, set.dark.r, 1e-6);
}

test "every bad value is rejected with its file, key path and reason" {
    const Case = struct { json: []const u8, key: []const u8, code: Code };
    const head = "{\"format\":1,";
    const hair = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1}]}";
    const set = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\",\"metal\":\"#ffffff\",\"secondary\":\"#ffffff\",\"trim\":\"#ffffff\"";
    const piece = ",\"pieces\":[{\"kind\":\"blob\",\"anchor\":\"chest\"";
    const cases = [_]Case{
        .{ .json = "{ not json", .key = "", .code = .invalid_json },
        .{ .json = "[]", .key = "", .code = .wrong_type },
        .{ .json = "{}", .key = "format", .code = .missing_key },
        .{ .json = "{\"format\":2}", .key = "format", .code = .bad_format },
        .{ .json = head ++ "\"hairstyles\":[]}", .key = "hairstyles", .code = .unknown_key },
        .{ .json = head ++ "\"armor_pieces\":[]}", .key = "armor_pieces", .code = .unknown_key },
        .{ .json = head ++ "\"hair_styles\":{}}", .key = "hair_styles", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"name\":\"X\"}]}", .key = "hair_styles[0].id", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"Bad Id\",\"name\":\"X\"}]}", .key = "hair_styles[0].id", .code = .bad_id },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\"}]}", .key = "hair_styles[0].name", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"caf\\u00e9\"}]}", .key = "hair_styles[0].name", .code = .bad_name },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"This display name is far too long to fit\"}]}", .key = "hair_styles[0].name", .code = .too_long },
        .{ .json = hair ++ ",{\"id\":\"a\",\"name\":\"Y\",\"clumps\":[{\"az\":0,\"el\":1}]}]}", .key = "hair_styles[1].id", .code = .duplicate_id },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\"}]}", .key = "hair_styles[0].clumps", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[]}]}", .key = "hair_styles[0].clumps", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"el\":1}]}]}", .key = "hair_styles[0].clumps[0].az", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1,\"lenght\":1}]}]}", .key = "hair_styles[0].clumps[0].lenght", .code = .unknown_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1,\"length\":\"long\"}]}]}", .key = "hair_styles[0].clumps[0].length", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1,\"length\":9}]}]}", .key = "hair_styles[0].clumps[0].length", .code = .out_of_range },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1,\"layer\":2.5}]}]}", .key = "hair_styles[0].clumps[0].layer", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1,\"layer\":300}]}]}", .key = "hair_styles[0].clumps[0].layer", .code = .out_of_range },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1}],\"cap\":{\"lift\":2}}]}", .key = "hair_styles[0].cap.lift", .code = .out_of_range },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"clumps\":[{\"az\":0,\"el\":1}],\"cap\":{\"hairline\":[1,2]}}]}", .key = "hair_styles[0].cap.hairline", .code = .wrong_type },
        .{ .json = head ++ "\"face_presets\":[{\"id\":\"f\",\"name\":\"F\",\"masculine\":{\"cranium_width\":3}}]}", .key = "face_presets[0].masculine.cranium_width", .code = .out_of_range },
        .{ .json = head ++ "\"face_presets\":[{\"id\":\"f\",\"name\":\"F\",\"head_ratio\":9}]}", .key = "face_presets[0].head_ratio", .code = .out_of_range },
        .{ .json = head ++ "\"face_presets\":[{\"id\":\"f\",\"name\":\"F\",\"feminine\":{\"jaw_widht\":1}}]}", .key = "face_presets[0].feminine.jaw_widht", .code = .unknown_key },
        .{ .json = head ++ "\"face_presets\":[{\"id\":\"f\",\"name\":\"F\",\"feminine\":{\"cranium_width\":1.1,\"cranium_size\":1.2,\"cranium_depth\":1.15}}]}", .key = "face_presets[0].feminine", .code = .inconsistent },
        .{ .json = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\",\"metal\":\"#ffffff\",\"secondary\":\"#ffffff\"}]}", .key = "armor_sets[0].trim", .code = .missing_key },
        .{ .json = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\",\"metal\":\"red\",\"secondary\":\"#ffffff\",\"trim\":\"#ffffff\"}]}", .key = "armor_sets[0].metal", .code = .bad_color },
        .{ .json = set ++ ",\"visor\":\"periscope\"}]}", .key = "armor_sets[0].visor", .code = .bad_choice },
        .{ .json = set ++ ",\"shape\":{\"roundness\":2}}]}", .key = "armor_sets[0].shape.roundness", .code = .out_of_range },
        .{ .json = set ++ ",\"shape\":{\"silhouette\":\"fin\"}}]}", .key = "armor_sets[0].shape.silhouette", .code = .bad_choice },
        .{ .json = set ++ ",\"pieces\":[{\"kind\":\"blob\",\"anchor\":\"torso\"}]}]}", .key = "armor_sets[0].pieces[0].anchor", .code = .bad_choice },
        .{ .json = set ++ ",\"pieces\":[{\"anchor\":\"chest\"}]}]}", .key = "armor_sets[0].pieces[0].kind", .code = .missing_key },
        .{ .json = set ++ piece ++ ",\"offset\":[0,0]}]}]}", .key = "armor_sets[0].pieces[0].offset", .code = .wrong_type },
        .{ .json = set ++ piece ++ ",\"offset\":[0,0,3]}]}]}", .key = "armor_sets[0].pieces[0].offset", .code = .out_of_range },
        .{ .json = set ++ piece ++ ",\"size\":[0,0.1,0.1]}]}]}", .key = "armor_sets[0].pieces[0].size", .code = .out_of_range },
        .{ .json = set ++ piece ++ ",\"fit\":1}]}]}", .key = "armor_sets[0].pieces[0].fit", .code = .wrong_type },
        .{ .json = set ++ piece ++ ",\"shape\":{\"crest\":5}}]}]}", .key = "armor_sets[0].pieces[0].shape.crest", .code = .out_of_range },
        .{ .json = set ++ ",\"pieces\":[{\"kind\":\"blob\",\"anchor\":\"hand\",\"sides\":\"center\"}]}]}", .key = "armor_sets[0].pieces[0].sides", .code = .inconsistent },
        .{ .json = head ++ "\"palettes\":[{\"id\":\"c\",\"name\":\"C\",\"role\":\"hair\",\"colors\":[]}]}", .key = "palettes[0].colors", .code = .missing_key },
        .{ .json = head ++ "\"palettes\":[{\"id\":\"c\",\"name\":\"C\",\"colors\":[\"#000000\"]}]}", .key = "palettes[0].role", .code = .missing_key },
        .{ .json = head ++ "\"palettes\":[{\"id\":\"c\",\"name\":\"C\",\"role\":\"hair\",\"colors\":[\"#112233\",[2,0,0]]}]}", .key = "palettes[0].colors[1]", .code = .bad_color },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"base\":\"neon\"}]}", .key = "cel_styles[0].base", .code = .bad_choice },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"outline_scale\":20}]}", .key = "cel_styles[0].outline_scale", .code = .out_of_range },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"materials\":{\"steel\":{}}}]}", .key = "cel_styles[0].materials.steel", .code = .unknown_key },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"materials\":{\"armor\":{\"ramp\":{\"softness\":0}}}}]}", .key = "cel_styles[0].materials.armor.ramp", .code = .out_of_range },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"materials\":{\"armor\":{\"ramp\":{\"treshold\":0.5}}}}]}", .key = "cel_styles[0].materials.armor.ramp.treshold", .code = .unknown_key },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"materials\":{\"armor\":{\"emissive\":3}}}]}", .key = "cel_styles[0].materials.armor.emissive", .code = .out_of_range },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"materials\":{\"armor\":{\"outline\":{\"tint\":[0,0]}}}}]}", .key = "cel_styles[0].materials.armor.outline.tint", .code = .wrong_type },
    };
    for (cases) |c| {
        var report: Report = .{};
        const result = loadOne("testmod", &.{.{ "bad.json", c.json }}, &report);
        try testing.expectError(error.InvalidCharacterContent, result);
        var found = false;
        for (report.slice()) |*d| {
            if (d.code == c.code and std.mem.eql(u8, d.keyPath(), c.key) and std.mem.eql(u8, d.fileName(), "bad.json")) found = true;
        }
        if (!found) {
            var buf: [300]u8 = undefined;
            std.debug.print("case {s}\n  wanted {s} {s}; got {d} diagnostics, first: {s}\n", .{ c.json, c.key, @tagName(c.code), report.count, if (report.count > 0) report.items[0].format(&buf) else "-" });
        }
        try testing.expect(found);
    }
}

test "problems are collected rather than stopping at the first, and overflow is counted" {
    var report: Report = .{};
    var json: [4096]u8 = undefined;
    var w = std.Io.Writer.fixed(&json);
    try w.writeAll("{\"format\":1,\"hair_styles\":[");
    for (0..20) |i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"x{d}\",\"name\":\"N\",\"clumps\":[{{\"az\":0,\"el\":1,\"length\":\"x\"}}]}}", .{i});
    }
    try w.writeAll("]}");
    try testing.expectError(error.InvalidCharacterContent, loadOne("m", &.{.{ "f.json", w.buffered() }}, &report));
    try testing.expectEqual(@as(usize, max_diagnostics), report.count);
    try testing.expectEqual(@as(usize, 4), report.dropped);
}

test "the per-mod entry limit is reported, not overflowed" {
    var buf: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try w.writeAll("{\"format\":1,\"palettes\":[");
    for (0..max_per_mod + 1) |i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"p{d}\",\"name\":\"P\",\"role\":\"hair\",\"colors\":[\"#000000\"]}}", .{i});
    }
    try w.writeAll("]}");
    var report: Report = .{};
    try testing.expectError(error.InvalidCharacterContent, loadOne("m", &.{.{ "f.json", w.buffered() }}, &report));
    try testing.expectEqual(Code.too_many, report.items[0].code);
}

test "a rejected file leaves an installed registry untouched" {
    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try installSample(&reg);
    const before = reg.count;
    var report: Report = .{};
    const bad = "{\"format\":1,\"hair_styles\":[{\"id\":\"z\",\"name\":\"Z\",\"clumps\":[{\"az\":0,\"el\":1,\"length\":99}]}]}";
    try testing.expectError(error.InvalidCharacterContent, loadOne("other", &.{.{ "z.json", bad }}, &report));
    try testing.expectEqual(before, reg.count);
    try testing.expect(reg.find(.hair_style, &Id.parse("other.z").?) == null);
}

test "conversions reject the wrong kind and content that stopped validating" {
    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try installSample(&reg);
    try testing.expectError(error.WrongKind, hairStyle(entryFor(&reg, .armor_set, "testmod.phoenix")));
    try testing.expectError(error.WrongKind, armorSet(entryFor(&reg, .hair_style, "testmod.flame")));
    try testing.expectError(error.WrongKind, celStyle(entryFor(&reg, .face_preset, "testmod.sharp")));
    try testing.expectError(error.WrongKind, facePreset(entryFor(&reg, .cel_style, "testmod.ink")));
    // Corrupt entries in place (as a bad hot reload might): the real validators refuse them.
    const hair = &reg.entries[reg.find(.hair_style, &Id.parse("testmod.flame").?).?];
    hair.data.hair_style.clumps[0].length = std.math.nan(f32);
    try testing.expectError(error.InvalidContent, hairStyle(hair));
    const set = &reg.entries[reg.find(.armor_set, &Id.parse("testmod.phoenix").?).?];
    set.data.armor_set.pieces[0].size = .{ 5, 5, 5 };
    try testing.expectError(error.InvalidContent, armorSet(set));
    const face = &reg.entries[reg.find(.face_preset, &Id.parse("testmod.sharp").?).?];
    face.data.face_preset.masculine.cranium_width = 9;
    try testing.expectError(error.InvalidContent, facePreset(face));
    const ink = &reg.entries[reg.find(.cel_style, &Id.parse("testmod.ink").?).?];
    ink.data.cel_style.materials[0].ramp.softness = 0;
    try testing.expectError(error.InvalidContent, celStyle(ink));
}

test "every built-in face and style sits inside the limits mods are held to" {
    for (spec.face_presets) |fp| {
        try testing.expect(faceOk(fp));
        try testing.expect(headOk(fp.masculine) and headOk(fp.feminine));
    }
    try testing.expect(headOk(.{}));
    for (cel.presets) |p| try testing.expect(celOk(p.style.*));
    for (armor.builtin_sets) |def| {
        for (def.pieces) |p| try testing.expect(pieceOk(p));
        try testing.expect(shapeOk(def.shape));
    }
    for (std.enums.values(spec.HairStyle)) |style| {
        const def = @import("../character/hair_library.zig").lookup(style) orelse continue;
        for (def.clumps) |c| try testing.expect(clumpOk(c));
    }
}

test "registry: namespacing, stable order independent of install order, dedupe and conflicts" {
    const a_json = "{\"format\":1,\"palettes\":[{\"id\":\"b\",\"name\":\"B\",\"role\":\"hair\",\"colors\":[\"#000000\"]},{\"id\":\"a\",\"name\":\"A\",\"role\":\"hair\",\"colors\":[\"#ffffff\"]}]}";
    const b_json = "{\"format\":1,\"palettes\":[{\"id\":\"b\",\"name\":\"Other B\",\"role\":\"skin\",\"colors\":[\"#101010\"]}]}";
    var report: Report = .{};
    const zeta = try loadOne("zeta", &.{.{ "p.json", a_json }}, &report);
    defer zeta.destroy();
    const alpha = try loadOne("alpha", &.{.{ "p.json", b_json }}, &report);
    defer alpha.destroy();

    var reg = try Registry.init(testing.allocator, 8);
    defer reg.deinit();
    var reg2 = try Registry.init(testing.allocator, 8);
    defer reg2.deinit();
    for ([_]*Batch{ zeta, alpha }) |b| {
        try reg.canInstall(b, &report);
        _ = reg.install(b);
    }
    for ([_]*Batch{ alpha, zeta }) |b| {
        try reg2.canInstall(b, &report);
        _ = reg2.install(b);
    }
    // Same display order either way: alpha.b, then zeta.b, zeta.a (declaration order).
    const expected = [_][]const u8{ "alpha.b", "zeta.b", "zeta.a" };
    for ([_]*const Registry{ &reg, &reg2 }) |r| {
        const handles = r.list(.palette);
        try testing.expectEqual(@as(usize, 3), handles.len);
        for (handles, expected) |h, want| {
            const id = r.get(h).id();
            try testing.expectEqualStrings(want, id.slice());
        }
    }
    // Both mods use the local id "b" without clobbering each other.
    try testing.expectEqualStrings("Other B", reg.get(reg.find(.palette, &Id.parse("alpha.b").?).?).name());
    try testing.expectEqualStrings("B", reg.get(reg.find(.palette, &Id.parse("zeta.b").?).?).name());
    try testing.expect(reg.find(.palette, &Id.parse("zeta.missing").?) == null);
    try testing.expect(reg.find(.hair_style, &Id.parse("zeta.b").?) == null);

    // Installing identical content again is a no-op; different content under the same name is a conflict.
    try reg.canInstall(zeta, &report);
    try testing.expectEqual(InstallOutcome.unchanged, reg.install(zeta));
    try testing.expectEqual(@as(usize, 3), reg.count);
    const changed = try loadOne("zeta", &.{.{ "p.json", b_json }}, &report);
    defer changed.destroy();
    var conflict: Report = .{};
    try testing.expectError(error.ModConflict, reg.canInstall(changed, &conflict));
    try testing.expectEqual(Code.mod_conflict, conflict.items[0].code);
    try testing.expectEqual(@as(usize, 3), reg.count);

    // A full registry rejects a mod and stays unchanged.
    var tiny = try Registry.init(testing.allocator, 1);
    defer tiny.deinit();
    var full: Report = .{};
    try testing.expectError(error.ModConflict, tiny.canInstall(zeta, &full));
    try testing.expectEqual(Code.registry_full, full.items[0].code);
    try testing.expectEqual(@as(usize, 0), tiny.count);
}

test "selection documents round-trip, reject malformed ids, and resolve only installed content" {
    var s: Selection = .{};
    s.set(.hair_style, Id.parse("testmod.flame").?);
    s.set(.cel_style, Id.parse("gone.style").?);
    const doc = s.toDoc();
    try testing.expectEqualStrings("testmod.flame", doc.hair_style.?);
    try testing.expect(doc.palette == null);
    const back = try Selection.fromDoc(doc);
    try testing.expectEqualDeep(s, back);
    try testing.expectError(error.InvalidModContent, Selection.fromDoc(.{ .palette = "no_dot" }));
    try testing.expectError(error.InvalidModContent, Selection.fromDoc(.{ .palette = "A.b" }));
    try testing.expectError(error.InvalidModContent, Selection.fromDoc(.{ .palette = "a.b.c" }));

    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try testing.expect(s.resolve(.hair_style, &reg) == null);
    try testing.expect(s.resolve(.hair_style, null) == null);
    try installSample(&reg);
    try testing.expect(s.resolve(.hair_style, &reg) != null);
    // A mod that is missing keeps its id but resolves to nothing.
    try testing.expect(s.resolve(.cel_style, &reg) == null);
    try testing.expectEqualStrings("gone.style", s.get(.cel_style).?.slice());
}
