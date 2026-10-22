pub const want_mach: bool = true;
pub const want_core: bool = true;
pub const want_sysaudio: bool = true;
pub const want_sysgpu: bool = true;
pub const @"build.SysgpuBackend" = enum (u3) {
    default = 0,
    webgpu = 1,
    d3d12 = 2,
    metal = 3,
    vulkan = 4,
    opengl = 5,
};
pub const sysgpu_backend: @"build.SysgpuBackend" = .default;
