//! The imported character meshes a player has uploaded, kept side by side so they can switch
//! between them or delete one. Each import lives in its own folder,
//! `saves/imports/<name>/`, holding the source GLB, its component sidecar and any saved vertex
//! edits; `saves/imports/active.txt` names the one in use. Names come from the uploaded file
//! (lower case, letters, digits and dashes) and are made unique.
const std = @import("std");

pub const root = "saves/imports";
pub const active_file = "saves/imports/active.txt";
pub const capacity = 16;
pub const name_len = 32;

/// The single-import layout this replaces; moved into the library on first start.
pub const legacy_source = "saves/imported-character.glb";
pub const legacy_modifiers = "saves/imported-character.modifiers.json";
pub const legacy_edited = "saves/imported-character.edited.hwmesh";

pub const Entry = struct {
    name: [name_len]u8 = @splat(0),
    len: u8 = 0,

    pub fn slice(self: *const Entry) []const u8 {
        return self.name[0..self.len];
    }
};

pub const Library = struct {
    entries: [capacity]Entry = @splat(.{}),
    count: u8 = 0,
    /// The import drawn on the character, if any.
    active: ?u8 = null,

    pub fn find(self: *const Library, name: []const u8) ?u8 {
        for (self.entries[0..self.count], 0..) |*e, i| if (std.mem.eql(u8, e.slice(), name)) return @intCast(i);
        return null;
    }

    pub fn activeName(self: *const Library) ?[]const u8 {
        const i = self.active orelse return null;
        return self.entries[i].slice();
    }

    fn insertSorted(self: *Library, name: []const u8) void {
        if (self.count == capacity or name.len == 0 or name.len > name_len) return;
        var at: usize = self.count;
        for (self.entries[0..self.count], 0..) |*e, i| if (std.mem.order(u8, name, e.slice()) == .lt) {
            at = i;
            break;
        };
        std.mem.copyBackwards(Entry, self.entries[at + 1 .. self.count + 1], self.entries[at..self.count]);
        var entry: Entry = .{ .len = @intCast(name.len) };
        @memcpy(entry.name[0..name.len], name);
        self.entries[at] = entry;
        self.count += 1;
    }
};

/// A folder-safe name from an uploaded file's name ("Mecha Suit 3D model.glb" -> "mecha-suit-3d-model").
pub fn slug(out: *[name_len]u8, file_name: []const u8) []const u8 {
    const stem = if (std.mem.lastIndexOfScalar(u8, file_name, '.')) |dot| file_name[0..dot] else file_name;
    var n: usize = 0;
    var dash = false;
    for (stem) |ch| {
        if (n == name_len - 4) break; // room for a "-NN" suffix
        const lower = std.ascii.toLower(ch);
        if (std.ascii.isAlphanumeric(lower)) {
            if (dash and n > 0) {
                out[n] = '-';
                n += 1;
            }
            dash = false;
            out[n] = lower;
            n += 1;
        } else dash = true;
    }
    if (n == 0) {
        @memcpy(out[0..6], "import");
        n = 6;
    }
    return out[0..n];
}

/// `base`, or `base-2`, `base-3`... whichever the library does not hold yet.
pub fn unique(lib: *const Library, out: *[name_len]u8, base: []const u8) []const u8 {
    if (lib.find(base) == null) {
        @memcpy(out[0..base.len], base);
        return out[0..base.len];
    }
    var k: usize = 2;
    while (k < 100) : (k += 1) {
        const name = std.fmt.bufPrint(out, "{s}-{d}", .{ base, k }) catch break;
        if (lib.find(name) == null) return name;
    }
    return std.fmt.bufPrint(out, "{s}-x", .{base}) catch base;
}

pub const Paths = struct {
    source: [96]u8 = undefined,
    source_len: usize = 0,
    modifiers: [96]u8 = undefined,
    modifiers_len: usize = 0,
    edited: [96]u8 = undefined,
    edited_len: usize = 0,

    pub fn of(name: []const u8) Paths {
        var p: Paths = .{};
        p.source_len = (std.fmt.bufPrint(&p.source, "{s}/{s}/source.glb", .{ root, name }) catch unreachable).len;
        p.modifiers_len = (std.fmt.bufPrint(&p.modifiers, "{s}/{s}/modifiers.json", .{ root, name }) catch unreachable).len;
        p.edited_len = (std.fmt.bufPrint(&p.edited, "{s}/{s}/edited.hwmesh", .{ root, name }) catch unreachable).len;
        return p;
    }
    pub fn sourcePath(self: *const Paths) []const u8 {
        return self.source[0..self.source_len];
    }
    pub fn modifiersPath(self: *const Paths) []const u8 {
        return self.modifiers[0..self.modifiers_len];
    }
    pub fn editedPath(self: *const Paths) []const u8 {
        return self.edited[0..self.edited_len];
    }
};

/// Every folder under `root` that holds a source GLB, in name order, and the active one.
pub fn scan(io: std.Io) Library {
    var lib: Library = .{};
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return lib;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory or entry.name.len > name_len) continue;
        const paths = Paths.of(entry.name);
        std.Io.Dir.cwd().access(io, paths.sourcePath(), .{}) catch continue;
        lib.insertSorted(entry.name);
    }
    var buffer: [name_len + 2]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(io, active_file, &buffer) catch return lib;
    lib.active = lib.find(std.mem.trim(u8, text, " \r\n\t"));
    return lib;
}

pub fn writeActive(io: std.Io, name: ?[]const u8) void {
    const Save = @import("Save.zig");
    if (name) |n| Save.writeFile(io, active_file, n) catch {} else std.Io.Dir.cwd().deleteFile(io, active_file) catch {};
}

/// Move a single import from before the library into it, as the active entry.
pub fn migrateLegacy(io: std.Io) void {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, legacy_source, .{}) catch return;
    const paths = Paths.of("imported-character");
    cwd.createDirPath(io, root ++ "/imported-character") catch return;
    cwd.rename(legacy_source, cwd, paths.sourcePath(), io) catch return;
    cwd.rename(legacy_modifiers, cwd, paths.modifiersPath(), io) catch {};
    cwd.rename(legacy_edited, cwd, paths.editedPath(), io) catch {};
    writeActive(io, "imported-character");
}

/// Delete an import's folder.
pub fn remove(io: std.Io, name: []const u8) void {
    var buffer: [96]u8 = undefined;
    const path = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ root, name }) catch return;
    std.Io.Dir.cwd().deleteTree(io, path) catch {};
}

test "file names become short, safe, unique library names" {
    var a: [name_len]u8 = undefined;
    try std.testing.expectEqualStrings("mecha-suit-3d-model", slug(&a, "mecha suit 3d model.glb"));
    try std.testing.expectEqualStrings("futuristic-female-mecha", slug(&a, "futuristic+female+mecha.GLB"));
    try std.testing.expectEqualStrings("import", slug(&a, "+++.glb"));
    const long_name: [80]u8 = @splat('a');
    try std.testing.expect(slug(&a, &long_name).len <= name_len - 4);
    var lib: Library = .{};
    lib.insertSorted("mecha");
    lib.insertSorted("alpha");
    try std.testing.expectEqualStrings("alpha", lib.entries[0].slice());
    var b: [name_len]u8 = undefined;
    try std.testing.expectEqualStrings("mecha-2", unique(&lib, &b, "mecha"));
    lib.insertSorted("mecha-2");
    try std.testing.expectEqualStrings("mecha-3", unique(&lib, &b, "mecha"));
    try std.testing.expectEqualStrings("new", unique(&lib, &b, "new"));
    const p = Paths.of("mecha");
    try std.testing.expectEqualStrings("saves/imports/mecha/source.glb", p.sourcePath());
    try std.testing.expectEqualStrings("saves/imports/mecha/edited.hwmesh", p.editedPath());
}
