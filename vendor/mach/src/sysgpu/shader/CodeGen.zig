const std = @import("std");
const Air = @import("Air.zig");
const genGlsl = @import("codegen/glsl.zig").gen;
const genHlsl = @import("codegen/hlsl.zig").gen;
const genMsl = @import("codegen/msl.zig").gen;
const genSpirv = @import("codegen/spirv.zig").gen;

pub const Language = enum {
    glsl,
    hlsl,
    msl,
    spirv,
};

pub const DebugInfo = struct {
    emit_source_file: ?[]const u8 = null,
    emit_names: bool = true,
};

pub const Stage = enum {
    vertex,
    fragment,
    compute,
};

pub const Entrypoint = struct {
    stage: Stage,
    name: [*:0]const u8,
};

pub const BindingPoint = struct { group: u32, binding: u32 };
pub const BindingTable = std.AutoHashMapUnmanaged(BindingPoint, u32);

pub fn generate(
    allocator: std.mem.Allocator,
    air: *const Air,
    out_lang: Language,
    use_spirv_cross: bool,
    debug_info: DebugInfo,
    entrypoint: ?Entrypoint,
    bindings: ?*const BindingTable,
    label: ?[*:0]const u8,
) ![]const u8 {
    _ = use_spirv_cross;
    // if (!use_spirv_cross) {
    //     const spirv_data = try genSpirv(allocator, air, .{});
    //     const spirv_data_z = try allocator.dupeZ(u8, spirv_data);
    //     defer allocator.free(spirv_data_z);
    //     allocator.free(spirv_data);

    //     const spirv_words_ptr = @as([*]const u32, @ptrCast(@alignCast(spirv_data_z.ptr)));
    //     const spirv_words = spirv_words_ptr[0 .. spirv_data_z.len / @sizeOf(u32)];

    //     // Optimize
    //     var optimized_spirv: c.spv_binary = undefined;
    //     const target_env = spvTargetEnv(out_lang);
    //     const optimizer = c.spvOptimizerCreate(target_env);
    //     defer c.spvOptimizerDestroy(optimizer);

    //     c.spvOptimizerSetMessageConsumer(optimizer, spvMessageConsumer);
    //     c.spvOptimizerRegisterPerformancePasses(optimizer);
    //     c.spvOptimizerRegisterLegalizationPasses(optimizer);

    //     const opt_options = c.spvOptimizerOptionsCreate();
    //     defer c.spvOptimizerOptionsDestroy(opt_options);
    //     c.spvOptimizerOptionsSetRunValidator(opt_options, false);

    //     var res = c.spvOptimizerRun(
    //         optimizer,
    //         spirv_words.ptr,
    //         spirv_words.len,
    //         &optimized_spirv,
    //         opt_options,
    //     );
    //     switch (res) {
    //         c.SPV_SUCCESS => {},
    //         else => return error.SpvOptimizerFailed,
    //     }

    //     if (out_lang == .spirv) {
    //         const code_bytes_ptr = @as([*]const u8, @ptrCast(optimized_spirv.*.code));
    //         const code_bytes = code_bytes_ptr[0 .. optimized_spirv.*.wordCount * @sizeOf(u32)];
    //         return allocator.dupe(u8, code_bytes);
    //     }

    //     // Translate
    //     var context: c.spvc_context = undefined;
    //     _ = c.spvc_context_create(&context);
    //     defer c.spvc_context_destroy(context);
    //     c.spvc_context_set_error_callback(context, spvcErrorCallback, null);

    //     var ir: c.spvc_parsed_ir = undefined;
    //     _ = c.spvc_context_parse_spirv(context, optimized_spirv.*.code, optimized_spirv.*.wordCount, &ir);

    //     var compiler: c.spvc_compiler = undefined;
    //     _ = c.spvc_context_create_compiler(
    //         context,
    //         spvcBackend(out_lang),
    //         ir,
    //         c.SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
    //         &compiler,
    //     );

    //     var resources: c.spvc_resources = undefined;
    //     _ = c.spvc_compiler_create_shader_resources(compiler, &resources);

    //     var options: c.spvc_compiler_options = undefined;
    //     _ = c.spvc_compiler_create_compiler_options(compiler, &options);
    //     switch (out_lang) {
    //         .glsl => {
    //             const resource_types = [_]c.spvc_resource_type{
    //                 c.SPVC_RESOURCE_TYPE_UNIFORM_BUFFER,
    //                 c.SPVC_RESOURCE_TYPE_STORAGE_BUFFER,
    //                 c.SPVC_RESOURCE_TYPE_STORAGE_IMAGE,
    //                 c.SPVC_RESOURCE_TYPE_SAMPLED_IMAGE,
    //                 c.SPVC_RESOURCE_TYPE_SEPARATE_IMAGE,
    //                 c.SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS,
    //             };
    //             for (resource_types) |resource_type| {
    //                 glslRemapResources(compiler, resources, resource_type, bindings orelse &.{});
    //             }

    //             _ = c.spvc_compiler_options_set_uint(options, c.SPVC_COMPILER_OPTION_GLSL_VERSION, 450);
    //             _ = c.spvc_compiler_options_set_bool(options, c.SPVC_COMPILER_OPTION_GLSL_ES, c.SPVC_FALSE);
    //             if (entrypoint) |e| {
    //                 _ = c.spvc_compiler_set_entry_point(compiler, e.name, spvExecutionModel(e.stage));
    //             }

    //             // combiner samplers/textures
    //             var id: c.spvc_variable_id = undefined;
    //             res = c.spvc_compiler_build_dummy_sampler_for_combined_images(compiler, &id);
    //             if (res == c.SPVC_SUCCESS) {
    //                 c.spvc_compiler_set_decoration(compiler, id, c.SpvDecorationDescriptorSet, 0);
    //                 c.spvc_compiler_set_decoration(compiler, id, c.SpvDecorationBinding, 0);
    //             }
    //             _ = c.spvc_compiler_build_combined_image_samplers(compiler);
    //         },
    //         else => @panic("TODO"),
    //     }
    //     _ = c.spvc_compiler_install_compiler_options(compiler, options);

    //     var source: [*c]const u8 = undefined;
    //     _ = c.spvc_compiler_compile(compiler, &source);

    //     return allocator.dupe(u8, std.mem.span(source));
    // }

    // Direct translation
    return switch (out_lang) {
        .spirv => try genSpirv(allocator, air, debug_info),
        .hlsl => try genHlsl(allocator, air, debug_info),
        .msl => try genMsl(allocator, air, debug_info, entrypoint, bindings, label orelse "<ShaderModule label not specified>"),
        .glsl => try genGlsl(allocator, air, debug_info, entrypoint, bindings),
    };
}

// The spirv-cross and spirv-tools helpers that lived here (`spvMessageConsumer`, `spvTargetEnv`,
// `spvExecutionModel`, `spvcBackend`, `glslRemapResources`) were unreferenced and imported headers no
// build dependency provides; Zig 0.17 removed the `@cImport` they needed. See git history to restore.
