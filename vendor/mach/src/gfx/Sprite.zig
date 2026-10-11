const std = @import("std");
const mach = @import("../main.zig");
const gpu = mach.gpu;
const gfx = mach.gfx;

const math = mach.math;
const Vec2 = math.Vec2;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;

const Sprite = @This();

pub const mach_module = .mach_gfx_sprite;

pub const mach_systems = .{
    .init,
    .cleanup,
    .snapshot,
    .render,
    .deinit,
};

const Uniforms = extern struct {
    /// The view * orthographic projection matrix
    view_projection: gpu.Mat4x4 align(16),

    /// Total size of the sprite texture in pixels
    texture_size: gpu.Vec2 align(16),
};

const BuiltPipeline = struct {
    render: *gpu.RenderPipeline,
    texture_sampler: *gpu.Sampler,
    texture: *gpu.Texture,
    texture2: ?*gpu.Texture,
    texture3: ?*gpu.Texture,
    texture4: ?*gpu.Texture,
    bind_group: *gpu.BindGroup,
    bind_group_layout: ?*gpu.BindGroupLayout,
    uniforms: *gpu.Buffer,

    // Storage buffers
    transforms: *gpu.Buffer,
    uv_transforms: *gpu.Buffer,
    sizes: *gpu.Buffer,
    buffer_cap: u32,

    fn deinit(p: *const BuiltPipeline) void {
        p.render.release();
        p.texture_sampler.release();
        p.texture.release();
        if (p.texture2) |tex| tex.release();
        if (p.texture3) |tex| tex.release();
        if (p.texture4) |tex| tex.release();
        p.bind_group.release();
        if (p.bind_group_layout) |l| l.release();
        p.uniforms.release();
        p.transforms.release();
        p.uv_transforms.release();
        p.sizes.release();
    }
};

const Objects = mach.Objects(.{ .track_fields = true }, struct {
    /// The sprite model transformation matrix. A sprite is measured in pixel units, starting from
    /// (0, 0) at the top-left corner and extending to the size of the sprite. By default, the world
    /// origin (0, 0) lives at the center of the window.
    ///
    /// Example: in a 500px by 500px window, a sprite located at (0, 0) with size (250, 250) will
    /// cover the top-right hand corner of the window.
    transform: Mat4x4,

    /// UV coordinate transformation matrix describing top-left corner / origin of sprite, in pixels.
    uv_transform: Mat3x3,

    /// The size of the sprite, in pixels.
    size: Vec2,
});

/// A sprite pipeline renders all sprites in its `.render_list`
const Pipelines = mach.Objects(.{ .track_fields = true }, struct {
    /// Which window (device/queue) to use. If not set, this pipeline will not be rendered.
    window: ?mach.ObjectID = null,

    /// Which render pass should be used during rendering. If not set, this pipeline will not be
    /// rendered.
    render_pass: ?*gpu.RenderPassEncoder = null,

    /// Texture to use when rendering. The default shader can handle only one texture input.
    /// Must be specified for a pipeline entity to be valid.
    texture: *gpu.Texture,

    /// View*Projection matrix to use when rendering with this pipeline. This controls both
    /// the size of the 'virtual canvas' which is rendered onto, as well as the 'camera position'.
    ///
    /// By default, the size is configured to be equal to the window size in virtual pixels (e.g.
    /// if the window size is 1920x1080, the virtual canvas will also be that size even if ran on a
    /// HiDPI / Retina display where the actual framebuffer is larger than that.) The origin (0, 0)
    /// is configured to be the center of the window:
    ///
    /// ```
    /// const width_px: f32 = @floatFromInt(window.width);
    /// const height_px: f32 = @floatFromInt(window.height);
    /// const projection = math.Mat4x4.projection2D(.{
    ///     .left = -width_px / 2.0,
    ///     .right = width_px / 2.0,
    ///     .bottom = -height_px / 2.0,
    ///     .top = height_px / 2.0,
    ///     .near = -0.1,
    ///     .far = 100000,
    /// });
    /// const view_projection = projection.mul(&Mat4x4.translate(vec3(0, 0, 0)));
    /// ```
    view_projection: ?Mat4x4 = null,

    /// Optional multi-texturing.
    texture2: ?*gpu.Texture = null,
    texture3: ?*gpu.Texture = null,
    texture4: ?*gpu.Texture = null,

    /// Shader program to use when rendering
    ///
    /// If null, defaults to sprite.wgsl
    shader: ?*gpu.ShaderModule = null,

    /// Whether to use linear (blurry) or nearest (pixelated) upscaling/downscaling.
    ///
    /// If null, defaults to nearest (pixelated)
    texture_sampler: ?*gpu.Sampler = null,

    /// Alpha and color blending options
    ///
    /// If null, defaults to
    /// .{
    ///   .color = .{ .operation = .add, .src_factor = .src_alpha .dst_factor = .one_minus_src_alpha },
    ///   .alpha = .{ .operation = .add, .src_factor = .one, .dst_factor = .zero },
    /// }
    blend_state: ?gpu.BlendState = null,

    /// Override to enable passing additional data to your shader program.
    bind_group_layout: ?*gpu.BindGroupLayout = null,

    /// Override to enable passing additional data to your shader program.
    bind_group: ?*gpu.BindGroup = null,

    /// Override to enable custom color target state for render pipeline.
    color_target_state: ?gpu.ColorTargetState = null,

    /// Override to enable custom fragment state for render pipeline.
    fragment_state: ?gpu.FragmentState = null,

    /// Override to enable custom pipeline layout.
    layout: ?*gpu.PipelineLayout = null,

    /// Number of sprites this pipeline will render.
    /// Read-only, updated as part of Sprite.snapshot
    num_sprites: u32 = 0,

    /// The sprites this pipeline will render. Add to it to render a sprite:
    ///
    /// ```
    /// var render_list = sprite.pipelines.get(pipeline_id, .render_list);
    /// try render_list.append(allocator, sprite_id);
    /// sprite.pipelines.set(pipeline_id, .render_list, render_list);
    /// ```
    ///
    /// Sprites are removed from this list automatically when they are deleted (via Sprite.cleanup).
    render_list: std.ArrayList(mach.ObjectID) = .empty,

    /// Internal pipeline state.
    built_index: ?u32 = null,
});

allocator: std.mem.Allocator,

objects: Objects,
pipelines: Pipelines,

// Internal render copy of objects and pipelines.
render_objects: Objects,
render_pipelines: Pipelines,
built_pipelines: std.ArrayList(?BuiltPipeline) = .empty,

// Per-pipeline render-side `.render_list` storage, indexed by `built_index` (parallel to
// `built_pipelines`). Owned by us across frames so the allocated capacity can be reused rather
// than freed and re-allocated on each `copyFrom`.
cached_render_lists: std.ArrayList(std.ArrayList(mach.ObjectID)) = .empty,

// Temporary buffers used during updatePipelineBuffers, retained to avoid re-allocation.
cp_transforms: std.ArrayList(gpu.Mat4x4) = .empty,
cp_uv_transforms: std.ArrayList(gpu.Mat4x4) = .empty,
cp_sizes: std.ArrayList(gpu.Vec2) = .empty,

pub fn init(sprite: *Sprite, allocator: std.mem.Allocator) !void {
    sprite.* = .{
        .allocator = allocator,
        .objects = sprite.objects,
        .pipelines = sprite.pipelines,
        .render_objects = sprite.render_objects,
        .render_pipelines = sprite.render_pipelines,
    };
}

/// Cleans up sprite objects that have been marked for deletion via `delete()`.
///
/// Each deleted sprite is removed from any pipeline's `.render_list` it appears in.
pub fn cleanup(sprite: *Sprite) void {
    // Fast path: no deletions, no work.
    if (sprite.objects.numDeleted() == 0) return;

    // Remove deleted sprite IDs from every pipeline's render_list.
    var pipeline_ids = sprite.pipelines.slice();
    while (pipeline_ids.next()) |pipeline_id| {
        var render_list = sprite.pipelines.get(pipeline_id, .render_list);
        var i: usize = render_list.items.len;
        while (i > 0) {
            i -= 1;
            if (sprite.objects.isDeleted(render_list.items[i])) _ = render_list.swapRemove(i);
        }
        sprite.pipelines.setRaw(pipeline_id, .render_list, render_list);
    }

    // Now free the deleted sprite slots.
    var deleted = sprite.objects.sliceDeleted();
    while (deleted.next()) |sprite_id| {
        sprite.objects.free(sprite_id);
    }
}

pub fn snapshot(sprite: *Sprite, core: *mach.Core) !void {
    const allocator = sprite.allocator;
    {
        // Walk over all render snapshot pipelines.
        var render_it = sprite.render_pipelines.slice();
        while (render_it.next()) |render_pid| {
            // Does the app side still have the pipeline object alive, or was it deleted?
            const alive = blk: {
                var app_it = sprite.pipelines.slice();
                while (app_it.next()) |app_pid| {
                    if (render_pid == app_pid) break :blk true;
                }
                break :blk false;
            };
            const built_idx = sprite.render_pipelines.get(render_pid, .built_index).?;
            if (alive) {
                // The app pipeline is still alive, so update it with stats from the last .render.
                sprite.pipelines.setRaw(render_pid, .num_sprites, sprite.render_pipelines.get(render_pid, .num_sprites));

                // Clear our cached render_list for re-use after copyFrom; capacity is retained.
                sprite.cached_render_lists.items[built_idx].clearRetainingCapacity();
            } else {
                // The app wants to delete the pipeline, so deinit it.
                sprite.cached_render_lists.items[built_idx].deinit(allocator);
                sprite.cached_render_lists.items[built_idx] = .empty;
                if (sprite.built_pipelines.items[built_idx]) |*b| b.deinit();
                sprite.built_pipelines.items[built_idx] = null;
            }
        }
    }

    // Ensure every app-side pipeline has a built_pipelines slot allocated where we'll store the pipeline.
    {
        var app_it = sprite.pipelines.slice();
        while (app_it.next()) |app_pid| {
            if (sprite.pipelines.get(app_pid, .built_index) == null) {
                const idx: u32 = @intCast(sprite.built_pipelines.items.len);
                try sprite.built_pipelines.append(allocator, null);
                try sprite.cached_render_lists.append(allocator, .empty);
                sprite.pipelines.setRaw(app_pid, .built_index, idx);
            }
        }
    }

    // Snapshot the sprite objects and pipelines.
    try mach.Core.snapshotObjects(core, &sprite.render_objects, &sprite.objects);
    try mach.Core.snapshotObjects(core, &sprite.render_pipelines, &sprite.pipelines);

    // Deep-copy each pipeline's .render_list. copyFrom shallow-aliased the field to the app-side
    // backing memory; re-attach our owned cached_render_lists entry (with its retained capacity)
    // and re-fill it from the app-side items.
    var render_pipeline_ids = sprite.render_pipelines.slice();
    while (render_pipeline_ids.next()) |render_pipeline_id| {
        const src = sprite.render_pipelines.get(render_pipeline_id, .render_list);
        const built_idx = sprite.render_pipelines.get(render_pipeline_id, .built_index).?;
        var dst = sprite.cached_render_lists.items[built_idx];
        try dst.appendSlice(allocator, src.items);
        sprite.cached_render_lists.items[built_idx] = dst;
        sprite.render_pipelines.setRaw(render_pipeline_id, .render_list, dst);
    }

    // Clear all dirty flags on app-side after copyFrom. The flags have already been copied to the
    // render side, so render() will see them. Clearing here ensures they don't re-propagate next frame.
    {
        var object_it = sprite.objects.slice();
        while (object_it.next()) |sid| {
            _ = sprite.objects.anyUpdated(sid);
        }
        var pipeline_it = sprite.pipelines.slice();
        while (pipeline_it.next()) |pid| {
            _ = sprite.pipelines.anyUpdated(pid);
        }
    }
}

pub fn render(sprite: *Sprite, core: *mach.Core) !void {
    var pipelines = sprite.render_pipelines.slice();
    while (pipelines.next()) |pipeline_id| {
        // Is this pipeline usable for rendering? If not, no need to process it.
        var pipeline = sprite.render_pipelines.getValue(pipeline_id);
        if (pipeline.window == null) continue;
        std.debug.assert(pipeline.built_index != null);

        // render_pass is a transient GPU resource set by the render thread each frame
        // directly on the app-side pipelines — read it from there, not the snapshot.
        const render_pass = sprite.pipelines.get(pipeline_id, .render_pass) orelse continue;

        // Changing these fields shouldn't trigger a pipeline rebuild, so clear their update values:
        _ = sprite.render_pipelines.updated(pipeline_id, .window);
        _ = sprite.render_pipelines.updated(pipeline_id, .render_pass);
        _ = sprite.render_pipelines.updated(pipeline_id, .view_projection);
        _ = sprite.render_pipelines.updated(pipeline_id, .num_sprites);
        _ = sprite.render_pipelines.updated(pipeline_id, .built_index);
        _ = sprite.render_pipelines.updated(pipeline_id, .render_list);

        // A pipeline rebuild is required if the slot hasn't been built yet, or if any
        // pipeline fields (texture, shader, blend state, etc.) have been updated.
        const needs_rebuild = sprite.built_pipelines.items[pipeline.built_index.?] == null or
            sprite.render_pipelines.anyUpdated(pipeline_id);
        if (needs_rebuild) rebuildPipeline(core, sprite, pipeline_id);

        // Get sprites registered with this pipeline
        const render_list = sprite.render_pipelines.get(pipeline_id, .render_list).items;

        // If the pipeline was just rebuilt, or any sprites were updated, we need to
        // upload all sprite data to the GPU storage buffers.
        const any_sprites_updated = needs_rebuild or blk: {
            for (render_list) |sprite_id| {
                if (!sprite.render_objects.is(sprite_id)) continue;
                if (sprite.render_objects.anyUpdated(sprite_id)) break :blk true;
            }
            break :blk false;
        };
        if (any_sprites_updated) try updatePipelineBuffers(sprite, core, pipeline_id, render_list);

        // Do we actually have any sprites to render?
        pipeline = sprite.render_pipelines.getValue(pipeline_id);
        if (pipeline.num_sprites == 0) continue;

        // TODO(sprite): need a way to specify order of rendering with multiple pipelines
        renderPipeline(sprite, core, pipeline_id, render_pass);
    }
}

fn rebuildPipeline(
    core: *mach.Core,
    sprite: *Sprite,
    pipeline_id: mach.ObjectID,
) void {
    // Destroy the current pipeline, if built.
    var pipeline = sprite.render_pipelines.getValue(pipeline_id);
    const built_idx = pipeline.built_index.?;
    if (sprite.built_pipelines.items[built_idx]) |built| built.deinit();

    // Reference any user-provided objects.
    pipeline.texture.reference();
    if (pipeline.texture2) |v| v.reference();
    if (pipeline.texture3) |v| v.reference();
    if (pipeline.texture4) |v| v.reference();
    if (pipeline.shader) |v| v.reference();
    if (pipeline.texture_sampler) |v| v.reference();
    if (pipeline.bind_group_layout) |v| v.reference();
    if (pipeline.bind_group) |v| v.reference();
    if (pipeline.layout) |v| v.reference();

    const window = core.windows.getValue(pipeline.window.?);
    const device = window.device;

    const label = @tagName(mach_module) ++ ".rebuildPipeline";

    const initial_buffer_cap: u32 = 64;

    // Storage buffers
    const transforms = device.createBuffer(&.{
        .label = label ++ " transforms",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(gpu.Mat4x4) * initial_buffer_cap,
        .mapped_at_creation = .false,
    });
    const uv_transforms = device.createBuffer(&.{
        .label = label ++ " uv_transforms",
        .usage = .{ .storage = true, .copy_dst = true },
        // TODO(d3d12): uv_transform should be a Mat3x3 but our D3D12/HLSL backend cannot handle it.
        .size = @sizeOf(gpu.Mat4x4) * initial_buffer_cap,
        .mapped_at_creation = .false,
    });
    const sizes = device.createBuffer(&.{
        .label = label ++ " sizes",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(gpu.Vec2) * initial_buffer_cap,
        .mapped_at_creation = .false,
    });

    const texture_sampler = pipeline.texture_sampler orelse device.createSampler(&.{
        .label = label ++ " sampler",
        .mag_filter = .nearest,
        .min_filter = .nearest,
    });
    const uniforms = device.createBuffer(&.{
        .label = label ++ " uniforms",
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
        .mapped_at_creation = .false,
    });
    const owns_bind_group_layout = pipeline.bind_group_layout == null;
    const bind_group_layout = pipeline.bind_group_layout orelse device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .label = label,
            .entries = &.{
                gpu.BindGroupLayout.Entry.initBuffer(0, .{ .vertex = true }, .uniform, false, 0),
                gpu.BindGroupLayout.Entry.initBuffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.initBuffer(2, .{ .vertex = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.initBuffer(3, .{ .vertex = true }, .read_only_storage, false, 0),
                gpu.BindGroupLayout.Entry.initSampler(4, .{ .fragment = true }, .filtering),
                gpu.BindGroupLayout.Entry.initTexture(5, .{ .fragment = true }, .float, .dimension_2d, false),
                gpu.BindGroupLayout.Entry.initTexture(6, .{ .fragment = true }, .float, .dimension_2d, false),
                gpu.BindGroupLayout.Entry.initTexture(7, .{ .fragment = true }, .float, .dimension_2d, false),
                gpu.BindGroupLayout.Entry.initTexture(8, .{ .fragment = true }, .float, .dimension_2d, false),
            },
        }),
    );

    const texture_view = pipeline.texture.createView(&gpu.TextureView.Descriptor{ .label = label });
    const texture2_view = if (pipeline.texture2) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
    const texture3_view = if (pipeline.texture3) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
    const texture4_view = if (pipeline.texture4) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
    defer texture_view.release();
    // TODO: texture views 2-4 leak

    const bind_group = pipeline.bind_group orelse device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .label = label,
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.initBuffer(0, uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
                gpu.BindGroup.Entry.initBuffer(1, transforms, 0, @sizeOf(gpu.Mat4x4) * initial_buffer_cap, @sizeOf(gpu.Mat4x4)),
                gpu.BindGroup.Entry.initBuffer(2, uv_transforms, 0, @sizeOf(gpu.Mat4x4) * initial_buffer_cap, @sizeOf(gpu.Mat4x4)),
                gpu.BindGroup.Entry.initBuffer(3, sizes, 0, @sizeOf(gpu.Vec2) * initial_buffer_cap, @sizeOf(gpu.Vec2)),
                gpu.BindGroup.Entry.initSampler(4, texture_sampler),
                gpu.BindGroup.Entry.initTextureView(5, texture_view),
                gpu.BindGroup.Entry.initTextureView(6, texture2_view),
                gpu.BindGroup.Entry.initTextureView(7, texture3_view),
                gpu.BindGroup.Entry.initTextureView(8, texture4_view),
            },
        }),
    );

    const blend_state = pipeline.blend_state orelse gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const shader_module = pipeline.shader orelse device.createShaderModuleWGSL("sprite.wgsl", @embedFile("sprite.wgsl"));
    defer shader_module.release();

    const color_target = pipeline.color_target_state orelse gpu.ColorTargetState{
        .format = window.framebuffer_format,
        .blend = &blend_state,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = pipeline.fragment_state orelse gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fragMain",
        .targets = &.{color_target},
    });

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};
    const pipeline_layout = pipeline.layout orelse device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = label,
        .bind_group_layouts = &bind_group_layouts,
    }));
    defer pipeline_layout.release();
    const render_pipeline = device.createRenderPipeline(&gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .layout = pipeline_layout,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertMain",
        },
    });

    sprite.built_pipelines.items[built_idx] = BuiltPipeline{
        .render = render_pipeline,
        .texture_sampler = texture_sampler,
        .texture = pipeline.texture,
        .texture2 = pipeline.texture2,
        .texture3 = pipeline.texture3,
        .texture4 = pipeline.texture4,
        .bind_group = bind_group,
        .bind_group_layout = if (owns_bind_group_layout) bind_group_layout else null,
        .uniforms = uniforms,
        .transforms = transforms,
        .uv_transforms = uv_transforms,
        .sizes = sizes,
        .buffer_cap = initial_buffer_cap,
    };
    pipeline.num_sprites = 0;
    sprite.render_pipelines.setValueRaw(pipeline_id, pipeline);
}

fn updatePipelineBuffers(
    sprite: *Sprite,
    core: *mach.Core,
    pipeline_id: mach.ObjectID,
    pipeline_children: []const mach.ObjectID,
) !void {
    const pipeline = sprite.render_pipelines.getValue(pipeline_id);
    var built = &sprite.built_pipelines.items[pipeline.built_index.?].?;
    const window = core.windows.getValue(pipeline.window.?);
    const device = window.device;

    const label = @tagName(mach_module) ++ ".updatePipelineBuffers";
    const encoder = device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    sprite.cp_transforms.clearRetainingCapacity();
    sprite.cp_uv_transforms.clearRetainingCapacity();
    sprite.cp_sizes.clearRetainingCapacity();

    for (pipeline_children) |sprite_id| {
        if (!sprite.render_objects.is(sprite_id)) continue;
        const s = sprite.render_objects.getValue(sprite_id);

        try sprite.cp_transforms.append(sprite.allocator, s.transform.gpu());

        // TODO(d3d12): uv_transform should be a Mat3x3 but our D3D12/HLSL backend cannot handle it.
        try sprite.cp_uv_transforms.append(sprite.allocator, s.uv_transform.mat4x4().gpu());
        try sprite.cp_sizes.append(sprite.allocator, s.size.gpu());
    }

    const count: u32 = @intCast(sprite.cp_transforms.items.len);

    // Grow GPU storage buffers and recreate bind group if needed.
    if (count > built.buffer_cap and built.bind_group_layout != null) {
        var new_cap = built.buffer_cap;
        while (new_cap < count) new_cap *= 2;

        built.transforms.release();
        built.uv_transforms.release();
        built.sizes.release();
        built.bind_group.release();

        built.transforms = device.createBuffer(&.{
            .label = label ++ " transforms",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(gpu.Mat4x4) * new_cap,
            .mapped_at_creation = .false,
        });
        built.uv_transforms = device.createBuffer(&.{
            .label = label ++ " uv_transforms",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(gpu.Mat4x4) * new_cap,
            .mapped_at_creation = .false,
        });
        built.sizes = device.createBuffer(&.{
            .label = label ++ " sizes",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(gpu.Vec2) * new_cap,
            .mapped_at_creation = .false,
        });

        const texture_view = built.texture.createView(&gpu.TextureView.Descriptor{ .label = label });
        const texture2_view = if (built.texture2) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
        const texture3_view = if (built.texture3) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
        const texture4_view = if (built.texture4) |tex| tex.createView(&gpu.TextureView.Descriptor{ .label = label }) else texture_view;
        defer texture_view.release();
        defer if (built.texture2 != null) texture2_view.release();
        defer if (built.texture3 != null) texture3_view.release();
        defer if (built.texture4 != null) texture4_view.release();

        built.bind_group = device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .label = label,
                .layout = built.bind_group_layout.?,
                .entries = &.{
                    gpu.BindGroup.Entry.initBuffer(0, built.uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
                    gpu.BindGroup.Entry.initBuffer(1, built.transforms, 0, @sizeOf(gpu.Mat4x4) * new_cap, @sizeOf(gpu.Mat4x4)),
                    gpu.BindGroup.Entry.initBuffer(2, built.uv_transforms, 0, @sizeOf(gpu.Mat4x4) * new_cap, @sizeOf(gpu.Mat4x4)),
                    gpu.BindGroup.Entry.initBuffer(3, built.sizes, 0, @sizeOf(gpu.Vec2) * new_cap, @sizeOf(gpu.Vec2)),
                    gpu.BindGroup.Entry.initSampler(4, built.texture_sampler),
                    gpu.BindGroup.Entry.initTextureView(5, texture_view),
                    gpu.BindGroup.Entry.initTextureView(6, texture2_view),
                    gpu.BindGroup.Entry.initTextureView(7, texture3_view),
                    gpu.BindGroup.Entry.initTextureView(8, texture4_view),
                },
            }),
        );
        built.buffer_cap = new_cap;
    }

    // Sort sprites back-to-front for draw order, alpha blending
    const Context = struct {
        transforms: []gpu.Mat4x4,
        uv_transforms: []gpu.Mat4x4,
        sizes: []gpu.Vec2,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            const a_z = ctx.transforms[a].math().translation().z();
            const b_z = ctx.transforms[b].math().translation().z();
            // Greater z values are further away, and thus should render/sort before those with lesser z values.
            return a_z > b_z;
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(gpu.Mat4x4, &ctx.transforms[a], &ctx.transforms[b]);
            std.mem.swap(gpu.Mat4x4, &ctx.uv_transforms[a], &ctx.uv_transforms[b]);
            std.mem.swap(gpu.Vec2, &ctx.sizes[a], &ctx.sizes[b]);
        }
    };
    std.sort.pdqContext(0, count, Context{
        .transforms = sprite.cp_transforms.items,
        .uv_transforms = sprite.cp_uv_transforms.items,
        .sizes = sprite.cp_sizes.items,
    });

    sprite.render_pipelines.set(pipeline_id, .num_sprites, @intCast(count));
    if (count > 0) {
        encoder.writeBuffer(built.transforms, 0, sprite.cp_transforms.items);
        encoder.writeBuffer(built.uv_transforms, 0, sprite.cp_uv_transforms.items);
        encoder.writeBuffer(built.sizes, 0, sprite.cp_sizes.items);

        var command = encoder.finish(&.{ .label = label });
        defer command.release();
        window.queue.submit(&[_]*gpu.CommandBuffer{command});
    }
}

fn renderPipeline(
    sprite: *Sprite,
    core: *mach.Core,
    pipeline_id: mach.ObjectID,
    render_pass: *gpu.RenderPassEncoder,
) void {
    const pipeline = sprite.render_pipelines.getValue(pipeline_id);
    const built = sprite.built_pipelines.items[pipeline.built_index.?].?;
    const window = core.windows.getValue(pipeline.window.?);
    const device = window.device;

    const label = @tagName(mach_module) ++ ".renderPipeline";
    const encoder = device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    // Update uniform buffer
    const view_projection = pipeline.view_projection orelse blk: {
        const width_px: f32 = @floatFromInt(window.width);
        const height_px: f32 = @floatFromInt(window.height);
        break :blk math.Mat4x4.projection2D(.{
            .left = -width_px / 2,
            .right = width_px / 2,
            .bottom = -height_px / 2,
            .top = height_px / 2,
            .near = -0.1,
            .far = 100000,
        });
    };
    const uniforms = Uniforms{
        .view_projection = view_projection.gpu(),
        // TODO(sprite): dimensions of multi-textures, number of multi-textures present
        .texture_size = gpu.vec2(
            @as(f32, @floatFromInt(built.texture.getWidth())),
            @as(f32, @floatFromInt(built.texture.getHeight())),
        ),
    };
    encoder.writeBuffer(built.uniforms, 0, &[_]Uniforms{uniforms});
    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    window.queue.submit(&[_]*gpu.CommandBuffer{command});

    // Draw the sprite batch
    const total_vertices = pipeline.num_sprites * 6;
    render_pass.setPipeline(built.render);
    // TODO(sprite): can we remove unused dynamic offsets?
    render_pass.setBindGroup(0, built.bind_group, &.{});
    render_pass.draw(total_vertices, 1, 0, 0);
}

pub fn deinit(sprite: *Sprite) void {
    const allocator = sprite.allocator;

    var pipeline_ids = sprite.pipelines.slice();
    while (pipeline_ids.next()) |pipeline_id| {
        var render_list = sprite.pipelines.get(pipeline_id, .render_list);
        render_list.deinit(allocator);
    }
    var deleted_pipelines = sprite.pipelines.sliceDeleted();
    while (deleted_pipelines.next()) |pipeline_id| {
        var render_list = sprite.pipelines.get(pipeline_id, .render_list);
        render_list.deinit(allocator);
    }

    for (sprite.built_pipelines.items) |*built| {
        if (built.*) |*pipeline| pipeline.deinit();
    }
    for (sprite.cached_render_lists.items) |*render_list| {
        render_list.deinit(allocator);
    }
    sprite.built_pipelines.deinit(allocator);
    sprite.cached_render_lists.deinit(allocator);
    sprite.cp_transforms.deinit(allocator);
    sprite.cp_uv_transforms.deinit(allocator);
    sprite.cp_sizes.deinit(allocator);
}
