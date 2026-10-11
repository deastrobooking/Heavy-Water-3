const std = @import("std");
const mach = @import("../main.zig");
const Core = @import("../Core.zig");
const X11 = @import("linux/X11.zig");
const Wayland = @import("linux/Wayland.zig");
const gpu = mach.gpu;
const InitOptions = Core.InitOptions;
const Event = Core.Event;
const KeyEvent = Core.Event.Key;
const MouseButtonEvent = Core.Event.MouseButton;
const MouseButton = Core.MouseButtonID;
const Size = Core.Size;
const DisplayMode = Core.DisplayMode;
const CursorShape = Core.CursorShape;
const VSyncMode = Core.VSyncMode;
const Position = Core.Position;
const Key = Core.KeyButtonID;
const KeyMods = Core.KeyMods;

const log = std.log.scoped(.mach);

const BackendEnum = enum {
    x11,
    wayland,
};

const Backend = union(BackendEnum) {
    x11: X11,
    wayland: Wayland,
};

pub const Native = union(BackendEnum) {
    x11: X11.Native,
    wayland: Wayland.Native,
};

pub const Linux = @This();

allocator: std.mem.Allocator,
title: [:0]const u8,

display_mode: DisplayMode,
vsync_mode: VSyncMode,
cursor_visible: bool,
cursor_shape: CursorShape,
border: bool,
headless: bool,
size: Size,
surface_descriptor: gpu.Surface.Descriptor,

backend: Backend,

// these arrays are used as info messages to the user that some features are missing
// please keep these up to date until we can remove them
const MISSING_FEATURES_X11 = [_][]const u8{ "Resizing window", "Changing display mode", "VSync", "Setting window border/cursor" };
const MISSING_FEATURES_WAYLAND = [_][]const u8{ "Changing display mode", "VSync", "Setting window border/cursor" };

// Called by Core when the user calls Core.snapshotStart, Core.events, core.exit
pub fn wakeMainThread(core: *Core) void {
    _ = core;
}

pub fn wakeRenderThread(_: *Core) void {}

pub fn shouldRenderWindow(_: *Core, _: mach.ObjectID) bool {
    return true;
}

pub fn didRenderWindow(_: *Core, _: mach.ObjectID) void {}

pub fn presentSwapChain(_: *Core, _: mach.ObjectID, swap_chain: *gpu.SwapChain, _: std.Io) void {
    swap_chain.present();
}

pub fn run(comptime on_each_update_fn: anytype, args_tuple: std.meta.ArgsTuple(@TypeOf(on_each_update_fn))) void {
    while (@call(.auto, on_each_update_fn, args_tuple) catch false) {}
}

pub fn tick(core: *Core, core_mod: mach.Mod(Core), io: std.Io) !void {
    {
        core.windows.lock();
        defer core.windows.unlock();

        // Window management: create new windows, handle property changes, pump display server events.
        var windows = core.windows.slice();
        while (windows.next()) |window_id| {
            const native_opt: ?Native = core.windows.get(window_id, .native);
            if (native_opt) |native| {
                const core_window = core.windows.getValue(window_id);

                // Update window title
                if (core.windows.updated(window_id, .title)) {
                    setTitle(&native, core_window.title);
                }

                // Update display mode, decorations
                if (core.windows.updated(window_id, .display_mode) or core.windows.updated(window_id, .decorated)) {
                    setDisplayMode(&native, core_window.display_mode, core_window.decorated);
                    setBorder(&native, core_window.decorated);
                }

                // Check for display server events
                switch (native) {
                    .x11 => try X11.tick(window_id),
                    .wayland => try Wayland.tick(window_id),
                }

                // Renew swap chain
                renewSwapChain(core, window_id);
            } else {
                try initWindow(core, window_id);

                // Consume the initial updated flags so we don't spuriously
                // call setDisplayMode/setBorder on the next tick.
                _ = core.windows.updated(window_id, .display_mode);
                _ = core.windows.updated(window_id, .decorated);
            }
        }
    }

    // Render all windows.
    try core.renderFrame(core_mod, io);
}

inline fn renewSwapChain(core: *Core, window_id: mach.ObjectID) void {
    var core_window = core.windows.getValue(window_id);
    if (core_window.framebuffer_width != core_window.width or
        core_window.framebuffer_height != core_window.height)
    {
        core_window.framebuffer_width = core_window.width;
        core_window.framebuffer_height = core_window.height;
        core_window.swap_chain_descriptor.height = core_window.framebuffer_height;
        core_window.swap_chain_descriptor.width = core_window.framebuffer_width;

        core_window.swap_chain.release();
        core_window.swap_chain = core_window.device.createSwapChain(core_window.surface, &core_window.swap_chain_descriptor);
        core.windows.setValueRaw(window_id, core_window);
    }
}

pub fn initWindow(
    core: *Core,
    window_id: mach.ObjectID,
) !void {
    const force_backend: ?BackendEnum = blk: {
        // TODO(env): upgrade to https://codeberg.org/ziglang/zig/pulls/30644 by properly passing
        // env around
        const backend_ptr = std.c.getenv("MACH_FORCE_BACKEND") orelse break :blk null;
        const backend = std.mem.sliceTo(backend_ptr, 0);

        if (std.ascii.eqlIgnoreCase(backend, "x11")) break :blk .x11;
        if (std.ascii.eqlIgnoreCase(backend, "wayland")) break :blk .wayland;
        std.debug.panic("mach: unknown MACH_FORCE_BACKEND: {s}", .{backend});
    };

    const desired_backend: BackendEnum = force_backend orelse .wayland;

    if (force_backend) |forced| {
        // MACH_FORCE_BACKEND: no fallback, fail hard if the forced backend can't init
        switch (forced) {
            .x11 => {
                X11.initWindow(core, window_id) catch |err| {
                    log.err("MACH_FORCE_BACKEND=x11: failed to initialize X11: {}", .{err});
                    return err;
                };
            },
            .wayland => {
                Wayland.initWindow(core, window_id) catch |err| {
                    log.err("MACH_FORCE_BACKEND=wayland: failed to initialize Wayland: {}", .{err});
                    return err;
                };
            },
        }
    } else {
        // Default: try Wayland first, fall back to X11
        Wayland.initWindow(core, window_id) catch |err| {
            const err_msg = switch (err) {
                error.NoDecorationSupport => "No window decoration support available",
                error.LibraryNotFound => "Missing Wayland library",
                error.FailedToConnectToDisplay => "Failed to connect to Wayland display",
                else => "An unknown error occured while trying to connect to Wayland",
            };

            log.err("{s}\n\nFalling back to X11\n", .{err_msg});
            X11.initWindow(core, window_id) catch |e| {
                log.err("Failed to connect to fallback display server, X11.\n", .{});
                var libs: std.ArrayList(u8) = .empty;
                defer libs.deinit(core.allocator);
                if (Wayland.libwaylandclient == null) {
                    try libs.appendSlice(core.allocator, "\t* libwayland-client\n");
                }
                if (Wayland.libxkbcommon == null) {
                    try libs.appendSlice(core.allocator, "\t* libxkbcommon\n");
                }
                log.err("The following Wayland libraries were not available:\n{s}", .{libs.items});
                return e;
            };
        };
    }

    // warn about incomplete features
    // TODO: remove this when linux is not missing major features
    try warnAboutIncompleteFeatures(desired_backend, &MISSING_FEATURES_X11, &MISSING_FEATURES_WAYLAND, core.allocator);
}

pub fn update(linux: *Linux) !void {
    switch (linux.backend) {
        .wayland => try linux.backend.wayland.update(linux),
        .x11 => try linux.backend.x11.update(linux),
    }
}

fn setTitle(native: *const Native, title: [:0]const u8) void {
    switch (native.*) {
        .wayland => |wl| Wayland.setTitle(&wl, title),
        .x11 => |x| X11.setTitle(&x, title),
    }
}

fn setDisplayMode(native: *const Native, display_mode: DisplayMode, decorated: bool) void {
    switch (native.*) {
        .wayland => Wayland.setDisplayMode(&native.wayland, display_mode),
        .x11 => X11.setDisplayMode(&native.x11, display_mode, decorated),
    }
}

fn setBorder(_: *const Native, _: bool) void {
    return;
}

pub fn setHeadless(_: *Linux, _: bool) void {
    return;
}

pub fn setVSync(_: *Linux, _: VSyncMode) void {
    return;
}

pub fn setSize(_: *Linux, _: Size) void {
    return;
}

pub fn setCursorVisible(_: *Linux, _: bool) void {
    return;
}

pub fn setCursorShape(_: *Linux, _: CursorShape) void {
    return;
}

/// Used to inform users that some features are not present. Remove when features are complete.
fn warnAboutIncompleteFeatures(backend: BackendEnum, missing_features_x11: []const []const u8, missing_features_wayland: []const []const u8, alloc: std.mem.Allocator) !void {
    const features_incomplete_message =
        \\You are using the {s} backend, which is currently experimental as we continue to rewrite Mach in Zig instead of using C libraries like GLFW/etc. The following features are expected to not work:
        \\
        \\{s}
        \\
        \\Contributions welcome!
        \\
    ;
    var bullet_points = switch (backend) {
        .x11 => try generateFeatureBulletPoints(missing_features_x11, alloc),
        .wayland => try generateFeatureBulletPoints(missing_features_wayland, alloc),
    };
    defer bullet_points.deinit(alloc);
    log.warn(features_incomplete_message, .{ @tagName(backend), bullet_points.items });
}

/// Turn an array of strings into a single, bullet-pointed string, like this:
/// * Item one
/// * Item two
///
/// Returned value will need to be deinitialized.
fn generateFeatureBulletPoints(features: []const []const u8, alloc: std.mem.Allocator) !std.ArrayList(u8) {
    var message: std.ArrayList(u8) = .empty;
    for (features, 0..) |str, i| {
        try message.appendSlice(alloc, "* ");
        try message.appendSlice(alloc, str);
        if (i < features.len - 1) {
            try message.appendSlice(alloc, "\n");
        }
    }
    return message;
}
