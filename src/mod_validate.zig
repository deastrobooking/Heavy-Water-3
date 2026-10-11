//! `mod-validate [mods-directory | mod-directory]`: loads every mod the way the game does and
//! prints each problem as `file: key: reason`. Exits non-zero if any mod is rejected, so modders
//! and CI can run it without opening a window. Run through `python3 tools/zig.py build validate-mods`.
const std = @import("std");
const Mod = @import("mod/Mod.zig");
const CharacterContent = @import("game/CharacterContent.zig");

const Files = struct {
    dir: std.Io.Dir,
    io: std.Io,
    pub fn read(files: @This(), allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return files.dir.readFileAlloc(files.io, path, allocator, .limited(Mod.max_file_bytes));
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const io = init.io;
    const gpa = init.gpa;
    const root_path = if (args.len >= 2) args[1] else "mods";
    var out_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buffer);
    const out = &stdout.interface;
    defer out.flush() catch {};

    var root = std.Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch |err| {
        try out.print("cannot open {s}: {s}\n", .{ root_path, @errorName(err) });
        std.process.exit(2);
    };
    defer root.close(io);

    var registry = try CharacterContent.Registry.init(gpa, CharacterContent.max_registry_entries);
    defer registry.deinit();
    var failures: usize = 0;
    var checked: usize = 0;

    // A directory holding `mod.json` is a single mod; otherwise each subdirectory is one.
    if (root.access(io, "mod.json", .{})) |_| {
        const name = std.fs.path.basename(std.mem.trimEnd(u8, root_path, "/"));
        checked += 1;
        if (!try check(gpa, io, out, &registry, root, name)) failures += 1;
    } else |_| {
        var it = root.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .directory) continue;
            var sub = root.openDir(io, entry.name, .{}) catch continue;
            defer sub.close(io);
            checked += 1;
            if (!try check(gpa, io, out, &registry, sub, entry.name)) failures += 1;
        }
    }
    try out.print("{d} mods checked, {d} rejected\n", .{ checked, failures });
    try out.flush();
    if (failures > 0) std.process.exit(1);
}

fn check(gpa: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, registry: *CharacterContent.Registry, dir: std.Io.Dir, name: []const u8) !bool {
    var report: CharacterContent.Report = .{};
    var pkg = Mod.loadReported(gpa, name, Files{ .dir = dir, .io = io }, &report) catch |err| {
        try out.print("REJECTED {s}: {s}\n", .{ name, @errorName(err) });
        try printReport(out, &report);
        return false;
    };
    defer pkg.deinit();
    if (pkg.character) |batch| {
        var conflicts: CharacterContent.Report = .{};
        registry.canInstall(batch, &conflicts) catch {
            try out.print("REJECTED {s}: character content conflicts\n", .{name});
            try printReport(out, &conflicts);
            return false;
        };
        _ = registry.install(batch);
    }
    try out.print("ok {s} {d}.{d}.{d}: {d} blueprints, {d} scripts, {d} character entries\n", .{ pkg.name(), pkg.version.major, pkg.version.minor, pkg.version.patch, pkg.blueprint_count, pkg.export_count, pkg.characterCount() });
    return true;
}

fn printReport(out: *std.Io.Writer, report: *const CharacterContent.Report) !void {
    for (report.slice()) |*d| {
        var buffer: [320]u8 = undefined;
        try out.print("  {s}\n", .{d.format(&buffer)});
    }
    if (report.dropped > 0) try out.print("  ... and {d} more\n", .{report.dropped});
}
