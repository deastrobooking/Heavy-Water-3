const builtin = @import("builtin");

pub const c = @cImport({
    if (builtin.target.os.tag == .windows) {
        // TODO(translate-c): workaround for Zig translate-c failures on aarch64-windows-gnu and x86_64-windows-gnu
        // release builds only:
        if (builtin.target.abi == .gnu) @cDefine("_FORTIFY_SOURCE", "0");

        // TODO(translate-c): workaround for Zig translate-c failures on aarch64-windows-gnu release and debug builds:
        // - aro's stddef.h defines wchar_t via __WCHAR_TYPE__ (unsigned int on aarch64), conflicting
        //   with mingw's corecrt.h which typedefs it as unsigned short
        // - mingw's winnt.h uses `register` storage class on a global variable for __mingw_current_teb
        if (builtin.target.cpu.arch == .aarch64 and builtin.target.abi == .gnu) {
            @cDefine("__WCHAR_TYPE__", "unsigned short");
            @cDefine("register", "");
        }

        @cInclude("windows.h");
        @cInclude("GL/glcorearb.h");
        @cInclude("GL/glext.h");
        @cInclude("GL/wglext.h");
    } else if (builtin.target.os.tag == .linux) {
        @cInclude("GL/glcorearb.h");
        @cInclude("GL/glext.h");
    }
});
