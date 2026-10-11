//! Mod packages, format 1: a directory `mods/<name>/` with a `mod.json` manifest that adds
//! machine blueprints and, optionally, one WebAssembly script module (see `script/Host.zig`).
//! This is the whole public mod API for API version 1: data validated by the same blueprint
//! rules as built-in content, plus pure, budgeted scripts with no imports. Mods cannot read
//! files, call the engine, or reference another mod's scripts.
//!
//! Loading is all-or-nothing: every file is read and validated before a package is returned,
//! and the world installs a package only if all its names are free.
const std = @import("std");
const Blueprint = @import("../machine/Blueprint.zig");
const Host = @import("../script/Host.zig");
const CharacterContent = @import("../game/CharacterContent.zig");
const Mod = @This();

comptime {
    std.debug.assert(CharacterContent.mod_name_len == Host.name_len);
}

pub const format_version: u32 = 1;
pub const max_blueprints = 8;
pub const max_exports = 8;
pub const max_character_files = 8;
pub const max_file_bytes = 1 << 20;
pub const name_len = Host.name_len;

pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,
    pub fn parse(text: []const u8) error{InvalidVersion}!Version {
        var it = std.mem.splitScalar(u8, text, '.');
        var parts: [3]u16 = undefined;
        for (&parts) |*p| p.* = std.fmt.parseInt(u16, it.next() orelse return error.InvalidVersion, 10) catch return error.InvalidVersion;
        if (it.next() != null) return error.InvalidVersion;
        return .{ .major = parts[0], .minor = parts[1], .patch = parts[2] };
    }
    pub fn eql(a: Version, b: Version) bool {
        return a.major == b.major and a.minor == b.minor and a.patch == b.patch;
    }
};

const ScriptsDoc = struct { module: []const u8, exports: []const []const u8, fuel: u64 = 20000, memory_pages: u32 = 4 };
const Manifest = struct {
    format: u32,
    name: []const u8,
    version: []const u8,
    api: u32,
    description: []const u8 = "",
    blueprints: []const []const u8 = &.{},
    /// Character content files (hairstyles, armor, palettes, cel styles); see docs/mods.md.
    character: []const []const u8 = &.{},
    scripts: ?ScriptsDoc = null,
};

pub const Error = error{
    InvalidManifest,
    UnsupportedModFormat,
    IncompatibleApi,
    InvalidModName,
    NameMismatch,
    InvalidVersion,
    UnsafePath,
    TooManyBlueprints,
    TooManyExports,
    InvalidExportName,
    InvalidScriptLimits,
    ForeignScript,
    UndeclaredScript,
    InvalidBlueprint,
    TooManyCharacterFiles,
    /// Details are in the `CharacterContent.Report` passed to `loadReported`.
    InvalidCharacterContent,
    MissingFile,
    OutOfMemory,
};

/// A validated package. `wasm` and `script_path` are owned; free with `deinit`.
pub const Package = struct {
    allocator: std.mem.Allocator,
    name_buffer: [name_len]u8 = @splat(0),
    name_length: usize = 0,
    version: Version,
    blueprints: [max_blueprints]Blueprint = undefined,
    blueprint_count: usize = 0,
    wasm: ?[]u8 = null,
    script_path: ?[]u8 = null,
    export_names: [max_exports][name_len]u8 = undefined,
    export_lengths: [max_exports]usize = @splat(0),
    export_count: usize = 0,
    fuel: u64 = 0,
    memory_pages: u32 = 0,
    /// Validated character content, if the manifest lists any. Owned.
    character: ?*CharacterContent.Batch = null,

    pub fn name(self: *const Package) []const u8 {
        return self.name_buffer[0..self.name_length];
    }
    pub fn exports(self: *const Package, out: *[max_exports][]const u8) []const []const u8 {
        for (0..self.export_count) |i| out[i] = self.export_names[i][0..self.export_lengths[i]];
        return out[0..self.export_count];
    }
    pub fn deinit(self: *Package) void {
        if (self.wasm) |w| self.allocator.free(w);
        self.wasm = null;
        if (self.script_path) |path| self.allocator.free(path);
        self.script_path = null;
        if (self.character) |b| b.destroy();
        self.character = null;
    }
    pub fn characterCount(self: *const Package) usize {
        return if (self.character) |b| b.count else 0;
    }
};

fn identifier(text: []const u8) bool {
    if (text.len == 0 or text.len >= name_len) return false;
    for (text) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}

/// Package-relative paths only: no absolute paths, parent directories, or backslashes.
fn safePath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| if (part.len == 0 or std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".")) return false;
    return true;
}

/// Loads mod directory `dir_name` through `files.read(allocator, path) ![]u8` (paths are
/// package-relative; the caller frees nothing returned here except via `Package.deinit`).
pub fn load(allocator: std.mem.Allocator, dir_name: []const u8, files: anytype) Error!Package {
    var discarded: CharacterContent.Report = .{};
    return loadReported(allocator, dir_name, files, &discarded);
}

/// Like `load`; when character content is rejected, `report` says which file, key and why.
pub fn loadReported(allocator: std.mem.Allocator, dir_name: []const u8, files: anytype, report: *CharacterContent.Report) Error!Package {
    const manifest_bytes = files.read(allocator, "mod.json") catch return error.MissingFile;
    defer allocator.free(manifest_bytes);
    const parsed = std.json.parseFromSlice(Manifest, allocator, manifest_bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidManifest;
    defer parsed.deinit();
    const m = parsed.value;
    if (m.format != format_version) return error.UnsupportedModFormat;
    if (m.api != Host.api_version) return error.IncompatibleApi;
    if (!identifier(m.name)) return error.InvalidModName;
    if (!std.mem.eql(u8, m.name, dir_name)) return error.NameMismatch;
    var pkg: Package = .{ .allocator = allocator, .version = try Version.parse(m.version) };
    errdefer pkg.deinit();
    @memcpy(pkg.name_buffer[0..m.name.len], m.name);
    pkg.name_length = m.name.len;
    if (m.scripts) |s| {
        if (s.exports.len > max_exports) return error.TooManyExports;
        if (s.fuel < 100 or s.fuel > 1_000_000 or s.memory_pages == 0 or s.memory_pages > 64) return error.InvalidScriptLimits;
        if (!safePath(s.module)) return error.UnsafePath;
        for (s.exports, 0..) |e, i| {
            if (!identifier(e)) return error.InvalidExportName;
            @memcpy(pkg.export_names[i][0..e.len], e);
            pkg.export_lengths[i] = e.len;
        }
        pkg.export_count = s.exports.len;
        pkg.fuel = s.fuel;
        pkg.memory_pages = s.memory_pages;
        pkg.script_path = try allocator.dupe(u8, s.module);
        pkg.wasm = files.read(allocator, s.module) catch return error.MissingFile;
    }
    if (m.blueprints.len > max_blueprints) return error.TooManyBlueprints;
    for (m.blueprints) |path| {
        if (!safePath(path)) return error.UnsafePath;
        const bytes = files.read(allocator, path) catch return error.MissingFile;
        defer allocator.free(bytes);
        const bp = Blueprint.parse(allocator, bytes) catch return error.InvalidBlueprint;
        // Script devices may only name this mod's declared exports.
        for (bp.devices[0..bp.device_count]) |*d| {
            if (d.kind != .script) continue;
            const ref = d.scriptName();
            const dot = std.mem.indexOfScalar(u8, ref, '.').?;
            if (!std.mem.eql(u8, ref[0..dot], m.name)) return error.ForeignScript;
            const declared = if (m.scripts) |s| for (s.exports) |e| {
                if (std.mem.eql(u8, e, ref[dot + 1 ..])) break true;
            } else false else false;
            if (!declared) return error.UndeclaredScript;
        }
        pkg.blueprints[pkg.blueprint_count] = bp;
        pkg.blueprint_count += 1;
    }
    if (m.character.len > max_character_files) return error.TooManyCharacterFiles;
    if (m.character.len > 0) {
        const batch = try CharacterContent.Batch.create(allocator, m.name);
        pkg.character = batch;
        for (m.character) |path| {
            if (!safePath(path)) return error.UnsafePath;
            const bytes = files.read(allocator, path) catch return error.MissingFile;
            defer allocator.free(bytes);
            try batch.addFile(path, bytes, report);
        }
        batch.finish(report) catch return error.InvalidCharacterContent;
    }
    return pkg;
}

/// In-memory package files for tests and tools.
/// Contents are held by value so a `MemoryFiles` can be returned from a helper.
pub const MemoryFiles = struct {
    paths: []const []const u8,
    contents: [4][]const u8 = @splat(""),
    pub fn read(self: MemoryFiles, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        for (self.paths, self.contents[0..self.paths.len]) |p, c| if (std.mem.eql(u8, p, path)) return allocator.dupe(u8, c);
        return error.FileNotFound;
    }
};

pub fn glowworksFiles(manifest: []const u8) MemoryFiles {
    return .{ .paths = &.{ "mod.json", "blueprints/breathing_lamp.json", "glowworks.wasm" }, .contents = .{ manifest, @embedFile("glowworks.lamp"), @embedFile("glowworks.wasm"), "" } };
}

test "the example mod package loads, and its scripts install into a host" {
    var pkg = try load(std.testing.allocator, "glowworks", glowworksFiles(@embedFile("glowworks.mod")));
    defer pkg.deinit();
    try std.testing.expectEqualStrings("glowworks", pkg.name());
    try std.testing.expect(pkg.version.eql(.{ .major = 1, .minor = 0, .patch = 0 }));
    try std.testing.expectEqual(@as(usize, 1), pkg.blueprint_count);
    try std.testing.expectEqualStrings("breathing_lamp", pkg.blueprints[0].name());
    var host = Host.init(std.testing.allocator);
    defer host.deinit();
    var names: [max_exports][]const u8 = undefined;
    try host.add(pkg.name(), pkg.wasm.?, pkg.exports(&names), pkg.fuel, pkg.memory_pages);
    try std.testing.expect(host.find("glowworks.breathe") != null);
}

test "invalid packages are rejected with a reason" {
    const a = std.testing.allocator;
    const base = @embedFile("glowworks.mod");
    const Case = struct { from: []const u8, to: []const u8, err: Error };
    const cases = [_]Case{
        .{ .from = "\"api\": 1", .to = "\"api\": 2", .err = error.IncompatibleApi },
        .{ .from = "\"format\": 1", .to = "\"format\": 3", .err = error.UnsupportedModFormat },
        .{ .from = "\"1.0.0\"", .to = "\"1.0\"", .err = error.InvalidVersion },
        .{ .from = "\"name\": \"glowworks\"", .to = "\"name\": \"Glow Works\"", .err = error.InvalidModName },
        .{ .from = "\"name\": \"glowworks\"", .to = "\"name\": \"other\"", .err = error.NameMismatch },
        .{ .from = "\"blueprints/breathing_lamp.json\"", .to = "\"../../saves/quicksave.json\"", .err = error.UnsafePath },
        .{ .from = "\"glowworks.wasm\"", .to = "\"/etc/passwd\"", .err = error.UnsafePath },
        .{ .from = "\"breathe\", ", .to = "", .err = error.UndeclaredScript },
        .{ .from = "\"fuel\": 20000", .to = "\"fuel\": 5000000", .err = error.InvalidScriptLimits },
        .{ .from = "\"memory_pages\": 4", .to = "\"memory_pages\": 0", .err = error.InvalidScriptLimits },
    };
    for (cases) |c| {
        const manifest = try std.mem.replaceOwned(u8, a, base, c.from, c.to);
        defer a.free(manifest);
        try std.testing.expect(!std.mem.eql(u8, manifest, base));
        try std.testing.expectError(c.err, load(a, "glowworks", glowworksFiles(manifest)));
    }
    // A blueprint naming another mod's script is foreign, even if the export name matches.
    const foreign = try std.mem.replaceOwned(u8, a, @embedFile("glowworks.lamp"), "glowworks.breathe", "othermod.breathe");
    defer a.free(foreign);
    const files: MemoryFiles = .{ .paths = &.{ "mod.json", "blueprints/breathing_lamp.json", "glowworks.wasm" }, .contents = .{ base, foreign, @embedFile("glowworks.wasm"), "" } };
    try std.testing.expectError(error.ForeignScript, load(a, "glowworks", files));
    try std.testing.expectError(error.MissingFile, load(a, "glowworks", MemoryFiles{ .paths = &.{"mod.json"}, .contents = .{ base, "", "", "" } }));
    try std.testing.expect(Version.parse("1.2.3x") == error.InvalidVersion);
}

/// In-memory package files of any number, for tests and tools.
pub const FileList = struct {
    pub const Item = struct { path: []const u8, bytes: []const u8 };
    items: []const Item,
    pub fn read(self: FileList, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        for (self.items) |item| if (std.mem.eql(u8, item.path, path)) return allocator.dupe(u8, item.bytes);
        return error.FileNotFound;
    }
};

const ember_manifest = @embedFile("emberwear.mod");
const ember_hair = @embedFile("emberwear.hair");
const ember_armor = @embedFile("emberwear.armor");
const ember_style = @embedFile("emberwear.style");

fn emberFiles(items: *[4]FileList.Item, manifest: []const u8, hair: []const u8, armor: []const u8) FileList {
    items.* = .{
        .{ .path = "mod.json", .bytes = manifest },
        .{ .path = "character/hair.json", .bytes = hair },
        .{ .path = "character/armor.json", .bytes = armor },
        .{ .path = "character/style.json", .bytes = ember_style },
    };
    return .{ .items = items };
}

test "the example character mod loads, installs, and lists in stable order" {
    var items: [4]FileList.Item = undefined;
    var report: CharacterContent.Report = .{};
    var pkg = try loadReported(std.testing.allocator, "emberwear", emberFiles(&items, ember_manifest, ember_hair, ember_armor), &report);
    defer pkg.deinit();
    try std.testing.expect(report.ok());
    try std.testing.expectEqual(@as(usize, 9), pkg.characterCount());
    var registry = try CharacterContent.Registry.init(std.testing.allocator, 32);
    defer registry.deinit();
    try registry.canInstall(pkg.character.?, &report);
    try std.testing.expectEqual(CharacterContent.InstallOutcome.installed, registry.install(pkg.character.?));
    const hair = registry.list(.hair_style);
    try std.testing.expectEqual(@as(usize, 2), hair.len);
    try std.testing.expectEqualStrings("Flame Crest", registry.get(hair[0]).name());
    const phoenix = registry.get(registry.find(.armor_set, &CharacterContent.Id.parse("emberwear.phoenix").?).?);
    try std.testing.expectEqual(@as(usize, 3), phoenix.refCount("pieces"));
    try std.testing.expectEqualStrings("Slit Visor", registry.get(phoenix.refAt("pieces", 1).?).name());
    // Mods without character files, like glowworks, carry no batch.
    var glow = try load(std.testing.allocator, "glowworks", glowworksFiles(@embedFile("glowworks.mod")));
    defer glow.deinit();
    try std.testing.expect(glow.character == null);
}

test "bad character content rejects the whole mod with file, key and reason; nothing leaks" {
    const a = std.testing.allocator;
    const Case = struct { file: enum { manifest, hair, armor }, from: []const u8, to: []const u8, err: Error, key: []const u8 = "", code: CharacterContent.Code = .invalid_json };
    const cases = [_]Case{
        .{ .file = .hair, .from = "\"spike\"", .to = "\"spikes\"", .err = error.InvalidCharacterContent, .key = "hair_styles[0].spikes", .code = .unknown_key },
        .{ .file = .hair, .from = "\"cards\": 32", .to = "\"cards\": 500", .err = error.InvalidCharacterContent, .key = "hair_styles[0].cards", .code = .out_of_range },
        .{ .file = .armor, .from = "\"slit_visor\", \"ash_greave\"", .to = "\"visor_x\", \"ash_greave\"", .err = error.InvalidCharacterContent, .key = "armor_sets[0].pieces[1]", .code = .unknown_ref },
        .{ .file = .armor, .from = "\"silhouette\": \"fin\"", .to = "\"silhouette\": \"spiral\"", .err = error.InvalidCharacterContent, .key = "armor_pieces[0].silhouette", .code = .bad_choice },
        .{ .file = .manifest, .from = "character/hair.json", .to = "../hair.json", .err = error.UnsafePath },
        .{ .file = .manifest, .from = "character/hair.json", .to = "character/nope.json", .err = error.MissingFile },
    };
    for (cases) |c| {
        const target = switch (c.file) {
            .manifest => ember_manifest,
            .hair => ember_hair,
            .armor => ember_armor,
        };
        const changed = try std.mem.replaceOwned(u8, a, target, c.from, c.to);
        defer a.free(changed);
        try std.testing.expect(!std.mem.eql(u8, changed, target));
        var items: [4]FileList.Item = undefined;
        const files = switch (c.file) {
            .manifest => emberFiles(&items, changed, ember_hair, ember_armor),
            .hair => emberFiles(&items, ember_manifest, changed, ember_armor),
            .armor => emberFiles(&items, ember_manifest, ember_hair, changed),
        };
        var report: CharacterContent.Report = .{};
        try std.testing.expectError(c.err, loadReported(a, "emberwear", files, &report));
        if (c.err == error.InvalidCharacterContent) {
            try std.testing.expect(report.count >= 1);
            const d = report.items[0];
            try std.testing.expectEqualStrings(c.key, d.keyPath());
            try std.testing.expectEqual(c.code, d.code);
            try std.testing.expect(std.mem.startsWith(u8, d.fileName(), "character/"));
        }
    }
}
