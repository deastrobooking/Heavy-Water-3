# Heavy Water Vulkan Zig compatibility patch

This is the `vulkan-zig` generator revision previously pinned by the Mach package (`8dd11cfb44b3897b2cd8b026184306e46e7b1e40`), vendored because its old array-repeat and tuple-reflection syntax blocks Zig 0.17 builds.

The project patch preserves the upstream generator behavior and adds Zig 0.16/0.17 compatibility in `src/vulkan/render.zig` and `src/vulkan/parse.zig`. Keep the upstream license in `LICENSE`; update this note if the base revision or patch set changes.
