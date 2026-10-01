const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Mesh = @import("Mesh.zig");
const Scene = @import("StreamingScene.zig");
const Seed = @import("../procedural/Seed.zig");
const FrameStats = @import("../engine/FrameStats.zig");
const Flythrough = @import("../engine/Flythrough.zig");
const Overlay = @import("Overlay.zig");
const Modifications = @import("../world/Modifications.zig");
const options = @import("options");
const Renderer = @This();
const Characters = @import("Characters.zig");

pub const mach_module = .renderer;
pub const mach_systems = .{ .init, .render, .deinit };
pub const panel_capacity = 16;
const Instance = Scene.Instance;
comptime {
    if (options.upload_budget < Scene.chunk_bytes) @compileError("upload-budget-kib must be at least 278");
}
const Sky = @import("../engine/Sky.zig");
/// Matches `Frame` in scene.wgsl.
const Frame = extern struct { vp: mach.math.Mat4x4, eye: [4]f32, light_direction: [4]f32, light_color: [4]f32, ambient_sky: [4]f32, ambient_ground: [4]f32, horizon: [4]f32, planes: [6][4]f32 };
const Field = @import("Field.zig");
const Memory = @import("../engine/Memory.zig");
const Visibility = @import("Visibility.zig");
pub const max_views = Layout.max_views;
/// One split-screen view. View 0 is P1's and uses `hud_lines`, `panel`, and the metrics.
pub const View = struct {
    camera: Camera = .{},
    /// Avatar owner hidden in this view (its own body in first person), or 0.
    hide_owner: u8 = 0,
    crosshair: bool = false,
    /// Guest status and hint lines, drawn in `accent`.
    lines: [2]Overlay.Line = @splat(.{}),
    accent: [4]f32 = .{ 0.24, 0.88, 0.82, 1 },
};
const Layout = @import("Layout.zig");
pub const Rect = Layout.Rect;
pub const viewRect = Layout.viewRect;

// Written by App.publish only inside Core's render mutex.
views: [max_views]View = @splat(.{}),
view_count: usize = 1,
/// Time of day in [0, 1) (0.5 noon), published by the application.
time_of_day: f32 = 0.35,
outline_pipeline: ?*gpu.RenderPipeline = null,
outline_layout: ?*gpu.BindGroupLayout = null,
outline_bind_group: ?*gpu.BindGroup = null,
tick: u64 = 0,
show_metrics: bool = true,
culling: bool = false,
props: [World.max_props]World.Prop = undefined,
prop_count: usize = 0,
modifications: Modifications = .{},
hud_lines: [3]Overlay.Line = @splat(.{}),
/// Machine inspection text (right side), drawn even with metrics hidden.
panel: [panel_capacity]Overlay.Line = @splat(.{}),
panel_count: usize = 0,
scene: Scene = undefined,
characters: Characters = .{},
/// Views 2–4 stream their own terrain; created when first shown, kept until exit so pools
/// never grow again mid-session.
extra_scenes: [max_views - 1]?*Scene = @splat(null),
allocator: std.mem.Allocator = undefined,
io: std.Io = undefined,
seed: u64 = 0,
intervals: FrameStats = .{},
cpu_times: FrameStats = .{},
percentiles: FrameStats.Summary = .{ .p50 = 0, .p95 = 0, .p99 = 0, .worst = 0, .mean = 0 },
pipeline: ?*gpu.RenderPipeline = null,
overlay_pipeline: ?*gpu.RenderPipeline = null,
scene_layout: ?*gpu.BindGroupLayout = null,
uniforms: [max_views]?*gpu.Buffer = @splat(null),
instance_buffers: [max_views]?*gpu.Buffer = @splat(null),
bind_groups: [max_views]?*gpu.BindGroup = @splat(null),
overlay_buffer: ?*gpu.Buffer = null,
texture: ?*gpu.Texture = null,
texture_view: ?*gpu.TextureView = null,
sampler: ?*gpu.Sampler = null,
depth: ?*gpu.Texture = null,
depth_view: ?*gpu.TextureView = null,
width: u32 = 0,
height: u32 = 0,
overlay: Overlay = .{},
timer: mach.time.Timer = undefined,
frames: u64 = 0,
frame_ms: f32 = 0,
underfilled_frames: u64 = 0,
arbor_detail_frames: u64 = 0,
arbor_proxy_frames: u64 = 0,
/// Scale workload (`-Dscale-objects`), its GPU instance buffer, and per-frame measurements.
field: ?Field = null,
field_buffer: ?*gpu.Buffer = null,
field_submitted: FrameStats = .{},
field_runs: FrameStats = .{},
field_cells: FrameStats = .{},
field_resident_frame: ?u64 = null,
field_peak_cpu_bytes: usize = 0,
field_last: Field.Plan = .{},
peak_footprint: u64 = 0,
/// Late catalog uploads (deferred builds, packs): worst frame and totals.
peak_late_upload: usize = 0,
largest_late_mesh: usize = 0,
total_late_uploads: u32 = 0,
/// Pack stress benchmark, published by the application.
pack_requested_frame: i64 = -1,
pack_installed: u32 = 0,
pack_ready_frame: i64 = -1,
pack_bytes: u64 = 0,
/// `-Dcapture-frame`: offscreen target, compute copy, and a readback buffer mapped after the
/// GPU finishes.
capture_pipeline: ?*gpu.ComputePipeline = null,
capture_layout: ?*gpu.BindGroupLayout = null,
capture_texture: ?*gpu.Texture = null,
capture_view: ?*gpu.TextureView = null,
capture_buffer: ?*gpu.Buffer = null,
capture_size: [2]u32 = .{ 0, 0 },
capture_ready: std.atomic.Value(bool) = .init(false),
capture_requested: bool = false,

pub fn init(self: *Renderer, world: *World, io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .seed = world.seed, .allocator = allocator, .io = io, .scene = try Scene.init(allocator, io, world.seed, &world.catalog) };
    if (options.scale_objects > 0) {
        var timer = mach.time.Timer.start(io);
        self.field = try Field.generate(allocator, world.seed, options.scale_objects);
        self.field.?.generation_ms = timer.read() * 1000;
        self.field_peak_cpu_bytes = self.field.?.cpuBytes();
        std.log.info("Scale workload: {d} objects in {d} cells, generated in {d:.0} ms, {d} MiB of instances", .{ options.scale_objects, Field.cell_count, self.field.?.generation_ms, self.field.?.gpuBytes() >> 20 });
    }
}

fn setup(self: *Renderer, core: *mach.Core) !void {
    const window = core.windows.getValue(core.window);
    const device = window.device;
    // Keep Mach's fail-fast GPU callback: validation errors must fail smoke/benchmark runs.
    // Every field below is nulled by its errdefer so a failure partway leaves deinit() safe to
    // release only what was actually created; render() turns a setup failure into a clean exit
    // instead of letting it reach Mach's panic-on-error callback dispatch.
    const shader = device.createShaderModuleWGSL("scene.wgsl", @embedFile("scene.wgsl"));
    defer shader.release();
    const layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{ .entries = &.{
        gpu.BindGroupLayout.Entry.initBuffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(Frame)),
        gpu.BindGroupLayout.Entry.initTexture(1, .{ .fragment = true }, .float, .dimension_2d, false),
        gpu.BindGroupLayout.Entry.initSampler(2, .{ .fragment = true }, .filtering),
    } }));
    self.scene_layout = layout;
    errdefer {
        layout.release();
        self.scene_layout = null;
    }
    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{ .bind_group_layouts = &.{layout} }));
    defer pipeline_layout.release();
    self.texture = device.createTexture(&.{ .label = "surface checker", .size = .{ .width = 2, .height = 2 }, .format = .rgba8_unorm, .usage = .{ .texture_binding = true, .copy_dst = true } });
    errdefer {
        self.texture.?.release();
        self.texture = null;
    }
    self.texture_view = self.texture.?.createView(&.{});
    errdefer {
        self.texture_view.?.release();
        self.texture_view = null;
    }
    self.sampler = device.createSampler(&.{ .address_mode_u = .repeat, .address_mode_v = .repeat, .mag_filter = .nearest, .min_filter = .nearest });
    errdefer {
        self.sampler.?.release();
        self.sampler = null;
    }
    const pixels = [_]u8{ 240, 240, 240, 255, 190, 200, 205, 255, 190, 200, 205, 255, 240, 240, 240, 255 };
    window.queue.writeTexture(&.{ .texture = self.texture.? }, &.{ .bytes_per_row = 8, .rows_per_image = 2 }, &.{ .width = 2, .height = 2 }, &pixels);
    self.createViewResources(device, 0);
    errdefer self.releaseViewResources(0);
    if (self.field) |f| self.field_buffer = device.createBuffer(&.{ .label = "scale field", .size = @max(f.gpuBytes(), 64), .usage = .{ .vertex = true, .copy_dst = true } });
    const buffers = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout.init(.{ .array_stride = @sizeOf(Mesh.Vertex), .attributes = &.{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = 12, .shader_location = 1 },
            .{ .format = .float32x2, .offset = 24, .shader_location = 2 },
            .{ .format = .float32x3, .offset = 32, .shader_location = 5 },
        } }),
        gpu.VertexBufferLayout.init(.{ .array_stride = @sizeOf(Instance), .step_mode = .instance, .attributes = &.{
            .{ .format = .float32x4, .offset = 0, .shader_location = 3 },
            .{ .format = .float32x4, .offset = 16, .shader_location = 4 },
            .{ .format = .float32x4, .offset = 32, .shader_location = 6 },
            .{ .format = .float32x4, .offset = 48, .shader_location = 7 },
        } }),
    };
    const fragment = gpu.FragmentState.init(.{ .module = shader, .entry_point = "frag_main", .targets = &.{.{ .format = window.framebuffer_format }} });
    self.pipeline = device.createRenderPipeline(&.{
        .label = "opaque textured instances",
        .layout = pipeline_layout,
        .vertex = gpu.VertexState.init(.{ .module = shader, .entry_point = "vertex_main", .buffers = &buffers }),
        .fragment = &fragment,
        .primitive = .{ .cull_mode = .none },
        .depth_stencil = &.{ .format = .depth32_float, .depth_write_enabled = .true, .depth_compare = .greater },
    });
    errdefer {
        self.pipeline.?.release();
        self.pipeline = null;
    }
    self.scene.setup(device, window.queue);

    // Silhouette outlines: a fullscreen pass sampling scene depth, blended over the frame.
    const outline_shader = device.createShaderModuleWGSL("outline.wgsl", @embedFile("outline.wgsl"));
    defer outline_shader.release();
    self.outline_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{ .entries = &.{
        gpu.BindGroupLayout.Entry.initTexture(0, .{ .fragment = true }, .depth, .dimension_2d, false),
    } }));
    const outline_pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{ .bind_group_layouts = &.{self.outline_layout.?} }));
    defer outline_pipeline_layout.release();
    const blend: gpu.BlendState = .{
        .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
        .alpha = .{ .operation = .add, .src_factor = .zero, .dst_factor = .one },
    };
    const outline_fragment = gpu.FragmentState.init(.{ .module = outline_shader, .entry_point = "frag_main", .targets = &.{.{ .format = window.framebuffer_format, .blend = &blend }} });
    self.outline_pipeline = device.createRenderPipeline(&.{
        .label = "silhouette outlines",
        .layout = outline_pipeline_layout,
        .vertex = gpu.VertexState.init(.{ .module = outline_shader, .entry_point = "vertex_main" }),
        .fragment = &outline_fragment,
    });

    const hud_shader = device.createShaderModuleWGSL("overlay.wgsl", @embedFile("overlay.wgsl"));
    defer hud_shader.release();
    const hud_fragment = gpu.FragmentState.init(.{ .module = hud_shader, .entry_point = "frag_main", .targets = &.{.{ .format = window.framebuffer_format }} });
    self.overlay_pipeline = device.createRenderPipeline(&.{
        .vertex = gpu.VertexState.init(.{ .module = hud_shader, .entry_point = "vertex_main", .buffers = &.{gpu.VertexBufferLayout.init(.{ .array_stride = @sizeOf(Overlay.Vertex), .attributes = &.{
            .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x4, .offset = 8, .shader_location = 1 },
        } })} }),
        .fragment = &hud_fragment,
    });
    errdefer {
        self.overlay_pipeline.?.release();
        self.overlay_pipeline = null;
    }
    self.overlay_buffer = device.createBuffer(&.{ .label = "debug overlay", .size = Overlay.capacity * @sizeOf(Overlay.Vertex), .usage = .{ .vertex = true, .copy_dst = true } });
    errdefer {
        self.overlay_buffer.?.release();
        self.overlay_buffer = null;
    }
    std.log.info("Heavy Water: seed={d}, generator={d}, streaming pool=49 chunks, GPU pool=25 chunks, upload budget={d}", .{ self.seed, Seed.generator_version, options.upload_budget });
    self.timer.reset();
}

/// Per-view camera uniform, bind group, and instance buffer.
fn createViewResources(self: *Renderer, device: *gpu.Device, i: usize) void {
    self.uniforms[i] = device.createBuffer(&.{ .label = "camera", .size = @sizeOf(Frame), .usage = .{ .uniform = true, .copy_dst = true } });
    self.instance_buffers[i] = device.createBuffer(&.{ .label = "instances", .size = Scene.max_instances * @sizeOf(Instance), .usage = .{ .vertex = true, .copy_dst = true } });
    self.bind_groups[i] = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = self.scene_layout.?, .entries = &.{
        gpu.BindGroup.Entry.initBuffer(0, self.uniforms[i].?, 0, @sizeOf(Frame), @sizeOf(Frame)),
        gpu.BindGroup.Entry.initTextureView(1, self.texture_view.?),
        gpu.BindGroup.Entry.initSampler(2, self.sampler.?),
    } }));
}

fn releaseViewResources(self: *Renderer, i: usize) void {
    if (self.bind_groups[i]) |p| p.release();
    if (self.instance_buffers[i]) |p| p.release();
    if (self.uniforms[i]) |p| p.release();
    self.bind_groups[i] = null;
    self.instance_buffers[i] = null;
    self.uniforms[i] = null;
}

/// The scene for view `i`, creating a split-screen view's streamer and GPU pool on first use.
fn viewScene(self: *Renderer, device: *gpu.Device, i: usize) !*Scene {
    if (i == 0) return &self.scene;
    if (self.extra_scenes[i - 1]) |scene| return scene;
    const scene = try self.allocator.create(Scene);
    errdefer self.allocator.destroy(scene);
    scene.* = try Scene.init(self.allocator, self.io, self.seed, self.scene.catalog);
    scene.setupShared(device, &self.scene);
    self.createViewResources(device, i);
    self.extra_scenes[i - 1] = scene;
    std.log.info("Split-screen view {d}: streaming pool=49 chunks, GPU pool=25 chunks", .{i + 1});
    return scene;
}

fn resize(self: *Renderer, device: *gpu.Device, width: u32, height: u32) void {
    if (self.width == width and self.height == height) return;
    if (self.outline_bind_group) |g| g.release();
    if (self.depth_view) |v| v.release();
    if (self.depth) |t| t.release();
    // Sampled by the outline pass after the scene pass.
    self.depth = device.createTexture(&.{ .label = "scene depth", .size = .{ .width = width, .height = height }, .format = .depth32_float, .usage = .{ .render_attachment = true, .texture_binding = true } });
    self.depth_view = self.depth.?.createView(&.{});
    self.outline_bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = self.outline_layout.?, .entries = &.{
        gpu.BindGroup.Entry.initTextureView(0, self.depth_view.?),
    } }));
    self.width = width;
    self.height = height;
}

fn benchmarkArborMesh(self: *const Renderer) @import("../asset/Catalog.zig").MeshHandle {
    return if (options.benchmark_arbor == 0) self.scene.catalog.content.test_arbor else self.scene.catalog.arbors[options.benchmark_arbor - 1].mesh;
}

pub fn render(self: *Renderer, core: *mach.Core) !void {
    // A setup failure must not reach Mach's callback dispatch: it panics on any returned error,
    // skipping App.stop/Renderer.deinit and leaking the streaming worker and GPU resources.
    if (self.pipeline == null) self.setup(core) catch |err| {
        std.log.err("renderer setup failed, exiting: {s}", .{@errorName(err)});
        core.exit();
        return;
    };
    var cpu_timer = mach.time.Timer.start(self.timer.io);
    if (options.benchmark_frames > 0) {
        const frame = self.frames -| Flythrough.warmup_frames;
        self.view_count = 1;
        self.views[0].camera = Flythrough.camera(frame, options.benchmark_frames);
        if (options.benchmark_canopy) for (self.props[0..self.prop_count]) |prop| {
            if (prop.mesh.eql(self.benchmarkArborMesh())) {
                self.views[0].camera = Flythrough.canopyCamera(frame, options.benchmark_frames, prop.transform.position);
                break;
            }
        };
    }
    const window = core.windows.getValue(core.window);
    if (window.framebuffer_width == 0 or window.framebuffer_height == 0) return;
    const swap_view = window.swap_chain.getCurrentTextureView() orelse return;
    defer swap_view.release();
    self.resize(window.device, window.framebuffer_width, window.framebuffer_height);
    if (self.capture_ready.load(.acquire)) return self.finishCapture(core);
    const capturing = options.capture_frame > 0 and self.frames == options.capture_frame and !self.capture_requested;
    if (capturing) self.prepareCapture(window.device, window.framebuffer_format);
    const back = if (capturing) self.capture_view.? else swap_view;
    const elapsed = self.timer.lap();
    self.frame_ms = if (self.frames == 0) elapsed * 1000 else self.frame_ms * 0.95 + elapsed * 50;
    // Unattended smoke covers a complete lighting cycle, independent of presentation speed.
    const sky_time = if (options.smoke_frames > 0 and options.benchmark_frames == 0)
        @as(f32, @floatFromInt(self.frames)) / @as(f32, @floatFromInt(options.smoke_frames))
    else
        self.time_of_day;
    const light = Sky.at(sky_time);
    const encoder = window.device.createCommandEncoder(&.{ .label = "frame" });
    defer encoder.release();
    try self.characters.prepare(self.allocator, window.device, encoder, self.props[0..self.prop_count]);
    // Catalog meshes installed after startup (deferred builds, reloads) upload under a budget.
    const late = self.scene.uploadMeshes(window.device, window.queue, options.asset_upload);
    if (options.benchmark_frames == 0 or self.frames >= Flythrough.warmup_frames) {
        self.peak_late_upload = @max(self.peak_late_upload, late);
        self.total_late_uploads += self.scene.late_uploads;
        if (self.scene.late_uploads == 1) self.largest_late_mesh = @max(self.largest_late_mesh, late);
    }
    self.scene.late_uploads = 0;
    const count = @max(1, @min(self.view_count, max_views));
    var scenes: [max_views]*Scene = undefined;
    var pixels: [max_views][4]u32 = undefined;
    var objects: u32 = 0;
    for (0..count) |i| {
        scenes[i] = self.viewScene(window.device, i) catch |err| {
            std.log.err("split-screen view {d} unavailable: {s}", .{ i + 1, @errorName(err) });
            self.view_count = i;
            break;
        };
    }
    const shown = @max(1, @min(count, self.view_count));
    // One per-frame upload budget for all views, offered to each view first in turn.
    var budget: usize = options.upload_budget;
    for (0..shown) |j| {
        const i = (@as(usize, @intCast(self.frames % shown)) + j) % shown;
        const view = &self.views[i];
        const r = viewRect(i, shown);
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        const x0: u32 = @intFromFloat(@round(r.x * w));
        const y0: u32 = @intFromFloat(@round(r.y * h));
        const x1: u32 = @intFromFloat(@round((r.x + r.w) * w));
        const y1: u32 = @intFromFloat(@round((r.y + r.h) * h));
        pixels[i] = .{ x0, y0, @max(1, x1 - x0), @max(1, y1 - y0) };
        const vp = view.camera.viewProjection(@as(f32, @floatFromInt(pixels[i][2])) / @as(f32, @floatFromInt(pixels[i][3])));
        const frame = Frame{
            .vp = vp,
            .eye = .{ view.camera.position.x(), view.camera.position.y(), view.camera.position.z(), 1 },
            .light_direction = light.direction ++ [_]f32{0},
            .light_color = light.color ++ [_]f32{0},
            .ambient_sky = light.ambient_sky ++ [_]f32{0},
            .ambient_ground = light.ambient_ground ++ [_]f32{0},
            .horizon = light.horizon ++ [_]f32{light.night},
            .planes = Visibility.frustumPlanes(vp),
        };
        if (i == 0) if (self.field) |*f| {
            // Stream instances under their own byte budget, then plan visible cells. Uploads go
            // through the frame's encoder, which copies into Mach's staging page immediately and
            // shares it with terrain uploads; a separate queue write would claim another 64 MiB
            // staging page per frame in flight, which Mach's pool keeps for the session.
            if (f.nextUpload(options.field_upload)) |u| {
                encoder.writeBuffer(self.field_buffer.?, @as(u64, u.first) * @sizeOf(Instance), u.data);
                f.commit(@intCast(u.data.len));
                if (f.resident()) self.field_resident_frame = self.frames;
            }
            self.field_last = f.plan(.{ view.camera.position.x(), view.camera.position.y(), view.camera.position.z() }, vp);
        };
        scenes[i].prepare(window.queue, view.camera, vp, self.culling, budget, &self.modifications, self.props[0..self.prop_count], view.hide_owner);
        budget -= scenes[i].upload_bytes;
        encoder.writeBuffer(self.uniforms[i].?, 0, &[_]Frame{frame});
        encoder.writeBuffer(self.instance_buffers[i].?, 0, scenes[i].instances[0..scenes[i].instance_count]);
        objects += scenes[i].instance_count - 1;
    }
    self.buildOverlay(objects, window.width, window.height, shown);
    if (self.overlay.len > 0) encoder.writeBuffer(self.overlay_buffer.?, 0, self.overlay.vertices[0..self.overlay.len]);
    const pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{.{ .view = back, .load_op = .clear, .store_op = .store, .clear_value = .{ .r = light.horizon[0], .g = light.horizon[1], .b = light.horizon[2], .a = 1 } }},
        .depth_stencil_attachment = &.{ .view = self.depth_view.?, .depth_load_op = .clear, .depth_store_op = .store, .depth_clear_value = 0 },
    }));
    defer pass.release();
    pass.setPipeline(self.pipeline.?);
    for (0..shown) |i| {
        const px = pixels[i];
        pass.setViewport(@floatFromInt(px[0]), @floatFromInt(px[1]), @floatFromInt(px[2]), @floatFromInt(px[3]), 0, 1);
        pass.setScissorRect(px[0], px[1], px[2], px[3]);
        pass.setBindGroup(0, self.bind_groups[i].?, &.{});
        pass.setVertexBuffer(1, self.instance_buffers[i].?, 0, Scene.max_instances * @sizeOf(Instance));
        scenes[i].draw(pass);
        self.characters.draw(pass, self.views[i].hide_owner);
        if (i == 0) if (self.field != null) {
            pass.setVertexBuffer(1, self.field_buffer.?, 0, self.field.?.gpuBytes());
            const near = self.scene.gpuMesh(self.scene.catalog.content.crate);
            const far = self.scene.gpuMesh(self.scene.catalog.content.block);
            for (self.field_last.slice()) |run| if (if (run.lod == .near) near else far) |mesh| mesh.draw(pass, run.count, run.first);
        };
    }
    pass.end();
    {
        // Depth is shared across views, so the seams between them draw as ink dividers.
        const outline = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{ .color_attachments = &.{.{ .view = back, .load_op = .load, .store_op = .store, .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 } }} }));
        defer outline.release();
        outline.setPipeline(self.outline_pipeline.?);
        outline.setBindGroup(0, self.outline_bind_group.?, &.{});
        outline.draw(3, 1, 0, 0);
        outline.end();
    }
    if (self.overlay.len > 0) {
        const hud = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{ .color_attachments = &.{.{ .view = back, .load_op = .load, .store_op = .store, .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 } }} }));
        defer hud.release();
        hud.setPipeline(self.overlay_pipeline.?);
        hud.setVertexBuffer(0, self.overlay_buffer.?, 0, self.overlay.len * @sizeOf(Overlay.Vertex));
        hud.draw(@intCast(self.overlay.len), 1, 0, 0);
        hud.end();
    }
    if (capturing) {
        const bind = window.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = self.capture_layout.?, .entries = &.{
            gpu.BindGroup.Entry.initTextureView(0, self.capture_view.?),
            gpu.BindGroup.Entry.initBuffer(1, self.capture_buffer.?, 0, @as(u64, self.capture_size[0]) * self.capture_size[1] * 4, 0),
        } }));
        defer bind.release();
        const compute = encoder.beginComputePass(null);
        defer compute.release();
        compute.setPipeline(self.capture_pipeline.?);
        compute.setBindGroup(0, bind, null);
        compute.dispatchWorkgroups((self.capture_size[0] + 7) / 8, (self.capture_size[1] + 7) / 8, 1);
        compute.end();
    }
    const command = encoder.finish(&.{});
    defer command.release();
    window.queue.submit(&.{command});
    if (capturing) {
        self.capture_requested = true;
        self.capture_buffer.?.mapAsync(.{ .read = true }, 0, @as(usize, self.capture_size[0]) * self.capture_size[1] * 4, self, struct {
            inline fn done(r: *Renderer, status: gpu.Buffer.MapAsyncStatus) void {
                if (status == .success) r.capture_ready.store(true, .release);
            }
        }.done);
    }
    if (options.benchmark_frames == 0 or self.frames >= Flythrough.warmup_frames) {
        self.intervals.record(elapsed * 1000);
        self.cpu_times.record(cpu_timer.read() * 1000);
        if (self.scene.active_missing > 0) self.underfilled_frames += 1;
        if (self.field != null) {
            self.field_submitted.record(@floatFromInt(self.field_last.instances[0] + self.field_last.instances[1]));
            self.field_runs.record(@floatFromInt(self.field_last.run_count));
            self.field_cells.record(@floatFromInt(self.field_last.visible_cells));
        }
        if (self.frames % 30 == 0) if (Memory.footprint()) |bytes| {
            self.peak_footprint = @max(self.peak_footprint, bytes);
        };
        const eye: [3]f32 = .{ self.views[0].camera.position.x(), self.views[0].camera.position.y(), self.views[0].camera.position.z() };
        for (self.props[0..self.prop_count]) |prop| {
            if (!prop.mesh.eql(self.benchmarkArborMesh())) continue;
            if (prop.effectiveMesh(eye).eql(prop.mesh)) self.arbor_detail_frames += 1 else self.arbor_proxy_frames += 1;
        }
    }
    if (self.frames % 30 == 0) self.percentiles = self.intervals.summary();
    self.frames += 1;
    if (options.benchmark_frames > 0 and self.frames >= options.benchmark_frames + Flythrough.warmup_frames) {
        self.reportBenchmark();
        core.exit();
    }

    if (options.benchmark_frames == 0 and options.smoke_frames > 0 and self.frames >= options.smoke_frames) {
        std.log.info("Smoke complete: {d} frames, {d} submitted objects, {d} simulation ticks", .{ self.frames, objects, self.tick });
        core.exit();
    }
}

fn buildOverlay(self: *Renderer, count: u32, width: u32, height: u32, views: usize) void {
    self.overlay.len = 0;
    self.overlay.width = @floatFromInt(@max(width, 1));
    self.overlay.height = @floatFromInt(@max(height, 1));
    const ink: [4]f32 = .{ 0.70, 0.84, 0.86, 1 };
    const cyan: [4]f32 = .{ 0.24, 0.88, 0.82, 1 };
    var p1: Rect = undefined;
    for (self.views[0..views], 0..) |view, i| {
        const f = viewRect(i, views);
        const r: Rect = .{ .x = f.x * self.overlay.width, .y = f.y * self.overlay.height, .w = f.w * self.overlay.width, .h = f.h * self.overlay.height };
        if (i == 0) p1 = r;
        if (view.crosshair) {
            const cx = r.x + r.w / 2;
            const cy = r.y + r.h / 2;
            self.overlay.rect(cx - 7, cy - 1, 14, 2, if (i == 0) cyan else view.accent);
            self.overlay.rect(cx - 1, cy - 7, 2, 14, if (i == 0) cyan else view.accent);
        }
        if (i > 0) for (view.lines, 0..) |line, k| if (line.len > 0) {
            self.overlay.text(r.x + 30, r.y + r.h - 58 + @as(f32, @floatFromInt(k)) * 18, line.slice(), if (k == 0) view.accent else ink);
        };
        // Dividers along the top and left edges of views that do not touch the window edge.
        if (f.y > 0) self.overlay.rect(r.x, r.y - 1, r.w, 2, .{ 0.02, 0.035, 0.05, 1 });
        if (f.x > 0) self.overlay.rect(r.x - 1, r.y, 2, r.h, .{ 0.02, 0.035, 0.05, 1 });
    }
    // Interaction status stays visible with metrics hidden.
    const status_y = p1.y + p1.h - 76;
    for (self.hud_lines, 0..) |line, i| if (line.len > 0) {
        self.overlay.text(p1.x + 30, status_y + @as(f32, @floatFromInt(i)) * 18, line.slice(), if (i == 0) cyan else ink);
    };
    if (self.panel_count > 0) {
        const x = p1.x + p1.w - 16 - 520;
        const h = @as(f32, @floatFromInt(self.panel_count)) * 18 + 22;
        self.overlay.rect(x, 16, 520, h, .{ 0.02, 0.035, 0.05, 1 });
        self.overlay.rect(x, 16, 3, h, cyan);
        for (self.panel[0..self.panel_count], 0..) |line, i| {
            self.overlay.text(x + 14, 28 + @as(f32, @floatFromInt(i)) * 18, line.slice(), if (i == 0) cyan else ink);
        }
    }
    if (!self.show_metrics) return;
    self.overlay.rect(16, 16, 448, 296, .{ 0.02, 0.035, 0.05, 1 });
    self.overlay.rect(16, 16, 3, 296, cyan);
    self.overlay.text(30, 30, "HEAVY WATER / PROCEDURAL FRONTIER", cyan);
    var buffer: [128]u8 = undefined;
    self.overlay.text(30, 51, std.fmt.bufPrint(&buffer, "FPS {d:.0}  FRAME {d:.2} MS", .{ 1000 / @max(self.frame_ms, 0.001), self.frame_ms }) catch unreachable, ink);
    self.overlay.text(30, 69, std.fmt.bufPrint(&buffer, "P50 {d:.1}  P95 {d:.1}  P99 {d:.1} MS", .{ self.percentiles.p50, self.percentiles.p95, self.percentiles.p99 }) catch unreachable, ink);
    self.overlay.text(30, 87, std.fmt.bufPrint(&buffer, "CHUNKS GPU {d}/25  CACHE {d}/49  ACTIVE {d}", .{ self.scene.resident_count, self.scene.stats.ready, self.scene.stats.active }) catch unreachable, ink);
    self.overlay.text(30, 105, std.fmt.bufPrint(&buffer, "QUEUED {d}  GENERATED {d}  CANCEL {d}", .{ self.scene.stats.queued, self.scene.stats.generated, self.scene.stats.canceled }) catch unreachable, ink);
    self.overlay.text(30, 123, std.fmt.bufPrint(&buffer, "UPLOAD {d} KIB  CPU POOL {d} KIB", .{ self.scene.upload_bytes / 1024, self.scene.stats.cpu_bytes / 1024 }) catch unreachable, ink);
    self.overlay.text(30, 141, std.fmt.bufPrint(&buffer, "OBJECTS {d}  TERRAIN DRAWS {d}", .{ count, self.scene.terrain_draws }) catch unreachable, ink);
    if (self.field) |f| {
        self.overlay.text(30, 159, std.fmt.bufPrint(&buffer, "FIELD {d}K  DRAWN {d}K  RUNS {d}  CELLS {d}", .{ f.count / 1000, (self.field_last.instances[0] + self.field_last.instances[1]) / 1000, self.field_last.run_count, self.field_last.visible_cells }) catch unreachable, cyan);
    } else self.overlay.text(30, 159, std.fmt.bufPrint(&buffer, "SEED {d}  GEN {d}", .{ self.seed, Seed.generator_version }) catch unreachable, ink);
    self.overlay.text(30, 185, "WASD MOVE  SPACE JUMP/JET  SHIFT SPRINT", ink);
    self.overlay.text(30, 203, "CTRL ROLL  X STOMP  G GRAPPLE  B TRAVERSAL", ink);
    self.overlay.text(30, 221, "F MANTLE  V WALK/FLY  R RESET  ESC", ink);
    self.overlay.text(30, 239, "CLICK LOOK/GRAB  RMB SALVAGE  F2 VIEW", ink);
    self.overlay.text(30, 257, "F4 CHARACTER  F5 SAVE  F9 LOAD  F6 GUEST", ink);
    self.overlay.text(30, 275, if (self.culling) "F1 HUD  C CULLING ON  PAD MENU JOINS" else "F1 HUD  C CULLING OFF  PAD MENU JOINS", cyan);
}

fn prepareCapture(self: *Renderer, device: *gpu.Device, format: gpu.Texture.Format) void {
    self.capture_size = .{ self.width, self.height };
    self.capture_texture = device.createTexture(&.{ .label = "capture", .size = .{ .width = self.width, .height = self.height }, .format = format, .usage = .{ .render_attachment = true, .texture_binding = true } });
    self.capture_view = self.capture_texture.?.createView(&.{});
    self.capture_buffer = device.createBuffer(&.{ .label = "capture readback", .size = @as(u64, self.width) * self.height * 4, .usage = .{ .storage = true, .map_read = true } });
    const shader = device.createShaderModuleWGSL("capture.wgsl", @embedFile("capture.wgsl"));
    defer shader.release();
    self.capture_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{ .entries = &.{
        gpu.BindGroupLayout.Entry.initTexture(0, .{ .compute = true }, .float, .dimension_2d, false),
        gpu.BindGroupLayout.Entry.initBuffer(1, .{ .compute = true }, .storage, false, 0),
    } }));
    const layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{ .bind_group_layouts = &.{self.capture_layout.?} }));
    defer layout.release();
    self.capture_pipeline = device.createComputePipeline(&.{ .label = "capture", .layout = layout, .compute = .{ .module = shader, .entry_point = "main" } });
}

fn finishCapture(self: *Renderer, core: *mach.Core) void {
    self.capture_ready.store(false, .release);
    const n = @as(usize, self.capture_size[0]) * self.capture_size[1];
    const pixels = self.capture_buffer.?.getConstMappedRange(u32, 0, n) orelse {
        std.log.err("capture: buffer not mapped", .{});
        return core.exit();
    };
    const bmp = @import("Capture.zig").encodeBmp(self.allocator, self.capture_size[0], self.capture_size[1], pixels) catch return core.exit();
    defer self.allocator.free(bmp);
    std.Io.Dir.cwd().createDirPath(self.io, "zig-out") catch {};
    std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = "zig-out/capture.bmp", .data = bmp }) catch |err| std.log.err("capture: {s}", .{@errorName(err)});
    std.log.info("Captured frame {d} ({d}x{d}) to zig-out/capture.bmp", .{ options.capture_frame, self.capture_size[0], self.capture_size[1] });
    core.exit();
}

fn reportBenchmark(self: *Renderer) void {
    const interval = self.intervals.summary();
    const cpu = self.cpu_times.summary();
    // Scale workload and memory. GPU execution time needs timestamp queries, which the pinned
    // Mach Metal backend does not implement, so it is reported as unavailable, not estimated.
    const submitted = self.field_submitted.summary();
    const runs = self.field_runs.summary();
    const cells = self.field_cells.summary();
    if (Memory.footprint()) |bytes| self.peak_footprint = @max(self.peak_footprint, bytes);
    std.log.info("REPORT {{\"scale_objects\":{d},\"field_generation_ms\":{d:.1},\"field_gpu_bytes\":{d},\"field_cpu_peak_bytes\":{d},\"field_cpu_bytes_now\":{d},\"field_upload_budget_bytes\":{d},\"field_resident_frame\":{d},\"field_submitted_p50\":{d:.0},\"field_submitted_p99\":{d:.0},\"field_submitted_max\":{d:.0},\"field_runs_p50\":{d:.0},\"field_runs_p99\":{d:.0},\"field_cells_p50\":{d:.0},\"field_cells_p99\":{d:.0},\"peak_footprint_bytes\":{d},\"asset_upload_budget_bytes\":{d},\"peak_late_upload_bytes\":{d},\"largest_single_late_upload_bytes\":{d},\"late_uploads\":{d},\"pack_assets\":{d},\"pack_bytes\":{d},\"pack_requested_frame\":{d},\"pack_installed\":{d},\"pack_ready_frame\":{d},\"gpu_time\":\"unavailable\"}}", .{
        options.scale_objects,
        if (self.field) |f| f.generation_ms else 0,
        if (self.field) |f| f.gpuBytes() else 0,
        self.field_peak_cpu_bytes,
        if (self.field) |f| f.cpuBytes() else 0,
        options.field_upload,
        if (self.field_resident_frame) |f| @as(i64, @intCast(f)) else -1,
        submitted.p50,
        submitted.p99,
        submitted.worst,
        runs.p50,
        runs.p99,
        cells.p50,
        cells.p99,
        self.peak_footprint,
        options.asset_upload,
        self.peak_late_upload,
        self.largest_late_mesh,
        self.total_late_uploads,
        options.pack_stress,
        self.pack_bytes,
        self.pack_requested_frame,
        self.pack_installed,
        self.pack_ready_frame,
    });
    std.log.info("BENCHMARK {{\"seed\":{d},\"generator\":{d},\"frames\":{d},\"interval_p50_ms\":{d:.3},\"interval_p95_ms\":{d:.3},\"interval_p99_ms\":{d:.3},\"cpu_p50_ms\":{d:.3},\"cpu_p95_ms\":{d:.3},\"cpu_p99_ms\":{d:.3},\"generated\":{d},\"canceled\":{d},\"uploads\":{d},\"evictions\":{d},\"chunk_crossings\":{d},\"peak_upload_bytes\":{d},\"upload_budget_bytes\":{d},\"cpu_pool_bytes\":{d},\"gpu_terrain_pool_bytes\":{d},\"pool_allocations\":{d},\"gpu_pool_allocations\":{d},\"peak_resident_chunks\":{d},\"underfilled_frames\":{d},\"arbor_detail_frames\":{d},\"arbor_proxy_frames\":{d}}}", .{
        self.seed,                         Seed.generator_version,          self.intervals.total,           interval.p50,            interval.p95,              interval.p99,                 cpu.p50,               cpu.p95,                    cpu.p99,
        self.scene.stats.generated,        self.scene.stats.canceled,       self.scene.uploads,             self.scene.evictions,    self.scene.center_changes, self.scene.peak_upload_bytes, options.upload_budget, self.scene.stats.cpu_bytes, Scene.gpu_pool_bytes,
        self.scene.stats.pool_allocations, self.scene.gpu_pool_allocations, self.scene.peak_resident_count, self.underfilled_frames, self.arbor_detail_frames,  self.arbor_proxy_frames,
    });
}

pub fn deinit(self: *Renderer) void {
    self.characters.deinit(self.allocator);
    if (self.outline_bind_group) |p| p.release();
    if (self.outline_layout) |p| p.release();
    if (self.outline_pipeline) |p| p.release();
    if (self.depth_view) |p| p.release();
    if (self.depth) |p| p.release();
    for (0..max_views) |i| self.releaseViewResources(i);
    if (self.scene_layout) |p| p.release();
    if (self.pipeline) |p| p.release();
    if (self.overlay_pipeline) |p| p.release();
    if (self.field_buffer) |p| p.release();
    if (self.capture_pipeline) |p| p.release();
    if (self.capture_layout) |p| p.release();
    if (self.capture_view) |p| p.release();
    if (self.capture_texture) |p| p.release();
    if (self.capture_buffer) |p| p.release();
    if (self.field) |*f| f.deinit();
    self.scene.destroy();
    for (self.extra_scenes) |maybe| if (maybe) |scene| {
        scene.destroy();
        self.allocator.destroy(scene);
    };
    if (self.overlay_buffer) |p| p.release();
    if (self.texture_view) |p| p.release();
    if (self.texture) |p| p.release();
    if (self.sampler) |p| p.release();
}
