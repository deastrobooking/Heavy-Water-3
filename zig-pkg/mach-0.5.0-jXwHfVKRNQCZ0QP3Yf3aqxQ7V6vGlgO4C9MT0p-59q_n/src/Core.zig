//! mach.Core provides the ability to open windows, get input events, and ultimately render.
//!
//! # Units
//!
//! Firstly, Core does not expose the concept of monitors (because many platforms, such as mobile
//! phones, consoles, VR devices, browsers, etc. do not have meaningful information about these
//! available.) - instead we only expose the concept of a 'window' - a virtual surface which can be
//! rendered to.
//!
//! Secondly, a window's framebuffer is always allocated at the native display resolution. We do not
//! expose the ability to create a window framebuffer at a lesser resolution and allow the OS
//! compositor to upscale the contents to the native resolution (because while on macOS/iOS this is
//! available with your choice of nearest/bilinear/trilinear upscaling, on Windows only bilinear is
//! available, and on Wayland this depends on the compositor and what extensions are available, and
//! on Android this is usually bilinear but not guaranteed.) Instead, applications are responsible
//! for scaling their render output appropriately. As a result, GPU scissor rectangles, viewports,
//! etc. all operate in framebuffer coordinates.
//!
//! Each window exposes two notable scaling factors that you should be aware of when rendering:
//!
//! 1. `pixel_density`: this is the number of framebuffer texels per window pixel unit. For
//!    example, on a high DPI monitor, creating an 800x600px window may result in a framebuffer
//!    which is twice that size in native (physical) pixels. In this case, `width` and `height`
//!    would be 800x600, `framebuffer_width` and `framebuffer_height` would be 1600x1200, and
//!    `pixel_density` would be `2.0`. Fractional scaling is possible on some platforms.
//! 2. `display_scale`: this is how much bigger the user wants their UI to be, specifically text and
//!    UI elements which are sized relative to the size of text. This corresponds to e.g.
//!    'Display Scale: 150%' in the Microsoft Windows settings.
//!
//! Both scaling factors may change dynamically at runtime, e.g. as a window is dragged from one
//! display or another - or when a user updates their system preferences. Use the Resize and
//! DisplayScaleChanged events to get notified of changes to pixel density and display scale.
//!
//! For example, suppose we wanted to render a green square on the framebuffer, taking up the same
//! visual size as a single character of a 12pt font in other apps on their system. That square
//! would take up `12pt * display_scale * pixel_density` texels in the framebuffer.
//!
//! If we then wanted to stretch a texture of an actual glyph over that square when we render, a
//! glyph texture of `12pt * display_scale` would visually appear to be the right character, but on
//! high DPI (e.g. Retina) displays it would appear blurry, while a glyph texture of
//! `12pt * display_scale * pixel_density` would appear crisp on all displays.
//!
//! You can multiply window units by pixel_density to get framebuffer units, or divide framebuffer
//! units by it to get window units.
const std = @import("std");
const builtin = @import("builtin");

const mach = @import("main.zig");
const gpu = mach.gpu;
const log = std.log.scoped(.mach);

const Core = @This();

pub const mach_module = .mach_core;

pub const mach_systems = .{
    .main,
    .init,
    .tick,
    .snapshotStart,
    .snapshotEnd,
    .deinit,
};

const PendingPresent = struct {
    window_id: mach.ObjectID,
    swap_chain: *gpu.SwapChain,
};

/// Window objects managed by the platform.
windows: mach.Objects(
    // Set track_fields to true so that when these field values change, we know about it
    // and can update the platform windows.
    .{ .track_fields = true },
    struct {
        /// Window title string. May be a static string literal, or owned memory managed via
        /// `core.fmtTitle(window_id, fmt, args)` (which sets `title_owned` to track ownership).
        title: [:0]const u8 = "Mach Window",

        /// If non-null, a heap allocation backing `title` that Core owns and frees when a new
        /// title is set via `fmtTitle` or when the window is destroyed. Set/managed exclusively
        /// by `core.fmtTitle`; do not set this field directly.
        title_owned: ?[:0]u8 = null,

        /// Hash of the previous `fmtTitle` arguments. `fmtTitle` uses this to skip allocation
        /// and `setTitle` work when the inputs haven't changed since the last call, so that calling
        /// `fmtTitle` frequently is less expensive.
        title_hash: u64 = 0,

        /// Render callback
        on_render: ?mach.FunctionID = null,

        /// Frequency at which this window's render callback runs (read-only).
        frame: mach.time.Frequency = .{ .target = 0 },

        /// Texture format of the framebuffer (read-only)
        framebuffer_format: gpu.Texture.Format = .bgra8_unorm,

        /// Width of the window in virtual pixels
        width: u32 = 1920 / 2,

        /// Height of the window in virtual pixels
        height: u32 = 1080 / 2,

        /// Width of the framebuffer in texels (read-only)
        /// Will be updated to reflect the actual framebuffer dimensions after window creation.
        framebuffer_width: u32 = 1920 / 2,

        /// Height of the framebuffer in texels (read-only)
        /// Will be updated to reflect the actual framebuffer dimensions after window creation.
        framebuffer_height: u32 = 1080 / 2,

        /// Number of framebuffer texels per window pixel unit (read-only). See top-level Core docs.
        ///
        /// Updated whenever the window is moved to a display with a different DPI. See also the
        /// `.resize` event.
        pixel_density: f32 = 1.0,

        /// User-preferred UI scale factor (read-only). See top-level Core docs.
        ///
        /// Updated whenever the user changes their system display scale preferences. See also the
        /// `.display_scale_changed` event.
        ///
        /// * on Windows/Linux, this corresponds to the e.g. "Display Scale: 150%" in system
        ///   settings menus.
        /// * on macOS, this value is always 1.0 because macOS handles display scaling at the
        ///   compositor level (no app-side render scaling needed beyond consideration for
        ///   pixel_density)
        ///
        display_scale: f32 = 1.0,

        /// Vertical sync mode, prevents screen tearing.
        vsync_mode: VSyncMode = .triple,

        /// Window display mode: fullscreen, windowed or borderless fullscreen
        display_mode: DisplayMode = .windowed,

        /// Whether or not the cursor should be visible when it is inside the window.
        ///
        /// When the mouse is captured, the cursor is always invisible irrespective of this field.
        cursor_visible: bool = true,

        /// The shape the cursor should use when it is inside the window.
        cursor_shape: CursorShape = .arrow,

        /// Whether or not the mouse cursor should be captured by the window.
        ///
        /// Once set to true, the app requests to capture the mouse cursor - some platforms grant
        /// this request instantly, while others (e.g. browsers) prompt the user to allow it. If the
        /// request is denied, `mouse_capture` is set to `false` and a `.mouse_capture_lost` event
        /// is sent with `.denied = true`. If the request is approved, `mouse_capture` remains
        /// `true` and a `.mouse_capture_gained` event is sent.
        ///
        /// If the request was approved and your application sets `mouse_capture = false`, mouse
        /// capture is released and setting it to true again would be a different request.
        mouse_capture: bool = false,

        /// Whether window decorations (titlebar, borders, etc.) should be shown.
        ///
        /// Has no effect on windows who DisplayMode is .fullscreen or .fullscreen_borderless
        decorated: bool = true,

        /// Color of the window decorations, e.g. titlebar.
        ///
        /// if null, system chooses its defaults
        decoration_color: ?gpu.Color = null,

        /// Whether the window should be completely transparent or not.
        ///
        /// on macOS, you must also set decoration_color to a transparent color if you wish to have
        /// a fully transparent window as it controls the 'background color' of the window.
        transparent: bool = false,

        // GPU
        // When `native` is not null, the rest of the fields have been
        // initialized.
        device: *gpu.Device = undefined,
        instance: *gpu.Instance = undefined,
        adapter: *gpu.Adapter = undefined,
        queue: *gpu.Queue = undefined,
        swap_chain: *gpu.SwapChain = undefined,
        swap_chain_descriptor: gpu.SwapChain.Descriptor = undefined,
        surface: *gpu.Surface = undefined,
        surface_descriptor: gpu.Surface.Descriptor = undefined,

        // After window initialization, (when device is not null)
        // changing these will have no effect
        power_preference: gpu.PowerPreference = .undefined,
        required_features: ?[]const gpu.FeatureName = null,
        required_limits: ?gpu.Limits = null,
        swap_chain_usage: gpu.Texture.UsageFlags = .{
            .render_attachment = true,
        },

        /// Container for native platform-specific information
        native: ?Platform.Native = null,
    },
),

/// The current window being rendered. Only valid during an on_render() callback.
window: mach.ObjectID = undefined,

/// Callback system invoked when application is exiting (called on render thread).
on_exit: ?mach.FunctionID = null,

/// Current state of the application.
state: std.atomic.Value(State) = .init(.running),

input: mach.time.Frequency,
input_periodic_deadline: mach.time.PeriodicDeadline = .{},

/// Mutex protecting the render snapshot itself (e.g. render_graph or snapshotted objects.)
/// The app thread holds this between snapshotStart and snapshotEnd. The render thread holds
/// this only while recording GPU commands (on_render) in renderFrame, releasing it before
/// swapchain presentation so the app thread can start its next snapshot while it presents.
render_mu: std.Io.Mutex = .init,

/// Latest published render snapshot. Incremented by snapshotEnd while holding render_mu. Platform
/// render loops use this to let independently paced windows consume the latest snapshot once.
snapshot_generation: std.atomic.Value(u64) = .init(0),

/// Latest snapshot generation whose first render consumption woke adaptive event pacing.
/// Accessed by the render thread while holding render_mu.
consumed_snapshot_generation: u64 = 0,

/// Coalesces render-consumption wakes until the app thread starts its next event-processing tick.
snapshot_consumed_pending: std.atomic.Value(bool) = .init(false),

/// Swap chains selected during the current render pass. Each entry is retained while render_mu is
/// released so the same set can be presented safely even if its window changes concurrently.
present_swap_chains: std.ArrayList(PendingPresent) = .empty,

// Internal module state
allocator: std.mem.Allocator,
io: std.Io,

backend_events_mu: std.Io.Mutex = .init,
backend_events: std.ArrayList(Event) = .empty,

events_ready: std.Io.Event = .unset,
iter_events: std.ArrayList(Event) = .empty,
input_state: InputState,
oom: std.atomic.Value(bool) = .init(false),
render_graph: mach.Graph,

pub const State = enum(u8) {
    running,
    exiting,
    exited,
};

/// Core.main enters the platform's main loop, which drives rendering on the main thread.
///
/// The app is responsible for running its own tick logic, either:
/// * In `on_render` for single-threaded apps, or
/// * On a separate app thread via `mach.AppThread`.
pub fn main(core: *Core, core_mod: mach.Mod(Core), io: std.Io) !void {
    if (core.on_exit == null) @panic("core.on_exit callback must be set");

    try Platform.tick(core, core_mod, io);

    // Platform drives the main loop (render thread).
    Platform.run(platform_update_callback, .{ core, core_mod, io });

    // Platform.run is marked noreturn on some platforms, but not all, so this is here for the
    // platforms that do return
    std.process.exit(0);
}

pub fn init(core: *Core, allocator: std.mem.Allocator, io: std.Io) !void {
    // TODO(leak): fix all leaks
    try mach.sysgpu.Impl.init(allocator, .{});

    core.* = .{
        // Note: since core.windows is initialized for us already, we just copy the pointer.
        .windows = core.windows,

        .allocator = allocator,
        .io = io,
        .input_state = .{},
        .render_graph = undefined,

        .input = .{ .target = 0 },
    };

    // TODO(leak)
    try core.backend_events.ensureTotalCapacity(allocator, 8192);
    try core.iter_events.ensureTotalCapacity(allocator, 8192);

    // TODO(leak)
    try mach.initGraph(&core.render_graph, allocator, io, .render);

    core.input.start(io);
}

/// Caller must hold core.windows.lock
pub fn initWindow(core: *Core, window_id: mach.ObjectID) !void {
    var core_window = core.windows.getValue(window_id);
    defer core.windows.setValueRaw(window_id, core_window);

    core_window.frame.start(core.io);

    // All windows share the same GPU device; only the surface and swap chain are per-window.
    const existing_gpu = blk: {
        var windows = core.windows.slice();
        while (windows.next()) |wid| {
            if (wid == window_id) continue;
            const w = core.windows.getValue(wid);
            if (w.native != null) break :blk w;
        }
        break :blk null;
    };

    // Reuse the device/instance/adapter/queue from an existing window if available.
    if (existing_gpu) |existing| {
        core_window.instance = existing.instance;
        core_window.adapter = existing.adapter;
        core_window.device = existing.device;
        core_window.queue = existing.queue;
    } else {
        core_window.instance = gpu.createInstance(null) orelse {
            log.err("failed to create GPU instance", .{});
            std.process.exit(1);
        };

        var response: RequestAdapterResponse = undefined;
        core_window.instance.requestAdapter(&gpu.RequestAdapterOptions{
            .compatible_surface = null,
            .power_preference = core_window.power_preference,
            .force_fallback_adapter = .false,
        }, &response, requestAdapterCallback);
        if (response.status != .success) {
            log.err("failed to create GPU adapter: {?s}", .{response.message});
            if (builtin.target.os.tag == .linux) {
                log.info("-> maybe try MACH_FORCE_GPU_BACKEND=opengl ?", .{});
            }
            std.process.exit(1);
        }

        var props = std.mem.zeroes(gpu.Adapter.Properties);
        response.adapter.?.getProperties(&props);
        if (props.backend_type == .null) {
            log.err("no backend found for {s} adapter", .{props.adapter_type.name()});
            std.process.exit(1);
        }
        log.info("found {s} backend on {s} adapter: {s}, {s}\n", .{
            props.backend_type.name(),
            props.adapter_type.name(),
            props.name,
            props.driver_description,
        });

        core_window.adapter = response.adapter.?;
        core_window.device = response.adapter.?.createDevice(&.{
            .required_features_count = if (core_window.required_features) |v| @as(u32, @intCast(v.len)) else 0,
            .required_features = if (core_window.required_features) |v| @as(?[*]const gpu.FeatureName, v.ptr) else null,
            .required_limits = if (core_window.required_limits) |limits| @as(?*const gpu.RequiredLimits, &gpu.RequiredLimits{
                .limits = limits,
            }) else null,
            .device_lost_callback = &deviceLostCallback,
            .device_lost_userdata = null,
        }) orelse {
            log.err("failed to create GPU device\n", .{});
            std.process.exit(1);
        };
        core_window.device.setUncapturedErrorCallback({}, printUnhandledErrorCallback);
        core_window.queue = core_window.device.getQueue();
    }

    // Create window surface
    core_window.surface = core_window.instance.createSurface(&core_window.surface_descriptor);

    // Create swap chain
    core_window.swap_chain_descriptor = gpu.SwapChain.Descriptor{
        .label = "main swap chain",
        .usage = core_window.swap_chain_usage,
        .format = .bgra8_unorm,
        .width = core_window.framebuffer_width,
        .height = core_window.framebuffer_height,
        .present_mode = switch (core_window.vsync_mode) {
            .none_low_latency, .none_max_throughput => .immediate,
            .double, .adaptive => .fifo,
            .triple => .fifo,
            .low_latency => .mailbox,
        },
        .preferred_image_count = core_window.vsync_mode.preferredImageCount(),
    };
    core_window.swap_chain = core_window.device.createSwapChain(core_window.surface, &core_window.swap_chain_descriptor);

    // Emit open event
    core.pushEvent(.{ .open = .{ .window_id = window_id } });
}

/// Render all windows, must be called on the render thread.
pub fn renderFrame(core: *Core, core_mod: mach.Mod(Core), io: std.Io) !void {
    std.debug.assert(core.present_swap_chains.items.len == 0);
    errdefer {
        for (core.present_swap_chains.items) |present| present.swap_chain.release();
        core.present_swap_chains.clearRetainingCapacity();
    }

    var shared_device: ?*gpu.Device = null;
    var signal_snapshot_consumed = false;
    errdefer if (signal_snapshot_consumed) core.signalSnapshotConsumed();

    // Hold render_mu only during GPU command recording (on_render) so the app thread can start its
    // next snapshot while we present.
    {
        core.render_mu.lockUncancelable(io);
        defer core.render_mu.unlock(io);

        const snapshot_generation = core.snapshot_generation.load(.acquire);

        core.windows.lock();
        defer core.windows.unlock();
        var windows = core.windows.slice();
        while (windows.next()) |window_id| {
            const core_window = core.windows.getValue(window_id);
            if (core_window.native == null) continue;
            const on_render = core_window.on_render orelse continue;
            if (!Platform.shouldRenderWindow(core, window_id)) continue;

            try core.present_swap_chains.append(core.allocator, .{
                .window_id = window_id,
                .swap_chain = core_window.swap_chain,
            });
            core_window.swap_chain.reference();
            shared_device = core_window.device;

            // Allow on_render to read the current window being rendered.
            core.window = window_id;

            // Run on_render for the window with the windows lock released so user code may take it.
            core.windows.unlock();
            core_mod.callId(on_render);

            // Ensure nobody reads the window outside on_render.
            core.window = undefined;

            core.windows.lock();
            var frame = core.windows.get(window_id, .frame);
            frame.tick();
            core.windows.setRaw(window_id, .frame, frame);
            Platform.didRenderWindow(core, window_id);

            if (snapshot_generation != 0 and core.consumed_snapshot_generation != snapshot_generation) {
                core.consumed_snapshot_generation = snapshot_generation;
                signal_snapshot_consumed = true;
            }
        }
    }

    // The app thread can begin its next snapshot now that render_mu is available.
    if (signal_snapshot_consumed) core.signalSnapshotConsumed();

    // Present only the selected swap chains outside render_mu so the app thread can prepare the
    // next frame during GPU submission.
    for (core.present_swap_chains.items) |present| {
        Platform.presentSwapChain(core, present.window_id, present.swap_chain, io);
        present.swap_chain.release();
    }
    core.present_swap_chains.clearRetainingCapacity();

    // Device tick.
    if (shared_device) |device| mach.sysgpu.Impl.deviceTick(device);
}

pub fn tick(core: *Core, core_mod: mach.Mod(Core), io: std.Io) !void {
    try Platform.tick(core, core_mod, io);
    _ = try core.handleExit(core_mod);
}

/// Begin submitting a snapshot for rendering the next frame.
pub fn snapshotStart(core: *Core, io: std.Io) !void {
    // Free windows whose native resources have been torn down already by the platform backend. This
    // happens here on the app thread before the snapshot so that the render thread never sees a
    // freed window.
    {
        core.windows.lock();
        defer core.windows.unlock();
        var deleted_windows = core.windows.sliceDeleted();
        while (deleted_windows.next()) |window_id| {
            if (core.windows.get(window_id, .native) != null) continue;
            core.windows.free(window_id);
        }
    }

    core.render_mu.lockUncancelable(io);
    Platform.wakeMainThread(core);
    try core.render_graph.copyFrom(core.windows.internal.graph, core.allocator);
}

/// Copies app-side objects into a render-side snapshot using the current render graph.
pub fn snapshotObjects(core: *Core, dst: anytype, src: anytype) !void {
    try dst.copyFrom(src);
    dst.internal.graph = &core.render_graph;
}

/// End submission of a snapshot for rendering the next frame.
pub fn snapshotEnd(core: *Core, io: std.Io) void {
    _ = core.snapshot_generation.fetchAdd(1, .release);
    core.render_mu.unlock(io);
    Platform.wakeRenderThread(core);
}

/// Sets the window title using a format string. Core owns the resulting allocation and frees it
/// on the next `fmtTitle` call (or when the window is destroyed), so callers do not need to manage
/// the buffer's lifetime.
///
/// The hashed inputs are compared against the previous call's inputs and the work is skipped when
/// they are unchanged, so it is safe and cheap to call this every frame.
///
/// Example:
/// ```
/// core.windows.lock();
/// defer core.windows.unlock();
/// try core.fmtTitle(window_id, "myapp [ {d}fps ] [ Input {d}hz ]", .{
///     core.windows.get(window_id, .frame).rate, core.input.rate,
/// });
/// ```
pub fn fmtTitle(
    core: *Core,
    window_id: mach.ObjectID,
    comptime fmt: []const u8,
    args: anytype,
) std.mem.Allocator.Error!void {
    // If the hashed inputs wouldn't actually change the title, nothing to do.
    const hash = hashTitleArgs(fmt, args);
    if (core.windows.get(window_id, .title_hash) == hash) return;

    const new_title = try std.fmt.allocPrintSentinel(core.allocator, fmt, args, 0);
    if (core.windows.get(window_id, .title_owned)) |prev| core.allocator.free(prev);
    core.windows.set(window_id, .title_owned, new_title);
    core.windows.set(window_id, .title, new_title);
    core.windows.set(window_id, .title_hash, hash);
}

fn hashTitleArgs(comptime fmt: []const u8, args: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(fmt);
    inline for (args) |arg| hashValue(&hasher, arg);
    return hasher.final();
}

fn hashValue(hasher: anytype, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                hasher.update(std.mem.sliceAsBytes(value));
            } else {
                std.hash.autoHash(hasher, value);
            }
        },
        else => std.hash.autoHash(hasher, value),
    }
}

fn platform_update_callback(core: *Core, core_mod: mach.Mod(Core), io: std.Io) !bool {
    try Platform.tick(core, core_mod, io);
    if (try core.handleExit(core_mod)) return false;
    return core.state.load(.acquire) != .exited;
}

fn handleExit(core: *Core, core_mod: mach.Mod(Core)) !bool {
    if (core.state.load(.acquire) == .exiting) {
        if (core.on_exit) |on_exit| core_mod.callId(on_exit);
        core_mod.call(.deinit);
        return true;
    }
    return false;
}

/// Signal that the application should exit. Thread-safe.
pub fn exit(core: *Core) void {
    core.state.store(.exiting, .release);
    core.events_ready.set(core.io);
    Platform.wakeMainThread(core);
}

pub fn deinit(core: *Core) !void {
    core.state.store(.exited, .release);

    // Release per-window resources first, then shared GPU objects once.
    var shared_device: ?*gpu.Device = null;
    var shared_queue: ?*gpu.Queue = null;
    var shared_adapter: ?*gpu.Adapter = null;
    var shared_instance: ?*gpu.Instance = null;

    var windows = core.windows.slice();
    while (windows.next()) |window_id| {
        var core_window = core.windows.getValue(window_id);

        // Free any heap-allocated title owned by Core via fmtTitle().
        if (core_window.title_owned) |owned| core.allocator.free(owned);

        if (core_window.native == null) continue;

        core_window.swap_chain.release();
        core_window.surface.release();

        // Track shared objects for single release.
        shared_device = core_window.device;
        shared_queue = core_window.queue;
        shared_adapter = core_window.adapter;
        shared_instance = core_window.instance;
    }

    if (shared_queue) |q| q.release();
    if (shared_device) |d| d.release();
    if (shared_adapter) |a| a.release();
    if (shared_instance) |i| i.release();

    core.render_graph.deinit(core.allocator);
    core.backend_events.deinit(core.allocator);
    core.iter_events.deinit(core.allocator);
    core.present_swap_chains.deinit(core.allocator);
}

pub const EventMode = union(enum) {
    /// Picks either `.poll` (if any window has vsync disabled) or `.adaptive` otherwise.
    default,
    /// Never blocks.
    poll,
    /// Blocks until there is at least one event.
    wait,
    /// Alias for .adaptive_frequency = .{ .min = 120 }
    adaptive,
    /// Blocks as needed to run at the target minimum frequency, but immediately unblocks if
    /// an event is available or the renderer consumes the latest snapshot.
    ///
    /// Use this to e.g. run your event handling loop at 120hz, but allow the loop to run faster
    /// (e.g. at 1000hz) if the user has a very fast gaming mouse producing events quickly.
    /// Render-consumption wakes also let the app prepare its next snapshot as soon as possible.
    adaptive_frequency: struct {
        min: u32,
    },
    /// Blocks as needed to run at the target frequency.
    ///
    /// Use this to e.g. run your event handling loop at 120hz, and generally not allow it to run
    /// faster even if the user has a very fast input device producing events quickly.
    fixed_frequency: struct {
        target: u32,
    },
};

pub const EventIterator = struct {
    events: []const Event,
    index: usize = 0,

    pub fn next(self: *EventIterator) ?Event {
        if (self.index >= self.events.len) return null;
        const event = self.events[self.index];
        self.index += 1;
        return event;
    }
};

/// Returns an iterator over events using the specified mode for pacing/blocking.
///
/// Events are always buffered between calls to events() so none are lost, the mode strictly
/// controls pacing of your event handling loop itself.
pub fn events(core: *@This(), mode_arg: EventMode) EventIterator {
    Platform.wakeMainThread(core);

    // Resolve .default and .adaptive aliases to a concrete mode.
    const mode: EventMode = switch (mode_arg) {
        .default => blk: {
            core.windows.lockShared();
            defer core.windows.unlockShared();
            var windows = core.windows.slice();
            while (windows.next()) |wid| {
                if (core.windows.get(wid, .vsync_mode).isNone()) break :blk .poll;
            }
            break :blk .{ .adaptive_frequency = .{ .min = 120 } };
        },
        .adaptive => .{ .adaptive_frequency = .{ .min = 120 } },
        else => mode_arg,
    };

    // Set target before tick so delay_ns is computed correctly.
    switch (mode) {
        .adaptive_frequency => |f| core.input.target = f.min,
        .fixed_frequency => |f| core.input.target = f.target,
        else => {},
    }
    core.input.tick();

    // Handle pacing, and ensure we have core.backend_events_mu locked.
    switch (mode) {
        .poll => {
            core.backend_events_mu.lockUncancelable(core.io);
        },
        .wait => {
            core.backend_events_mu.lockUncancelable(core.io);
            while (core.backend_events.items.len == 0 and core.state.load(.acquire) == .running) {
                core.events_ready.reset();
                if (core.backend_events.items.len != 0 or
                    core.state.load(.acquire) != .running) break;

                // Snapshot-consumption wakes are exclusive to adaptive pacing.
                core.backend_events_mu.unlock(core.io);
                core.events_ready.waitUncancelable(core.io);
                core.backend_events_mu.lockUncancelable(core.io);
            }
        },
        .adaptive_frequency => |f| adaptive: {
            const maybe_deadline = core.input_periodic_deadline.next(core.io, f.min);
            core.backend_events_mu.lockUncancelable(core.io);
            const deadline = maybe_deadline orelse break :adaptive;

            while (core.backend_events.items.len == 0 and
                core.state.load(.acquire) == .running and
                !core.snapshot_consumed_pending.load(.acquire))
            {
                core.events_ready.reset();
                if (core.backend_events.items.len != 0 or
                    core.state.load(.acquire) != .running or
                    core.snapshot_consumed_pending.load(.acquire)) break;

                core.backend_events_mu.unlock(core.io);
                core.events_ready.waitTimeout(core.io, .{
                    .deadline = deadline,
                }) catch {
                    core.backend_events_mu.lockUncancelable(core.io);
                    break;
                };
                core.backend_events_mu.lockUncancelable(core.io);
            }
        },
        .fixed_frequency => {
            if (core.input.delay_ns > 0) {
                core.io.sleep(.{ .nanoseconds = @intCast(core.input.delay_ns) }, .awake) catch {};
            }
            core.backend_events_mu.lockUncancelable(core.io);
        },
        .adaptive, .default => unreachable,
    }

    // Reset wakes and consume any snapshot signal satisfied by this tick. Queued event visibility
    // is protected by backend_events_mu, and reset/recheck above filters a late stale set. A render
    // signal racing the atomic swap is either consumed now or remains pending for the next tick.
    core.events_ready.reset();
    _ = core.snapshot_consumed_pending.swap(false, .acq_rel);

    // With the mutex held from above, swap the backend_events (new events) and iter_events (handled events) buffers.
    std.mem.swap(std.ArrayList(Event), &core.backend_events, &core.iter_events);
    core.backend_events.clearRetainingCapacity();
    core.backend_events_mu.unlock(core.io);

    // Update input_state from swapped events.
    for (core.iter_events.items) |event| {
        switch (event) {
            .key_press => |ev| core.input_state.keys.setValue(@intFromEnum(ev.key), true),
            .key_release => |ev| core.input_state.keys.setValue(@intFromEnum(ev.key), false),
            .mouse_press => |ev| core.input_state.mouse_buttons.setValue(@intFromEnum(ev.button), true),
            .mouse_release => |ev| core.input_state.mouse_buttons.setValue(@intFromEnum(ev.button), false),
            .mouse_motion => |ev| core.input_state.mouse_position = ev.pos,
            .focus_lost => {
                // Clear input state that may be 'stuck' when focus is regained.
                core.input_state.keys = InputState.KeyButtonBitSet.initEmpty();
                core.input_state.mouse_buttons = InputState.MouseButtonSet.initEmpty();
            },
            else => {},
        }
    }

    return .{ .events = core.iter_events.items };
}

/// Push an event onto the event queue. Thread-safe.
pub inline fn pushEvent(core: *@This(), event: Event) void {
    core.backend_events_mu.lockUncancelable(core.io);
    core.backend_events.append(core.allocator, event) catch {
        core.backend_events_mu.unlock(core.io);
        core.oom.store(true, .release);
        return;
    };
    core.backend_events_mu.unlock(core.io);
    core.events_ready.set(core.io);
}

/// Wakes adaptive event pacing after the renderer consumes a new snapshot.
fn signalSnapshotConsumed(core: *Core) void {
    if (core.snapshot_consumed_pending.cmpxchgStrong(
        false,
        true,
        .acq_rel,
        .acquire,
    ) == null) core.events_ready.set(core.io);
}

/// Reports whether mach.Core ran out of memory, indicating events may have been dropped.
///
/// Once called, the OOM flag is reset and mach.Core will continue operating normally.
pub fn outOfMemory(core: *@This()) bool {
    if (!core.oom.load(.acquire)) return false;
    core.oom.store(false, .release);
    return true;
}

/// Whether or not the given key button ID is currently pressed down or not.
pub fn keyPressed(core: *@This(), key: KeyButtonID) bool {
    return core.input_state.keyPressed(key);
}

/// Whether or not the given key button ID is currently released (not pressed down).
pub fn keyReleased(core: *@This(), key: KeyButtonID) bool {
    return core.input_state.keyReleased(key);
}

/// Whether or not the given mouse button ID is currently pressed down or not.
pub fn mousePressed(core: *@This(), button: MouseButtonID) bool {
    return core.input_state.mousePressed(button);
}

/// Whether or not the given mouse button ID is currently released (not pressed down).
pub fn mouseReleased(core: *@This(), button: MouseButtonID) bool {
    return core.input_state.mouseReleased(button);
}

/// The current mouse position.
pub fn mousePosition(core: *@This()) Position {
    return core.input_state.mouse_position;
}

inline fn requestAdapterCallback(
    context: *RequestAdapterResponse,
    status: gpu.RequestAdapterStatus,
    adapter: ?*gpu.Adapter,
    message: ?[*:0]const u8,
) void {
    context.* = RequestAdapterResponse{
        .status = status,
        .adapter = adapter,
        .message = message,
    };
}

// TODO(important): expose device loss to users, this can happen especially in the web and on mobile
// devices. Users will need to re-upload all assets to the GPU in this event.
fn deviceLostCallback(reason: gpu.Device.LostReason, msg: [*:0]const u8, userdata: ?*anyopaque) callconv(.c) void {
    _ = userdata;
    if (reason == .destroyed) return;
    log.err("mach: device lost: {s}", .{msg});
    @panic("mach: device lost");
}

pub inline fn printUnhandledErrorCallback(_: void, ty: gpu.ErrorType, message: [*:0]const u8) void {
    switch (ty) {
        .validation => std.log.err("gpu: validation error: {s}\n", .{message}),
        .out_of_memory => std.log.err("gpu: out of memory: {s}\n", .{message}),
        .device_lost => std.log.err("gpu: device lost: {s}\n", .{message}),
        .unknown => std.log.err("gpu: unknown error: {s}\n", .{message}),
        else => unreachable,
    }
    std.process.exit(1);
}

pub fn detectBackendType(allocator: std.mem.Allocator) !gpu.BackendType {
    _ = allocator;
    // TODO(env): upgrade to https://codeberg.org/ziglang/zig/pulls/30644 by properly passing
    // env around
    const backend_ptr = std.c.getenv("MACH_FORCE_GPU_BACKEND") orelse {
        return if (builtin.target.os.tag.isDarwin()) .metal else if (builtin.target.os.tag == .windows) .d3d12 else .vulkan;
    };
    const backend = std.mem.sliceTo(backend_ptr, 0);

    if (std.ascii.eqlIgnoreCase(backend, "null")) return .null;
    if (std.ascii.eqlIgnoreCase(backend, "d3d11")) return .d3d11;
    if (std.ascii.eqlIgnoreCase(backend, "d3d12")) return .d3d12;
    if (std.ascii.eqlIgnoreCase(backend, "metal")) return .metal;
    if (std.ascii.eqlIgnoreCase(backend, "vulkan")) return .vulkan;
    if (std.ascii.eqlIgnoreCase(backend, "opengl")) return .opengl;
    if (std.ascii.eqlIgnoreCase(backend, "opengles")) return .opengles;

    @panic("unknown MACH_FORCE_GPU_BACKEND type");
}

const Platform = switch (builtin.target.os.tag) {
    .wasi => @panic("TODO: support mach.Core WASM platform"),
    .ios => @import("core/iOS.zig"),
    .windows => @import("core/Windows.zig"),
    .linux => blk: {
        if (builtin.target.abi.isAndroid())
            @panic("TODO: support mach.Core Android platform");
        break :blk @import("core/Linux.zig");
    },
    .macos => @import("core/macOS.zig"),
    else => {},
};

pub const InputState = struct {
    const KeyButtonBitSet = std.StaticBitSet(@as(u8, @intFromEnum(KeyButtonID.max)) + 1);
    const MouseButtonSet = std.StaticBitSet(@as(u4, @intFromEnum(MouseButtonID.max)) + 1);

    keys: KeyButtonBitSet = KeyButtonBitSet.initEmpty(),
    mouse_buttons: MouseButtonSet = MouseButtonSet.initEmpty(),
    mouse_position: Position = .{ .x = 0, .y = 0 },

    pub inline fn keyPressed(input: InputState, key: KeyButtonID) bool {
        return input.keys.isSet(@intFromEnum(key));
    }

    pub inline fn keyReleased(input: InputState, key: KeyButtonID) bool {
        return !input.keyPressed(key);
    }

    pub inline fn mousePressed(input: InputState, button: MouseButtonID) bool {
        return input.mouse_buttons.isSet(@intFromEnum(button));
    }

    pub inline fn mouseReleased(input: InputState, button: MouseButtonID) bool {
        return !input.mousePressed(button);
    }
};

pub const Event = union(enum) {
    /// Sent when a window opens.
    open: Open,

    /// Sent when a window is closed.
    close: Close,

    /// Sent when the window's display_scale changes (e.g. when the user changes their system
    /// display scale preferences.)
    display_scale_changed: DisplayScaleChanged,

    /// Sent when a window or its framebuffer is resized, including when the pixel_density
    /// changes (e.g. when the window is moved to a display with a different DPI.)
    resize: Resize,

    /// Sent when a window gains focus.
    focus_gained: FocusGained,

    /// Sent when a window loses focus.
    focus_lost: FocusLost,

    /// Sent once when a key button is pressed down.
    ///
    /// Do not use this event for text input, use the `.char_input` event instead.
    key_press: Key,

    /// Sent at the platform-specified rate when a key button is held down, and continues to be held
    /// down.
    ///
    /// Do not use this event for text input, use the `.char_input` event instead.
    key_repeat: Key,

    /// Sent once when a key button is released.
    ///
    /// Do not use this event for text input, use the `.char_input` event instead.
    key_release: Key,

    /// Sent when the user is trying to input text.
    char_input: CharInput,

    /// Sent when the mouse cursor moves.
    ///
    /// Not sent if the mouse is captured (i.e. after `.mouse_capture_gained` has been sent).
    mouse_motion: MouseMotion,

    /// Sent when the mouse moves while the window has the mouse captured, providing raw mouse
    /// motion deltas.
    mouse_motion_relative: MouseMotionRelative,

    /// Sent when a request to capture the mouse pointer succeeded.
    ///
    /// See the Window `.mouse_capture` field for more information.
    mouse_capture_gained: MouseCaptureGained,

    /// Sent when the mouse capture is lost:
    /// * The platform declined the capture request (`.denied = true`), or
    /// * The window lost focus, or
    /// * The application set `Window.mouse_capture = false`, or
    /// * The platform revoked the capture for any other reason.
    mouse_capture_lost: MouseCaptureLost,

    /// Sent once when a mouse button is pressed down.
    mouse_press: MouseButton,

    /// Sent once when a mouse button is released.
    mouse_release: MouseButton,

    /// Sent when the mouse wheel is scrolled.
    mouse_scroll: MouseScroll,

    /// Zoom gesture began.
    ///
    /// Followed by zero or more `zoom_update` events and terminated by exactly one `zoom_end` or
    /// `zoom_cancel` event.
    ///
    /// Supported on: macOS
    zoom_begin: GestureBegin,

    /// Zoom gesture progressed.
    ///
    /// Supported on: macOS
    zoom_update: ZoomUpdate,

    /// Zoom gesture completed.
    ///
    /// Supported on: macOS
    zoom_end: GestureLifecycle,

    /// Zoom gesture cancelled by the system, e.g. because a palm was recognized instead.
    /// Apps should roll back any zoom state they accumulated during the gesture, rather
    /// than committing it as they would on `zoom_end`.
    ///
    /// Supported on: macOS
    zoom_cancel: GestureLifecycle,

    /// Rotation gesture began.
    ///
    /// Followed by zero or more `rotate_update` events and terminated by exactly one `rotate_end`
    /// or `rotate_cancel` event.
    ///
    /// Supported on: no platforms currently.
    rotate_begin: GestureBegin,

    /// Rotation gesture progressed.
    ///
    /// Supported on: no platforms currently.
    rotate_update: RotateUpdate,

    /// Rotation gesture completed normally.
    ///
    /// Supported on: no platforms currently.
    rotate_end: GestureLifecycle,

    /// Rotation gesture cancelled by the system, e.g. because a palm was recognized instead.
    /// Apps should roll back any rotation state they accumulated during the gesture, rather
    /// than committing it as they would on `rotate_end`.
    ///
    /// Supported on: no platforms currently.
    rotate_cancel: GestureLifecycle,

    /// Panning gesture began.
    ///
    /// Followed by zero or more `pan_update` events and terminated by exactly one `pan_end` or
    /// `pan_cancel` event.
    ///
    /// Supported on: no platforms currently.
    pan_begin: GestureBegin,

    /// Pan gesture progressed.
    ///
    /// Supported on: no platforms currently.
    pan_update: PanUpdate,

    /// Pan gesture completed normally.
    ///
    /// Supported on: no platforms currently.
    pan_end: GestureLifecycle,

    /// Pan gesture cancelled by the system, e.g. because a palm was recognized instead.
    /// Apps should roll back any panning state they accumulated during the gesture, rather
    /// than committing it as they would on `pan_end`.
    ///
    /// Supported on: no platforms currently.
    pan_cancel: GestureLifecycle,

    /// A discrete swipe gesture (single fire on recognition.)
    ///
    /// Supported on: no platforms currently.
    swipe_gesture: SwipeGesture,

    pub const Key = struct {
        window_id: mach.ObjectID,
        key: KeyButtonID,
        mods: KeyMods,
    };

    pub const CharInput = struct {
        window_id: mach.ObjectID,
        codepoint: u21,
    };

    pub const MouseMotion = struct {
        window_id: mach.ObjectID,

        /// Mouse position, in window units, with sub-pixel precision when possible.
        pos: Position,
    };

    pub const MouseMotionRelative = struct {
        window_id: mach.ObjectID,

        /// Horizontal mouse delta in window units since the last motion event.
        dx: f64,

        /// Vertical mouse delta in window units since the last motion event.
        dy: f64,
    };

    pub const MouseCaptureGained = struct {
        window_id: mach.ObjectID,
    };

    pub const MouseCaptureLost = struct {
        window_id: mach.ObjectID,

        /// Whether or not the mouse capture request was denied. If it was granted but subsequently
        /// lost, this will be false (e.g. focus loss, application set `.mouse_capture = false`,
        /// etc.)
        denied: bool,
    };

    pub const MouseButton = struct {
        window_id: mach.ObjectID,
        button: MouseButtonID,
        mods: KeyMods,

        /// Mouse position, in window units, with sub-pixel precision when possible.
        pos: Position,
    };

    pub const MouseScroll = struct {
        window_id: mach.ObjectID,
        xoffset: f32,
        yoffset: f32,
    };

    pub const Resize = struct {
        window_id: mach.ObjectID,

        /// New window size, in window units.
        window_size: Size,

        /// New framebuffer size, in framebuffer units.
        framebuffer_size: Size,

        /// New number of framebuffer texels per window unit. See top-level Core docs for what this
        /// represents.
        pixel_density: f32,
    };

    pub const DisplayScaleChanged = struct {
        window_id: mach.ObjectID,

        /// New display scale factor. See top-level Core docs for what this represents.
        display_scale: f32,
    };

    pub const Open = struct {
        window_id: mach.ObjectID,
    };

    /// A touch gesture lifecycle event.
    pub const GestureLifecycle = struct {
        window_id: mach.ObjectID,

        /// When the underlying hardware / OS reported this gesture transition.
        ///
        /// Drawn from the host's monotonic clock so successive events are guaranteed to have
        /// non-decreasing timestamps.
        timestamp: std.Io.Timestamp = .zero,
    };

    /// A touch gesture 'begin' lifecycle event.
    pub const GestureBegin = struct {
        window_id: mach.ObjectID,

        /// See `GestureLifecycle.timestamp`.
        timestamp: std.Io.Timestamp = .zero,

        /// The gesture's focal point: the centroid of the contacts the OS's recognizer attributes
        /// to this gesture, in normalized window coordinates - for implementing 'zoom around the
        /// cursor', 'rotate around the pinch center', etc. behavior.
        ///
        /// Normalized window-space focal point: `0` is the left/top edge, `1` is
        /// the right/bottom edge (same convention as `Event.Finger.x` / `.y`).
        ///
        /// May lie outside `[0, 1]` if the recognizer's centroid falls outside
        /// the window bounds (e.g. trackpad gesture that the OS attributes to
        /// the focused window even though no physical contact is on it).
        focal_x: f32,
        focal_y: f32,
    };

    pub const ZoomUpdate = struct {
        window_id: mach.ObjectID,

        /// See `GestureLifecycle.timestamp`.
        timestamp: std.Io.Timestamp = .zero,

        /// Zoom scale change since the previous `zoom_update` (or `zoom_begin` for the first
        /// update). `1.0` = no change; `> 1.0` = zoom in; `< 1.0` = zoom out.
        ///
        /// To accumulate: `final_zoom *= ev.zoom_delta;`
        zoom_delta: f32,
    };

    pub const RotateUpdate = struct {
        window_id: mach.ObjectID,

        /// See `GestureLifecycle.timestamp`.
        timestamp: std.Io.Timestamp = .zero,

        /// Additive rotation change since the previous `rotate_update` (or `rotate_begin`) in
        /// radians. Positive is clockwise on screen.
        ///
        /// To accumulate: `final_rotation += ev.rotation_delta;`
        rotation_delta: f32,
    };

    pub const PanUpdate = struct {
        window_id: mach.ObjectID,

        /// See `GestureLifecycle.timestamp`.
        timestamp: std.Io.Timestamp = .zero,

        /// Additive translation since the previous `pan_update` (or `pan_begin`), normalized
        /// against the window's bounds (same convention as `Event.Finger.dx` / `.dy`)
        /// `dx = 1.0` means a full window width to the right; `dy` grows downward.
        ///
        /// To accumulate: `final_pos.x += ev.dx; final_pos.y += ev.dy`
        dx: f32,
        dy: f32,
    };

    pub const SwipeGesture = struct {
        window_id: mach.ObjectID,

        /// See `GestureLifecycle.timestamp`.
        timestamp: std.Io.Timestamp = .zero,

        /// Cardinal direction the swipe travelled in window space.
        direction: SwipeDirection,
    };

    pub const FocusGained = struct {
        window_id: mach.ObjectID,
    };

    pub const FocusLost = struct {
        window_id: mach.ObjectID,
    };

    pub const Close = struct {
        window_id: mach.ObjectID,
    };
};

pub const MouseButtonID = enum {
    left,
    right,
    middle,
    four,
    five,
    six,
    seven,
    eight,

    pub const max = MouseButtonID.eight;
};

pub const KeyMods = packed struct(u16) {
    shift: bool,
    control: bool,
    alt: bool,
    super: bool,
    caps_lock: bool,
    num_lock: bool,
    help: bool,
    function: bool,
    _padding: u8 = 0,
};

pub const SwipeDirection = enum { up, down, left, right };

/// A keyboard button ID, a virtual 'scancode' (not mapping to actual USB or PS/2 scancodes).
///
/// This is a physical button identifier, irrespective of keyboard layout. For example, `.w` is used
/// to identify the key in the QWERTY keyboard layout "W" location, even if the keyboard is actually
/// AZERTY layout or any other non-QWERTY layout.
///
/// This lets you e.g. map WASD keyboard movement to the same physical location on all keyboards,
/// irrespective of layout.
pub const KeyButtonID = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,

    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,

    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_comma,
    kp_equal,
    kp_enter,

    enter,
    escape,
    tab,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    menu,
    num_lock,
    caps_lock,
    print,
    scroll_lock,
    pause,
    delete,
    home,
    end,
    page_up,
    page_down,
    insert,
    left,
    right,
    up,
    down,
    backspace,
    space,
    minus,
    equal,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    comma,
    period,
    slash,
    grave,

    iso_backslash,
    international1,
    international2,
    international3,
    international4,
    international5,
    lang1,
    lang2,

    unknown,

    pub const max = KeyButtonID.unknown;
};

pub const DisplayMode = enum {
    /// Windowed mode.
    windowed,

    /// Fullscreen mode, using this option may change the display's video mode.
    fullscreen,

    /// Borderless fullscreen window.
    ///
    /// Beware that true .fullscreen is also a hint to the OS that is used in various contexts, e.g.
    ///
    /// * macOS: Moving to a virtual space dedicated to fullscreen windows as the user expects
    /// * macOS: .fullscreen_borderless windows cannot prevent the system menu bar from being
    ///          displayed, which makes it appear 'not fullscreen' to users who are familiar with
    ///          macOS.
    ///
    /// Always allow users to choose their preferred display mode.
    fullscreen_borderless,
};

/// Controls how frames are buffered, synchronized, and presented with the display/compositor.
///
/// | VSyncMode              | Present Mode | Metal (macOS)                      | Metal (iOS)                 | D3D12                                          | Vulkan          | WebAssembly           |
/// |------------------------|--------------|------------------------------------|-----------------------------|------------------------------------------------|-----------------|-----------------------|
/// | `.double`              | fifo         | displaySync=on, 2 drawables        | displaySync=on, 2 drawables | 2 buffers, flip-sequential                     | minImageCount=2 | requestAnimationFrame |
/// | `.triple`              | fifo         | displaySync=on, 3 drawables        | displaySync=on, 3 drawables | 3 buffers, flip-discard                        | minImageCount=3 | same as `.double`     |
/// | `.low_latency`         | mailbox      | same as `.double`                  | same as `.double`           | 2 buffers, flip-discard, SetMaxFrameLatency(1) | minImageCount+1 | same as `.double`     |
/// | `.adaptive`            | fifo_relaxed | same as `.double`                  | same as `.double`           | `DXGI_PRESENT_ALLOW_TEARING` per-present       | minImageCount=2 | same as `.double`     |
/// | `.none_low_latency`    | immediate    | displaySync=off, 2 drawables[1]    | same as `.double`[2]        | 2 buffers, `SetMaxFrameLatency(1)`, waitable   | minImageCount=2 | same as `.double`     |
/// | `.none_max_throughput` | immediate    | displaySync=off, 2 drawables[1]    | same as `.double`[2]        | 3 buffers, `SetMaxFrameLatency(2)`             | minImageCount=3 | same as `.double`     |
///
/// 1. Metal APIs generally do not allow outpacing the compositors' frame rate, so .none vsync
///    typically run about 3x the usual refresh rate, although sometimes higher in fullscreen.
/// 2. iOS: displaySyncEnabled is always true; disabling vsync is not supported.
///
pub const VSyncMode = enum {
    /// May cause tearing, may stall GPU. Aims for lowest latency, not highest FPS.
    none_low_latency,

    /// Traditional "vsync off"
    ///
    /// May cause tearing. Aims for highest frame rate, not lowest latency.
    none_max_throughput,

    /// Traditional "double bufferring"
    ///
    /// No tearing. Double buffered. Framerate halves on missed deadlines.
    double,

    /// No tearing. Triple-buffered. No GPU stalls, all frames shown in order.
    triple,

    /// No tearing. Lowest latency. Discards stale frames, wastes GPU work.
    low_latency,

    /// No tearing, but Vtears on missed deadlines instead of halving framerate.
    adaptive,

    pub fn isNone(mode: VSyncMode) bool {
        return mode == .none_low_latency or mode == .none_max_throughput;
    }

    /// Returns the preferred number of presentable swap chain images.
    ///
    /// This is not the number of frames the application may render ahead of presentation.
    pub fn preferredImageCount(mode: VSyncMode) u32 {
        return switch (mode) {
            .double, .low_latency, .adaptive => 2,
            .triple, .none_max_throughput => 3,
            .none_low_latency => 2,
        };
    }
};

pub const Size = struct {
    width: u32,
    height: u32,

    pub inline fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }
};

pub const CursorShape = enum {
    arrow,
    ibeam,
    crosshair,
    pointing_hand,
    resize_ew,
    resize_ns,
    resize_nwse,
    resize_nesw,
    resize_all,
    not_allowed,
};

pub const Position = struct {
    x: f64,
    y: f64,
};

const RequestAdapterResponse = struct {
    status: gpu.RequestAdapterStatus,
    adapter: ?*gpu.Adapter,
    message: ?[*:0]const u8,
};

fn assertHasDecl(comptime T: anytype, comptime decl_name: []const u8) void {
    if (!@hasDecl(T, decl_name)) @compileError(@typeName(T) ++ " missing declaration: " ++ decl_name);
}

fn assertHasField(comptime T: anytype, comptime field_name: []const u8) void {
    if (!@hasField(T, field_name)) @compileError(@typeName(T) ++ " missing field: " ++ field_name);
}

test {
    _ = Platform;
    @import("std").testing.refAllDecls(VSyncMode);
    @import("std").testing.refAllDecls(Size);
    @import("std").testing.refAllDecls(Position);
    @import("std").testing.refAllDecls(Event);
    @import("std").testing.refAllDecls(MouseButtonID);
    @import("std").testing.refAllDecls(KeyButtonID);
    @import("std").testing.refAllDecls(KeyMods);
    @import("std").testing.refAllDecls(DisplayMode);
    @import("std").testing.refAllDecls(CursorShape);
}

test "VSyncMode selects the preferred swap chain image count" {
    try std.testing.expectEqual(2, VSyncMode.double.preferredImageCount());
    try std.testing.expectEqual(3, VSyncMode.triple.preferredImageCount());
    try std.testing.expectEqual(2, VSyncMode.low_latency.preferredImageCount());
    try std.testing.expectEqual(2, VSyncMode.adaptive.preferredImageCount());
    try std.testing.expectEqual(2, VSyncMode.none_low_latency.preferredImageCount());
    try std.testing.expectEqual(3, VSyncMode.none_max_throughput.preferredImageCount());
}

test "snapshot consumption wake coalesces until consumed" {
    var core: Core = undefined;
    core.io = std.testing.io;
    core.events_ready = .unset;
    core.snapshot_consumed_pending = .init(false);

    core.signalSnapshotConsumed();
    try std.testing.expect(core.snapshot_consumed_pending.load(.acquire));
    try std.testing.expect(core.events_ready.isSet());

    core.events_ready.reset();
    core.signalSnapshotConsumed();
    try std.testing.expect(!core.events_ready.isSet());

    try std.testing.expect(core.snapshot_consumed_pending.swap(false, .acq_rel));
    core.signalSnapshotConsumed();
    try std.testing.expect(core.events_ready.isSet());
}
