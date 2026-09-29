const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Mesh = @import("Mesh.zig");
const Chunk = @import("../procedural/Chunk.zig");
const Material = @import("Material.zig");
const Visibility = @import("Visibility.zig");
const Overlay = @import("Overlay.zig");
const options = @import("options");
const Renderer = @This();

pub const mach_module = .renderer;
pub const mach_systems = .{ .init, .render, .deinit };
const Instance = extern struct { translation_scale: [4]f32, tint: [4]f32 };
const Frame = extern struct { vp: mach.math.Mat4x4, eye: [4]f32 };
const GpuMesh = struct {
    vertices: *gpu.Buffer,
    indices: *gpu.Buffer,
    vertex_bytes: usize,
    index_count: u32,

    fn upload(device: *gpu.Device, queue: *gpu.Queue, mesh: Mesh) GpuMesh {
        const vb = device.createBuffer(&.{ .label = "mesh vertices", .size = mesh.vertices.len * @sizeOf(Mesh.Vertex), .usage = .{ .vertex = true, .copy_dst = true } });
        const ib = device.createBuffer(&.{ .label = "mesh indices", .size = mesh.indices.len * 4, .usage = .{ .index = true, .copy_dst = true } });
        queue.writeBuffer(vb, 0, mesh.vertices);
        queue.writeBuffer(ib, 0, mesh.indices);
        return .{ .vertices = vb, .indices = ib, .vertex_bytes = mesh.vertices.len * @sizeOf(Mesh.Vertex), .index_count = @intCast(mesh.indices.len) };
    }
    fn draw(self: GpuMesh, pass: *gpu.RenderPassEncoder, instances: u32, first: u32) void {
        pass.setVertexBuffer(0, self.vertices, 0, self.vertex_bytes);
        pass.setIndexBuffer(self.indices, .uint32, 0, self.index_count * 4);
        pass.drawIndexed(self.index_count, instances, 0, 0, first);
    }
    fn deinit(self: GpuMesh) void {
        self.indices.release();
        self.vertices.release();
    }
};

// Written by App.publish only inside Core's render mutex.
camera: Camera = .{},
tick: u64 = 0,
show_metrics: bool = true,
culling: bool = false,
// Immutable world presentation copied before either thread starts.
instances: [World.max_objects + 1]Instance = undefined,
visible: [World.max_objects + 1]Instance = undefined,
pipeline: ?*gpu.RenderPipeline = null,
overlay_pipeline: ?*gpu.RenderPipeline = null,
terrain: ?GpuMesh = null,
relic: ?GpuMesh = null,
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

pub fn init(self: *Renderer, world: *World, io: std.Io) void {
    self.* = .{ .timer = mach.time.Timer.start(io) };
    self.instances[0] = .{ .translation_scale = .{ 0, 0, 0, 1 }, .tint = Material.terrain };
    world.objects.lock();
    defer world.objects.unlock();
    var iter = world.objects.slice();
    var i: usize = 1;
    while (iter.next()) |id| : (i += 1) {
        const object = world.objects.getValue(id);
        self.instances[i] = .{ .translation_scale = object.transform.toInstance(), .tint = object.tint };
    }
    std.debug.assert(i == World.max_objects + 1);
}

fn setup(self: *Renderer, core: *mach.Core, allocator: std.mem.Allocator) !void {
    const window = core.windows.getValue(core.window);
    const device = window.device;
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
    self.instance_buffer = device.createBuffer(&.{ .label = "instances", .size = @sizeOf(@TypeOf(self.instances)), .usage = .{ .vertex = true, .copy_dst = true } });
    self.texture = device.createTexture(&.{ .label = "surface checker", .size = .{ .width = 2, .height = 2 }, .format = .rgba8_unorm, .usage = .{ .texture_binding = true, .copy_dst = true } });
    self.texture_view = self.texture.?.createView(&.{});
    self.sampler = device.createSampler(&.{ .address_mode_u = .repeat, .address_mode_v = .repeat, .mag_filter = .nearest, .min_filter = .nearest });
    const pixels = [_]u8{ 240, 240, 240, 255, 190, 200, 205, 255, 190, 200, 205, 255, 240, 240, 240, 255 };
    window.queue.writeTexture(&.{ .texture = self.texture.? }, &.{ .bytes_per_row = 8, .rows_per_image = 2 }, &.{ .width = 2, .height = 2 }, &pixels);
    self.bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{ .layout = layout, .entries = &.{
        gpu.BindGroup.Entry.initBuffer(0, self.uniform.?, 0, @sizeOf(Frame), @sizeOf(Frame)),
        gpu.BindGroup.Entry.initTextureView(1, self.texture_view.?),
        gpu.BindGroup.Entry.initSampler(2, self.sampler.?),
    } }));
    const buffers = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout.init(.{ .array_stride = @sizeOf(Mesh.Vertex), .attributes = &.{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = 12, .shader_location = 1 },
            .{ .format = .float32x2, .offset = 24, .shader_location = 2 },
        } }),
        gpu.VertexBufferLayout.init(.{ .array_stride = @sizeOf(Instance), .step_mode = .instance, .attributes = &.{
            .{ .format = .float32x4, .offset = 0, .shader_location = 3 },
            .{ .format = .float32x4, .offset = 16, .shader_location = 4 },
        } }),
    };
    const fragment = gpu.FragmentState.init(.{ .module = shader, .entry_point = "frag_main", .targets = &.{.{ .format = window.framebuffer_format }} });
    self.pipeline = device.createRenderPipeline(&.{
        .label = "opaque textured instances",
        .layout = pipeline_layout,
        .vertex = gpu.VertexState.init(.{ .module = shader, .entry_point = "vertex_main", .buffers = &buffers }),
        .fragment = &fragment,
        .primitive = .{ .cull_mode = .none },
        .depth_stencil = &.{ .format = .depth32_float, .depth_write_enabled = .true, .depth_compare = .less },
    });
    const terrain = try Chunk.generate(allocator, options.seed, 0, 0);
    defer terrain.deinit(allocator);
    self.terrain = GpuMesh.upload(device, window.queue, terrain);
    const relic = try Mesh.cube(allocator);
    defer relic.deinit(allocator);
    self.relic = GpuMesh.upload(device, window.queue, relic);

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
    self.overlay_buffer = device.createBuffer(&.{ .label = "debug overlay", .size = Overlay.capacity * @sizeOf(Overlay.Vertex), .usage = .{ .vertex = true, .copy_dst = true } });
    std.log.info("Heavy Water: seed={d}, generator=1, objects={d}, terrain triangles={d}", .{ options.seed, World.max_objects, self.terrain.?.index_count / 3 });
    self.timer.reset();
}

fn resize(self: *Renderer, device: *gpu.Device, width: u32, height: u32) void {
    if (self.width == width and self.height == height) return;
    if (self.depth_view) |v| v.release();
    if (self.depth) |t| t.release();
    self.depth = device.createTexture(&.{ .label = "scene depth", .size = .{ .width = width, .height = height }, .format = .depth32_float, .usage = .{ .render_attachment = true } });
    self.depth_view = self.depth.?.createView(&.{});
    self.width = width;
    self.height = height;
}

pub fn render(self: *Renderer, core: *mach.Core, allocator: std.mem.Allocator) !void {
    if (self.pipeline == null) try self.setup(core, allocator);
    const window = core.windows.getValue(core.window);
    if (window.framebuffer_width == 0 or window.framebuffer_height == 0) return;
    const back = window.swap_chain.getCurrentTextureView() orelse return;
    defer back.release();
    self.resize(window.device, window.framebuffer_width, window.framebuffer_height);
    const elapsed = self.timer.lap();
    self.frame_ms = if (self.frames == 0) elapsed * 1000 else self.frame_ms * 0.95 + elapsed * 50;
    const vp = self.camera.viewProjection(@as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height)));
    const frame = Frame{ .vp = vp, .eye = .{ self.camera.position.x(), self.camera.position.y(), self.camera.position.z(), 1 } };
    self.visible[0] = self.instances[0];
    var count: u32 = 1;
    for (self.instances[1..]) |instance| {
        const t = instance.translation_scale;
        if (self.culling and !Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3], t[2] }, 1.225 * t[3])) continue;
        self.visible[count] = instance;
        count += 1;
    }
    const encoder = window.device.createCommandEncoder(&.{ .label = "frame" });
    defer encoder.release();
    encoder.writeBuffer(self.uniform.?, 0, &[_]Frame{frame});
    encoder.writeBuffer(self.instance_buffer.?, 0, self.visible[0..count]);
    if (self.show_metrics) {
        self.buildOverlay(count - 1, window.width, window.height);
        encoder.writeBuffer(self.overlay_buffer.?, 0, self.overlay.vertices[0..self.overlay.len]);
    }
    const pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{.{ .view = back, .load_op = .clear, .store_op = .store, .clear_value = .{ .r = 0.055, .g = 0.10, .b = 0.14, .a = 1 } }},
        .depth_stencil_attachment = &.{ .view = self.depth_view.?, .depth_load_op = .clear, .depth_store_op = .discard, .depth_clear_value = 1 },
    }));
    defer pass.release();
    pass.setPipeline(self.pipeline.?);
    pass.setBindGroup(0, self.bind_group.?, &.{});
    pass.setVertexBuffer(1, self.instance_buffer.?, 0, @sizeOf(@TypeOf(self.instances)));
    self.terrain.?.draw(pass, 1, 0);
    if (count > 1) self.relic.?.draw(pass, count - 1, 1);
    pass.end();
    if (self.show_metrics) {
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
    self.frames += 1;
    if (options.smoke_frames > 0 and self.frames >= options.smoke_frames) {
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
    self.overlay.rect(16, 16, 368, 152, .{ 0.02, 0.035, 0.05, 1 });
    self.overlay.rect(16, 16, 3, 152, cyan);
    self.overlay.text(30, 30, "HEAVY WATER / ENGINE FIELD TEST", cyan);
    var buffer: [96]u8 = undefined;
    const timing = std.fmt.bufPrint(&buffer, "FPS {d:.0}  FRAME {d:.2} MS", .{ 1000 / @max(self.frame_ms, 0.001), self.frame_ms }) catch unreachable;
    self.overlay.text(30, 51, timing, ink);
    const objects = std.fmt.bufPrint(&buffer, "OBJECTS {d}/1000  DRAWS {d}", .{ count, @as(u32, if (count > 0) 3 else 2) }) catch unreachable;
    self.overlay.text(30, 69, objects, ink);
    const seed = std.fmt.bufPrint(&buffer, "SEED {d}  GEN 1", .{options.seed}) catch unreachable;
    self.overlay.text(30, 87, seed, ink);
    self.overlay.text(30, 108, "WASD MOVE  QE RISE  SHIFT FAST", ink);
    self.overlay.text(30, 126, "CLICK LOOK  ESC RELEASE  R RESET", ink);
    self.overlay.text(30, 144, if (self.culling) "F1 HUD  C CULLING ON" else "F1 HUD  C CULLING OFF", cyan);
}

pub fn deinit(self: *Renderer) void {
    if (self.depth_view) |p| p.release();
    if (self.depth) |p| p.release();
    if (self.bind_group) |p| p.release();
    if (self.pipeline) |p| p.release();
    if (self.overlay_pipeline) |p| p.release();
    if (self.terrain) |m| m.deinit();
    if (self.relic) |m| m.deinit();
    if (self.uniform) |p| p.release();
    if (self.instance_buffer) |p| p.release();
    if (self.overlay_buffer) |p| p.release();
    if (self.texture_view) |p| p.release();
    if (self.texture) |p| p.release();
    if (self.sampler) |p| p.release();
}
