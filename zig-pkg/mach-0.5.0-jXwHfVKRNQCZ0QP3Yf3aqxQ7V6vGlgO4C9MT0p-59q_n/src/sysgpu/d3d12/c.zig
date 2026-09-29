const builtin = @import("builtin");

pub const c = @cImport({
    // TODO(translate-c): workaround for Zig translate-c failures on aarch64-windows-gnu and x86_64-windows-gnu
    // release builds only:
    if (builtin.target.abi == .gnu) @cDefine("_FORTIFY_SOURCE", "0");

    // TODO(translate-c): workaround for Zig translate-c failures on aarch64-windows-gnu release and debug builds:
    // - aro's stddef.h defines wchar_t via __WCHAR_TYPE__ (unsigned int on aarch64), conflicting
    //   with mingw's corecrt.h which typedefs it as unsigned short
    // - mingw's winnt.h uses `register` storage class on a global variable for __mingw_current_teb
    if (builtin.target.cpu.arch == .aarch64 and builtin.target.os.tag == .windows and builtin.target.abi == .gnu) {
        @cDefine("__WCHAR_TYPE__", "unsigned short");
        @cDefine("register", "");
    }

    @cDefine("CINTERFACE", "");
    @cDefine("COBJMACROS", "");
    @cDefine("WIDL_using_Windows_Foundation", "");
    @cDefine("WIDL_using_Windows_Foundation_Collections", "");
    @cInclude("initguid.h");
    @cInclude("d3d12.h");
    @cInclude("dxgi1_6.h");
    @cInclude("d3dcompiler.h");
    @cInclude("dxgidebug.h");
});
