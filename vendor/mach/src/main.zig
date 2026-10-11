//! The Mach standard library

const build_options = @import("build-options");
const builtin = @import("builtin");
const std = @import("std");

const log = std.log.scoped(.mach);

pub const is_debug = builtin.mode == .Debug;

// Core
pub const Core = if (build_options.want_core) @import("Core.zig") else struct {};

pub const gfx = if (build_options.want_mach) @import("gfx/main.zig") else struct {};
pub const Audio = if (build_options.want_sysaudio) @import("Audio.zig") else struct {};
pub const math = @import("math/main.zig");
pub const testing = @import("testing.zig");
pub const time = @import("time/main.zig");

pub const sysaudio = if (build_options.want_sysaudio) @import("sysaudio/main.zig") else struct {};
pub const sysgpu = if (build_options.want_sysgpu) @import("sysgpu/main.zig") else struct {};
pub const gpu = if (build_options.want_sysgpu) @import("sysgpu/main.zig").sysgpu else struct {};

const module = @import("module.zig");
pub const FunctionID = module.FunctionID;
pub const Graph = @import("graph.zig").Graph;
pub const Mod = module.Mod;
pub const ModuleID = module.ModuleID;
pub const Modules = module.Modules;
pub const ModuleFunctionID = module.ModuleFunctionID;
pub const ObjectID = module.ObjectID;
pub const Objects = module.Objects;
pub const Thread = module.Thread;
pub const initGraph = module.initGraph;
pub const schedule = module.schedule;
pub const startThread = module.startThread;

/// All Mach modules
pub const modules =
    (if (build_options.want_core) .{Core} else .{}) ++
    (if (build_options.want_sysaudio) .{Audio} else .{}) ++
    (if (build_options.want_mach) gfx.modules else .{});

// Instrumented function to load system libraries and print nicer error
// messages. Accepts a tuple of library names to try in order (e.g.,
// versioned soname first, then unversioned fallback).
pub inline fn dynLibOpen(comptime lib_names: anytype) !std.DynLib {
    inline for (lib_names) |name| {
        if (std.DynLib.open(name)) |lib| return lib else |_| {}
    }
    log.err("missing system library, tried:", .{});
    inline for (lib_names) |name| {
        log.err("  * {s}", .{name});
    }
    return error.LibraryNotFound;
}

test {
    // TODO: refactor code so we can use this here:
    // std.testing.refAllDecls(@This());
    _ = Modules;
    _ = Core;
    _ = gpu;
    _ = sysaudio;
    _ = sysgpu;
    _ = gfx;
    _ = Audio;
    _ = math;
    _ = testing;
    _ = time;
    _ = @import("mpsc.zig");
    _ = @import("graph.zig");

    std.testing.refAllDecls(math);
}
