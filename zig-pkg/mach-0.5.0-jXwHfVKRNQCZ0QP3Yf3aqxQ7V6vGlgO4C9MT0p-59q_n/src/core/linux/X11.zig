const Linux = @import("../Linux.zig");
const Core = @import("../../Core.zig");
const InitOptions = Core.InitOptions;

const builtin = @import("builtin");
const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/cursorfont.h");
    @cInclude("X11/Xcursor/Xcursor.h");
    @cInclude("X11/extensions/Xrandr.h");
    @cInclude("xkbcommon/xkbcommon.h");
});
const mach = @import("../../main.zig");
const gpu = mach.gpu;
const Event = Core.Event;
const KeyEvent = Core.Event.Key;
const MouseButtonEvent = Core.Event.MouseButton;
const MouseButton = Core.MouseButtonID;
const DisplayMode = Core.DisplayMode;
const CursorShape = Core.CursorShape;
const VSyncMode = Core.VSyncMode;
const Key = Core.KeyButtonID;
const KeyMods = Core.KeyMods;
const Joystick = Core.Joystick;
const Position = Core.Position;
const log = std.log.scoped(.mach);
pub const defaultLog = std.log.defaultLog;
pub const defaultPanic = std.debug.panicImpl;

// TODO: determine if it's really needed to store global pointer
var core_ptr: *Core = undefined;

pub var libx11: ?LibX11 = null;
pub var libxkbcommon: ?LibXkbCommon = null;
pub var libgl: ?LibGL = null;

pub const Native = struct {
    backend_type: gpu.BackendType,
    cursors: [@typeInfo(CursorShape).@"enum".fields.len]?c.Cursor,
    display: *c.Display,
    empty_event_pipe: [2]std.c.fd_t,
    gl_ctx: ?*LibGL.Context,
    hidden_cursor: c.Cursor,
    libxcursor: ?LibXCursor,
    motif_wm_hints: c.Atom,
    net_wm_bypass_compositor: c.Atom,
    net_wm_ping: c.Atom,
    net_wm_window_type: c.Atom,
    net_wm_window_type_dock: c.Atom,
    refresh_rate: u32,
    root_window: c.Window,
    surface_descriptor: gpu.Surface.DescriptorFromXlibWindow,
    window: c.Window,
    wm_delete_window: c.Atom,
    wm_protocols: c.Atom,
};

// Mutable fields only used by main thread

// Mutable state fields; read/write by any thread

pub fn initWindow(
    core: *Core,
    window_id: mach.ObjectID,
) !void {
    core_ptr = core;
    var core_window = core.windows.getValue(window_id);
    // TODO(core): return errors.NotSupported if not supported
    // Try to load both libs so either or both missing libs can be communicated, if necessary
    libx11 = LibX11.load() catch |err| switch (err) {
        error.LibraryNotFound => null,
        else => return err,
    };
    libxkbcommon = LibXkbCommon.load() catch |err| switch (err) {
        error.LibraryNotFound => null,
        else => return err,
    };
    libgl = LibGL.load() catch |err| switch (err) {
        error.LibraryNotFound => null,
        else => return err,
    };
    if (libx11 == null or libxkbcommon == null or libgl == null) return error.LibraryNotFound;

    // Note: X11 (at least, older versions of it definitely) have a race condition with frame submission
    // when the Vulkan presentation mode != .none; XInitThreads() resolves this. We use XInitThreads
    // /solely/ to ensure we can use .double and .triple presentation modes, we do not use it for
    // anything else and otherwise treat all X11 API calls as if they are not thread-safe as with all
    // other native GUI APIs.
    _ = libx11.?.XInitThreads();

    const libxcursor = LibXCursor.load() catch |err| switch (err) {
        error.LibraryNotFound => null,
        else => return err,
    };
    const libxrr = LibXRR.load() catch |err| switch (err) {
        error.LibraryNotFound => null,
        else => return err,
    };
    const display = libx11.?.XOpenDisplay(null) orelse {
        return error.FailedToConnectToDisplay;
    };
    const screen = c.DefaultScreen(display);
    const visual = c.DefaultVisual(display, screen);
    const root_window = c.RootWindow(display, screen);

    const colormap = libx11.?.XCreateColormap(display, root_window, visual, c.AllocNone);
    defer _ = libx11.?.XFreeColormap(display, colormap);

    var set_window_attrs = c.XSetWindowAttributes{
        .colormap = colormap,
        // TODO: reduce
        .event_mask = c.StructureNotifyMask | c.KeyPressMask | c.KeyReleaseMask |
            c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask |
            c.ExposureMask | c.FocusChangeMask | c.VisibilityChangeMask |
            c.EnterWindowMask | c.LeaveWindowMask | c.PropertyChangeMask,
    };

    // TODO: read error after function call and handle
    const x_window_id = libx11.?.XCreateWindow(
        display,
        root_window,
        @divFloor(libx11.?.XDisplayWidth(display, screen), 2), // TODO: add window width?
        @divFloor(libx11.?.XDisplayHeight(display, screen), 2), // TODO: add window height?
        core_window.width,
        core_window.height,
        0,
        c.DefaultDepth(display, screen),
        c.InputOutput,
        visual,
        c.CWColormap | c.CWEventMask,
        &set_window_attrs,
    );

    const blank_pixmap = libx11.?.XCreatePixmap(display, x_window_id, 1, 1, 1);
    var color = c.XColor{};

    // Query the display's current refresh rate for future frame-pacing / vsync work.
    const refresh_rate: u32 = blk: {
        if (libxrr) |_libxrr| {
            const conf = _libxrr.XRRGetScreenInfo(display, root_window);
            break :blk @intCast(_libxrr.XRRConfigCurrentRate(conf));
        }
        break :blk 60;
    };

    const surface_descriptor = gpu.Surface.DescriptorFromXlibWindow{ .display = display, .window = @intCast(x_window_id) };
    core_window.surface_descriptor = .{ .next_in_chain = .{
        .from_xlib_window = &surface_descriptor,
    } };

    core_window.native = .{ .x11 = .{
        .backend_type = try Core.detectBackendType(core.allocator),
        .cursors = std.mem.zeroes([@typeInfo(CursorShape).@"enum".fields.len]?c.Cursor),
        .display = display,
        .empty_event_pipe = try std.Io.Threaded.pipe2(.{ .NONBLOCK = true, .CLOEXEC = true }),
        .gl_ctx = null,
        .hidden_cursor = libx11.?.XCreatePixmapCursor(display, blank_pixmap, blank_pixmap, &color, &color, 0, 0),
        .libxcursor = libxcursor,
        .motif_wm_hints = libx11.?.XInternAtom(display, "_MOTIF_WM_HINTS", c.False),
        .net_wm_bypass_compositor = libx11.?.XInternAtom(display, "_NET_WM_BYPASS_COMPOSITOR", c.False),
        .net_wm_ping = libx11.?.XInternAtom(display, "NET_WM_PING", c.False),
        .net_wm_window_type = libx11.?.XInternAtom(display, "_NET_WM_WINDOW_TYPE", c.False),
        .net_wm_window_type_dock = libx11.?.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", c.False),
        .refresh_rate = refresh_rate,
        .root_window = root_window,
        .surface_descriptor = surface_descriptor,
        .window = x_window_id,
        .wm_delete_window = libx11.?.XInternAtom(display, "WM_DELETE_WINDOW", c.False),
        .wm_protocols = libx11.?.XInternAtom(display, "WM_PROTOCOLS", c.False),
    } };
    var x11 = &core_window.native.?.x11;

    // NONBLOCK and CLOEXEC already set via pipe2 flags above.
    var protocols = [_]c.Atom{ x11.wm_delete_window, x11.net_wm_ping };
    _ = libx11.?.XSetWMProtocols(x11.display, x11.window, &protocols, protocols.len);
    _ = libx11.?.XStoreName(x11.display, x11.window, core_window.title);
    _ = libx11.?.XSelectInput(x11.display, x11.window, set_window_attrs.event_mask);
    _ = libx11.?.XMapWindow(x11.display, x11.window);

    // TODO: see if this can be removed
    const backend_type = try Core.detectBackendType(core.allocator);
    switch (backend_type) {
        .opengl, .opengles => {
            // zig fmt: off
            const attrs = &[_]c_int{
                LibGL.rgba,
                LibGL.doublebuffer,
                LibGL.depth_size,     24,
                LibGL.stencil_size,   8,
                LibGL.red_size,       8,
                LibGL.green_size,     8,
                LibGL.blue_size,      8,
                LibGL.sample_buffers, 0,
                LibGL.samples,        0,
                c.None,
            };
            // zig fmt: on
            const visual_info = libgl.?.glXChooseVisual(x11.display, screen, attrs.ptr);
            defer _ = libx11.?.XFree(visual_info);
            x11.gl_ctx = libgl.?.glXCreateContext(x11.display, visual_info, null, true);
            _ = libgl.?.glXMakeCurrent(x11.display, x11.window, x11.gl_ctx);
        },
        else => {},
    }

    // Create hidden cursor
    const gc = libx11.?.XCreateGC(x11.display, blank_pixmap, 0, null);
    if (gc != null) {
        _ = libx11.?.XDrawPoint(x11.display, blank_pixmap, gc, 0, 0);
        _ = libx11.?.XFreeGC(x11.display, gc);
    }
    x11.cursors[@intFromEnum(CursorShape.arrow)] = try createStandardCursor(x11, .arrow);

    core.windows.setValue(window_id, core_window);
    try core.initWindow(window_id);
}

// Called on the main thread
pub fn tick(window_id: mach.ObjectID) !void {
    var core_window = core_ptr.windows.getValue(window_id);
    var x11 = &core_window.native.?.x11;
    while (c.QLength(x11.display) != 0) {
        var event: c.XEvent = undefined;
        _ = libx11.?.XNextEvent(x11.display, &event);
        processEvent(window_id, &event);
        // update in case core_window was changed
        core_window = core_ptr.windows.getValue(window_id);
        x11 = &core_window.native.?.x11;
    }

    _ = libx11.?.XFlush(x11.display);

    // const frequency_delay = @as(f32, @floatFromInt(x11.input.delay_ns)) / @as(f32, @floatFromInt(std.time.ns_per_s));
    // TODO: glfw.waitEventsTimeout(frequency_delay);
}

pub fn setTitle(x11: *const Native, title: [:0]const u8) void {
    _ = libx11.?.XStoreName(x11.display, x11.window, title);
}

pub fn setDisplayMode(x11: *const Native, display_mode: DisplayMode, border: bool) void {
    const wm_state = libx11.?.XInternAtom(x11.display, "_NET_WM_STATE", c.False);
    switch (display_mode) {
        .windowed => {
            // Clear _NET_WM_STATE (remove fullscreen/above states)
            _ = libx11.?.XChangeProperty(
                x11.display,
                x11.window,
                wm_state,
                c.XA_ATOM,
                32,
                c.PropModeReplace,
                null,
                0,
            );
            setFullscreen(x11, false);
            setDecorated(x11, border);
            setFloating(x11, false);
            _ = libx11.?.XMapWindow(x11.display, x11.window);
            _ = libx11.?.XFlush(x11.display);
        },
        .fullscreen => {
            setFullscreen(x11, true);
            _ = libx11.?.XFlush(x11.display);
        },
        .fullscreen_borderless => {
            setDecorated(x11, false);
            setFloating(x11, true);
            setFullscreen(x11, false);
            _ = libx11.?.XResizeWindow(
                x11.display,
                x11.window,
                @intCast(c.DisplayWidth(x11.display, c.DefaultScreen(x11.display))),
                @intCast(c.DisplayHeight(x11.display, c.DefaultScreen(x11.display))),
            );
            _ = libx11.?.XFlush(x11.display);
        },
    }
}

fn setFullscreen(x11: *const Native, enabled: bool) void {
    const wm_state = libx11.?.XInternAtom(x11.display, "_NET_WM_STATE", c.False);
    const wm_fullscreen = libx11.?.XInternAtom(x11.display, "_NET_WM_STATE_FULLSCREEN", c.False);
    sendEventToWM(x11, wm_state, &.{ @intFromBool(enabled), @intCast(wm_fullscreen), 0, 1 });
    // Force composition OFF to reduce overhead
    const compositing_disable_on: c_long = @intFromBool(enabled);
    const bypass_compositor = libx11.?.XInternAtom(x11.display, "_NET_WM_BYPASS_COMPOSITOR", c.False);
    if (bypass_compositor != c.None) {
        _ = libx11.?.XChangeProperty(
            x11.display,
            x11.window,
            bypass_compositor,
            c.XA_CARDINAL,
            32,
            c.PropModeReplace,
            @ptrCast(&compositing_disable_on),
            1,
        );
    }
}

fn setFloating(x11: *const Native, enabled: bool) void {
    const wm_state = libx11.?.XInternAtom(x11.display, "_NET_WM_STATE", c.False);
    const wm_above = libx11.?.XInternAtom(x11.display, "_NET_WM_STATE_ABOVE", c.False);
    const net_wm_state_remove = 0;
    const net_wm_state_add = 1;
    const action: c_long = if (enabled) net_wm_state_add else net_wm_state_remove;
    sendEventToWM(x11, wm_state, &.{ action, @intCast(wm_above), 0, 1 });
}

fn sendEventToWM(x11: *const Native, message_type: c.Atom, data: []const c_long) void {
    var ev = std.mem.zeroes(c.XEvent);
    ev.type = c.ClientMessage;
    ev.xclient.window = x11.window;
    ev.xclient.message_type = message_type;
    ev.xclient.format = 32;
    @memcpy(ev.xclient.data.l[0..data.len], data);
    _ = libx11.?.XSendEvent(
        x11.display,
        x11.root_window,
        c.False,
        c.SubstructureNotifyMask | c.SubstructureRedirectMask,
        &ev,
    );
    _ = libx11.?.XFlush(x11.display);
}

fn setDecorated(x11: *const Native, enabled: bool) void {
    const MWMHints = struct {
        flags: u32,
        functions: u32,
        decorations: u32,
        input_mode: i32,
        status: u32,
    };
    const hints = MWMHints{
        .functions = 0,
        .flags = 2,
        .decorations = if (enabled) 1 else 0,
        .input_mode = 0,
        .status = 0,
    };
    _ = libx11.?.XChangeProperty(
        x11.display,
        x11.window,
        x11.motif_wm_hints,
        x11.motif_wm_hints,
        32,
        c.PropModeReplace,
        @ptrCast(&hints),
        5,
    );
}

pub const LibX11 = struct {
    handle: std.DynLib,
    XInitThreads: *const fn () callconv(.c) c_int,
    XrmInitialize: *const fn () callconv(.c) void,
    XOpenDisplay: *const fn ([*c]const u8) callconv(.c) ?*c.Display,
    XCloseDisplay: *const fn (?*c.Display) callconv(.c) c_int,
    XCreateWindow: *const fn (?*c.Display, c.Window, c_int, c_int, c_uint, c_uint, c_uint, c_int, c_uint, [*c]c.Visual, c_ulong, [*c]c.XSetWindowAttributes) callconv(.c) c.Window,
    XSelectInput: *const fn (?*c.Display, c.Window, c_long) callconv(.c) c_int,
    XMapWindow: *const fn (?*c.Display, c.Window) callconv(.c) c_int,
    XNextEvent: *const fn (?*c.Display, [*c]c.XEvent) callconv(.c) c_int,
    XDisplayWidth: *const fn (?*c.Display, c_int) callconv(.c) c_int,
    XDisplayHeight: *const fn (?*c.Display, c_int) callconv(.c) c_int,
    XCreateColormap: *const fn (?*c.Display, c.Window, [*c]c.Visual, c_int) callconv(.c) c.Colormap,
    XSetErrorHandler: *const fn (c.XErrorHandler) callconv(.c) c.XErrorHandler,
    XGetWindowAttributes: *const fn (?*c.Display, c.Window, [*c]c.XWindowAttributes) callconv(.c) c_int,
    XStoreName: *const fn (?*c.Display, c.Window, [*c]const u8) callconv(.c) c_int,
    XFreeColormap: *const fn (?*c.Display, c.Colormap) callconv(.c) c_int,
    XUnmapWindow: *const fn (?*c.Display, c.Window) callconv(.c) c_int,
    XDestroyWindow: *const fn (?*c.Display, c.Window) callconv(.c) c_int,
    XFlush: *const fn (?*c.Display) callconv(.c) c_int,
    XLookupString: *const fn ([*c]c.XKeyEvent, [*c]u8, c_int, [*c]c.KeySym, [*c]c.XComposeStatus) callconv(.c) c_int,
    XQueryPointer: *const fn (?*c.Display, c.Window, [*c]c.Window, [*c]c.Window, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_int, [*c]c_uint) callconv(.c) c_int,
    XInternAtom: *const fn (?*c.Display, [*c]const u8, c_int) callconv(.c) c.Atom,
    XSendEvent: *const fn (?*c.Display, c.Window, c_int, c_long, [*c]c.XEvent) callconv(.c) c_int,
    XSetWMProtocols: *const fn (?*c.Display, c.Window, [*c]c.Atom, c_int) callconv(.c) c_int,
    XDefineCursor: *const fn (?*c.Display, c.Window, c.Cursor) callconv(.c) c_int,
    XUndefineCursor: *const fn (?*c.Display, c.Window) callconv(.c) c_int,
    XCreatePixmap: *const fn (?*c.Display, c.Drawable, c_uint, c_uint, c_uint) callconv(.c) c.Pixmap,
    XCreateGC: *const fn (?*c.Display, c.Drawable, c_ulong, [*c]c.XGCValues) callconv(.c) c.GC,
    XDrawPoint: *const fn (?*c.Display, c.Drawable, c.GC, c_int, c_int) callconv(.c) c_int,
    XFreeGC: *const fn (?*c.Display, c.GC) callconv(.c) c_int,
    XCreatePixmapCursor: *const fn (?*c.Display, c.Pixmap, c.Pixmap, [*c]c.XColor, [*c]c.XColor, c_uint, c_uint) callconv(.c) c.Cursor,
    XGrabPointer: *const fn (?*c.Display, c.Window, c_int, c_uint, c_int, c_int, c.Window, c.Cursor, c.Time) callconv(.c) c_int,
    XUngrabPointer: *const fn (?*c.Display, c.Time) callconv(.c) c_int,
    XCreateFontCursor: *const fn (?*c.Display, c_uint) callconv(.c) c.Cursor,
    XFreeCursor: *const fn (?*c.Display, c.Cursor) callconv(.c) c_int,
    XChangeProperty: *const fn (?*c.Display, c.Window, c.Atom, c.Atom, c_int, c_int, [*c]const u8, c_int) callconv(.c) c_int,
    XResizeWindow: *const fn (?*c.Display, c.Window, c_uint, c_uint) callconv(.c) c_int,
    XConfigureWindow: *const fn (?*c.Display, c.Window, c_uint, [*c]c.XWindowChanges) callconv(.c) c_int,
    XSetWMHints: *const fn (?*c.Display, c.Window, [*c]c.XWMHints) callconv(.c) c_int,
    XDeleteProperty: *const fn (?*c.Display, c.Window, c.Atom) callconv(.c) c_int,
    XAllocSizeHints: *const fn () callconv(.c) [*c]c.XSizeHints,
    XSetWMNormalHints: *const fn (?*c.Display, c.Window, [*c]c.XSizeHints) callconv(.c) void,
    XFree: *const fn (?*anyopaque) callconv(.c) c_int,

    pub fn load() !LibX11 {
        var lib: LibX11 = undefined;
        lib.handle = mach.dynLibOpen(.{ "libX11.so.6", "libX11.so" }) catch return error.LibraryNotFound;
        @setEvalBranchQuota(10000);
        inline for (@typeInfo(LibX11).@"struct".fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse return error.SymbolLookup;
        }
        return lib;
    }
};

const LibXCursor = struct {
    handle: std.DynLib,
    XcursorImageCreate: *const fn (c_int, c_int) callconv(.c) [*c]c.XcursorImage,
    XcursorImageDestroy: *const fn ([*c]c.XcursorImage) callconv(.c) void,
    XcursorImageLoadCursor: *const fn (?*c.Display, [*c]const c.XcursorImage) callconv(.c) c.Cursor,
    XcursorGetTheme: *const fn (?*c.Display) callconv(.c) [*c]u8,
    XcursorGetDefaultSize: *const fn (?*c.Display) callconv(.c) c_int,
    XcursorLibraryLoadImage: *const fn ([*c]const u8, [*c]const u8, c_int) callconv(.c) [*c]c.XcursorImage,
    pub fn load() !LibXCursor {
        var lib: LibXCursor = undefined;
        lib.handle = mach.dynLibOpen(.{ "libXcursor.so.1", "libXcursor.so" }) catch return error.LibraryNotFound;
        @setEvalBranchQuota(10000);
        inline for (@typeInfo(LibXCursor).@"struct".fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse return error.SymbolLookup;
        }
        return lib;
    }
};

// LibXRR dynamically loads libXrandr for querying display refresh rates and mode changes.
const LibXRR = struct {
    handle: std.DynLib,
    XRRGetScreenInfo: *const fn (?*c.Display, c.Window) callconv(.c) ?*c.XRRScreenConfiguration,
    XRRConfigCurrentRate: *const fn (?*c.XRRScreenConfiguration) callconv(.c) c_short,
    pub fn load() !LibXRR {
        var lib: LibXRR = undefined;
        lib.handle = mach.dynLibOpen(.{ "libXrandr.so.1", "libXrandr.so" }) catch return error.LibraryNotFound;
        @setEvalBranchQuota(10000);
        inline for (@typeInfo(LibXRR).@"struct".fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse return error.SymbolLookup;
        }
        return lib;
    }
};

pub const LibGL = struct {
    const Drawable = c.XID;
    const Context = opaque {};
    const FBConfig = opaque {};
    const rgba = 4;
    const doublebuffer = 5;
    const red_size = 8;
    const green_size = 9;
    const blue_size = 10;
    const depth_size = 12;
    const stencil_size = 13;
    const sample_buffers = 0x186a0;
    const samples = 0x186a1;
    handle: std.DynLib,
    glXCreateContext: *const fn (*c.Display, *c.XVisualInfo, ?*Context, bool) callconv(.c) ?*Context,
    glXDestroyContext: *const fn (*c.Display, ?*Context) callconv(.c) void,
    glXMakeCurrent: *const fn (*c.Display, Drawable, ?*Context) callconv(.c) bool,
    glXChooseVisual: *const fn (*c.Display, c_int, [*]const c_int) callconv(.c) *c.XVisualInfo,
    glXSwapBuffers: *const fn (*c.Display, Drawable) callconv(.c) bool,

    pub fn load() !LibGL {
        var lib: LibGL = undefined;
        lib.handle = mach.dynLibOpen(.{ "libGL.so.1", "libGL.so" }) catch return error.LibraryNotFound;
        @setEvalBranchQuota(10000);
        inline for (@typeInfo(LibGL).@"struct".fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse return error.SymbolLookup;
        }
        return lib;
    }
};

pub const LibXkbCommon = struct {
    handle: std.DynLib,

    xkb_context_new: *const fn (c.enum_xkb_context_flags) callconv(.c) ?*c.struct_xkb_context,
    xkb_keymap_new_from_string: *const fn (?*c.struct_xkb_context, [*c]const u8, c.enum_xkb_keymap_format, c.enum_xkb_keymap_compile_flags) callconv(.c) ?*c.struct_xkb_keymap,
    xkb_state_new: *const fn (?*c.struct_xkb_keymap) callconv(.c) ?*c.struct_xkb_state,
    xkb_keymap_unref: *const fn (?*c.struct_xkb_keymap) callconv(.c) void,
    xkb_state_unref: *const fn (?*c.struct_xkb_state) callconv(.c) void,
    // xkb_compose_table_new_from_locale: *const fn (?*c.struct_xkb_context, [*c]const u8, c.enum_xkb_compose_compile_flags) callconv(.c) ?*c.struct_xkb_compose_table,
    // xkb_compose_state_new: *const fn (?*c.struct_xkb_compose_table, c.enum_xkb_compose_state_flags) callconv(.c) ?*c.struct_xkb_compose_state,
    // xkb_compose_table_unref: *const fn (?*c.struct_xkb_compose_table) callconv(.c) void,
    xkb_keymap_mod_get_index: *const fn (?*c.struct_xkb_keymap, [*c]const u8) callconv(.c) c.xkb_mod_index_t,
    xkb_state_update_mask: *const fn (?*c.struct_xkb_state, c.xkb_mod_mask_t, c.xkb_mod_mask_t, c.xkb_mod_mask_t, c.xkb_layout_index_t, c.xkb_layout_index_t, c.xkb_layout_index_t) callconv(.c) c.enum_xkb_state_component,
    xkb_state_mod_index_is_active: *const fn (?*c.struct_xkb_state, c.xkb_mod_index_t, c.enum_xkb_state_component) callconv(.c) c_int,
    xkb_state_key_get_syms: *const fn (?*c.struct_xkb_state, c.xkb_keycode_t, [*c][*c]const c.xkb_keysym_t) callconv(.c) c_int,
    // xkb_compose_state_feed: *const fn (?*c.struct_xkb_compose_state, c.xkb_keysym_t) callconv(.c) c.enum_xkb_compose_feed_result,
    // xkb_compose_state_get_status: *const fn (?*c.struct_xkb_compose_state) callconv(.c) c.enum_xkb_compose_status,
    // xkb_compose_state_get_one_sym: *const fn (?*c.struct_xkb_compose_state) callconv(.c) c.xkb_keysym_t,
    xkb_keysym_to_utf32: *const fn (c.xkb_keysym_t) callconv(.c) u32,

    pub fn load() !LibXkbCommon {
        var lib: LibXkbCommon = undefined;
        lib.handle = mach.dynLibOpen(.{ "libxkbcommon.so.0", "libxkbcommon.so" }) catch return error.LibraryNotFound;
        @setEvalBranchQuota(10000);
        inline for (@typeInfo(LibXkbCommon).@"struct".fields[1..]) |field| {
            const name = std.fmt.comptimePrint("{s}\x00", .{field.name});
            const name_z: [:0]const u8 = @ptrCast(name[0 .. name.len - 1]);
            @field(lib, field.name) = lib.handle.lookup(field.type, name_z) orelse {
                log.err("Symbol lookup failed for {s}", .{name});
                return error.SymbolLookup;
            };
        }
        return lib;
    }
};

fn createStandardCursor(x11: *const Native, shape: CursorShape) !c.Cursor {
    if (x11.libxcursor) |libxcursor| {
        const theme = libxcursor.XcursorGetTheme(x11.display);
        if (theme != null) {
            const name = switch (shape) {
                .arrow => "default",
                .ibeam => "text",
                .crosshair => "crosshair",
                .pointing_hand => "pointer",
                .resize_ew => "ew-resize",
                .resize_ns => "ns-resize",
                .resize_nwse => "nwse-resize",
                .resize_nesw => "nesw-resize",
                .resize_all => "all-scroll",
                .not_allowed => "not-allowed",
            };
            const cursor_size = libxcursor.XcursorGetDefaultSize(x11.display);
            const image = libxcursor.XcursorLibraryLoadImage(name, theme, cursor_size);
            defer libxcursor.XcursorImageDestroy(image);
            if (image != null) {
                return libxcursor.XcursorImageLoadCursor(x11.display, image);
            }
        }
    }
    const xc: c_uint = switch (shape) {
        .arrow => c.XC_left_ptr,
        .ibeam => c.XC_xterm,
        .crosshair => c.XC_crosshair,
        .pointing_hand => c.XC_hand2,
        .resize_ew => c.XC_sb_h_double_arrow,
        .resize_ns => c.XC_sb_v_double_arrow,
        .resize_nwse => c.XC_sb_h_double_arrow,
        .resize_nesw => c.XC_sb_h_double_arrow,
        .resize_all => c.XC_fleur,
        .not_allowed => c.XC_X_cursor,
    };
    const cursor = libx11.?.XCreateFontCursor(x11.display, xc);
    if (cursor == 0) return error.FailedToCreateCursor;
    return cursor;
}

fn getCursorPos(x11: *const Native) Position {
    var root_window: c.Window = undefined;
    var child_window: c.Window = undefined;
    var root_cursor_x: c_int = 0;
    var root_cursor_y: c_int = 0;
    var cursor_x: c_int = 0;
    var cursor_y: c_int = 0;
    var mask: c_uint = 0;
    _ = libx11.?.XQueryPointer(
        x11.display,
        x11.window,
        &root_window,
        &child_window,
        &root_cursor_x,
        &root_cursor_y,
        &cursor_x,
        &cursor_y,
        &mask,
    );

    return .{ .x = @floatFromInt(cursor_x), .y = @floatFromInt(cursor_y) };
}

/// Handle XEvents. Window object can be modified.
fn processEvent(window_id: mach.ObjectID, event: *c.XEvent) void {
    var core_window = core_ptr.windows.getValue(window_id);
    const x11 = &core_window.native.?.x11;
    switch (event.type) {
        c.KeyPress, c.KeyRelease => {
            // TODO: key repeat event

            var keysym: c.KeySym = undefined;
            _ = libx11.?.XLookupString(&event.xkey, null, 0, &keysym, null);

            const key_event = KeyEvent{
                .key = toMachKey(keysym),
                .mods = toMachMods(event.xkey.state),
                .window_id = window_id,
            };

            switch (event.type) {
                c.KeyPress => {
                    core_ptr.pushEvent(.{ .key_press = key_event });

                    const codepoint = libxkbcommon.?.xkb_keysym_to_utf32(@truncate(keysym));
                    if (codepoint != 0) {
                        core_ptr.pushEvent(.{ .char_input = .{ .codepoint = @truncate(codepoint), .window_id = window_id } });
                    }
                },
                c.KeyRelease => {
                    core_ptr.pushEvent(.{ .key_release = key_event });
                },
                else => unreachable,
            }
        },
        c.ButtonPress => {
            const button = toMachButton(event.xbutton.button) orelse {
                // Modern X provides scroll events as mouse button presses
                const scroll: struct { f32, f32 } = switch (event.xbutton.button) {
                    c.Button4 => .{ 0.0, 1.0 },
                    c.Button5 => .{ 0.0, -1.0 },
                    6 => .{ 1.0, 0.0 },
                    7 => .{ -1.0, 0.0 },
                    else => unreachable,
                };
                core_ptr.pushEvent(.{ .mouse_scroll = .{ .xoffset = scroll[0], .yoffset = scroll[1], .window_id = window_id } });
                return;
            };
            const cursor_pos = getCursorPos(x11);
            const mouse_button = MouseButtonEvent{
                .button = button,
                .pos = cursor_pos,
                .mods = toMachMods(event.xbutton.state),
                .window_id = window_id,
            };

            core_ptr.pushEvent(.{ .mouse_press = mouse_button });
        },
        c.ButtonRelease => {
            const button = toMachButton(event.xbutton.button) orelse return;
            const cursor_pos = getCursorPos(x11);
            const mouse_button = MouseButtonEvent{
                .button = button,
                .pos = cursor_pos,
                .mods = toMachMods(event.xbutton.state),
                .window_id = window_id,
            };

            core_ptr.pushEvent(.{ .mouse_release = mouse_button });
        },
        c.ClientMessage => {
            if (event.xclient.message_type == c.None) return;

            if (event.xclient.message_type == x11.wm_protocols) {
                const protocol = event.xclient.data.l[0];
                if (protocol == c.None) return;

                if (protocol == x11.wm_delete_window) {
                    core_ptr.pushEvent(.{ .close = .{ .window_id = window_id } });
                } else if (protocol == x11.net_wm_ping) {
                    // The window manager is pinging the application to ensure
                    // it's still responding to events
                    var reply = event.*;
                    reply.xclient.window = x11.root_window;
                    _ = libx11.?.XSendEvent(
                        x11.display,
                        x11.root_window,
                        c.False,
                        c.SubstructureNotifyMask | c.SubstructureRedirectMask,
                        &reply,
                    );
                }
            }
        },
        c.EnterNotify => {
            const x: f32 = @floatFromInt(event.xcrossing.x);
            const y: f32 = @floatFromInt(event.xcrossing.y);
            core_ptr.pushEvent(.{ .mouse_motion = .{ .pos = .{ .x = x, .y = y }, .window_id = window_id } });
        },
        c.MotionNotify => {
            const x: f32 = @floatFromInt(event.xmotion.x);
            const y: f32 = @floatFromInt(event.xmotion.y);
            core_ptr.pushEvent(.{ .mouse_motion = .{ .pos = .{ .x = x, .y = y }, .window_id = window_id } });
        },
        c.ConfigureNotify => {
            if (event.xconfigure.width != core_window.width or
                event.xconfigure.height != core_window.height)
            {
                core_window.width = @intCast(event.xconfigure.width);
                core_window.height = @intCast(event.xconfigure.height);
                defer core_ptr.windows.setValueRaw(window_id, core_window);

                const new_size = Core.Size{
                    .width = core_window.width,
                    .height = core_window.height,
                };
                core_ptr.pushEvent(.{
                    .resize = .{
                        .window_id = window_id,
                        // TODO: X11 does not currently track pixel density properly
                        .window_size = new_size,
                        .framebuffer_size = new_size,
                        .pixel_density = 1.0,
                    },
                });
            }
        },
        c.FocusIn => {
            if (event.xfocus.mode == c.NotifyGrab or
                event.xfocus.mode == c.NotifyUngrab)
            {
                // Ignore focus events from popup indicator windows, window menu
                // key chords and window dragging
                return;
            }

            core_ptr.pushEvent(.{ .focus_gained = .{ .window_id = window_id } });
        },
        c.FocusOut => {
            if (event.xfocus.mode == c.NotifyGrab or
                event.xfocus.mode == c.NotifyUngrab)
            {
                // Ignore focus events from popup indicator windows, window menu
                // key chords and window dragging
                return;
            }

            core_ptr.pushEvent(.{ .focus_lost = .{ .window_id = window_id } });
        },
        c.ResizeRequest => {
            _ = libx11.?.XResizeWindow(
                x11.display,
                x11.window,
                @intCast(c.DisplayWidth(x11.display, c.DefaultScreen(x11.display))),
                @intCast(c.DisplayHeight(x11.display, c.DefaultScreen(x11.display))),
            );
        },
        else => {},
    }
}

fn toMachMods(mods: c_uint) KeyMods {
    return .{
        .shift = mods & c.ShiftMask != 0,
        .control = mods & c.ControlMask != 0,
        .alt = mods & c.Mod1Mask != 0,
        .super = mods & c.Mod4Mask != 0,
        .caps_lock = mods & c.LockMask != 0,
        .num_lock = mods & c.Mod2Mask != 0,
        .help = false,
        .function = false,
    };
}

fn toMachButton(button: c_uint) ?MouseButton {
    return switch (button) {
        c.Button1 => .left,
        c.Button2 => .middle,
        c.Button3 => .right,
        // Scroll events are handled by caller
        c.Button4, c.Button5, 6, 7 => null,
        // Additional buttons after 7 are treated as regular buttons
        8 => .four,
        9 => .five,
        10 => .six,
        11 => .seven,
        12 => .eight,
        // Unknown button
        else => null,
    };
}

fn toMachKey(key: c.KeySym) Key {
    return switch (key) {
        c.XK_a, c.XK_A => .a,
        c.XK_b, c.XK_B => .b,
        c.XK_c, c.XK_C => .c,
        c.XK_d, c.XK_D => .d,
        c.XK_e, c.XK_E => .e,
        c.XK_f, c.XK_F => .f,
        c.XK_g, c.XK_G => .g,
        c.XK_h, c.XK_H => .h,
        c.XK_i, c.XK_I => .i,
        c.XK_j, c.XK_J => .j,
        c.XK_k, c.XK_K => .k,
        c.XK_l, c.XK_L => .l,
        c.XK_m, c.XK_M => .m,
        c.XK_n, c.XK_N => .n,
        c.XK_o, c.XK_O => .o,
        c.XK_p, c.XK_P => .p,
        c.XK_q, c.XK_Q => .q,
        c.XK_r, c.XK_R => .r,
        c.XK_s, c.XK_S => .s,
        c.XK_t, c.XK_T => .t,
        c.XK_u, c.XK_U => .u,
        c.XK_v, c.XK_V => .v,
        c.XK_w, c.XK_W => .w,
        c.XK_x, c.XK_X => .x,
        c.XK_y, c.XK_Y => .y,
        c.XK_z, c.XK_Z => .z,

        c.XK_0 => .zero,
        c.XK_1 => .one,
        c.XK_2 => .two,
        c.XK_3 => .three,
        c.XK_4 => .four,
        c.XK_5 => .five,
        c.XK_6 => .six,
        c.XK_7 => .seven,
        c.XK_8 => .eight,
        c.XK_9 => .nine,

        c.XK_F1 => .f1,
        c.XK_F2 => .f2,
        c.XK_F3 => .f3,
        c.XK_F4 => .f4,
        c.XK_F5 => .f5,
        c.XK_F6 => .f6,
        c.XK_F7 => .f7,
        c.XK_F8 => .f8,
        c.XK_F9 => .f9,
        c.XK_F10 => .f10,
        c.XK_F11 => .f11,
        c.XK_F12 => .f12,
        c.XK_F13 => .f13,
        c.XK_F14 => .f14,
        c.XK_F15 => .f15,
        c.XK_F16 => .f16,
        c.XK_F17 => .f17,
        c.XK_F18 => .f18,
        c.XK_F19 => .f19,
        c.XK_F20 => .f20,
        c.XK_F21 => .f21,
        c.XK_F22 => .f22,
        c.XK_F23 => .f23,
        c.XK_F24 => .f24,
        c.XK_F25 => .f25,

        c.XK_KP_Divide => .kp_divide,
        c.XK_KP_Multiply => .kp_multiply,
        c.XK_KP_Subtract => .kp_subtract,
        c.XK_KP_Add => .kp_add,
        c.XK_KP_0 => .kp_0,
        c.XK_KP_1 => .kp_1,
        c.XK_KP_2 => .kp_2,
        c.XK_KP_3 => .kp_3,
        c.XK_KP_4 => .kp_4,
        c.XK_KP_5 => .kp_5,
        c.XK_KP_6 => .kp_6,
        c.XK_KP_7 => .kp_7,
        c.XK_KP_8 => .kp_8,
        c.XK_KP_9 => .kp_9,
        c.XK_KP_Decimal => .kp_decimal,
        c.XK_KP_Equal => .kp_equal,
        c.XK_KP_Enter => .kp_enter,

        c.XK_Return => .enter,
        c.XK_Escape => .escape,
        c.XK_Tab => .tab,
        c.XK_Shift_L => .left_shift,
        c.XK_Shift_R => .right_shift,
        c.XK_Control_L => .left_control,
        c.XK_Control_R => .right_control,
        c.XK_Alt_L => .left_alt,
        c.XK_Alt_R => .right_alt,
        c.XK_Super_L => .left_super,
        c.XK_Super_R => .right_super,
        c.XK_Menu => .menu,
        c.XK_Num_Lock => .num_lock,
        c.XK_Caps_Lock => .caps_lock,
        c.XK_Print => .print,
        c.XK_Scroll_Lock => .scroll_lock,
        c.XK_Pause => .pause,
        c.XK_Delete => .delete,
        c.XK_Home => .home,
        c.XK_End => .end,
        c.XK_Page_Up => .page_up,
        c.XK_Page_Down => .page_down,
        c.XK_Insert => .insert,
        c.XK_Left => .left,
        c.XK_Right => .right,
        c.XK_Up => .up,
        c.XK_Down => .down,
        c.XK_BackSpace => .backspace,
        c.XK_space => .space,
        c.XK_minus => .minus,
        c.XK_equal => .equal,
        c.XK_braceleft => .left_bracket,
        c.XK_braceright => .right_bracket,
        c.XK_backslash => .backslash,
        c.XK_semicolon => .semicolon,
        c.XK_apostrophe => .apostrophe,
        c.XK_comma => .comma,
        c.XK_period => .period,
        c.XK_slash => .slash,
        c.XK_grave => .grave,

        else => .unknown,
    };
}
