//! Mod-declared character content: hairstyles, face presets, armor pieces and sets, palettes and
//! cel styles. A mod lists JSON files under `"character"` in its manifest; each file is
//! validated against the schema tables below and becomes entries in a `Registry`.
//!
//! This module knows nothing about meshes or the renderer. An entry is an id, a display name and
//! a bounded set of typed parameters whose names and ranges come from `schema`. The systems that
//! draw hair, faces, armor and cel shading read parameters through `Entry.float`, `Entry.choice`
//! and friends, so adding a parameter is one line in `schema` plus the reader.
//!
//! Rules (docs/mods.md, "Character content"):
//! - **Namespaced.** An entry is `<mod>.<id>`; a mod cannot define another mod's ids.
//! - **All or nothing.** A file with any problem rejects the whole mod, with one `Diagnostic`
//!   (file, key path, reason) per problem. Validation never panics on mod data.
//! - **Bounded.** Fixed counts and lengths; allocation happens when a mod loads, never per frame.
//! - **Stable.** Handles never change during a run; listing order is mod name, then declaration
//!   order, so it does not depend on directory order.
const std = @import("std");
const CharacterContent = @This();

pub const format_version: u32 = 1;
/// Mirrors `script/Host.name_len`; `mod/Mod.zig` asserts they agree.
pub const mod_name_len = 24;
pub const id_len = 24;
pub const qualified_len = 48;
pub const display_len = 32;
pub const max_params = 12;
pub const max_values = 24;
pub const max_per_mod = 64;
pub const max_pending = 256;
pub const max_registry_entries = 256;
pub const max_diagnostics = 16;

pub const Kind = enum { hair_style, face_preset, armor_piece, armor_set, palette, cel_style };
pub const kind_count = 6;

/// The JSON array that holds a kind's entries.
pub fn sectionKey(kind: Kind) []const u8 {
    return switch (kind) {
        .hair_style => "hair_styles",
        .face_preset => "face_presets",
        .armor_piece => "armor_pieces",
        .armor_set => "armor_sets",
        .palette => "palettes",
        .cel_style => "cel_styles",
    };
}

// ---- Schema ----------------------------------------------------------------------------------

pub const Type = union(enum) {
    float: struct { min: f32, max: f32, default: f32 },
    int: struct { min: i32, max: i32, default: i32 },
    boolean: bool,
    /// One of the listed strings; stored as its index.
    choice: []const []const u8,
    vec3: struct { min: f32, max: f32, default: [3]f32 },
    /// "#rrggbb" or [r, g, b] with 0..1 channels. `null` default means optional and unset.
    color: ?[3]f32,
    /// 1..max colors.
    colors: struct { max: u8 },
    floats: struct { min_len: u8, max_len: u8, min: f32, max: f32, ascending: bool },
    /// Optional local id of another entry in the same mod.
    ref: Kind,
    refs: struct { kind: Kind, max: u8 },
};
pub const Param = struct { key: []const u8, ty: Type, required: bool = false };

/// Built-in names a mod may name as its `base`: what an old or partial renderer falls back to.
/// `test "schema base choices name real Profile enum tags"` in Creator.zig keeps them honest.
pub const base_hair = [_][]const u8{ "short", "ponytail", "long", "crest", "hood", "bob", "twin_tails", "bun", "braids", "curly", "undercut", "short_curly", "curly_fade", "curly_coils", "afro", "long_curls", "textured_crop", "locs", "swept_back", "layered_shag", "nova_spike", "alien_crown", "crew_cut", "side_part" };
pub const base_face = [_][]const u8{ "classic", "soft", "angular", "heroic", "alien" };
pub const base_armor = [_][]const u8{ "none", "scout", "sentinel", "rootweave", "skyguard", "gem_aegis", "starforge", "deep_prism" };
const tint_slots = [_][]const u8{ "outfit", "accent", "trim", "metal" };
const hair_slots = [_][]const u8{ "hair", "highlight", "accent" };
const parts = [_][]const u8{ "helmet", "pauldron", "chest", "bracer", "gauntlet", "belt", "tasset", "greave", "boot", "back" };
const joints = [_][]const u8{ "head", "neck", "chest", "spine", "shoulder", "upper_arm", "forearm", "hand", "hip", "thigh", "shin", "foot" };
const silhouettes = [_][]const u8{ "plate", "wedge", "dome", "ring", "blade", "fin", "cylinder", "cone" };
const roles = [_][]const u8{ "hair", "outfit", "accent", "skin", "coat" };

fn float(key: []const u8, min: f32, max: f32, default: f32) Param {
    return .{ .key = key, .ty = .{ .float = .{ .min = min, .max = max, .default = default } } };
}

const hair_schema = [_]Param{
    .{ .key = "base", .ty = .{ .choice = &base_hair } },
    float("length", 0.1, 2, 1),
    float("volume", 0.5, 2.5, 1),
    float("curl", 0, 1, 0),
    float("spike", 0, 1, 0),
    float("parting", -1, 1, 0),
    .{ .key = "cards", .ty = .{ .int = .{ .min = 8, .max = 64, .default = 24 } } },
    .{ .key = "tip_color", .ty = .{ .color = null } },
    .{ .key = "tint_slot", .ty = .{ .choice = &hair_slots } },
};
const face_schema = [_]Param{
    .{ .key = "base", .ty = .{ .choice = &base_face } },
    float("jaw_width", 0.7, 1.3, 1),
    float("chin_height", 0.7, 1.3, 1),
    float("cheek_fullness", 0.5, 1.5, 1),
    float("eye_size", 0.7, 1.4, 1),
    float("eye_spacing", 0.8, 1.2, 1),
    float("eye_tilt", -1, 1, 0),
    float("brow_height", -1, 1, 0),
    float("nose_length", 0.7, 1.3, 1),
    float("mouth_width", 0.7, 1.3, 1),
    float("lip_fullness", 0.5, 1.5, 1),
};
const piece_schema = [_]Param{
    .{ .key = "part", .ty = .{ .choice = &parts }, .required = true },
    .{ .key = "attach_joint", .ty = .{ .choice = &joints }, .required = true },
    .{ .key = "silhouette", .ty = .{ .choice = &silhouettes } },
    .{ .key = "size", .ty = .{ .vec3 = .{ .min = 0.02, .max = 1.5, .default = .{ 0.2, 0.2, 0.2 } } } },
    .{ .key = "offset", .ty = .{ .vec3 = .{ .min = -0.5, .max = 0.5, .default = .{ 0, 0, 0 } } } },
    float("flare", 0, 2, 0),
    .{ .key = "fins", .ty = .{ .int = .{ .min = 0, .max = 8, .default = 0 } } },
    float("bevel", 0, 1, 0.2),
    .{ .key = "mirror", .ty = .{ .boolean = true } },
    .{ .key = "tint", .ty = .{ .choice = &tint_slots } },
    float("emissive", 0, 1, 0),
};
const set_schema = [_]Param{
    .{ .key = "base", .ty = .{ .choice = &base_armor }, .required = false },
    .{ .key = "pieces", .ty = .{ .refs = .{ .kind = .armor_piece, .max = 12 } }, .required = true },
    .{ .key = "palette", .ty = .{ .ref = .palette } },
};
const palette_schema = [_]Param{
    .{ .key = "role", .ty = .{ .choice = &roles }, .required = true },
    .{ .key = "colors", .ty = .{ .colors = .{ .max = 8 } }, .required = true },
};
const cel_schema = [_]Param{
    .{ .key = "bands", .ty = .{ .int = .{ .min = 2, .max = 6, .default = 3 } } },
    .{ .key = "band_thresholds", .ty = .{ .floats = .{ .min_len = 1, .max_len = 5, .min = 0, .max = 1, .ascending = true } } },
    .{ .key = "shadow_tint", .ty = .{ .color = .{ 0.42, 0.44, 0.66 } } },
    float("outline_width", 0, 4, 1.5),
    .{ .key = "outline_color", .ty = .{ .color = .{ 0.05, 0.04, 0.08 } } },
    float("rim_strength", 0, 1, 0.3),
    .{ .key = "rim_color", .ty = .{ .color = null } },
    float("specular_size", 0, 1, 0.2),
    float("saturation", 0.5, 1.5, 1),
};

pub fn schema(kind: Kind) []const Param {
    return switch (kind) {
        .hair_style => &hair_schema,
        .face_preset => &face_schema,
        .armor_piece => &piece_schema,
        .armor_set => &set_schema,
        .palette => &palette_schema,
        .cel_style => &cel_schema,
    };
}

comptime {
    for (std.enums.values(Kind)) |k| std.debug.assert(schema(k).len <= max_params);
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
    unknown_ref,
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
            .bad_color => "bad color (\"#rrggbb\" or [r,g,b] in 0..1)",
            .bad_format => "unsupported content format",
            .duplicate_id => "id already declared in this mod",
            .unknown_ref => "refers to an id this mod does not declare",
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

pub const Value = struct {
    set: bool = false,
    /// Items for lists; 1 for scalars, 3 for vec3 and color.
    n: u8 = 0,
    v: [max_values]f32 = @splat(0),
};

pub const Entry = struct {
    kind: Kind = .hair_style,
    mod: [mod_name_len]u8 = @splat(0),
    mod_len: u8 = 0,
    local: [id_len]u8 = @splat(0),
    local_len: u8 = 0,
    display: [display_len]u8 = @splat(0),
    display_len: u8 = 0,
    /// Position within the mod's declarations of this kind (the stable list order).
    index: u16 = 0,
    /// Handle of the mod's first entry once installed; ref values are offsets from it.
    base: u16 = 0,
    values: [max_params]Value = @splat(.{}),

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

    fn slot(kind: Kind, key: []const u8) ?usize {
        for (schema(kind), 0..) |p, i| if (std.mem.eql(u8, p.key, key)) return i;
        return null;
    }
    /// The parameter's value, or null when the schema has no such key or it is unset.
    pub fn value(self: *const Entry, key: []const u8) ?*const Value {
        const i = slot(self.kind, key) orelse return null;
        return if (self.values[i].set) &self.values[i] else null;
    }
    pub fn float(self: *const Entry, key: []const u8) ?f32 {
        const v = self.value(key) orelse return null;
        return v.v[0];
    }
    pub fn int(self: *const Entry, key: []const u8) ?i32 {
        const v = self.value(key) orelse return null;
        return @intFromFloat(v.v[0]);
    }
    pub fn boolean(self: *const Entry, key: []const u8) ?bool {
        const v = self.value(key) orelse return null;
        return v.v[0] != 0;
    }
    /// The chosen string, e.g. `choice("silhouette")` is "wedge".
    pub fn choice(self: *const Entry, key: []const u8) ?[]const u8 {
        const i = slot(self.kind, key) orelse return null;
        if (!self.values[i].set) return null;
        return schema(self.kind)[i].ty.choice[@as(usize, @intFromFloat(self.values[i].v[0]))];
    }
    pub fn vec3(self: *const Entry, key: []const u8) ?[3]f32 {
        const v = self.value(key) orelse return null;
        return v.v[0..3].*;
    }
    pub fn color(self: *const Entry, key: []const u8) ?[3]f32 {
        return self.vec3(key);
    }
    /// Color `i` of a `colors` parameter.
    pub fn colorAt(self: *const Entry, key: []const u8, i: usize) ?[3]f32 {
        const v = self.value(key) orelse return null;
        if (i >= v.n) return null;
        return v.v[i * 3 ..][0..3].*;
    }
    pub fn list(self: *const Entry, key: []const u8) []const f32 {
        const v = self.value(key) orelse return &.{};
        return v.v[0..v.n];
    }
    /// Registry handle of the entry named by a `ref` parameter, or item `i` of a `refs` list.
    pub fn refAt(self: *const Entry, key: []const u8, i: usize) ?Handle {
        const v = self.value(key) orelse return null;
        if (i >= v.n) return null;
        return self.base + @as(u16, @intFromFloat(v.v[i]));
    }
    pub fn refCount(self: *const Entry, key: []const u8) usize {
        const v = self.value(key) orelse return 0;
        return v.n;
    }
};

pub const Handle = u16;

// ---- Batch: one mod's validated content ------------------------------------------------------

const Pending = struct {
    entry: u16,
    param: u8,
    item: u8,
    kind: Kind,
    id: [id_len]u8,
    id_len: u8,
    file: u8,
    section: u8,
    index: u16,
};

pub const Batch = struct {
    allocator: std.mem.Allocator,
    mod: [mod_name_len]u8 = @splat(0),
    mod_len: u8 = 0,
    count: usize = 0,
    next_index: [kind_count]u16 = @splat(0),
    pending: [max_pending]Pending = undefined,
    pending_count: usize = 0,
    /// File names for diagnostics raised during `finish`.
    files: [8][48]u8 = undefined,
    file_lens: [8]u8 = @splat(0),
    file_count: usize = 0,
    entries: [max_per_mod]Entry = undefined,

    pub fn create(allocator: std.mem.Allocator, mod_name: []const u8) !*Batch {
        std.debug.assert(validIdentifier(mod_name, mod_name_len));
        const self = try allocator.create(Batch);
        // Field by field: a struct literal would build the whole entry table on the stack first.
        self.allocator = allocator;
        self.mod = @splat(0);
        self.count = 0;
        self.next_index = @splat(0);
        self.pending_count = 0;
        self.file_lens = @splat(0);
        self.file_count = 0;
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
        const file_index: u8 = @intCast(@min(self.file_count, self.files.len - 1));
        if (self.file_count < self.files.len) {
            self.file_lens[self.file_count] = @intCast(copyInto(&self.files[self.file_count], file));
            self.file_count += 1;
        }
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
            if (!isSection(key)) report.add(file, key, .unknown_key, "sections: hair_styles, face_presets, armor_pieces, armor_sets, palettes, cel_styles", .{});
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
            for (array, 0..) |item, i| self.addEntry(report, file, file_index, kind, i, item);
        }
    }

    fn addEntry(self: *Batch, report: *Report, file: []const u8, file_index: u8, kind: Kind, index: usize, item: std.json.Value) void {
        var path_buf: [64]u8 = undefined;
        const prefix = std.fmt.bufPrint(&path_buf, "{s}[{d}]", .{ sectionKey(kind), index }) catch path_buf[0..0];
        const obj = switch (item) {
            .object => |o| o,
            else => return report.add(file, prefix, .wrong_type, "expected an object", .{}),
        };
        var ctx: Ctx = .{ .report = report, .file = file, .prefix = prefix };
        const pending_mark = self.pending_count;
        if (self.count == max_per_mod) return report.add(file, prefix, .too_many, "at most {d} entries per mod", .{max_per_mod});
        var entry: Entry = .{ .kind = kind, .index = self.next_index[@intFromEnum(kind)] };
        @memcpy(entry.mod[0..self.mod_len], self.modName());
        entry.mod_len = self.mod_len;

        // Common header.
        const schema_keys = schema(kind);
        var it = obj.iterator();
        while (it.next()) |kv| {
            const key = kv.key_ptr.*;
            if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "name")) continue;
            if (Entry.slot(kind, key) == null) ctx.fail(key, .unknown_key, "{s} accepts: id, name{s}", .{ sectionKey(kind), keyList(kind) });
        }
        var valid_header = true;
        if (obj.get("id")) |v| switch (v) {
            .string => |s| if (validIdentifier(s, id_len)) {
                @memcpy(entry.local[0..s.len], s);
                entry.local_len = @intCast(s.len);
            } else {
                valid_header = false;
                ctx.fail("id", .bad_id, "\"{s}\", at most {d} characters", .{ clip(s), id_len - 1 });
            },
            else => {
                valid_header = false;
                ctx.fail("id", .wrong_type, "expected a string", .{});
            },
        } else {
            valid_header = false;
            ctx.fail("id", .missing_key, "", .{});
        }
        if (obj.get("name")) |v| switch (v) {
            .string => |s| if (validName(s)) {
                @memcpy(entry.display[0..s.len], s);
                entry.display_len = @intCast(s.len);
            } else ctx.fail("name", if (s.len >= display_len) .too_long else .bad_name, "1 to {d} printable ASCII characters", .{display_len - 1}),
            else => ctx.fail("name", .wrong_type, "expected a string", .{}),
        } else ctx.fail("name", .missing_key, "the label shown in the creator", .{});

        if (valid_header) for (self.entries[0..self.count]) |*other| {
            if (other.kind == kind and std.mem.eql(u8, other.localId(), entry.localId())) {
                ctx.fail("id", .duplicate_id, "\"{s}\"", .{entry.localId()});
                valid_header = false;
                break;
            }
        };

        for (schema_keys, 0..) |param, pi| {
            const raw = obj.get(param.key);
            if (raw == null) {
                if (param.required) ctx.fail(param.key, .missing_key, "", .{});
                applyDefault(&entry.values[pi], param);
                continue;
            }
            self.parseParam(&ctx, &entry, pi, param, raw.?, file_index, index, kind);
        }
        if (kind == .cel_style) checkCel(&ctx, &entry);
        if (!valid_header) {
            // Not stored, so references recorded for its slot would point at the next entry.
            self.pending_count = pending_mark;
            return;
        }
        self.entries[self.count] = entry;
        self.count += 1;
        self.next_index[@intFromEnum(kind)] += 1;
    }

    fn parseParam(self: *Batch, ctx: *Ctx, entry: *Entry, pi: usize, param: Param, raw: std.json.Value, file_index: u8, index: usize, kind: Kind) void {
        const out = &entry.values[pi];
        switch (param.ty) {
            .float => |t| if (number(raw)) |n| {
                if (n < t.min or n > t.max) return ctx.fail(param.key, .out_of_range, "{d} not in {d}..{d}", .{ n, t.min, t.max });
                out.* = .{ .set = true, .n = 1 };
                out.v[0] = @floatCast(n);
            } else ctx.fail(param.key, .wrong_type, "expected a number", .{}),
            .int => |t| switch (raw) {
                .integer => |n| {
                    if (n < t.min or n > t.max) return ctx.fail(param.key, .out_of_range, "{d} not in {d}..{d}", .{ n, t.min, t.max });
                    out.* = .{ .set = true, .n = 1 };
                    out.v[0] = @floatFromInt(n);
                },
                else => ctx.fail(param.key, .wrong_type, "expected a whole number", .{}),
            },
            .boolean => switch (raw) {
                .bool => |b| out.* = .{ .set = true, .n = 1, .v = scalar(@as(f32, if (b) 1 else 0)) },
                else => ctx.fail(param.key, .wrong_type, "expected true or false", .{}),
            },
            .choice => |options| switch (raw) {
                .string => |s| {
                    for (options, 0..) |o, i| if (std.mem.eql(u8, o, s)) {
                        out.* = .{ .set = true, .n = 1, .v = scalar(@as(f32, @floatFromInt(i))) };
                        return;
                    };
                    var list_buf: [96]u8 = undefined;
                    ctx.fail(param.key, .bad_choice, "\"{s}\"; one of {s}", .{ clip(s), joinChoices(&list_buf, options) });
                },
                else => ctx.fail(param.key, .wrong_type, "expected a string", .{}),
            },
            .vec3 => |t| {
                const a = switch (raw) {
                    .array => |a| a.items,
                    else => return ctx.fail(param.key, .wrong_type, "expected [x, y, z]", .{}),
                };
                if (a.len != 3) return ctx.fail(param.key, .wrong_type, "expected exactly 3 numbers", .{});
                var v: [3]f32 = undefined;
                for (a, &v) |item, *slot_value| {
                    const n = number(item) orelse return ctx.fail(param.key, .wrong_type, "expected [x, y, z] numbers", .{});
                    if (n < t.min or n > t.max) return ctx.fail(param.key, .out_of_range, "{d} not in {d}..{d}", .{ n, t.min, t.max });
                    slot_value.* = @floatCast(n);
                }
                out.* = .{ .set = true, .n = 3 };
                out.v[0..3].* = v;
            },
            .color => if (parseColor(raw)) |c| {
                out.* = .{ .set = true, .n = 3 };
                out.v[0..3].* = c;
            } else ctx.fail(param.key, .bad_color, "", .{}),
            .colors => |t| {
                const a = switch (raw) {
                    .array => |a| a.items,
                    else => return ctx.fail(param.key, .wrong_type, "expected an array of colors", .{}),
                };
                if (a.len == 0) return ctx.fail(param.key, .missing_key, "at least one color", .{});
                if (a.len > t.max) return ctx.fail(param.key, .too_many, "at most {d} colors", .{t.max});
                out.* = .{ .set = true, .n = @intCast(a.len) };
                for (a, 0..) |item, i| {
                    const c = parseColor(item) orelse {
                        out.set = false;
                        var key_buf: [40]u8 = undefined;
                        return ctx.fail(std.fmt.bufPrint(&key_buf, "{s}[{d}]", .{ param.key, i }) catch param.key, .bad_color, "", .{});
                    };
                    out.v[i * 3 ..][0..3].* = c;
                }
            },
            .floats => |t| {
                const a = switch (raw) {
                    .array => |a| a.items,
                    else => return ctx.fail(param.key, .wrong_type, "expected an array of numbers", .{}),
                };
                if (a.len < t.min_len or a.len > t.max_len) return ctx.fail(param.key, .too_many, "{d} items; want {d} to {d}", .{ a.len, t.min_len, t.max_len });
                out.* = .{ .set = true, .n = @intCast(a.len) };
                for (a, 0..) |item, i| {
                    const n = number(item) orelse {
                        out.set = false;
                        return ctx.fail(param.key, .wrong_type, "item {d} is not a number", .{i});
                    };
                    if (n < t.min or n > t.max) {
                        out.set = false;
                        return ctx.fail(param.key, .out_of_range, "item {d} = {d} not in {d}..{d}", .{ i, n, t.min, t.max });
                    }
                    out.v[i] = @floatCast(n);
                    if (t.ascending and i > 0 and out.v[i] <= out.v[i - 1]) {
                        out.set = false;
                        return ctx.fail(param.key, .out_of_range, "items must strictly ascend (item {d})", .{i});
                    }
                }
            },
            .ref => |target| {
                const text = switch (raw) {
                    .string => |s| s,
                    else => return ctx.fail(param.key, .wrong_type, "expected a string id", .{}),
                };
                if (!self.queueRef(ctx, param.key, text, target, pi, 0, file_index, kind, index)) return;
                out.* = .{ .set = true, .n = 1 };
            },
            .refs => |t| {
                const a = switch (raw) {
                    .array => |a| a.items,
                    else => return ctx.fail(param.key, .wrong_type, "expected an array of ids", .{}),
                };
                if (a.len == 0) return ctx.fail(param.key, .missing_key, "at least one id", .{});
                if (a.len > t.max) return ctx.fail(param.key, .too_many, "at most {d}", .{t.max});
                out.* = .{ .set = true, .n = @intCast(a.len) };
                for (a, 0..) |item, i| {
                    var key_buf: [40]u8 = undefined;
                    const key = std.fmt.bufPrint(&key_buf, "{s}[{d}]", .{ param.key, i }) catch param.key;
                    const text = switch (item) {
                        .string => |s| s,
                        else => {
                            ctx.fail(key, .wrong_type, "expected a string id", .{});
                            continue;
                        },
                    };
                    _ = self.queueRef(ctx, key, text, t.kind, pi, i, file_index, kind, index);
                }
            },
        }
    }

    fn queueRef(self: *Batch, ctx: *Ctx, key: []const u8, text: []const u8, target: Kind, pi: usize, item: usize, file_index: u8, kind: Kind, index: usize) bool {
        if (!validIdentifier(text, id_len)) {
            ctx.fail(key, .bad_id, "\"{s}\" (use this mod's local id, without a mod prefix)", .{clip(text)});
            return false;
        }
        if (self.pending_count == max_pending) {
            ctx.fail(key, .too_many, "too many references in one mod", .{});
            return false;
        }
        var p: Pending = .{ .entry = @intCast(self.count), .param = @intCast(pi), .item = @intCast(item), .kind = target, .id = @splat(0), .id_len = @intCast(text.len), .file = file_index, .section = @intFromEnum(kind), .index = @intCast(index) };
        @memcpy(p.id[0..text.len], text);
        self.pending[self.pending_count] = p;
        self.pending_count += 1;
        return true;
    }

    /// Resolves references between this mod's entries. Reports problems to `report`.
    pub fn finish(self: *Batch, report: *Report) error{InvalidCharacterContent}!void {
        for (self.pending[0..self.pending_count]) |p| {
            const wanted = p.id[0..p.id_len];
            const found = for (self.entries[0..self.count], 0..) |*e, i| {
                if (e.kind == p.kind and std.mem.eql(u8, e.localId(), wanted)) break i;
            } else null;
            const entry = &self.entries[p.entry];
            if (found) |i| {
                entry.values[p.param].v[p.item] = @floatFromInt(i);
            } else {
                var key_buf: [64]u8 = undefined;
                const param = schema(entry.kind)[p.param];
                const key = if (param.ty == .refs)
                    std.fmt.bufPrint(&key_buf, "{s}[{d}].{s}[{d}]", .{ sectionKey(@enumFromInt(p.section)), p.index, param.key, p.item }) catch ""
                else
                    std.fmt.bufPrint(&key_buf, "{s}[{d}].{s}", .{ sectionKey(@enumFromInt(p.section)), p.index, param.key }) catch "";
                report.add(self.files[p.file][0..self.file_lens[p.file]], key, .unknown_ref, "no {s} \"{s}\" in this mod", .{ sectionKey(p.kind), wanted });
            }
        }
        self.pending_count = 0;
        if (!report.ok()) return error.InvalidCharacterContent;
    }
};

const Ctx = struct {
    report: *Report,
    file: []const u8,
    prefix: []const u8,

    fn fail(self: *Ctx, field: []const u8, code: Code, comptime fmt: []const u8, args: anytype) void {
        var buf: [64]u8 = undefined;
        const key = if (field.len == 0)
            self.prefix
        else
            std.fmt.bufPrint(&buf, "{s}.{s}", .{ self.prefix, field }) catch self.prefix;
        self.report.add(self.file, key, code, fmt, args);
    }
};

fn isSection(key: []const u8) bool {
    for (std.enums.values(Kind)) |k| if (std.mem.eql(u8, key, sectionKey(k))) return true;
    return false;
}

fn keyList(kind: Kind) []const u8 {
    return switch (kind) {
        .hair_style => ", base, length, volume, curl, spike, parting, cards, tip_color, tint_slot",
        .face_preset => ", base, jaw_width, chin_height, cheek_fullness, eye_size, eye_spacing, eye_tilt, brow_height, nose_length, mouth_width, lip_fullness",
        .armor_piece => ", part, attach_joint, silhouette, size, offset, flare, fins, bevel, mirror, tint, emissive",
        .armor_set => ", base, pieces, palette",
        .palette => ", role, colors",
        .cel_style => ", bands, band_thresholds, shadow_tint, outline_width, outline_color, rim_strength, rim_color, specular_size, saturation",
    };
}

fn checkCel(ctx: *Ctx, entry: *Entry) void {
    const bands = entry.int("bands") orelse return;
    const ramp = entry.value("band_thresholds") orelse return;
    if (@as(i32, ramp.n) != bands - 1) ctx.fail("band_thresholds", .inconsistent, "{d} thresholds for {d} bands (need bands - 1)", .{ ramp.n, bands });
}

fn clip(text: []const u8) []const u8 {
    return text[0..@min(text.len, 24)];
}

fn joinChoices(buffer: []u8, options: []const []const u8) []const u8 {
    var n: usize = 0;
    for (options, 0..) |o, i| {
        const sep = if (i == 0) "" else "|";
        const room = buffer.len - n;
        if (room < o.len + sep.len + 3) {
            @memcpy(buffer[n..][0..3], "...");
            return buffer[0 .. n + 3];
        }
        @memcpy(buffer[n..][0..sep.len], sep);
        n += sep.len;
        @memcpy(buffer[n..][0..o.len], o);
        n += o.len;
    }
    return buffer[0..n];
}

fn scalar(x: f32) [max_values]f32 {
    var v: [max_values]f32 = @splat(0);
    v[0] = x;
    return v;
}

fn number(v: std.json.Value) ?f64 {
    const n: f64 = switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => return null,
    };
    return if (std.math.isFinite(n)) n else null;
}

fn validName(text: []const u8) bool {
    if (text.len == 0 or text.len >= display_len or text[0] == ' ') return false;
    for (text) |c| if (c < 0x20 or c > 0x7e) return false;
    return true;
}

fn parseColor(raw: std.json.Value) ?[3]f32 {
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
                if (n < 0 or n > 1) return null;
                c.* = @floatCast(n);
            }
            return out;
        },
        else => return null,
    }
}

fn applyDefault(out: *Value, param: Param) void {
    switch (param.ty) {
        .float => |t| out.* = .{ .set = true, .n = 1, .v = scalar(t.default) },
        .int => |t| out.* = .{ .set = true, .n = 1, .v = scalar(@floatFromInt(t.default)) },
        .boolean => |b| out.* = .{ .set = true, .n = 1, .v = scalar(if (b) 1 else 0) },
        .choice => out.* = .{ .set = true, .n = 1 },
        .vec3 => |t| {
            out.* = .{ .set = true, .n = 3 };
            out.v[0..3].* = t.default;
        },
        .color => |c| if (c) |rgb| {
            out.* = .{ .set = true, .n = 3 };
            out.v[0..3].* = rgb;
        },
        .colors, .floats, .ref, .refs => {},
    }
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
            var a = self.entries[base + i];
            a.base = 0;
            if (!std.meta.eql(a, b.*)) return false;
        }
        return base + batch.count == self.count or !std.mem.eql(u8, self.entries[base + batch.count].modName(), batch.modName());
    }

    /// Adds a mod's entries. Call `canInstall` first; this asserts instead of failing.
    pub fn install(self: *Registry, batch: *const Batch) InstallOutcome {
        if (batch.count == 0) return .unchanged;
        if (self.modBase(batch.modName()) != null) return .unchanged;
        std.debug.assert(self.count + batch.count <= self.entries.len);
        const base = self.count;
        for (batch.slice()) |e| {
            var copy = e;
            copy.base = @intCast(base);
            self.entries[self.count] = copy;
            const handle: Handle = @intCast(self.count);
            self.count += 1;
            self.insertSorted(copy.kind, handle);
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
    \\  "hair_styles": [ { "id": "flame", "name": "Flame Crest", "base": "crest", "spike": 0.8, "cards": 32, "tip_color": "#ff8800" } ],
    \\  "armor_pieces": [
    \\    { "id": "wing", "name": "Wing Pauldron", "part": "pauldron", "attach_joint": "shoulder", "silhouette": "fin", "fins": 3, "flare": 1.5, "offset": [0.05, 0.1, 0] },
    \\    { "id": "visor", "name": "Slit Visor", "part": "helmet", "attach_joint": "head", "mirror": false } ],
    \\  "palettes": [ { "id": "ember", "name": "Ember", "role": "outfit", "colors": ["#220000", [0.9, 0.3, 0.1]] } ],
    \\  "armor_sets": [ { "id": "phoenix", "name": "Phoenix", "base": "starforge", "pieces": ["wing", "visor"], "palette": "ember" } ],
    \\  "cel_styles": [ { "id": "ink", "name": "Ink Wash", "bands": 4, "band_thresholds": [0.2, 0.5, 0.8], "outline_width": 2.5 } ] }
;

test "a valid file loads with defaults, typed reads, and resolved references" {
    var report: Report = .{};
    const batch = try loadOne("testmod", &.{.{ "a.json", sample }}, &report);
    defer batch.destroy();
    try testing.expect(report.ok());
    try testing.expectEqual(@as(usize, 6), batch.count);
    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try reg.canInstall(batch, &report);
    try testing.expectEqual(InstallOutcome.installed, reg.install(batch));
    const flame = reg.get(reg.find(.hair_style, &Id.parse("testmod.flame").?).?);
    try testing.expectEqualStrings("Flame Crest", flame.name());
    try testing.expectEqualStrings("crest", flame.choice("base").?);
    try testing.expectEqual(@as(f32, 0.8), flame.float("spike").?);
    try testing.expectEqual(@as(f32, 1), flame.float("length").?);
    try testing.expectEqual(@as(i32, 32), flame.int("cards").?);
    try testing.expectApproxEqAbs(@as(f32, 1), flame.color("tip_color").?[0], 1e-6);
    const wing = reg.get(reg.find(.armor_piece, &Id.parse("testmod.wing").?).?);
    try testing.expectEqualStrings("fin", wing.choice("silhouette").?);
    try testing.expectEqual(true, wing.boolean("mirror").?);
    try testing.expectEqual([3]f32{ 0.05, 0.1, 0 }, wing.vec3("offset").?);
    const set = reg.get(reg.find(.armor_set, &Id.parse("testmod.phoenix").?).?);
    try testing.expectEqual(@as(usize, 2), set.refCount("pieces"));
    try testing.expectEqualStrings("Slit Visor", reg.get(set.refAt("pieces", 1).?).name());
    try testing.expectEqualStrings("Ember", reg.get(set.refAt("palette", 0).?).name());
    const ember = reg.get(set.refAt("palette", 0).?);
    try testing.expectApproxEqAbs(@as(f32, 0.9), ember.colorAt("colors", 1).?[0], 1e-6);
    try testing.expect(ember.colorAt("colors", 2) == null);
    // Optional values with no default stay unset.
    try testing.expect(reg.get(reg.find(.cel_style, &Id.parse("testmod.ink").?).?).color("rim_color") == null);
}

test "every bad value is rejected with its file, key path and reason" {
    const Case = struct { json: []const u8, key: []const u8, code: Code };
    const head = "{\"format\":1,";
    const cases = [_]Case{
        .{ .json = "{ not json", .key = "", .code = .invalid_json },
        .{ .json = "[]", .key = "", .code = .wrong_type },
        .{ .json = "{}", .key = "format", .code = .missing_key },
        .{ .json = "{\"format\":2}", .key = "format", .code = .bad_format },
        .{ .json = head ++ "\"hairstyles\":[]}", .key = "hairstyles", .code = .unknown_key },
        .{ .json = head ++ "\"hair_styles\":{}}", .key = "hair_styles", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"name\":\"X\"}]}", .key = "hair_styles[0].id", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"Bad Id\",\"name\":\"X\"}]}", .key = "hair_styles[0].id", .code = .bad_id },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\"}]}", .key = "hair_styles[0].name", .code = .missing_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"caf\\u00e9\"}]}", .key = "hair_styles[0].name", .code = .bad_name },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"This display name is far too long to fit\"}]}", .key = "hair_styles[0].name", .code = .too_long },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"volumee\":1}]}", .key = "hair_styles[0].volumee", .code = .unknown_key },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"volume\":9}]}", .key = "hair_styles[0].volume", .code = .out_of_range },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"volume\":\"big\"}]}", .key = "hair_styles[0].volume", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"cards\":2.5}]}", .key = "hair_styles[0].cards", .code = .wrong_type },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"base\":\"mohawk\"}]}", .key = "hair_styles[0].base", .code = .bad_choice },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\",\"tip_color\":\"red\"}]}", .key = "hair_styles[0].tip_color", .code = .bad_color },
        .{ .json = head ++ "\"hair_styles\":[{\"id\":\"a\",\"name\":\"X\"},{\"id\":\"a\",\"name\":\"Y\"}]}", .key = "hair_styles[1].id", .code = .duplicate_id },
        .{ .json = head ++ "\"armor_pieces\":[{\"id\":\"p\",\"name\":\"P\",\"attach_joint\":\"head\"}]}", .key = "armor_pieces[0].part", .code = .missing_key },
        .{ .json = head ++ "\"armor_pieces\":[{\"id\":\"p\",\"name\":\"P\",\"part\":\"helmet\",\"attach_joint\":\"head\",\"offset\":[0,0]}]}", .key = "armor_pieces[0].offset", .code = .wrong_type },
        .{ .json = head ++ "\"armor_pieces\":[{\"id\":\"p\",\"name\":\"P\",\"part\":\"helmet\",\"attach_joint\":\"head\",\"offset\":[0,0,3]}]}", .key = "armor_pieces[0].offset", .code = .out_of_range },
        .{ .json = head ++ "\"armor_pieces\":[{\"id\":\"p\",\"name\":\"P\",\"part\":\"helmet\",\"attach_joint\":\"head\",\"mirror\":1}]}", .key = "armor_pieces[0].mirror", .code = .wrong_type },
        .{ .json = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\",\"pieces\":[\"ghost\"]}]}", .key = "armor_sets[0].pieces[0]", .code = .unknown_ref },
        .{ .json = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\",\"pieces\":[\"other.piece\"]}]}", .key = "armor_sets[0].pieces[0]", .code = .bad_id },
        .{ .json = head ++ "\"armor_sets\":[{\"id\":\"s\",\"name\":\"S\"}]}", .key = "armor_sets[0].pieces", .code = .missing_key },
        .{ .json = head ++ "\"palettes\":[{\"id\":\"c\",\"name\":\"C\",\"role\":\"hair\",\"colors\":[]}]}", .key = "palettes[0].colors", .code = .missing_key },
        .{ .json = head ++ "\"palettes\":[{\"id\":\"c\",\"name\":\"C\",\"role\":\"hair\",\"colors\":[\"#112233\",[2,0,0]]}]}", .key = "palettes[0].colors[1]", .code = .bad_color },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"bands\":3,\"band_thresholds\":[0.5]}]}", .key = "cel_styles[0].band_thresholds", .code = .inconsistent },
        .{ .json = head ++ "\"cel_styles\":[{\"id\":\"c\",\"name\":\"C\",\"bands\":3,\"band_thresholds\":[0.6,0.4]}]}", .key = "cel_styles[0].band_thresholds", .code = .out_of_range },
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
            var buf: [200]u8 = undefined;
            std.debug.print("case {s}\n  wanted {s} {s}; got {d} diagnostics, first: {s}\n", .{ c.json, c.key, @tagName(c.code), report.count, if (report.count > 0) report.items[0].format(&buf) else "-" });
        }
        try testing.expect(found);
    }
}

test "problems are collected rather than stopping at the first, and overflow is counted" {
    var report: Report = .{};
    var json: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&json);
    try w.writeAll("{\"format\":1,\"hair_styles\":[");
    for (0..20) |i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"id\":\"x");
        try w.print("{d}", .{i});
        try w.writeAll("\",\"name\":\"N\",\"volume\":99}");
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

    var report: Report = .{};
    const batch = try loadOne("testmod", &.{.{ "a.json", sample }}, &report);
    defer batch.destroy();
    var reg = try Registry.init(testing.allocator, 16);
    defer reg.deinit();
    try testing.expect(s.resolve(.hair_style, &reg) == null);
    try testing.expect(s.resolve(.hair_style, null) == null);
    _ = reg.install(batch);
    try testing.expect(s.resolve(.hair_style, &reg) != null);
    // A mod that is missing keeps its id but resolves to nothing.
    try testing.expect(s.resolve(.cel_style, &reg) == null);
    try testing.expectEqualStrings("gone.style", s.get(.cel_style).?.slice());
}
