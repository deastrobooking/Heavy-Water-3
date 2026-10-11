// Translated by the build system (build.zig, `addCImport`) because Zig 0.17 removed @cImport.
// Zig's translate-C (Aro) chokes on _Static_assert in these headers, so define it away.
#define _Static_assert(expr, msg) ((void)0)
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
