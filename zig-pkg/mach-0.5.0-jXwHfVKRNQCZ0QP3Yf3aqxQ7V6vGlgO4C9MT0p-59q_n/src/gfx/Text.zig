const std = @import("std");
const mach = @import("../main.zig");
const gpu = mach.gpu;
const gfx = mach.gfx;

const math = mach.math;
const vec4 = math.vec4;
const Mat4x4 = math.Mat4x4;

const Text = @This();

pub const mach_module = .mach_gfx_text;

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

    /// Total size of the font atlas texture in pixels
    texture_size: gpu.Vec2 align(16),
};

const BuiltPipeline = struct {
    render: *gpu.RenderPipeline,
    texture_sampler: *gpu.Sampler,
    texture: *gpu.Texture,
    bind_group: *gpu.BindGroup,
    bind_group_layout: ?*gpu.BindGroupLayout,
    uniforms: *gpu.Buffer,
    texture_atlas: gfx.Atlas,
    regions: RegionMap = .{},

    // Storage buffers
    transforms: *gpu.Buffer,
    colors: *gpu.Buffer,
    glyphs: *gpu.Buffer,
    buffer_cap: u32,

    fn deinit(p: *BuiltPipeline, allocator: std.mem.Allocator) void {
        p.render.release();
        p.texture_sampler.release();
        p.texture.release();
        p.bind_group.release();
        if (p.bind_group_layout) |l| l.release();
        p.uniforms.release();
        p.texture_atlas.deinit(allocator);
        p.regions.deinit(allocator);
        p.transforms.release();
        p.colors.release();
        p.glyphs.release();
    }
};

const BuiltText = struct {
    glyphs: std.ArrayList(Glyph),
};

const Glyph = extern struct {
    /// Position of this glyph (top-left corner.)
    pos: gpu.Vec2,

    /// Width of the glyph in pixels.
    size: gpu.Vec2,

    /// Normalized position of the top-left UV coordinate
    uv_pos: gpu.Vec2,

    /// Which text this glyph belongs to; this is the index for transforms[i], colors[i].
    text_index: u32,

    // TODO(d3d12): this is a hack, having 7 floats before the color vec causes an error
    text_padding: u32,

    /// Color of the glyph
    color: gpu.Vec4,
};

const GlyphKey = struct {
    index: u32,
    // Auto Hashing doesn't work for floats, so we bitcast to integer.
    size: u32,
};

const CachedGlyph = struct {
    region: gfx.Atlas.Region,
    bearing_x: f32,
    bearing_y: f32,
};

const RegionMap = std.AutoArrayHashMapUnmanaged(GlyphKey, CachedGlyph);

pub const Segment = struct {
    /// UTF-8 encoded string of text to render
    text: []const u8,

    /// Style to apply when rendering the text
    style: mach.ObjectID,
};

/// State for text objects whose segments are managed by createFmt/setFmt.
pub const Managed = struct {
    /// Segments. The text object's `.segments` field points to `.items`.
    segments: std.ArrayList(Segment),

    /// Text buffers. Each segment's `.text` slice points to the corresponding buffer's `.items`.
    bufs: std.ArrayList(std.ArrayList(u8)),

    /// Hash of the last createFmt/setFmt inputs. setFmt uses this to skip expensive computation
    /// to rebuild the text when the inputs haven't changed.
    hash: u64,
};

const Styles = mach.Objects(.{ .track_fields = true }, struct {
    // TODO(text): not currently implemented
    // TODO(text): ship a default font
    /// Desired font to render text with
    font_name: []const u8 = "",

    /// Font size in pixels
    /// e.g. 12 * mach.gfx.px_per_pt for 12pt font size
    font_size: f32 = 12 * gfx.px_per_pt,

    // TODO(text): not currently implemented
    /// Font weight
    font_weight: u16 = gfx.font_weight_normal,

    // TODO(text): not currently implemented
    /// Fill color of text
    color: math.Vec4 = vec4(0, 0, 0, 1.0), // black

    // TODO(text): not currently implemented
    /// Italic style
    italic: bool = false,

    // TODO(text): allow user to specify projection matrix (3d-space flat text etc.)
});

const TextObjects = mach.Objects(.{ .track_fields = true }, struct {
    /// The text model transformation matrix. Text is measured in pixel units, starting from
    /// (0, 0) at the top-left corner and extending to the size of the text. By default, the world
    /// origin (0, 0) lives at the center of the window.
    transform: Mat4x4,

    /// The segments of text
    segments: []const Segment,

    /// Managed text state. When non-null, this text object's segments are managed by
    /// createFmt/setFmt and will be freed by cleanup().
    managed: ?Managed = null,

    /// Internal text object state.
    built: ?BuiltText = null,
});

/// A text pipeline renders all text objects in its `.render_list`
const TextPipelines = mach.Objects(.{ .track_fields = true }, struct {
    /// Which window (device/queue) to use. If not set, this pipeline will not be rendered.
    window: ?mach.ObjectID = null,

    /// Which render pass should be used during rendering. If not set, this pipeline will not be
    /// rendered.
    render_pass: ?*gpu.RenderPassEncoder = null,

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

    /// Shader program to use when rendering
    ///
    /// If null, defaults to text.wgsl
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

    /// Number of text objects this pipeline will render.
    /// Read-only, updated as part of Text.snapshot
    num_texts: u32 = 0,

    /// Number of text segments this pipeline will render.
    /// Read-only, updated as part of Text.snapshot
    num_segments: u32 = 0,

    /// Total number of glyphs this pipeline will render.
    /// Read-only, updated as part of Text.snapshot
    num_glyphs: u32 = 0,

    /// The text objects this pipeline will render. Add to it to render text:
    ///
    /// ```
    /// var render_list = text.pipelines.get(pipeline_id, .render_list);
    /// try render_list.append(allocator, text_id);
    /// text.pipelines.set(pipeline_id, .render_list, render_list);
    /// ```
    ///
    /// Text objects are removed from this list automatically when they are deleted (via Text.cleanup).
    render_list: std.ArrayList(mach.ObjectID) = .empty,

    /// Internal pipeline state.
    built_index: ?u32 = null,
});

allocator: std.mem.Allocator,
glyph_update_buffer: ?std.ArrayList(Glyph) = null,
font_once: ?gfx.Font = null,

styles: Styles,
objects: TextObjects,
pipelines: TextPipelines,

// Internal render copy of objects and pipelines.
render_objects: TextObjects,
render_pipelines: TextPipelines,
built_pipelines: std.ArrayList(?BuiltPipeline) = .empty,

// Per-pipeline render-side `.render_list` storage, indexed by `built_index` (parallel to
// `built_pipelines`). Owned by us across frames so the allocated capacity can be reused rather
// than freed and re-allocated on each `copyFrom`.
cached_render_lists: std.ArrayList(std.ArrayList(mach.ObjectID)) = .empty,

// Tracks render-side deep-copied segments so they can be freed next frame.
render_segments: ?[][]Segment = null,

// Temporary buffer used during updatePipelineBuffers, retained to avoid re-allocation.
cp_transforms: std.ArrayList(gpu.Mat4x4) = .empty,

pub fn init(text: *Text, allocator: std.mem.Allocator) !void {
    text.* = .{
        .allocator = allocator,
        .styles = text.styles,
        .objects = text.objects,
        .pipelines = text.pipelines,
        .render_objects = text.render_objects,
        .render_pipelines = text.render_pipelines,
    };
}

/// Creates a managed text object with formatted segments. Each element of `specs` is a
/// `.{ style, fmt, args }` tuple.
///
/// The caller is responsible for registering the returned text object with a pipeline by appending
/// it to `pipeline.render_list`.
///
/// Allocations are managed by the Text module and freed automatically by `cleanup()`.
///
/// Example:
/// ```
/// const my_text_id = try text.createFmt(Mat4x4.translate(vec3(0, 0, 0)), .{
///     .{ style_id, "Score: {d}", .{score} },
///     .{ label_style, "Player: {s}", .{name} },
/// });
/// ```
pub fn createFmt(text: *Text, transform: Mat4x4, specs: anytype) !mach.ObjectID {
    const hash = hashSpecs(specs);
    var managed: Managed = .{
        .segments = .empty,
        .bufs = .empty,
        .hash = hash,
    };
    try managed.segments.ensureTotalCapacity(text.allocator, specs.len);
    try managed.bufs.ensureTotalCapacity(text.allocator, specs.len);
    inline for (0..specs.len) |i| {
        var buf: std.ArrayList(u8) = .empty;
        buf.print(text.allocator, specs[i][1], specs[i][2]) catch return error.OutOfMemory;
        managed.bufs.appendAssumeCapacity(buf);
        managed.segments.appendAssumeCapacity(.{ .text = buf.items, .style = specs[i][0] });
    }
    return try text.objects.new(.{
        .transform = transform,
        .segments = managed.segments.items,
        .managed = managed,
    });
}

/// Updates a managed text object with new formatted segments. Each element of `specs` is a
/// `.{ style, fmt, args }` tuple.
///
/// If the input specs hash to the same as the text currently has, this function is no-op to prevent
/// costly recomputation - making it less expensive to invoke each frame if your inputs have not
/// changed.
///
/// Example:
/// ```
/// // Create text initially
/// const my_text_id = try text.createFmt(Mat4x4.translate(vec3(0, 0, 0)), .{
///     .{ style_id, "Score: {d}", .{score} },
///     .{ label_style, "Player: {s}", .{name} },
/// });
///
/// // Update text
/// text.setFmt(my_text_id, .{
///     .{ style_id, "Score: {d}", .{score} },
/// });
/// ```
pub fn setFmt(text_mod: *Text, text_id: mach.ObjectID, specs: anytype) !void {
    var managed = text_mod.objects.get(text_id, .managed) orelse return;

    // If the hashed inputs wouldn't actually change the text, nothing to do.
    const hash = hashSpecs(specs);
    if (managed.hash == hash) return;

    // Grow segments and bufs if the new spec count is larger.
    if (specs.len > managed.segments.items.len) {
        try managed.segments.ensureTotalCapacity(text_mod.allocator, specs.len);
        try managed.bufs.ensureTotalCapacity(text_mod.allocator, specs.len);
        while (managed.bufs.items.len < specs.len) {
            managed.bufs.appendAssumeCapacity(.empty);
            managed.segments.appendAssumeCapacity(undefined);
        }
    }

    // Pre-ensure capacity on all buffers so print cannot fail below.
    inline for (0..specs.len) |i| {
        try managed.bufs.items[i].ensureTotalCapacity(text_mod.allocator, std.fmt.count(specs[i][1], specs[i][2]));
    }

    // Update segments
    inline for (0..specs.len) |i| {
        // Update text buffer
        managed.bufs.items[i].clearRetainingCapacity();
        managed.bufs.items[i].print(text_mod.allocator, specs[i][1], specs[i][2]) catch unreachable;

        // Update segment
        managed.segments.items[i] = .{ .text = managed.bufs.items[i].items, .style = specs[i][0] };
    }

    // Update managed field
    managed.hash = hash;
    text_mod.objects.set(text_id, .segments, managed.segments.items[0..specs.len]);
    text_mod.objects.set(text_id, .managed, managed);
}

fn hashSpecs(specs: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (0..specs.len) |i| {
        std.hash.autoHash(&hasher, specs[i][0]); // style
        inline for (specs[i][2]) |arg| {
            hashValue(&hasher, arg);
        }
    }
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

/// Cleans up text objects that have been marked for deletion via `delete()`.
///
/// Each deleted text object is removed from any pipeline's `.render_list` it appears in.
pub fn cleanup(text: *Text) void {
    // Fast path: no deletions, no work.
    if (text.objects.numDeleted() == 0) return;

    // Remove deleted text IDs from every pipeline's render_list.
    var pipeline_ids = text.pipelines.slice();
    while (pipeline_ids.next()) |pipeline_id| {
        var render_list = text.pipelines.get(pipeline_id, .render_list);
        var i: usize = render_list.items.len;
        while (i > 0) {
            i -= 1;
            if (text.objects.isDeleted(render_list.items[i])) _ = render_list.swapRemove(i);
        }
        text.pipelines.setRaw(pipeline_id, .render_list, render_list);
    }

    // Now free the deleted text slots.
    var deleted = text.objects.sliceDeleted();
    while (deleted.next()) |text_id| {
        deinitObject(text, text_id);
        text.objects.free(text_id);
    }
}

fn deinitObject(text: *Text, text_id: mach.ObjectID) void {
    if (text.objects.get(text_id, .managed)) |managed| {
        for (managed.bufs.items) |*buf| buf.deinit(text.allocator);
        var bufs = managed.bufs;
        bufs.deinit(text.allocator);
        var segments = managed.segments;
        segments.deinit(text.allocator);
    }
    if (text.objects.get(text_id, .built)) |built| {
        var glyphs = built.glyphs;
        glyphs.deinit(text.allocator);
    }
}

pub fn snapshot(text: *Text, core: *mach.Core) !void {
    {
        // Walk over all render snapshot pipelines.
        var render_it = text.render_pipelines.slice();
        while (render_it.next()) |render_pid| {
            // Does the app side still have the pipeline object alive, or was it deleted?
            const alive = blk: {
                var app_it = text.pipelines.slice();
                while (app_it.next()) |app_pid| {
                    if (render_pid == app_pid) break :blk true;
                }
                break :blk false;
            };
            const built_idx = text.render_pipelines.get(render_pid, .built_index).?;
            if (alive) {
                // The app pipeline is still alive, so update it with stats from the last .render.
                text.pipelines.setRaw(render_pid, .num_texts, text.render_pipelines.get(render_pid, .num_texts));
                text.pipelines.setRaw(render_pid, .num_segments, text.render_pipelines.get(render_pid, .num_segments));
                text.pipelines.setRaw(render_pid, .num_glyphs, text.render_pipelines.get(render_pid, .num_glyphs));

                // Clear our cached render_list for re-use after copyFrom; capacity is retained.
                text.cached_render_lists.items[built_idx].clearRetainingCapacity();
            } else {
                // The app wants to delete the pipeline, so deinit it.
                text.cached_render_lists.items[built_idx].deinit(text.allocator);
                text.cached_render_lists.items[built_idx] = .empty;
                if (text.built_pipelines.items[built_idx]) |*b| b.deinit(text.allocator);
                text.built_pipelines.items[built_idx] = null;
            }
        }
    }

    // Ensure every app-side pipeline has a built_pipelines slot allocated where we'll store the pipeline.
    {
        var app_it = text.pipelines.slice();
        while (app_it.next()) |app_pid| {
            if (text.pipelines.get(app_pid, .built_index) == null) {
                const idx: u32 = @intCast(text.built_pipelines.items.len);
                try text.built_pipelines.append(text.allocator, null);
                try text.cached_render_lists.append(text.allocator, .empty);
                text.pipelines.setRaw(app_pid, .built_index, idx);
            }
        }
    }

    // Snapshot the text objects and pipelines.
    try mach.Core.snapshotObjects(core, &text.render_objects, &text.objects);
    try mach.Core.snapshotObjects(core, &text.render_pipelines, &text.pipelines);

    // Deep-copy each pipeline's .render_list. copyFrom shallow-aliased the field to the app-side
    // backing memory; re-attach our owned cached_render_lists entry (with its retained capacity)
    // and re-fill it from the app-side items.
    var render_pipeline_ids = text.render_pipelines.slice();
    while (render_pipeline_ids.next()) |render_pipeline_id| {
        const src = text.render_pipelines.get(render_pipeline_id, .render_list);
        const built_idx = text.render_pipelines.get(render_pipeline_id, .built_index).?;
        var dst = text.cached_render_lists.items[built_idx];
        try dst.appendSlice(text.allocator, src.items);
        text.cached_render_lists.items[built_idx] = dst;
        text.render_pipelines.setRaw(render_pipeline_id, .render_list, dst);
    }

    // Deep-copy segment text for managed text objects so the render thread has
    // its own stable copy that won't be modified by the app thread's setFmt.
    {
        var it = text.render_objects.slice();
        while (it.next()) |text_id| {
            if (text.render_objects.get(text_id, .managed) == null) continue;
            const src_segments = text.render_objects.get(text_id, .segments);
            const dst_segments = try text.allocator.alloc(Segment, src_segments.len);
            for (src_segments, 0..) |seg, i| {
                dst_segments[i] = .{
                    .text = try text.allocator.dupe(u8, seg.text),
                    .style = seg.style,
                };
            }
            text.render_objects.setRaw(text_id, .segments, dst_segments);
        }
    }

    // Free render-side deep copies from the previous frame.
    if (text.render_segments) |old| {
        for (old) |segments| {
            for (segments) |seg| text.allocator.free(@constCast(seg.text));
            text.allocator.free(segments);
        }
        text.allocator.free(old);
    }

    // Collect current render-side segment pointers so we can free them next frame.
    {
        var count: usize = 0;
        var it = text.render_objects.slice();
        while (it.next()) |text_id| {
            if (text.render_objects.get(text_id, .managed) != null) count += 1;
        }
        const entries = try text.allocator.alloc([]Segment, count);
        var idx: usize = 0;
        it = text.render_objects.slice();
        while (it.next()) |text_id| {
            if (text.render_objects.get(text_id, .managed) == null) continue;
            entries[idx] = @constCast(text.render_objects.get(text_id, .segments));
            idx += 1;
        }
        text.render_segments = entries;
    }

    // Clear all dirty flags on app-side after copyFrom. The flags have already been copied to the
    // render side, so render() will see them. Clearing here ensures they don't re-propagate next frame.
    {
        var object_it = text.objects.slice();
        while (object_it.next()) |text_id| {
            _ = text.objects.anyUpdated(text_id);
        }
        var pipeline_it = text.pipelines.slice();
        while (pipeline_it.next()) |pid| {
            _ = text.pipelines.anyUpdated(pid);
        }
    }
}
pub fn render(text: *Text, core: *mach.Core) !void {
    var pipelines = text.render_pipelines.slice();
    while (pipelines.next()) |pipeline_id| {
        // Is this pipeline usable for rendering? If not, no need to process it.
        const pipeline = text.render_pipelines.getValue(pipeline_id);
        if (pipeline.window == null) continue;
        std.debug.assert(pipeline.built_index != null);

        // render_pass is a transient GPU resource set by the render thread each frame
        // directly on the app-side pipelines — read it from there, not the snapshot.
        const render_pass = text.pipelines.get(pipeline_id, .render_pass) orelse continue;

        // Changing these fields shouldn't trigger a pipeline rebuild, so clear their update values:
        _ = text.render_pipelines.updated(pipeline_id, .window);
        _ = text.render_pipelines.updated(pipeline_id, .render_pass);
        _ = text.render_pipelines.updated(pipeline_id, .view_projection);
        _ = text.render_pipelines.updated(pipeline_id, .num_texts);
        _ = text.render_pipelines.updated(pipeline_id, .num_segments);
        _ = text.render_pipelines.updated(pipeline_id, .num_glyphs);
        _ = text.render_pipelines.updated(pipeline_id, .built_index);
        _ = text.render_pipelines.updated(pipeline_id, .render_list);

        // A pipeline rebuild is required if the slot hasn't been built yet, or if any
        // pipeline fields (texture, shader, blend state, etc.) have been updated.
        const needs_rebuild = text.built_pipelines.items[pipeline.built_index.?] == null or
            text.render_pipelines.anyUpdated(pipeline_id);
        if (needs_rebuild) try rebuildPipeline(core, text, pipeline_id);

        // Get text objects registered with this pipeline
        const render_list = text.render_pipelines.get(pipeline_id, .render_list).items;

        // If the pipeline was just rebuilt, or any text objects were updated, we need to
        // upload all text data to the GPU storage buffers.
        const any_updated = needs_rebuild or blk: {
            for (render_list) |text_id| {
                if (!text.render_objects.is(text_id)) continue;
                if (text.render_objects.peekAnyUpdated(text_id)) break :blk true;
            }
            break :blk false;
        };
        if (any_updated) try updatePipelineBuffers(text, core, pipeline_id, render_list);

        // Do we actually have any glyphs to render?
        if (text.render_pipelines.get(pipeline_id, .num_glyphs) == 0) continue;

        // TODO(text): need a way to specify order of rendering with multiple pipelines
        renderPipeline(text, core, pipeline_id, render_pass);
    }
}

fn rebuildPipeline(
    core: *mach.Core,
    text: *Text,
    pipeline_id: mach.ObjectID,
) !void {
    // Destroy the current pipeline, if built.
    var pipeline = text.render_pipelines.getValue(pipeline_id);
    defer text.render_pipelines.setValueRaw(pipeline_id, pipeline);
    const built_idx = pipeline.built_index.?;
    if (text.built_pipelines.items[built_idx]) |*built| built.deinit(text.allocator);

    // Reference any user-provided objects.
    if (pipeline.shader) |v| v.reference();
    if (pipeline.texture_sampler) |v| v.reference();
    if (pipeline.bind_group_layout) |v| v.reference();
    if (pipeline.bind_group) |v| v.reference();
    if (pipeline.layout) |v| v.reference();

    const window = core.windows.getValue(pipeline.window.?);
    const device = window.device;

    const label = @tagName(mach_module) ++ ".rebuildPipeline";

    // Prepare texture for the font atlas.
    // TODO(text): dynamic texture re-allocation when not large enough
    // TODO(text): better default allocation size
    const img_size = gpu.Extent3D{ .width = 1024, .height = 1024 };
    const texture = device.createTexture(&.{
        .label = label,
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
        },
    });
    const texture_atlas = try gfx.Atlas.init(
        text.allocator,
        img_size.width,
        .rgba,
    );

    const initial_buffer_cap: u32 = 64;

    // Storage buffers
    const transforms = device.createBuffer(&.{
        .label = label ++ " transforms",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(gpu.Mat4x4) * initial_buffer_cap,
        .mapped_at_creation = .false,
    });
    const colors = device.createBuffer(&.{
        .label = label ++ " colors",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(gpu.Vec4) * initial_buffer_cap,
        .mapped_at_creation = .false,
    });
    const glyphs = device.createBuffer(&.{
        .label = label ++ " glyphs",
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf(Glyph) * initial_buffer_cap,
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
            },
        }),
    );

    const texture_view = texture.createView(&gpu.TextureView.Descriptor{ .label = label });
    defer texture_view.release();

    const bind_group = pipeline.bind_group orelse device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .label = label,
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.initBuffer(0, uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
                gpu.BindGroup.Entry.initBuffer(1, transforms, 0, @sizeOf(gpu.Mat4x4) * initial_buffer_cap, @sizeOf(gpu.Mat4x4)),
                gpu.BindGroup.Entry.initBuffer(2, colors, 0, @sizeOf(gpu.Vec4) * initial_buffer_cap, @sizeOf(gpu.Vec4)),
                gpu.BindGroup.Entry.initBuffer(3, glyphs, 0, @sizeOf(Glyph) * initial_buffer_cap, @sizeOf(Glyph)),
                gpu.BindGroup.Entry.initSampler(4, texture_sampler),
                gpu.BindGroup.Entry.initTextureView(5, texture_view),
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

    const shader_module = pipeline.shader orelse device.createShaderModuleWGSL("text.wgsl", @embedFile("text.wgsl"));
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

    text.built_pipelines.items[built_idx] = BuiltPipeline{
        .render = render_pipeline,
        .texture_sampler = texture_sampler,
        .texture = texture,
        .bind_group = bind_group,
        .bind_group_layout = if (owns_bind_group_layout) bind_group_layout else null,
        .uniforms = uniforms,
        .transforms = transforms,
        .colors = colors,
        .glyphs = glyphs,
        .buffer_cap = initial_buffer_cap,
        .texture_atlas = texture_atlas,
    };
    pipeline.num_texts = 0;
    pipeline.num_segments = 0;
    pipeline.num_glyphs = 0;
}

fn updatePipelineBuffers(
    text: *Text,
    core: *mach.Core,
    pipeline_id: mach.ObjectID,
    pipeline_children: []const mach.ObjectID,
) !void {
    var pipeline = text.render_pipelines.getValue(pipeline_id);
    defer text.render_pipelines.setValueRaw(pipeline_id, pipeline);
    const built_idx = pipeline.built_index.?;
    const built = &text.built_pipelines.items[built_idx].?;
    const window = core.windows.getValue(pipeline.window.?);
    const device = window.device;
    const queue = window.queue;

    const label = @tagName(mach_module) ++ ".updatePipelineBuffers";
    const encoder = device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    var glyphs = if (text.glyph_update_buffer) |*b| b else blk: {
        // TODO(text): better default allocation size
        const b = try std.ArrayList(Glyph).initCapacity(text.allocator, 256);
        text.glyph_update_buffer = b;
        break :blk &text.glyph_update_buffer.?;
    };
    glyphs.clearRetainingCapacity();
    text.cp_transforms.clearRetainingCapacity();

    var texture_update = false;
    var num_segments: u32 = 0;
    var i: u32 = 0;
    for (pipeline_children) |text_id| {
        if (!text.render_objects.is(text_id)) continue;
        var t = text.render_objects.getValue(text_id);
        num_segments += @intCast(t.segments.len);

        try text.cp_transforms.append(text.allocator, t.transform.gpu());

        // Changing these fields shouldn't trigger a pipeline rebuild, so clear their update values:
        _ = text.render_objects.updated(text_id, .transform);

        // If the text has been built before, and nothing about it has changed, then we can just use
        // what we built already.
        if (t.built != null and !text.render_objects.anyUpdated(text_id)) {
            for (t.built.?.glyphs.items) |*glyph| glyph.text_index = i;
            try glyphs.appendSlice(text.allocator, t.built.?.glyphs.items);
            i += 1;
            continue;
        }

        // Where we will store the built glyphs for this text entity.
        var built_text = if (t.built) |bt| bt else BuiltText{
            // TODO(text): better default allocations
            .glyphs = try std.ArrayList(Glyph).initCapacity(text.allocator, 64),
        };
        built_text.glyphs.clearRetainingCapacity();

        const px_density = 2.0; // TODO(text): do not hard-code pixel density
        var origin_x: f32 = 0.0;
        var origin_y: f32 = 0.0;
        for (t.segments) |segment| {
            // Load the font
            // TODO(text): allow specifying a custom font
            // TODO(text): keep fonts around for reuse later
            // const font_name = text_style.get(style, .font_name).?;
            // _ = font_name; // TODO(text): actually use font name
            const font_bytes = gfx.default_font;
            var font = if (text.font_once) |f| f else blk: {
                text.font_once = try gfx.Font.initBytes(font_bytes);
                break :blk text.font_once.?;
            };
            // TODO(text)
            // defer font.deinit(allocator);

            const style = text.styles.getValue(segment.style);

            // Create a text shaper
            var run = try gfx.TextRun.init();
            run.font_size_px = style.font_size;
            run.px_density = px_density;
            defer run.deinit();

            run.addText(segment.text);
            try font.shape(&run);

            while (run.next()) |glyph| {
                const codepoint = segment.text[glyph.cluster];
                // TODO(text): use flags(?) to detect newline, or at least something more reliable?
                if (codepoint == '\n') {
                    origin_x = 0;
                    origin_y -= style.font_size;
                    continue;
                }

                const region = try built.regions.getOrPut(text.allocator, .{
                    .index = glyph.glyph_index,
                    .size = @bitCast(style.font_size),
                });
                if (!region.found_existing) {
                    const rendered_glyph = try font.render(text.allocator, glyph.glyph_index, .{
                        .font_size_px = run.font_size_px,
                    });
                    if (rendered_glyph.bitmap) |bitmap| {
                        var glyph_atlas_region = try built.texture_atlas.reserve(text.allocator, rendered_glyph.width, rendered_glyph.height);
                        built.texture_atlas.set(glyph_atlas_region, @as([*]const u8, @ptrCast(bitmap.ptr))[0 .. bitmap.len * 4]);
                        texture_update = true;

                        // Exclude the 1px blank space margin when describing the region of the texture
                        // that actually represents the glyph.
                        const margin = 1;
                        glyph_atlas_region.x += margin;
                        glyph_atlas_region.y += margin;
                        glyph_atlas_region.width -= margin * 2;
                        glyph_atlas_region.height -= margin * 2;
                        region.value_ptr.* = .{
                            .region = glyph_atlas_region,
                            .bearing_x = rendered_glyph.bearing_x,
                            .bearing_y = rendered_glyph.bearing_y,
                        };
                    } else {
                        // whitespace
                        region.value_ptr.* = .{
                            .region = .{ .width = 0, .height = 0, .x = 0, .y = 0 },
                            .bearing_x = rendered_glyph.bearing_x,
                            .bearing_y = rendered_glyph.bearing_y,
                        };
                    }
                }

                const cached = region.value_ptr.*;
                const r = cached.region;
                const size = math.vec2(@floatFromInt(r.width), @floatFromInt(r.height));
                const pos = math.vec2(
                    origin_x + glyph.offset.x() + cached.bearing_x,
                    origin_y - (size.y() - (glyph.offset.y() + cached.bearing_y)),
                ).divScalar(px_density);
                try built_text.glyphs.append(text.allocator, .{
                    .pos = pos.gpu(),
                    .size = size.divScalar(px_density).gpu(),
                    .text_index = i,
                    // TODO(d3d12): this is a hack, having 7 floats before the color vec causes an error
                    .text_padding = 0,
                    .uv_pos = gpu.vec2(@floatFromInt(r.x), @floatFromInt(r.y)),
                    .color = style.color.gpu(),
                });
                origin_x += glyph.advance.x();
            }
        }
        // Update the text entity's built form on both render and app side, so that copyFrom
        // preserves it (same pattern as built_index on pipelines).
        t.built = built_text;
        text.render_objects.setValueRaw(text_id, t);
        text.objects.setRaw(text_id, .built, built_text);

        // Add to the entire set of glyphs for this pipeline
        try glyphs.appendSlice(text.allocator, built_text.glyphs.items);
        i += 1;
    }

    // Every pipeline update, we copy updated glyph and text buffers to the GPU.
    pipeline.num_texts = i;
    pipeline.num_segments = num_segments;
    pipeline.num_glyphs = @intCast(glyphs.items.len);

    // Grow GPU storage buffers and recreate bind group if needed.
    const needed: u32 = @intCast(@max(i, glyphs.items.len));
    if (needed > built.buffer_cap and built.bind_group_layout != null) {
        var new_cap = built.buffer_cap;
        while (new_cap < needed) new_cap *= 2;

        built.transforms.release();
        built.colors.release();
        built.glyphs.release();
        built.bind_group.release();

        built.transforms = device.createBuffer(&.{
            .label = label ++ " transforms",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(gpu.Mat4x4) * new_cap,
            .mapped_at_creation = .false,
        });
        built.colors = device.createBuffer(&.{
            .label = label ++ " colors",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(gpu.Vec4) * new_cap,
            .mapped_at_creation = .false,
        });
        built.glyphs = device.createBuffer(&.{
            .label = label ++ " glyphs",
            .usage = .{ .storage = true, .copy_dst = true },
            .size = @sizeOf(Glyph) * new_cap,
            .mapped_at_creation = .false,
        });

        const texture_view = built.texture.createView(&gpu.TextureView.Descriptor{ .label = label });
        defer texture_view.release();

        built.bind_group = device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .label = label,
                .layout = built.bind_group_layout.?,
                .entries = &.{
                    gpu.BindGroup.Entry.initBuffer(0, built.uniforms, 0, @sizeOf(Uniforms), @sizeOf(Uniforms)),
                    gpu.BindGroup.Entry.initBuffer(1, built.transforms, 0, @sizeOf(gpu.Mat4x4) * new_cap, @sizeOf(gpu.Mat4x4)),
                    gpu.BindGroup.Entry.initBuffer(2, built.colors, 0, @sizeOf(gpu.Vec4) * new_cap, @sizeOf(gpu.Vec4)),
                    gpu.BindGroup.Entry.initBuffer(3, built.glyphs, 0, @sizeOf(Glyph) * new_cap, @sizeOf(Glyph)),
                    gpu.BindGroup.Entry.initSampler(4, built.texture_sampler),
                    gpu.BindGroup.Entry.initTextureView(5, texture_view),
                },
            }),
        );
        built.buffer_cap = new_cap;
    }

    if (glyphs.items.len > 0) encoder.writeBuffer(built.glyphs, 0, glyphs.items);
    if (i > 0) encoder.writeBuffer(built.transforms, 0, text.cp_transforms.items);

    if (texture_update) {
        // TODO(text): do not assume texture's data_layout and img_size here, instead get it from
        // somewhere known to be matching the actual texture.
        //
        // TODO(text): allow users to specify RGBA32 or other pixel formats
        const img_size = gpu.Extent3D{ .width = 1024, .height = 1024 };
        const data_layout = gpu.Texture.DataLayout{
            .bytes_per_row = @as(u32, @intCast(img_size.width * 4)),
            .rows_per_image = @as(u32, @intCast(img_size.height)),
        };
        queue.writeTexture(
            &.{ .texture = built.texture },
            &data_layout,
            &img_size,
            built.texture_atlas.data,
        );
    }

    if (i > 0 or glyphs.items.len > 0) {
        var command = encoder.finish(&.{ .label = label });
        defer command.release();
        queue.submit(&[_]*gpu.CommandBuffer{command});
    }
}

fn renderPipeline(
    text: *Text,
    core: *mach.Core,
    pipeline_id: mach.ObjectID,
    render_pass: *gpu.RenderPassEncoder,
) void {
    const pipeline = text.render_pipelines.getValue(pipeline_id);
    const built = text.built_pipelines.items[pipeline.built_index.?].?;
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
        .texture_size = gpu.vec2(
            @as(f32, @floatFromInt(built.texture.getWidth())),
            @as(f32, @floatFromInt(built.texture.getHeight())),
        ),
    };
    encoder.writeBuffer(built.uniforms, 0, &[_]Uniforms{uniforms});
    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    window.queue.submit(&[_]*gpu.CommandBuffer{command});

    // Draw the text batch
    const total_vertices = pipeline.num_glyphs * 6;
    render_pass.setPipeline(built.render);
    // TODO(text): can we remove unused dynamic offsets?
    render_pass.setBindGroup(0, built.bind_group, &.{});
    render_pass.draw(total_vertices, 1, 0, 0);
}

pub fn deinit(text: *Text) void {
    const allocator = text.allocator;

    var object_ids = text.objects.slice();
    while (object_ids.next()) |text_id| deinitObject(text, text_id);
    var deleted_objects = text.objects.sliceDeleted();
    while (deleted_objects.next()) |text_id| deinitObject(text, text_id);

    var pipeline_ids = text.pipelines.slice();
    while (pipeline_ids.next()) |pipeline_id| {
        var render_list = text.pipelines.get(pipeline_id, .render_list);
        render_list.deinit(allocator);
    }
    var deleted_pipelines = text.pipelines.sliceDeleted();
    while (deleted_pipelines.next()) |pipeline_id| {
        var render_list = text.pipelines.get(pipeline_id, .render_list);
        render_list.deinit(allocator);
    }

    if (text.render_segments) |segments_list| {
        for (segments_list) |segments| {
            for (segments) |segment| allocator.free(@constCast(segment.text));
            allocator.free(segments);
        }
        allocator.free(segments_list);
    }
    for (text.built_pipelines.items) |*built| {
        if (built.*) |*pipeline| pipeline.deinit(allocator);
    }
    for (text.cached_render_lists.items) |*render_list| {
        render_list.deinit(allocator);
    }
    text.built_pipelines.deinit(allocator);
    text.cached_render_lists.deinit(allocator);
    if (text.glyph_update_buffer) |*glyphs| glyphs.deinit(allocator);
    if (text.font_once) |*font| font.deinit(allocator);
    text.cp_transforms.deinit(allocator);
}
