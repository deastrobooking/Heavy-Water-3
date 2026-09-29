const std = @import("std");
const Gltf = @import("asset/Gltf.zig");
const Model = @import("asset/Model.zig");
const Blueprint = @import("machine/Blueprint.zig");

/// Build-time tool:
///   asset-compiler <source.gltf|.glb> <output.hwmesh>   compile a model (external buffers
///                                                          resolve relative to the source)
///   asset-compiler <blueprint.json> <output.json>       validate a machine blueprint; the
///                                                          output is the unchanged source
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        std.log.err("usage: asset-compiler <source.gltf|.glb|blueprint.json> <output>", .{});
        return error.InvalidArguments;
    }
    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    const source = try cwd.readFileAlloc(io, args[1], init.gpa, .limited(64 << 20));
    defer init.gpa.free(source);
    if (std.mem.endsWith(u8, args[1], ".json")) {
        _ = Blueprint.parse(init.gpa, source) catch |err| {
            std.log.err("{s}: {s}", .{ args[1], @errorName(err) });
            return err;
        };
        return cwd.writeFile(io, .{ .sub_path = args[2], .data = source });
    }
    var context: Context = .{ .io = io, .dir = std.fs.path.dirname(args[1]) orelse "." };
    const model = Gltf.compile(init.gpa, source, .{ .context = &context, .load = Context.load }) catch |err| {
        std.log.err("{s}: {s}", .{ args[1], @errorName(err) });
        return err;
    };
    defer model.deinit(init.gpa);
    const bytes = try model.encode(init.gpa);
    defer init.gpa.free(bytes);
    try cwd.writeFile(io, .{ .sub_path = args[2], .data = bytes });
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
