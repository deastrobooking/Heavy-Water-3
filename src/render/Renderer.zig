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

pub const mach_module = .renderer;
pub const mach_systems = .{ .init, .render, .deinit };
pub const panel_capacity = 16;
const Instance = Scene.Instance;
comptime {
    if (options.upload_budget < Scene.chunk_bytes) @compileError("upload-budget-kib must be at least 278");
}
const Sky = @import("../engine/Sky.zig");
/// Matches `Frame` in scene.wgsl.
const Frame = extern struct { vp: mach.math.Mat4x4, eye: [4]f32, light_direction: [4]f32, light_color: [4]f32, ambient_sky: [4]f32, ambient_ground: [4]f32, horizon: [4]f32 };
// Written by App.publish only inside Core's render mutex.
camera: Camera = .{},
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
crosshair: bool = false,
scene: Scene = undefined,
seed: u64 = 0,
intervals: FrameStats = .{},
cpu_times: FrameStats = .{},
percentiles: FrameStats.Summary = .{ .p50 = 0, .p95 = 0, .p99 = 0, .worst = 0, .mean = 0 },
pipeline: ?*gpu.RenderPipeline = null,
overlay_pipeline: ?*gpu.RenderPipeline = null,
uniform: ?*gpu.Buffer = null,
instance_buffer: ?*gpu.Buffer = null,
overlay_buffer: ?*gpu.Buffer = null,
bind_group: ?*gpu.BindGroup = null,
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

pub fn init(self: *Renderer, world: *World, io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .timer = mach.time.Timer.start(io), .seed = world.seed, .scene = try Scene.init(allocator, io, world.seed, &world.catalog) };
}

/// Async validation errors from the device driver; the WebGPU-style API otherwise reports
/// success even when a descriptor is rejected, so this is the only observable failure path.
fn onDeviceError(_: void, typ: gpu.ErrorType, message: [*:0]const u8) callconv(.@"inline") void {
    std.log.err("GPU device error ({s}): {s}", .{ @tagName(typ), message });
}

fn setup(self: *Renderer, core: *mach.Core) !void {
    const window = core.windows.getValue(core.window);
    const device = window.device;
    device.setUncapturedErrorCallback({}, onDeviceError);
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
    defer layout.release();
    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{ .bind_group_layouts = &.{layout} }));
    defer pipeline_layout.release();
    self.uniform = device.createBuffer(&.{ .label = "camera", .size = @sizeOf(Frame), .usage = .{ .uniform = true, .copy_dst = true } });
    errdefer { self.uniform.?.release(); self.uniform = null; }
    self.instance_buffer = device.createBuffer(&.{ .label = "instances", .size = Scene.max_instances * @sizeOf(Instance), .usage = .{ .vertex = true, .copy_dst = true } });
    errdefer { self.instance_buffer.?.release(); self.instance_buffer = null; }
    self.texture = device.createTexture(&.{ .label = "surface checker", .size = .{ .width = 2, .height = 2 }, .format = .rgba8_unorm, .usage = .{ .texture_binding = true, .copy_dst = true } });
    errdefer { self.texture.?.release(); self.texture = null; }
    self.texture_view = self.texture.?.createView(&.{});
    errdefer { self.texture_view.?.release(); self.texture_view = null; }
    self.sampler = device.createSampler(&.{ .address_mode_u = .repeat, .address_mode_v = .repeat, .mag_filter = .nearest, .min_filter = .nearest });
    errdefer { self.sampler.?.release(); self.sampler = null; }
    const pixels = [_]u8{ 240, 240, 240, 255, 190, 200, 205, 255, 190, 200, 205, 255, 240, 240, 240, 255 };
    window.queue.writeTexture(&.{ .texture = self.texture.? }, &.{ .bytes_per_row = 8, .rows_per_image = 2 }, &.{ .width = 2, .height = 2 }, &pixels);
    self.bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = layout, .entries = &.{
        gpu.BindGroup.Entry.initBuffer(0, self.uniform.?, 0, @sizeOf(Frame), @sizeOf(Frame)),
        gpu.BindGroup.Entry.initTextureView(1, self.texture_view.?),
        gpu.BindGroup.Entry.initSampler(2, self.sampler.?),
    } }));
    errdefer { self.bind_group.?.release(); self.bind_group = null; }
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
    errdefer { self.pipeline.?.release(); self.pipeline = null; }
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
    errdefer { self.overlay_pipeline.?.release(); self.overlay_pipeline = null; }
    self.overlay_buffer = device.createBuffer(&.{ .label = "debug overlay", .size = Overlay.capacity * @sizeOf(Overlay.Vertex), .usage = .{ .vertex = true, .copy_dst = true } });
    errdefer { self.overlay_buffer.?.release(); self.overlay_buffer = null; }
    std.log.info("Heavy Water: seed={d}, generator={d}, streaming pool=49 chunks, GPU pool=25 chunks, upload budget={d}", .{ self.seed, Seed.generator_version, options.upload_budget });
    self.timer.reset();
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

pub fn render(self: *Renderer, core: *mach.Core) !void {
    // A setup failure must not reach Mach's callback dispatch: it panics on any returned error,
    // skipping App.stop/Renderer.deinit and leaking the streaming worker and GPU resources.
    if (self.pipeline == null) self.setup(core) catch |err| {
        std.log.err("renderer setup failed, exiting: {s}", .{@errorName(err)});
        core.exit();
        return;
    };
    var cpu_timer = mach.time.Timer.start(self.timer.io);
    if (options.benchmark_frames > 0) self.camera = Flythrough.camera(self.frames -| Flythrough.warmup_frames, options.benchmark_frames);
    const window = core.windows.getValue(core.window);
    if (window.framebuffer_width == 0 or window.framebuffer_height == 0) return;
    const back = window.swap_chain.getCurrentTextureView() orelse return;
    defer back.release();
    self.resize(window.device, window.framebuffer_width, window.framebuffer_height);
    const elapsed = self.timer.lap();
    self.frame_ms = if (self.frames == 0) elapsed * 1000 else self.frame_ms * 0.95 + elapsed * 50;
    const vp = self.camera.viewProjection(@as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height)));
    const light = Sky.at(self.time_of_day);
    const frame = Frame{
        .vp = vp,
        .eye = .{ self.camera.position.x(), self.camera.position.y(), self.camera.position.z(), 1 },
        .light_direction = light.direction ++ [_]f32{0},
        .light_color = light.color ++ [_]f32{0},
        .ambient_sky = light.ambient_sky ++ [_]f32{0},
        .ambient_ground = light.ambient_ground ++ [_]f32{0},
        .horizon = light.horizon ++ [_]f32{light.night},
    };
    self.scene.prepare(window.queue, self.camera, vp, self.culling, options.upload_budget, &self.modifications, self.props[0..self.prop_count]);
    const count = self.scene.instance_count;
    const encoder = window.device.createCommandEncoder(&.{ .label = "frame" });
    defer encoder.release();
    encoder.writeBuffer(self.uniform.?, 0, &[_]Frame{frame});
    encoder.writeBuffer(self.instance_buffer.?, 0, self.scene.instances[0..count]);
    self.buildOverlay(count - 1, window.width, window.height);
    if (self.overlay.len > 0) encoder.writeBuffer(self.overlay_buffer.?, 0, self.overlay.vertices[0..self.overlay.len]);
    const pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{.{ .view = back, .load_op = .clear, .store_op = .store, .clear_value = .{ .r = light.horizon[0], .g = light.horizon[1], .b = light.horizon[2], .a = 1 } }},
        .depth_stencil_attachment = &.{ .view = self.depth_view.?, .depth_load_op = .clear, .depth_store_op = .store, .depth_clear_value = 0 },
    }));
    defer pass.release();
    pass.setPipeline(self.pipeline.?);
    pass.setBindGroup(0, self.bind_group.?, &.{});
    pass.setVertexBuffer(1, self.instance_buffer.?, 0, Scene.max_instances * @sizeOf(Instance));
    self.scene.draw(pass);
    pass.end();
    {
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
    const command = encoder.finish(&.{});
    defer command.release();
    window.queue.submit(&.{command});
    if (options.benchmark_frames == 0 or self.frames >= Flythrough.warmup_frames) {
        self.intervals.record(elapsed * 1000);
        self.cpu_times.record(cpu_timer.read() * 1000);
        if (self.scene.active_missing > 0) self.underfilled_frames += 1;
    }
    if (self.frames % 30 == 0) self.percentiles = self.intervals.summary();
    self.frames += 1;
    if (options.benchmark_frames > 0 and self.frames >= options.benchmark_frames + Flythrough.warmup_frames) {
        self.reportBenchmark();
        core.exit();
    }

    if (options.benchmark_frames == 0 and options.smoke_frames > 0 and self.frames >= options.smoke_frames) {
        std.log.info("Smoke complete: {d} frames, {d} submitted objects, {d} simulation ticks", .{ self.frames, count - 1, self.tick });
        core.exit();
    }
}

fn buildOverlay(self: *Renderer, count: u32, width: u32, height: u32) void {
    self.overlay.len = 0;
    self.overlay.width = @floatFromInt(@max(width, 1));
    self.overlay.height = @floatFromInt(@max(height, 1));
    const ink: [4]f32 = .{ 0.70, 0.84, 0.86, 1 };
    const cyan: [4]f32 = .{ 0.24, 0.88, 0.82, 1 };
    if (self.crosshair) {
        const cx = self.overlay.width / 2;
        const cy = self.overlay.height / 2;
        self.overlay.rect(cx - 7, cy - 1, 14, 2, cyan);
        self.overlay.rect(cx - 1, cy - 7, 2, 14, cyan);
    }
    // Interaction status stays visible with metrics hidden.
    const status_y = self.overlay.height - 76;
    for (self.hud_lines, 0..) |line, i| if (line.len > 0) {
        self.overlay.text(30, status_y + @as(f32, @floatFromInt(i)) * 18, line.slice(), if (i == 0) cyan else ink);
    };
    if (self.panel_count > 0) {
        const x = self.overlay.width - 16 - 520;
        const h = @as(f32, @floatFromInt(self.panel_count)) * 18 + 22;
        self.overlay.rect(x, 16, 520, h, .{ 0.02, 0.035, 0.05, 1 });
        self.overlay.rect(x, 16, 3, h, cyan);
        for (self.panel[0..self.panel_count], 0..) |line, i| {
            self.overlay.text(x + 14, 28 + @as(f32, @floatFromInt(i)) * 18, line.slice(), if (i == 0) cyan else ink);
        }
    }
    if (!self.show_metrics) return;
    self.overlay.rect(16, 16, 448, 278, .{ 0.02, 0.035, 0.05, 1 });
    self.overlay.rect(16, 16, 3, 278, cyan);
    self.overlay.text(30, 30, "HEAVY WATER / PROCEDURAL FRONTIER", cyan);
    var buffer: [128]u8 = undefined;
    self.overlay.text(30, 51, std.fmt.bufPrint(&buffer, "FPS {d:.0}  FRAME {d:.2} MS", .{ 1000 / @max(self.frame_ms, 0.001), self.frame_ms }) catch unreachable, ink);
    self.overlay.text(30, 69, std.fmt.bufPrint(&buffer, "P50 {d:.1}  P95 {d:.1}  P99 {d:.1} MS", .{ self.percentiles.p50, self.percentiles.p95, self.percentiles.p99 }) catch unreachable, ink);
    self.overlay.text(30, 87, std.fmt.bufPrint(&buffer, "CHUNKS GPU {d}/25  CACHE {d}/49  ACTIVE {d}", .{ self.scene.resident_count, self.scene.stats.ready, self.scene.stats.active }) catch unreachable, ink);
    self.overlay.text(30, 105, std.fmt.bufPrint(&buffer, "QUEUED {d}  GENERATED {d}  CANCEL {d}", .{ self.scene.stats.queued, self.scene.stats.generated, self.scene.stats.canceled }) catch unreachable, ink);
    self.overlay.text(30, 123, std.fmt.bufPrint(&buffer, "UPLOAD {d} KIB  CPU POOL {d} KIB", .{ self.scene.upload_bytes / 1024, self.scene.stats.cpu_bytes / 1024 }) catch unreachable, ink);
    self.overlay.text(30, 141, std.fmt.bufPrint(&buffer, "OBJECTS {d}  TERRAIN DRAWS {d}", .{ count, self.scene.terrain_draws }) catch unreachable, ink);
    self.overlay.text(30, 159, std.fmt.bufPrint(&buffer, "SEED {d}  GEN {d}", .{ self.seed, Seed.generator_version }) catch unreachable, ink);
    self.overlay.text(30, 185, "WASD MOVE  SPACE JUMP  SHIFT FAST", ink);
    self.overlay.text(30, 203, "V WALK/FLY  QE FLY RISE  R RESET", ink);
    self.overlay.text(30, 221, "CLICK LOOK/GRAB  RMB SALVAGE  ESC", ink);
    self.overlay.text(30, 239, "F2 VIEW  F4 CHARACTER  F5 SAVE  F9 LOAD", ink);
    self.overlay.text(30, 257, if (self.culling) "F1 HUD  C CULLING ON" else "F1 HUD  C CULLING OFF", cyan);
}

fn reportBenchmark(self: *Renderer) void {
    const interval = self.intervals.summary();
    const cpu = self.cpu_times.summary();
    std.log.info("BENCHMARK {{\"seed\":{d},\"generator\":{d},\"frames\":{d},\"interval_p50_ms\":{d:.3},\"interval_p95_ms\":{d:.3},\"interval_p99_ms\":{d:.3},\"cpu_p50_ms\":{d:.3},\"cpu_p95_ms\":{d:.3},\"cpu_p99_ms\":{d:.3},\"generated\":{d},\"canceled\":{d},\"uploads\":{d},\"evictions\":{d},\"chunk_crossings\":{d},\"peak_upload_bytes\":{d},\"upload_budget_bytes\":{d},\"cpu_pool_bytes\":{d},\"gpu_terrain_pool_bytes\":{d},\"pool_allocations\":{d},\"gpu_pool_allocations\":{d},\"peak_resident_chunks\":{d},\"underfilled_frames\":{d}}}", .{
        self.seed,                         Seed.generator_version,          self.intervals.total,           interval.p50,            interval.p95,              interval.p99,                 cpu.p50,               cpu.p95,                    cpu.p99,
        self.scene.stats.generated,        self.scene.stats.canceled,       self.scene.uploads,             self.scene.evictions,    self.scene.center_changes, self.scene.peak_upload_bytes, options.upload_budget, self.scene.stats.cpu_bytes, Scene.gpu_pool_bytes,
        self.scene.stats.pool_allocations, self.scene.gpu_pool_allocations, self.scene.peak_resident_count, self.underfilled_frames,
    });
}

pub fn deinit(self: *Renderer) void {
    if (self.outline_bind_group) |p| p.release();
    if (self.outline_layout) |p| p.release();
    if (self.outline_pipeline) |p| p.release();
    if (self.depth_view) |p| p.release();
    if (self.depth) |p| p.release();
    if (self.bind_group) |p| p.release();
    if (self.pipeline) |p| p.release();
    if (self.overlay_pipeline) |p| p.release();
    self.scene.destroy();
    if (self.uniform) |p| p.release();
    if (self.instance_buffer) |p| p.release();
    if (self.overlay_buffer) |p| p.release();
    if (self.texture_view) |p| p.release();
    if (self.texture) |p| p.release();
    if (self.sampler) |p| p.release();
}
