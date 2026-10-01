const std = @import("std");
const Gltf = @import("asset/Gltf.zig");
const Model = @import("asset/Model.zig");
const Blueprint = @import("machine/Blueprint.zig");
const Meta = @import("asset/Meta.zig");
const Guid = @import("asset/Guid.zig");
const Registry = @import("asset/Registry.zig");
const Heightmap = @import("procedural/Heightmap.zig");

/// Build-time tool:
///   asset-compiler compile <source> <source.meta> <output>
///       check the sidecar (GUID, kind, importer, settings, unchanged source), then compile a
///       glTF model, validate a blueprint, or compile a PGM heightmap
///   asset-compiler manifest <output> (<source.meta> <name> <output-name>)...
///       write the asset manifest the runtime registry loads
///   asset-compiler import <directory>
///       create missing sidecars (new GUIDs) and refresh hashes for every source under a
///       directory; existing GUIDs and settings are kept
///   asset-compiler heightmap <source.pgm> <output.hwmh> [world-width world-depth elevation base-height]
///       import ASCII or binary grayscale PGM data to the runtime heightmap format
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const io = init.io;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "compile") and args.len == 5) return compile(init.gpa, io, args[2], args[3], args[4]);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "manifest") and (args.len - 3) % 3 == 0) return manifest(init.gpa, io, args[2], args[3..]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "import")) return import(init.gpa, io, args[2]);
    if (args.len == 4 or args.len == 8) if (std.mem.eql(u8, args[1], "heightmap")) return compileHeightmap(init.gpa, io, args[2], args[3], args[4..]);
    std.log.err("usage: asset-compiler compile <source> <meta> <output> | manifest <output> (<meta> <name> <output-name>)... | import <dir> | heightmap <source.pgm> <output.hwmh> [world-width world-depth elevation base-height]", .{});
    return error.InvalidArguments;
}

fn readFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
}

fn compileHeightmap(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, output_path: []const u8, settings_args: []const []const u8) !void {
    var settings: Heightmap.Settings = .{};
    if (settings_args.len != 0) {
        settings.world_width = std.fmt.parseFloat(f32, settings_args[0]) catch return error.InvalidSettings;
        settings.world_depth = std.fmt.parseFloat(f32, settings_args[1]) catch return error.InvalidSettings;
        settings.elevation = std.fmt.parseFloat(f32, settings_args[2]) catch return error.InvalidSettings;
        settings.base_height = std.fmt.parseFloat(f32, settings_args[3]) catch return error.InvalidSettings;
    }
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const heightmap = try Heightmap.importPgm(gpa, source, settings);
    defer heightmap.deinit(gpa);
    const output = try heightmap.encode(gpa);
    defer gpa.free(output);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = output });
    std.log.info("heightmap: {d}x{d}, {d:.1}x{d:.1} m, elevations {d:.1}..{d:.1} m -> {s}", .{
        heightmap.width,
        heightmap.height,
        settings.world_width,
        settings.world_depth,
        settings.base_height,
        settings.base_height + settings.elevation,
        output_path,
    });
}

fn compile(gpa: std.mem.Allocator, io: std.Io, source_path: []const u8, meta_path: []const u8, output: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const source = try readFile(gpa, io, source_path);
    defer gpa.free(source);
    const meta_bytes = readFile(gpa, io, meta_path) catch |err| {
        std.log.err("{s}: missing sidecar {s} ({s}); run `zig build import`", .{ source_path, meta_path, @errorName(err) });
        return error.MissingMeta;
    };
    defer gpa.free(meta_bytes);
    const meta = Meta.check(gpa, meta_bytes, source_path, source) catch |err| {
        std.log.err("{s}: {s}{s}", .{ meta_path, @errorName(err), if (err == error.StaleMeta or err == error.OldImporter) "; run `zig build import`" else "" });
        return err;
    };
    switch (meta.kind) {
        .blueprint => {
            _ = Blueprint.parse(gpa, source) catch |err| {
                std.log.err("{s}: {s}", .{ source_path, @errorName(err) });
                return err;
            };
            return cwd.writeFile(io, .{ .sub_path = output, .data = source });
        },
        .model => {
            var context: Context = .{ .io = io, .dir = std.fs.path.dirname(source_path) orelse "." };
            var model = Gltf.compile(gpa, source, .{ .context = &context, .load = Context.load }) catch |err| {
                std.log.err("{s}: {s}", .{ source_path, @errorName(err) });
                return err;
            };
            defer model.deinit(gpa);
            if (meta.model.scale != 1) {
                for (model.mesh.vertices) |*v| for (&v.position) |*c| {
                    c.* *= meta.model.scale;
                };
                model.computeBounds();
            }
            const bytes = try model.encode(gpa);
            defer gpa.free(bytes);
            try cwd.writeFile(io, .{ .sub_path = output, .data = bytes });
        },
        .heightmap => {
            const heightmap = try Heightmap.importPgm(gpa, source, meta.heightmap);
            defer heightmap.deinit(gpa);
            const bytes = try heightmap.encode(gpa);
            defer gpa.free(bytes);
            try cwd.writeFile(io, .{ .sub_path = output, .data = bytes });
        },
        else => return error.UnsupportedKind,
    }
}

fn manifest(gpa: std.mem.Allocator, io: std.Io, output: []const u8, triples: []const []const u8) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const entries = try arena.alloc(Registry.ManifestEntry, triples.len / 3);
    for (entries, 0..) |*e, i| {
        const bytes = try readFile(arena, io, triples[i * 3]);
        const doc = std.json.parseFromSliceLeaky(Meta.Doc, arena, bytes, .{}) catch return error.InvalidMeta;
        e.* = .{ .guid = doc.guid, .kind = doc.kind, .name = triples[i * 3 + 1], .output = triples[i * 3 + 2], .source = triples[i * 3] };
        if (std.mem.endsWith(u8, e.source, ".meta")) e.source = e.source[0 .. e.source.len - 5];
        for (entries[0..i]) |other| if (other.guid.eql(e.guid)) {
            std.log.err("{s}: GUID {s} is already used by {s}", .{ triples[i * 3], &e.guid.format(), other.name });
            return error.DuplicateGuid;
        };
    }
    const json = try std.json.Stringify.valueAlloc(arena, Registry.Manifest{ .format = Registry.manifest_format, .assets = entries }, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output, .data = json });
}

fn import(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    var created: usize = 0;
    var refreshed: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        _ = Meta.kindOf(entry.basename) catch continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, gpa, .limited(64 << 20));
        defer gpa.free(source);
        const meta_name = try std.fmt.allocPrint(gpa, "{s}.meta", .{entry.basename});
        defer gpa.free(meta_name);
        const existing = entry.dir.readFileAlloc(io, meta_name, gpa, .limited(1 << 20)) catch null;
        defer if (existing) |e| gpa.free(e);
        const updated = try Meta.refresh(gpa, existing, entry.basename, source, Guid.generate(io));
        defer gpa.free(updated);
        if (existing) |e| if (std.mem.eql(u8, e, updated)) continue;
        try entry.dir.writeFile(io, .{ .sub_path = meta_name, .data = updated });
        if (existing == null) created += 1 else refreshed += 1;
        std.log.info("{s}.meta {s}", .{ entry.path, if (existing == null) "created" else "refreshed" });
    }
    std.log.info("import: {d} sidecars created, {d} refreshed", .{ created, refreshed });
}

const Context = struct {
    io: std.Io,
    dir: []const u8,

    fn load(opaque_context: ?*anyopaque, allocator: std.mem.Allocator, uri: []const u8) anyerror![]u8 {
        const self: *Context = @ptrCast(@alignCast(opaque_context.?));
        const path = try std.fs.path.join(allocator, &.{ self.dir, uri });
        defer allocator.free(path);
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(256 << 20));
    }
};
