const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var io_threaded = std.Io.Threaded.init(allocator, .{});
    const io = io_threaded.io();

    // The set of Mach modules our application may use.
    var mods: @import("app").Modules = .{};
    try mods.init(allocator, io);
    // TODO: enable mods.deinit(allocator); for allocator leak detection
    // defer mods.deinit(allocator);

    const app = mods.get(.app);
    app.call(.main);
}
