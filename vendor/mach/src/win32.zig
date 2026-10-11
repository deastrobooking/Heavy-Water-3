const std = @import("std");
const builtin = @import("builtin");
pub const L = std.unicode.utf8ToUtf16LeStringLiteral;

const w = std.os.windows;
pub const BOOL = i32;
pub const HWND = w.HWND;
pub const HRESULT = i32;
pub const HINSTANCE = w.HINSTANCE;
pub const CHAR = w.CHAR;
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};
pub const FILETIME = w.FILETIME;
pub const POINT = extern struct {
    x: i32,
    y: i32,
};
pub const HANDLE = w.HANDLE;
pub const PWSTR = w.PWSTR;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HICON = w.HICON;
pub const HCURSOR = w.HCURSOR;
pub const HBRUSH = w.HBRUSH;
pub const HMENU = w.HMENU;
pub const HMONITOR = *opaque {};
pub const HDC = w.HDC;
pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub fn FAILED(hr: HRESULT) bool {
    return hr < 0;
}
pub fn SUCCEEDED(hr: HRESULT) bool {
    return hr >= 0;
}

pub const SIZE = extern struct {
    cx: i32,
    cy: i32,
};

pub const WIN32_ERROR = u32;
pub extern "kernel32" fn GetLastError() callconv(.winapi) WIN32_ERROR;

//pub const GetModuleHandleW = w.kernel32.GetModuleHandleW;
// TODO: this type is limited to platform 'windows5.1.2600'
pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?[*:0]const u16,
) callconv(.winapi) ?HINSTANCE;

pub const KF_REPEAT = @as(u32, 16384);
pub const CW_USEDEFAULT = @as(i32, -2147483648);
pub const DIRECTINPUT_VERSION = @as(u32, 2048);
pub const DI_OK = @as(i32, 0);
pub const DI_NOTATTACHED = @as(i32, 1);
pub const DI_BUFFEROVERFLOW = @as(i32, 1);
pub const DI_PROPNOEFFECT = @as(i32, 1);
pub const DI_NOEFFECT = @as(i32, 1);

//--------------------------------------------------------------------------------
// Section: Functions (47)
//--------------------------------------------------------------------------------
pub extern "dinput8" fn DirectInput8Create(
    hinst: ?HINSTANCE,
    dwVersion: u32,
    riidltf: ?*const Guid,
    ppvOut: ?*?*anyopaque,
    punkOuter: ?*IUnknown,
) callconv(.winapi) HRESULT;

pub const MOUSEHOOKSTRUCTEX_MOUSE_DATA = packed struct(u32) {
    @"1": u1 = 0,
    @"2": u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const XBUTTON1 = MOUSEHOOKSTRUCTEX_MOUSE_DATA{ .@"1" = 1 };
pub const XBUTTON2 = MOUSEHOOKSTRUCTEX_MOUSE_DATA{ .@"2" = 1 };
pub extern "user32" fn GetClientRect(
    hWnd: ?HWND,
    lpRect: ?*RECT,
) callconv(.winapi) BOOL;
// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetWindowRect(
    hWnd: ?HWND,
    lpRect: ?*RECT,
) callconv(.winapi) BOOL;

pub extern "user32" fn AdjustWindowRectExForDpi(
    lpRect: ?*RECT,
    dwStyle: WINDOW_STYLE,
    bMenu: BOOL,
    dwExStyle: WINDOW_EX_STYLE,
    dpi: u32,
) callconv(.winapi) BOOL;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetMessageTime() callconv(.winapi) i32;
// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn TranslateMessage(lpMsg: ?*const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: ?*const MSG) callconv(.winapi) LRESULT;

pub extern "user32" fn PeekMessageW(
    lpMsg: ?*MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
    wRemoveMsg: PEEK_MESSAGE_REMOVE_TYPE,
) callconv(.winapi) BOOL;
pub const PEEK_MESSAGE_REMOVE_TYPE = packed struct(u32) {
    REMOVE: u1 = 0,
    NOYIELD: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    QS_PAINT: u1 = 0,
    QS_SENDMESSAGE: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const PM_NOREMOVE = PEEK_MESSAGE_REMOVE_TYPE{};
pub const PM_REMOVE = PEEK_MESSAGE_REMOVE_TYPE{ .REMOVE = 1 };
pub const PM_NOYIELD = PEEK_MESSAGE_REMOVE_TYPE{ .NOYIELD = 1 };
pub const PM_QS_INPUT = PEEK_MESSAGE_REMOVE_TYPE{
    ._16 = 1,
    ._17 = 1,
    ._18 = 1,
    ._26 = 1,
};
pub const PM_QS_POSTMESSAGE = PEEK_MESSAGE_REMOVE_TYPE{
    ._19 = 1,
    ._20 = 1,
    ._23 = 1,
};
pub const PM_QS_PAINT = PEEK_MESSAGE_REMOVE_TYPE{ .QS_PAINT = 1 };
pub const PM_QS_SENDMESSAGE = PEEK_MESSAGE_REMOVE_TYPE{ .QS_SENDMESSAGE = 1 };

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
};

pub const WINDOW_LONG_PTR_INDEX = enum(i32) {
    _EXSTYLE = -20,
    P_HINSTANCE = -6,
    P_HWNDPARENT = -8,
    P_ID = -12,
    _STYLE = -16,
    P_USERDATA = -21,
    P_WNDPROC = -4,
    // _HINSTANCE = -6, this enum value conflicts with P_HINSTANCE
    // _ID = -12, this enum value conflicts with P_ID
    // _USERDATA = -21, this enum value conflicts with P_USERDATA
    // _WNDPROC = -4, this enum value conflicts with P_WNDPROC
    // _HWNDPARENT = -8, this enum value conflicts with P_HWNDPARENT
    _,
};
pub const GWL_EXSTYLE = WINDOW_LONG_PTR_INDEX._EXSTYLE;
pub const GWLP_HINSTANCE = WINDOW_LONG_PTR_INDEX.P_HINSTANCE;
pub const GWLP_HWNDPARENT = WINDOW_LONG_PTR_INDEX.P_HWNDPARENT;
pub const GWLP_ID = WINDOW_LONG_PTR_INDEX.P_ID;
pub const GWL_STYLE = WINDOW_LONG_PTR_INDEX._STYLE;
pub const GWLP_USERDATA = WINDOW_LONG_PTR_INDEX.P_USERDATA;
pub const GWLP_WNDPROC = WINDOW_LONG_PTR_INDEX.P_WNDPROC;
pub const GWL_HINSTANCE = WINDOW_LONG_PTR_INDEX.P_HINSTANCE;
pub const GWL_ID = WINDOW_LONG_PTR_INDEX.P_ID;
pub const GWL_USERDATA = WINDOW_LONG_PTR_INDEX.P_USERDATA;
pub const GWL_WNDPROC = WINDOW_LONG_PTR_INDEX.P_WNDPROC;
pub const GWL_HWNDPARENT = WINDOW_LONG_PTR_INDEX.P_HWNDPARENT;

pub const Arch = enum { X86, X64, Arm64 };
pub const arch: Arch = switch (builtin.target.cpu.arch) {
    .x86 => .X86,
    .x86_64 => .X64,
    .arm, .armeb, .aarch64 => .Arm64,
    else => @compileError("unhandled arch " ++ @tagName(builtin.target.cpu.arch)),
};

pub const GetWindowLongPtrW = switch (arch) {
    .X64, .Arm64 => (struct {
        pub extern "user32" fn GetWindowLongPtrW(
            hWnd: ?HWND,
            nIndex: WINDOW_LONG_PTR_INDEX,
        ) callconv(.winapi) isize;
    }).GetWindowLongPtrW,
    .X86 => (struct {
        pub extern "user32" fn GetWindowLongW(
            hWnd: ?HWND,
            nIndex: WINDOW_LONG_PTR_INDEX,
        ) callconv(.winapi) i32;
    }).GetWindowLongW,
};

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn SetCursor(
    hCursor: ?HCURSOR,
) callconv(.winapi) ?HCURSOR;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetCursorPos(
    lpPoint: ?*POINT,
) callconv(.winapi) BOOL;

pub extern "user32" fn SetCursorPos(
    X: i32,
    Y: i32,
) callconv(.winapi) BOOL;

pub const SetWindowLongPtrW = switch (arch) {
    .X64, .Arm64 => (struct {
        pub extern "user32" fn SetWindowLongPtrW(
            hWnd: ?HWND,
            nIndex: WINDOW_LONG_PTR_INDEX,
            dwNewLong: isize,
        ) callconv(.winapi) isize;
    }).SetWindowLongPtrW,
    .X86 => (struct {
        pub extern "user32" fn SetWindowLongW(
            hWnd: ?HWND,
            nIndex: WINDOW_LONG_PTR_INDEX,
            dwNewLong: i32,
        ) callconv(.winapi) i32;
    }).SetWindowLongW,
};

pub extern "user32" fn SetWindowLongW(
    hWnd: ?HWND,
    nIndex: WINDOW_LONG_PTR_INDEX,
    dwNewLong: i32,
) callconv(.winapi) i32;

pub extern "user32" fn BringWindowToTop(
    hWnd: ?HWND,
) callconv(.winapi) BOOL;

pub extern "user32" fn SetForegroundWindow(
    hWnd: ?HWND,
) callconv(.winapi) BOOL;

//pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: u32) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(
    hWnd: ?HWND,
    hWndInsertAfter: ?HWND,
    X: i32,
    Y: i32,
    cx: i32,
    cy: i32,
    uFlags: SET_WINDOW_POS_FLAGS,
) callconv(.winapi) BOOL;

pub const SET_WINDOW_POS_FLAGS = packed struct(u32) {
    NOSIZE: u1 = 0,
    NOMOVE: u1 = 0,
    NOZORDER: u1 = 0,
    NOREDRAW: u1 = 0,
    NOACTIVATE: u1 = 0,
    DRAWFRAME: u1 = 0,
    SHOWWINDOW: u1 = 0,
    HIDEWINDOW: u1 = 0,
    NOCOPYBITS: u1 = 0,
    NOOWNERZORDER: u1 = 0,
    NOSENDCHANGING: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    DEFERERASE: u1 = 0,
    ASYNCWINDOWPOS: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
    // FRAMECHANGED (bit index 5) conflicts with DRAWFRAME
    // NOREPOSITION (bit index 9) conflicts with NOOWNERZORDER
};
pub const SWP_ASYNCWINDOWPOS = SET_WINDOW_POS_FLAGS{ .ASYNCWINDOWPOS = 1 };
pub const SWP_DEFERERASE = SET_WINDOW_POS_FLAGS{ .DEFERERASE = 1 };
pub const SWP_DRAWFRAME = SET_WINDOW_POS_FLAGS{ .DRAWFRAME = 1 };
pub const SWP_FRAMECHANGED = SET_WINDOW_POS_FLAGS{ .DRAWFRAME = 1 };
pub const SWP_HIDEWINDOW = SET_WINDOW_POS_FLAGS{ .HIDEWINDOW = 1 };
pub const SWP_NOACTIVATE = SET_WINDOW_POS_FLAGS{ .NOACTIVATE = 1 };
pub const SWP_NOCOPYBITS = SET_WINDOW_POS_FLAGS{ .NOCOPYBITS = 1 };
pub const SWP_NOMOVE = SET_WINDOW_POS_FLAGS{ .NOMOVE = 1 };
pub const SWP_NOOWNERZORDER = SET_WINDOW_POS_FLAGS{ .NOOWNERZORDER = 1 };
pub const SWP_NOREDRAW = SET_WINDOW_POS_FLAGS{ .NOREDRAW = 1 };
pub const SWP_NOREPOSITION = SET_WINDOW_POS_FLAGS{ .NOOWNERZORDER = 1 };
pub const SWP_NOSENDCHANGING = SET_WINDOW_POS_FLAGS{ .NOSENDCHANGING = 1 };
pub const SWP_NOSIZE = SET_WINDOW_POS_FLAGS{ .NOSIZE = 1 };
pub const SWP_NOZORDER = SET_WINDOW_POS_FLAGS{ .NOZORDER = 1 };
pub const SWP_SHOWWINDOW = SET_WINDOW_POS_FLAGS{ .SHOWWINDOW = 1 };

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn SetWindowTextW(
    hWnd: ?HWND,
    lpString: ?[*:0]const u16,
) callconv(.winapi) BOOL;

pub fn typedConst(comptime T: type, comptime value: anytype) T {
    return typedConst2(T, T, value);
}

fn typedConst2(comptime ReturnType: type, comptime SwitchType: type, comptime value: anytype) ReturnType {
    const value_type_error = @as([]const u8, "typedConst cannot convert " ++ @typeName(@TypeOf(value)) ++ " to " ++ @typeName(ReturnType));

    switch (@typeInfo(SwitchType)) {
        .int => {
            return value;
        },
        .pointer => |target_type_info| switch (target_type_info.size) {
            .one, .many, .c => {
                switch (@typeInfo(@TypeOf(value))) {
                    .comptime_int, .int => {
                        const usize_value = if (value >= 0) value else @as(usize, @bitCast(@as(isize, value)));
                        return @as(ReturnType, @ptrFromInt(usize_value));
                    },
                    else => @compileError(value_type_error),
                }
            },
            else => @compileError(value_type_error),
        },
        .optional => |target_type_info| switch (@typeInfo(target_type_info.child)) {
            .pointer => return typedConst2(ReturnType, target_type_info.child, value),
            else => @compileError(value_type_error),
        },
        .@"enum" => switch (@typeInfo(@TypeOf(value))) {
            .int => return @as(ReturnType, @enumFromInt(value)),
            else => @compileError(value_type_error),
        },
        else => @compileError(value_type_error),
    }
}

fn hexVal(c: u8) u4 {
    if (c <= '9') return @as(u4, @intCast(c - '0'));
    if (c >= 'a') return @as(u4, @intCast(c + 10 - 'a'));
    return @as(u4, @intCast(c + 10 - 'A'));
}

fn decodeHexByte(hex: [2]u8) u8 {
    return @as(u8, @intCast(hexVal(hex[0]))) << 4 | hexVal(hex[1]);
}

// TODO: this should probably be in the standard lib somewhere?
pub const Guid = extern union {
    Ints: extern struct {
        a: u32,
        b: u16,
        c: u16,
        d: [8]u8,
    },
    Bytes: [16]u8,

    const big_endian_hex_offsets = [16]u6{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
    const little_endian_hex_offsets = [16]u6{ 6, 4, 2, 0, 11, 9, 16, 14, 19, 21, 24, 26, 28, 30, 32, 34 };

    const hex_offsets = switch (builtin.target.cpu.arch.endian()) {
        .big => big_endian_hex_offsets,
        .little => little_endian_hex_offsets,
    };

    pub fn initString(s: []const u8) Guid {
        var guid = Guid{ .Bytes = undefined };
        for (hex_offsets, 0..) |hex_offset, i| {
            guid.Bytes[i] = decodeHexByte([2]u8{ s[hex_offset], s[hex_offset + 1] });
        }
        return guid;
    }
};
comptime {
    std.debug.assert(@sizeOf(Guid) == 16);
}

pub const DIDEVICEINSTANCEA = extern struct {
    dwSize: u32,
    guidInstance: Guid,
    guidProduct: Guid,
    dwDevType: u32,
    tszInstanceName: [260]CHAR,
    tszProductName: [260]CHAR,
    guidFFDriver: Guid,
    wUsagePage: u16,
    wUsage: u16,
};

pub const DIDEVICEINSTANCEW = extern struct {
    dwSize: u32,
    guidInstance: Guid,
    guidProduct: Guid,
    dwDevType: u32,
    tszInstanceName: [260]u16,
    tszProductName: [260]u16,
    guidFFDriver: Guid,
    wUsagePage: u16,
    wUsage: u16,
};

pub const LPDIENUMDEVICESCALLBACKA = *const fn (
    param0: ?*DIDEVICEINSTANCEA,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const LPDIENUMDEVICESCALLBACKW = *const fn (
    param0: ?*DIDEVICEINSTANCEW,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const LPDICONFIGUREDEVICESCALLBACK = *const fn (
    param0: ?*IUnknown,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

const IID_IUnknown_Value = Guid.initString("00000000-0000-0000-c000-000000000046");
pub const IID_IUnknown = &IID_IUnknown_Value;
pub const IUnknown = extern union {
    pub const VTable = extern struct {
        QueryInterface: *const fn (
            self: *const IUnknown,
            riid: *const Guid,
            ppvObject: **anyopaque,
        ) callconv(.winapi) HRESULT,
        AddRef: *const fn (
            self: *const IUnknown,
        ) callconv(.winapi) u32,
        Release: *const fn (
            self: *const IUnknown,
        ) callconv(.winapi) u32,
    };
    vtable: *const VTable,
    pub inline fn QueryInterface(self: *const IUnknown, riid: *const Guid, ppvObject: **anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, ppvObject);
    }
    pub inline fn AddRef(self: *const IUnknown) u32 {
        return self.vtable.AddRef(self);
    }
    pub inline fn Release(self: *const IUnknown) u32 {
        return self.vtable.Release(self);
    }
};

const IID_IDirectInput8W_Value = Guid.initString("bf798031-483a-4da2-aa99-5d64ed369700");
pub const IID_IDirectInput8W = &IID_IDirectInput8W_Value;
pub const IDirectInput8W = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        CreateDevice: *const fn (
            self: *const IDirectInput8W,
            param0: ?*const Guid,
            param1: ?*?*IDirectInputDevice8W,
            param2: ?*IUnknown,
        ) callconv(.winapi) HRESULT,
        EnumDevices: *const fn (
            self: *const IDirectInput8W,
            param0: u32,
            param1: ?LPDIENUMDEVICESCALLBACKW,
            param2: ?*anyopaque,
            param3: u32,
        ) callconv(.winapi) HRESULT,
        GetDeviceStatus: *const fn (
            self: *const IDirectInput8W,
            param0: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        RunControlPanel: *const fn (
            self: *const IDirectInput8W,
            param0: ?HWND,
            param1: u32,
        ) callconv(.winapi) HRESULT,
        Initialize: *const fn (
            self: *const IDirectInput8W,
            param0: ?HINSTANCE,
            param1: u32,
        ) callconv(.winapi) HRESULT,
        FindDevice: *const fn (
            self: *const IDirectInput8W,
            param0: ?*const Guid,
            param1: ?[*:0]const u16,
            param2: ?*Guid,
        ) callconv(.winapi) HRESULT,
        EnumDevicesBySemantics: *const fn (
            self: *const IDirectInput8W,
            param0: ?[*:0]const u16,
            param1: ?*DIACTIONFORMATW,
            param2: ?LPDIENUMDEVICESBYSEMANTICSCBW,
            param3: ?*anyopaque,
            param4: u32,
        ) callconv(.winapi) HRESULT,
        ConfigureDevices: *const fn (
            self: *const IDirectInput8W,
            param0: ?LPDICONFIGUREDEVICESCALLBACK,
            param1: ?*DICONFIGUREDEVICESPARAMSW,
            param2: u32,
            param3: ?*anyopaque,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn CreateDevice(self: *const IDirectInput8W, param0: ?*const Guid, param1: ?*?*IDirectInputDevice8W, param2: ?*IUnknown) HRESULT {
        return self.vtable.CreateDevice(self, param0, param1, param2);
    }
    pub inline fn EnumDevices(self: *const IDirectInput8W, param0: u32, param1: ?LPDIENUMDEVICESCALLBACKW, param2: ?*anyopaque, param3: u32) HRESULT {
        return self.vtable.EnumDevices(self, param0, param1, param2, param3);
    }
    pub inline fn GetDeviceStatus(self: *const IDirectInput8W, param0: ?*const Guid) HRESULT {
        return self.vtable.GetDeviceStatus(self, param0);
    }
    pub inline fn RunControlPanel(self: *const IDirectInput8W, param0: ?HWND, param1: u32) HRESULT {
        return self.vtable.RunControlPanel(self, param0, param1);
    }
    pub inline fn Initialize(self: *const IDirectInput8W, param0: ?HINSTANCE, param1: u32) HRESULT {
        return self.vtable.Initialize(self, param0, param1);
    }
    pub inline fn FindDevice(self: *const IDirectInput8W, param0: ?*const Guid, param1: ?[*:0]const u16, param2: ?*Guid) HRESULT {
        return self.vtable.FindDevice(self, param0, param1, param2);
    }
    pub inline fn EnumDevicesBySemantics(self: *const IDirectInput8W, param0: ?[*:0]const u16, param1: ?*DIACTIONFORMATW, param2: ?LPDIENUMDEVICESBYSEMANTICSCBW, param3: ?*anyopaque, param4: u32) HRESULT {
        return self.vtable.EnumDevicesBySemantics(self, param0, param1, param2, param3, param4);
    }
    pub inline fn ConfigureDevices(self: *const IDirectInput8W, param0: ?LPDICONFIGUREDEVICESCALLBACK, param1: ?*DICONFIGUREDEVICESPARAMSW, param2: u32, param3: ?*anyopaque) HRESULT {
        return self.vtable.ConfigureDevices(self, param0, param1, param2, param3);
    }
};

const IID_IDirectInputDevice8W_Value = Guid.initString("54d41081-dc15-4833-a41b-748f73a38179");
pub const IID_IDirectInputDevice8W = &IID_IDirectInputDevice8W_Value;
pub const IDirectInputDevice8W = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetCapabilities: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIDEVCAPS) callconv(.winapi) HRESULT,
        EnumObjects: *const fn (self: *const IDirectInputDevice8W, param0: ?LPDIENUMDEVICEOBJECTSCALLBACKW, param1: ?*anyopaque, param2: u32) callconv(.winapi) HRESULT,
        GetProperty: *const fn (self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIPROPHEADER) callconv(.winapi) HRESULT,
        SetProperty: *const fn (self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIPROPHEADER) callconv(.winapi) HRESULT,
        Acquire: *const fn (self: *const IDirectInputDevice8W) callconv(.winapi) HRESULT,
        Unacquire: *const fn (self: *const IDirectInputDevice8W) callconv(.winapi) HRESULT,
        GetDeviceState: *const fn (self: *const IDirectInputDevice8W, param0: u32, param1: ?*anyopaque) callconv(.winapi) HRESULT,
        GetDeviceData: *const fn (self: *const IDirectInputDevice8W, param0: u32, param1: ?*DIDEVICEOBJECTDATA, param2: ?*u32, param3: u32) callconv(.winapi) HRESULT,
        SetDataFormat: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIDATAFORMAT) callconv(.winapi) HRESULT,
        SetEventNotification: *const fn (self: *const IDirectInputDevice8W, param0: ?HANDLE) callconv(.winapi) HRESULT,
        SetCooperativeLevel: *const fn (self: *const IDirectInputDevice8W, param0: ?HWND, param1: u32) callconv(.winapi) HRESULT,
        GetObjectInfo: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIDEVICEOBJECTINSTANCEW, param1: u32, param2: u32) callconv(.winapi) HRESULT,
        GetDeviceInfo: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIDEVICEINSTANCEW) callconv(.winapi) HRESULT,
        RunControlPanel: *const fn (self: *const IDirectInputDevice8W, param0: ?HWND, param1: u32) callconv(.winapi) HRESULT,
        Initialize: *const fn (self: *const IDirectInputDevice8W, param0: ?HINSTANCE, param1: u32, param2: ?*const Guid) callconv(.winapi) HRESULT,
        CreateEffect: *const fn (self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIEFFECT, param2: ?*?*IDirectInputEffect, param3: ?*IUnknown) callconv(.winapi) HRESULT,
        EnumEffects: *const fn (self: *const IDirectInputDevice8W, param0: ?LPDIENUMEFFECTSCALLBACKW, param1: ?*anyopaque, param2: u32) callconv(.winapi) HRESULT,
        GetEffectInfo: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIEFFECTINFOW, param1: ?*const Guid) callconv(.winapi) HRESULT,
        GetForceFeedbackState: *const fn (self: *const IDirectInputDevice8W, param0: ?*u32) callconv(.winapi) HRESULT,
        SendForceFeedbackCommand: *const fn (self: *const IDirectInputDevice8W, param0: u32) callconv(.winapi) HRESULT,
        EnumCreatedEffectObjects: *const fn (self: *const IDirectInputDevice8W, param0: ?LPDIENUMCREATEDEFFECTOBJECTSCALLBACK, param1: ?*anyopaque, param2: u32) callconv(.winapi) HRESULT,
        Escape: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIEFFESCAPE) callconv(.winapi) HRESULT,
        Poll: *const fn (self: *const IDirectInputDevice8W) callconv(.winapi) HRESULT,
        SendDeviceData: *const fn (self: *const IDirectInputDevice8W, param0: u32, param1: ?*DIDEVICEOBJECTDATA, param2: ?*u32, param3: u32) callconv(.winapi) HRESULT,
        EnumEffectsInFile: *const fn (self: *const IDirectInputDevice8W, param0: ?[*:0]const u16, param1: ?LPDIENUMEFFECTSINFILECALLBACK, param2: ?*anyopaque, param3: u32) callconv(.winapi) HRESULT,
        WriteEffectToFile: *const fn (self: *const IDirectInputDevice8W, param0: ?[*:0]const u16, param1: u32, param2: ?*DIFILEEFFECT, param3: u32) callconv(.winapi) HRESULT,
        BuildActionMap: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIACTIONFORMATW, param1: ?[*:0]const u16, param2: u32) callconv(.winapi) HRESULT,
        SetActionMap: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIACTIONFORMATW, param1: ?[*:0]const u16, param2: u32) callconv(.winapi) HRESULT,
        GetImageInfo: *const fn (self: *const IDirectInputDevice8W, param0: ?*DIDEVICEIMAGEINFOHEADERW) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetCapabilities(self: *const IDirectInputDevice8W, param0: ?*DIDEVCAPS) HRESULT {
        return self.vtable.GetCapabilities(self, param0);
    }
    pub inline fn EnumObjects(self: *const IDirectInputDevice8W, param0: ?LPDIENUMDEVICEOBJECTSCALLBACKW, param1: ?*anyopaque, param2: u32) HRESULT {
        return self.vtable.EnumObjects(self, param0, param1, param2);
    }
    pub inline fn GetProperty(self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIPROPHEADER) HRESULT {
        return self.vtable.GetProperty(self, param0, param1);
    }
    pub inline fn SetProperty(self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIPROPHEADER) HRESULT {
        return self.vtable.SetProperty(self, param0, param1);
    }
    pub inline fn Acquire(self: *const IDirectInputDevice8W) HRESULT {
        return self.vtable.Acquire(self);
    }
    pub inline fn Unacquire(self: *const IDirectInputDevice8W) HRESULT {
        return self.vtable.Unacquire(self);
    }
    pub inline fn GetDeviceState(self: *const IDirectInputDevice8W, param0: u32, param1: ?*anyopaque) HRESULT {
        return self.vtable.GetDeviceState(self, param0, param1);
    }
    pub inline fn GetDeviceData(self: *const IDirectInputDevice8W, param0: u32, param1: ?*DIDEVICEOBJECTDATA, param2: ?*u32, param3: u32) HRESULT {
        return self.vtable.GetDeviceData(self, param0, param1, param2, param3);
    }
    pub inline fn SetDataFormat(self: *const IDirectInputDevice8W, param0: ?*DIDATAFORMAT) HRESULT {
        return self.vtable.SetDataFormat(self, param0);
    }
    pub inline fn SetEventNotification(self: *const IDirectInputDevice8W, param0: ?HANDLE) HRESULT {
        return self.vtable.SetEventNotification(self, param0);
    }
    pub inline fn SetCooperativeLevel(self: *const IDirectInputDevice8W, param0: ?HWND, param1: u32) HRESULT {
        return self.vtable.SetCooperativeLevel(self, param0, param1);
    }
    pub inline fn GetObjectInfo(self: *const IDirectInputDevice8W, param0: ?*DIDEVICEOBJECTINSTANCEW, param1: u32, param2: u32) HRESULT {
        return self.vtable.GetObjectInfo(self, param0, param1, param2);
    }
    pub inline fn GetDeviceInfo(self: *const IDirectInputDevice8W, param0: ?*DIDEVICEINSTANCEW) HRESULT {
        return self.vtable.GetDeviceInfo(self, param0);
    }
    pub inline fn RunControlPanel(self: *const IDirectInputDevice8W, param0: ?HWND, param1: u32) HRESULT {
        return self.vtable.RunControlPanel(self, param0, param1);
    }
    pub inline fn Initialize(self: *const IDirectInputDevice8W, param0: ?HINSTANCE, param1: u32, param2: ?*const Guid) HRESULT {
        return self.vtable.Initialize(self, param0, param1, param2);
    }
    pub inline fn CreateEffect(self: *const IDirectInputDevice8W, param0: ?*const Guid, param1: ?*DIEFFECT, param2: ?*?*IDirectInputEffect, param3: ?*IUnknown) HRESULT {
        return self.vtable.CreateEffect(self, param0, param1, param2, param3);
    }
    pub inline fn EnumEffects(self: *const IDirectInputDevice8W, param0: ?LPDIENUMEFFECTSCALLBACKW, param1: ?*anyopaque, param2: u32) HRESULT {
        return self.vtable.EnumEffects(self, param0, param1, param2);
    }
    pub inline fn GetEffectInfo(self: *const IDirectInputDevice8W, param0: ?*DIEFFECTINFOW, param1: ?*const Guid) HRESULT {
        return self.vtable.GetEffectInfo(self, param0, param1);
    }
    pub inline fn GetForceFeedbackState(self: *const IDirectInputDevice8W, param0: ?*u32) HRESULT {
        return self.vtable.GetForceFeedbackState(self, param0);
    }
    pub inline fn SendForceFeedbackCommand(self: *const IDirectInputDevice8W, param0: u32) HRESULT {
        return self.vtable.SendForceFeedbackCommand(self, param0);
    }
    pub inline fn EnumCreatedEffectObjects(self: *const IDirectInputDevice8W, param0: ?LPDIENUMCREATEDEFFECTOBJECTSCALLBACK, param1: ?*anyopaque, param2: u32) HRESULT {
        return self.vtable.EnumCreatedEffectObjects(self, param0, param1, param2);
    }
    pub inline fn Escape(self: *const IDirectInputDevice8W, param0: ?*DIEFFESCAPE) HRESULT {
        return self.vtable.Escape(self, param0);
    }
    pub inline fn Poll(self: *const IDirectInputDevice8W) HRESULT {
        return self.vtable.Poll(self);
    }
    pub inline fn SendDeviceData(self: *const IDirectInputDevice8W, param0: u32, param1: ?*DIDEVICEOBJECTDATA, param2: ?*u32, param3: u32) HRESULT {
        return self.vtable.SendDeviceData(self, param0, param1, param2, param3);
    }
    pub inline fn EnumEffectsInFile(self: *const IDirectInputDevice8W, param0: ?[*:0]const u16, param1: ?LPDIENUMEFFECTSINFILECALLBACK, param2: ?*anyopaque, param3: u32) HRESULT {
        return self.vtable.EnumEffectsInFile(self, param0, param1, param2, param3);
    }
    pub inline fn WriteEffectToFile(self: *const IDirectInputDevice8W, param0: ?[*:0]const u16, param1: u32, param2: ?*DIFILEEFFECT, param3: u32) HRESULT {
        return self.vtable.WriteEffectToFile(self, param0, param1, param2, param3);
    }
    pub inline fn BuildActionMap(self: *const IDirectInputDevice8W, param0: ?*DIACTIONFORMATW, param1: ?[*:0]const u16, param2: u32) HRESULT {
        return self.vtable.BuildActionMap(self, param0, param1, param2);
    }
    pub inline fn SetActionMap(self: *const IDirectInputDevice8W, param0: ?*DIACTIONFORMATW, param1: ?[*:0]const u16, param2: u32) HRESULT {
        return self.vtable.SetActionMap(self, param0, param1, param2);
    }
    pub inline fn GetImageInfo(self: *const IDirectInputDevice8W, param0: ?*DIDEVICEIMAGEINFOHEADERW) HRESULT {
        return self.vtable.GetImageInfo(self, param0);
    }
    pub inline fn QueryInterface(self: *const IDirectInputDevice8W, riid: *const Guid, ppvObject: **anyopaque) HRESULT {
        return self.vtable.base.QueryInterface(self, riid, ppvObject);
    }
    pub inline fn AddRef(self: *const IDirectInputDevice8W) u32 {
        return self.vtable.base.AddRef(self);
    }
    pub inline fn Release(self: *const IDirectInputDevice8W) u32 {
        return self.vtable.base.Release(self);
    }
};

pub const DIACTIONFORMATW = extern struct {
    dwSize: u32,
    dwActionSize: u32,
    dwDataSize: u32,
    dwNumActions: u32,
    rgoAction: ?*DIACTIONW,
    guidActionMap: Guid,
    dwGenre: u32,
    dwBufferSize: u32,
    lAxisMin: i32,
    lAxisMax: i32,
    hInstString: ?HINSTANCE,
    ftTimeStamp: FILETIME,
    dwCRC: u32,
    tszActionMap: [260]u16,
};

pub const DIACTIONW = extern struct {
    uAppData: usize,
    dwSemantic: u32,
    dwFlags: u32,
    Anonymous: extern union {
        lptszActionName: ?[*:0]const u16,
        uResIdString: u32,
    },
    guidInstance: Guid,
    dwObjID: u32,
    dwHow: u32,
};

pub const DIDEVICEIMAGEINFOHEADERW = extern struct {
    dwSize: u32,
    dwSizeImageInfo: u32,
    dwcViews: u32,
    dwcButtons: u32,
    dwcAxes: u32,
    dwcPOVs: u32,
    dwBufferSize: u32,
    dwBufferUsed: u32,
    lprgImageInfoArray: ?*DIDEVICEIMAGEINFOW,
};

pub const DIDEVICEIMAGEINFOW = extern struct {
    tszImagePath: [260]u16,
    dwFlags: u32,
    dwViewID: u32,
    rcOverlay: RECT,
    dwObjID: u32,
    dwcValidPts: u32,
    rgptCalloutLine: [5]POINT,
    rcCalloutRect: RECT,
    dwTextAlign: u32,
};

pub const LPDIENUMDEVICESBYSEMANTICSCBW = *const fn (
    param0: ?*DIDEVICEINSTANCEW,
    param1: ?*IDirectInputDevice8W,
    param2: u32,
    param3: u32,
    param4: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const DIFILEEFFECT = extern struct {
    dwSize: u32,
    GuidEffect: Guid,
    lpDiEffect: ?*DIEFFECT,
    szFriendlyName: [260]CHAR,
};

pub const DIEFFECT = extern struct {
    dwSize: u32,
    dwFlags: u32,
    dwDuration: u32,
    dwSamplePeriod: u32,
    dwGain: u32,
    dwTriggerButton: u32,
    dwTriggerRepeatInterval: u32,
    cAxes: u32,
    rgdwAxes: ?*u32,
    rglDirection: ?*i32,
    lpEnvelope: ?*DIENVELOPE,
    cbTypeSpecificParams: u32,
    lpvTypeSpecificParams: ?*anyopaque,
    dwStartDelay: u32,
};

pub const DIEFFESCAPE = extern struct {
    dwSize: u32,
    dwCommand: u32,
    lpvInBuffer: ?*anyopaque,
    cbInBuffer: u32,
    lpvOutBuffer: ?*anyopaque,
    cbOutBuffer: u32,
};

pub const DIENVELOPE = extern struct {
    dwSize: u32,
    dwAttackLevel: u32,
    dwAttackTime: u32,
    dwFadeLevel: u32,
    dwFadeTime: u32,
};

pub const LPDIENUMEFFECTSCALLBACKW = *const fn (
    param0: ?*DIEFFECTINFOW,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const DIEFFECTINFOW = extern struct {
    dwSize: u32,
    guid: Guid,
    dwEffType: u32,
    dwStaticParams: u32,
    dwDynamicParams: u32,
    tszName: [260]u16,
};

pub const LPDIENUMEFFECTSINFILECALLBACK = *const fn (
    param0: ?*DIFILEEFFECT,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const DIDEVICEOBJECTDATA = extern struct {
    dwOfs: u32,
    dwData: u32,
    dwTimeStamp: u32,
    dwSequence: u32,
    uAppData: usize,
};

pub const LPDIENUMCREATEDEFFECTOBJECTSCALLBACK = *const fn (
    param0: ?*IDirectInputEffect,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

const IID_IDirectInputEffect_Value = Guid.initString("e7e1f7c0-88d2-11d0-9ad0-00a0c9a06e35");
pub const IID_IDirectInputEffect = &IID_IDirectInputEffect_Value;
pub const IDirectInputEffect = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Initialize: *const fn (
            self: *const IDirectInputEffect,
            param0: ?HINSTANCE,
            param1: u32,
            param2: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        GetEffectGuid: *const fn (
            self: *const IDirectInputEffect,
            param0: ?*Guid,
        ) callconv(.winapi) HRESULT,
        GetParameters: *const fn (
            self: *const IDirectInputEffect,
            param0: ?*DIEFFECT,
            param1: u32,
        ) callconv(.winapi) HRESULT,
        SetParameters: *const fn (
            self: *const IDirectInputEffect,
            param0: ?*DIEFFECT,
            param1: u32,
        ) callconv(.winapi) HRESULT,
        Start: *const fn (
            self: *const IDirectInputEffect,
            param0: u32,
            param1: u32,
        ) callconv(.winapi) HRESULT,
        Stop: *const fn (
            self: *const IDirectInputEffect,
        ) callconv(.winapi) HRESULT,
        GetEffectStatus: *const fn (
            self: *const IDirectInputEffect,
            param0: ?*u32,
        ) callconv(.winapi) HRESULT,
        Download: *const fn (
            self: *const IDirectInputEffect,
        ) callconv(.winapi) HRESULT,
        Unload: *const fn (
            self: *const IDirectInputEffect,
        ) callconv(.winapi) HRESULT,
        Escape: *const fn (
            self: *const IDirectInputEffect,
            param0: ?*DIEFFESCAPE,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn Initialize(self: *const IDirectInputEffect, param0: ?HINSTANCE, param1: u32, param2: ?*const Guid) HRESULT {
        return self.vtable.Initialize(self, param0, param1, param2);
    }
    pub inline fn GetEffectGuid(self: *const IDirectInputEffect, param0: ?*Guid) HRESULT {
        return self.vtable.GetEffectGuid(self, param0);
    }
    pub inline fn GetParameters(self: *const IDirectInputEffect, param0: ?*DIEFFECT, param1: u32) HRESULT {
        return self.vtable.GetParameters(self, param0, param1);
    }
    pub inline fn SetParameters(self: *const IDirectInputEffect, param0: ?*DIEFFECT, param1: u32) HRESULT {
        return self.vtable.SetParameters(self, param0, param1);
    }
    pub inline fn Start(self: *const IDirectInputEffect, param0: u32, param1: u32) HRESULT {
        return self.vtable.Start(self, param0, param1);
    }
    pub inline fn Stop(self: *const IDirectInputEffect) HRESULT {
        return self.vtable.Stop(self);
    }
    pub inline fn GetEffectStatus(self: *const IDirectInputEffect, param0: ?*u32) HRESULT {
        return self.vtable.GetEffectStatus(self, param0);
    }
    pub inline fn Download(self: *const IDirectInputEffect) HRESULT {
        return self.vtable.Download(self);
    }
    pub inline fn Unload(self: *const IDirectInputEffect) HRESULT {
        return self.vtable.Unload(self);
    }
    pub inline fn Escape(self: *const IDirectInputEffect, param0: ?*DIEFFESCAPE) HRESULT {
        return self.vtable.Escape(self, param0);
    }
};

pub const DIDATAFORMAT = extern struct {
    dwSize: u32,
    dwObjSize: u32,
    dwFlags: u32,
    dwDataSize: u32,
    dwNumObjs: u32,
    rgodf: ?*DIOBJECTDATAFORMAT,
};

pub const DIOBJECTDATAFORMAT = extern struct {
    pguid: ?*const Guid,
    dwOfs: u32,
    dwType: u32,
    dwFlags: u32,
};

pub const DIPROPHEADER = extern struct {
    dwSize: u32,
    dwHeaderSize: u32,
    dwObj: u32,
    dwHow: u32,
};

pub const DIDEVCAPS = extern struct {
    dwSize: u32,
    dwFlags: u32,
    dwDevType: u32,
    dwAxes: u32,
    dwButtons: u32,
    dwPOVs: u32,
    dwFFSamplePeriod: u32,
    dwFFMinTimeResolution: u32,
    dwFirmwareRevision: u32,
    dwHardwareRevision: u32,
    dwFFDriverVersion: u32,
};

pub const DICONFIGUREDEVICESPARAMSW = extern struct {
    dwSize: u32,
    dwcUsers: u32,
    lptszUserNames: ?PWSTR,
    dwcFormats: u32,
    lprgFormats: ?*DIACTIONFORMATW,
    hwnd: ?HWND,
    dics: DICOLORSET,
    lpUnkDDSTarget: ?*IUnknown,
};

pub const DIDEVICEOBJECTINSTANCEW = extern struct {
    dwSize: u32,
    guidType: Guid,
    dwOfs: u32,
    dwType: u32,
    dwFlags: u32,
    tszName: [260]u16,
    dwFFMaxForce: u32,
    dwFFForceResolution: u32,
    wCollectionNumber: u16,
    wDesignatorIndex: u16,
    wUsagePage: u16,
    wUsage: u16,
    dwDimension: u32,
    wExponent: u16,
    wReportId: u16,
};

pub const DICOLORSET = extern struct {
    dwSize: u32,
    cTextFore: u32,
    cTextHighlight: u32,
    cCalloutLine: u32,
    cCalloutHighlight: u32,
    cBorder: u32,
    cControlFill: u32,
    cHighlightFill: u32,
    cAreaFill: u32,
};

pub const LPDIENUMDEVICEOBJECTSCALLBACKW = *const fn (
    param0: ?*DIDEVICEOBJECTINSTANCEW,
    param1: ?*anyopaque,
) callconv(.winapi) BOOL;

pub const IDI_APPLICATION = typedConst([*:0]align(1) const u16, @as(i32, 32512));
pub extern "user32" fn LoadIconW(
    hInstance: ?HINSTANCE,
    lpIconName: ?[*:0]align(1) const u16,
) callconv(.winapi) ?HICON;

pub const IDC_ARROW = typedConst([*:0]align(1) const u16, @as(i32, 32512));
pub const IDC_HAND = typedConst([*:0]align(1) const u16, @as(i32, 32649));
pub const IDC_HELP = typedConst([*:0]align(1) const u16, @as(i32, 32651));
pub const IDC_IBEAM = typedConst([*:0]align(1) const u16, @as(i32, 32513));
pub const IDC_ICON = typedConst([*:0]align(1) const u16, @as(i32, 32641));
pub const IDC_CROSS = typedConst([*:0]align(1) const u16, @as(i32, 32515));
pub const IDC_SIZE = typedConst([*:0]align(1) const u16, @as(i32, 32640));
pub const IDC_SIZEALL = typedConst([*:0]align(1) const u16, @as(i32, 32646));
pub const IDC_SIZENESW = typedConst([*:0]align(1) const u16, @as(i32, 32643));
pub const IDC_SIZENS = typedConst([*:0]align(1) const u16, @as(i32, 32645));
pub const IDC_SIZENWSE = typedConst([*:0]align(1) const u16, @as(i32, 32642));
pub const IDC_SIZEWE = typedConst([*:0]align(1) const u16, @as(i32, 32644));
pub const IDC_NO = typedConst([*:0]align(1) const u16, @as(i32, 32648));

pub extern "user32" fn LoadCursorW(
    hInstance: ?HINSTANCE,
    lpCursorName: ?[*:0]align(1) const u16,
) callconv(.winapi) ?HCURSOR;

pub const WNDCLASSW = extern struct {
    style: WNDCLASS_STYLES,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: ?[*:0]const u16,
};

//--------------------------------------------------------------------------------
// Section: Types (154)
//--------------------------------------------------------------------------------
pub const WNDCLASS_STYLES = packed struct(u32) {
    VREDRAW: u1 = 0,
    HREDRAW: u1 = 0,
    _2: u1 = 0,
    DBLCLKS: u1 = 0,
    _4: u1 = 0,
    OWNDC: u1 = 0,
    CLASSDC: u1 = 0,
    PARENTDC: u1 = 0,
    _8: u1 = 0,
    NOCLOSE: u1 = 0,
    _10: u1 = 0,
    SAVEBITS: u1 = 0,
    BYTEALIGNCLIENT: u1 = 0,
    BYTEALIGNWINDOW: u1 = 0,
    GLOBALCLASS: u1 = 0,
    _15: u1 = 0,
    IME: u1 = 0,
    DROPSHADOW: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const CS_VREDRAW = WNDCLASS_STYLES{ .VREDRAW = 1 };
pub const CS_HREDRAW = WNDCLASS_STYLES{ .HREDRAW = 1 };
pub const CS_DBLCLKS = WNDCLASS_STYLES{ .DBLCLKS = 1 };
pub const CS_OWNDC = WNDCLASS_STYLES{ .OWNDC = 1 };
pub const CS_CLASSDC = WNDCLASS_STYLES{ .CLASSDC = 1 };
pub const CS_PARENTDC = WNDCLASS_STYLES{ .PARENTDC = 1 };
pub const CS_NOCLOSE = WNDCLASS_STYLES{ .NOCLOSE = 1 };
pub const CS_SAVEBITS = WNDCLASS_STYLES{ .SAVEBITS = 1 };
pub const CS_BYTEALIGNCLIENT = WNDCLASS_STYLES{ .BYTEALIGNCLIENT = 1 };
pub const CS_BYTEALIGNWINDOW = WNDCLASS_STYLES{ .BYTEALIGNWINDOW = 1 };
pub const CS_GLOBALCLASS = WNDCLASS_STYLES{ .GLOBALCLASS = 1 };
pub const CS_IME = WNDCLASS_STYLES{ .IME = 1 };
pub const CS_DROPSHADOW = WNDCLASS_STYLES{ .DROPSHADOW = 1 };

pub const WNDPROC = *const fn (
    param0: HWND,
    param1: u32,
    param2: WPARAM,
    param3: LPARAM,
) callconv(.winapi) LRESULT;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn RegisterClassW(
    lpWndClass: ?*const WNDCLASSW,
) callconv(.winapi) u16;

pub const WINDOW_EX_STYLE = packed struct(u32) {
    DLGMODALFRAME: u1 = 0,
    _1: u1 = 0,
    NOPARENTNOTIFY: u1 = 0,
    TOPMOST: u1 = 0,
    ACCEPTFILES: u1 = 0,
    TRANSPARENT: u1 = 0,
    MDICHILD: u1 = 0,
    TOOLWINDOW: u1 = 0,
    WINDOWEDGE: u1 = 0,
    CLIENTEDGE: u1 = 0,
    CONTEXTHELP: u1 = 0,
    _11: u1 = 0,
    RIGHT: u1 = 0,
    RTLREADING: u1 = 0,
    LEFTSCROLLBAR: u1 = 0,
    _15: u1 = 0,
    CONTROLPARENT: u1 = 0,
    STATICEDGE: u1 = 0,
    APPWINDOW: u1 = 0,
    LAYERED: u1 = 0,
    NOINHERITLAYOUT: u1 = 0,
    NOREDIRECTIONBITMAP: u1 = 0,
    LAYOUTRTL: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    COMPOSITED: u1 = 0,
    _26: u1 = 0,
    NOACTIVATE: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const WS_EX_DLGMODALFRAME = WINDOW_EX_STYLE{ .DLGMODALFRAME = 1 };
pub const WS_EX_NOPARENTNOTIFY = WINDOW_EX_STYLE{ .NOPARENTNOTIFY = 1 };
pub const WS_EX_TOPMOST = WINDOW_EX_STYLE{ .TOPMOST = 1 };
pub const WS_EX_ACCEPTFILES = WINDOW_EX_STYLE{ .ACCEPTFILES = 1 };
pub const WS_EX_TRANSPARENT = WINDOW_EX_STYLE{ .TRANSPARENT = 1 };
pub const WS_EX_MDICHILD = WINDOW_EX_STYLE{ .MDICHILD = 1 };
pub const WS_EX_TOOLWINDOW = WINDOW_EX_STYLE{ .TOOLWINDOW = 1 };
pub const WS_EX_WINDOWEDGE = WINDOW_EX_STYLE{ .WINDOWEDGE = 1 };
pub const WS_EX_CLIENTEDGE = WINDOW_EX_STYLE{ .CLIENTEDGE = 1 };
pub const WS_EX_CONTEXTHELP = WINDOW_EX_STYLE{ .CONTEXTHELP = 1 };
pub const WS_EX_RIGHT = WINDOW_EX_STYLE{ .RIGHT = 1 };
pub const WS_EX_LEFT = WINDOW_EX_STYLE{};
pub const WS_EX_RTLREADING = WINDOW_EX_STYLE{ .RTLREADING = 1 };
pub const WS_EX_LTRREADING = WINDOW_EX_STYLE{};
pub const WS_EX_LEFTSCROLLBAR = WINDOW_EX_STYLE{ .LEFTSCROLLBAR = 1 };
pub const WS_EX_RIGHTSCROLLBAR = WINDOW_EX_STYLE{};
pub const WS_EX_CONTROLPARENT = WINDOW_EX_STYLE{ .CONTROLPARENT = 1 };
pub const WS_EX_STATICEDGE = WINDOW_EX_STYLE{ .STATICEDGE = 1 };
pub const WS_EX_APPWINDOW = WINDOW_EX_STYLE{ .APPWINDOW = 1 };
pub const WS_EX_OVERLAPPEDWINDOW = WINDOW_EX_STYLE{
    .WINDOWEDGE = 1,
    .CLIENTEDGE = 1,
};
pub const WS_EX_PALETTEWINDOW = WINDOW_EX_STYLE{
    .TOPMOST = 1,
    .TOOLWINDOW = 1,
    .WINDOWEDGE = 1,
};
pub const WS_EX_LAYERED = WINDOW_EX_STYLE{ .LAYERED = 1 };
pub const WS_EX_NOINHERITLAYOUT = WINDOW_EX_STYLE{ .NOINHERITLAYOUT = 1 };
pub const WS_EX_NOREDIRECTIONBITMAP = WINDOW_EX_STYLE{ .NOREDIRECTIONBITMAP = 1 };
pub const WS_EX_LAYOUTRTL = WINDOW_EX_STYLE{ .LAYOUTRTL = 1 };
pub const WS_EX_COMPOSITED = WINDOW_EX_STYLE{ .COMPOSITED = 1 };
pub const WS_EX_NOACTIVATE = WINDOW_EX_STYLE{ .NOACTIVATE = 1 };

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn CreateWindowExW(
    dwExStyle: WINDOW_EX_STYLE,
    lpClassName: ?[*:0]align(1) const u16,
    lpWindowName: ?[*:0]const u16,
    dwStyle: WINDOW_STYLE,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;

pub extern "user32" fn ShowCursor(
    bShow: BOOL,
) callconv(.winapi) i32;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn ShowWindow(
    hWnd: ?HWND,
    nCmdShow: SHOW_WINDOW_CMD,
) callconv(.winapi) BOOL;

pub const WINDOW_STYLE = packed struct(u32) {
    ACTIVECAPTION: u1 = 0,
    _1: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    TABSTOP: u1 = 0,
    GROUP: u1 = 0,
    THICKFRAME: u1 = 0,
    SYSMENU: u1 = 0,
    HSCROLL: u1 = 0,
    VSCROLL: u1 = 0,
    DLGFRAME: u1 = 0,
    BORDER: u1 = 0,
    MAXIMIZE: u1 = 0,
    CLIPCHILDREN: u1 = 0,
    CLIPSIBLINGS: u1 = 0,
    DISABLED: u1 = 0,
    VISIBLE: u1 = 0,
    MINIMIZE: u1 = 0,
    CHILD: u1 = 0,
    POPUP: u1 = 0,
    // MINIMIZEBOX (bit index 17) conflicts with GROUP
    // MAXIMIZEBOX (bit index 16) conflicts with TABSTOP
    // ICONIC (bit index 29) conflicts with MINIMIZE
    // SIZEBOX (bit index 18) conflicts with THICKFRAME
    // CHILDWINDOW (bit index 30) conflicts with CHILD
};
pub const WS_OVERLAPPED = WINDOW_STYLE{};
pub const WS_POPUP = WINDOW_STYLE{ .POPUP = 1 };
pub const WS_CHILD = WINDOW_STYLE{ .CHILD = 1 };
pub const WS_MINIMIZE = WINDOW_STYLE{ .MINIMIZE = 1 };
pub const WS_VISIBLE = WINDOW_STYLE{ .VISIBLE = 1 };
pub const WS_DISABLED = WINDOW_STYLE{ .DISABLED = 1 };
pub const WS_CLIPSIBLINGS = WINDOW_STYLE{ .CLIPSIBLINGS = 1 };
pub const WS_CLIPCHILDREN = WINDOW_STYLE{ .CLIPCHILDREN = 1 };
pub const WS_MAXIMIZE = WINDOW_STYLE{ .MAXIMIZE = 1 };
pub const WS_CAPTION = WINDOW_STYLE{
    .DLGFRAME = 1,
    .BORDER = 1,
};
pub const WS_BORDER = WINDOW_STYLE{ .BORDER = 1 };
pub const WS_DLGFRAME = WINDOW_STYLE{ .DLGFRAME = 1 };
pub const WS_VSCROLL = WINDOW_STYLE{ .VSCROLL = 1 };
pub const WS_HSCROLL = WINDOW_STYLE{ .HSCROLL = 1 };
pub const WS_SYSMENU = WINDOW_STYLE{ .SYSMENU = 1 };
pub const WS_THICKFRAME = WINDOW_STYLE{ .THICKFRAME = 1 };
pub const WS_GROUP = WINDOW_STYLE{ .GROUP = 1 };
pub const WS_TABSTOP = WINDOW_STYLE{ .TABSTOP = 1 };
pub const WS_MINIMIZEBOX = WINDOW_STYLE{ .GROUP = 1 };
pub const WS_MAXIMIZEBOX = WINDOW_STYLE{ .TABSTOP = 1 };
pub const WS_TILED = WINDOW_STYLE{};
pub const WS_ICONIC = WINDOW_STYLE{ .MINIMIZE = 1 };
pub const WS_SIZEBOX = WINDOW_STYLE{ .THICKFRAME = 1 };
pub const WS_TILEDWINDOW = WINDOW_STYLE{
    .TABSTOP = 1,
    .GROUP = 1,
    .THICKFRAME = 1,
    .SYSMENU = 1,
    .DLGFRAME = 1,
    .BORDER = 1,
};
pub const WS_OVERLAPPEDWINDOW = WINDOW_STYLE{
    .TABSTOP = 1,
    .GROUP = 1,
    .THICKFRAME = 1,
    .SYSMENU = 1,
    .DLGFRAME = 1,
    .BORDER = 1,
};
pub const WS_POPUPWINDOW = WINDOW_STYLE{
    .SYSMENU = 1,
    .BORDER = 1,
    .POPUP = 1,
};
pub const WS_CHILDWINDOW = WINDOW_STYLE{ .CHILD = 1 };
pub const WS_ACTIVECAPTION = WINDOW_STYLE{ .ACTIVECAPTION = 1 };

pub const SHOW_WINDOW_CMD = packed struct(u32) {
    SHOWNORMAL: u1 = 0,
    SHOWMINIMIZED: u1 = 0,
    SHOWNOACTIVATE: u1 = 0,
    SHOWNA: u1 = 0,
    SMOOTHSCROLL: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
    // NORMAL (bit index 0) conflicts with SHOWNORMAL
    // PARENTCLOSING (bit index 0) conflicts with SHOWNORMAL
    // OTHERZOOM (bit index 1) conflicts with SHOWMINIMIZED
    // OTHERUNZOOM (bit index 2) conflicts with SHOWNOACTIVATE
    // SCROLLCHILDREN (bit index 0) conflicts with SHOWNORMAL
    // INVALIDATE (bit index 1) conflicts with SHOWMINIMIZED
    // ERASE (bit index 2) conflicts with SHOWNOACTIVATE
};
pub const SW_FORCEMINIMIZE = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
    .SHOWNA = 1,
};
pub const SW_HIDE = SHOW_WINDOW_CMD{};
pub const SW_MAXIMIZE = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
};
pub const SW_MINIMIZE = SHOW_WINDOW_CMD{
    .SHOWMINIMIZED = 1,
    .SHOWNOACTIVATE = 1,
};
pub const SW_RESTORE = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWNA = 1,
};
pub const SW_SHOW = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWNOACTIVATE = 1,
};
pub const SW_SHOWDEFAULT = SHOW_WINDOW_CMD{
    .SHOWMINIMIZED = 1,
    .SHOWNA = 1,
};
pub const SW_SHOWMAXIMIZED = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
};
pub const SW_SHOWMINIMIZED = SHOW_WINDOW_CMD{ .SHOWMINIMIZED = 1 };
pub const SW_SHOWMINNOACTIVE = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
    .SHOWNOACTIVATE = 1,
};
pub const SW_SHOWNA = SHOW_WINDOW_CMD{ .SHOWNA = 1 };
pub const SW_SHOWNOACTIVATE = SHOW_WINDOW_CMD{ .SHOWNOACTIVATE = 1 };
pub const SW_SHOWNORMAL = SHOW_WINDOW_CMD{ .SHOWNORMAL = 1 };
pub const SW_NORMAL = SHOW_WINDOW_CMD{ .SHOWNORMAL = 1 };
pub const SW_MAX = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
    .SHOWNA = 1,
};
pub const SW_PARENTCLOSING = SHOW_WINDOW_CMD{ .SHOWNORMAL = 1 };
pub const SW_OTHERZOOM = SHOW_WINDOW_CMD{ .SHOWMINIMIZED = 1 };
pub const SW_PARENTOPENING = SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWMINIMIZED = 1,
};
pub const SW_OTHERUNZOOM = SHOW_WINDOW_CMD{ .SHOWNOACTIVATE = 1 };
pub const SW_SCROLLCHILDREN = SHOW_WINDOW_CMD{ .SHOWNORMAL = 1 };
pub const SW_INVALIDATE = SHOW_WINDOW_CMD{ .SHOWMINIMIZED = 1 };
pub const SW_ERASE = SHOW_WINDOW_CMD{ .SHOWNOACTIVATE = 1 };
pub const SW_SMOOTHSCROLL = SHOW_WINDOW_CMD{ .SMOOTHSCROLL = 1 };

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn DefWindowProcW(
    hWnd: ?HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.winapi) LRESULT;

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

pub const WM_NULL = @as(u32, 0);
pub const WM_CREATE = @as(u32, 1);
pub const WM_DESTROY = @as(u32, 2);
pub const WM_MOVE = @as(u32, 3);
pub const WM_SIZE = @as(u32, 5);
pub const WM_ACTIVATE = @as(u32, 6);
pub const WA_INACTIVE = @as(u32, 0);
pub const WA_ACTIVE = @as(u32, 1);
pub const WA_CLICKACTIVE = @as(u32, 2);
pub const WM_SETFOCUS = @as(u32, 7);
pub const WM_KILLFOCUS = @as(u32, 8);
pub const WM_ENABLE = @as(u32, 10);
pub const WM_SETREDRAW = @as(u32, 11);
pub const WM_SETTEXT = @as(u32, 12);
pub const WM_GETTEXT = @as(u32, 13);
pub const WM_GETTEXTLENGTH = @as(u32, 14);
pub const WM_PAINT = @as(u32, 15);
pub const WM_CLOSE = @as(u32, 16);
pub const WM_QUERYENDSESSION = @as(u32, 17);
pub const WM_QUERYOPEN = @as(u32, 19);
pub const WM_ENDSESSION = @as(u32, 22);
pub const WM_QUIT = @as(u32, 18);
pub const WM_GETMINMAXINFO = @as(u32, 36);
pub const WM_WINDOWPOSCHANGED = @as(u32, 71);
pub const WM_KEYFIRST = @as(u32, 256);
pub const WM_KEYDOWN = @as(u32, 256);
pub const WM_KEYUP = @as(u32, 257);
pub const WM_CHAR = @as(u32, 258);
pub const WM_DEADCHAR = @as(u32, 259);
pub const WM_SYSKEYDOWN = @as(u32, 260);
pub const WM_SYSKEYUP = @as(u32, 261);
pub const WM_SYSCHAR = @as(u32, 262);
pub const WM_SYSDEADCHAR = @as(u32, 263);
pub const WM_KEYLAST = @as(u32, 265);
pub const UNICODE_NOCHAR = @as(u32, 65535);
pub const WM_IME_STARTCOMPOSITION = @as(u32, 269);
pub const WM_IME_ENDCOMPOSITION = @as(u32, 270);
pub const WM_IME_COMPOSITION = @as(u32, 271);
pub const WM_IME_KEYLAST = @as(u32, 271);
pub const WM_INITDIALOG = @as(u32, 272);
pub const WM_COMMAND = @as(u32, 273);
pub const WM_SYSCOMMAND = @as(u32, 274);
pub const WM_TIMER = @as(u32, 275);
pub const WM_HSCROLL = @as(u32, 276);
pub const WM_VSCROLL = @as(u32, 277);
pub const WM_INITMENU = @as(u32, 278);
pub const WM_INITMENUPOPUP = @as(u32, 279);
pub const WM_GESTURE = @as(u32, 281);
pub const WM_GESTURENOTIFY = @as(u32, 282);
pub const WM_MENUSELECT = @as(u32, 287);
pub const WM_MENUCHAR = @as(u32, 288);
pub const WM_ENTERIDLE = @as(u32, 289);
pub const WM_MENURBUTTONUP = @as(u32, 290);
pub const WM_MENUDRAG = @as(u32, 291);
pub const WM_MENUGETOBJECT = @as(u32, 292);
pub const WM_UNINITMENUPOPUP = @as(u32, 293);
pub const WM_MENUCOMMAND = @as(u32, 294);
pub const WM_CHANGEUISTATE = @as(u32, 295);
pub const WM_UPDATEUISTATE = @as(u32, 296);
pub const WM_QUERYUISTATE = @as(u32, 297);
pub const UIS_SET = @as(u32, 1);
pub const UIS_CLEAR = @as(u32, 2);
pub const UIS_INITIALIZE = @as(u32, 3);
pub const UISF_HIDEFOCUS = @as(u32, 1);
pub const UISF_HIDEACCEL = @as(u32, 2);
pub const UISF_ACTIVE = @as(u32, 4);
pub const WM_CTLCOLORMSGBOX = @as(u32, 306);
pub const WM_CTLCOLOREDIT = @as(u32, 307);
pub const WM_CTLCOLORLISTBOX = @as(u32, 308);
pub const WM_CTLCOLORBTN = @as(u32, 309);
pub const WM_CTLCOLORDLG = @as(u32, 310);
pub const WM_CTLCOLORSCROLLBAR = @as(u32, 311);
pub const WM_CTLCOLORSTATIC = @as(u32, 312);
pub const MN_GETHMENU = @as(u32, 481);
pub const WM_MOUSEFIRST = @as(u32, 512);
pub const WM_MOUSEMOVE = @as(u32, 512);
pub const WM_LBUTTONDOWN = @as(u32, 513);
pub const WM_LBUTTONUP = @as(u32, 514);
pub const WM_LBUTTONDBLCLK = @as(u32, 515);
pub const WM_RBUTTONDOWN = @as(u32, 516);
pub const WM_RBUTTONUP = @as(u32, 517);
pub const WM_RBUTTONDBLCLK = @as(u32, 518);
pub const WM_MBUTTONDOWN = @as(u32, 519);
pub const WM_MBUTTONUP = @as(u32, 520);
pub const WM_MBUTTONDBLCLK = @as(u32, 521);
pub const WM_MOUSEWHEEL = @as(u32, 522);
pub const WM_XBUTTONDOWN = @as(u32, 523);
pub const WM_XBUTTONUP = @as(u32, 524);
pub const WM_XBUTTONDBLCLK = @as(u32, 525);
pub const WM_MOUSEHWHEEL = @as(u32, 526);
pub const WM_MOUSELAST = @as(u32, 526);
pub const WHEEL_DELTA = @as(u32, 120);
pub const WM_PARENTNOTIFY = @as(u32, 528);
pub const WM_ENTERMENULOOP = @as(u32, 529);
pub const WM_EXITMENULOOP = @as(u32, 530);
pub const WM_NEXTMENU = @as(u32, 531);
pub const WM_SIZING = @as(u32, 532);
pub const WM_CAPTURECHANGED = @as(u32, 533);
pub const WM_MOVING = @as(u32, 534);
pub const WM_POWERBROADCAST = @as(u32, 536);
pub const WM_DPICHANGED = @as(u32, 736);

pub const KEYBD_EVENT_FLAGS = packed struct(u32) {
    EXTENDEDKEY: u1 = 0,
    KEYUP: u1 = 0,
    UNICODE: u1 = 0,
    SCANCODE: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const KEYEVENTF_EXTENDEDKEY = KEYBD_EVENT_FLAGS{ .EXTENDEDKEY = 1 };
pub const KEYEVENTF_KEYUP = KEYBD_EVENT_FLAGS{ .KEYUP = 1 };
pub const KEYEVENTF_SCANCODE = KEYBD_EVENT_FLAGS{ .SCANCODE = 1 };
pub const KEYEVENTF_UNICODE = KEYBD_EVENT_FLAGS{ .UNICODE = 1 };

pub const MOUSE_EVENT_FLAGS = packed struct(u32) {
    MOVE: u1 = 0,
    LEFTDOWN: u1 = 0,
    LEFTUP: u1 = 0,
    RIGHTDOWN: u1 = 0,
    RIGHTUP: u1 = 0,
    MIDDLEDOWN: u1 = 0,
    MIDDLEUP: u1 = 0,
    XDOWN: u1 = 0,
    XUP: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    WHEEL: u1 = 0,
    HWHEEL: u1 = 0,
    MOVE_NOCOALESCE: u1 = 0,
    VIRTUALDESK: u1 = 0,
    ABSOLUTE: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const MOUSEEVENTF_ABSOLUTE = MOUSE_EVENT_FLAGS{ .ABSOLUTE = 1 };
pub const MOUSEEVENTF_LEFTDOWN = MOUSE_EVENT_FLAGS{ .LEFTDOWN = 1 };
pub const MOUSEEVENTF_LEFTUP = MOUSE_EVENT_FLAGS{ .LEFTUP = 1 };
pub const MOUSEEVENTF_MIDDLEDOWN = MOUSE_EVENT_FLAGS{ .MIDDLEDOWN = 1 };
pub const MOUSEEVENTF_MIDDLEUP = MOUSE_EVENT_FLAGS{ .MIDDLEUP = 1 };
pub const MOUSEEVENTF_MOVE = MOUSE_EVENT_FLAGS{ .MOVE = 1 };
pub const MOUSEEVENTF_RIGHTDOWN = MOUSE_EVENT_FLAGS{ .RIGHTDOWN = 1 };
pub const MOUSEEVENTF_RIGHTUP = MOUSE_EVENT_FLAGS{ .RIGHTUP = 1 };
pub const MOUSEEVENTF_WHEEL = MOUSE_EVENT_FLAGS{ .WHEEL = 1 };
pub const MOUSEEVENTF_XDOWN = MOUSE_EVENT_FLAGS{ .XDOWN = 1 };
pub const MOUSEEVENTF_XUP = MOUSE_EVENT_FLAGS{ .XUP = 1 };
pub const MOUSEEVENTF_HWHEEL = MOUSE_EVENT_FLAGS{ .HWHEEL = 1 };
pub const MOUSEEVENTF_MOVE_NOCOALESCE = MOUSE_EVENT_FLAGS{ .MOVE_NOCOALESCE = 1 };
pub const MOUSEEVENTF_VIRTUALDESK = MOUSE_EVENT_FLAGS{ .VIRTUALDESK = 1 };

pub const INPUT_TYPE = enum(u32) {
    MOUSE = 0,
    KEYBOARD = 1,
    HARDWARE = 2,
};
pub const INPUT_MOUSE = INPUT_TYPE.MOUSE;
pub const INPUT_KEYBOARD = INPUT_TYPE.KEYBOARD;
pub const INPUT_HARDWARE = INPUT_TYPE.HARDWARE;

pub const TRACKMOUSEEVENT_FLAGS = packed struct(u32) {
    HOVER: u1 = 0,
    LEAVE: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    NONCLIENT: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    QUERY: u1 = 0,
    CANCEL: u1 = 0,
};
pub const TME_CANCEL = TRACKMOUSEEVENT_FLAGS{ .CANCEL = 1 };
pub const TME_HOVER = TRACKMOUSEEVENT_FLAGS{ .HOVER = 1 };
pub const TME_LEAVE = TRACKMOUSEEVENT_FLAGS{ .LEAVE = 1 };
pub const TME_NONCLIENT = TRACKMOUSEEVENT_FLAGS{ .NONCLIENT = 1 };
pub const TME_QUERY = TRACKMOUSEEVENT_FLAGS{ .QUERY = 1 };

pub const VIRTUAL_KEY = enum(u16) {
    @"0" = 48,
    @"1" = 49,
    @"2" = 50,
    @"3" = 51,
    @"4" = 52,
    @"5" = 53,
    @"6" = 54,
    @"7" = 55,
    @"8" = 56,
    @"9" = 57,
    A = 65,
    B = 66,
    C = 67,
    D = 68,
    E = 69,
    F = 70,
    G = 71,
    H = 72,
    I = 73,
    J = 74,
    K = 75,
    L = 76,
    M = 77,
    N = 78,
    O = 79,
    P = 80,
    Q = 81,
    R = 82,
    S = 83,
    T = 84,
    U = 85,
    V = 86,
    W = 87,
    X = 88,
    Y = 89,
    Z = 90,
    LBUTTON = 1,
    RBUTTON = 2,
    CANCEL = 3,
    MBUTTON = 4,
    XBUTTON1 = 5,
    XBUTTON2 = 6,
    BACK = 8,
    TAB = 9,
    CLEAR = 12,
    RETURN = 13,
    SHIFT = 16,
    CONTROL = 17,
    MENU = 18,
    PAUSE = 19,
    CAPITAL = 20,
    KANA = 21,
    // HANGEUL = 21, this enum value conflicts with KANA
    // HANGUL = 21, this enum value conflicts with KANA
    IME_ON = 22,
    JUNJA = 23,
    FINAL = 24,
    HANJA = 25,
    // KANJI = 25, this enum value conflicts with HANJA
    IME_OFF = 26,
    ESCAPE = 27,
    CONVERT = 28,
    NONCONVERT = 29,
    ACCEPT = 30,
    MODECHANGE = 31,
    SPACE = 32,
    PRIOR = 33,
    NEXT = 34,
    END = 35,
    HOME = 36,
    LEFT = 37,
    UP = 38,
    RIGHT = 39,
    DOWN = 40,
    SELECT = 41,
    PRINT = 42,
    EXECUTE = 43,
    SNAPSHOT = 44,
    INSERT = 45,
    DELETE = 46,
    HELP = 47,
    LWIN = 91,
    RWIN = 92,
    APPS = 93,
    SLEEP = 95,
    NUMPAD0 = 96,
    NUMPAD1 = 97,
    NUMPAD2 = 98,
    NUMPAD3 = 99,
    NUMPAD4 = 100,
    NUMPAD5 = 101,
    NUMPAD6 = 102,
    NUMPAD7 = 103,
    NUMPAD8 = 104,
    NUMPAD9 = 105,
    MULTIPLY = 106,
    ADD = 107,
    SEPARATOR = 108,
    SUBTRACT = 109,
    DECIMAL = 110,
    DIVIDE = 111,
    F1 = 112,
    F2 = 113,
    F3 = 114,
    F4 = 115,
    F5 = 116,
    F6 = 117,
    F7 = 118,
    F8 = 119,
    F9 = 120,
    F10 = 121,
    F11 = 122,
    F12 = 123,
    F13 = 124,
    F14 = 125,
    F15 = 126,
    F16 = 127,
    F17 = 128,
    F18 = 129,
    F19 = 130,
    F20 = 131,
    F21 = 132,
    F22 = 133,
    F23 = 134,
    F24 = 135,
    NAVIGATION_VIEW = 136,
    NAVIGATION_MENU = 137,
    NAVIGATION_UP = 138,
    NAVIGATION_DOWN = 139,
    NAVIGATION_LEFT = 140,
    NAVIGATION_RIGHT = 141,
    NAVIGATION_ACCEPT = 142,
    NAVIGATION_CANCEL = 143,
    NUMLOCK = 144,
    SCROLL = 145,
    OEM_NEC_EQUAL = 146,
    // OEM_FJ_JISHO = 146, this enum value conflicts with OEM_NEC_EQUAL
    OEM_FJ_MASSHOU = 147,
    OEM_FJ_TOUROKU = 148,
    OEM_FJ_LOYA = 149,
    OEM_FJ_ROYA = 150,
    LSHIFT = 160,
    RSHIFT = 161,
    LCONTROL = 162,
    RCONTROL = 163,
    LMENU = 164,
    RMENU = 165,
    BROWSER_BACK = 166,
    BROWSER_FORWARD = 167,
    BROWSER_REFRESH = 168,
    BROWSER_STOP = 169,
    BROWSER_SEARCH = 170,
    BROWSER_FAVORITES = 171,
    BROWSER_HOME = 172,
    VOLUME_MUTE = 173,
    VOLUME_DOWN = 174,
    VOLUME_UP = 175,
    MEDIA_NEXT_TRACK = 176,
    MEDIA_PREV_TRACK = 177,
    MEDIA_STOP = 178,
    MEDIA_PLAY_PAUSE = 179,
    LAUNCH_MAIL = 180,
    LAUNCH_MEDIA_SELECT = 181,
    LAUNCH_APP1 = 182,
    LAUNCH_APP2 = 183,
    OEM_1 = 186,
    OEM_PLUS = 187,
    OEM_COMMA = 188,
    OEM_MINUS = 189,
    OEM_PERIOD = 190,
    OEM_2 = 191,
    OEM_3 = 192,
    GAMEPAD_A = 195,
    GAMEPAD_B = 196,
    GAMEPAD_X = 197,
    GAMEPAD_Y = 198,
    GAMEPAD_RIGHT_SHOULDER = 199,
    GAMEPAD_LEFT_SHOULDER = 200,
    GAMEPAD_LEFT_TRIGGER = 201,
    GAMEPAD_RIGHT_TRIGGER = 202,
    GAMEPAD_DPAD_UP = 203,
    GAMEPAD_DPAD_DOWN = 204,
    GAMEPAD_DPAD_LEFT = 205,
    GAMEPAD_DPAD_RIGHT = 206,
    GAMEPAD_MENU = 207,
    GAMEPAD_VIEW = 208,
    GAMEPAD_LEFT_THUMBSTICK_BUTTON = 209,
    GAMEPAD_RIGHT_THUMBSTICK_BUTTON = 210,
    GAMEPAD_LEFT_THUMBSTICK_UP = 211,
    GAMEPAD_LEFT_THUMBSTICK_DOWN = 212,
    GAMEPAD_LEFT_THUMBSTICK_RIGHT = 213,
    GAMEPAD_LEFT_THUMBSTICK_LEFT = 214,
    GAMEPAD_RIGHT_THUMBSTICK_UP = 215,
    GAMEPAD_RIGHT_THUMBSTICK_DOWN = 216,
    GAMEPAD_RIGHT_THUMBSTICK_RIGHT = 217,
    GAMEPAD_RIGHT_THUMBSTICK_LEFT = 218,
    OEM_4 = 219,
    OEM_5 = 220,
    OEM_6 = 221,
    OEM_7 = 222,
    OEM_8 = 223,
    OEM_AX = 225,
    OEM_102 = 226,
    ICO_HELP = 227,
    ICO_00 = 228,
    PROCESSKEY = 229,
    ICO_CLEAR = 230,
    PACKET = 231,
    OEM_RESET = 233,
    OEM_JUMP = 234,
    OEM_PA1 = 235,
    OEM_PA2 = 236,
    OEM_PA3 = 237,
    OEM_WSCTRL = 238,
    OEM_CUSEL = 239,
    OEM_ATTN = 240,
    OEM_FINISH = 241,
    OEM_COPY = 242,
    OEM_AUTO = 243,
    OEM_ENLW = 244,
    OEM_BACKTAB = 245,
    ATTN = 246,
    CRSEL = 247,
    EXSEL = 248,
    EREOF = 249,
    PLAY = 250,
    ZOOM = 251,
    NONAME = 252,
    PA1 = 253,
    OEM_CLEAR = 254,
};
pub const VK_0 = VIRTUAL_KEY.@"0";
pub const VK_1 = VIRTUAL_KEY.@"1";
pub const VK_2 = VIRTUAL_KEY.@"2";
pub const VK_3 = VIRTUAL_KEY.@"3";
pub const VK_4 = VIRTUAL_KEY.@"4";
pub const VK_5 = VIRTUAL_KEY.@"5";
pub const VK_6 = VIRTUAL_KEY.@"6";
pub const VK_7 = VIRTUAL_KEY.@"7";
pub const VK_8 = VIRTUAL_KEY.@"8";
pub const VK_9 = VIRTUAL_KEY.@"9";
pub const VK_A = VIRTUAL_KEY.A;
pub const VK_B = VIRTUAL_KEY.B;
pub const VK_C = VIRTUAL_KEY.C;
pub const VK_D = VIRTUAL_KEY.D;
pub const VK_E = VIRTUAL_KEY.E;
pub const VK_F = VIRTUAL_KEY.F;
pub const VK_G = VIRTUAL_KEY.G;
pub const VK_H = VIRTUAL_KEY.H;
pub const VK_I = VIRTUAL_KEY.I;
pub const VK_J = VIRTUAL_KEY.J;
pub const VK_K = VIRTUAL_KEY.K;
pub const VK_L = VIRTUAL_KEY.L;
pub const VK_M = VIRTUAL_KEY.M;
pub const VK_N = VIRTUAL_KEY.N;
pub const VK_O = VIRTUAL_KEY.O;
pub const VK_P = VIRTUAL_KEY.P;
pub const VK_Q = VIRTUAL_KEY.Q;
pub const VK_R = VIRTUAL_KEY.R;
pub const VK_S = VIRTUAL_KEY.S;
pub const VK_T = VIRTUAL_KEY.T;
pub const VK_U = VIRTUAL_KEY.U;
pub const VK_V = VIRTUAL_KEY.V;
pub const VK_W = VIRTUAL_KEY.W;
pub const VK_X = VIRTUAL_KEY.X;
pub const VK_Y = VIRTUAL_KEY.Y;
pub const VK_Z = VIRTUAL_KEY.Z;
pub const VK_LBUTTON = VIRTUAL_KEY.LBUTTON;
pub const VK_RBUTTON = VIRTUAL_KEY.RBUTTON;
pub const VK_CANCEL = VIRTUAL_KEY.CANCEL;
pub const VK_MBUTTON = VIRTUAL_KEY.MBUTTON;
pub const VK_XBUTTON1 = VIRTUAL_KEY.XBUTTON1;
pub const VK_XBUTTON2 = VIRTUAL_KEY.XBUTTON2;
pub const VK_BACK = VIRTUAL_KEY.BACK;
pub const VK_TAB = VIRTUAL_KEY.TAB;
pub const VK_CLEAR = VIRTUAL_KEY.CLEAR;
pub const VK_RETURN = VIRTUAL_KEY.RETURN;
pub const VK_SHIFT = VIRTUAL_KEY.SHIFT;
pub const VK_CONTROL = VIRTUAL_KEY.CONTROL;
pub const VK_MENU = VIRTUAL_KEY.MENU;
pub const VK_PAUSE = VIRTUAL_KEY.PAUSE;
pub const VK_CAPITAL = VIRTUAL_KEY.CAPITAL;
pub const VK_KANA = VIRTUAL_KEY.KANA;
pub const VK_HANGEUL = VIRTUAL_KEY.KANA;
pub const VK_HANGUL = VIRTUAL_KEY.KANA;
pub const VK_IME_ON = VIRTUAL_KEY.IME_ON;
pub const VK_JUNJA = VIRTUAL_KEY.JUNJA;
pub const VK_FINAL = VIRTUAL_KEY.FINAL;
pub const VK_HANJA = VIRTUAL_KEY.HANJA;
pub const VK_KANJI = VIRTUAL_KEY.HANJA;
pub const VK_IME_OFF = VIRTUAL_KEY.IME_OFF;
pub const VK_ESCAPE = VIRTUAL_KEY.ESCAPE;
pub const VK_CONVERT = VIRTUAL_KEY.CONVERT;
pub const VK_NONCONVERT = VIRTUAL_KEY.NONCONVERT;
pub const VK_ACCEPT = VIRTUAL_KEY.ACCEPT;
pub const VK_MODECHANGE = VIRTUAL_KEY.MODECHANGE;
pub const VK_SPACE = VIRTUAL_KEY.SPACE;
pub const VK_PRIOR = VIRTUAL_KEY.PRIOR;
pub const VK_NEXT = VIRTUAL_KEY.NEXT;
pub const VK_END = VIRTUAL_KEY.END;
pub const VK_HOME = VIRTUAL_KEY.HOME;
pub const VK_LEFT = VIRTUAL_KEY.LEFT;
pub const VK_UP = VIRTUAL_KEY.UP;
pub const VK_RIGHT = VIRTUAL_KEY.RIGHT;
pub const VK_DOWN = VIRTUAL_KEY.DOWN;
pub const VK_SELECT = VIRTUAL_KEY.SELECT;
pub const VK_PRINT = VIRTUAL_KEY.PRINT;
pub const VK_EXECUTE = VIRTUAL_KEY.EXECUTE;
pub const VK_SNAPSHOT = VIRTUAL_KEY.SNAPSHOT;
pub const VK_INSERT = VIRTUAL_KEY.INSERT;
pub const VK_DELETE = VIRTUAL_KEY.DELETE;
pub const VK_HELP = VIRTUAL_KEY.HELP;
pub const VK_LWIN = VIRTUAL_KEY.LWIN;
pub const VK_RWIN = VIRTUAL_KEY.RWIN;
pub const VK_APPS = VIRTUAL_KEY.APPS;
pub const VK_SLEEP = VIRTUAL_KEY.SLEEP;
pub const VK_NUMPAD0 = VIRTUAL_KEY.NUMPAD0;
pub const VK_NUMPAD1 = VIRTUAL_KEY.NUMPAD1;
pub const VK_NUMPAD2 = VIRTUAL_KEY.NUMPAD2;
pub const VK_NUMPAD3 = VIRTUAL_KEY.NUMPAD3;
pub const VK_NUMPAD4 = VIRTUAL_KEY.NUMPAD4;
pub const VK_NUMPAD5 = VIRTUAL_KEY.NUMPAD5;
pub const VK_NUMPAD6 = VIRTUAL_KEY.NUMPAD6;
pub const VK_NUMPAD7 = VIRTUAL_KEY.NUMPAD7;
pub const VK_NUMPAD8 = VIRTUAL_KEY.NUMPAD8;
pub const VK_NUMPAD9 = VIRTUAL_KEY.NUMPAD9;
pub const VK_MULTIPLY = VIRTUAL_KEY.MULTIPLY;
pub const VK_ADD = VIRTUAL_KEY.ADD;
pub const VK_SEPARATOR = VIRTUAL_KEY.SEPARATOR;
pub const VK_SUBTRACT = VIRTUAL_KEY.SUBTRACT;
pub const VK_DECIMAL = VIRTUAL_KEY.DECIMAL;
pub const VK_DIVIDE = VIRTUAL_KEY.DIVIDE;
pub const VK_F1 = VIRTUAL_KEY.F1;
pub const VK_F2 = VIRTUAL_KEY.F2;
pub const VK_F3 = VIRTUAL_KEY.F3;
pub const VK_F4 = VIRTUAL_KEY.F4;
pub const VK_F5 = VIRTUAL_KEY.F5;
pub const VK_F6 = VIRTUAL_KEY.F6;
pub const VK_F7 = VIRTUAL_KEY.F7;
pub const VK_F8 = VIRTUAL_KEY.F8;
pub const VK_F9 = VIRTUAL_KEY.F9;
pub const VK_F10 = VIRTUAL_KEY.F10;
pub const VK_F11 = VIRTUAL_KEY.F11;
pub const VK_F12 = VIRTUAL_KEY.F12;
pub const VK_F13 = VIRTUAL_KEY.F13;
pub const VK_F14 = VIRTUAL_KEY.F14;
pub const VK_F15 = VIRTUAL_KEY.F15;
pub const VK_F16 = VIRTUAL_KEY.F16;
pub const VK_F17 = VIRTUAL_KEY.F17;
pub const VK_F18 = VIRTUAL_KEY.F18;
pub const VK_F19 = VIRTUAL_KEY.F19;
pub const VK_F20 = VIRTUAL_KEY.F20;
pub const VK_F21 = VIRTUAL_KEY.F21;
pub const VK_F22 = VIRTUAL_KEY.F22;
pub const VK_F23 = VIRTUAL_KEY.F23;
pub const VK_F24 = VIRTUAL_KEY.F24;
pub const VK_NAVIGATION_VIEW = VIRTUAL_KEY.NAVIGATION_VIEW;
pub const VK_NAVIGATION_MENU = VIRTUAL_KEY.NAVIGATION_MENU;
pub const VK_NAVIGATION_UP = VIRTUAL_KEY.NAVIGATION_UP;
pub const VK_NAVIGATION_DOWN = VIRTUAL_KEY.NAVIGATION_DOWN;
pub const VK_NAVIGATION_LEFT = VIRTUAL_KEY.NAVIGATION_LEFT;
pub const VK_NAVIGATION_RIGHT = VIRTUAL_KEY.NAVIGATION_RIGHT;
pub const VK_NAVIGATION_ACCEPT = VIRTUAL_KEY.NAVIGATION_ACCEPT;
pub const VK_NAVIGATION_CANCEL = VIRTUAL_KEY.NAVIGATION_CANCEL;
pub const VK_NUMLOCK = VIRTUAL_KEY.NUMLOCK;
pub const VK_SCROLL = VIRTUAL_KEY.SCROLL;
pub const VK_OEM_NEC_EQUAL = VIRTUAL_KEY.OEM_NEC_EQUAL;
pub const VK_OEM_FJ_JISHO = VIRTUAL_KEY.OEM_NEC_EQUAL;
pub const VK_OEM_FJ_MASSHOU = VIRTUAL_KEY.OEM_FJ_MASSHOU;
pub const VK_OEM_FJ_TOUROKU = VIRTUAL_KEY.OEM_FJ_TOUROKU;
pub const VK_OEM_FJ_LOYA = VIRTUAL_KEY.OEM_FJ_LOYA;
pub const VK_OEM_FJ_ROYA = VIRTUAL_KEY.OEM_FJ_ROYA;
pub const VK_LSHIFT = VIRTUAL_KEY.LSHIFT;
pub const VK_RSHIFT = VIRTUAL_KEY.RSHIFT;
pub const VK_LCONTROL = VIRTUAL_KEY.LCONTROL;
pub const VK_RCONTROL = VIRTUAL_KEY.RCONTROL;
pub const VK_LMENU = VIRTUAL_KEY.LMENU;
pub const VK_RMENU = VIRTUAL_KEY.RMENU;
pub const VK_BROWSER_BACK = VIRTUAL_KEY.BROWSER_BACK;
pub const VK_BROWSER_FORWARD = VIRTUAL_KEY.BROWSER_FORWARD;
pub const VK_BROWSER_REFRESH = VIRTUAL_KEY.BROWSER_REFRESH;
pub const VK_BROWSER_STOP = VIRTUAL_KEY.BROWSER_STOP;
pub const VK_BROWSER_SEARCH = VIRTUAL_KEY.BROWSER_SEARCH;
pub const VK_BROWSER_FAVORITES = VIRTUAL_KEY.BROWSER_FAVORITES;
pub const VK_BROWSER_HOME = VIRTUAL_KEY.BROWSER_HOME;
pub const VK_VOLUME_MUTE = VIRTUAL_KEY.VOLUME_MUTE;
pub const VK_VOLUME_DOWN = VIRTUAL_KEY.VOLUME_DOWN;
pub const VK_VOLUME_UP = VIRTUAL_KEY.VOLUME_UP;
pub const VK_MEDIA_NEXT_TRACK = VIRTUAL_KEY.MEDIA_NEXT_TRACK;
pub const VK_MEDIA_PREV_TRACK = VIRTUAL_KEY.MEDIA_PREV_TRACK;
pub const VK_MEDIA_STOP = VIRTUAL_KEY.MEDIA_STOP;
pub const VK_MEDIA_PLAY_PAUSE = VIRTUAL_KEY.MEDIA_PLAY_PAUSE;
pub const VK_LAUNCH_MAIL = VIRTUAL_KEY.LAUNCH_MAIL;
pub const VK_LAUNCH_MEDIA_SELECT = VIRTUAL_KEY.LAUNCH_MEDIA_SELECT;
pub const VK_LAUNCH_APP1 = VIRTUAL_KEY.LAUNCH_APP1;
pub const VK_LAUNCH_APP2 = VIRTUAL_KEY.LAUNCH_APP2;
pub const VK_OEM_1 = VIRTUAL_KEY.OEM_1;
pub const VK_OEM_PLUS = VIRTUAL_KEY.OEM_PLUS;
pub const VK_OEM_COMMA = VIRTUAL_KEY.OEM_COMMA;
pub const VK_OEM_MINUS = VIRTUAL_KEY.OEM_MINUS;
pub const VK_OEM_PERIOD = VIRTUAL_KEY.OEM_PERIOD;
pub const VK_OEM_2 = VIRTUAL_KEY.OEM_2;
pub const VK_OEM_3 = VIRTUAL_KEY.OEM_3;
pub const VK_GAMEPAD_A = VIRTUAL_KEY.GAMEPAD_A;
pub const VK_GAMEPAD_B = VIRTUAL_KEY.GAMEPAD_B;
pub const VK_GAMEPAD_X = VIRTUAL_KEY.GAMEPAD_X;
pub const VK_GAMEPAD_Y = VIRTUAL_KEY.GAMEPAD_Y;
pub const VK_GAMEPAD_RIGHT_SHOULDER = VIRTUAL_KEY.GAMEPAD_RIGHT_SHOULDER;
pub const VK_GAMEPAD_LEFT_SHOULDER = VIRTUAL_KEY.GAMEPAD_LEFT_SHOULDER;
pub const VK_GAMEPAD_LEFT_TRIGGER = VIRTUAL_KEY.GAMEPAD_LEFT_TRIGGER;
pub const VK_GAMEPAD_RIGHT_TRIGGER = VIRTUAL_KEY.GAMEPAD_RIGHT_TRIGGER;
pub const VK_GAMEPAD_DPAD_UP = VIRTUAL_KEY.GAMEPAD_DPAD_UP;
pub const VK_GAMEPAD_DPAD_DOWN = VIRTUAL_KEY.GAMEPAD_DPAD_DOWN;
pub const VK_GAMEPAD_DPAD_LEFT = VIRTUAL_KEY.GAMEPAD_DPAD_LEFT;
pub const VK_GAMEPAD_DPAD_RIGHT = VIRTUAL_KEY.GAMEPAD_DPAD_RIGHT;
pub const VK_GAMEPAD_MENU = VIRTUAL_KEY.GAMEPAD_MENU;
pub const VK_GAMEPAD_VIEW = VIRTUAL_KEY.GAMEPAD_VIEW;
pub const VK_GAMEPAD_LEFT_THUMBSTICK_BUTTON = VIRTUAL_KEY.GAMEPAD_LEFT_THUMBSTICK_BUTTON;
pub const VK_GAMEPAD_RIGHT_THUMBSTICK_BUTTON = VIRTUAL_KEY.GAMEPAD_RIGHT_THUMBSTICK_BUTTON;
pub const VK_GAMEPAD_LEFT_THUMBSTICK_UP = VIRTUAL_KEY.GAMEPAD_LEFT_THUMBSTICK_UP;
pub const VK_GAMEPAD_LEFT_THUMBSTICK_DOWN = VIRTUAL_KEY.GAMEPAD_LEFT_THUMBSTICK_DOWN;
pub const VK_GAMEPAD_LEFT_THUMBSTICK_RIGHT = VIRTUAL_KEY.GAMEPAD_LEFT_THUMBSTICK_RIGHT;
pub const VK_GAMEPAD_LEFT_THUMBSTICK_LEFT = VIRTUAL_KEY.GAMEPAD_LEFT_THUMBSTICK_LEFT;
pub const VK_GAMEPAD_RIGHT_THUMBSTICK_UP = VIRTUAL_KEY.GAMEPAD_RIGHT_THUMBSTICK_UP;
pub const VK_GAMEPAD_RIGHT_THUMBSTICK_DOWN = VIRTUAL_KEY.GAMEPAD_RIGHT_THUMBSTICK_DOWN;
pub const VK_GAMEPAD_RIGHT_THUMBSTICK_RIGHT = VIRTUAL_KEY.GAMEPAD_RIGHT_THUMBSTICK_RIGHT;
pub const VK_GAMEPAD_RIGHT_THUMBSTICK_LEFT = VIRTUAL_KEY.GAMEPAD_RIGHT_THUMBSTICK_LEFT;
pub const VK_OEM_4 = VIRTUAL_KEY.OEM_4;
pub const VK_OEM_5 = VIRTUAL_KEY.OEM_5;
pub const VK_OEM_6 = VIRTUAL_KEY.OEM_6;
pub const VK_OEM_7 = VIRTUAL_KEY.OEM_7;
pub const VK_OEM_8 = VIRTUAL_KEY.OEM_8;
pub const VK_OEM_AX = VIRTUAL_KEY.OEM_AX;
pub const VK_OEM_102 = VIRTUAL_KEY.OEM_102;
pub const VK_ICO_HELP = VIRTUAL_KEY.ICO_HELP;
pub const VK_ICO_00 = VIRTUAL_KEY.ICO_00;
pub const VK_PROCESSKEY = VIRTUAL_KEY.PROCESSKEY;
pub const VK_ICO_CLEAR = VIRTUAL_KEY.ICO_CLEAR;
pub const VK_PACKET = VIRTUAL_KEY.PACKET;
pub const VK_OEM_RESET = VIRTUAL_KEY.OEM_RESET;
pub const VK_OEM_JUMP = VIRTUAL_KEY.OEM_JUMP;
pub const VK_OEM_PA1 = VIRTUAL_KEY.OEM_PA1;
pub const VK_OEM_PA2 = VIRTUAL_KEY.OEM_PA2;
pub const VK_OEM_PA3 = VIRTUAL_KEY.OEM_PA3;
pub const VK_OEM_WSCTRL = VIRTUAL_KEY.OEM_WSCTRL;
pub const VK_OEM_CUSEL = VIRTUAL_KEY.OEM_CUSEL;
pub const VK_OEM_ATTN = VIRTUAL_KEY.OEM_ATTN;
pub const VK_OEM_FINISH = VIRTUAL_KEY.OEM_FINISH;
pub const VK_OEM_COPY = VIRTUAL_KEY.OEM_COPY;
pub const VK_OEM_AUTO = VIRTUAL_KEY.OEM_AUTO;
pub const VK_OEM_ENLW = VIRTUAL_KEY.OEM_ENLW;
pub const VK_OEM_BACKTAB = VIRTUAL_KEY.OEM_BACKTAB;
pub const VK_ATTN = VIRTUAL_KEY.ATTN;
pub const VK_CRSEL = VIRTUAL_KEY.CRSEL;
pub const VK_EXSEL = VIRTUAL_KEY.EXSEL;
pub const VK_EREOF = VIRTUAL_KEY.EREOF;
pub const VK_PLAY = VIRTUAL_KEY.PLAY;
pub const VK_ZOOM = VIRTUAL_KEY.ZOOM;
pub const VK_NONAME = VIRTUAL_KEY.NONAME;
pub const VK_PA1 = VIRTUAL_KEY.PA1;
pub const VK_OEM_CLEAR = VIRTUAL_KEY.OEM_CLEAR;

// ---------------------------
// Keyboard and mouse
// ---------------------------
// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetFocus() callconv(.winapi) ?HWND;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetKBCodePage() callconv(.winapi) u32;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetKeyState(
    nVirtKey: i32,
) callconv(.winapi) i16;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetAsyncKeyState(
    vKey: i32,
) callconv(.winapi) i16;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetKeyboardState(
    lpKeyState: *[256]u8,
) callconv(.winapi) BOOL;

pub extern "user32" fn GetCapture() callconv(.winapi) ?HWND;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn SetCapture(
    hWnd: ?HWND,
) callconv(.winapi) ?HWND;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;

// --------------------------
//  GDI
// --------------------------
pub const MONITORENUMPROC = *const fn (
    param0: ?HMONITOR,
    param1: ?HDC,
    param2: ?*RECT,
    param3: LPARAM,
) callconv(.winapi) BOOL;

pub const MONITORINFO = extern struct {
    cbSize: u32,
    rcMonitor: RECT,
    rcWork: RECT,
    dwFlags: u32,
};

pub const MONITOR_FROM_FLAGS = enum(u32) {
    NEAREST = 2,
    NULL = 0,
    PRIMARY = 1,
};
pub const MONITOR_DEFAULTTONEAREST = MONITOR_FROM_FLAGS.NEAREST;
pub const MONITOR_DEFAULTTONULL = MONITOR_FROM_FLAGS.NULL;
pub const MONITOR_DEFAULTTOPRIMARY = MONITOR_FROM_FLAGS.PRIMARY;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn MonitorFromPoint(
    pt: POINT,
    dwFlags: MONITOR_FROM_FLAGS,
) callconv(.winapi) ?HMONITOR;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn MonitorFromRect(
    lprc: ?*RECT,
    dwFlags: MONITOR_FROM_FLAGS,
) callconv(.winapi) ?HMONITOR;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn MonitorFromWindow(
    hwnd: ?HWND,
    dwFlags: MONITOR_FROM_FLAGS,
) callconv(.winapi) ?HMONITOR;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetMonitorInfoA(
    hMonitor: ?HMONITOR,
    lpmi: ?*MONITORINFO,
) callconv(.winapi) BOOL;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn GetMonitorInfoW(
    hMonitor: ?HMONITOR,
    lpmi: ?*MONITORINFO,
) callconv(.winapi) BOOL;

// TODO: this type is limited to platform 'windows5.0'
pub extern "user32" fn EnumDisplayMonitors(
    hdc: ?HDC,
    lprcClip: ?*RECT,
    lpfnEnum: ?MONITORENUMPROC,
    dwData: LPARAM,
) callconv(.winapi) BOOL;

pub const PROPERTYKEY = extern struct {
    fmtid: Guid,
    pid: u32,
};
pub const DECIMAL = extern struct {
    wReserved: u16,
    anon1: extern union {
        anon: extern struct {
            scale: u8,
            sign: u8,
        },
        signscale: u16,
    },
    Hi32: u32,
    anon2: extern union {
        anon: extern struct {
            Lo32: u32,
            Mid32: u32,
        },
        Lo64: u64,
    },
};
pub const LARGE_INTEGER = extern union {
    anon: extern struct {
        LowPart: u32,
        HighPart: i32,
    },
    u: extern struct {
        LowPart: u32,
        HighPart: i32,
    },
    QuadPart: i64,
};
pub const ULARGE_INTEGER = extern union {
    anon: extern struct {
        LowPart: u32,
        HighPart: u32,
    },
    u: extern struct {
        LowPart: u32,
        HighPart: u32,
    },
    QuadPart: u64,
};
pub const BSTR = *u16;
pub const PSTR = [*:0]u8;
pub const S_OK = 0;
pub const S_FALSE = 1;
pub const E_NOTIMPL = -2147467263;
pub const E_NOT_FOUND = -2147023728;
pub const E_OUTOFMEMORY = -2147024882;
pub const E_INVALIDARG = -2147024809;
pub const E_FAIL = -2147467259;
pub const E_UNEXPECTED = -2147418113;
pub const E_NOINTERFACE = -2147467262;
pub const E_POINTER = -2147467261;
pub const E_HANDLE = -2147024890;
pub const E_ABORT = -2147467260;
pub const E_ACCESSDENIED = -2147024891;
pub const E_BOUNDS = -2147483637;
pub const E_CHANGED_STATE = -2147483636;
pub const E_ILLEGAL_STATE_CHANGE = -2147483635;
pub const E_ILLEGAL_METHOD_CALL = -2147483634;
pub const CLASS_E_NOAGGREGATION = -2147221232;
pub const CLASS_E_CLASSNOTAVAILABLE = -2147221231;
pub const CLASS_E_NOTLICENSED = -2147221230;
pub const REGDB_E_CLASSNOTREG = -2147221164;
pub const RPC_E_CHANGED_MODE = -2147417850;
pub const SAFEARRAYBOUND = extern struct {
    cElements: u32,
    lLbound: i32,
};
pub const SAFEARRAY = extern struct {
    cDims: u16,
    fFeatures: u16,
    cbElements: u32,
    cLocks: u32,
    pvData: ?*anyopaque,
    rgsabound: [1]SAFEARRAYBOUND,
};
pub const CLIPDATA = extern struct {
    cbSize: u32,
    ulClipFmt: i32,
    pClipData: ?*u8,
};
pub const VERSIONEDSTREAM = extern struct {
    guidVersion: Guid,
    pStream: ?*IStream,
};
pub const STREAM_SEEK = enum(u32) {
    SET = 0,
    CUR = 1,
    END = 2,
};
pub const STATSTG = extern struct {
    pwcsName: ?PWSTR,
    type: u32,
    cbSize: ULARGE_INTEGER,
    mtime: FILETIME,
    ctime: FILETIME,
    atime: FILETIME,
    grfMode: u32,
    grfLocksSupported: u32,
    clsid: Guid,
    grfStateBits: u32,
    reserved: u32,
};
pub const IStream = extern union {
    pub const VTable = extern struct {
        base: ISequentialStream.VTable,
        Seek: *const fn (
            self: *const IStream,
            dlibMove: LARGE_INTEGER,
            dwOrigin: STREAM_SEEK,
            plibNewPosition: ?*ULARGE_INTEGER,
        ) callconv(.winapi) HRESULT,
        SetSize: *const fn (
            self: *const IStream,
            libNewSize: ULARGE_INTEGER,
        ) callconv(.winapi) HRESULT,
        CopyTo: *const fn (
            self: *const IStream,
            pstm: ?*IStream,
            cb: ULARGE_INTEGER,
            pcbRead: ?*ULARGE_INTEGER,
            pcbWritten: ?*ULARGE_INTEGER,
        ) callconv(.winapi) HRESULT,
        Commit: *const fn (
            self: *const IStream,
            grfCommitFlags: STGC,
        ) callconv(.winapi) HRESULT,
        Revert: *const fn (
            self: *const IStream,
        ) callconv(.winapi) HRESULT,
        LockRegion: *const fn (
            self: *const IStream,
            libOffset: ULARGE_INTEGER,
            cb: ULARGE_INTEGER,
            dwLockType: u32,
        ) callconv(.winapi) HRESULT,
        UnlockRegion: *const fn (
            self: *const IStream,
            libOffset: ULARGE_INTEGER,
            cb: ULARGE_INTEGER,
            dwLockType: u32,
        ) callconv(.winapi) HRESULT,
        Stat: *const fn (
            self: *const IStream,
            pstatstg: ?*STATSTG,
            grfStatFlag: u32,
        ) callconv(.winapi) HRESULT,
        Clone: *const fn (
            self: *const IStream,
            ppstm: ?*?*IStream,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    ISequentialStream: ISequentialStream,
    IUnknown: IUnknown,
};
pub const COINIT = packed struct(u32) {
    _0: u1 = 0,
    APARTMENTTHREADED: u1 = 0,
    DISABLE_OLE1DDE: u1 = 0,
    SPEED_OVER_MEMORY: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const COINIT_APARTMENTTHREADED = COINIT{ .APARTMENTTHREADED = 1 };
pub const COINIT_MULTITHREADED = COINIT{};
pub const COINIT_DISABLE_OLE1DDE = COINIT{ .DISABLE_OLE1DDE = 1 };
pub const COINIT_SPEED_OVER_MEMORY = COINIT{ .SPEED_OVER_MEMORY = 1 };
pub const CLSCTX = packed struct(u32) {
    INPROC_SERVER: u1 = 0,
    INPROC_HANDLER: u1 = 0,
    LOCAL_SERVER: u1 = 0,
    INPROC_SERVER16: u1 = 0,
    REMOTE_SERVER: u1 = 0,
    INPROC_HANDLER16: u1 = 0,
    RESERVED1: u1 = 0,
    RESERVED2: u1 = 0,
    RESERVED3: u1 = 0,
    RESERVED4: u1 = 0,
    NO_CODE_DOWNLOAD: u1 = 0,
    RESERVED5: u1 = 0,
    NO_CUSTOM_MARSHAL: u1 = 0,
    ENABLE_CODE_DOWNLOAD: u1 = 0,
    NO_FAILURE_LOG: u1 = 0,
    DISABLE_AAA: u1 = 0,
    ENABLE_AAA: u1 = 0,
    FROM_DEFAULT_CONTEXT: u1 = 0,
    ACTIVATE_X86_SERVER: u1 = 0,
    ACTIVATE_64_BIT_SERVER: u1 = 0,
    ENABLE_CLOAKING: u1 = 0,
    _21: u1 = 0,
    APPCONTAINER: u1 = 0,
    ACTIVATE_AAA_AS_IU: u1 = 0,
    RESERVED6: u1 = 0,
    ACTIVATE_ARM32_SERVER: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    PS_DLL: u1 = 0,
};
pub const CLSCTX_ALL = CLSCTX{
    .INPROC_SERVER = 1,
    .INPROC_HANDLER = 1,
    .LOCAL_SERVER = 1,
    .REMOTE_SERVER = 1,
};
pub extern "ole32" fn CoInitializeEx(
    pvReserved: ?*anyopaque,
    dwCoInit: COINIT,
) callconv(.winapi) HRESULT;
pub extern "ole32" fn CoCreateInstance(
    rclsid: ?*const Guid,
    pUnkOuter: ?*IUnknown,
    dwClsContext: CLSCTX,
    riid: *const Guid,
    ppv: **anyopaque,
) callconv(.winapi) HRESULT;
pub extern "kernel32" fn CreateEventA(
    lpEventAttributes: ?*SECURITY_ATTRIBUTES,
    bManualReset: BOOL,
    bInitialState: BOOL,
    lpName: ?[*:0]const u8,
) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn WaitForSingleObject(
    hHandle: ?HANDLE,
    dwMilliseconds: u32,
) callconv(.winapi) u32;
pub extern "kernel32" fn GetModuleHandleA(
    lpModuleName: ?[*:0]const u8,
) callconv(.winapi) ?HINSTANCE;
pub const FARPROC = *const fn () callconv(.winapi) isize;
pub extern "kernel32" fn GetProcAddress(
    hModule: ?HINSTANCE,
    lpProcName: ?[*:0]const u8,
) callconv(.winapi) ?FARPROC;
pub extern "kernel32" fn ExitProcess(
    uExitCode: u32,
) callconv(.winapi) noreturn;

pub const INFINITE = 4294967295;
pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: u32,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: BOOL,
};
pub const ISequentialStream = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Read: *const fn (
            self: *const ISequentialStream,
            pv: ?*anyopaque,
            cb: u32,
            pcbRead: ?*u32,
        ) callconv(.winapi) HRESULT,
        Write: *const fn (
            self: *const ISequentialStream,
            pv: ?*const anyopaque,
            cb: u32,
            pcbWritten: ?*u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const CY = extern union {
    anon: extern struct {
        Lo: u32,
        Hi: i32,
    },
    int64: i64,
};
pub const CAC = extern struct {
    cElems: u32,
    pElems: ?PSTR,
};
pub const CAUB = extern struct {
    cElems: u32,
    pElems: ?*u8,
};
pub const CAI = extern struct {
    cElems: u32,
    pElems: ?*i16,
};
pub const CAUI = extern struct {
    cElems: u32,
    pElems: ?*u16,
};
pub const CAL = extern struct {
    cElems: u32,
    pElems: ?*i32,
};
pub const CAUL = extern struct {
    cElems: u32,
    pElems: ?*u32,
};
pub const CAFLT = extern struct {
    cElems: u32,
    pElems: ?*f32,
};
pub const CADBL = extern struct {
    cElems: u32,
    pElems: ?*f64,
};
pub const CACY = extern struct {
    cElems: u32,
    pElems: ?*CY,
};
pub const CADATE = extern struct {
    cElems: u32,
    pElems: ?*f64,
};
pub const CABSTR = extern struct {
    cElems: u32,
    pElems: ?*?BSTR,
};
pub const BSTRBLOB = extern struct {
    cbSize: u32,
    pData: ?*u8,
};
pub const CABSTRBLOB = extern struct {
    cElems: u32,
    pElems: ?*BSTRBLOB,
};
pub const CABOOL = extern struct {
    cElems: u32,
    pElems: ?*i16,
};
pub const CASCODE = extern struct {
    cElems: u32,
    pElems: ?*i32,
};
pub const CAPROPVARIANT = extern struct {
    cElems: u32,
    pElems: ?*PROPVARIANT,
};
pub const CAH = extern struct {
    cElems: u32,
    pElems: ?*LARGE_INTEGER,
};
pub const CAUH = extern struct {
    cElems: u32,
    pElems: ?*ULARGE_INTEGER,
};
pub const CALPSTR = extern struct {
    cElems: u32,
    pElems: ?*?PSTR,
};
pub const CALPWSTR = extern struct {
    cElems: u32,
    pElems: ?*?PWSTR,
};
pub const CAFILETIME = extern struct {
    cElems: u32,
    pElems: ?*FILETIME,
};
pub const CACLIPDATA = extern struct {
    cElems: u32,
    pElems: ?*CLIPDATA,
};
pub const CACLSID = extern struct {
    cElems: u32,
    pElems: ?*Guid,
};
pub const BLOB = extern struct {
    cbSize: u32,
    pBlobData: ?*u8,
};
pub const INVOKEKIND = enum(i32) {
    FUNC = 1,
    PROPERTYGET = 2,
    PROPERTYPUT = 4,
    PROPERTYPUTREF = 8,
};
pub const IDLDESC = extern struct {
    dwReserved: usize,
    wIDLFlags: u16,
};
pub const VARENUM = enum(u16) {
    EMPTY = 0,
    NULL = 1,
    I2 = 2,
    I4 = 3,
    R4 = 4,
    R8 = 5,
    CY = 6,
    DATE = 7,
    BSTR = 8,
    DISPATCH = 9,
    ERROR = 10,
    BOOL = 11,
    VARIANT = 12,
    UNKNOWN = 13,
    DECIMAL = 14,
    I1 = 16,
    UI1 = 17,
    UI2 = 18,
    UI4 = 19,
    I8 = 20,
    UI8 = 21,
    INT = 22,
    UINT = 23,
    VOID = 24,
    HRESULT = 25,
    PTR = 26,
    SAFEARRAY = 27,
    CARRAY = 28,
    USERDEFINED = 29,
    LPSTR = 30,
    LPWSTR = 31,
    RECORD = 36,
    INT_PTR = 37,
    UINT_PTR = 38,
    FILETIME = 64,
    BLOB = 65,
    STREAM = 66,
    STORAGE = 67,
    STREAMED_OBJECT = 68,
    STORED_OBJECT = 69,
    BLOB_OBJECT = 70,
    CF = 71,
    CLSID = 72,
    VERSIONED_STREAM = 73,
    BSTR_BLOB = 4095,
    VECTOR = 4096,
    ARRAY = 8192,
    BYREF = 16384,
    RESERVED = 32768,
    ILLEGAL = 65535,
    _,
};
pub const VARIANT = extern struct {
    anon: extern union {
        anon: extern struct {
            vt: VARENUM,
            wReserved1: u16,
            wReserved2: u16,
            wReserved3: u16,
            anon: extern union {
                llVal: i64,
                lVal: i32,
                bVal: u8,
                iVal: i16,
                fltVal: f32,
                dblVal: f64,
                boolVal: i16,
                __OBSOLETE__VARIANT_BOOL: i16,
                scode: i32,
                cyVal: CY,
                date: f64,
                bstrVal: ?BSTR,
                punkVal: ?*IUnknown,
                pdispVal: ?*IDispatch,
                parray: ?*SAFEARRAY,
                pbVal: ?*u8,
                piVal: ?*i16,
                plVal: ?*i32,
                pllVal: ?*i64,
                pfltVal: ?*f32,
                pdblVal: ?*f64,
                pboolVal: ?*i16,
                __OBSOLETE__VARIANT_PBOOL: ?*i16,
                pscode: ?*i32,
                pcyVal: ?*CY,
                pdate: ?*f64,
                pbstrVal: ?*?BSTR,
                ppunkVal: ?*?*IUnknown,
                ppdispVal: ?*?*IDispatch,
                pparray: ?*?*SAFEARRAY,
                pvarVal: ?*VARIANT,
                byref: ?*anyopaque,
                cVal: CHAR,
                uiVal: u16,
                ulVal: u32,
                ullVal: u64,
                intVal: i32,
                uintVal: u32,
                pdecVal: ?*DECIMAL,
                pcVal: ?PSTR,
                puiVal: ?*u16,
                pulVal: ?*u32,
                pullVal: ?*u64,
                pintVal: ?*i32,
                puintVal: ?*u32,
                anon: extern struct {
                    pvRecord: ?*anyopaque,
                    pRecInfo: ?*IRecordInfo,
                },
            },
        },
        decVal: DECIMAL,
    },
};
pub const IRecordInfo = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        RecordInit: *const fn (
            self: *const IRecordInfo,
            pvNew: ?*anyopaque,
        ) callconv(.winapi) HRESULT,
        RecordClear: *const fn (
            self: *const IRecordInfo,
            pvExisting: ?*anyopaque,
        ) callconv(.winapi) HRESULT,
        RecordCopy: *const fn (
            self: *const IRecordInfo,
            pvExisting: ?*anyopaque,
            pvNew: ?*anyopaque,
        ) callconv(.winapi) HRESULT,
        GetGuid: *const fn (
            self: *const IRecordInfo,
            pguid: ?*Guid,
        ) callconv(.winapi) HRESULT,
        GetName: *const fn (
            self: *const IRecordInfo,
            pbstrName: ?*?BSTR,
        ) callconv(.winapi) HRESULT,
        GetSize: *const fn (
            self: *const IRecordInfo,
            pcbSize: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetTypeInfo: *const fn (
            self: *const IRecordInfo,
            ppTypeInfo: ?*?*ITypeInfo,
        ) callconv(.winapi) HRESULT,
        GetField: *const fn (
            self: *const IRecordInfo,
            pvData: ?*anyopaque,
            szFieldName: ?[*:0]const u16,
            pvarField: ?*VARIANT,
        ) callconv(.winapi) HRESULT,
        GetFieldNoCopy: *const fn (
            self: *const IRecordInfo,
            pvData: ?*anyopaque,
            szFieldName: ?[*:0]const u16,
            pvarField: ?*VARIANT,
            ppvDataCArray: ?*?*anyopaque,
        ) callconv(.winapi) HRESULT,
        PutField: *const fn (
            self: *const IRecordInfo,
            wFlags: u32,
            pvData: ?*anyopaque,
            szFieldName: ?[*:0]const u16,
            pvarField: ?*VARIANT,
        ) callconv(.winapi) HRESULT,
        PutFieldNoCopy: *const fn (
            self: *const IRecordInfo,
            wFlags: u32,
            pvData: ?*anyopaque,
            szFieldName: ?[*:0]const u16,
            pvarField: ?*VARIANT,
        ) callconv(.winapi) HRESULT,
        GetFieldNames: *const fn (
            self: *const IRecordInfo,
            pcNames: ?*u32,
            rgBstrNames: [*]?BSTR,
        ) callconv(.winapi) HRESULT,
        IsMatchingType: *const fn (
            self: *const IRecordInfo,
            pRecordInfo: ?*IRecordInfo,
        ) callconv(.winapi) BOOL,
        RecordCreate: *const fn (
            self: *const IRecordInfo,
        ) callconv(.winapi) ?*anyopaque,
        RecordCreateCopy: *const fn (
            self: *const IRecordInfo,
            pvSource: ?*anyopaque,
            ppvDest: ?*?*anyopaque,
        ) callconv(.winapi) HRESULT,
        RecordDestroy: *const fn (
            self: *const IRecordInfo,
            pvRecord: ?*anyopaque,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const PARAMDESCEX = extern struct {
    cBytes: u32,
    varDefaultValue: VARIANT,
};
pub const PARAMDESC = extern struct {
    pparamdescex: ?*PARAMDESCEX,
    wParamFlags: u16,
};
pub const ARRAYDESC = extern struct {
    tdescElem: TYPEDESC,
    cDims: u16,
    rgbounds: [1]SAFEARRAYBOUND,
};
pub const TYPEDESC = extern struct {
    anon: extern union {
        lptdesc: ?*TYPEDESC,
        lpadesc: ?*ARRAYDESC,
        hreftype: u32,
    },
    vt: VARENUM,
};
pub const ELEMDESC = extern struct {
    tdesc: TYPEDESC,
    anon: extern union {
        idldesc: IDLDESC,
        paramdesc: PARAMDESC,
    },
};
pub const CALLCONV = enum(i32) {
    FASTCALL = 0,
    CDECL = 1,
    MSCPASCAL = 2,
    MACPASCAL = 3,
    STDCALL = 4,
    FPFASTCALL = 5,
    SYSCALL = 6,
    MPWCDECL = 7,
    MPWPASCAL = 8,
    MAX = 9,
};
pub const FUNCKIND = enum(i32) {
    VIRTUAL = 0,
    PUREVIRTUAL = 1,
    NONVIRTUAL = 2,
    STATIC = 3,
    DISPATCH = 4,
};
pub const FUNCDESC = extern struct {
    memid: i32,
    lprgscode: ?*i32,
    lprgelemdescParam: ?*ELEMDESC,
    funckind: FUNCKIND,
    invkind: INVOKEKIND,
    @"callconv": CALLCONV,
    cParams: i16,
    cParamsOpt: i16,
    oVft: i16,
    cScodes: i16,
    elemdescFunc: ELEMDESC,
    wFuncFlags: u16,
};
pub const TYPEATTR = extern struct {
    guid: Guid,
    lcid: u32,
    dwReserved: u32,
    memidConstructor: i32,
    memidDestructor: i32,
    lpstrSchema: ?PWSTR,
    cbSizeInstance: u32,
    typekind: TYPEKIND,
    cFuncs: u16,
    cVars: u16,
    cImplTypes: u16,
    cbSizeVft: u16,
    cbAlignment: u16,
    wTypeFlags: u16,
    wMajorVerNum: u16,
    wMinorVerNum: u16,
    tdescAlias: TYPEDESC,
    idldescType: IDLDESC,
};
pub const TYPEKIND = enum(i32) {
    ENUM = 0,
    RECORD = 1,
    MODULE = 2,
    INTERFACE = 3,
    DISPATCH = 4,
    COCLASS = 5,
    ALIAS = 6,
    UNION = 7,
    MAX = 8,
};
pub const DESCKIND = enum(i32) {
    NONE = 0,
    FUNCDESC = 1,
    VARDESC = 2,
    TYPECOMP = 3,
    IMPLICITAPPOBJ = 4,
    MAX = 5,
};
pub const BINDPTR = extern union {
    lpfuncdesc: ?*FUNCDESC,
    lpvardesc: ?*VARDESC,
    lptcomp: ?*ITypeComp,
};
pub const VARDESC = extern struct {
    memid: i32,
    lpstrSchema: ?PWSTR,
    anon: extern union {
        oInst: u32,
        lpvarValue: ?*VARIANT,
    },
    elemdescVar: ELEMDESC,
    wVarFlags: u16,
    varkind: VARKIND,
};
pub const VARKIND = enum(i32) {
    PERINSTANCE = 0,
    STATIC = 1,
    CONST = 2,
    DISPATCH = 3,
};
pub const ITypeComp = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Bind: *const fn (
            self: *const ITypeComp,
            szName: ?PWSTR,
            lHashVal: u32,
            wFlags: u16,
            ppTInfo: ?*?*ITypeInfo,
            pDescKind: ?*DESCKIND,
            pBindPtr: ?*BINDPTR,
        ) callconv(.winapi) HRESULT,
        BindType: *const fn (
            self: *const ITypeComp,
            szName: ?PWSTR,
            lHashVal: u32,
            ppTInfo: ?*?*ITypeInfo,
            ppTComp: ?*?*ITypeComp,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const DISPPARAMS = extern struct {
    rgvarg: ?*VARIANT,
    rgdispidNamedArgs: ?*i32,
    cArgs: u32,
    cNamedArgs: u32,
};
pub const EXCEPINFO = extern struct {
    wCode: u16,
    wReserved: u16,
    bstrSource: ?BSTR,
    bstrDescription: ?BSTR,
    bstrHelpFile: ?BSTR,
    dwHelpContext: u32,
    pvReserved: ?*anyopaque,
    pfnDeferredFillIn: ?LPEXCEPFINO_DEFERRED_FILLIN,
    scode: i32,
};
pub const LPEXCEPFINO_DEFERRED_FILLIN = *const fn (
    pExcepInfo: ?*EXCEPINFO,
) callconv(.winapi) HRESULT;
pub const ITypeInfo = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetTypeAttr: *const fn (
            self: *const ITypeInfo,
            ppTypeAttr: ?*?*TYPEATTR,
        ) callconv(.winapi) HRESULT,
        GetTypeComp: *const fn (
            self: *const ITypeInfo,
            ppTComp: ?*?*ITypeComp,
        ) callconv(.winapi) HRESULT,
        GetFuncDesc: *const fn (
            self: *const ITypeInfo,
            index: u32,
            ppFuncDesc: ?*?*FUNCDESC,
        ) callconv(.winapi) HRESULT,
        GetVarDesc: *const fn (
            self: *const ITypeInfo,
            index: u32,
            ppVarDesc: ?*?*VARDESC,
        ) callconv(.winapi) HRESULT,
        GetNames: *const fn (
            self: *const ITypeInfo,
            memid: i32,
            rgBstrNames: [*]?BSTR,
            cMaxNames: u32,
            pcNames: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetRefTypeOfImplType: *const fn (
            self: *const ITypeInfo,
            index: u32,
            pRefType: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetImplTypeFlags: *const fn (
            self: *const ITypeInfo,
            index: u32,
            pImplTypeFlags: ?*i32,
        ) callconv(.winapi) HRESULT,
        GetIDsOfNames: *const fn (
            self: *const ITypeInfo,
            rgszNames: [*]?PWSTR,
            cNames: u32,
            pMemId: [*]i32,
        ) callconv(.winapi) HRESULT,
        Invoke: *const fn (
            self: *const ITypeInfo,
            pvInstance: ?*anyopaque,
            memid: i32,
            wFlags: u16,
            pDispParams: ?*DISPPARAMS,
            pVarResult: ?*VARIANT,
            pExcepInfo: ?*EXCEPINFO,
            puArgErr: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetDocumentation: *const fn (
            self: *const ITypeInfo,
            memid: i32,
            pBstrName: ?*?BSTR,
            pBstrDocString: ?*?BSTR,
            pdwHelpContext: ?*u32,
            pBstrHelpFile: ?*?BSTR,
        ) callconv(.winapi) HRESULT,
        GetDllEntry: *const fn (
            self: *const ITypeInfo,
            memid: i32,
            invKind: INVOKEKIND,
            pBstrDllName: ?*?BSTR,
            pBstrName: ?*?BSTR,
            pwOrdinal: ?*u16,
        ) callconv(.winapi) HRESULT,
        GetRefTypeInfo: *const fn (
            self: *const ITypeInfo,
            hRefType: u32,
            ppTInfo: ?*?*ITypeInfo,
        ) callconv(.winapi) HRESULT,
        AddressOfMember: *const fn (
            self: *const ITypeInfo,
            memid: i32,
            invKind: INVOKEKIND,
            ppv: ?*?*anyopaque,
        ) callconv(.winapi) HRESULT,
        CreateInstance: *const fn (
            self: *const ITypeInfo,
            pUnkOuter: ?*IUnknown,
            riid: ?*const Guid,
            ppvObj: **anyopaque,
        ) callconv(.winapi) HRESULT,
        GetMops: *const fn (
            self: *const ITypeInfo,
            memid: i32,
            pBstrMops: ?*?BSTR,
        ) callconv(.winapi) HRESULT,
        GetContainingTypeLib: *const fn (
            self: *const ITypeInfo,
            ppTLib: ?*?*ITypeLib,
            pIndex: ?*u32,
        ) callconv(.winapi) HRESULT,
        ReleaseTypeAttr: *const fn (
            self: *const ITypeInfo,
            pTypeAttr: ?*TYPEATTR,
        ) callconv(.winapi) void,
        ReleaseFuncDesc: *const fn (
            self: *const ITypeInfo,
            pFuncDesc: ?*FUNCDESC,
        ) callconv(.winapi) void,
        ReleaseVarDesc: *const fn (
            self: *const ITypeInfo,
            pVarDesc: ?*VARDESC,
        ) callconv(.winapi) void,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const SYSKIND = enum(i32) {
    WIN16 = 0,
    WIN32 = 1,
    MAC = 2,
    WIN64 = 3,
};
pub const TLIBATTR = extern struct {
    guid: Guid,
    lcid: u32,
    syskind: SYSKIND,
    wMajorVerNum: u16,
    wMinorVerNum: u16,
    wLibFlags: u16,
};
pub const ITypeLib = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetTypeInfoCount: *const fn (
            self: *const ITypeLib,
        ) callconv(.winapi) u32,
        GetTypeInfo: *const fn (
            self: *const ITypeLib,
            index: u32,
            ppTInfo: ?*?*ITypeInfo,
        ) callconv(.winapi) HRESULT,
        GetTypeInfoType: *const fn (
            self: *const ITypeLib,
            index: u32,
            pTKind: ?*TYPEKIND,
        ) callconv(.winapi) HRESULT,
        GetTypeInfoOfGuid: *const fn (
            self: *const ITypeLib,
            guid: ?*const Guid,
            ppTinfo: ?*?*ITypeInfo,
        ) callconv(.winapi) HRESULT,
        GetLibAttr: *const fn (
            self: *const ITypeLib,
            ppTLibAttr: ?*?*TLIBATTR,
        ) callconv(.winapi) HRESULT,
        GetTypeComp: *const fn (
            self: *const ITypeLib,
            ppTComp: ?*?*ITypeComp,
        ) callconv(.winapi) HRESULT,
        GetDocumentation: *const fn (
            self: *const ITypeLib,
            index: i32,
            pBstrName: ?*?BSTR,
            pBstrDocString: ?*?BSTR,
            pdwHelpContext: ?*u32,
            pBstrHelpFile: ?*?BSTR,
        ) callconv(.winapi) HRESULT,
        IsName: *const fn (
            self: *const ITypeLib,
            szNameBuf: ?PWSTR,
            lHashVal: u32,
            pfName: ?*BOOL,
        ) callconv(.winapi) HRESULT,
        FindName: *const fn (
            self: *const ITypeLib,
            szNameBuf: ?PWSTR,
            lHashVal: u32,
            ppTInfo: [*]?*ITypeInfo,
            rgMemId: [*]i32,
            pcFound: ?*u16,
        ) callconv(.winapi) HRESULT,
        ReleaseTLibAttr: *const fn (
            self: *const ITypeLib,
            pTLibAttr: ?*TLIBATTR,
        ) callconv(.winapi) void,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const IDispatch = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetTypeInfoCount: *const fn (
            self: *const IDispatch,
            pctinfo: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetTypeInfo: *const fn (
            self: *const IDispatch,
            iTInfo: u32,
            lcid: u32,
            ppTInfo: ?*?*ITypeInfo,
        ) callconv(.winapi) HRESULT,
        GetIDsOfNames: *const fn (
            self: *const IDispatch,
            riid: ?*const Guid,
            rgszNames: [*]?PWSTR,
            cNames: u32,
            lcid: u32,
            rgDispId: [*]i32,
        ) callconv(.winapi) HRESULT,
        Invoke: *const fn (
            self: *const IDispatch,
            dispIdMember: i32,
            riid: ?*const Guid,
            lcid: u32,
            wFlags: u16,
            pDispParams: ?*DISPPARAMS,
            pVarResult: ?*VARIANT,
            pExcepInfo: ?*EXCEPINFO,
            puArgErr: ?*u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const IEnumSTATSTG = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Next: *const fn (
            self: *const IEnumSTATSTG,
            celt: u32,
            rgelt: [*]STATSTG,
            pceltFetched: ?*u32,
        ) callconv(.winapi) HRESULT,
        Skip: *const fn (
            self: *const IEnumSTATSTG,
            celt: u32,
        ) callconv(.winapi) HRESULT,
        Reset: *const fn (
            self: *const IEnumSTATSTG,
        ) callconv(.winapi) HRESULT,
        Clone: *const fn (
            self: *const IEnumSTATSTG,
            ppenum: ?*?*IEnumSTATSTG,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const IStorage = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        CreateStream: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            grfMode: STGM,
            reserved1: u32,
            reserved2: u32,
            ppstm: ?*?*IStream,
        ) callconv(.winapi) HRESULT,
        OpenStream: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            reserved1: ?*anyopaque,
            grfMode: STGM,
            reserved2: u32,
            ppstm: ?*?*IStream,
        ) callconv(.winapi) HRESULT,
        CreateStorage: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            grfMode: STGM,
            reserved1: u32,
            reserved2: u32,
            ppstg: ?*?*IStorage,
        ) callconv(.winapi) HRESULT,
        OpenStorage: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            pstgPriority: ?*IStorage,
            grfMode: STGM,
            snbExclude: ?*?*u16,
            reserved: u32,
            ppstg: ?*?*IStorage,
        ) callconv(.winapi) HRESULT,
        CopyTo: *const fn (
            self: *const IStorage,
            ciidExclude: u32,
            rgiidExclude: ?[*]const Guid,
            snbExclude: ?*?*u16,
            pstgDest: ?*IStorage,
        ) callconv(.winapi) HRESULT,
        MoveElementTo: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            pstgDest: ?*IStorage,
            pwcsNewName: ?[*:0]const u16,
            grfFlags: STGMOVE,
        ) callconv(.winapi) HRESULT,
        Commit: *const fn (
            self: *const IStorage,
            grfCommitFlags: STGC,
        ) callconv(.winapi) HRESULT,
        Revert: *const fn (
            self: *const IStorage,
        ) callconv(.winapi) HRESULT,
        EnumElements: *const fn (
            self: *const IStorage,
            reserved1: u32,
            reserved2: ?*anyopaque,
            reserved3: u32,
            ppenum: ?*?*IEnumSTATSTG,
        ) callconv(.winapi) HRESULT,
        DestroyElement: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
        ) callconv(.winapi) HRESULT,
        RenameElement: *const fn (
            self: *const IStorage,
            pwcsOldName: ?[*:0]const u16,
            pwcsNewName: ?[*:0]const u16,
        ) callconv(.winapi) HRESULT,
        SetElementTimes: *const fn (
            self: *const IStorage,
            pwcsName: ?[*:0]const u16,
            pctime: ?*const FILETIME,
            patime: ?*const FILETIME,
            pmtime: ?*const FILETIME,
        ) callconv(.winapi) HRESULT,
        SetClass: *const fn (
            self: *const IStorage,
            clsid: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        SetStateBits: *const fn (
            self: *const IStorage,
            grfStateBits: u32,
            grfMask: u32,
        ) callconv(.winapi) HRESULT,
        Stat: *const fn (
            self: *const IStorage,
            pstatstg: ?*STATSTG,
            grfStatFlag: u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
};
pub const PROPVARIANT = extern struct {
    anon: extern union {
        anon: extern struct {
            vt: VARENUM,
            wReserved1: u16,
            wReserved2: u16,
            wReserved3: u16,
            anon: extern union {
                cVal: CHAR,
                bVal: u8,
                iVal: i16,
                uiVal: u16,
                lVal: i32,
                ulVal: u32,
                intVal: i32,
                uintVal: u32,
                hVal: LARGE_INTEGER,
                uhVal: ULARGE_INTEGER,
                fltVal: f32,
                dblVal: f64,
                boolVal: i16,
                __OBSOLETE__VARIANT_BOOL: i16,
                scode: i32,
                cyVal: CY,
                date: f64,
                filetime: FILETIME,
                puuid: ?*Guid,
                pclipdata: ?*CLIPDATA,
                bstrVal: ?BSTR,
                bstrblobVal: BSTRBLOB,
                blob: BLOB,
                pszVal: ?PSTR,
                pwszVal: ?PWSTR,
                punkVal: ?*IUnknown,
                pdispVal: ?*IDispatch,
                pStream: ?*IStream,
                pStorage: ?*IStorage,
                pVersionedStream: ?*VERSIONEDSTREAM,
                parray: ?*SAFEARRAY,
                cac: CAC,
                caub: CAUB,
                cai: CAI,
                caui: CAUI,
                cal: CAL,
                caul: CAUL,
                cah: CAH,
                cauh: CAUH,
                caflt: CAFLT,
                cadbl: CADBL,
                cabool: CABOOL,
                cascode: CASCODE,
                cacy: CACY,
                cadate: CADATE,
                cafiletime: CAFILETIME,
                cauuid: CACLSID,
                caclipdata: CACLIPDATA,
                cabstr: CABSTR,
                cabstrblob: CABSTRBLOB,
                calpstr: CALPSTR,
                calpwstr: CALPWSTR,
                capropvar: CAPROPVARIANT,
                pcVal: ?PSTR,
                pbVal: ?*u8,
                piVal: ?*i16,
                puiVal: ?*u16,
                plVal: ?*i32,
                pulVal: ?*u32,
                pintVal: ?*i32,
                puintVal: ?*u32,
                pfltVal: ?*f32,
                pdblVal: ?*f64,
                pboolVal: ?*i16,
                pdecVal: ?*DECIMAL,
                pscode: ?*i32,
                pcyVal: ?*CY,
                pdate: ?*f64,
                pbstrVal: ?*?BSTR,
                ppunkVal: ?*?*IUnknown,
                ppdispVal: ?*?*IDispatch,
                pparray: ?*?*SAFEARRAY,
                pvarVal: ?*PROPVARIANT,
            },
        },
        decVal: DECIMAL,
    },
};
pub const WAVEFORMATEX = extern struct {
    wFormatTag: u16 align(1),
    nChannels: u16 align(1),
    nSamplesPerSec: u32 align(1),
    nAvgBytesPerSec: u32 align(1),
    nBlockAlign: u16 align(1),
    wBitsPerSample: u16 align(1),
    cbSize: u16 align(1),
};
pub const WAVEFORMATEXTENSIBLE = extern struct {
    Format: WAVEFORMATEX align(1),
    Samples: extern union {
        wValidBitsPerSample: u16 align(1),
        wSamplesPerBlock: u16 align(1),
        wReserved: u16 align(1),
    },
    dwChannelMask: u32 align(1),
    SubFormat: Guid align(1),
};
pub const CLSID_MMDeviceEnumerator = &Guid.initString("bcde0395-e52f-467c-8e3d-c4579291692e");
pub const DIRECTX_AUDIO_ACTIVATION_PARAMS = extern struct {
    cbDirectXAudioActivationParams: u32,
    guidAudioSession: Guid,
    dwAudioStreamFlags: u32,
};
pub const EDataFlow = enum(i32) {
    eRender = 0,
    eCapture = 1,
    eAll = 2,
    EDataFlow_enum_count = 3,
};
pub const ERole = enum(i32) {
    eConsole = 0,
    eMultimedia = 1,
    eCommunications = 2,
    ERole_enum_count = 3,
};
pub const AUDCLNT_SHAREMODE = enum(i32) {
    SHARED = 0,
    EXCLUSIVE = 1,
};
pub const IID_IAudioClient = &Guid.initString("1cb9ad4c-dbfa-4c32-b178-c2f568a703b2");
pub const IAudioClient = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Initialize: *const fn (
            self: *const IAudioClient,
            ShareMode: AUDCLNT_SHAREMODE,
            StreamFlags: u32,
            hnsBufferDuration: i64,
            hnsPeriodicity: i64,
            pFormat: ?*const WAVEFORMATEX,
            AudioSessionGuid: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        GetBufferSize: *const fn (
            self: *const IAudioClient,
            pNumBufferFrames: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetStreamLatency: *const fn (
            self: *const IAudioClient,
            phnsLatency: ?*i64,
        ) callconv(.winapi) HRESULT,
        GetCurrentPadding: *const fn (
            self: *const IAudioClient,
            pNumPaddingFrames: ?*u32,
        ) callconv(.winapi) HRESULT,
        IsFormatSupported: *const fn (
            self: *const IAudioClient,
            ShareMode: AUDCLNT_SHAREMODE,
            pFormat: ?*const WAVEFORMATEX,
            ppClosestMatch: ?*?*WAVEFORMATEX,
        ) callconv(.winapi) HRESULT,
        GetMixFormat: *const fn (
            self: *const IAudioClient,
            ppDeviceFormat: ?*?*WAVEFORMATEX,
        ) callconv(.winapi) HRESULT,
        GetDevicePeriod: *const fn (
            self: *const IAudioClient,
            phnsDefaultDevicePeriod: ?*i64,
            phnsMinimumDevicePeriod: ?*i64,
        ) callconv(.winapi) HRESULT,
        Start: *const fn (
            self: *const IAudioClient,
        ) callconv(.winapi) HRESULT,
        Stop: *const fn (
            self: *const IAudioClient,
        ) callconv(.winapi) HRESULT,
        Reset: *const fn (
            self: *const IAudioClient,
        ) callconv(.winapi) HRESULT,
        SetEventHandle: *const fn (
            self: *const IAudioClient,
            eventHandle: ?HANDLE,
        ) callconv(.winapi) HRESULT,
        GetService: *const fn (
            self: *const IAudioClient,
            riid: *const Guid,
            ppv: **anyopaque,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn Initialize(self: *const IAudioClient, ShareMode: AUDCLNT_SHAREMODE, StreamFlags: u32, hnsBufferDuration: i64, hnsPeriodicity: i64, pFormat: ?*const WAVEFORMATEX, AudioSessionGuid: ?*const Guid) HRESULT {
        return self.vtable.Initialize(self, ShareMode, StreamFlags, hnsBufferDuration, hnsPeriodicity, pFormat, AudioSessionGuid);
    }
    pub inline fn GetBufferSize(self: *const IAudioClient, pNumBufferFrames: ?*u32) HRESULT {
        return self.vtable.GetBufferSize(self, pNumBufferFrames);
    }
    pub inline fn GetStreamLatency(self: *const IAudioClient, phnsLatency: ?*i64) HRESULT {
        return self.vtable.GetStreamLatency(self, phnsLatency);
    }
    pub inline fn GetCurrentPadding(self: *const IAudioClient, pNumPaddingFrames: ?*u32) HRESULT {
        return self.vtable.GetCurrentPadding(self, pNumPaddingFrames);
    }
    pub inline fn IsFormatSupported(self: *const IAudioClient, ShareMode: AUDCLNT_SHAREMODE, pFormat: ?*const WAVEFORMATEX, ppClosestMatch: ?*?*WAVEFORMATEX) HRESULT {
        return self.vtable.IsFormatSupported(self, ShareMode, pFormat, ppClosestMatch);
    }
    pub inline fn GetMixFormat(self: *const IAudioClient, ppDeviceFormat: ?*?*WAVEFORMATEX) HRESULT {
        return self.vtable.GetMixFormat(self, ppDeviceFormat);
    }
    pub inline fn GetDevicePeriod(self: *const IAudioClient, phnsDefaultDevicePeriod: ?*i64, phnsMinimumDevicePeriod: ?*i64) HRESULT {
        return self.vtable.GetDevicePeriod(self, phnsDefaultDevicePeriod, phnsMinimumDevicePeriod);
    }
    pub inline fn Start(self: *const IAudioClient) HRESULT {
        return self.vtable.Start(self);
    }
    pub inline fn Stop(self: *const IAudioClient) HRESULT {
        return self.vtable.Stop(self);
    }
    pub inline fn Reset(self: *const IAudioClient) HRESULT {
        return self.vtable.Reset(self);
    }
    pub inline fn SetEventHandle(self: *const IAudioClient, eventHandle: ?HANDLE) HRESULT {
        return self.vtable.SetEventHandle(self, eventHandle);
    }
    pub inline fn GetService(self: *const IAudioClient, riid: *const Guid, ppv: **anyopaque) HRESULT {
        return self.vtable.GetService(self, riid, ppv);
    }
};
pub const AUDCLNT_STREAMOPTIONS = enum(u32) {
    NONE = 0,
    RAW = 1,
    MATCH_FORMAT = 2,
    AMBISONICS = 4,
};
pub const AudioClientProperties = extern struct {
    cbSize: u32,
    bIsOffload: BOOL,
    eCategory: AUDIO_STREAM_CATEGORY,
    Options: AUDCLNT_STREAMOPTIONS,
};
pub const AUDIO_STREAM_CATEGORY = enum(i32) {
    Other = 0,
    ForegroundOnlyMedia = 1,
    Communications = 3,
    Alerts = 4,
    SoundEffects = 5,
    GameEffects = 6,
    GameMedia = 7,
    GameChat = 8,
    Speech = 9,
    Movie = 10,
    Media = 11,
    FarFieldSpeech = 12,
    UniformSpeech = 13,
    VoiceTyping = 14,
};
pub const IID_IAudioClient2 = &Guid.initString("726778cd-f60a-4eda-82de-e47610cd78aa");
pub const IAudioClient2 = extern union {
    pub const VTable = extern struct {
        base: IAudioClient.VTable,
        IsOffloadCapable: *const fn (
            self: *const IAudioClient2,
            Category: AUDIO_STREAM_CATEGORY,
            pbOffloadCapable: ?*BOOL,
        ) callconv(.winapi) HRESULT,
        SetClientProperties: *const fn (
            self: *const IAudioClient2,
            pProperties: ?*const AudioClientProperties,
        ) callconv(.winapi) HRESULT,
        GetBufferSizeLimits: *const fn (
            self: *const IAudioClient2,
            pFormat: ?*const WAVEFORMATEX,
            bEventDriven: BOOL,
            phnsMinBufferDuration: ?*i64,
            phnsMaxBufferDuration: ?*i64,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IAudioClient: IAudioClient,
    IUnknown: IUnknown,
    pub inline fn IsOffloadCapable(self: *const IAudioClient2, Category: AUDIO_STREAM_CATEGORY, pbOffloadCapable: ?*BOOL) HRESULT {
        return self.vtable.IsOffloadCapable(self, Category, pbOffloadCapable);
    }
    pub inline fn SetClientProperties(self: *const IAudioClient2, pProperties: ?*const AudioClientProperties) HRESULT {
        return self.vtable.SetClientProperties(self, pProperties);
    }
    pub inline fn GetBufferSizeLimits(self: *const IAudioClient2, pFormat: ?*const WAVEFORMATEX, bEventDriven: BOOL, phnsMinBufferDuration: ?*i64, phnsMaxBufferDuration: ?*i64) HRESULT {
        return self.vtable.GetBufferSizeLimits(self, pFormat, bEventDriven, phnsMinBufferDuration, phnsMaxBufferDuration);
    }
};
pub const IID_IAudioClient3 = &Guid.initString("7ed4ee07-8e67-4cd4-8c1a-2b7a5987ad42");
pub const IAudioClient3 = extern union {
    pub const VTable = extern struct {
        base: IAudioClient2.VTable,
        GetSharedModeEnginePeriod: *const fn (
            self: *const IAudioClient3,
            pFormat: ?*const WAVEFORMATEX,
            pDefaultPeriodInFrames: ?*u32,
            pFundamentalPeriodInFrames: ?*u32,
            pMinPeriodInFrames: ?*u32,
            pMaxPeriodInFrames: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetCurrentSharedModeEnginePeriod: *const fn (
            self: *const IAudioClient3,
            ppFormat: ?*?*WAVEFORMATEX,
            pCurrentPeriodInFrames: ?*u32,
        ) callconv(.winapi) HRESULT,
        InitializeSharedAudioStream: *const fn (
            self: *const IAudioClient3,
            StreamFlags: u32,
            PeriodInFrames: u32,
            pFormat: ?*const WAVEFORMATEX,
            AudioSessionGuid: ?*const Guid,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IAudioClient2: IAudioClient2,
    IAudioClient: IAudioClient,
    IUnknown: IUnknown,
    pub inline fn GetSharedModeEnginePeriod(self: *const IAudioClient3, pFormat: ?*const WAVEFORMATEX, pDefaultPeriodInFrames: ?*u32, pFundamentalPeriodInFrames: ?*u32, pMinPeriodInFrames: ?*u32, pMaxPeriodInFrames: ?*u32) HRESULT {
        return self.vtable.GetSharedModeEnginePeriod(self, pFormat, pDefaultPeriodInFrames, pFundamentalPeriodInFrames, pMinPeriodInFrames, pMaxPeriodInFrames);
    }
    pub inline fn GetCurrentSharedModeEnginePeriod(self: *const IAudioClient3, ppFormat: ?*?*WAVEFORMATEX, pCurrentPeriodInFrames: ?*u32) HRESULT {
        return self.vtable.GetCurrentSharedModeEnginePeriod(self, ppFormat, pCurrentPeriodInFrames);
    }
    pub inline fn InitializeSharedAudioStream(self: *const IAudioClient3, StreamFlags: u32, PeriodInFrames: u32, pFormat: ?*const WAVEFORMATEX, AudioSessionGuid: ?*const Guid) HRESULT {
        return self.vtable.InitializeSharedAudioStream(self, StreamFlags, PeriodInFrames, pFormat, AudioSessionGuid);
    }
};
pub extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;
pub const IID_IAudioRenderClient = &Guid.initString("f294acfc-3146-4483-a7bf-addca7c260e2");
pub const IAudioRenderClient = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetBuffer: *const fn (
            self: *const IAudioRenderClient,
            NumFramesRequested: u32,
            ppData: ?*?*u8,
        ) callconv(.winapi) HRESULT,
        ReleaseBuffer: *const fn (
            self: *const IAudioRenderClient,
            NumFramesWritten: u32,
            dwFlags: u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetBuffer(self: *const IAudioRenderClient, NumFramesRequested: u32, ppData: ?*?*u8) HRESULT {
        return self.vtable.GetBuffer(self, NumFramesRequested, ppData);
    }
    pub inline fn ReleaseBuffer(self: *const IAudioRenderClient, NumFramesWritten: u32, dwFlags: u32) HRESULT {
        return self.vtable.ReleaseBuffer(self, NumFramesWritten, dwFlags);
    }
};
pub const IID_IAudioCaptureClient = &Guid.initString("c8adbd64-e71e-48a0-a4de-185c395cd317");
pub const IAudioCaptureClient = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetBuffer: *const fn (
            self: *const IAudioCaptureClient,
            ppData: ?*?*u8,
            pNumFramesToRead: ?*u32,
            pdwFlags: ?*u32,
            pu64DevicePosition: ?*u64,
            pu64QPCPosition: ?*u64,
        ) callconv(.winapi) HRESULT,
        ReleaseBuffer: *const fn (
            self: *const IAudioCaptureClient,
            NumFramesRead: u32,
        ) callconv(.winapi) HRESULT,
        GetNextPacketSize: *const fn (
            self: *const IAudioCaptureClient,
            pNumFramesInNextPacket: ?*u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetBuffer(self: *const IAudioCaptureClient, ppData: ?*?*u8, pNumFramesToRead: ?*u32, pdwFlags: ?*u32, pu64DevicePosition: ?*u64, pu64QPCPosition: ?*u64) HRESULT {
        return self.vtable.GetBuffer(self, ppData, pNumFramesToRead, pdwFlags, pu64DevicePosition, pu64QPCPosition);
    }
    pub inline fn ReleaseBuffer(self: *const IAudioCaptureClient, NumFramesRead: u32) HRESULT {
        return self.vtable.ReleaseBuffer(self, NumFramesRead);
    }
    pub inline fn GetNextPacketSize(self: *const IAudioCaptureClient, pNumFramesInNextPacket: ?*u32) HRESULT {
        return self.vtable.GetNextPacketSize(self, pNumFramesInNextPacket);
    }
};
pub const IID_ISimpleAudioVolume = &Guid.initString("87ce5498-68d6-44e5-9215-6da47ef883d8");
pub const ISimpleAudioVolume = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        SetMasterVolume: *const fn (
            self: *const ISimpleAudioVolume,
            fLevel: f32,
            EventContext: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        GetMasterVolume: *const fn (
            self: *const ISimpleAudioVolume,
            pfLevel: ?*f32,
        ) callconv(.winapi) HRESULT,
        SetMute: *const fn (
            self: *const ISimpleAudioVolume,
            bMute: BOOL,
            EventContext: ?*const Guid,
        ) callconv(.winapi) HRESULT,
        GetMute: *const fn (
            self: *const ISimpleAudioVolume,
            pbMute: ?*BOOL,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn SetMasterVolume(self: *const ISimpleAudioVolume, fLevel: f32, EventContext: ?*const Guid) HRESULT {
        return self.vtable.SetMasterVolume(self, fLevel, EventContext);
    }
    pub inline fn GetMasterVolume(self: *const ISimpleAudioVolume, pfLevel: ?*f32) HRESULT {
        return self.vtable.GetMasterVolume(self, pfLevel);
    }
    pub inline fn SetMute(self: *const ISimpleAudioVolume, bMute: BOOL, EventContext: ?*const Guid) HRESULT {
        return self.vtable.SetMute(self, bMute, EventContext);
    }
    pub inline fn GetMute(self: *const ISimpleAudioVolume, pbMute: ?*BOOL) HRESULT {
        return self.vtable.GetMute(self, pbMute);
    }
};
pub const IID_IPropertyStore = &Guid.initString("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99");
pub const IPropertyStore = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetCount: *const fn (
            self: *const IPropertyStore,
            cProps: ?*u32,
        ) callconv(.winapi) HRESULT,
        GetAt: *const fn (
            self: *const IPropertyStore,
            iProp: u32,
            pkey: ?*PROPERTYKEY,
        ) callconv(.winapi) HRESULT,
        GetValue: *const fn (
            self: *const IPropertyStore,
            key: ?*const PROPERTYKEY,
            pv: ?*PROPVARIANT,
        ) callconv(.winapi) HRESULT,
        SetValue: *const fn (
            self: *const IPropertyStore,
            key: ?*const PROPERTYKEY,
            propvar: ?*const PROPVARIANT,
        ) callconv(.winapi) HRESULT,
        Commit: *const fn (
            self: *const IPropertyStore,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetCount(self: *const IPropertyStore, cProps: ?*u32) HRESULT {
        return self.vtable.GetCount(self, cProps);
    }
    pub inline fn GetAt(self: *const IPropertyStore, iProp: u32, pkey: ?*PROPERTYKEY) HRESULT {
        return self.vtable.GetAt(self, iProp, pkey);
    }
    pub inline fn GetValue(self: *const IPropertyStore, key: ?*const PROPERTYKEY, pv: ?*PROPVARIANT) HRESULT {
        return self.vtable.GetValue(self, key, pv);
    }
    pub inline fn SetValue(self: *const IPropertyStore, key: ?*const PROPERTYKEY, propvar: ?*const PROPVARIANT) HRESULT {
        return self.vtable.SetValue(self, key, propvar);
    }
    pub inline fn Commit(self: *const IPropertyStore) HRESULT {
        return self.vtable.Commit(self);
    }
};
pub const IID_IMMDevice = &Guid.initString("d666063f-1587-4e43-81f1-b948e807363f");
pub const IMMDevice = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Activate: *const fn (
            self: *const IMMDevice,
            iid: ?*const Guid,
            dwClsCtx: CLSCTX,
            pActivationParams: ?*PROPVARIANT,
            ppInterface: **anyopaque,
        ) callconv(.winapi) HRESULT,
        OpenPropertyStore: *const fn (
            self: *const IMMDevice,
            stgmAccess: STGM,
            ppProperties: ?*?*IPropertyStore,
        ) callconv(.winapi) HRESULT,
        GetId: *const fn (
            self: *const IMMDevice,
            ppstrId: ?*?PWSTR,
        ) callconv(.winapi) HRESULT,
        GetState: *const fn (
            self: *const IMMDevice,
            pdwState: ?*u32,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn Activate(self: *const IMMDevice, iid: ?*const Guid, dwClsCtx: CLSCTX, pActivationParams: ?*PROPVARIANT, ppInterface: **anyopaque) HRESULT {
        return self.vtable.Activate(self, iid, dwClsCtx, pActivationParams, ppInterface);
    }
    pub inline fn OpenPropertyStore(self: *const IMMDevice, stgmAccess: STGM, ppProperties: ?*?*IPropertyStore) HRESULT {
        return self.vtable.OpenPropertyStore(self, stgmAccess, ppProperties);
    }
    pub inline fn GetId(self: *const IMMDevice, ppstrId: ?*?PWSTR) HRESULT {
        return self.vtable.GetId(self, ppstrId);
    }
    pub inline fn GetState(self: *const IMMDevice, pdwState: ?*u32) HRESULT {
        return self.vtable.GetState(self, pdwState);
    }
};
pub const IID_IMMNotificationClient = &Guid.initString("7991eec9-7e89-4d85-8390-6c703cec60c0");
pub const IMMNotificationClient = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        OnDeviceStateChanged: *const fn (
            self: *const IMMNotificationClient,
            pwstrDeviceId: ?[*:0]const u16,
            dwNewState: u32,
        ) callconv(.winapi) HRESULT,
        OnDeviceAdded: *const fn (
            self: *const IMMNotificationClient,
            pwstrDeviceId: ?[*:0]const u16,
        ) callconv(.winapi) HRESULT,
        OnDeviceRemoved: *const fn (
            self: *const IMMNotificationClient,
            pwstrDeviceId: ?[*:0]const u16,
        ) callconv(.winapi) HRESULT,
        OnDefaultDeviceChanged: *const fn (
            self: *const IMMNotificationClient,
            flow: EDataFlow,
            role: ERole,
            pwstrDefaultDeviceId: ?[*:0]const u16,
        ) callconv(.winapi) HRESULT,
        OnPropertyValueChanged: *const fn (
            self: *const IMMNotificationClient,
            pwstrDeviceId: ?[*:0]const u16,
            key: PROPERTYKEY,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn OnDeviceStateChanged(self: *const IMMNotificationClient, pwstrDeviceId: ?[*:0]const u16, dwNewState: u32) HRESULT {
        return self.vtable.OnDeviceStateChanged(self, pwstrDeviceId, dwNewState);
    }
    pub inline fn OnDeviceAdded(self: *const IMMNotificationClient, pwstrDeviceId: ?[*:0]const u16) HRESULT {
        return self.vtable.OnDeviceAdded(self, pwstrDeviceId);
    }
    pub inline fn OnDeviceRemoved(self: *const IMMNotificationClient, pwstrDeviceId: ?[*:0]const u16) HRESULT {
        return self.vtable.OnDeviceRemoved(self, pwstrDeviceId);
    }
    pub inline fn OnDefaultDeviceChanged(self: *const IMMNotificationClient, flow: EDataFlow, role: ERole, pwstrDefaultDeviceId: ?[*:0]const u16) HRESULT {
        return self.vtable.OnDefaultDeviceChanged(self, flow, role, pwstrDefaultDeviceId);
    }
    pub inline fn OnPropertyValueChanged(self: *const IMMNotificationClient, pwstrDeviceId: ?[*:0]const u16, key: PROPERTYKEY) HRESULT {
        return self.vtable.OnPropertyValueChanged(self, pwstrDeviceId, key);
    }
};
pub const IID_IMMDeviceCollection = &Guid.initString("0bd7a1be-7a1a-44db-8397-cc5392387b5e");
pub const IMMDeviceCollection = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetCount: *const fn (
            self: *const IMMDeviceCollection,
            pcDevices: ?*u32,
        ) callconv(.winapi) HRESULT,
        Item: *const fn (
            self: *const IMMDeviceCollection,
            nDevice: u32,
            ppDevice: ?*?*IMMDevice,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetCount(self: *const IMMDeviceCollection, pcDevices: ?*u32) HRESULT {
        return self.vtable.GetCount(self, pcDevices);
    }
    pub inline fn Item(self: *const IMMDeviceCollection, nDevice: u32, ppDevice: ?*?*IMMDevice) HRESULT {
        return self.vtable.Item(self, nDevice, ppDevice);
    }
};
pub const IID_IMMDeviceEnumerator = &Guid.initString("a95664d2-9614-4f35-a746-de8db63617e6");
pub const IMMDeviceEnumerator = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        EnumAudioEndpoints: *const fn (
            self: *const IMMDeviceEnumerator,
            dataFlow: EDataFlow,
            dwStateMask: u32,
            ppDevices: ?*?*IMMDeviceCollection,
        ) callconv(.winapi) HRESULT,
        GetDefaultAudioEndpoint: *const fn (
            self: *const IMMDeviceEnumerator,
            dataFlow: EDataFlow,
            role: ERole,
            ppEndpoint: ?*?*IMMDevice,
        ) callconv(.winapi) HRESULT,
        GetDevice: *const fn (
            self: *const IMMDeviceEnumerator,
            pwstrId: ?[*:0]const u16,
            ppDevice: ?*?*IMMDevice,
        ) callconv(.winapi) HRESULT,
        RegisterEndpointNotificationCallback: *const fn (
            self: *const IMMDeviceEnumerator,
            pClient: ?*IMMNotificationClient,
        ) callconv(.winapi) HRESULT,
        UnregisterEndpointNotificationCallback: *const fn (
            self: *const IMMDeviceEnumerator,
            pClient: ?*IMMNotificationClient,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn EnumAudioEndpoints(self: *const IMMDeviceEnumerator, dataFlow: EDataFlow, dwStateMask: u32, ppDevices: ?*?*IMMDeviceCollection) HRESULT {
        return self.vtable.EnumAudioEndpoints(self, dataFlow, dwStateMask, ppDevices);
    }
    pub inline fn GetDefaultAudioEndpoint(self: *const IMMDeviceEnumerator, dataFlow: EDataFlow, role: ERole, ppEndpoint: ?*?*IMMDevice) HRESULT {
        return self.vtable.GetDefaultAudioEndpoint(self, dataFlow, role, ppEndpoint);
    }
    pub inline fn GetDevice(self: *const IMMDeviceEnumerator, pwstrId: ?[*:0]const u16, ppDevice: ?*?*IMMDevice) HRESULT {
        return self.vtable.GetDevice(self, pwstrId, ppDevice);
    }
    pub inline fn RegisterEndpointNotificationCallback(self: *const IMMDeviceEnumerator, pClient: ?*IMMNotificationClient) HRESULT {
        return self.vtable.RegisterEndpointNotificationCallback(self, pClient);
    }
    pub inline fn UnregisterEndpointNotificationCallback(self: *const IMMDeviceEnumerator, pClient: ?*IMMNotificationClient) HRESULT {
        return self.vtable.UnregisterEndpointNotificationCallback(self, pClient);
    }
};
pub const IID_IMMEndpoint = &Guid.initString("1be09788-6894-4089-8586-9a2a6c265ac5");
pub const IMMEndpoint = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetDataFlow: *const fn (
            self: *const IMMEndpoint,
            pDataFlow: ?*EDataFlow,
        ) callconv(.winapi) HRESULT,
    };
    vtable: *const VTable,
    IUnknown: IUnknown,
    pub inline fn GetDataFlow(self: *const IMMEndpoint, pDataFlow: ?*EDataFlow) HRESULT {
        return self.vtable.GetDataFlow(self, pDataFlow);
    }
};
pub const AUDCLNT_STREAMFLAGS_CROSSPROCESS = 65536;
pub const AUDCLNT_STREAMFLAGS_LOOPBACK = 131072;
pub const AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 262144;
pub const AUDCLNT_STREAMFLAGS_NOPERSIST = 524288;
pub const AUDCLNT_STREAMFLAGS_RATEADJUST = 1048576;
pub const AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 134217728;
pub const AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 2147483648;
pub const AUDCLNT_SESSIONFLAGS_EXPIREWHENUNOWNED = 268435456;
pub const PKEY_Device_FriendlyName = PROPERTYKEY{ .fmtid = Guid.initString("a45c254e-df1c-4efd-8020-67d146a850e0"), .pid = 14 };
pub const CLSID_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = &Guid.initString("00000003-0000-0010-8000-00aa00389b71");
pub const SPEAKER_FRONT_LEFT = 1;
pub const SPEAKER_FRONT_RIGHT = 2;
pub const SPEAKER_FRONT_CENTER = 4;
pub const SPEAKER_LOW_FREQUENCY = 8;
pub const SPEAKER_BACK_LEFT = 16;
pub const SPEAKER_BACK_RIGHT = 32;
pub const SPEAKER_FRONT_LEFT_OF_CENTER = 64;
pub const SPEAKER_FRONT_RIGHT_OF_CENTER = 128;
pub const SPEAKER_BACK_CENTER = 256;
pub const SPEAKER_SIDE_LEFT = 512;
pub const SPEAKER_SIDE_RIGHT = 1024;
pub const SPEAKER_TOP_CENTER = 2048;
pub const SPEAKER_TOP_FRONT_LEFT = 4096;
pub const SPEAKER_TOP_FRONT_CENTER = 8192;
pub const SPEAKER_TOP_FRONT_RIGHT = 16384;
pub const SPEAKER_TOP_BACK_LEFT = 32768;
pub const SPEAKER_TOP_BACK_CENTER = 65536;
pub const SPEAKER_TOP_BACK_RIGHT = 131072;
pub const SPEAKER_RESERVED = @as(u32, 2147221504);
pub const SPEAKER_ALL = @as(u32, 2147483648);
pub const CLSID_KSDATAFORMAT_SUBTYPE_PCM = &Guid.initString("00000001-0000-0010-8000-00aa00389b71");
pub const INPLACE_S_TRUNCATED = 262560;
pub const PKEY_AudioEngine_DeviceFormat = PROPERTYKEY{ .fmtid = Guid.initString("f19f064d-082c-4e27-bc73-6882a1bb8e4c"), .pid = 0 };
pub const WAVE_FORMAT_EXTENSIBLE = 65534;
pub const STGC = packed struct(u32) {
    OVERWRITE: u1 = 0,
    ONLYIFCURRENT: u1 = 0,
    DANGEROUSLYCOMMITMERELYTODISKCACHE: u1 = 0,
    CONSOLIDATE: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const STGC_DEFAULT = STGC{};
pub const STGMOVE = enum(i32) {
    MOVE = 0,
    COPY = 1,
    SHALLOWCOPY = 2,
};
pub const STGM = packed struct(u32) {
    WRITE: u1 = 0,
    READWRITE: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    SHARE_EXCLUSIVE: u1 = 0,
    SHARE_DENY_WRITE: u1 = 0,
    SHARE_DENY_NONE: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    CREATE: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    TRANSACTED: u1 = 0,
    CONVERT: u1 = 0,
    PRIORITY: u1 = 0,
    _19: u1 = 0,
    NOSCRATCH: u1 = 0,
    NOSNAPSHOT: u1 = 0,
    DIRECT_SWMR: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    DELETEONRELEASE: u1 = 0,
    SIMPLE: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};
pub const STGM_READ = STGM{};
pub const DEVICE_STATE_ACTIVE = 1;
pub const AUDCLNT_E_NOT_INITIALIZED = -2004287487;
pub const AUDCLNT_E_ALREADY_INITIALIZED = -2004287486;
pub const AUDCLNT_E_WRONG_ENDPOINT_TYPE = -2004287485;
pub const AUDCLNT_E_DEVICE_INVALIDATED = -2004287484;
pub const AUDCLNT_E_NOT_STOPPED = -2004287483;
pub const AUDCLNT_E_BUFFER_TOO_LARGE = -2004287482;
pub const AUDCLNT_E_OUT_OF_ORDER = -2004287481;
pub const AUDCLNT_E_UNSUPPORTED_FORMAT = -2004287480;
pub const AUDCLNT_E_INVALID_SIZE = -2004287479;
pub const AUDCLNT_E_DEVICE_IN_USE = -2004287478;
pub const AUDCLNT_E_BUFFER_OPERATION_PENDING = -2004287477;
pub const AUDCLNT_E_THREAD_NOT_REGISTERED = -2004287476;
pub const AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED = -2004287474;
pub const AUDCLNT_E_ENDPOINT_CREATE_FAILED = -2004287473;
pub const AUDCLNT_E_SERVICE_NOT_RUNNING = -2004287472;
pub const AUDCLNT_E_EVENTHANDLE_NOT_EXPECTED = -2004287471;
pub const AUDCLNT_E_EXCLUSIVE_MODE_ONLY = -2004287470;
pub const AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL = -2004287469;
pub const AUDCLNT_E_EVENTHANDLE_NOT_SET = -2004287468;
pub const AUDCLNT_E_INCORRECT_BUFFER_SIZE = -2004287467;
pub const AUDCLNT_E_BUFFER_SIZE_ERROR = -2004287466;
pub const AUDCLNT_E_CPUUSAGE_EXCEEDED = -2004287465;
pub const AUDCLNT_E_BUFFER_ERROR = -2004287464;
pub const AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED = -2004287463;
pub const AUDCLNT_E_INVALID_DEVICE_PERIOD = -2004287456;
pub const AUDCLNT_E_INVALID_STREAM_FLAG = -2004287455;
pub const AUDCLNT_E_ENDPOINT_OFFLOAD_NOT_CAPABLE = -2004287454;
pub const AUDCLNT_E_OUT_OF_OFFLOAD_RESOURCES = -2004287453;
pub const AUDCLNT_E_OFFLOAD_MODE_ONLY = -2004287452;
pub const AUDCLNT_E_NONOFFLOAD_MODE_ONLY = -2004287451;
pub const AUDCLNT_E_RESOURCES_INVALIDATED = -2004287450;
pub const AUDCLNT_E_RAW_MODE_UNSUPPORTED = -2004287449;
pub const AUDCLNT_E_ENGINE_PERIODICITY_LOCKED = -2004287448;
pub const AUDCLNT_E_ENGINE_FORMAT_LOCKED = -2004287447;
pub const AUDCLNT_E_HEADTRACKING_ENABLED = -2004287440;
pub const AUDCLNT_E_HEADTRACKING_UNSUPPORTED = -2004287424;
pub const AUDCLNT_E_EFFECT_NOT_AVAILABLE = -2004287423;
pub const AUDCLNT_E_EFFECT_STATE_READ_ONLY = -2004287422;

pub extern "user32" fn GetDpiForWindow(
    hwnd: ?HWND,
) callconv(.winapi) u32;

pub fn dpiFromHwnd(hwnd: HWND) u32 {
    const value = GetDpiForWindow(hwnd);
    if (value == 0) std.debug.panic(
        "GetDpiForWindow failed, error={}",
        .{GetLastError()},
    );
    return value;
}

fn getDpiFactor(dpi: u32) f32 {
    std.debug.assert(dpi >= 96);
    return @as(f32, @floatFromInt(dpi)) / 96.0;
}

pub fn pxFromPt(comptime T: type, value: T, dpi: u32) T {
    switch (@typeInfo(T)) {
        .float => return value * getDpiFactor(dpi),
        .int => return @intFromFloat(@round(@as(f32, @floatFromInt(value)) * getDpiFactor(dpi))),
        else => @compileError("scaleDpi does not support type " ++ @typeName(@TypeOf(value))),
    }
}

pub fn ptFromPx(comptime T: type, value: T, dpi: u32) T {
    switch (@typeInfo(T)) {
        .float => return value / getDpiFactor(dpi),
        .int => return @intFromFloat(@round(@as(f32, @floatFromInt(value)) / getDpiFactor(dpi))),
        else => @compileError("scaleDpi does not support type " ++ @typeName(@TypeOf(value))),
    }
}

pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: ?HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    lpszName: ?[*:0]const u16,
    lpszClass: ?[*:0]const u16,
    dwExStyle: u32,
};

pub fn loword(value: anytype) u16 {
    switch (@typeInfo(@TypeOf(value))) {
        .int => |int| switch (int.signedness) {
            .signed => return loword(@as(@Int(.unsigned, int.bits), @bitCast(value))),
            .unsigned => return if (int.bits <= 16) value else @intCast(0xffff & value),
        },
        else => {},
    }
    @compileError("unsupported type " ++ @typeName(@TypeOf(value)));
}
pub fn hiword(value: anytype) u16 {
    switch (@typeInfo(@TypeOf(value))) {
        .int => |int| switch (int.signedness) {
            .signed => return hiword(@as(@Int(.unsigned, int.bits), @bitCast(value))),
            .unsigned => return @intCast(0xffff & (value >> 16)),
        },
        else => {},
    }
    @compileError("unsupported type " ++ @typeName(@TypeOf(value)));
}

fn xFromLparam(lparam: LPARAM) i16 {
    return @bitCast(loword(lparam));
}
fn yFromLparam(lparam: LPARAM) i16 {
    return @bitCast(hiword(lparam));
}
pub fn pointFromLparam(lparam: LPARAM) POINT {
    return POINT{ .x = xFromLparam(lparam), .y = yFromLparam(lparam) };
}
