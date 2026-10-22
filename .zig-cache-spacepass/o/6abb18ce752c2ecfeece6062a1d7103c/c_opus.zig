const __root = @This();
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;

pub const __builtin_va_list = [*c]u8;
pub const va_list = __builtin_va_list;
pub const __gnuc_va_list = __builtin_va_list;
pub const __int8_t = i8;
pub const __uint8_t = u8;
pub const __int16_t = c_short;
pub const __uint16_t = c_ushort;
pub const __int32_t = c_int;
pub const __uint32_t = c_uint;
pub const __int64_t = c_longlong;
pub const __uint64_t = c_ulonglong;
pub const __darwin_intptr_t = c_long;
pub const __darwin_natural_t = c_uint;
pub const __darwin_ct_rune_t = c_int;
pub const __mbstate_t = extern union {
    __mbstate8: [128]u8,
    _mbstateL: c_longlong,
};
pub const __darwin_mbstate_t = __mbstate_t;
pub const __darwin_ptrdiff_t = c_long;
pub const __darwin_size_t = c_ulong;
pub const __darwin_va_list = __builtin_va_list;
pub const __darwin_wchar_t = c_int;
pub const __darwin_rune_t = __darwin_wchar_t;
pub const __darwin_wint_t = __darwin_ct_rune_t;
pub const __darwin_clock_t = c_ulong;
pub const __darwin_socklen_t = __uint32_t;
pub const __darwin_ssize_t = c_long;
pub const __darwin_time_t = c_long;
pub const __darwin_blkcnt_t = __int64_t;
pub const __darwin_blksize_t = __int32_t;
pub const __darwin_dev_t = __int32_t;
pub const __darwin_fsblkcnt_t = c_uint;
pub const __darwin_fsfilcnt_t = c_uint;
pub const __darwin_gid_t = __uint32_t;
pub const __darwin_id_t = __uint32_t;
pub const __darwin_ino64_t = __uint64_t;
pub const __darwin_ino_t = __darwin_ino64_t;
pub const __darwin_mach_port_name_t = __darwin_natural_t;
pub const __darwin_mach_port_t = __darwin_mach_port_name_t;
pub const __darwin_mode_t = __uint16_t;
pub const __darwin_off_t = __int64_t;
pub const __darwin_pid_t = __int32_t;
pub const __darwin_sigset_t = __uint32_t;
pub const __darwin_suseconds_t = __int32_t;
pub const __darwin_uid_t = __uint32_t;
pub const __darwin_useconds_t = __uint32_t;
pub const __darwin_uuid_t = [16]u8;
pub const __darwin_uuid_string_t = [37]u8;
pub const struct___darwin_pthread_handler_rec = extern struct {
    __routine: ?*const fn (?*anyopaque) callconv(.c) void = null,
    __arg: ?*anyopaque = null,
    __next: [*c]struct___darwin_pthread_handler_rec = null,
};
pub const struct__opaque_pthread_attr_t = extern struct {
    __sig: c_long = 0,
    __opaque: [56]u8 = @import("std").mem.zeroes([56]u8),
};
pub const struct__opaque_pthread_cond_t = extern struct {
    __sig: c_long = 0,
    __opaque: [40]u8 = @import("std").mem.zeroes([40]u8),
};
pub const struct__opaque_pthread_condattr_t = extern struct {
    __sig: c_long = 0,
    __opaque: [8]u8 = @import("std").mem.zeroes([8]u8),
};
pub const struct__opaque_pthread_mutex_t = extern struct {
    __sig: c_long = 0,
    __opaque: [56]u8 = @import("std").mem.zeroes([56]u8),
};
pub const struct__opaque_pthread_mutexattr_t = extern struct {
    __sig: c_long = 0,
    __opaque: [8]u8 = @import("std").mem.zeroes([8]u8),
};
pub const struct__opaque_pthread_once_t = extern struct {
    __sig: c_long = 0,
    __opaque: [8]u8 = @import("std").mem.zeroes([8]u8),
};
pub const struct__opaque_pthread_rwlock_t = extern struct {
    __sig: c_long = 0,
    __opaque: [192]u8 = @import("std").mem.zeroes([192]u8),
};
pub const struct__opaque_pthread_rwlockattr_t = extern struct {
    __sig: c_long = 0,
    __opaque: [16]u8 = @import("std").mem.zeroes([16]u8),
};
pub const struct__opaque_pthread_t = extern struct {
    __sig: c_long = 0,
    __cleanup_stack: [*c]struct___darwin_pthread_handler_rec = null,
    __opaque: [8176]u8 = @import("std").mem.zeroes([8176]u8),
};
pub const __darwin_pthread_attr_t = struct__opaque_pthread_attr_t;
pub const __darwin_pthread_cond_t = struct__opaque_pthread_cond_t;
pub const __darwin_pthread_condattr_t = struct__opaque_pthread_condattr_t;
pub const __darwin_pthread_key_t = c_ulong;
pub const __darwin_pthread_mutex_t = struct__opaque_pthread_mutex_t;
pub const __darwin_pthread_mutexattr_t = struct__opaque_pthread_mutexattr_t;
pub const __darwin_pthread_once_t = struct__opaque_pthread_once_t;
pub const __darwin_pthread_rwlock_t = struct__opaque_pthread_rwlock_t;
pub const __darwin_pthread_rwlockattr_t = struct__opaque_pthread_rwlockattr_t;
pub const __darwin_pthread_t = [*c]struct__opaque_pthread_t;
pub const __darwin_nl_item = c_int;
pub const __darwin_wctrans_t = c_int;
pub const __darwin_wctype_t = __uint32_t;
pub const u_int8_t = u8;
pub const u_int16_t = c_ushort;
pub const u_int32_t = c_uint;
pub const u_int64_t = c_ulonglong;
pub const register_t = i64;
pub const user_addr_t = u_int64_t;
pub const user_size_t = u_int64_t;
pub const user_ssize_t = i64;
pub const user_long_t = i64;
pub const user_ulong_t = u_int64_t;
pub const user_time_t = i64;
pub const user_off_t = i64;
pub const syscall_arg_t = u_int64_t;
pub extern fn renameat(c_int, [*c]const u8, c_int, [*c]const u8) c_int;
pub extern fn renamex_np([*c]const u8, [*c]const u8, c_uint) c_int;
pub extern fn renameatx_np(c_int, [*c]const u8, c_int, [*c]const u8, c_uint) c_int;
pub const fpos_t = __darwin_off_t;
pub const struct___sbuf = extern struct {
    _base: [*c]u8 = null,
    _size: c_int = 0,
};
pub const struct___sFILEX = opaque {};
pub const struct___sFILE = extern struct {
    _p: [*c]u8 = null,
    _r: c_int = 0,
    _w: c_int = 0,
    _flags: c_short = 0,
    _file: c_short = 0,
    _bf: struct___sbuf = @import("std").mem.zeroes(struct___sbuf),
    _lbfsize: c_int = 0,
    _cookie: ?*anyopaque = null,
    _close: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
    _read: ?*const fn (?*anyopaque, [*c]u8, c_int) callconv(.c) c_int = null,
    _seek: ?*const fn (?*anyopaque, fpos_t, c_int) callconv(.c) fpos_t = null,
    _write: ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) c_int = null,
    _ub: struct___sbuf = @import("std").mem.zeroes(struct___sbuf),
    _extra: ?*struct___sFILEX = null,
    _ur: c_int = 0,
    _ubuf: [3]u8 = @import("std").mem.zeroes([3]u8),
    _nbuf: [1]u8 = @import("std").mem.zeroes([1]u8),
    _lb: struct___sbuf = @import("std").mem.zeroes(struct___sbuf),
    _blksize: c_int = 0,
    _offset: fpos_t = 0,
    pub const clearerr = __root.clearerr;
    pub const fclose = __root.fclose;
    pub const feof = __root.feof;
    pub const ferror = __root.ferror;
    pub const fflush = __root.fflush;
    pub const fgetc = __root.fgetc;
    pub const fgetpos = __root.fgetpos;
    pub const fprintf = __root.fprintf;
    pub const fscanf = __root.fscanf;
    pub const fseek = __root.fseek;
    pub const fsetpos = __root.fsetpos;
    pub const ftell = __root.ftell;
    pub const getc = __root.getc;
    pub const rewind = __root.rewind;
    pub const setbuf = __root.setbuf;
    pub const setvbuf = __root.setvbuf;
    pub const vfprintf = __root.vfprintf;
    pub const fileno = __root.fileno;
    pub const pclose = __root.pclose;
    pub const __srget = __root.__srget;
    pub const __svfscanf = __root.__svfscanf;
    pub const flockfile = __root.flockfile;
    pub const ftrylockfile = __root.ftrylockfile;
    pub const funlockfile = __root.funlockfile;
    pub const getc_unlocked = __root.getc_unlocked;
    pub const getw = __root.getw;
    pub const fseeko = __root.fseeko;
    pub const ftello = __root.ftello;
    pub const vfscanf = __root.vfscanf;
    pub const fgetln = __root.fgetln;
    pub const fpurge = __root.fpurge;
    pub const setbuffer = __root.setbuffer;
    pub const setlinebuf = __root.setlinebuf;
    pub const srget = __root.__srget;
    pub const svfscanf = __root.__svfscanf;
    pub const unlocked = __root.getc_unlocked;
};
pub const FILE = struct___sFILE;
pub extern var __stdinp: [*c]FILE;
pub extern var __stdoutp: [*c]FILE;
pub extern var __stderrp: [*c]FILE;
pub extern fn clearerr([*c]FILE) void;
pub extern fn fclose([*c]FILE) c_int;
pub extern fn feof([*c]FILE) c_int;
pub extern fn ferror([*c]FILE) c_int;
pub extern fn fflush([*c]FILE) c_int;
pub extern fn fgetc([*c]FILE) c_int;
pub extern fn fgetpos(noalias [*c]FILE, [*c]fpos_t) c_int;
pub extern fn fgets(noalias [*c]u8, c_int, [*c]FILE) [*c]u8;
pub extern fn fopen(noalias __filename: [*c]const u8, noalias __mode: [*c]const u8) [*c]FILE;
pub extern fn fprintf(noalias [*c]FILE, noalias [*c]const u8, ...) c_int;
pub extern fn fputc(c_int, [*c]FILE) c_int;
pub extern fn fputs(noalias [*c]const u8, noalias [*c]FILE) c_int;
pub extern fn fread(noalias __ptr: ?*anyopaque, __size: usize, __nitems: usize, noalias __stream: [*c]FILE) usize;
pub extern fn freopen(noalias [*c]const u8, noalias [*c]const u8, noalias [*c]FILE) [*c]FILE;
pub extern fn fscanf(noalias [*c]FILE, noalias [*c]const u8, ...) c_int;
pub extern fn fseek([*c]FILE, c_long, c_int) c_int;
pub extern fn fsetpos([*c]FILE, [*c]const fpos_t) c_int;
pub extern fn ftell([*c]FILE) c_long;
pub extern fn fwrite(noalias __ptr: ?*const anyopaque, __size: usize, __nitems: usize, noalias __stream: [*c]FILE) usize;
pub extern fn getc([*c]FILE) c_int;
pub extern fn getchar() c_int;
pub extern fn gets([*c]u8) [*c]u8;
pub extern fn perror([*c]const u8) void;
pub extern fn printf(noalias [*c]const u8, ...) c_int;
pub extern fn putc(c_int, [*c]FILE) c_int;
pub extern fn putchar(c_int) c_int;
pub extern fn puts([*c]const u8) c_int;
pub extern fn remove([*c]const u8) c_int;
pub extern fn rename(__old: [*c]const u8, __new: [*c]const u8) c_int;
pub extern fn rewind([*c]FILE) void;
pub extern fn scanf(noalias [*c]const u8, ...) c_int;
pub extern fn setbuf(noalias [*c]FILE, noalias [*c]u8) void;
pub extern fn setvbuf(noalias [*c]FILE, noalias [*c]u8, c_int, usize) c_int;
pub extern fn sprintf(noalias [*c]u8, noalias [*c]const u8, ...) c_int;
pub extern fn sscanf(noalias [*c]const u8, noalias [*c]const u8, ...) c_int;
pub extern fn tmpfile() [*c]FILE;
pub extern fn tmpnam([*c]u8) [*c]u8;
pub extern fn ungetc(c_int, [*c]FILE) c_int;
pub extern fn vfprintf(noalias [*c]FILE, noalias [*c]const u8, va_list) c_int;
pub extern fn vprintf(noalias [*c]const u8, va_list) c_int;
pub extern fn vsprintf(noalias [*c]u8, noalias [*c]const u8, va_list) c_int;
pub extern fn ctermid([*c]u8) [*c]u8;
pub extern fn fdopen(c_int, [*c]const u8) [*c]FILE;
pub extern fn fileno([*c]FILE) c_int;
pub extern fn pclose([*c]FILE) c_int;
pub extern fn popen([*c]const u8, [*c]const u8) [*c]FILE;
pub extern fn __srget([*c]FILE) c_int;
pub extern fn __svfscanf([*c]FILE, [*c]const u8, va_list) c_int;
pub extern fn __swbuf(c_int, [*c]FILE) c_int;
pub inline fn __sputc(arg__c: c_int, arg__p: [*c]FILE) c_int {
    var _c = arg__c;
    _ = &_c;
    var _p = arg__p;
    _ = &_p;
    if (((blk: {
        const ref = &_p.*._w;
        ref.* -= 1;
        break :blk ref.*;
    }) >= @as(c_int, 0)) or ((_p.*._w >= _p.*._lbfsize) and (@as(c_int, @as(u8, @bitCast(@as(i8, @truncate(_c))))) != @as(c_int, '\n')))) return blk: {
        const tmp = @as(u8, @bitCast(@as(i8, @truncate(_c))));
        (blk_1: {
            const ref = &_p.*._p;
            const tmp_2 = ref.*;
            ref.* += 1;
            break :blk_1 tmp_2;
        }).* = tmp;
        break :blk tmp;
    } else return __swbuf(_c, _p);
}
pub extern fn flockfile([*c]FILE) void;
pub extern fn ftrylockfile([*c]FILE) c_int;
pub extern fn funlockfile([*c]FILE) void;
pub extern fn getc_unlocked([*c]FILE) c_int;
pub extern fn getchar_unlocked() c_int;
pub extern fn putc_unlocked(c_int, [*c]FILE) c_int;
pub extern fn putchar_unlocked(c_int) c_int;
pub extern fn getw([*c]FILE) c_int;
pub extern fn putw(c_int, [*c]FILE) c_int;
pub extern fn tempnam(__dir: [*c]const u8, __prefix: [*c]const u8) [*c]u8;
pub const off_t = __darwin_off_t;
pub extern fn fseeko(__stream: [*c]FILE, __offset: off_t, __whence: c_int) c_int;
pub extern fn ftello(__stream: [*c]FILE) off_t;
pub extern fn snprintf(noalias __str: [*c]u8, __size: usize, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vfscanf(noalias __stream: [*c]FILE, noalias __format: [*c]const u8, va_list) c_int;
pub extern fn vscanf(noalias __format: [*c]const u8, va_list) c_int;
pub extern fn vsnprintf(noalias __str: [*c]u8, __size: usize, noalias __format: [*c]const u8, va_list) c_int;
pub extern fn vsscanf(noalias __str: [*c]const u8, noalias __format: [*c]const u8, va_list) c_int;
pub extern fn dprintf(c_int, noalias [*c]const u8, ...) c_int;
pub extern fn vdprintf(c_int, noalias [*c]const u8, va_list) c_int;
pub extern fn getdelim(noalias __linep: [*c][*c]u8, noalias __linecapp: [*c]usize, __delimiter: c_int, noalias __stream: [*c]FILE) isize;
pub extern fn getline(noalias __linep: [*c][*c]u8, noalias __linecapp: [*c]usize, noalias __stream: [*c]FILE) isize;
pub extern fn fmemopen(noalias __buf: ?*anyopaque, __size: usize, noalias __mode: [*c]const u8) [*c]FILE;
pub extern fn open_memstream(__bufp: [*c][*c]u8, __sizep: [*c]usize) [*c]FILE;
pub extern const sys_nerr: c_int;
pub const sys_errlist: [*c]const [*c]const u8 = @extern([*c]const [*c]const u8, .{
    .name = "sys_errlist",
});
pub extern fn asprintf(noalias [*c][*c]u8, noalias [*c]const u8, ...) c_int;
pub extern fn ctermid_r([*c]u8) [*c]u8;
pub extern fn fgetln([*c]FILE, [*c]usize) [*c]u8;
pub extern fn fmtcheck([*c]const u8, [*c]const u8) [*c]const u8;
pub extern fn fpurge([*c]FILE) c_int;
pub extern fn setbuffer([*c]FILE, [*c]u8, c_int) void;
pub extern fn setlinebuf([*c]FILE) c_int;
pub extern fn vasprintf(noalias [*c][*c]u8, noalias [*c]const u8, va_list) c_int;
pub extern fn funopen(?*const anyopaque, ?*const fn (?*anyopaque, [*c]u8, c_int) callconv(.c) c_int, ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) c_int, ?*const fn (?*anyopaque, fpos_t, c_int) callconv(.c) fpos_t, ?*const fn (?*anyopaque) callconv(.c) c_int) [*c]FILE;
pub extern fn __sprintf_chk(noalias [*c]u8, c_int, usize, noalias [*c]const u8, ...) c_int;
pub extern fn __snprintf_chk(noalias [*c]u8, usize, c_int, usize, noalias [*c]const u8, ...) c_int;
pub extern fn __vsprintf_chk(noalias [*c]u8, c_int, usize, noalias [*c]const u8, va_list) c_int;
pub extern fn __vsnprintf_chk(noalias [*c]u8, usize, c_int, usize, noalias [*c]const u8, va_list) c_int;
pub const ptrdiff_t = c_long;
pub const wchar_t = c_int;
pub const max_align_t = extern struct {
    __aro_max_align_ll: c_longlong = 0,
    __aro_max_align_ld: c_longdouble = 0,
};
pub const int_least8_t = i8;
pub const int_least16_t = i16;
pub const int_least32_t = i32;
pub const int_least64_t = i64;
pub const uint_least8_t = u8;
pub const uint_least16_t = u16;
pub const uint_least32_t = u32;
pub const uint_least64_t = u64;
pub const int_fast8_t = i8;
pub const int_fast16_t = i16;
pub const int_fast32_t = i32;
pub const int_fast64_t = i64;
pub const uint_fast8_t = u8;
pub const uint_fast16_t = u16;
pub const uint_fast32_t = u32;
pub const uint_fast64_t = u64;
pub const intmax_t = c_long;
pub const uintmax_t = c_ulong;
pub fn _OSSwapInt16(arg__data: u16) callconv(.c) u16 {
    var _data = arg__data;
    _ = &_data;
    return @bitCast(@as(c_short, @truncate((@as(c_int, _data) << @intCast(8)) | (@as(c_int, _data) >> @intCast(8)))));
}
pub fn _OSSwapInt32(arg__data: u32) callconv(.c) u32 {
    var _data = arg__data;
    _ = &_data;
    _data = (((_data ^ ((_data >> @intCast(16)) | (_data << @intCast(16)))) & @as(c_uint, 4278255615)) >> @intCast(8)) ^ ((_data >> @intCast(8)) | (_data << @intCast(24)));
    return _data;
}
pub fn _OSSwapInt64(arg__data: u64) callconv(.c) u64 {
    var _data = arg__data;
    _ = &_data;
    const union_unnamed_1 = extern union {
        _ull: u64,
        _ul: [2]u32,
    };
    _ = &union_unnamed_1;
    var _u: union_unnamed_1 = undefined;
    _ = &_u;
    _u._ul[@as(c_int, 0)] = @truncate(_data >> @intCast(32));
    _u._ul[@as(c_int, 1)] = @truncate(_data & @as(u64, 4294967295));
    _u._ul[@as(c_int, 0)] = _OSSwapInt32(_u._ul[@as(c_int, 0)]);
    _u._ul[@as(c_int, 1)] = _OSSwapInt32(_u._ul[@as(c_int, 1)]);
    return _u._ull;
}
pub const struct__OSUnalignedU16 = extern struct {
    __val: u16 align(1) = 0,
};
pub const struct__OSUnalignedU32 = extern struct {
    __val: u32 align(1) = 0,
};
pub const struct__OSUnalignedU64 = extern struct {
    __val: u64 align(1) = 0,
};
pub fn OSReadSwapInt16(arg__base: ?*const volatile anyopaque, arg__offset: usize) callconv(.c) u16 {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    return _OSSwapInt16(@as([*c]struct__OSUnalignedU16, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val);
}
pub fn OSReadSwapInt32(arg__base: ?*const volatile anyopaque, arg__offset: usize) callconv(.c) u32 {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    return _OSSwapInt32(@as([*c]struct__OSUnalignedU32, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val);
}
pub fn OSReadSwapInt64(arg__base: ?*const volatile anyopaque, arg__offset: usize) callconv(.c) u64 {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    return _OSSwapInt64(@as([*c]struct__OSUnalignedU64, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val);
}
pub fn OSWriteSwapInt16(arg__base: ?*volatile anyopaque, arg__offset: usize, arg__data: u16) callconv(.c) void {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    var _data = arg__data;
    _ = &_data;
    @as([*c]struct__OSUnalignedU16, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val = _OSSwapInt16(_data);
}
pub fn OSWriteSwapInt32(arg__base: ?*volatile anyopaque, arg__offset: usize, arg__data: u32) callconv(.c) void {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    var _data = arg__data;
    _ = &_data;
    @as([*c]struct__OSUnalignedU32, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val = _OSSwapInt32(_data);
}
pub fn OSWriteSwapInt64(arg__base: ?*volatile anyopaque, arg__offset: usize, arg__data: u64) callconv(.c) void {
    var _base = arg__base;
    _ = &_base;
    var _offset = arg__offset;
    _ = &_offset;
    var _data = arg__data;
    _ = &_data;
    @as([*c]struct__OSUnalignedU64, @ptrFromInt(@as(usize, @intCast(@intFromPtr(_base))) +% _offset)).*.__val = _OSSwapInt64(_data);
}
pub const u_char = u8;
pub const u_short = c_ushort;
pub const u_int = c_uint;
pub const u_long = c_ulong;
pub const ushort = c_ushort;
pub const uint = c_uint;
pub const u_quad_t = u_int64_t;
pub const quad_t = i64;
pub const qaddr_t = [*c]quad_t;
pub const caddr_t = [*c]u8;
pub const daddr_t = i32;
pub const dev_t = __darwin_dev_t;
pub const fixpt_t = u_int32_t;
pub const blkcnt_t = __darwin_blkcnt_t;
pub const blksize_t = __darwin_blksize_t;
pub const gid_t = __darwin_gid_t;
pub const in_addr_t = __uint32_t;
pub const in_port_t = __uint16_t;
pub const ino_t = __darwin_ino_t;
pub const ino64_t = __darwin_ino64_t;
pub const key_t = __int32_t;
pub const mode_t = __darwin_mode_t;
pub const nlink_t = __uint16_t;
pub const id_t = __darwin_id_t;
pub const pid_t = __darwin_pid_t;
pub const segsz_t = i32;
pub const swblk_t = i32;
pub const uid_t = __darwin_uid_t;
pub const clock_t = __darwin_clock_t;
pub const time_t = __darwin_time_t;
pub const useconds_t = __darwin_useconds_t;
pub const suseconds_t = __darwin_suseconds_t;
pub const rsize_t = __darwin_size_t;
pub const errno_t = c_int;
pub const struct_fd_set = extern struct {
    fds_bits: [32]__int32_t = @import("std").mem.zeroes([32]__int32_t),
};
pub const fd_set = struct_fd_set;
pub extern fn __darwin_check_fd_set_overflow(c_int, ?*const anyopaque, c_int) c_int;
pub inline fn __darwin_check_fd_set(arg__a: c_int, arg__b: ?*const anyopaque) c_int {
    var _a = arg__a;
    _ = &_a;
    var _b = arg__b;
    _ = &_b;
    if (@as(usize, @intCast(@intFromPtr(&__darwin_check_fd_set_overflow))) != @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) {
        return __darwin_check_fd_set_overflow(_a, _b, 0);
    } else {
        return 1;
    }
}
pub inline fn __darwin_fd_isset(arg__fd: c_int, arg__p: [*c]const struct_fd_set) c_int {
    var _fd = arg__fd;
    _ = &_fd;
    var _p = arg__p;
    _ = &_p;
    if (__darwin_check_fd_set(_fd, @ptrCast(@alignCast(_p))) != 0) {
        return _p.*.fds_bits[@as(c_ulong, @bitCast(@as(c_long, _fd))) / (@sizeOf(__int32_t) *% @as(c_ulong, 8))] & @as(__int32_t, @bitCast(@as(c_uint, @truncate(@as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))) << @intCast(@as(c_ulong, @bitCast(@as(c_long, _fd))) % (@sizeOf(__int32_t) *% @as(c_ulong, 8)))))));
    }
    return 0;
}
pub inline fn __darwin_fd_set(arg__fd: c_int, _p: [*c]struct_fd_set) void {
    var _fd = arg__fd;
    _ = &_fd;
    _ = &_p;
    if (__darwin_check_fd_set(_fd, @ptrCast(@alignCast(_p))) != 0) {
        _p.*.fds_bits[@as(c_ulong, @bitCast(@as(c_long, _fd))) / (@sizeOf(__int32_t) *% @as(c_ulong, 8))] |= @as(__int32_t, @bitCast(@as(c_uint, @truncate(@as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))) << @intCast(@as(c_ulong, @bitCast(@as(c_long, _fd))) % (@sizeOf(__int32_t) *% @as(c_ulong, 8)))))));
    }
}
pub inline fn __darwin_fd_clr(arg__fd: c_int, _p: [*c]struct_fd_set) void {
    var _fd = arg__fd;
    _ = &_fd;
    _ = &_p;
    if (__darwin_check_fd_set(_fd, @ptrCast(@alignCast(_p))) != 0) {
        _p.*.fds_bits[@as(c_ulong, @bitCast(@as(c_long, _fd))) / (@sizeOf(__int32_t) *% @as(c_ulong, 8))] &= ~@as(__int32_t, @bitCast(@as(c_uint, @truncate(@as(c_ulong, @bitCast(@as(c_long, @as(c_int, 1)))) << @intCast(@as(c_ulong, @bitCast(@as(c_long, _fd))) % (@sizeOf(__int32_t) *% @as(c_ulong, 8)))))));
    }
}
pub const fd_mask = __int32_t;
pub const pthread_attr_t = __darwin_pthread_attr_t;
pub const pthread_cond_t = __darwin_pthread_cond_t;
pub const pthread_condattr_t = __darwin_pthread_condattr_t;
pub const pthread_mutex_t = __darwin_pthread_mutex_t;
pub const pthread_mutexattr_t = __darwin_pthread_mutexattr_t;
pub const pthread_once_t = __darwin_pthread_once_t;
pub const pthread_rwlock_t = __darwin_pthread_rwlock_t;
pub const pthread_rwlockattr_t = __darwin_pthread_rwlockattr_t;
pub const pthread_t = __darwin_pthread_t;
pub const pthread_key_t = __darwin_pthread_key_t;
pub const fsblkcnt_t = __darwin_fsblkcnt_t;
pub const fsfilcnt_t = __darwin_fsfilcnt_t;
pub const ogg_int16_t = i16;
pub const ogg_uint16_t = u_int16_t;
pub const ogg_int32_t = i32;
pub const ogg_uint32_t = u_int32_t;
pub const ogg_int64_t = i64;
pub const ogg_uint64_t = u_int64_t;
pub const ogg_iovec_t = extern struct {
    iov_base: ?*anyopaque = null,
    iov_len: usize = 0,
};
pub const oggpack_buffer = extern struct {
    endbyte: c_long = 0,
    endbit: c_int = 0,
    buffer: [*c]u8 = null,
    ptr: [*c]u8 = null,
    storage: c_long = 0,
    pub const oggpack_writeinit = __root.oggpack_writeinit;
    pub const oggpack_writecheck = __root.oggpack_writecheck;
    pub const oggpack_writetrunc = __root.oggpack_writetrunc;
    pub const oggpack_writealign = __root.oggpack_writealign;
    pub const oggpack_writecopy = __root.oggpack_writecopy;
    pub const oggpack_reset = __root.oggpack_reset;
    pub const oggpack_writeclear = __root.oggpack_writeclear;
    pub const oggpack_readinit = __root.oggpack_readinit;
    pub const oggpack_write = __root.oggpack_write;
    pub const oggpack_look = __root.oggpack_look;
    pub const oggpack_look1 = __root.oggpack_look1;
    pub const oggpack_adv = __root.oggpack_adv;
    pub const oggpack_adv1 = __root.oggpack_adv1;
    pub const oggpack_read = __root.oggpack_read;
    pub const oggpack_read1 = __root.oggpack_read1;
    pub const oggpack_bytes = __root.oggpack_bytes;
    pub const oggpack_bits = __root.oggpack_bits;
    pub const oggpack_get_buffer = __root.oggpack_get_buffer;
    pub const oggpackB_writeinit = __root.oggpackB_writeinit;
    pub const oggpackB_writecheck = __root.oggpackB_writecheck;
    pub const oggpackB_writetrunc = __root.oggpackB_writetrunc;
    pub const oggpackB_writealign = __root.oggpackB_writealign;
    pub const oggpackB_writecopy = __root.oggpackB_writecopy;
    pub const oggpackB_reset = __root.oggpackB_reset;
    pub const oggpackB_writeclear = __root.oggpackB_writeclear;
    pub const oggpackB_readinit = __root.oggpackB_readinit;
    pub const oggpackB_write = __root.oggpackB_write;
    pub const oggpackB_look = __root.oggpackB_look;
    pub const oggpackB_look1 = __root.oggpackB_look1;
    pub const oggpackB_adv = __root.oggpackB_adv;
    pub const oggpackB_adv1 = __root.oggpackB_adv1;
    pub const oggpackB_read = __root.oggpackB_read;
    pub const oggpackB_read1 = __root.oggpackB_read1;
    pub const oggpackB_bytes = __root.oggpackB_bytes;
    pub const oggpackB_bits = __root.oggpackB_bits;
    pub const oggpackB_get_buffer = __root.oggpackB_get_buffer;
    pub const writeinit = __root.oggpack_writeinit;
    pub const writecheck = __root.oggpack_writecheck;
    pub const writetrunc = __root.oggpack_writetrunc;
    pub const writealign = __root.oggpack_writealign;
    pub const writecopy = __root.oggpack_writecopy;
    pub const reset = __root.oggpack_reset;
    pub const writeclear = __root.oggpack_writeclear;
    pub const readinit = __root.oggpack_readinit;
    pub const write = __root.oggpack_write;
    pub const look = __root.oggpack_look;
    pub const look1 = __root.oggpack_look1;
    pub const adv = __root.oggpack_adv;
    pub const adv1 = __root.oggpack_adv1;
    pub const read = __root.oggpack_read;
    pub const read1 = __root.oggpack_read1;
    pub const bytes = __root.oggpack_bytes;
    pub const bits = __root.oggpack_bits;
};
pub const ogg_page = extern struct {
    header: [*c]u8 = null,
    header_len: c_long = 0,
    body: [*c]u8 = null,
    body_len: c_long = 0,
    pub const ogg_page_checksum_set = __root.ogg_page_checksum_set;
    pub const ogg_page_version = __root.ogg_page_version;
    pub const ogg_page_continued = __root.ogg_page_continued;
    pub const ogg_page_bos = __root.ogg_page_bos;
    pub const ogg_page_eos = __root.ogg_page_eos;
    pub const ogg_page_granulepos = __root.ogg_page_granulepos;
    pub const ogg_page_serialno = __root.ogg_page_serialno;
    pub const ogg_page_pageno = __root.ogg_page_pageno;
    pub const ogg_page_packets = __root.ogg_page_packets;
    pub const set = __root.ogg_page_checksum_set;
    pub const version = __root.ogg_page_version;
    pub const continued = __root.ogg_page_continued;
    pub const bos = __root.ogg_page_bos;
    pub const eos = __root.ogg_page_eos;
    pub const granulepos = __root.ogg_page_granulepos;
    pub const serialno = __root.ogg_page_serialno;
    pub const pageno = __root.ogg_page_pageno;
    pub const packets = __root.ogg_page_packets;
};
pub const ogg_stream_state = extern struct {
    body_data: [*c]u8 = null,
    body_storage: c_long = 0,
    body_fill: c_long = 0,
    body_returned: c_long = 0,
    lacing_vals: [*c]c_int = null,
    granule_vals: [*c]ogg_int64_t = null,
    lacing_storage: c_long = 0,
    lacing_fill: c_long = 0,
    lacing_packet: c_long = 0,
    lacing_returned: c_long = 0,
    header: [282]u8 = @import("std").mem.zeroes([282]u8),
    header_fill: c_int = 0,
    e_o_s: c_int = 0,
    b_o_s: c_int = 0,
    serialno: c_long = 0,
    pageno: c_long = 0,
    packetno: ogg_int64_t = 0,
    granulepos: ogg_int64_t = 0,
    pub const ogg_stream_packetin = __root.ogg_stream_packetin;
    pub const ogg_stream_iovecin = __root.ogg_stream_iovecin;
    pub const ogg_stream_pageout = __root.ogg_stream_pageout;
    pub const ogg_stream_pageout_fill = __root.ogg_stream_pageout_fill;
    pub const ogg_stream_flush = __root.ogg_stream_flush;
    pub const ogg_stream_flush_fill = __root.ogg_stream_flush_fill;
    pub const ogg_stream_pagein = __root.ogg_stream_pagein;
    pub const ogg_stream_packetout = __root.ogg_stream_packetout;
    pub const ogg_stream_packetpeek = __root.ogg_stream_packetpeek;
    pub const ogg_stream_init = __root.ogg_stream_init;
    pub const ogg_stream_clear = __root.ogg_stream_clear;
    pub const ogg_stream_reset = __root.ogg_stream_reset;
    pub const ogg_stream_reset_serialno = __root.ogg_stream_reset_serialno;
    pub const ogg_stream_destroy = __root.ogg_stream_destroy;
    pub const ogg_stream_check = __root.ogg_stream_check;
    pub const ogg_stream_eos = __root.ogg_stream_eos;
    pub const packetin = __root.ogg_stream_packetin;
    pub const iovecin = __root.ogg_stream_iovecin;
    pub const pageout = __root.ogg_stream_pageout;
    pub const fill = __root.ogg_stream_pageout_fill;
    pub const flush = __root.ogg_stream_flush;
    pub const pagein = __root.ogg_stream_pagein;
    pub const packetout = __root.ogg_stream_packetout;
    pub const packetpeek = __root.ogg_stream_packetpeek;
    pub const init = __root.ogg_stream_init;
    pub const clear = __root.ogg_stream_clear;
    pub const reset = __root.ogg_stream_reset;
    pub const destroy = __root.ogg_stream_destroy;
    pub const check = __root.ogg_stream_check;
    pub const eos = __root.ogg_stream_eos;
};
pub const ogg_packet = extern struct {
    packet: [*c]u8 = null,
    bytes: c_long = 0,
    b_o_s: c_long = 0,
    e_o_s: c_long = 0,
    granulepos: ogg_int64_t = 0,
    packetno: ogg_int64_t = 0,
    pub const ogg_packet_clear = __root.ogg_packet_clear;
    pub const clear = __root.ogg_packet_clear;
};
pub const ogg_sync_state = extern struct {
    data: [*c]u8 = null,
    storage: c_int = 0,
    fill: c_int = 0,
    returned: c_int = 0,
    unsynced: c_int = 0,
    headerbytes: c_int = 0,
    bodybytes: c_int = 0,
    pub const ogg_sync_init = __root.ogg_sync_init;
    pub const ogg_sync_clear = __root.ogg_sync_clear;
    pub const ogg_sync_reset = __root.ogg_sync_reset;
    pub const ogg_sync_destroy = __root.ogg_sync_destroy;
    pub const ogg_sync_check = __root.ogg_sync_check;
    pub const ogg_sync_buffer = __root.ogg_sync_buffer;
    pub const ogg_sync_wrote = __root.ogg_sync_wrote;
    pub const ogg_sync_pageseek = __root.ogg_sync_pageseek;
    pub const ogg_sync_pageout = __root.ogg_sync_pageout;
    pub const init = __root.ogg_sync_init;
    pub const clear = __root.ogg_sync_clear;
    pub const reset = __root.ogg_sync_reset;
    pub const destroy = __root.ogg_sync_destroy;
    pub const check = __root.ogg_sync_check;
    pub const buffer = __root.ogg_sync_buffer;
    pub const wrote = __root.ogg_sync_wrote;
    pub const pageseek = __root.ogg_sync_pageseek;
    pub const pageout = __root.ogg_sync_pageout;
};
pub extern fn oggpack_writeinit(b: [*c]oggpack_buffer) void;
pub extern fn oggpack_writecheck(b: [*c]oggpack_buffer) c_int;
pub extern fn oggpack_writetrunc(b: [*c]oggpack_buffer, bits: c_long) void;
pub extern fn oggpack_writealign(b: [*c]oggpack_buffer) void;
pub extern fn oggpack_writecopy(b: [*c]oggpack_buffer, source: ?*anyopaque, bits: c_long) void;
pub extern fn oggpack_reset(b: [*c]oggpack_buffer) void;
pub extern fn oggpack_writeclear(b: [*c]oggpack_buffer) void;
pub extern fn oggpack_readinit(b: [*c]oggpack_buffer, buf: [*c]u8, bytes: c_int) void;
pub extern fn oggpack_write(b: [*c]oggpack_buffer, value: c_ulong, bits: c_int) void;
pub extern fn oggpack_look(b: [*c]oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpack_look1(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpack_adv(b: [*c]oggpack_buffer, bits: c_int) void;
pub extern fn oggpack_adv1(b: [*c]oggpack_buffer) void;
pub extern fn oggpack_read(b: [*c]oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpack_read1(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpack_bytes(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpack_bits(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpack_get_buffer(b: [*c]oggpack_buffer) [*c]u8;
pub extern fn oggpackB_writeinit(b: [*c]oggpack_buffer) void;
pub extern fn oggpackB_writecheck(b: [*c]oggpack_buffer) c_int;
pub extern fn oggpackB_writetrunc(b: [*c]oggpack_buffer, bits: c_long) void;
pub extern fn oggpackB_writealign(b: [*c]oggpack_buffer) void;
pub extern fn oggpackB_writecopy(b: [*c]oggpack_buffer, source: ?*anyopaque, bits: c_long) void;
pub extern fn oggpackB_reset(b: [*c]oggpack_buffer) void;
pub extern fn oggpackB_writeclear(b: [*c]oggpack_buffer) void;
pub extern fn oggpackB_readinit(b: [*c]oggpack_buffer, buf: [*c]u8, bytes: c_int) void;
pub extern fn oggpackB_write(b: [*c]oggpack_buffer, value: c_ulong, bits: c_int) void;
pub extern fn oggpackB_look(b: [*c]oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpackB_look1(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpackB_adv(b: [*c]oggpack_buffer, bits: c_int) void;
pub extern fn oggpackB_adv1(b: [*c]oggpack_buffer) void;
pub extern fn oggpackB_read(b: [*c]oggpack_buffer, bits: c_int) c_long;
pub extern fn oggpackB_read1(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpackB_bytes(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpackB_bits(b: [*c]oggpack_buffer) c_long;
pub extern fn oggpackB_get_buffer(b: [*c]oggpack_buffer) [*c]u8;
pub extern fn ogg_stream_packetin(os: [*c]ogg_stream_state, op: [*c]ogg_packet) c_int;
pub extern fn ogg_stream_iovecin(os: [*c]ogg_stream_state, iov: [*c]ogg_iovec_t, count: c_int, e_o_s: c_long, granulepos: ogg_int64_t) c_int;
pub extern fn ogg_stream_pageout(os: [*c]ogg_stream_state, og: [*c]ogg_page) c_int;
pub extern fn ogg_stream_pageout_fill(os: [*c]ogg_stream_state, og: [*c]ogg_page, nfill: c_int) c_int;
pub extern fn ogg_stream_flush(os: [*c]ogg_stream_state, og: [*c]ogg_page) c_int;
pub extern fn ogg_stream_flush_fill(os: [*c]ogg_stream_state, og: [*c]ogg_page, nfill: c_int) c_int;
pub extern fn ogg_sync_init(oy: [*c]ogg_sync_state) c_int;
pub extern fn ogg_sync_clear(oy: [*c]ogg_sync_state) c_int;
pub extern fn ogg_sync_reset(oy: [*c]ogg_sync_state) c_int;
pub extern fn ogg_sync_destroy(oy: [*c]ogg_sync_state) c_int;
pub extern fn ogg_sync_check(oy: [*c]ogg_sync_state) c_int;
pub extern fn ogg_sync_buffer(oy: [*c]ogg_sync_state, size: c_long) [*c]u8;
pub extern fn ogg_sync_wrote(oy: [*c]ogg_sync_state, bytes: c_long) c_int;
pub extern fn ogg_sync_pageseek(oy: [*c]ogg_sync_state, og: [*c]ogg_page) c_long;
pub extern fn ogg_sync_pageout(oy: [*c]ogg_sync_state, og: [*c]ogg_page) c_int;
pub extern fn ogg_stream_pagein(os: [*c]ogg_stream_state, og: [*c]ogg_page) c_int;
pub extern fn ogg_stream_packetout(os: [*c]ogg_stream_state, op: [*c]ogg_packet) c_int;
pub extern fn ogg_stream_packetpeek(os: [*c]ogg_stream_state, op: [*c]ogg_packet) c_int;
pub extern fn ogg_stream_init(os: [*c]ogg_stream_state, serialno: c_int) c_int;
pub extern fn ogg_stream_clear(os: [*c]ogg_stream_state) c_int;
pub extern fn ogg_stream_reset(os: [*c]ogg_stream_state) c_int;
pub extern fn ogg_stream_reset_serialno(os: [*c]ogg_stream_state, serialno: c_int) c_int;
pub extern fn ogg_stream_destroy(os: [*c]ogg_stream_state) c_int;
pub extern fn ogg_stream_check(os: [*c]ogg_stream_state) c_int;
pub extern fn ogg_stream_eos(os: [*c]ogg_stream_state) c_int;
pub extern fn ogg_page_checksum_set(og: [*c]ogg_page) void;
pub extern fn ogg_page_version(og: [*c]const ogg_page) c_int;
pub extern fn ogg_page_continued(og: [*c]const ogg_page) c_int;
pub extern fn ogg_page_bos(og: [*c]const ogg_page) c_int;
pub extern fn ogg_page_eos(og: [*c]const ogg_page) c_int;
pub extern fn ogg_page_granulepos(og: [*c]const ogg_page) ogg_int64_t;
pub extern fn ogg_page_serialno(og: [*c]const ogg_page) c_int;
pub extern fn ogg_page_pageno(og: [*c]const ogg_page) c_long;
pub extern fn ogg_page_packets(og: [*c]const ogg_page) c_int;
pub extern fn ogg_packet_clear(op: [*c]ogg_packet) void;
pub const opus_int8 = i8;
pub const opus_uint8 = u8;
pub const opus_int16 = i16;
pub const opus_uint16 = u16;
pub const opus_int32 = i32;
pub const opus_uint32 = u32;
pub const opus_int64 = i64;
pub const opus_uint64 = u64;
pub extern fn opus_strerror(@"error": c_int) [*c]const u8;
pub extern fn opus_get_version_string() [*c]const u8;
pub const struct_OpusEncoder = opaque {
    pub const opus_encoder_init = __root.opus_encoder_init;
    pub const opus_encode = __root.opus_encode;
    pub const opus_encode24 = __root.opus_encode24;
    pub const opus_encode_float = __root.opus_encode_float;
    pub const opus_encoder_destroy = __root.opus_encoder_destroy;
    pub const opus_encoder_ctl = __root.opus_encoder_ctl;
    pub const init = __root.opus_encoder_init;
    pub const encode = __root.opus_encode;
    pub const encode24 = __root.opus_encode24;
    pub const float = __root.opus_encode_float;
    pub const destroy = __root.opus_encoder_destroy;
    pub const ctl = __root.opus_encoder_ctl;
};
pub const OpusEncoder = struct_OpusEncoder;
pub extern fn opus_encoder_get_size(channels: c_int) c_int;
pub extern fn opus_encoder_create(Fs: opus_int32, channels: c_int, application: c_int, @"error": [*c]c_int) ?*OpusEncoder;
pub extern fn opus_encoder_init(st: ?*OpusEncoder, Fs: opus_int32, channels: c_int, application: c_int) c_int;
pub extern fn opus_encode(st: ?*OpusEncoder, pcm: [*c]const opus_int16, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) opus_int32;
pub extern fn opus_encode24(st: ?*OpusEncoder, pcm: [*c]const opus_int32, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) opus_int32;
pub extern fn opus_encode_float(st: ?*OpusEncoder, pcm: [*c]const f32, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) opus_int32;
pub extern fn opus_encoder_destroy(st: ?*OpusEncoder) void;
pub extern fn opus_encoder_ctl(st: ?*OpusEncoder, request: c_int, ...) c_int;
pub const struct_OpusDecoder = opaque {
    pub const opus_decoder_init = __root.opus_decoder_init;
    pub const opus_decode = __root.opus_decode;
    pub const opus_decode24 = __root.opus_decode24;
    pub const opus_decode_float = __root.opus_decode_float;
    pub const opus_decoder_ctl = __root.opus_decoder_ctl;
    pub const opus_decoder_destroy = __root.opus_decoder_destroy;
    pub const opus_decoder_dred_decode = __root.opus_decoder_dred_decode;
    pub const opus_decoder_dred_decode24 = __root.opus_decoder_dred_decode24;
    pub const opus_decoder_dred_decode_float = __root.opus_decoder_dred_decode_float;
    pub const opus_decoder_get_nb_samples = __root.opus_decoder_get_nb_samples;
    pub const init = __root.opus_decoder_init;
    pub const decode = __root.opus_decode;
    pub const decode24 = __root.opus_decode24;
    pub const float = __root.opus_decode_float;
    pub const ctl = __root.opus_decoder_ctl;
    pub const destroy = __root.opus_decoder_destroy;
    pub const samples = __root.opus_decoder_get_nb_samples;
};
pub const OpusDecoder = struct_OpusDecoder;
pub const struct_OpusDREDDecoder = opaque {
    pub const opus_dred_decoder_init = __root.opus_dred_decoder_init;
    pub const opus_dred_decoder_destroy = __root.opus_dred_decoder_destroy;
    pub const opus_dred_decoder_ctl = __root.opus_dred_decoder_ctl;
    pub const opus_dred_parse = __root.opus_dred_parse;
    pub const opus_dred_process = __root.opus_dred_process;
    pub const init = __root.opus_dred_decoder_init;
    pub const destroy = __root.opus_dred_decoder_destroy;
    pub const ctl = __root.opus_dred_decoder_ctl;
    pub const parse = __root.opus_dred_parse;
    pub const process = __root.opus_dred_process;
};
pub const OpusDREDDecoder = struct_OpusDREDDecoder;
pub const struct_OpusDRED = opaque {
    pub const opus_dred_free = __root.opus_dred_free;
    pub const free = __root.opus_dred_free;
};
pub const OpusDRED = struct_OpusDRED;
pub extern fn opus_decoder_get_size(channels: c_int) c_int;
pub extern fn opus_decoder_create(Fs: opus_int32, channels: c_int, @"error": [*c]c_int) ?*OpusDecoder;
pub extern fn opus_decoder_init(st: ?*OpusDecoder, Fs: opus_int32, channels: c_int) c_int;
pub extern fn opus_decode(st: ?*OpusDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]opus_int16, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decode24(st: ?*OpusDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]opus_int32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decode_float(st: ?*OpusDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]f32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_decoder_ctl(st: ?*OpusDecoder, request: c_int, ...) c_int;
pub extern fn opus_decoder_destroy(st: ?*OpusDecoder) void;
pub extern fn opus_dred_decoder_get_size() c_int;
pub extern fn opus_dred_decoder_create(@"error": [*c]c_int) ?*OpusDREDDecoder;
pub extern fn opus_dred_decoder_init(dec: ?*OpusDREDDecoder) c_int;
pub extern fn opus_dred_decoder_destroy(dec: ?*OpusDREDDecoder) void;
pub extern fn opus_dred_decoder_ctl(dred_dec: ?*OpusDREDDecoder, request: c_int, ...) c_int;
pub extern fn opus_dred_get_size() c_int;
pub extern fn opus_dred_alloc(@"error": [*c]c_int) ?*OpusDRED;
pub extern fn opus_dred_free(dec: ?*OpusDRED) void;
pub extern fn opus_dred_parse(dred_dec: ?*OpusDREDDecoder, dred: ?*OpusDRED, data: [*c]const u8, len: opus_int32, max_dred_samples: opus_int32, sampling_rate: opus_int32, dred_end: [*c]c_int, defer_processing: c_int) c_int;
pub extern fn opus_dred_process(dred_dec: ?*OpusDREDDecoder, src: ?*const OpusDRED, dst: ?*OpusDRED) c_int;
pub extern fn opus_decoder_dred_decode(st: ?*OpusDecoder, dred: ?*const OpusDRED, dred_offset: opus_int32, pcm: [*c]opus_int16, frame_size: opus_int32) c_int;
pub extern fn opus_decoder_dred_decode24(st: ?*OpusDecoder, dred: ?*const OpusDRED, dred_offset: opus_int32, pcm: [*c]opus_int32, frame_size: opus_int32) c_int;
pub extern fn opus_decoder_dred_decode_float(st: ?*OpusDecoder, dred: ?*const OpusDRED, dred_offset: opus_int32, pcm: [*c]f32, frame_size: opus_int32) c_int;
pub extern fn opus_packet_parse(data: [*c]const u8, len: opus_int32, out_toc: [*c]u8, frames: [*c][*c]const u8, size: [*c]opus_int16, payload_offset: [*c]c_int) c_int;
pub extern fn opus_packet_get_bandwidth(data: [*c]const u8) c_int;
pub extern fn opus_packet_get_samples_per_frame(data: [*c]const u8, Fs: opus_int32) c_int;
pub extern fn opus_packet_get_nb_channels(data: [*c]const u8) c_int;
pub extern fn opus_packet_get_nb_frames(packet: [*c]const u8, len: opus_int32) c_int;
pub extern fn opus_packet_get_nb_samples(packet: [*c]const u8, len: opus_int32, Fs: opus_int32) c_int;
pub extern fn opus_packet_has_lbrr(packet: [*c]const u8, len: opus_int32) c_int;
pub extern fn opus_decoder_get_nb_samples(dec: ?*const OpusDecoder, packet: [*c]const u8, len: opus_int32) c_int;
pub extern fn opus_pcm_soft_clip(pcm: [*c]f32, frame_size: c_int, channels: c_int, softclip_mem: [*c]f32) void;
pub const struct_OpusRepacketizer = opaque {
    pub const opus_repacketizer_init = __root.opus_repacketizer_init;
    pub const opus_repacketizer_destroy = __root.opus_repacketizer_destroy;
    pub const opus_repacketizer_cat = __root.opus_repacketizer_cat;
    pub const opus_repacketizer_out_range = __root.opus_repacketizer_out_range;
    pub const opus_repacketizer_get_nb_frames = __root.opus_repacketizer_get_nb_frames;
    pub const opus_repacketizer_out = __root.opus_repacketizer_out;
    pub const init = __root.opus_repacketizer_init;
    pub const destroy = __root.opus_repacketizer_destroy;
    pub const cat = __root.opus_repacketizer_cat;
    pub const range = __root.opus_repacketizer_out_range;
    pub const frames = __root.opus_repacketizer_get_nb_frames;
    pub const out = __root.opus_repacketizer_out;
};
pub const OpusRepacketizer = struct_OpusRepacketizer;
pub extern fn opus_repacketizer_get_size() c_int;
pub extern fn opus_repacketizer_init(rp: ?*OpusRepacketizer) ?*OpusRepacketizer;
pub extern fn opus_repacketizer_create() ?*OpusRepacketizer;
pub extern fn opus_repacketizer_destroy(rp: ?*OpusRepacketizer) void;
pub extern fn opus_repacketizer_cat(rp: ?*OpusRepacketizer, data: [*c]const u8, len: opus_int32) c_int;
pub extern fn opus_repacketizer_out_range(rp: ?*OpusRepacketizer, begin: c_int, end: c_int, data: [*c]u8, maxlen: opus_int32) opus_int32;
pub extern fn opus_repacketizer_get_nb_frames(rp: ?*OpusRepacketizer) c_int;
pub extern fn opus_repacketizer_out(rp: ?*OpusRepacketizer, data: [*c]u8, maxlen: opus_int32) opus_int32;
pub extern fn opus_packet_pad(data: [*c]u8, len: opus_int32, new_len: opus_int32) c_int;
pub extern fn opus_packet_unpad(data: [*c]u8, len: opus_int32) opus_int32;
pub extern fn opus_multistream_packet_pad(data: [*c]u8, len: opus_int32, new_len: opus_int32, nb_streams: c_int) c_int;
pub extern fn opus_multistream_packet_unpad(data: [*c]u8, len: opus_int32, nb_streams: c_int) opus_int32;
pub const struct_OpusMSEncoder = opaque {
    pub const opus_multistream_encoder_init = __root.opus_multistream_encoder_init;
    pub const opus_multistream_surround_encoder_init = __root.opus_multistream_surround_encoder_init;
    pub const opus_multistream_encode = __root.opus_multistream_encode;
    pub const opus_multistream_encode24 = __root.opus_multistream_encode24;
    pub const opus_multistream_encode_float = __root.opus_multistream_encode_float;
    pub const opus_multistream_encoder_destroy = __root.opus_multistream_encoder_destroy;
    pub const opus_multistream_encoder_ctl = __root.opus_multistream_encoder_ctl;
    pub const init = __root.opus_multistream_encoder_init;
    pub const encode = __root.opus_multistream_encode;
    pub const encode24 = __root.opus_multistream_encode24;
    pub const float = __root.opus_multistream_encode_float;
    pub const destroy = __root.opus_multistream_encoder_destroy;
    pub const ctl = __root.opus_multistream_encoder_ctl;
};
pub const OpusMSEncoder = struct_OpusMSEncoder;
pub const struct_OpusMSDecoder = opaque {
    pub const opus_multistream_decoder_init = __root.opus_multistream_decoder_init;
    pub const opus_multistream_decode = __root.opus_multistream_decode;
    pub const opus_multistream_decode24 = __root.opus_multistream_decode24;
    pub const opus_multistream_decode_float = __root.opus_multistream_decode_float;
    pub const opus_multistream_decoder_ctl = __root.opus_multistream_decoder_ctl;
    pub const opus_multistream_decoder_destroy = __root.opus_multistream_decoder_destroy;
    pub const init = __root.opus_multistream_decoder_init;
    pub const decode = __root.opus_multistream_decode;
    pub const decode24 = __root.opus_multistream_decode24;
    pub const float = __root.opus_multistream_decode_float;
    pub const ctl = __root.opus_multistream_decoder_ctl;
    pub const destroy = __root.opus_multistream_decoder_destroy;
};
pub const OpusMSDecoder = struct_OpusMSDecoder;
pub extern fn opus_multistream_encoder_get_size(streams: c_int, coupled_streams: c_int) opus_int32;
pub extern fn opus_multistream_surround_encoder_get_size(channels: c_int, mapping_family: c_int) opus_int32;
pub extern fn opus_multistream_encoder_create(Fs: opus_int32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*c]const u8, application: c_int, @"error": [*c]c_int) ?*OpusMSEncoder;
pub extern fn opus_multistream_surround_encoder_create(Fs: opus_int32, channels: c_int, mapping_family: c_int, streams: [*c]c_int, coupled_streams: [*c]c_int, mapping: [*c]u8, application: c_int, @"error": [*c]c_int) ?*OpusMSEncoder;
pub extern fn opus_multistream_encoder_init(st: ?*OpusMSEncoder, Fs: opus_int32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*c]const u8, application: c_int) c_int;
pub extern fn opus_multistream_surround_encoder_init(st: ?*OpusMSEncoder, Fs: opus_int32, channels: c_int, mapping_family: c_int, streams: [*c]c_int, coupled_streams: [*c]c_int, mapping: [*c]u8, application: c_int) c_int;
pub extern fn opus_multistream_encode(st: ?*OpusMSEncoder, pcm: [*c]const opus_int16, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) c_int;
pub extern fn opus_multistream_encode24(st: ?*OpusMSEncoder, pcm: [*c]const opus_int32, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) c_int;
pub extern fn opus_multistream_encode_float(st: ?*OpusMSEncoder, pcm: [*c]const f32, frame_size: c_int, data: [*c]u8, max_data_bytes: opus_int32) c_int;
pub extern fn opus_multistream_encoder_destroy(st: ?*OpusMSEncoder) void;
pub extern fn opus_multistream_encoder_ctl(st: ?*OpusMSEncoder, request: c_int, ...) c_int;
pub extern fn opus_multistream_decoder_get_size(streams: c_int, coupled_streams: c_int) opus_int32;
pub extern fn opus_multistream_decoder_create(Fs: opus_int32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*c]const u8, @"error": [*c]c_int) ?*OpusMSDecoder;
pub extern fn opus_multistream_decoder_init(st: ?*OpusMSDecoder, Fs: opus_int32, channels: c_int, streams: c_int, coupled_streams: c_int, mapping: [*c]const u8) c_int;
pub extern fn opus_multistream_decode(st: ?*OpusMSDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]opus_int16, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decode24(st: ?*OpusMSDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]opus_int32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decode_float(st: ?*OpusMSDecoder, data: [*c]const u8, len: opus_int32, pcm: [*c]f32, frame_size: c_int, decode_fec: c_int) c_int;
pub extern fn opus_multistream_decoder_ctl(st: ?*OpusMSDecoder, request: c_int, ...) c_int;
pub extern fn opus_multistream_decoder_destroy(st: ?*OpusMSDecoder) void;
pub const struct_OpusHead = extern struct {
    version: c_int = 0,
    channel_count: c_int = 0,
    pre_skip: c_uint = 0,
    input_sample_rate: opus_uint32 = 0,
    output_gain: c_int = 0,
    mapping_family: c_int = 0,
    stream_count: c_int = 0,
    coupled_count: c_int = 0,
    mapping: [255]u8 = @import("std").mem.zeroes([255]u8),
    pub const opus_head_parse = __root.opus_head_parse;
    pub const opus_granule_sample = __root.opus_granule_sample;
    pub const op_test = __root.op_test;
    pub const parse = __root.opus_head_parse;
    pub const sample = __root.opus_granule_sample;
    pub const @"test" = __root.op_test;
};
pub const OpusHead = struct_OpusHead;
pub const struct_OpusTags = extern struct {
    user_comments: [*c][*c]u8 = null,
    comment_lengths: [*c]c_int = null,
    comments: c_int = 0,
    vendor: [*c]u8 = null,
    pub const opus_tags_parse = __root.opus_tags_parse;
    pub const opus_tags_copy = __root.opus_tags_copy;
    pub const opus_tags_init = __root.opus_tags_init;
    pub const opus_tags_add = __root.opus_tags_add;
    pub const opus_tags_add_comment = __root.opus_tags_add_comment;
    pub const opus_tags_set_binary_suffix = __root.opus_tags_set_binary_suffix;
    pub const opus_tags_query = __root.opus_tags_query;
    pub const opus_tags_query_count = __root.opus_tags_query_count;
    pub const opus_tags_get_binary_suffix = __root.opus_tags_get_binary_suffix;
    pub const opus_tags_get_album_gain = __root.opus_tags_get_album_gain;
    pub const opus_tags_get_track_gain = __root.opus_tags_get_track_gain;
    pub const opus_tags_clear = __root.opus_tags_clear;
    pub const parse = __root.opus_tags_parse;
    pub const copy = __root.opus_tags_copy;
    pub const init = __root.opus_tags_init;
    pub const add = __root.opus_tags_add;
    pub const comment = __root.opus_tags_add_comment;
    pub const suffix = __root.opus_tags_set_binary_suffix;
    pub const query = __root.opus_tags_query;
    pub const count = __root.opus_tags_query_count;
    pub const gain = __root.opus_tags_get_album_gain;
    pub const clear = __root.opus_tags_clear;
};
pub const OpusTags = struct_OpusTags;
pub const struct_OpusPictureTag = extern struct {
    type: opus_int32 = 0,
    mime_type: [*c]u8 = null,
    description: [*c]u8 = null,
    width: opus_uint32 = 0,
    height: opus_uint32 = 0,
    depth: opus_uint32 = 0,
    colors: opus_uint32 = 0,
    data_length: opus_uint32 = 0,
    data: [*c]u8 = null,
    format: c_int = 0,
    pub const opus_picture_tag_parse = __root.opus_picture_tag_parse;
    pub const opus_picture_tag_init = __root.opus_picture_tag_init;
    pub const opus_picture_tag_clear = __root.opus_picture_tag_clear;
    pub const parse = __root.opus_picture_tag_parse;
    pub const init = __root.opus_picture_tag_init;
    pub const clear = __root.opus_picture_tag_clear;
};
pub const OpusPictureTag = struct_OpusPictureTag;
pub const struct_OpusServerInfo = extern struct {
    name: [*c]u8 = null,
    description: [*c]u8 = null,
    genre: [*c]u8 = null,
    url: [*c]u8 = null,
    server: [*c]u8 = null,
    content_type: [*c]u8 = null,
    bitrate_kbps: opus_int32 = 0,
    is_public: c_int = 0,
    is_ssl: c_int = 0,
    pub const opus_server_info_init = __root.opus_server_info_init;
    pub const opus_server_info_clear = __root.opus_server_info_clear;
    pub const init = __root.opus_server_info_init;
    pub const clear = __root.opus_server_info_clear;
};
pub const OpusServerInfo = struct_OpusServerInfo;
pub const op_read_func = ?*const fn (_stream: ?*anyopaque, _ptr: [*c]u8, _nbytes: c_int) callconv(.c) c_int;
pub const op_seek_func = ?*const fn (_stream: ?*anyopaque, _offset: opus_int64, _whence: c_int) callconv(.c) c_int;
pub const op_tell_func = ?*const fn (_stream: ?*anyopaque) callconv(.c) opus_int64;
pub const op_close_func = ?*const fn (_stream: ?*anyopaque) callconv(.c) c_int;
pub const struct_OpusFileCallbacks = extern struct {
    read: op_read_func = null,
    seek: op_seek_func = null,
    tell: op_tell_func = null,
    close: op_close_func = null,
    pub const op_fopen = __root.op_fopen;
    pub const op_fdopen = __root.op_fdopen;
    pub const op_freopen = __root.op_freopen;
    pub const op_mem_stream_create = __root.op_mem_stream_create;
    pub const op_url_stream_vcreate = __root.op_url_stream_vcreate;
    pub const op_url_stream_create = __root.op_url_stream_create;
    pub const fopen = __root.op_fopen;
    pub const fdopen = __root.op_fdopen;
    pub const freopen = __root.op_freopen;
    pub const create = __root.op_mem_stream_create;
    pub const vcreate = __root.op_url_stream_vcreate;
};
pub const OpusFileCallbacks = struct_OpusFileCallbacks;
pub const struct_OggOpusFile = opaque {
    pub const op_test_open = __root.op_test_open;
    pub const op_free = __root.op_free;
    pub const op_seekable = __root.op_seekable;
    pub const op_link_count = __root.op_link_count;
    pub const op_serialno = __root.op_serialno;
    pub const op_channel_count = __root.op_channel_count;
    pub const op_raw_total = __root.op_raw_total;
    pub const op_pcm_total = __root.op_pcm_total;
    pub const op_head = __root.op_head;
    pub const op_tags = __root.op_tags;
    pub const op_current_link = __root.op_current_link;
    pub const op_bitrate = __root.op_bitrate;
    pub const op_bitrate_instant = __root.op_bitrate_instant;
    pub const op_raw_tell = __root.op_raw_tell;
    pub const op_pcm_tell = __root.op_pcm_tell;
    pub const op_raw_seek = __root.op_raw_seek;
    pub const op_pcm_seek = __root.op_pcm_seek;
    pub const op_set_decode_callback = __root.op_set_decode_callback;
    pub const op_set_gain_offset = __root.op_set_gain_offset;
    pub const op_set_dither_enabled = __root.op_set_dither_enabled;
    pub const op_read = __root.op_read;
    pub const op_read_float = __root.op_read_float;
    pub const op_read_stereo = __root.op_read_stereo;
    pub const op_read_float_stereo = __root.op_read_float_stereo;
    pub const open = __root.op_test_open;
    pub const free = __root.op_free;
    pub const seekable = __root.op_seekable;
    pub const count = __root.op_link_count;
    pub const serialno = __root.op_serialno;
    pub const total = __root.op_raw_total;
    pub const head = __root.op_head;
    pub const tags = __root.op_tags;
    pub const link = __root.op_current_link;
    pub const bitrate = __root.op_bitrate;
    pub const instant = __root.op_bitrate_instant;
    pub const tell = __root.op_raw_tell;
    pub const seek = __root.op_raw_seek;
    pub const callback = __root.op_set_decode_callback;
    pub const offset = __root.op_set_gain_offset;
    pub const enabled = __root.op_set_dither_enabled;
    pub const read = __root.op_read;
    pub const float = __root.op_read_float;
    pub const stereo = __root.op_read_stereo;
};
pub const OggOpusFile = struct_OggOpusFile;
pub extern fn opus_head_parse(_head: [*c]OpusHead, _data: [*c]const u8, _len: usize) c_int;
pub extern fn opus_granule_sample(_head: [*c]const OpusHead, _gp: ogg_int64_t) ogg_int64_t;
pub extern fn opus_tags_parse(_tags: [*c]OpusTags, _data: [*c]const u8, _len: usize) c_int;
pub extern fn opus_tags_copy(_dst: [*c]OpusTags, _src: [*c]const OpusTags) c_int;
pub extern fn opus_tags_init(_tags: [*c]OpusTags) void;
pub extern fn opus_tags_add(_tags: [*c]OpusTags, _tag: [*c]const u8, _value: [*c]const u8) c_int;
pub extern fn opus_tags_add_comment(_tags: [*c]OpusTags, _comment: [*c]const u8) c_int;
pub extern fn opus_tags_set_binary_suffix(_tags: [*c]OpusTags, _data: [*c]const u8, _len: c_int) c_int;
pub extern fn opus_tags_query(_tags: [*c]const OpusTags, _tag: [*c]const u8, _count: c_int) [*c]const u8;
pub extern fn opus_tags_query_count(_tags: [*c]const OpusTags, _tag: [*c]const u8) c_int;
pub extern fn opus_tags_get_binary_suffix(_tags: [*c]const OpusTags, _len: [*c]c_int) [*c]const u8;
pub extern fn opus_tags_get_album_gain(_tags: [*c]const OpusTags, _gain_q8: [*c]c_int) c_int;
pub extern fn opus_tags_get_track_gain(_tags: [*c]const OpusTags, _gain_q8: [*c]c_int) c_int;
pub extern fn opus_tags_clear(_tags: [*c]OpusTags) void;
pub extern fn opus_tagcompare(_tag_name: [*c]const u8, _comment: [*c]const u8) c_int;
pub extern fn opus_tagncompare(_tag_name: [*c]const u8, _tag_len: c_int, _comment: [*c]const u8) c_int;
pub extern fn opus_picture_tag_parse(_pic: [*c]OpusPictureTag, _tag: [*c]const u8) c_int;
pub extern fn opus_picture_tag_init(_pic: [*c]OpusPictureTag) void;
pub extern fn opus_picture_tag_clear(_pic: [*c]OpusPictureTag) void;
pub extern fn opus_server_info_init(_info: [*c]OpusServerInfo) void;
pub extern fn opus_server_info_clear(_info: [*c]OpusServerInfo) void;
pub extern fn op_fopen(_cb: [*c]OpusFileCallbacks, _path: [*c]const u8, _mode: [*c]const u8) ?*anyopaque;
pub extern fn op_fdopen(_cb: [*c]OpusFileCallbacks, _fd: c_int, _mode: [*c]const u8) ?*anyopaque;
pub extern fn op_freopen(_cb: [*c]OpusFileCallbacks, _path: [*c]const u8, _mode: [*c]const u8, _stream: ?*anyopaque) ?*anyopaque;
pub extern fn op_mem_stream_create(_cb: [*c]OpusFileCallbacks, _data: [*c]const u8, _size: usize) ?*anyopaque;
pub extern fn op_url_stream_vcreate(_cb: [*c]OpusFileCallbacks, _url: [*c]const u8, _ap: va_list) ?*anyopaque;
pub extern fn op_url_stream_create(_cb: [*c]OpusFileCallbacks, _url: [*c]const u8, ...) ?*anyopaque;
pub extern fn op_test(_head: [*c]OpusHead, _initial_data: [*c]const u8, _initial_bytes: usize) c_int;
pub extern fn op_open_file(_path: [*c]const u8, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_open_memory(_data: [*c]const u8, _size: usize, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_vopen_url(_url: [*c]const u8, _error: [*c]c_int, _ap: va_list) ?*OggOpusFile;
pub extern fn op_open_url(_url: [*c]const u8, _error: [*c]c_int, ...) ?*OggOpusFile;
pub extern fn op_open_callbacks(_stream: ?*anyopaque, _cb: [*c]const OpusFileCallbacks, _initial_data: [*c]const u8, _initial_bytes: usize, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_test_file(_path: [*c]const u8, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_test_memory(_data: [*c]const u8, _size: usize, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_vtest_url(_url: [*c]const u8, _error: [*c]c_int, _ap: va_list) ?*OggOpusFile;
pub extern fn op_test_url(_url: [*c]const u8, _error: [*c]c_int, ...) ?*OggOpusFile;
pub extern fn op_test_callbacks(_stream: ?*anyopaque, _cb: [*c]const OpusFileCallbacks, _initial_data: [*c]const u8, _initial_bytes: usize, _error: [*c]c_int) ?*OggOpusFile;
pub extern fn op_test_open(_of: ?*OggOpusFile) c_int;
pub extern fn op_free(_of: ?*OggOpusFile) void;
pub extern fn op_seekable(_of: ?*const OggOpusFile) c_int;
pub extern fn op_link_count(_of: ?*const OggOpusFile) c_int;
pub extern fn op_serialno(_of: ?*const OggOpusFile, _li: c_int) opus_uint32;
pub extern fn op_channel_count(_of: ?*const OggOpusFile, _li: c_int) c_int;
pub extern fn op_raw_total(_of: ?*const OggOpusFile, _li: c_int) opus_int64;
pub extern fn op_pcm_total(_of: ?*const OggOpusFile, _li: c_int) ogg_int64_t;
pub extern fn op_head(_of: ?*const OggOpusFile, _li: c_int) [*c]const OpusHead;
pub extern fn op_tags(_of: ?*const OggOpusFile, _li: c_int) [*c]const OpusTags;
pub extern fn op_current_link(_of: ?*const OggOpusFile) c_int;
pub extern fn op_bitrate(_of: ?*const OggOpusFile, _li: c_int) opus_int32;
pub extern fn op_bitrate_instant(_of: ?*OggOpusFile) opus_int32;
pub extern fn op_raw_tell(_of: ?*const OggOpusFile) opus_int64;
pub extern fn op_pcm_tell(_of: ?*const OggOpusFile) ogg_int64_t;
pub extern fn op_raw_seek(_of: ?*OggOpusFile, _byte_offset: opus_int64) c_int;
pub extern fn op_pcm_seek(_of: ?*OggOpusFile, _pcm_offset: ogg_int64_t) c_int;
pub const op_decode_cb_func = ?*const fn (_ctx: ?*anyopaque, _decoder: ?*OpusMSDecoder, _pcm: ?*anyopaque, _op: [*c]const ogg_packet, _nsamples: c_int, _nchannels: c_int, _format: c_int, _li: c_int) callconv(.c) c_int;
pub extern fn op_set_decode_callback(_of: ?*OggOpusFile, _decode_cb: op_decode_cb_func, _ctx: ?*anyopaque) void;
pub extern fn op_set_gain_offset(_of: ?*OggOpusFile, _gain_type: c_int, _gain_offset_q8: opus_int32) c_int;
pub extern fn op_set_dither_enabled(_of: ?*OggOpusFile, _enabled: c_int) void;
pub extern fn op_read(_of: ?*OggOpusFile, _pcm: [*c]opus_int16, _buf_size: c_int, _li: [*c]c_int) c_int;
pub extern fn op_read_float(_of: ?*OggOpusFile, _pcm: [*c]f32, _buf_size: c_int, _li: [*c]c_int) c_int;
pub extern fn op_read_stereo(_of: ?*OggOpusFile, _pcm: [*c]opus_int16, _buf_size: c_int) c_int;
pub extern fn op_read_float_stereo(_of: ?*OggOpusFile, _pcm: [*c]f32, _buf_size: c_int) c_int;
pub const ope_write_func = ?*const fn (user_data: ?*anyopaque, ptr: [*c]const u8, len: opus_int32) callconv(.c) c_int;
pub const ope_close_func = ?*const fn (user_data: ?*anyopaque) callconv(.c) c_int;
pub const ope_packet_func = ?*const fn (user_data: ?*anyopaque, packet_ptr: [*c]const u8, packet_len: opus_int32, flags: opus_uint32) callconv(.c) void;
pub const OpusEncCallbacks = extern struct {
    write: ope_write_func = null,
    close: ope_close_func = null,
    pub const ope_encoder_create_callbacks = __root.ope_encoder_create_callbacks;
    pub const callbacks = __root.ope_encoder_create_callbacks;
};
pub const struct_OggOpusComments = opaque {
    pub const ope_comments_copy = __root.ope_comments_copy;
    pub const ope_comments_destroy = __root.ope_comments_destroy;
    pub const ope_comments_add = __root.ope_comments_add;
    pub const ope_comments_add_string = __root.ope_comments_add_string;
    pub const ope_comments_add_picture = __root.ope_comments_add_picture;
    pub const ope_comments_add_picture_from_memory = __root.ope_comments_add_picture_from_memory;
    pub const ope_encoder_create_pull = __root.ope_encoder_create_pull;
    pub const copy = __root.ope_comments_copy;
    pub const destroy = __root.ope_comments_destroy;
    pub const add = __root.ope_comments_add;
    pub const string = __root.ope_comments_add_string;
    pub const picture = __root.ope_comments_add_picture;
    pub const memory = __root.ope_comments_add_picture_from_memory;
    pub const pull = __root.ope_encoder_create_pull;
};
pub const OggOpusComments = struct_OggOpusComments;
pub const struct_OggOpusEnc = opaque {
    pub const ope_encoder_deferred_init_with_mapping = __root.ope_encoder_deferred_init_with_mapping;
    pub const ope_encoder_write_float = __root.ope_encoder_write_float;
    pub const ope_encoder_write = __root.ope_encoder_write;
    pub const ope_encoder_get_page = __root.ope_encoder_get_page;
    pub const ope_encoder_drain = __root.ope_encoder_drain;
    pub const ope_encoder_destroy = __root.ope_encoder_destroy;
    pub const ope_encoder_chain_current = __root.ope_encoder_chain_current;
    pub const ope_encoder_continue_new_file = __root.ope_encoder_continue_new_file;
    pub const ope_encoder_continue_new_callbacks = __root.ope_encoder_continue_new_callbacks;
    pub const ope_encoder_flush_header = __root.ope_encoder_flush_header;
    pub const ope_encoder_ctl = __root.ope_encoder_ctl;
    pub const mapping = __root.ope_encoder_deferred_init_with_mapping;
    pub const float = __root.ope_encoder_write_float;
    pub const write = __root.ope_encoder_write;
    pub const page = __root.ope_encoder_get_page;
    pub const drain = __root.ope_encoder_drain;
    pub const destroy = __root.ope_encoder_destroy;
    pub const current = __root.ope_encoder_chain_current;
    pub const file = __root.ope_encoder_continue_new_file;
    pub const callbacks = __root.ope_encoder_continue_new_callbacks;
    pub const header = __root.ope_encoder_flush_header;
    pub const ctl = __root.ope_encoder_ctl;
};
pub const OggOpusEnc = struct_OggOpusEnc;
pub extern fn ope_comments_create() ?*OggOpusComments;
pub extern fn ope_comments_copy(comments: ?*OggOpusComments) ?*OggOpusComments;
pub extern fn ope_comments_destroy(comments: ?*OggOpusComments) void;
pub extern fn ope_comments_add(comments: ?*OggOpusComments, tag: [*c]const u8, val: [*c]const u8) c_int;
pub extern fn ope_comments_add_string(comments: ?*OggOpusComments, tag_and_val: [*c]const u8) c_int;
pub extern fn ope_comments_add_picture(comments: ?*OggOpusComments, filename: [*c]const u8, picture_type: c_int, description: [*c]const u8) c_int;
pub extern fn ope_comments_add_picture_from_memory(comments: ?*OggOpusComments, ptr: [*c]const u8, size: usize, picture_type: c_int, description: [*c]const u8) c_int;
pub extern fn ope_encoder_create_file(path: [*c]const u8, comments: ?*OggOpusComments, rate: opus_int32, channels: c_int, family: c_int, @"error": [*c]c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_create_callbacks(callbacks: [*c]const OpusEncCallbacks, user_data: ?*anyopaque, comments: ?*OggOpusComments, rate: opus_int32, channels: c_int, family: c_int, @"error": [*c]c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_create_pull(comments: ?*OggOpusComments, rate: opus_int32, channels: c_int, family: c_int, @"error": [*c]c_int) ?*OggOpusEnc;
pub extern fn ope_encoder_deferred_init_with_mapping(enc: ?*OggOpusEnc, family: c_int, streams: c_int, coupled_streams: c_int, mapping: [*c]const u8) c_int;
pub extern fn ope_encoder_write_float(enc: ?*OggOpusEnc, pcm: [*c]const f32, samples_per_channel: c_int) c_int;
pub extern fn ope_encoder_write(enc: ?*OggOpusEnc, pcm: [*c]const opus_int16, samples_per_channel: c_int) c_int;
pub extern fn ope_encoder_get_page(enc: ?*OggOpusEnc, page: [*c][*c]u8, len: [*c]opus_int32, flush: c_int) c_int;
pub extern fn ope_encoder_drain(enc: ?*OggOpusEnc) c_int;
pub extern fn ope_encoder_destroy(enc: ?*OggOpusEnc) void;
pub extern fn ope_encoder_chain_current(enc: ?*OggOpusEnc, comments: ?*OggOpusComments) c_int;
pub extern fn ope_encoder_continue_new_file(enc: ?*OggOpusEnc, path: [*c]const u8, comments: ?*OggOpusComments) c_int;
pub extern fn ope_encoder_continue_new_callbacks(enc: ?*OggOpusEnc, user_data: ?*anyopaque, comments: ?*OggOpusComments) c_int;
pub extern fn ope_encoder_flush_header(enc: ?*OggOpusEnc) c_int;
pub extern fn ope_encoder_ctl(enc: ?*OggOpusEnc, request: c_int, ...) c_int;
pub extern fn ope_strerror(@"error": c_int) [*c]const u8;
pub extern fn ope_get_version_string() [*c]const u8;
pub extern fn ope_get_abi_version() c_int;

pub const __VERSION__ = "Aro aro-zig";
pub const __Aro__ = "";
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __STDC_NO_THREADS__ = @as(c_int, 1);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __GNUC__ = @as(c_int, 4);
pub const __GNUC_MINOR__ = @as(c_int, 2);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 1);
pub const __ARO_EMULATE_CLANG__ = @as(c_int, 1);
pub const __ARO_EMULATE_GCC__ = @as(c_int, 2);
pub const __ARO_EMULATE_MSVC__ = @as(c_int, 3);
pub const __ARO_EMULATE__ = __ARO_EMULATE_CLANG__;
pub inline fn __building_module(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const __OPTIMIZE__ = @as(c_int, 1);
pub const __APPLE__ = @as(c_int, 1);
pub const __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ = __helpers.promoteIntLiteral(c_int, 260501, .decimal);
pub const __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__ = __helpers.promoteIntLiteral(c_int, 260501, .decimal);
pub const __aarch64__ = @as(c_int, 1);
pub const __AARCH64_SIMD__ = @as(c_int, 1);
pub const __ARM64_ARCH_8__ = @as(c_int, 1);
pub const __ARM_NEON__ = @as(c_int, 1);
pub const __arm64 = @as(c_int, 1);
pub const __arm64__ = @as(c_int, 1);
pub const __AARCH64_CMODEL_SMALL__ = @as(c_int, 1);
pub const __ARM_FP = @as(c_int, 0xE);
pub const __ARM_NEON = @as(c_int, 1);
pub const __ARM_NEON_FP = @as(c_int, 0xE);
pub const __ARM_FEATURE_BF16 = @as(c_int, 1);
pub const __ARM_FEATURE_BF16_VECTOR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_BF16_FORMAT_ALTERNATIVE = @as(c_int, 1);
pub const __ARM_FEATURE_BF16_SCALAR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_SHA3 = @as(c_int, 1);
pub const __ARM_FEATURE_SHA512 = @as(c_int, 1);
pub const __ARM_FEATURE_UNALIGNED = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_VECTOR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_RCPC = @as(c_int, 1);
pub const __ARM_FEATURE_CRC32 = @as(c_int, 1);
pub const __ARM_FEATURE_AES = @as(c_int, 1);
pub const __ARM_FEATURE_SHA2 = @as(c_int, 1);
pub const __ARM_FEATURE_PAUTH = @as(c_int, 1);
pub const __ARM_FEATURE_BTI = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_SCALAR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_DOTPROD = @as(c_int, 1);
pub const __ARM_FEATURE_MATMUL_INT8 = @as(c_int, 1);
pub const __ARM_FEATURE_ATOMICS = @as(c_int, 1);
pub const __ARM_FEATURE_SVE_MATMUL_INT8 = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_FML = @as(c_int, 1);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const __MACH__ = @as(c_int, 1);
pub const __nonnull = @compileError("unable to translate C expr: unexpected token '_Nonnull'"); // <builtin>:62:9
pub const __null_unspecified = @compileError("unable to translate C expr: unexpected token '_Null_unspecified'"); // <builtin>:63:9
pub const __nullable = @compileError("unable to translate C expr: unexpected token '_Nullable'"); // <builtin>:64:9
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __ATOMIC_BOOL_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_SHORT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_INT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LLONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_POINTER_LOCK_FREE = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SCHAR_WIDTH__ = @as(c_int, 8);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __LONG_LONG_WIDTH__ = @as(c_int, 64);
pub const __WCHAR_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIG_ATOMIC_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __BITINT_MAXWIDTH__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTPTR_TYPE__ = c_long;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:125:9
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:127:9
pub const __PTRDIFF_TYPE__ = c_long;
pub const __SIZE_TYPE__ = c_ulong;
pub const __WCHAR_TYPE__ = c_int;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub const __INT64_TYPE__ = c_longlong;
pub const __INT64_FMTd__ = "lld";
pub const __INT64_FMTi__ = "lli";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `LL`"); // <builtin>:148:9
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub const __UINT16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // <builtin>:170:9
pub const __UINT32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulonglong;
pub const __UINT64_FMTo__ = "llo";
pub const __UINT64_FMTu__ = "llu";
pub const __UINT64_FMTx__ = "llx";
pub const __UINT64_FMTX__ = "llX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `ULL`"); // <builtin>:178:9
pub const __UINT64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const __INT64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const INT_LEAST8_FMTd__ = "hhd";
pub const INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const UINT_LEAST8_FMTo__ = "hho";
pub const UINT_LEAST8_FMTu__ = "hhu";
pub const UINT_LEAST8_FMTx__ = "hhx";
pub const UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const INT_FAST8_FMTd__ = "hhd";
pub const INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const UINT_FAST8_FMTo__ = "hho";
pub const UINT_FAST8_FMTu__ = "hhu";
pub const UINT_FAST8_FMTx__ = "hhx";
pub const UINT_FAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const INT_LEAST16_FMTd__ = "hd";
pub const INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST16_FMTo__ = "ho";
pub const UINT_LEAST16_FMTu__ = "hu";
pub const UINT_LEAST16_FMTx__ = "hx";
pub const UINT_LEAST16_FMTX__ = "hX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const INT_FAST16_FMTd__ = "hd";
pub const INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_FAST16_FMTo__ = "ho";
pub const UINT_FAST16_FMTu__ = "hu";
pub const UINT_FAST16_FMTx__ = "hx";
pub const UINT_FAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const INT_LEAST32_FMTd__ = "d";
pub const INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST32_FMTo__ = "o";
pub const UINT_LEAST32_FMTu__ = "u";
pub const UINT_LEAST32_FMTx__ = "x";
pub const UINT_LEAST32_FMTX__ = "X";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const INT_FAST32_FMTd__ = "d";
pub const INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_FAST32_FMTo__ = "o";
pub const UINT_FAST32_FMTu__ = "u";
pub const UINT_FAST32_FMTx__ = "x";
pub const UINT_FAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_longlong;
pub const __INT_LEAST64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const INT_LEAST64_FMTd__ = "lld";
pub const INT_LEAST64_FMTi__ = "lli";
pub const __UINT_LEAST64_TYPE__ = c_ulonglong;
pub const __UINT_LEAST64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const UINT_LEAST64_FMTo__ = "llo";
pub const UINT_LEAST64_FMTu__ = "llu";
pub const UINT_LEAST64_FMTx__ = "llx";
pub const UINT_LEAST64_FMTX__ = "llX";
pub const __INT_FAST64_TYPE__ = c_longlong;
pub const __INT_FAST64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const INT_FAST64_FMTd__ = "lld";
pub const INT_FAST64_FMTi__ = "lli";
pub const __UINT_FAST64_TYPE__ = c_ulonglong;
pub const __UINT_FAST64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const UINT_FAST64_FMTo__ = "llo";
pub const UINT_FAST64_FMTu__ = "llu";
pub const UINT_FAST64_FMTx__ = "llx";
pub const UINT_FAST64_FMTX__ = "llX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_HAS_DENORM__ = "";
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = "";
pub const __FLT16_HAS_QUIET_NAN__ = "";
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = "";
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = "";
pub const __FLT_HAS_QUIET_NAN__ = "";
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = "";
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = "";
pub const __DBL_HAS_QUIET_NAN__ = "";
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 4.9406564584124654e-324);
pub const __LDBL_HAS_DENORM__ = "";
pub const __LDBL_DIG__ = @as(c_int, 15);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 2.2204460492503131e-16);
pub const __LDBL_HAS_INFINITY__ = "";
pub const __LDBL_HAS_QUIET_NAN__ = "";
pub const __LDBL_MANT_DIG__ = @as(c_int, 53);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __LDBL_MAX_EXP__ = @as(c_int, 1024);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.7976931348623157e+308);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __LDBL_MIN__ = @as(c_longdouble, 2.2250738585072014e-308);
pub const __FLT_EVAL_METHOD__ = @as(c_int, 0);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __pic__ = @as(c_int, 2);
pub const __PIC__ = @as(c_int, 2);
pub const _FORTIFY_SOURCE = @as(c_int, 2);
pub const _opusfile_h = @as(c_int, 1);
pub const __STDC_VERSION_STDARG_H__ = @as(c_int, 0);
pub const va_start = @compileError("unable to translate macro: undefined identifier `__builtin_va_start`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stdarg.h:12:9
pub const va_end = @compileError("unable to translate macro: undefined identifier `__builtin_va_end`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stdarg.h:14:9
pub const va_arg = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stdarg.h:15:9
pub const __va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stdarg.h:18:9
pub const va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stdarg.h:22:9
pub const __GNUC_VA_LIST = @as(c_int, 1);
pub const _STDIO_H_ = "";
pub const __STDIO_H_ = "";
pub const _CDEFS_H_ = "";
pub const __BEGIN_DECLS = "";
pub const __END_DECLS = "";
pub inline fn __has_cpp_attribute(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub inline fn __P(protos: anytype) @TypeOf(protos) {
    _ = &protos;
    return protos;
}
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token '##'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:116:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token ''"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:117:9
pub const __const = @compileError("unable to translate C expr: unexpected token 'const'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:119:9
pub const __signed = c_int;
pub const __volatile = @compileError("unable to translate C expr: unexpected token 'volatile'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:121:9
pub const __dead2 = @compileError("unable to translate macro: undefined identifier `__noreturn__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:165:9
pub const __pure2 = @compileError("unable to translate C expr: unexpected token '__attribute__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:166:9
pub const __stateful_pure = @compileError("unable to translate macro: undefined identifier `__pure__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:167:9
pub const __unused = @compileError("unable to translate macro: undefined identifier `__unused__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:172:9
pub const __used = @compileError("unable to translate macro: undefined identifier `__used__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:177:9
pub const __cold = @compileError("unable to translate macro: undefined identifier `__cold__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:183:9
pub const __returns_nonnull = @compileError("unable to translate macro: undefined identifier `returns_nonnull`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:190:9
pub const __exported = @compileError("unable to translate macro: undefined identifier `__visibility__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:200:9
pub const __exported_push = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:201:9
pub const __exported_pop = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:202:9
pub const __deprecated = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:214:9
pub const __deprecated_msg = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:220:10
pub inline fn __deprecated_enum_msg(_msg: anytype) void {
    _ = &_msg;
    return;
}
pub inline fn __kpi_deprecated(_msg: anytype) void {
    _ = &_msg;
    return;
}
pub const __unavailable = @compileError("unable to translate macro: undefined identifier `__unavailable__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:235:9
pub const __kpi_unavailable = "";
pub const __kpi_deprecated_arm64_macos_unavailable = "";
pub const __dead = "";
pub const __pure = "";
pub const __restrict = @compileError("unable to translate C expr: unexpected token 'restrict'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:257:9
pub const __disable_tail_calls = "";
pub const __not_tail_called = "";
pub const __result_use_check = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:313:9
pub const __swift_unavailable = @compileError("unable to translate macro: undefined identifier `__availability__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:323:9
pub const __abortlike = __dead2 ++ __cold;
pub const __header_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:361:10
pub const __header_always_inline = @compileError("unable to translate macro: undefined identifier `__always_inline__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:370:10
pub const __unreachable_ok_push = "";
pub const __unreachable_ok_pop = "";
pub const __printflike = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:407:9
pub const __printf0like = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:409:9
pub const __scanflike = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:411:9
pub const __osloglike = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:413:9
pub const __IDSTRING = @compileError("unable to translate C expr: unexpected token 'static'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:416:9
pub const __COPYRIGHT = @compileError("unable to translate macro: undefined identifier `copyright`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:419:9
pub const __RCSID = @compileError("unable to translate macro: undefined identifier `rcsid`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:423:9
pub const __SCCSID = @compileError("unable to translate macro: undefined identifier `sccsid`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:427:9
pub const __PROJECT_VERSION = @compileError("unable to translate macro: undefined identifier `project_version`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:431:9
pub inline fn __FBSDID(s: anytype) void {
    _ = &s;
    return;
}
pub const __DECONST = @compileError("unable to translate C expr: unexpected token 'const'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:440:9
pub const __DEVOLATILE = @compileError("unable to translate C expr: unexpected token 'volatile'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:444:9
pub const __DEQUALIFY = @compileError("unable to translate C expr: unexpected token 'const'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:448:9
pub const __alloc_align = @compileError("unable to translate macro: undefined identifier `alloc_align`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:457:9
pub const __alloc_size = @compileError("unable to translate macro: undefined identifier `alloc_size`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:478:9
pub const __has_safe_buffers = @as(c_int, 0);
pub const __unsafe_buffer_usage = "";
pub const __unsafe_buffer_usage_begin = "";
pub const __unsafe_buffer_usage_end = "";
pub const __DARWIN_ONLY_64_BIT_INO_T = @as(c_int, 1);
pub const __DARWIN_ONLY_UNIX_CONFORMANCE = @as(c_int, 1);
pub const __DARWIN_ONLY_VERS_1050 = @as(c_int, 1);
pub const __DARWIN_UNIX03 = @as(c_int, 1);
pub const __DARWIN_64_BIT_INO_T = @as(c_int, 1);
pub const __DARWIN_VERS_1050 = @as(c_int, 1);
pub const __DARWIN_NON_CANCELABLE = @as(c_int, 0);
pub const __DARWIN_SUF_UNIX03 = "";
pub const __DARWIN_SUF_64_BIT_INO_T = "";
pub const __DARWIN_SUF_1050 = "";
pub const __DARWIN_SUF_NON_CANCELABLE = "";
pub const __DARWIN_SUF_EXTSN = "$DARWIN_EXTSN";
pub const __DARWIN_ALIAS = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:751:9
pub const __DARWIN_ALIAS_C = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:752:9
pub const __DARWIN_ALIAS_I = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:753:9
pub const __DARWIN_NOCANCEL = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:754:9
pub const __DARWIN_INODE64 = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:755:9
pub const __DARWIN_1050 = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:757:9
pub const __DARWIN_1050ALIAS = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:758:9
pub const __DARWIN_1050ALIAS_C = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:759:9
pub const __DARWIN_1050ALIAS_I = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:760:9
pub const __DARWIN_1050INODE64 = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:761:9
pub const __DARWIN_EXTSN = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:763:9
pub const __DARWIN_EXTSN_C = @compileError("unable to translate C expr: unexpected token '__asm'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:764:9
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_2_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_2_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_2_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_3_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_3_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_3_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_4_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_4_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_4_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_4_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_5_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_5_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_6_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_6_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_7_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_7_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_8_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_8_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_8_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_8_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_8_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_9_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_9_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_9_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_9_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_10_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_10_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_10_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_10_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_11_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_11_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_11_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_11_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_11_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_12_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_12_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_12_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_12_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_12_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_5(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_6(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_13_7(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_5(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_6(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_7(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_14_8(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_5(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_6(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_7(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_15_8(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_5(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_6(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_16_7(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_17_0(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_17_1(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_17_2(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_17_3(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_17_4(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_0(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_5(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_6(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_7(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_8(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_9(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_10(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_10_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_10_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_11(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_11_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_11_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_11_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_12(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_12_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_12_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_12_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_13(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_13_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_13_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_13_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_14(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_14_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_14_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_14_5(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_14_6(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_15(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_15_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_15_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_10_16(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_0(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_5(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_11_6(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_0(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_5(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_6(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_12_7(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_0(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_5(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_13_6(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_14_0(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_14_1(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_14_2(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_14_3(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __DARWIN_ALIAS_STARTING_MAC___MAC_14_4(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub const __DARWIN_ALIAS_STARTING = @compileError("unable to translate macro: undefined identifier `__DARWIN_ALIAS_STARTING_MAC_`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:774:9
pub const ___POSIX_C_DEPRECATED_STARTING_198808L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_199009L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_199209L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_199309L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_199506L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_200112L = "";
pub const ___POSIX_C_DEPRECATED_STARTING_200809L = "";
pub const __POSIX_C_DEPRECATED = @compileError("unable to translate macro: undefined identifier `___POSIX_C_DEPRECATED_STARTING_`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:837:9
pub const __DARWIN_C_ANSI = @as(c_long, 0o10000);
pub const __DARWIN_C_FULL = @as(c_long, 900000);
pub const __DARWIN_C_LEVEL = __DARWIN_C_FULL;
pub const __STDC_WANT_LIB_EXT1__ = @as(c_int, 1);
pub const __DARWIN_NO_LONG_LONG = @as(c_int, 0);
pub const _DARWIN_FEATURE_64_BIT_INODE = @as(c_int, 1);
pub const _DARWIN_FEATURE_ONLY_64_BIT_INODE = @as(c_int, 1);
pub const _DARWIN_FEATURE_ONLY_VERS_1050 = @as(c_int, 1);
pub const _DARWIN_FEATURE_ONLY_UNIX_CONFORMANCE = @as(c_int, 1);
pub const _DARWIN_FEATURE_UNIX_CONFORMANCE = @as(c_int, 3);
pub const __CAST_AWAY_QUALIFIER = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:935:9
pub const __XNU_PRIVATE_EXTERN = @compileError("unable to translate macro: undefined identifier `visibility`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:949:9
pub const __has_ptrcheck = @as(c_int, 0);
pub const __single = "";
pub const __unsafe_indexable = "";
pub inline fn __counted_by(N: anytype) void {
    _ = &N;
    return;
}
pub inline fn __sized_by(N: anytype) void {
    _ = &N;
    return;
}
pub inline fn __ended_by(E: anytype) void {
    _ = &E;
    return;
}
pub inline fn __terminated_by(T: anytype) void {
    _ = &T;
    return;
}
pub const __null_terminated = "";
pub inline fn __ptrcheck_abi_assume_single() void {
    return;
}
pub inline fn __ptrcheck_abi_assume_unsafe_indexable() void {
    return;
}
pub inline fn __unsafe_forge_bidi_indexable(T: anytype, P: anytype, S: anytype) @TypeOf(T(P)) {
    _ = &T;
    _ = &P;
    _ = &S;
    return T(P);
}
pub const __unsafe_forge_single = __helpers.CAST_OR_CALL;
pub inline fn __unsafe_forge_terminated_by(T: anytype, P: anytype, E: anytype) @TypeOf(T(P)) {
    _ = &T;
    _ = &P;
    _ = &E;
    return T(P);
}
pub const __unsafe_forge_null_terminated = __helpers.CAST_OR_CALL;
pub inline fn __terminated_by_to_indexable(P: anytype) @TypeOf(P) {
    _ = &P;
    return P;
}
pub inline fn __unsafe_terminated_by_to_indexable(P: anytype) @TypeOf(P) {
    _ = &P;
    return P;
}
pub inline fn __null_terminated_to_indexable(P: anytype) @TypeOf(P) {
    _ = &P;
    return P;
}
pub inline fn __unsafe_null_terminated_to_indexable(P: anytype) @TypeOf(P) {
    _ = &P;
    return P;
}
pub inline fn __unsafe_terminated_by_from_indexable(T: anytype, P: anytype) @TypeOf(P) {
    _ = &T;
    _ = &P;
    return P;
}
pub inline fn __unsafe_null_terminated_from_indexable(P: anytype) @TypeOf(P) {
    _ = &P;
    return P;
}
pub const __array_decay_dicards_count_in_parameters = "";
pub const __unsafe_late_const = "";
pub const __ptrcheck_unavailable = "";
pub inline fn __ptrcheck_unavailable_r(REPLACEMENT: anytype) void {
    _ = &REPLACEMENT;
    return;
}
pub const __ASSUME_PTR_ABI_SINGLE_BEGIN = __ptrcheck_abi_assume_single();
pub const __ASSUME_PTR_ABI_SINGLE_END = __ptrcheck_abi_assume_unsafe_indexable();
pub const __header_indexable = "";
pub const __header_bidi_indexable = "";
pub const __compiler_barrier = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:1027:9
pub const __enum_open = "";
pub const __enum_closed = "";
pub const __enum_options = "";
pub const __enum_decl = @compileError("unable to translate C expr: unexpected token 'typedef'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:1060:9
pub const __enum_closed_decl = @compileError("unable to translate C expr: unexpected token 'typedef'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:1062:9
pub const __options_decl = @compileError("unable to translate C expr: unexpected token 'typedef'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:1064:9
pub const __options_closed_decl = @compileError("unable to translate C expr: unexpected token 'typedef'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/cdefs.h:1066:9
pub const __kernel_ptr_semantics = "";
pub const __kernel_data_semantics = "";
pub const __kernel_dual_semantics = "";
pub const __AVAILABILITY__ = "";
pub const __API_TO_BE_DEPRECATED = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_MACOS = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_IOS = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_MACCATALYST = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_WATCHOS = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_TVOS = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_DRIVERKIT = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __API_TO_BE_DEPRECATED_VISIONOS = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __AVAILABILITY_VERSIONS__ = "";
pub const __MAC_10_0 = @as(c_int, 1000);
pub const __MAC_10_1 = @as(c_int, 1010);
pub const __MAC_10_2 = @as(c_int, 1020);
pub const __MAC_10_3 = @as(c_int, 1030);
pub const __MAC_10_4 = @as(c_int, 1040);
pub const __MAC_10_5 = @as(c_int, 1050);
pub const __MAC_10_6 = @as(c_int, 1060);
pub const __MAC_10_7 = @as(c_int, 1070);
pub const __MAC_10_8 = @as(c_int, 1080);
pub const __MAC_10_9 = @as(c_int, 1090);
pub const __MAC_10_10 = __helpers.promoteIntLiteral(c_int, 101000, .decimal);
pub const __MAC_10_10_2 = __helpers.promoteIntLiteral(c_int, 101002, .decimal);
pub const __MAC_10_10_3 = __helpers.promoteIntLiteral(c_int, 101003, .decimal);
pub const __MAC_10_11 = __helpers.promoteIntLiteral(c_int, 101100, .decimal);
pub const __MAC_10_11_2 = __helpers.promoteIntLiteral(c_int, 101102, .decimal);
pub const __MAC_10_11_3 = __helpers.promoteIntLiteral(c_int, 101103, .decimal);
pub const __MAC_10_11_4 = __helpers.promoteIntLiteral(c_int, 101104, .decimal);
pub const __MAC_10_12 = __helpers.promoteIntLiteral(c_int, 101200, .decimal);
pub const __MAC_10_12_1 = __helpers.promoteIntLiteral(c_int, 101201, .decimal);
pub const __MAC_10_12_2 = __helpers.promoteIntLiteral(c_int, 101202, .decimal);
pub const __MAC_10_12_4 = __helpers.promoteIntLiteral(c_int, 101204, .decimal);
pub const __MAC_10_13 = __helpers.promoteIntLiteral(c_int, 101300, .decimal);
pub const __MAC_10_13_1 = __helpers.promoteIntLiteral(c_int, 101301, .decimal);
pub const __MAC_10_13_2 = __helpers.promoteIntLiteral(c_int, 101302, .decimal);
pub const __MAC_10_13_4 = __helpers.promoteIntLiteral(c_int, 101304, .decimal);
pub const __MAC_10_14 = __helpers.promoteIntLiteral(c_int, 101400, .decimal);
pub const __MAC_10_14_1 = __helpers.promoteIntLiteral(c_int, 101401, .decimal);
pub const __MAC_10_14_4 = __helpers.promoteIntLiteral(c_int, 101404, .decimal);
pub const __MAC_10_14_5 = __helpers.promoteIntLiteral(c_int, 101405, .decimal);
pub const __MAC_10_14_6 = __helpers.promoteIntLiteral(c_int, 101406, .decimal);
pub const __MAC_10_15 = __helpers.promoteIntLiteral(c_int, 101500, .decimal);
pub const __MAC_10_15_1 = __helpers.promoteIntLiteral(c_int, 101501, .decimal);
pub const __MAC_10_15_4 = __helpers.promoteIntLiteral(c_int, 101504, .decimal);
pub const __MAC_10_16 = __helpers.promoteIntLiteral(c_int, 101600, .decimal);
pub const __MAC_11_0 = __helpers.promoteIntLiteral(c_int, 110000, .decimal);
pub const __MAC_11_1 = __helpers.promoteIntLiteral(c_int, 110100, .decimal);
pub const __MAC_11_3 = __helpers.promoteIntLiteral(c_int, 110300, .decimal);
pub const __MAC_11_4 = __helpers.promoteIntLiteral(c_int, 110400, .decimal);
pub const __MAC_11_5 = __helpers.promoteIntLiteral(c_int, 110500, .decimal);
pub const __MAC_11_6 = __helpers.promoteIntLiteral(c_int, 110600, .decimal);
pub const __MAC_12_0 = __helpers.promoteIntLiteral(c_int, 120000, .decimal);
pub const __MAC_12_1 = __helpers.promoteIntLiteral(c_int, 120100, .decimal);
pub const __MAC_12_2 = __helpers.promoteIntLiteral(c_int, 120200, .decimal);
pub const __MAC_12_3 = __helpers.promoteIntLiteral(c_int, 120300, .decimal);
pub const __MAC_12_4 = __helpers.promoteIntLiteral(c_int, 120400, .decimal);
pub const __MAC_12_5 = __helpers.promoteIntLiteral(c_int, 120500, .decimal);
pub const __MAC_12_6 = __helpers.promoteIntLiteral(c_int, 120600, .decimal);
pub const __MAC_12_7 = __helpers.promoteIntLiteral(c_int, 120700, .decimal);
pub const __MAC_13_0 = __helpers.promoteIntLiteral(c_int, 130000, .decimal);
pub const __MAC_13_1 = __helpers.promoteIntLiteral(c_int, 130100, .decimal);
pub const __MAC_13_2 = __helpers.promoteIntLiteral(c_int, 130200, .decimal);
pub const __MAC_13_3 = __helpers.promoteIntLiteral(c_int, 130300, .decimal);
pub const __MAC_13_4 = __helpers.promoteIntLiteral(c_int, 130400, .decimal);
pub const __MAC_13_5 = __helpers.promoteIntLiteral(c_int, 130500, .decimal);
pub const __MAC_13_6 = __helpers.promoteIntLiteral(c_int, 130600, .decimal);
pub const __MAC_14_0 = __helpers.promoteIntLiteral(c_int, 140000, .decimal);
pub const __MAC_14_1 = __helpers.promoteIntLiteral(c_int, 140100, .decimal);
pub const __MAC_14_2 = __helpers.promoteIntLiteral(c_int, 140200, .decimal);
pub const __MAC_14_3 = __helpers.promoteIntLiteral(c_int, 140300, .decimal);
pub const __MAC_14_4 = __helpers.promoteIntLiteral(c_int, 140400, .decimal);
pub const __IPHONE_2_0 = @as(c_int, 20000);
pub const __IPHONE_2_1 = @as(c_int, 20100);
pub const __IPHONE_2_2 = @as(c_int, 20200);
pub const __IPHONE_3_0 = @as(c_int, 30000);
pub const __IPHONE_3_1 = @as(c_int, 30100);
pub const __IPHONE_3_2 = @as(c_int, 30200);
pub const __IPHONE_4_0 = __helpers.promoteIntLiteral(c_int, 40000, .decimal);
pub const __IPHONE_4_1 = __helpers.promoteIntLiteral(c_int, 40100, .decimal);
pub const __IPHONE_4_2 = __helpers.promoteIntLiteral(c_int, 40200, .decimal);
pub const __IPHONE_4_3 = __helpers.promoteIntLiteral(c_int, 40300, .decimal);
pub const __IPHONE_5_0 = __helpers.promoteIntLiteral(c_int, 50000, .decimal);
pub const __IPHONE_5_1 = __helpers.promoteIntLiteral(c_int, 50100, .decimal);
pub const __IPHONE_6_0 = __helpers.promoteIntLiteral(c_int, 60000, .decimal);
pub const __IPHONE_6_1 = __helpers.promoteIntLiteral(c_int, 60100, .decimal);
pub const __IPHONE_7_0 = __helpers.promoteIntLiteral(c_int, 70000, .decimal);
pub const __IPHONE_7_1 = __helpers.promoteIntLiteral(c_int, 70100, .decimal);
pub const __IPHONE_8_0 = __helpers.promoteIntLiteral(c_int, 80000, .decimal);
pub const __IPHONE_8_1 = __helpers.promoteIntLiteral(c_int, 80100, .decimal);
pub const __IPHONE_8_2 = __helpers.promoteIntLiteral(c_int, 80200, .decimal);
pub const __IPHONE_8_3 = __helpers.promoteIntLiteral(c_int, 80300, .decimal);
pub const __IPHONE_8_4 = __helpers.promoteIntLiteral(c_int, 80400, .decimal);
pub const __IPHONE_9_0 = __helpers.promoteIntLiteral(c_int, 90000, .decimal);
pub const __IPHONE_9_1 = __helpers.promoteIntLiteral(c_int, 90100, .decimal);
pub const __IPHONE_9_2 = __helpers.promoteIntLiteral(c_int, 90200, .decimal);
pub const __IPHONE_9_3 = __helpers.promoteIntLiteral(c_int, 90300, .decimal);
pub const __IPHONE_10_0 = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __IPHONE_10_1 = __helpers.promoteIntLiteral(c_int, 100100, .decimal);
pub const __IPHONE_10_2 = __helpers.promoteIntLiteral(c_int, 100200, .decimal);
pub const __IPHONE_10_3 = __helpers.promoteIntLiteral(c_int, 100300, .decimal);
pub const __IPHONE_11_0 = __helpers.promoteIntLiteral(c_int, 110000, .decimal);
pub const __IPHONE_11_1 = __helpers.promoteIntLiteral(c_int, 110100, .decimal);
pub const __IPHONE_11_2 = __helpers.promoteIntLiteral(c_int, 110200, .decimal);
pub const __IPHONE_11_3 = __helpers.promoteIntLiteral(c_int, 110300, .decimal);
pub const __IPHONE_11_4 = __helpers.promoteIntLiteral(c_int, 110400, .decimal);
pub const __IPHONE_12_0 = __helpers.promoteIntLiteral(c_int, 120000, .decimal);
pub const __IPHONE_12_1 = __helpers.promoteIntLiteral(c_int, 120100, .decimal);
pub const __IPHONE_12_2 = __helpers.promoteIntLiteral(c_int, 120200, .decimal);
pub const __IPHONE_12_3 = __helpers.promoteIntLiteral(c_int, 120300, .decimal);
pub const __IPHONE_12_4 = __helpers.promoteIntLiteral(c_int, 120400, .decimal);
pub const __IPHONE_13_0 = __helpers.promoteIntLiteral(c_int, 130000, .decimal);
pub const __IPHONE_13_1 = __helpers.promoteIntLiteral(c_int, 130100, .decimal);
pub const __IPHONE_13_2 = __helpers.promoteIntLiteral(c_int, 130200, .decimal);
pub const __IPHONE_13_3 = __helpers.promoteIntLiteral(c_int, 130300, .decimal);
pub const __IPHONE_13_4 = __helpers.promoteIntLiteral(c_int, 130400, .decimal);
pub const __IPHONE_13_5 = __helpers.promoteIntLiteral(c_int, 130500, .decimal);
pub const __IPHONE_13_6 = __helpers.promoteIntLiteral(c_int, 130600, .decimal);
pub const __IPHONE_13_7 = __helpers.promoteIntLiteral(c_int, 130700, .decimal);
pub const __IPHONE_14_0 = __helpers.promoteIntLiteral(c_int, 140000, .decimal);
pub const __IPHONE_14_1 = __helpers.promoteIntLiteral(c_int, 140100, .decimal);
pub const __IPHONE_14_2 = __helpers.promoteIntLiteral(c_int, 140200, .decimal);
pub const __IPHONE_14_3 = __helpers.promoteIntLiteral(c_int, 140300, .decimal);
pub const __IPHONE_14_5 = __helpers.promoteIntLiteral(c_int, 140500, .decimal);
pub const __IPHONE_14_4 = __helpers.promoteIntLiteral(c_int, 140400, .decimal);
pub const __IPHONE_14_6 = __helpers.promoteIntLiteral(c_int, 140600, .decimal);
pub const __IPHONE_14_7 = __helpers.promoteIntLiteral(c_int, 140700, .decimal);
pub const __IPHONE_14_8 = __helpers.promoteIntLiteral(c_int, 140800, .decimal);
pub const __IPHONE_15_0 = __helpers.promoteIntLiteral(c_int, 150000, .decimal);
pub const __IPHONE_15_1 = __helpers.promoteIntLiteral(c_int, 150100, .decimal);
pub const __IPHONE_15_2 = __helpers.promoteIntLiteral(c_int, 150200, .decimal);
pub const __IPHONE_15_3 = __helpers.promoteIntLiteral(c_int, 150300, .decimal);
pub const __IPHONE_15_4 = __helpers.promoteIntLiteral(c_int, 150400, .decimal);
pub const __IPHONE_15_5 = __helpers.promoteIntLiteral(c_int, 150500, .decimal);
pub const __IPHONE_15_6 = __helpers.promoteIntLiteral(c_int, 150600, .decimal);
pub const __IPHONE_15_7 = __helpers.promoteIntLiteral(c_int, 150700, .decimal);
pub const __IPHONE_15_8 = __helpers.promoteIntLiteral(c_int, 150800, .decimal);
pub const __IPHONE_16_0 = __helpers.promoteIntLiteral(c_int, 160000, .decimal);
pub const __IPHONE_16_1 = __helpers.promoteIntLiteral(c_int, 160100, .decimal);
pub const __IPHONE_16_2 = __helpers.promoteIntLiteral(c_int, 160200, .decimal);
pub const __IPHONE_16_3 = __helpers.promoteIntLiteral(c_int, 160300, .decimal);
pub const __IPHONE_16_4 = __helpers.promoteIntLiteral(c_int, 160400, .decimal);
pub const __IPHONE_16_5 = __helpers.promoteIntLiteral(c_int, 160500, .decimal);
pub const __IPHONE_16_6 = __helpers.promoteIntLiteral(c_int, 160600, .decimal);
pub const __IPHONE_16_7 = __helpers.promoteIntLiteral(c_int, 160700, .decimal);
pub const __IPHONE_17_0 = __helpers.promoteIntLiteral(c_int, 170000, .decimal);
pub const __IPHONE_17_1 = __helpers.promoteIntLiteral(c_int, 170100, .decimal);
pub const __IPHONE_17_2 = __helpers.promoteIntLiteral(c_int, 170200, .decimal);
pub const __IPHONE_17_3 = __helpers.promoteIntLiteral(c_int, 170300, .decimal);
pub const __IPHONE_17_4 = __helpers.promoteIntLiteral(c_int, 170400, .decimal);
pub const __WATCHOS_1_0 = @as(c_int, 10000);
pub const __WATCHOS_2_0 = @as(c_int, 20000);
pub const __WATCHOS_2_1 = @as(c_int, 20100);
pub const __WATCHOS_2_2 = @as(c_int, 20200);
pub const __WATCHOS_3_0 = @as(c_int, 30000);
pub const __WATCHOS_3_1 = @as(c_int, 30100);
pub const __WATCHOS_3_1_1 = @as(c_int, 30101);
pub const __WATCHOS_3_2 = @as(c_int, 30200);
pub const __WATCHOS_4_0 = __helpers.promoteIntLiteral(c_int, 40000, .decimal);
pub const __WATCHOS_4_1 = __helpers.promoteIntLiteral(c_int, 40100, .decimal);
pub const __WATCHOS_4_2 = __helpers.promoteIntLiteral(c_int, 40200, .decimal);
pub const __WATCHOS_4_3 = __helpers.promoteIntLiteral(c_int, 40300, .decimal);
pub const __WATCHOS_5_0 = __helpers.promoteIntLiteral(c_int, 50000, .decimal);
pub const __WATCHOS_5_1 = __helpers.promoteIntLiteral(c_int, 50100, .decimal);
pub const __WATCHOS_5_2 = __helpers.promoteIntLiteral(c_int, 50200, .decimal);
pub const __WATCHOS_5_3 = __helpers.promoteIntLiteral(c_int, 50300, .decimal);
pub const __WATCHOS_6_0 = __helpers.promoteIntLiteral(c_int, 60000, .decimal);
pub const __WATCHOS_6_1 = __helpers.promoteIntLiteral(c_int, 60100, .decimal);
pub const __WATCHOS_6_2 = __helpers.promoteIntLiteral(c_int, 60200, .decimal);
pub const __WATCHOS_7_0 = __helpers.promoteIntLiteral(c_int, 70000, .decimal);
pub const __WATCHOS_7_1 = __helpers.promoteIntLiteral(c_int, 70100, .decimal);
pub const __WATCHOS_7_2 = __helpers.promoteIntLiteral(c_int, 70200, .decimal);
pub const __WATCHOS_7_3 = __helpers.promoteIntLiteral(c_int, 70300, .decimal);
pub const __WATCHOS_7_4 = __helpers.promoteIntLiteral(c_int, 70400, .decimal);
pub const __WATCHOS_7_5 = __helpers.promoteIntLiteral(c_int, 70500, .decimal);
pub const __WATCHOS_7_6 = __helpers.promoteIntLiteral(c_int, 70600, .decimal);
pub const __WATCHOS_8_0 = __helpers.promoteIntLiteral(c_int, 80000, .decimal);
pub const __WATCHOS_8_1 = __helpers.promoteIntLiteral(c_int, 80100, .decimal);
pub const __WATCHOS_8_3 = __helpers.promoteIntLiteral(c_int, 80300, .decimal);
pub const __WATCHOS_8_4 = __helpers.promoteIntLiteral(c_int, 80400, .decimal);
pub const __WATCHOS_8_5 = __helpers.promoteIntLiteral(c_int, 80500, .decimal);
pub const __WATCHOS_8_6 = __helpers.promoteIntLiteral(c_int, 80600, .decimal);
pub const __WATCHOS_8_7 = __helpers.promoteIntLiteral(c_int, 80700, .decimal);
pub const __WATCHOS_8_8 = __helpers.promoteIntLiteral(c_int, 80800, .decimal);
pub const __WATCHOS_9_0 = __helpers.promoteIntLiteral(c_int, 90000, .decimal);
pub const __WATCHOS_9_1 = __helpers.promoteIntLiteral(c_int, 90100, .decimal);
pub const __WATCHOS_9_2 = __helpers.promoteIntLiteral(c_int, 90200, .decimal);
pub const __WATCHOS_9_3 = __helpers.promoteIntLiteral(c_int, 90300, .decimal);
pub const __WATCHOS_9_4 = __helpers.promoteIntLiteral(c_int, 90400, .decimal);
pub const __WATCHOS_9_5 = __helpers.promoteIntLiteral(c_int, 90500, .decimal);
pub const __WATCHOS_9_6 = __helpers.promoteIntLiteral(c_int, 90600, .decimal);
pub const __WATCHOS_10_0 = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __WATCHOS_10_1 = __helpers.promoteIntLiteral(c_int, 100100, .decimal);
pub const __WATCHOS_10_2 = __helpers.promoteIntLiteral(c_int, 100200, .decimal);
pub const __WATCHOS_10_3 = __helpers.promoteIntLiteral(c_int, 100300, .decimal);
pub const __WATCHOS_10_4 = __helpers.promoteIntLiteral(c_int, 100400, .decimal);
pub const __TVOS_9_0 = __helpers.promoteIntLiteral(c_int, 90000, .decimal);
pub const __TVOS_9_1 = __helpers.promoteIntLiteral(c_int, 90100, .decimal);
pub const __TVOS_9_2 = __helpers.promoteIntLiteral(c_int, 90200, .decimal);
pub const __TVOS_10_0 = __helpers.promoteIntLiteral(c_int, 100000, .decimal);
pub const __TVOS_10_0_1 = __helpers.promoteIntLiteral(c_int, 100001, .decimal);
pub const __TVOS_10_1 = __helpers.promoteIntLiteral(c_int, 100100, .decimal);
pub const __TVOS_10_2 = __helpers.promoteIntLiteral(c_int, 100200, .decimal);
pub const __TVOS_11_0 = __helpers.promoteIntLiteral(c_int, 110000, .decimal);
pub const __TVOS_11_1 = __helpers.promoteIntLiteral(c_int, 110100, .decimal);
pub const __TVOS_11_2 = __helpers.promoteIntLiteral(c_int, 110200, .decimal);
pub const __TVOS_11_3 = __helpers.promoteIntLiteral(c_int, 110300, .decimal);
pub const __TVOS_11_4 = __helpers.promoteIntLiteral(c_int, 110400, .decimal);
pub const __TVOS_12_0 = __helpers.promoteIntLiteral(c_int, 120000, .decimal);
pub const __TVOS_12_1 = __helpers.promoteIntLiteral(c_int, 120100, .decimal);
pub const __TVOS_12_2 = __helpers.promoteIntLiteral(c_int, 120200, .decimal);
pub const __TVOS_12_3 = __helpers.promoteIntLiteral(c_int, 120300, .decimal);
pub const __TVOS_12_4 = __helpers.promoteIntLiteral(c_int, 120400, .decimal);
pub const __TVOS_13_0 = __helpers.promoteIntLiteral(c_int, 130000, .decimal);
pub const __TVOS_13_2 = __helpers.promoteIntLiteral(c_int, 130200, .decimal);
pub const __TVOS_13_3 = __helpers.promoteIntLiteral(c_int, 130300, .decimal);
pub const __TVOS_13_4 = __helpers.promoteIntLiteral(c_int, 130400, .decimal);
pub const __TVOS_14_0 = __helpers.promoteIntLiteral(c_int, 140000, .decimal);
pub const __TVOS_14_1 = __helpers.promoteIntLiteral(c_int, 140100, .decimal);
pub const __TVOS_14_2 = __helpers.promoteIntLiteral(c_int, 140200, .decimal);
pub const __TVOS_14_3 = __helpers.promoteIntLiteral(c_int, 140300, .decimal);
pub const __TVOS_14_5 = __helpers.promoteIntLiteral(c_int, 140500, .decimal);
pub const __TVOS_14_6 = __helpers.promoteIntLiteral(c_int, 140600, .decimal);
pub const __TVOS_14_7 = __helpers.promoteIntLiteral(c_int, 140700, .decimal);
pub const __TVOS_15_0 = __helpers.promoteIntLiteral(c_int, 150000, .decimal);
pub const __TVOS_15_1 = __helpers.promoteIntLiteral(c_int, 150100, .decimal);
pub const __TVOS_15_2 = __helpers.promoteIntLiteral(c_int, 150200, .decimal);
pub const __TVOS_15_3 = __helpers.promoteIntLiteral(c_int, 150300, .decimal);
pub const __TVOS_15_4 = __helpers.promoteIntLiteral(c_int, 150400, .decimal);
pub const __TVOS_15_5 = __helpers.promoteIntLiteral(c_int, 150500, .decimal);
pub const __TVOS_15_6 = __helpers.promoteIntLiteral(c_int, 150600, .decimal);
pub const __TVOS_16_0 = __helpers.promoteIntLiteral(c_int, 160000, .decimal);
pub const __TVOS_16_1 = __helpers.promoteIntLiteral(c_int, 160100, .decimal);
pub const __TVOS_16_2 = __helpers.promoteIntLiteral(c_int, 160200, .decimal);
pub const __TVOS_16_3 = __helpers.promoteIntLiteral(c_int, 160300, .decimal);
pub const __TVOS_16_4 = __helpers.promoteIntLiteral(c_int, 160400, .decimal);
pub const __TVOS_16_5 = __helpers.promoteIntLiteral(c_int, 160500, .decimal);
pub const __TVOS_16_6 = __helpers.promoteIntLiteral(c_int, 160600, .decimal);
pub const __TVOS_17_0 = __helpers.promoteIntLiteral(c_int, 170000, .decimal);
pub const __TVOS_17_1 = __helpers.promoteIntLiteral(c_int, 170100, .decimal);
pub const __TVOS_17_2 = __helpers.promoteIntLiteral(c_int, 170200, .decimal);
pub const __TVOS_17_3 = __helpers.promoteIntLiteral(c_int, 170300, .decimal);
pub const __TVOS_17_4 = __helpers.promoteIntLiteral(c_int, 170400, .decimal);
pub const __BRIDGEOS_2_0 = @as(c_int, 20000);
pub const __BRIDGEOS_3_0 = @as(c_int, 30000);
pub const __BRIDGEOS_3_1 = @as(c_int, 30100);
pub const __BRIDGEOS_3_4 = @as(c_int, 30400);
pub const __BRIDGEOS_4_0 = __helpers.promoteIntLiteral(c_int, 40000, .decimal);
pub const __BRIDGEOS_4_1 = __helpers.promoteIntLiteral(c_int, 40100, .decimal);
pub const __BRIDGEOS_5_0 = __helpers.promoteIntLiteral(c_int, 50000, .decimal);
pub const __BRIDGEOS_5_1 = __helpers.promoteIntLiteral(c_int, 50100, .decimal);
pub const __BRIDGEOS_5_3 = __helpers.promoteIntLiteral(c_int, 50300, .decimal);
pub const __BRIDGEOS_6_0 = __helpers.promoteIntLiteral(c_int, 60000, .decimal);
pub const __BRIDGEOS_6_2 = __helpers.promoteIntLiteral(c_int, 60200, .decimal);
pub const __BRIDGEOS_6_4 = __helpers.promoteIntLiteral(c_int, 60400, .decimal);
pub const __BRIDGEOS_6_5 = __helpers.promoteIntLiteral(c_int, 60500, .decimal);
pub const __BRIDGEOS_6_6 = __helpers.promoteIntLiteral(c_int, 60600, .decimal);
pub const __BRIDGEOS_7_0 = __helpers.promoteIntLiteral(c_int, 70000, .decimal);
pub const __BRIDGEOS_7_1 = __helpers.promoteIntLiteral(c_int, 70100, .decimal);
pub const __BRIDGEOS_7_2 = __helpers.promoteIntLiteral(c_int, 70200, .decimal);
pub const __BRIDGEOS_7_3 = __helpers.promoteIntLiteral(c_int, 70300, .decimal);
pub const __BRIDGEOS_7_4 = __helpers.promoteIntLiteral(c_int, 70400, .decimal);
pub const __BRIDGEOS_7_6 = __helpers.promoteIntLiteral(c_int, 70600, .decimal);
pub const __BRIDGEOS_8_0 = __helpers.promoteIntLiteral(c_int, 80000, .decimal);
pub const __BRIDGEOS_8_1 = __helpers.promoteIntLiteral(c_int, 80100, .decimal);
pub const __BRIDGEOS_8_2 = __helpers.promoteIntLiteral(c_int, 80200, .decimal);
pub const __BRIDGEOS_8_3 = __helpers.promoteIntLiteral(c_int, 80300, .decimal);
pub const __BRIDGEOS_8_4 = __helpers.promoteIntLiteral(c_int, 80400, .decimal);
pub const __DRIVERKIT_19_0 = __helpers.promoteIntLiteral(c_int, 190000, .decimal);
pub const __DRIVERKIT_20_0 = __helpers.promoteIntLiteral(c_int, 200000, .decimal);
pub const __DRIVERKIT_21_0 = __helpers.promoteIntLiteral(c_int, 210000, .decimal);
pub const __DRIVERKIT_22_0 = __helpers.promoteIntLiteral(c_int, 220000, .decimal);
pub const __DRIVERKIT_22_4 = __helpers.promoteIntLiteral(c_int, 220400, .decimal);
pub const __DRIVERKIT_22_5 = __helpers.promoteIntLiteral(c_int, 220500, .decimal);
pub const __DRIVERKIT_22_6 = __helpers.promoteIntLiteral(c_int, 220600, .decimal);
pub const __DRIVERKIT_23_0 = __helpers.promoteIntLiteral(c_int, 230000, .decimal);
pub const __DRIVERKIT_23_1 = __helpers.promoteIntLiteral(c_int, 230100, .decimal);
pub const __DRIVERKIT_23_2 = __helpers.promoteIntLiteral(c_int, 230200, .decimal);
pub const __DRIVERKIT_23_3 = __helpers.promoteIntLiteral(c_int, 230300, .decimal);
pub const __DRIVERKIT_23_4 = __helpers.promoteIntLiteral(c_int, 230400, .decimal);
pub const __VISIONOS_1_0 = @as(c_int, 10000);
pub const __VISIONOS_1_1 = @as(c_int, 10100);
pub const MAC_OS_X_VERSION_10_0 = __MAC_10_0;
pub const MAC_OS_X_VERSION_10_1 = __MAC_10_1;
pub const MAC_OS_X_VERSION_10_2 = __MAC_10_2;
pub const MAC_OS_X_VERSION_10_3 = __MAC_10_3;
pub const MAC_OS_X_VERSION_10_4 = __MAC_10_4;
pub const MAC_OS_X_VERSION_10_5 = __MAC_10_5;
pub const MAC_OS_X_VERSION_10_6 = __MAC_10_6;
pub const MAC_OS_X_VERSION_10_7 = __MAC_10_7;
pub const MAC_OS_X_VERSION_10_8 = __MAC_10_8;
pub const MAC_OS_X_VERSION_10_9 = __MAC_10_9;
pub const MAC_OS_X_VERSION_10_10 = __MAC_10_10;
pub const MAC_OS_X_VERSION_10_10_2 = __MAC_10_10_2;
pub const MAC_OS_X_VERSION_10_10_3 = __MAC_10_10_3;
pub const MAC_OS_X_VERSION_10_11 = __MAC_10_11;
pub const MAC_OS_X_VERSION_10_11_2 = __MAC_10_11_2;
pub const MAC_OS_X_VERSION_10_11_3 = __MAC_10_11_3;
pub const MAC_OS_X_VERSION_10_11_4 = __MAC_10_11_4;
pub const MAC_OS_X_VERSION_10_12 = __MAC_10_12;
pub const MAC_OS_X_VERSION_10_12_1 = __MAC_10_12_1;
pub const MAC_OS_X_VERSION_10_12_2 = __MAC_10_12_2;
pub const MAC_OS_X_VERSION_10_12_4 = __MAC_10_12_4;
pub const MAC_OS_X_VERSION_10_13 = __MAC_10_13;
pub const MAC_OS_X_VERSION_10_13_1 = __MAC_10_13_1;
pub const MAC_OS_X_VERSION_10_13_2 = __MAC_10_13_2;
pub const MAC_OS_X_VERSION_10_13_4 = __MAC_10_13_4;
pub const MAC_OS_X_VERSION_10_14 = __MAC_10_14;
pub const MAC_OS_X_VERSION_10_14_1 = __MAC_10_14_1;
pub const MAC_OS_X_VERSION_10_14_4 = __MAC_10_14_4;
pub const MAC_OS_X_VERSION_10_14_5 = __MAC_10_14_5;
pub const MAC_OS_X_VERSION_10_14_6 = __MAC_10_14_6;
pub const MAC_OS_X_VERSION_10_15 = __MAC_10_15;
pub const MAC_OS_X_VERSION_10_15_1 = __MAC_10_15_1;
pub const MAC_OS_X_VERSION_10_15_4 = __MAC_10_15_4;
pub const MAC_OS_X_VERSION_10_16 = __MAC_10_16;
pub const MAC_OS_VERSION_11_0 = __MAC_11_0;
pub const MAC_OS_VERSION_11_1 = __MAC_11_1;
pub const MAC_OS_VERSION_11_3 = __MAC_11_3;
pub const MAC_OS_VERSION_11_4 = __MAC_11_4;
pub const MAC_OS_VERSION_11_5 = __MAC_11_5;
pub const MAC_OS_VERSION_11_6 = __MAC_11_6;
pub const MAC_OS_VERSION_12_0 = __MAC_12_0;
pub const MAC_OS_VERSION_12_1 = __MAC_12_1;
pub const MAC_OS_VERSION_12_2 = __MAC_12_2;
pub const MAC_OS_VERSION_12_3 = __MAC_12_3;
pub const MAC_OS_VERSION_12_4 = __MAC_12_4;
pub const MAC_OS_VERSION_12_5 = __MAC_12_5;
pub const MAC_OS_VERSION_12_6 = __MAC_12_6;
pub const MAC_OS_VERSION_12_7 = __MAC_12_7;
pub const MAC_OS_VERSION_13_0 = __MAC_13_0;
pub const MAC_OS_VERSION_13_1 = __MAC_13_1;
pub const MAC_OS_VERSION_13_2 = __MAC_13_2;
pub const MAC_OS_VERSION_13_3 = __MAC_13_3;
pub const MAC_OS_VERSION_13_4 = __MAC_13_4;
pub const MAC_OS_VERSION_13_5 = __MAC_13_5;
pub const MAC_OS_VERSION_13_6 = __MAC_13_6;
pub const MAC_OS_VERSION_14_0 = __MAC_14_0;
pub const MAC_OS_VERSION_14_1 = __MAC_14_1;
pub const MAC_OS_VERSION_14_2 = __MAC_14_2;
pub const MAC_OS_VERSION_14_3 = __MAC_14_3;
pub const MAC_OS_VERSION_14_4 = __MAC_14_4;
pub const __AVAILABILITY_INTERNAL__ = "";
pub const __MAC_OS_X_VERSION_MIN_REQUIRED = __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__;
pub const __MAC_OS_X_VERSION_MAX_ALLOWED = __MAC_14_4;
pub const __IPHONE_OS_VERSION_MIN_REQUIRED = __IPHONE_17_1;
pub const __IPHONE_OS_VERSION_MAX_ALLOWED = __IPHONE_17_4;
pub const __WATCH_OS_VERSION_MIN_REQUIRED = __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__;
pub const __WATCH_OS_VERSION_MAX_ALLOWED = __WATCHOS_10_4;
pub const __TV_OS_VERSION_MIN_REQUIRED = __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__;
pub const __TV_OS_VERSION_MAX_ALLOWED = __TVOS_17_4;
pub const __DRIVERKIT_VERSION_MIN_REQUIRED = __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__;
pub const __DRIVERKIT_VERSION_MAX_ALLOWED = __DRIVERKIT_23_4;
pub const __VISION_OS_VERSION_MIN_REQUIRED = __ENVIRONMENT_OS_VERSION_MIN_REQUIRED__;
pub const __VISION_OS_VERSION_MAX_ALLOWED = __VISIONOS_1_1;
pub const __AVAILABILITY_INTERNAL_DEPRECATED = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:160:9
pub const __AVAILABILITY_INTERNAL_DEPRECATED_MSG = @compileError("unable to translate macro: undefined identifier `deprecated`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:163:17
pub const __AVAILABILITY_INTERNAL_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `unavailable`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:172:9
pub const __AVAILABILITY_INTERNAL_WEAK_IMPORT = @compileError("unable to translate macro: undefined identifier `weak_import`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:173:9
pub const __AVAILABILITY_INTERNAL_REGULAR = "";
pub const __AVAILABILITY_INTERNAL_LEGACY__ = "";
pub const __ENABLE_LEGACY_IPHONE_AVAILABILITY = @as(c_int, 1);
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:65:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:66:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:68:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:72:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:74:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:78:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:80:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:84:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:86:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_11_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:90:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:91:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:93:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:97:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:99:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:103:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_2_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:105:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:109:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:111:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:115:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:117:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:121:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:123:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:127:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:129:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:133:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:135:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:139:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:141:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:145:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:147:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:151:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:153:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:157:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:159:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:163:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:165:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:169:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:171:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:175:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:177:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:181:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:183:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:187:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:189:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:193:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:195:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:199:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:201:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:205:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:207:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:211:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:213:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:217:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:219:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:223:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:225:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:229:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:231:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:235:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:237:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:241:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:242:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:243:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:244:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:246:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:250:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:252:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:256:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:258:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:262:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:264:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_2_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:268:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_2_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:270:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_2_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:274:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_2_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:276:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:280:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:282:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:286:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:288:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:292:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:294:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:298:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:300:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:304:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:306:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:310:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:312:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:316:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:318:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:322:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:324:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:328:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:330:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:334:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:336:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:340:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:342:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:346:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:348:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:352:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:354:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:358:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:360:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:364:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:366:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:370:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:372:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:376:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:378:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:382:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:384:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:388:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:390:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:394:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:396:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:400:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:402:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:406:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:408:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:412:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:413:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:414:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:415:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:417:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:421:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:423:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:427:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:429:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:433:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:435:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_2_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:439:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_2_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:441:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:445:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:447:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:451:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:453:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:457:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:459:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:463:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:465:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:469:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:471:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:475:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:477:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:481:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:483:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:487:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:489:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:493:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:495:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:499:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:501:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:505:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:507:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:511:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:513:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:517:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:519:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:523:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:525:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:529:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:531:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:535:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:537:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:541:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:543:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:547:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:549:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:553:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:555:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:559:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:561:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:565:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:567:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:571:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:573:25
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:577:21
pub const __AVAILABILITY_INTERNAL__IPHONE_2_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:578:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:579:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:580:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:582:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:586:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:588:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:592:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:594:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:598:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:600:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:604:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:606:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:610:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:612:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:616:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:618:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:622:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:624:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:628:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:630:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:634:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:636:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:640:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:642:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:646:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:648:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:652:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:654:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:658:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:660:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:664:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:666:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:670:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:672:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:676:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:678:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:682:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:684:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:688:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:690:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:694:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:696:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:700:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:702:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:706:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:708:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:712:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:714:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:718:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:720:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:724:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:726:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:730:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:732:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:736:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:737:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:738:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:739:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:741:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:745:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:747:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:751:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:753:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:757:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:759:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_3_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:763:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_3_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:765:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:769:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:771:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:775:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:777:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:781:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:783:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:787:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:789:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:793:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:795:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:799:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:801:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:805:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:807:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:811:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:813:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:817:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:819:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:823:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:825:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:829:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:831:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:835:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:837:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:841:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:843:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:847:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:849:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:853:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:855:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:859:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:861:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:865:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:867:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:871:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:873:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:877:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:879:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:883:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:885:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:889:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:890:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:891:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:892:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:894:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:898:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:900:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:904:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:906:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:910:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:912:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_3_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:916:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_3_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:918:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:922:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:924:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:928:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:930:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:934:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:936:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:940:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:942:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:946:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:948:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:952:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:954:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:958:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:960:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:964:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:966:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:970:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:972:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:976:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:978:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:982:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:984:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:988:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:990:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:994:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:996:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1000:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1002:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1006:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1008:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1012:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1014:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1018:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1020:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1024:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1026:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1030:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1032:25
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1036:21
pub const __AVAILABILITY_INTERNAL__IPHONE_3_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1037:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1038:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1039:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1041:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1045:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1047:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1051:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1053:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1057:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1059:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_12_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1064:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1068:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1070:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1074:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1076:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1080:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1082:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1086:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1088:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1092:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1094:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1098:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1100:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1104:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1106:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1110:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1112:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1116:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1118:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1122:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1124:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1128:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1130:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1134:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1136:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1140:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1142:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1146:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1148:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1152:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1154:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1158:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1160:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1164:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1166:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1170:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1172:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1176:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1178:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1182:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1183:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1184:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1185:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1187:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1191:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1193:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1197:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1199:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1203:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1205:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1209:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1211:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1215:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1217:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1221:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1223:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1227:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1229:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1233:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1235:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1239:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1241:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1245:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1247:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1251:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1253:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1257:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1259:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1263:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1265:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1269:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1271:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1275:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1277:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1281:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1283:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1287:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1289:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1293:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1295:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1299:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1301:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1305:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1307:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1311:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1313:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1317:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1318:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1319:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1320:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1322:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1326:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1328:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1332:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1334:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1338:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1340:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_4_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1344:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_4_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1346:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1350:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1352:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1356:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1358:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1362:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1364:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1368:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1370:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1374:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1376:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1380:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1382:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1386:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1388:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1392:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1394:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1398:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1400:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1404:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1406:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1410:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1412:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1416:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1418:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1422:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1424:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1428:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1430:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1434:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1436:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1440:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1442:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1446:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1447:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1448:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1449:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1451:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1455:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1457:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1461:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1463:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1467:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1469:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_4_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1473:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_4_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1475:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1479:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1481:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1485:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1487:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1491:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1493:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1497:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1499:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1503:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1505:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1509:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1511:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1515:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1517:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1521:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1523:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1527:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1529:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1533:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1535:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1539:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1541:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1545:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1547:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1551:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1553:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1557:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1559:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1563:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1565:25
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1569:21
pub const __AVAILABILITY_INTERNAL__IPHONE_4_3_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1570:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1571:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1572:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1574:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1578:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1580:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1584:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1586:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1590:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1592:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_11_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1596:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_5_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1597:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_5_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1599:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1603:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1605:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1609:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1611:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1615:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1617:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1621:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1623:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1627:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1629:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1633:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1635:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1639:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1641:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1645:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1647:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1651:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1653:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1657:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1659:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1663:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1665:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1669:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1671:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1675:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1677:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1681:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1683:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1687:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1688:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1689:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1690:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1692:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1696:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1698:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1702:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1704:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1708:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1710:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_5_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1714:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_5_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1716:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1720:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1722:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1726:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1728:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1732:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1734:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1738:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1740:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1744:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1746:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1750:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1752:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1756:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1758:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1762:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1764:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1768:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1770:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1774:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1776:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1780:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1782:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1786:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1788:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1792:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1794:25
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1798:21
pub const __AVAILABILITY_INTERNAL__IPHONE_5_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1799:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1800:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1801:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1803:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1807:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1809:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1813:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1815:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1819:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1821:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_6_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1825:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_6_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1827:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1831:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1833:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1837:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1839:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1843:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1845:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1849:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1851:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1855:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1857:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1861:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1863:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1867:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1869:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1873:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1875:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1879:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1881:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1885:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1887:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1891:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1893:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1897:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1899:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1903:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1904:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1905:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1906:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1908:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1912:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1914:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1918:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1920:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1924:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1926:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_6_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1930:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_6_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1932:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1936:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1938:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1942:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1944:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1948:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1950:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1954:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1956:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1960:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1962:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1966:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1968:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1972:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1974:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1978:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1980:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1984:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1986:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1990:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1992:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1996:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:1998:25
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2002:21
pub const __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2003:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2004:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2005:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2007:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2011:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2013:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2017:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2019:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2023:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2025:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_11_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2029:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_11_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2030:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_12_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2032:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_7_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2036:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_7_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2038:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2042:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2044:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2048:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2050:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2054:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2056:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2060:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2062:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2066:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2068:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2072:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2074:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2078:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2080:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2084:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2086:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2090:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2092:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2096:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2098:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2102:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2103:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2104:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2105:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2107:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2111:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2113:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2117:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2119:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2123:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2125:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_7_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2129:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_7_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2131:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2135:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2137:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2141:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2143:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2147:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2149:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2153:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2155:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2159:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2161:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2165:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2167:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2171:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2173:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2177:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2179:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2183:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2185:25
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2189:21
pub const __AVAILABILITY_INTERNAL__IPHONE_7_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2190:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2191:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2192:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2194:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2198:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2200:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2204:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2206:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2210:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2212:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_11_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2217:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_11_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2221:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_12_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2222:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2223:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2225:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2229:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2231:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2235:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2237:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2241:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2243:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2247:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2249:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2253:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2255:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2259:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2261:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2265:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2267:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2271:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2273:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2277:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2278:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2279:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2280:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2282:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2286:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2288:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2292:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2294:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2298:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2300:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2304:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2306:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2310:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2312:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2316:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2318:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2322:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2324:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2328:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2330:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2334:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2336:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2340:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2342:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2346:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2348:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2352:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2353:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2354:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2355:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2357:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2361:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2363:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2367:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2369:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2373:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2375:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2379:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2381:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2385:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2387:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2391:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2393:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2397:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2399:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2403:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2405:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2409:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2411:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2415:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2417:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2421:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2422:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2423:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2424:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2426:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2430:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2432:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2436:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2438:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2442:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2444:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_8_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2448:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_8_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2450:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2454:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2456:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2460:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2462:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2466:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2468:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2472:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2474:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2478:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2480:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2484:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_3_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2485:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2486:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2487:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2489:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2493:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2495:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2499:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2501:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2505:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2507:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_8_4 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2511:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_8_4_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2513:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2517:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2519:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2523:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2525:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2529:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2531:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2535:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2537:25
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2541:21
pub const __AVAILABILITY_INTERNAL__IPHONE_8_4_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2542:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2543:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2544:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2546:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2550:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2552:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2556:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2558:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2562:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2564:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2568:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2570:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2574:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2576:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2580:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2582:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2586:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2588:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2592:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2593:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2594:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2595:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2597:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2601:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2603:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2607:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2609:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2613:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2615:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2619:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2621:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2625:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2627:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2631:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2633:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2637:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2638:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2639:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2640:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2642:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2646:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2648:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2652:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2654:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2658:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2660:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_9_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2664:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_9_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2666:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2670:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2672:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2676:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2677:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2678:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2679:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2681:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2685:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2687:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2691:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2693:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2697:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2699:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_9_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2703:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_9_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2705:25
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2709:21
pub const __AVAILABILITY_INTERNAL__IPHONE_9_3_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2710:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2711:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2712:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_0_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2714:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2718:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2720:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2724:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2726:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2730:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2732:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_11_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2736:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_12_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2737:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2738:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_0_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2739:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2740:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_1 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2741:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_1_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2743:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2747:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2749:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2753:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2755:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2759:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_1_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2760:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2761:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_10_2 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2762:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_10_2_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2764:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2768:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2770:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2774:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_2_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2775:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2776:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_3_DEP__IPHONE_10_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2777:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_3_DEP__IPHONE_10_3_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2779:25
pub const __AVAILABILITY_INTERNAL__IPHONE_10_3_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2783:21
pub const __AVAILABILITY_INTERNAL__IPHONE_10_3_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2784:21
pub const __AVAILABILITY_INTERNAL__IPHONE_11 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2785:21
pub const __AVAILABILITY_INTERNAL__IPHONE_11_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2786:21
pub const __AVAILABILITY_INTERNAL__IPHONE_11_3 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2787:21
pub const __AVAILABILITY_INTERNAL__IPHONE_12_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2788:21
pub const __AVAILABILITY_INTERNAL__IPHONE_13_0 = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2789:21
pub const __AVAILABILITY_INTERNAL__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2791:21
pub const __AVAILABILITY_INTERNAL__IPHONE_NA__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2792:21
pub const __AVAILABILITY_INTERNAL__IPHONE_NA_DEP__IPHONE_NA = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2793:21
pub const __AVAILABILITY_INTERNAL__IPHONE_NA_DEP__IPHONE_NA_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2794:21
pub const __AVAILABILITY_INTERNAL__IPHONE_COMPAT_VERSION = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2815:25
pub const __AVAILABILITY_INTERNAL__IPHONE_COMPAT_VERSION_DEP__IPHONE_COMPAT_VERSION = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2816:25
pub const __AVAILABILITY_INTERNAL__IPHONE_COMPAT_VERSION_DEP__IPHONE_COMPAT_VERSION_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternalLegacy.h:2818:25
pub const __API_AVAILABLE_PLATFORM_macos = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:180:12
pub const __API_DEPRECATED_PLATFORM_macos = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:181:12
pub const __API_UNAVAILABLE_PLATFORM_macos = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:182:12
pub const __API_AVAILABLE_PLATFORM_macosx = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:183:12
pub const __API_DEPRECATED_PLATFORM_macosx = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:184:12
pub const __API_UNAVAILABLE_PLATFORM_macosx = @compileError("unable to translate macro: undefined identifier `macos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:185:12
pub const __API_AVAILABLE_PLATFORM_ios = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:186:12
pub const __API_DEPRECATED_PLATFORM_ios = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:187:12
pub const __API_UNAVAILABLE_PLATFORM_ios = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:188:12
pub const __API_AVAILABLE_PLATFORM_macCatalyst = @compileError("unable to translate macro: undefined identifier `macCatalyst`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:192:12
pub const __API_DEPRECATED_PLATFORM_macCatalyst = @compileError("unable to translate macro: undefined identifier `macCatalyst`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:193:12
pub const __API_UNAVAILABLE_PLATFORM_macCatalyst = @compileError("unable to translate macro: undefined identifier `macCatalyst`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:194:12
pub const __API_AVAILABLE_PLATFORM_watchos = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:195:12
pub const __API_DEPRECATED_PLATFORM_watchos = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:196:12
pub const __API_UNAVAILABLE_PLATFORM_watchos = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:197:12
pub const __API_AVAILABLE_PLATFORM_tvos = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:198:12
pub const __API_DEPRECATED_PLATFORM_tvos = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:199:12
pub const __API_UNAVAILABLE_PLATFORM_tvos = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:200:12
pub const __API_AVAILABLE_PLATFORM_driverkit = @compileError("unable to translate macro: undefined identifier `driverkit`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:204:12
pub const __API_DEPRECATED_PLATFORM_driverkit = @compileError("unable to translate macro: undefined identifier `driverkit`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:205:12
pub const __API_UNAVAILABLE_PLATFORM_driverkit = @compileError("unable to translate macro: undefined identifier `driverkit`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:206:12
pub const __API_AVAILABLE_PLATFORM_visionos = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:207:12
pub const __API_DEPRECATED_PLATFORM_visionos = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:208:12
pub const __API_UNAVAILABLE_PLATFORM_visionos = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:209:12
pub const __API_AVAILABLE_PLATFORM_xros = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:210:12
pub const __API_DEPRECATED_PLATFORM_xros = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:211:12
pub const __API_UNAVAILABLE_PLATFORM_xros = @compileError("unable to translate macro: undefined identifier `visionos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:212:12
pub const __API_APPLY_TO = @compileError("unable to translate macro: undefined identifier `any`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:219:11
pub inline fn __API_RANGE_STRINGIFY(x: anytype) @TypeOf(__API_RANGE_STRINGIFY2(x)) {
    _ = &x;
    return __API_RANGE_STRINGIFY2(x);
}
pub const __API_RANGE_STRINGIFY2 = @compileError("unable to translate C expr: unexpected token ''"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:221:11
pub const __API_A = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:235:13
pub inline fn __API_AVAILABLE0(arg0: anytype) @TypeOf(__API_A(arg0)) {
    _ = &arg0;
    return __API_A(arg0);
}
pub inline fn __API_AVAILABLE1(arg0: anytype, arg1: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1)) {
    _ = &arg0;
    _ = &arg1;
    return __API_A(arg0) ++ __API_A(arg1);
}
pub inline fn __API_AVAILABLE2(arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2);
}
pub inline fn __API_AVAILABLE3(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3);
}
pub inline fn __API_AVAILABLE4(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4);
}
pub inline fn __API_AVAILABLE5(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5);
}
pub inline fn __API_AVAILABLE6(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6);
}
pub inline fn __API_AVAILABLE7(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6) ++ __API_A(arg7)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6) ++ __API_A(arg7);
}
pub inline fn __API_AVAILABLE8(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6) ++ __API_A(arg7) ++ __API_A(arg8)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_A(arg0) ++ __API_A(arg1) ++ __API_A(arg2) ++ __API_A(arg3) ++ __API_A(arg4) ++ __API_A(arg5) ++ __API_A(arg6) ++ __API_A(arg7) ++ __API_A(arg8);
}
pub inline fn __API_AVAILABLE_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &NAME;
    return NAME;
}
pub const __API_A_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:248:13
pub inline fn __API_AVAILABLE_BEGIN0(arg0: anytype) @TypeOf(__API_A_BEGIN(arg0)) {
    _ = &arg0;
    return __API_A_BEGIN(arg0);
}
pub inline fn __API_AVAILABLE_BEGIN1(arg0: anytype, arg1: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1)) {
    _ = &arg0;
    _ = &arg1;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1);
}
pub inline fn __API_AVAILABLE_BEGIN2(arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2);
}
pub inline fn __API_AVAILABLE_BEGIN3(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3);
}
pub inline fn __API_AVAILABLE_BEGIN4(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4);
}
pub inline fn __API_AVAILABLE_BEGIN5(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5);
}
pub inline fn __API_AVAILABLE_BEGIN6(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6);
}
pub inline fn __API_AVAILABLE_BEGIN7(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6) ++ __API_A_BEGIN(arg7)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6) ++ __API_A_BEGIN(arg7);
}
pub inline fn __API_AVAILABLE_BEGIN8(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6) ++ __API_A_BEGIN(arg7) ++ __API_A_BEGIN(arg8)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_A_BEGIN(arg0) ++ __API_A_BEGIN(arg1) ++ __API_A_BEGIN(arg2) ++ __API_A_BEGIN(arg3) ++ __API_A_BEGIN(arg4) ++ __API_A_BEGIN(arg5) ++ __API_A_BEGIN(arg6) ++ __API_A_BEGIN(arg7) ++ __API_A_BEGIN(arg8);
}
pub inline fn __API_AVAILABLE_BEGIN_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &NAME;
    return NAME;
}
pub const __API_D = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:263:13
pub inline fn __API_DEPRECATED_MSG0(msg: anytype, arg0: anytype) @TypeOf(__API_D(msg, arg0)) {
    _ = &msg;
    _ = &arg0;
    return __API_D(msg, arg0);
}
pub inline fn __API_DEPRECATED_MSG1(msg: anytype, arg0: anytype, arg1: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1);
}
pub inline fn __API_DEPRECATED_MSG2(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2);
}
pub inline fn __API_DEPRECATED_MSG3(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3);
}
pub inline fn __API_DEPRECATED_MSG4(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4);
}
pub inline fn __API_DEPRECATED_MSG5(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5);
}
pub inline fn __API_DEPRECATED_MSG6(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6);
}
pub inline fn __API_DEPRECATED_MSG7(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6) ++ __API_D(msg, arg7)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6) ++ __API_D(msg, arg7);
}
pub inline fn __API_DEPRECATED_MSG8(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6) ++ __API_D(msg, arg7) ++ __API_D(msg, arg8)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_D(msg, arg0) ++ __API_D(msg, arg1) ++ __API_D(msg, arg2) ++ __API_D(msg, arg3) ++ __API_D(msg, arg4) ++ __API_D(msg, arg5) ++ __API_D(msg, arg6) ++ __API_D(msg, arg7) ++ __API_D(msg, arg8);
}
pub inline fn __API_DEPRECATED_MSG_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, _9: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &_9;
    _ = &NAME;
    return NAME;
}
pub const __API_D_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:276:13
pub inline fn __API_DEPRECATED_BEGIN0(msg: anytype, arg0: anytype) @TypeOf(__API_D_BEGIN(msg, arg0)) {
    _ = &msg;
    _ = &arg0;
    return __API_D_BEGIN(msg, arg0);
}
pub inline fn __API_DEPRECATED_BEGIN1(msg: anytype, arg0: anytype, arg1: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1);
}
pub inline fn __API_DEPRECATED_BEGIN2(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2);
}
pub inline fn __API_DEPRECATED_BEGIN3(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3);
}
pub inline fn __API_DEPRECATED_BEGIN4(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4);
}
pub inline fn __API_DEPRECATED_BEGIN5(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5);
}
pub inline fn __API_DEPRECATED_BEGIN6(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6);
}
pub inline fn __API_DEPRECATED_BEGIN7(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6) ++ __API_D_BEGIN(msg, arg7)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6) ++ __API_D_BEGIN(msg, arg7);
}
pub inline fn __API_DEPRECATED_BEGIN8(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6) ++ __API_D_BEGIN(msg, arg7) ++ __API_D_BEGIN(msg, arg8)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_D_BEGIN(msg, arg0) ++ __API_D_BEGIN(msg, arg1) ++ __API_D_BEGIN(msg, arg2) ++ __API_D_BEGIN(msg, arg3) ++ __API_D_BEGIN(msg, arg4) ++ __API_D_BEGIN(msg, arg5) ++ __API_D_BEGIN(msg, arg6) ++ __API_D_BEGIN(msg, arg7) ++ __API_D_BEGIN(msg, arg8);
}
pub inline fn __API_DEPRECATED_BEGIN_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, _9: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &_9;
    _ = &NAME;
    return NAME;
}
pub const __API_R = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:290:17
pub inline fn __API_DEPRECATED_REP0(msg: anytype, arg0: anytype) @TypeOf(__API_R(msg, arg0)) {
    _ = &msg;
    _ = &arg0;
    return __API_R(msg, arg0);
}
pub inline fn __API_DEPRECATED_REP1(msg: anytype, arg0: anytype, arg1: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1);
}
pub inline fn __API_DEPRECATED_REP2(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2);
}
pub inline fn __API_DEPRECATED_REP3(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3);
}
pub inline fn __API_DEPRECATED_REP4(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4);
}
pub inline fn __API_DEPRECATED_REP5(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5);
}
pub inline fn __API_DEPRECATED_REP6(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6);
}
pub inline fn __API_DEPRECATED_REP7(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6) ++ __API_R(msg, arg7)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6) ++ __API_R(msg, arg7);
}
pub inline fn __API_DEPRECATED_REP8(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6) ++ __API_R(msg, arg7) ++ __API_R(msg, arg8)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_R(msg, arg0) ++ __API_R(msg, arg1) ++ __API_R(msg, arg2) ++ __API_R(msg, arg3) ++ __API_R(msg, arg4) ++ __API_R(msg, arg5) ++ __API_R(msg, arg6) ++ __API_R(msg, arg7) ++ __API_R(msg, arg8);
}
pub inline fn __API_DEPRECATED_REP_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, _9: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &_9;
    _ = &NAME;
    return NAME;
}
pub const __API_R_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:307:17
pub inline fn __API_DEPRECATED_BEGIN_REP0(msg: anytype, arg0: anytype) @TypeOf(__API_R_BEGIN(msg, arg0)) {
    _ = &msg;
    _ = &arg0;
    return __API_R_BEGIN(msg, arg0);
}
pub inline fn __API_DEPRECATED_BEGIN_REP1(msg: anytype, arg0: anytype, arg1: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1);
}
pub inline fn __API_DEPRECATED_BEGIN_REP2(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2);
}
pub inline fn __API_DEPRECATED_BEGIN_REP3(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3);
}
pub inline fn __API_DEPRECATED_BEGIN_REP4(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4);
}
pub inline fn __API_DEPRECATED_BEGIN_REP5(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5);
}
pub inline fn __API_DEPRECATED_BEGIN_REP6(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6);
}
pub inline fn __API_DEPRECATED_BEGIN_REP7(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6) ++ __API_R_BEGIN(msg, arg7)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6) ++ __API_R_BEGIN(msg, arg7);
}
pub inline fn __API_DEPRECATED_BEGIN_REP8(msg: anytype, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6) ++ __API_R_BEGIN(msg, arg7) ++ __API_R_BEGIN(msg, arg8)) {
    _ = &msg;
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_R_BEGIN(msg, arg0) ++ __API_R_BEGIN(msg, arg1) ++ __API_R_BEGIN(msg, arg2) ++ __API_R_BEGIN(msg, arg3) ++ __API_R_BEGIN(msg, arg4) ++ __API_R_BEGIN(msg, arg5) ++ __API_R_BEGIN(msg, arg6) ++ __API_R_BEGIN(msg, arg7) ++ __API_R_BEGIN(msg, arg8);
}
pub inline fn __API_DEPRECATED_BEGIN_REP_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, _9: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &_9;
    _ = &NAME;
    return NAME;
}
pub const __API_U = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:332:13
pub inline fn __API_UNAVAILABLE0(arg0: anytype) @TypeOf(__API_U(arg0)) {
    _ = &arg0;
    return __API_U(arg0);
}
pub inline fn __API_UNAVAILABLE1(arg0: anytype, arg1: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1)) {
    _ = &arg0;
    _ = &arg1;
    return __API_U(arg0) ++ __API_U(arg1);
}
pub inline fn __API_UNAVAILABLE2(arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2);
}
pub inline fn __API_UNAVAILABLE3(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3);
}
pub inline fn __API_UNAVAILABLE4(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4);
}
pub inline fn __API_UNAVAILABLE5(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5);
}
pub inline fn __API_UNAVAILABLE6(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6);
}
pub inline fn __API_UNAVAILABLE7(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6) ++ __API_U(arg7)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6) ++ __API_U(arg7);
}
pub inline fn __API_UNAVAILABLE8(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6) ++ __API_U(arg7) ++ __API_U(arg8)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_U(arg0) ++ __API_U(arg1) ++ __API_U(arg2) ++ __API_U(arg3) ++ __API_U(arg4) ++ __API_U(arg5) ++ __API_U(arg6) ++ __API_U(arg7) ++ __API_U(arg8);
}
pub inline fn __API_UNAVAILABLE_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &NAME;
    return NAME;
}
pub const __API_U_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/AvailabilityInternal.h:345:13
pub inline fn __API_UNAVAILABLE_BEGIN0(arg0: anytype) @TypeOf(__API_U_BEGIN(arg0)) {
    _ = &arg0;
    return __API_U_BEGIN(arg0);
}
pub inline fn __API_UNAVAILABLE_BEGIN1(arg0: anytype, arg1: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1)) {
    _ = &arg0;
    _ = &arg1;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1);
}
pub inline fn __API_UNAVAILABLE_BEGIN2(arg0: anytype, arg1: anytype, arg2: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2);
}
pub inline fn __API_UNAVAILABLE_BEGIN3(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3);
}
pub inline fn __API_UNAVAILABLE_BEGIN4(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4);
}
pub inline fn __API_UNAVAILABLE_BEGIN5(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5);
}
pub inline fn __API_UNAVAILABLE_BEGIN6(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6);
}
pub inline fn __API_UNAVAILABLE_BEGIN7(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6) ++ __API_U_BEGIN(arg7)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6) ++ __API_U_BEGIN(arg7);
}
pub inline fn __API_UNAVAILABLE_BEGIN8(arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype, arg4: anytype, arg5: anytype, arg6: anytype, arg7: anytype, arg8: anytype) @TypeOf(__API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6) ++ __API_U_BEGIN(arg7) ++ __API_U_BEGIN(arg8)) {
    _ = &arg0;
    _ = &arg1;
    _ = &arg2;
    _ = &arg3;
    _ = &arg4;
    _ = &arg5;
    _ = &arg6;
    _ = &arg7;
    _ = &arg8;
    return __API_U_BEGIN(arg0) ++ __API_U_BEGIN(arg1) ++ __API_U_BEGIN(arg2) ++ __API_U_BEGIN(arg3) ++ __API_U_BEGIN(arg4) ++ __API_U_BEGIN(arg5) ++ __API_U_BEGIN(arg6) ++ __API_U_BEGIN(arg7) ++ __API_U_BEGIN(arg8);
}
pub inline fn __API_UNAVAILABLE_BEGIN_GET_MACRO(_0: anytype, _1: anytype, _2: anytype, _3: anytype, _4: anytype, _5: anytype, _6: anytype, _7: anytype, _8: anytype, NAME: anytype) @TypeOf(NAME) {
    _ = &_0;
    _ = &_1;
    _ = &_2;
    _ = &_3;
    _ = &_4;
    _ = &_5;
    _ = &_6;
    _ = &_7;
    _ = &_8;
    _ = &NAME;
    return NAME;
}
pub inline fn __swift_compiler_version_at_least() @TypeOf(@as(c_int, 1)) {
    return @as(c_int, 1);
}
pub inline fn __SPI_AVAILABLE() void {
    return;
}
pub inline fn __SPI_AVAILABLE_BEGIN() void {
    return;
}
pub inline fn __SPI_AVAILABLE_END() void {
    return;
}
pub const __OSX_AVAILABLE_STARTING = @compileError("unable to translate macro: undefined identifier `__AVAILABILITY_INTERNAL`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:180:13
pub const __OSX_AVAILABLE_BUT_DEPRECATED = @compileError("unable to translate macro: undefined identifier `__AVAILABILITY_INTERNAL`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:181:13
pub const __OSX_AVAILABLE_BUT_DEPRECATED_MSG = @compileError("unable to translate macro: undefined identifier `__AVAILABILITY_INTERNAL`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:183:13
pub const __OS_AVAILABILITY = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:239:13
pub const __OS_AVAILABILITY_MSG = @compileError("unable to translate macro: undefined identifier `availability`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:240:13
pub const __OSX_EXTENSION_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `macosx_app_extension`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:257:13
pub const __IOS_EXTENSION_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `ios_app_extension`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:258:13
pub inline fn __OS_EXTENSION_UNAVAILABLE(_msg: anytype) @TypeOf(__OSX_EXTENSION_UNAVAILABLE(_msg) ++ __IOS_EXTENSION_UNAVAILABLE(_msg)) {
    _ = &_msg;
    return __OSX_EXTENSION_UNAVAILABLE(_msg) ++ __IOS_EXTENSION_UNAVAILABLE(_msg);
}
pub const __OSX_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `macosx`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:275:13
pub const __OSX_AVAILABLE = @compileError("unable to translate macro: undefined identifier `macosx`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:276:13
pub const __OSX_DEPRECATED = @compileError("unable to translate macro: undefined identifier `macosx`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:277:13
pub const __IOS_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:301:13
pub const __IOS_PROHIBITED = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:303:15
pub const __IOS_AVAILABLE = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:305:13
pub const __IOS_DEPRECATED = @compileError("unable to translate macro: undefined identifier `ios`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:306:13
pub const __TVOS_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:330:13
pub const __TVOS_PROHIBITED = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:332:15
pub const __TVOS_AVAILABLE = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:334:13
pub const __TVOS_DEPRECATED = @compileError("unable to translate macro: undefined identifier `tvos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:335:13
pub const __WATCHOS_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:359:13
pub const __WATCHOS_PROHIBITED = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:361:15
pub const __WATCHOS_AVAILABLE = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:363:13
pub const __WATCHOS_DEPRECATED = @compileError("unable to translate macro: undefined identifier `watchos`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:364:13
pub const __SWIFT_UNAVAILABLE = @compileError("unable to translate macro: undefined identifier `swift`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:387:13
pub const __SWIFT_UNAVAILABLE_MSG = @compileError("unable to translate macro: undefined identifier `swift`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:388:13
pub const __API_AVAILABLE = @compileError("unable to translate C expr: unexpected token '__VA_ARGS__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:431:13
pub const __API_AVAILABLE_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:433:13
pub const __API_AVAILABLE_END = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:434:13
pub const __API_DEPRECATED = @compileError("unable to translate C expr: unexpected token '__VA_ARGS__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:452:13
pub const __API_DEPRECATED_WITH_REPLACEMENT = @compileError("unable to translate C expr: unexpected token '__VA_ARGS__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:453:13
pub const __API_DEPRECATED_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:455:13
pub const __API_DEPRECATED_END = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:456:13
pub const __API_DEPRECATED_WITH_REPLACEMENT_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:458:13
pub const __API_DEPRECATED_WITH_REPLACEMENT_END = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:459:13
pub const __API_UNAVAILABLE = @compileError("unable to translate C expr: unexpected token '__VA_ARGS__'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:469:13
pub const __API_UNAVAILABLE_BEGIN = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:471:13
pub const __API_UNAVAILABLE_END = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Availability.h:472:13
pub inline fn __SPI_DEPRECATED() void {
    return;
}
pub inline fn __SPI_DEPRECATED_WITH_REPLACEMENT() void {
    return;
}
pub const __TYPES_H_ = "";
pub const _SYS__TYPES_H_ = "";
pub const _BSD_MACHINE__TYPES_H_ = "";
pub const _BSD_ARM__TYPES_H_ = "";
pub const __DARWIN_NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const _SYS__PTHREAD_TYPES_H_ = "";
pub const __PTHREAD_SIZE__ = @as(c_int, 8176);
pub const __PTHREAD_ATTR_SIZE__ = @as(c_int, 56);
pub const __PTHREAD_MUTEXATTR_SIZE__ = @as(c_int, 8);
pub const __PTHREAD_MUTEX_SIZE__ = @as(c_int, 56);
pub const __PTHREAD_CONDATTR_SIZE__ = @as(c_int, 8);
pub const __PTHREAD_COND_SIZE__ = @as(c_int, 40);
pub const __PTHREAD_ONCE_SIZE__ = @as(c_int, 8);
pub const __PTHREAD_RWLOCK_SIZE__ = @as(c_int, 192);
pub const __PTHREAD_RWLOCKATTR_SIZE__ = @as(c_int, 16);
pub const __offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_types.h:83:9
pub const __strfmonlike = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/_types.h:31:9
pub const __strftimelike = @compileError("unable to translate macro: undefined identifier `__format__`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/_types.h:33:9
pub const __DARWIN_WCHAR_MAX = __WCHAR_MAX__;
pub const __DARWIN_WCHAR_MIN = -__helpers.promoteIntLiteral(c_int, 0x7fffffff, .hex) - @as(c_int, 1);
pub const __DARWIN_WEOF = __helpers.cast(__darwin_wint_t, -@as(c_int, 1));
pub const _VA_LIST_T = "";
pub const _BSD_MACHINE_TYPES_H_ = "";
pub const _ARM_MACHTYPES_H_ = "";
pub const _MACHTYPES_H_ = "";
pub const _INT8_T = "";
pub const _INT16_T = "";
pub const _INT32_T = "";
pub const _INT64_T = "";
pub const _U_INT8_T = "";
pub const _U_INT16_T = "";
pub const _U_INT32_T = "";
pub const _U_INT64_T = "";
pub const _INTPTR_T = "";
pub const _UINTPTR_T = "";
pub const USER_ADDR_NULL = __helpers.cast(user_addr_t, @as(c_int, 0));
pub inline fn CAST_USER_ADDR_T(a_ptr: anytype) user_addr_t {
    _ = &a_ptr;
    return __helpers.cast(user_addr_t, __helpers.cast(usize, a_ptr));
}
pub const _SIZE_T = "";
pub const NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const _SYS_STDIO_H_ = "";
pub const RENAME_SECLUDE = @as(c_int, 0x00000001);
pub const RENAME_SWAP = @as(c_int, 0x00000002);
pub const RENAME_EXCL = @as(c_int, 0x00000004);
pub const RENAME_RESERVED1 = @as(c_int, 0x00000008);
pub const RENAME_NOFOLLOW_ANY = @as(c_int, 0x00000010);
pub const _FSTDIO = "";
pub const _SEEK_SET_H_ = "";
pub const SEEK_SET = @as(c_int, 0);
pub const SEEK_CUR = @as(c_int, 1);
pub const SEEK_END = @as(c_int, 2);
pub const SEEK_HOLE = @as(c_int, 3);
pub const SEEK_DATA = @as(c_int, 4);
pub const __SLBF = @as(c_int, 0x0001);
pub const __SNBF = @as(c_int, 0x0002);
pub const __SRD = @as(c_int, 0x0004);
pub const __SWR = @as(c_int, 0x0008);
pub const __SRW = @as(c_int, 0x0010);
pub const __SEOF = @as(c_int, 0x0020);
pub const __SERR = @as(c_int, 0x0040);
pub const __SMBF = @as(c_int, 0x0080);
pub const __SAPP = @as(c_int, 0x0100);
pub const __SSTR = @as(c_int, 0x0200);
pub const __SOPT = @as(c_int, 0x0400);
pub const __SNPT = @as(c_int, 0x0800);
pub const __SOFF = @as(c_int, 0x1000);
pub const __SMOD = @as(c_int, 0x2000);
pub const __SALC = @as(c_int, 0x4000);
pub const __SIGN = __helpers.promoteIntLiteral(c_int, 0x8000, .hex);
pub const _IOFBF = @as(c_int, 0);
pub const _IOLBF = @as(c_int, 1);
pub const _IONBF = @as(c_int, 2);
pub const BUFSIZ = @as(c_int, 1024);
pub const EOF = -@as(c_int, 1);
pub const FOPEN_MAX = @as(c_int, 20);
pub const FILENAME_MAX = @as(c_int, 1024);
pub const P_tmpdir = "/var/tmp/";
pub const L_tmpnam = @as(c_int, 1024);
pub const TMP_MAX = __helpers.promoteIntLiteral(c_int, 308915776, .decimal);
// /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/stdio.h:119:9: warning: macro 'stdin' contains a runtime value, translated to function
pub inline fn stdin() @TypeOf(__stdinp) {
    return __stdinp;
}
// /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/stdio.h:120:9: warning: macro 'stdout' contains a runtime value, translated to function
pub inline fn stdout() @TypeOf(__stdoutp) {
    return __stdoutp;
}
// /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/stdio.h:121:9: warning: macro 'stderr' contains a runtime value, translated to function
pub inline fn stderr() @TypeOf(__stderrp) {
    return __stderrp;
}
pub const L_ctermid = @as(c_int, 1024);
pub const _CTERMID_H_ = "";
pub const __sgetc = @compileError("TODO unary inc/dec expr"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/stdio.h:261:9
pub inline fn __sfeof(p: anytype) @TypeOf((p.*._flags & __SEOF) != @as(c_int, 0)) {
    _ = &p;
    return (p.*._flags & __SEOF) != @as(c_int, 0);
}
pub inline fn __sferror(p: anytype) @TypeOf((p.*._flags & __SERR) != @as(c_int, 0)) {
    _ = &p;
    return (p.*._flags & __SERR) != @as(c_int, 0);
}
pub const __sclearerr = @compileError("unable to translate C expr: expected ')' instead got '&='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/stdio.h:285:9
pub inline fn __sfileno(p: anytype) @TypeOf(p.*._file) {
    _ = &p;
    return p.*._file;
}
pub const _OFF_T = "";
pub const _SSIZE_T = "";
pub inline fn fropen(cookie: anytype, @"fn": anytype) @TypeOf(funopen(cookie, @"fn", @as(c_int, 0), @as(c_int, 0), @as(c_int, 0))) {
    _ = &cookie;
    _ = &@"fn";
    return funopen(cookie, @"fn", @as(c_int, 0), @as(c_int, 0), @as(c_int, 0));
}
pub inline fn fwopen(cookie: anytype, @"fn": anytype) @TypeOf(funopen(cookie, @as(c_int, 0), @"fn", @as(c_int, 0), @as(c_int, 0))) {
    _ = &cookie;
    _ = &@"fn";
    return funopen(cookie, @as(c_int, 0), @"fn", @as(c_int, 0), @as(c_int, 0));
}
pub inline fn feof_unlocked(p: anytype) @TypeOf(__sfeof(p)) {
    _ = &p;
    return __sfeof(p);
}
pub inline fn ferror_unlocked(p: anytype) @TypeOf(__sferror(p)) {
    _ = &p;
    return __sferror(p);
}
pub inline fn clearerr_unlocked(p: anytype) @TypeOf(__sclearerr(p)) {
    _ = &p;
    return __sclearerr(p);
}
pub inline fn fileno_unlocked(p: anytype) @TypeOf(__sfileno(p)) {
    _ = &p;
    return __sfileno(p);
}
pub const _SECURE__STDIO_H_ = "";
pub const _SECURE__COMMON_H_ = "";
pub const _USE_FORTIFY_LEVEL = @as(c_int, 2);
pub inline fn __darwin_obsz0(object: anytype) @TypeOf(__builtin.object_size(object, @as(c_int, 0))) {
    _ = &object;
    return __builtin.object_size(object, @as(c_int, 0));
}
pub inline fn __darwin_obsz(object: anytype) @TypeOf(__builtin.object_size(object, if (_USE_FORTIFY_LEVEL > @as(c_int, 1)) @as(c_int, 1) else @as(c_int, 0))) {
    _ = &object;
    return __builtin.object_size(object, if (_USE_FORTIFY_LEVEL > @as(c_int, 1)) @as(c_int, 1) else @as(c_int, 0));
}
pub const _OGG_H = "";
pub const __STDC_VERSION_STDDEF_H__ = @as(c_long, 202311);
pub const offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // .tools/zig-aarch64-macos-0.16.0-dev.3142+5ccfeb926/lib/compiler/aro/include/stddef.h:18:9
pub const _OS_TYPES_H = "";
pub const _ogg_malloc = @compileError("unable to translate macro: undefined identifier `malloc`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/ogg/os_types.h:21:9
pub const _ogg_calloc = @compileError("unable to translate macro: undefined identifier `calloc`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/ogg/os_types.h:22:9
pub const _ogg_realloc = @compileError("unable to translate macro: undefined identifier `realloc`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/ogg/os_types.h:23:9
pub const _ogg_free = @compileError("unable to translate macro: undefined identifier `free`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/ogg/os_types.h:24:9
pub const _SYS_TYPES_H_ = "";
pub const __SYS_APPLEAPIOPTS_H__ = "";
pub const __APPLE_API_STANDARD = "";
pub const __APPLE_API_STABLE = "";
pub const __APPLE_API_EVOLVING = "";
pub const __APPLE_API_UNSTABLE = "";
pub const __APPLE_API_PRIVATE = "";
pub const __APPLE_API_OBSOLETE = "";
pub const _BSD_MACHINE_ENDIAN_H_ = "";
pub const _ARM__ENDIAN_H_ = "";
pub const _QUAD_HIGHWORD = @as(c_int, 1);
pub const _QUAD_LOWWORD = @as(c_int, 0);
pub const __DARWIN_LITTLE_ENDIAN = @as(c_int, 1234);
pub const __DARWIN_BIG_ENDIAN = @as(c_int, 4321);
pub const __DARWIN_PDP_ENDIAN = @as(c_int, 3412);
pub const __DARWIN_BYTE_ORDER = __DARWIN_LITTLE_ENDIAN;
pub const LITTLE_ENDIAN = __DARWIN_LITTLE_ENDIAN;
pub const BIG_ENDIAN = __DARWIN_BIG_ENDIAN;
pub const PDP_ENDIAN = __DARWIN_PDP_ENDIAN;
pub const BYTE_ORDER = __DARWIN_BYTE_ORDER;
pub const _SYS__ENDIAN_H_ = "";
pub const _OS__OSBYTEORDER_H = "";
pub inline fn __DARWIN_OSSwapConstInt16(x: anytype) __uint16_t {
    _ = &x;
    return __helpers.cast(__uint16_t, ((__helpers.cast(__uint16_t, x) & @as(c_uint, 0xff00)) >> @as(c_int, 8)) | ((__helpers.cast(__uint16_t, x) & @as(c_uint, 0x00ff)) << @as(c_int, 8)));
}
pub inline fn __DARWIN_OSSwapConstInt32(x: anytype) __uint32_t {
    _ = &x;
    return __helpers.cast(__uint32_t, ((((__helpers.cast(__uint32_t, x) & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((__helpers.cast(__uint32_t, x) & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((__helpers.cast(__uint32_t, x) & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((__helpers.cast(__uint32_t, x) & @as(c_uint, 0x000000ff)) << @as(c_int, 24)));
}
pub inline fn __DARWIN_OSSwapConstInt64(x: anytype) __uint64_t {
    _ = &x;
    return __helpers.cast(__uint64_t, ((((((((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((__helpers.cast(__uint64_t, x) & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56)));
}
pub const __DARWIN_OS_INLINE = @compileError("unable to translate C expr: unexpected token 'static'"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/libkern/_OSByteOrder.h:67:17
pub const _OS_OSBYTEORDERARM_H = "";
pub const __CLANG_STDINT_H = "";
pub const _STDINT_H_ = "";
pub const __WORDSIZE = @as(c_int, 64);
pub const _UINT8_T = "";
pub const _UINT16_T = "";
pub const _UINT32_T = "";
pub const _UINT64_T = "";
pub const _INTMAX_T = "";
pub const _UINTMAX_T = "";
pub inline fn INT8_C(v: anytype) @TypeOf(v) {
    _ = &v;
    return v;
}
pub inline fn INT16_C(v: anytype) @TypeOf(v) {
    _ = &v;
    return v;
}
pub inline fn INT32_C(v: anytype) @TypeOf(v) {
    _ = &v;
    return v;
}
pub const INT64_C = __helpers.LL_SUFFIX;
pub inline fn UINT8_C(v: anytype) @TypeOf(v) {
    _ = &v;
    return v;
}
pub inline fn UINT16_C(v: anytype) @TypeOf(v) {
    _ = &v;
    return v;
}
pub const UINT32_C = __helpers.U_SUFFIX;
pub const UINT64_C = __helpers.ULL_SUFFIX;
pub const INTMAX_C = __helpers.L_SUFFIX;
pub const UINTMAX_C = __helpers.UL_SUFFIX;
pub const INT8_MAX = @as(c_int, 127);
pub const INT16_MAX = @as(c_int, 32767);
pub const INT32_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT64_MAX = @as(c_longlong, 9223372036854775807);
pub const INT8_MIN = -@as(c_int, 128);
pub const INT16_MIN = -__helpers.promoteIntLiteral(c_int, 32768, .decimal);
pub const INT32_MIN = -INT32_MAX - @as(c_int, 1);
pub const INT64_MIN = -INT64_MAX - @as(c_int, 1);
pub const UINT8_MAX = @as(c_int, 255);
pub const UINT16_MAX = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT32_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT64_MAX = @as(c_ulonglong, 18446744073709551615);
pub const INT_LEAST8_MIN = INT8_MIN;
pub const INT_LEAST16_MIN = INT16_MIN;
pub const INT_LEAST32_MIN = INT32_MIN;
pub const INT_LEAST64_MIN = INT64_MIN;
pub const INT_LEAST8_MAX = INT8_MAX;
pub const INT_LEAST16_MAX = INT16_MAX;
pub const INT_LEAST32_MAX = INT32_MAX;
pub const INT_LEAST64_MAX = INT64_MAX;
pub const UINT_LEAST8_MAX = UINT8_MAX;
pub const UINT_LEAST16_MAX = UINT16_MAX;
pub const UINT_LEAST32_MAX = UINT32_MAX;
pub const UINT_LEAST64_MAX = UINT64_MAX;
pub const INT_FAST8_MIN = INT8_MIN;
pub const INT_FAST16_MIN = INT16_MIN;
pub const INT_FAST32_MIN = INT32_MIN;
pub const INT_FAST64_MIN = INT64_MIN;
pub const INT_FAST8_MAX = INT8_MAX;
pub const INT_FAST16_MAX = INT16_MAX;
pub const INT_FAST32_MAX = INT32_MAX;
pub const INT_FAST64_MAX = INT64_MAX;
pub const UINT_FAST8_MAX = UINT8_MAX;
pub const UINT_FAST16_MAX = UINT16_MAX;
pub const UINT_FAST32_MAX = UINT32_MAX;
pub const UINT_FAST64_MAX = UINT64_MAX;
pub const INTPTR_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INTPTR_MIN = -INTPTR_MAX - @as(c_int, 1);
pub const UINTPTR_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const INTMAX_MAX = INTMAX_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINTMAX_MAX = UINTMAX_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INTMAX_MIN = -INTMAX_MAX - @as(c_int, 1);
pub const PTRDIFF_MIN = INTMAX_MIN;
pub const PTRDIFF_MAX = INTMAX_MAX;
pub const SIZE_MAX = UINTPTR_MAX;
pub const RSIZE_MAX = SIZE_MAX >> @as(c_int, 1);
pub const WCHAR_MAX = __WCHAR_MAX__;
pub const WCHAR_MIN = -WCHAR_MAX - @as(c_int, 1);
pub const WINT_MIN = INT32_MIN;
pub const WINT_MAX = INT32_MAX;
pub const SIG_ATOMIC_MIN = INT32_MIN;
pub const SIG_ATOMIC_MAX = INT32_MAX;
pub const _ARM_ARCH_H = "";
pub inline fn __DARWIN_OSSwapInt16(x: anytype) __uint16_t {
    _ = &x;
    return __helpers.cast(__uint16_t, if (__builtin.constant_p(x)) __DARWIN_OSSwapConstInt16(x) else _OSSwapInt16(x));
}
pub inline fn __DARWIN_OSSwapInt32(x: anytype) @TypeOf(if (__builtin.constant_p(x)) __DARWIN_OSSwapConstInt32(x) else _OSSwapInt32(x)) {
    _ = &x;
    return if (__builtin.constant_p(x)) __DARWIN_OSSwapConstInt32(x) else _OSSwapInt32(x);
}
pub inline fn __DARWIN_OSSwapInt64(x: anytype) @TypeOf(if (__builtin.constant_p(x)) __DARWIN_OSSwapConstInt64(x) else _OSSwapInt64(x)) {
    _ = &x;
    return if (__builtin.constant_p(x)) __DARWIN_OSSwapConstInt64(x) else _OSSwapInt64(x);
}
pub inline fn ntohs(x: anytype) @TypeOf(__DARWIN_OSSwapInt16(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt16(x);
}
pub inline fn htons(x: anytype) @TypeOf(__DARWIN_OSSwapInt16(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt16(x);
}
pub inline fn ntohl(x: anytype) @TypeOf(__DARWIN_OSSwapInt32(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt32(x);
}
pub inline fn htonl(x: anytype) @TypeOf(__DARWIN_OSSwapInt32(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt32(x);
}
pub inline fn ntohll(x: anytype) @TypeOf(__DARWIN_OSSwapInt64(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt64(x);
}
pub inline fn htonll(x: anytype) @TypeOf(__DARWIN_OSSwapInt64(x)) {
    _ = &x;
    return __DARWIN_OSSwapInt64(x);
}
pub const NTOHL = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:144:9
pub const NTOHS = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:145:9
pub const NTOHLL = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:146:9
pub const HTONL = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:147:9
pub const HTONS = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:148:9
pub const HTONLL = @compileError("unable to translate C expr: unexpected token '='"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_endian.h:149:9
pub const _U_CHAR = "";
pub const _U_SHORT = "";
pub const _U_INT = "";
pub const _U_LONG = "";
pub const __DARWIN_UINT = "";
pub const _CADDR_T = "";
pub const _DEV_T = "";
pub const _BLKCNT_T = "";
pub const _BLKSIZE_T = "";
pub const _GID_T = "";
pub const _IN_ADDR_T = "";
pub const _IN_PORT_T = "";
pub const _INO_T = "";
pub const _INO64_T = "";
pub const _KEY_T = "";
pub const _MODE_T = "";
pub const _NLINK_T = "";
pub const _ID_T = "";
pub const _PID_T = "";
pub const _UID_T = "";
pub inline fn major(x: anytype) i32 {
    _ = &x;
    return __helpers.cast(i32, (__helpers.cast(u_int32_t, x) >> @as(c_int, 24)) & @as(c_int, 0xff));
}
pub inline fn minor(x: anytype) i32 {
    _ = &x;
    return __helpers.cast(i32, x & __helpers.promoteIntLiteral(c_int, 0xffffff, .hex));
}
pub inline fn makedev(x: anytype, y: anytype) dev_t {
    _ = &x;
    _ = &y;
    return __helpers.cast(dev_t, (x << @as(c_int, 24)) | y);
}
pub const _CLOCK_T = "";
pub const _TIME_T = "";
pub const _USECONDS_T = "";
pub const _SUSECONDS_T = "";
pub const _RSIZE_T = "";
pub const _ERRNO_T = "";
pub const _FD_SET = "";
pub const __DARWIN_FD_SETSIZE = @as(c_int, 1024);
pub const __DARWIN_NBBY = @as(c_int, 8);
pub const __DARWIN_NFDBITS = __helpers.sizeof(__int32_t) * __DARWIN_NBBY;
pub inline fn __DARWIN_howmany(x: anytype, y: anytype) @TypeOf(if (__helpers.rem(x, y) == @as(c_int, 0)) __helpers.div(x, y) else __helpers.div(x, y) + @as(c_int, 1)) {
    _ = &x;
    _ = &y;
    return if (__helpers.rem(x, y) == @as(c_int, 0)) __helpers.div(x, y) else __helpers.div(x, y) + @as(c_int, 1);
}
pub inline fn __DARWIN_FD_SET(n: anytype, p: anytype) @TypeOf(__darwin_fd_set(n, p)) {
    _ = &n;
    _ = &p;
    return __darwin_fd_set(n, p);
}
pub inline fn __DARWIN_FD_CLR(n: anytype, p: anytype) @TypeOf(__darwin_fd_clr(n, p)) {
    _ = &n;
    _ = &p;
    return __darwin_fd_clr(n, p);
}
pub inline fn __DARWIN_FD_ISSET(n: anytype, p: anytype) @TypeOf(__darwin_fd_isset(n, p)) {
    _ = &n;
    _ = &p;
    return __darwin_fd_isset(n, p);
}
pub const __DARWIN_FD_ZERO = @compileError("unable to translate macro: undefined identifier `__builtin_bzero`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_types/_fd_def.h:115:9
pub const __DARWIN_FD_COPY = @compileError("unable to translate macro: undefined identifier `bcopy`"); // /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/_types/_fd_def.h:120:9
pub const NBBY = __DARWIN_NBBY;
pub const NFDBITS = __DARWIN_NFDBITS;
pub inline fn howmany(x: anytype, y: anytype) @TypeOf(__DARWIN_howmany(x, y)) {
    _ = &x;
    _ = &y;
    return __DARWIN_howmany(x, y);
}
pub const FD_SETSIZE = __DARWIN_FD_SETSIZE;
pub inline fn FD_SET(n: anytype, p: anytype) @TypeOf(__DARWIN_FD_SET(n, p)) {
    _ = &n;
    _ = &p;
    return __DARWIN_FD_SET(n, p);
}
pub inline fn FD_CLR(n: anytype, p: anytype) @TypeOf(__DARWIN_FD_CLR(n, p)) {
    _ = &n;
    _ = &p;
    return __DARWIN_FD_CLR(n, p);
}
pub inline fn FD_ZERO(p: anytype) @TypeOf(__DARWIN_FD_ZERO(p)) {
    _ = &p;
    return __DARWIN_FD_ZERO(p);
}
pub inline fn FD_ISSET(n: anytype, p: anytype) @TypeOf(__DARWIN_FD_ISSET(n, p)) {
    _ = &n;
    _ = &p;
    return __DARWIN_FD_ISSET(n, p);
}
pub inline fn FD_COPY(f: anytype, t: anytype) @TypeOf(__DARWIN_FD_COPY(f, t)) {
    _ = &f;
    _ = &t;
    return __DARWIN_FD_COPY(f, t);
}
pub const _PTHREAD_ATTR_T = "";
pub const _PTHREAD_COND_T = "";
pub const _PTHREAD_CONDATTR_T = "";
pub const _PTHREAD_MUTEX_T = "";
pub const _PTHREAD_MUTEXATTR_T = "";
pub const _PTHREAD_ONCE_T = "";
pub const _PTHREAD_RWLOCK_T = "";
pub const _PTHREAD_RWLOCKATTR_T = "";
pub const _PTHREAD_T = "";
pub const _PTHREAD_KEY_T = "";
pub const _FSBLKCNT_T = "";
pub const _FSFILCNT_T = "";
pub const OPUS_MULTISTREAM_H = "";
pub const OPUS_H = "";
pub const OPUS_TYPES_H = "";
pub const opus_int = c_int;
pub const opus_uint = c_uint;
pub const OPUS_DEFINES_H = "";
pub const OPUS_OK = @as(c_int, 0);
pub const OPUS_BAD_ARG = -@as(c_int, 1);
pub const OPUS_BUFFER_TOO_SMALL = -@as(c_int, 2);
pub const OPUS_INTERNAL_ERROR = -@as(c_int, 3);
pub const OPUS_INVALID_PACKET = -@as(c_int, 4);
pub const OPUS_UNIMPLEMENTED = -@as(c_int, 5);
pub const OPUS_INVALID_STATE = -@as(c_int, 6);
pub const OPUS_ALLOC_FAIL = -@as(c_int, 7);
pub const OPUS_EXPORT = "";
pub inline fn OPUS_GNUC_PREREQ(_maj: anytype, _min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((_maj << @as(c_int, 16)) + _min)) {
    _ = &_maj;
    _ = &_min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((_maj << @as(c_int, 16)) + _min);
}
pub const OPUS_RESTRICT = @compileError("unable to translate C expr: unexpected token 'restrict'"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_defines.h:98:10
pub const OPUS_INLINE = @compileError("unable to translate C expr: unexpected token 'inline'"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_defines.h:110:10
pub const OPUS_WARN_UNUSED_RESULT = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_defines.h:117:10
pub const OPUS_ARG_NONNULL = @compileError("unable to translate macro: undefined identifier `__nonnull__`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_defines.h:122:10
pub const OPUS_SET_APPLICATION_REQUEST = @as(c_int, 4000);
pub const OPUS_GET_APPLICATION_REQUEST = @as(c_int, 4001);
pub const OPUS_SET_BITRATE_REQUEST = @as(c_int, 4002);
pub const OPUS_GET_BITRATE_REQUEST = @as(c_int, 4003);
pub const OPUS_SET_MAX_BANDWIDTH_REQUEST = @as(c_int, 4004);
pub const OPUS_GET_MAX_BANDWIDTH_REQUEST = @as(c_int, 4005);
pub const OPUS_SET_VBR_REQUEST = @as(c_int, 4006);
pub const OPUS_GET_VBR_REQUEST = @as(c_int, 4007);
pub const OPUS_SET_BANDWIDTH_REQUEST = @as(c_int, 4008);
pub const OPUS_GET_BANDWIDTH_REQUEST = @as(c_int, 4009);
pub const OPUS_SET_COMPLEXITY_REQUEST = @as(c_int, 4010);
pub const OPUS_GET_COMPLEXITY_REQUEST = @as(c_int, 4011);
pub const OPUS_SET_INBAND_FEC_REQUEST = @as(c_int, 4012);
pub const OPUS_GET_INBAND_FEC_REQUEST = @as(c_int, 4013);
pub const OPUS_SET_PACKET_LOSS_PERC_REQUEST = @as(c_int, 4014);
pub const OPUS_GET_PACKET_LOSS_PERC_REQUEST = @as(c_int, 4015);
pub const OPUS_SET_DTX_REQUEST = @as(c_int, 4016);
pub const OPUS_GET_DTX_REQUEST = @as(c_int, 4017);
pub const OPUS_SET_VBR_CONSTRAINT_REQUEST = @as(c_int, 4020);
pub const OPUS_GET_VBR_CONSTRAINT_REQUEST = @as(c_int, 4021);
pub const OPUS_SET_FORCE_CHANNELS_REQUEST = @as(c_int, 4022);
pub const OPUS_GET_FORCE_CHANNELS_REQUEST = @as(c_int, 4023);
pub const OPUS_SET_SIGNAL_REQUEST = @as(c_int, 4024);
pub const OPUS_GET_SIGNAL_REQUEST = @as(c_int, 4025);
pub const OPUS_GET_LOOKAHEAD_REQUEST = @as(c_int, 4027);
pub const OPUS_GET_SAMPLE_RATE_REQUEST = @as(c_int, 4029);
pub const OPUS_GET_FINAL_RANGE_REQUEST = @as(c_int, 4031);
pub const OPUS_GET_PITCH_REQUEST = @as(c_int, 4033);
pub const OPUS_SET_GAIN_REQUEST = @as(c_int, 4034);
pub const OPUS_GET_GAIN_REQUEST = @as(c_int, 4045);
pub const OPUS_SET_LSB_DEPTH_REQUEST = @as(c_int, 4036);
pub const OPUS_GET_LSB_DEPTH_REQUEST = @as(c_int, 4037);
pub const OPUS_GET_LAST_PACKET_DURATION_REQUEST = @as(c_int, 4039);
pub const OPUS_SET_EXPERT_FRAME_DURATION_REQUEST = @as(c_int, 4040);
pub const OPUS_GET_EXPERT_FRAME_DURATION_REQUEST = @as(c_int, 4041);
pub const OPUS_SET_PREDICTION_DISABLED_REQUEST = @as(c_int, 4042);
pub const OPUS_GET_PREDICTION_DISABLED_REQUEST = @as(c_int, 4043);
pub const OPUS_SET_PHASE_INVERSION_DISABLED_REQUEST = @as(c_int, 4046);
pub const OPUS_GET_PHASE_INVERSION_DISABLED_REQUEST = @as(c_int, 4047);
pub const OPUS_GET_IN_DTX_REQUEST = @as(c_int, 4049);
pub const OPUS_SET_DRED_DURATION_REQUEST = @as(c_int, 4050);
pub const OPUS_GET_DRED_DURATION_REQUEST = @as(c_int, 4051);
pub const OPUS_SET_DNN_BLOB_REQUEST = @as(c_int, 4052);
pub const OPUS_SET_OSCE_BWE_REQUEST = @as(c_int, 4054);
pub const OPUS_GET_OSCE_BWE_REQUEST = @as(c_int, 4055);
pub const OPUS_SET_QEXT_REQUEST = @as(c_int, 4056);
pub const OPUS_GET_QEXT_REQUEST = @as(c_int, 4057);
pub const OPUS_SET_IGNORE_EXTENSIONS_REQUEST = @as(c_int, 4058);
pub const OPUS_GET_IGNORE_EXTENSIONS_REQUEST = @as(c_int, 4059);
pub const OPUS_HAVE_OPUS_PROJECTION_H = "";
pub inline fn opus_check_int(x: anytype) opus_int32 {
    _ = &x;
    return blk_1: {
        _ = __helpers.cast(anyopaque, x == __helpers.cast(opus_int32, @as(c_int, 0)));
        break :blk_1 __helpers.cast(opus_int32, x);
    };
}
pub inline fn opus_check_int_ptr(ptr: anytype) @TypeOf(ptr + (ptr - __helpers.cast([*c]opus_int32, ptr))) {
    _ = &ptr;
    return ptr + (ptr - __helpers.cast([*c]opus_int32, ptr));
}
pub inline fn opus_check_uint_ptr(ptr: anytype) @TypeOf(ptr + (ptr - __helpers.cast([*c]opus_uint32, ptr))) {
    _ = &ptr;
    return ptr + (ptr - __helpers.cast([*c]opus_uint32, ptr));
}
pub inline fn opus_check_uint8_ptr(ptr: anytype) @TypeOf(ptr + (ptr - __helpers.cast([*c]opus_uint8, ptr))) {
    _ = &ptr;
    return ptr + (ptr - __helpers.cast([*c]opus_uint8, ptr));
}
pub const opus_check_val16_ptr = @compileError("unable to translate macro: undefined identifier `opus_val16`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_defines.h:201:9
pub inline fn opus_check_void_ptr(x: anytype) @TypeOf(x) {
    _ = &x;
    return blk_1: {
        _ = __helpers.cast(anyopaque, __helpers.cast(?*anyopaque, @as(c_int, 0)) == x);
        break :blk_1 x;
    };
}
pub const OPUS_AUTO = -@as(c_int, 1000);
pub const OPUS_BITRATE_MAX = -@as(c_int, 1);
pub const OPUS_APPLICATION_VOIP = @as(c_int, 2048);
pub const OPUS_APPLICATION_AUDIO = @as(c_int, 2049);
pub const OPUS_APPLICATION_RESTRICTED_LOWDELAY = @as(c_int, 2051);
pub const OPUS_APPLICATION_RESTRICTED_SILK = @as(c_int, 2052);
pub const OPUS_APPLICATION_RESTRICTED_CELT = @as(c_int, 2053);
pub const OPUS_SIGNAL_VOICE = @as(c_int, 3001);
pub const OPUS_SIGNAL_MUSIC = @as(c_int, 3002);
pub const OPUS_BANDWIDTH_NARROWBAND = @as(c_int, 1101);
pub const OPUS_BANDWIDTH_MEDIUMBAND = @as(c_int, 1102);
pub const OPUS_BANDWIDTH_WIDEBAND = @as(c_int, 1103);
pub const OPUS_BANDWIDTH_SUPERWIDEBAND = @as(c_int, 1104);
pub const OPUS_BANDWIDTH_FULLBAND = @as(c_int, 1105);
pub const OPUS_FRAMESIZE_ARG = @as(c_int, 5000);
pub const OPUS_FRAMESIZE_2_5_MS = @as(c_int, 5001);
pub const OPUS_FRAMESIZE_5_MS = @as(c_int, 5002);
pub const OPUS_FRAMESIZE_10_MS = @as(c_int, 5003);
pub const OPUS_FRAMESIZE_20_MS = @as(c_int, 5004);
pub const OPUS_FRAMESIZE_40_MS = @as(c_int, 5005);
pub const OPUS_FRAMESIZE_60_MS = @as(c_int, 5006);
pub const OPUS_FRAMESIZE_80_MS = @as(c_int, 5007);
pub const OPUS_FRAMESIZE_100_MS = @as(c_int, 5008);
pub const OPUS_FRAMESIZE_120_MS = @as(c_int, 5009);
pub inline fn OPUS_SET_COMPLEXITY(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_COMPLEXITY_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_COMPLEXITY(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_COMPLEXITY_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_BITRATE(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_BITRATE_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_BITRATE(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_BITRATE_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_VBR(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_VBR_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_VBR(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_VBR_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_VBR_CONSTRAINT(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_VBR_CONSTRAINT_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_VBR_CONSTRAINT(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_VBR_CONSTRAINT_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_FORCE_CHANNELS(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_FORCE_CHANNELS_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_FORCE_CHANNELS(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_FORCE_CHANNELS_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_MAX_BANDWIDTH(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_MAX_BANDWIDTH_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_MAX_BANDWIDTH(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_MAX_BANDWIDTH_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_BANDWIDTH(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_BANDWIDTH_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_SET_SIGNAL(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_SIGNAL_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_SIGNAL(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_SIGNAL_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_APPLICATION(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_APPLICATION_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_APPLICATION(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_APPLICATION_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_GET_LOOKAHEAD(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_LOOKAHEAD_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_INBAND_FEC(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_INBAND_FEC_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_INBAND_FEC(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_INBAND_FEC_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_PACKET_LOSS_PERC(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_PACKET_LOSS_PERC_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_PACKET_LOSS_PERC(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_PACKET_LOSS_PERC_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_DTX(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_DTX_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_DTX(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_DTX_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_LSB_DEPTH(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_LSB_DEPTH_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_LSB_DEPTH(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_LSB_DEPTH_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_EXPERT_FRAME_DURATION(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_EXPERT_FRAME_DURATION_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_EXPERT_FRAME_DURATION(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_EXPERT_FRAME_DURATION_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_PREDICTION_DISABLED(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_PREDICTION_DISABLED_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_PREDICTION_DISABLED(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_PREDICTION_DISABLED_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_DRED_DURATION(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_DRED_DURATION_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_DRED_DURATION(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_DRED_DURATION_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_DNN_BLOB(data: anytype, len: anytype) @TypeOf(opus_check_int(len)) {
    _ = &data;
    _ = &len;
    return blk: {
        _ = &OPUS_SET_DNN_BLOB_REQUEST;
        _ = opus_check_void_ptr(data);
        break :blk opus_check_int(len);
    };
}
pub inline fn OPUS_SET_QEXT(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_QEXT_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_QEXT(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_QEXT_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub const OPUS_RESET_STATE = @as(c_int, 4028);
pub inline fn OPUS_GET_FINAL_RANGE(x: anytype) @TypeOf(opus_check_uint_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_FINAL_RANGE_REQUEST;
        break :blk opus_check_uint_ptr(x);
    };
}
pub inline fn OPUS_GET_BANDWIDTH(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_BANDWIDTH_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_GET_SAMPLE_RATE(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_SAMPLE_RATE_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_PHASE_INVERSION_DISABLED(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_PHASE_INVERSION_DISABLED_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_PHASE_INVERSION_DISABLED(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_PHASE_INVERSION_DISABLED_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_GET_IN_DTX(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_IN_DTX_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_GAIN(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_GAIN_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_GAIN(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_GAIN_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_GET_LAST_PACKET_DURATION(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_LAST_PACKET_DURATION_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_GET_PITCH(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_PITCH_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_OSCE_BWE(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_OSCE_BWE_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_OSCE_BWE(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_OSCE_BWE_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub inline fn OPUS_SET_IGNORE_EXTENSIONS(x: anytype) @TypeOf(opus_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_SET_IGNORE_EXTENSIONS_REQUEST;
        break :blk opus_check_int(x);
    };
}
pub inline fn OPUS_GET_IGNORE_EXTENSIONS(x: anytype) @TypeOf(opus_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPUS_GET_IGNORE_EXTENSIONS_REQUEST;
        break :blk opus_check_int_ptr(x);
    };
}
pub const opus_check_encstate_ptr = @compileError("unable to translate C expr: expected ')' instead got '*'"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_multistream.h:47:9
pub const opus_check_decstate_ptr = @compileError("unable to translate C expr: expected ')' instead got '*'"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opus_multistream.h:48:9
pub const OPUS_MULTISTREAM_GET_ENCODER_STATE_REQUEST = @as(c_int, 5120);
pub const OPUS_MULTISTREAM_GET_DECODER_STATE_REQUEST = @as(c_int, 5122);
pub inline fn OPUS_MULTISTREAM_GET_ENCODER_STATE(x: anytype, y: anytype) @TypeOf(opus_check_encstate_ptr(y)) {
    _ = &x;
    _ = &y;
    return blk: {
        _ = &OPUS_MULTISTREAM_GET_ENCODER_STATE_REQUEST;
        _ = opus_check_int(x);
        break :blk opus_check_encstate_ptr(y);
    };
}
pub inline fn OPUS_MULTISTREAM_GET_DECODER_STATE(x: anytype, y: anytype) @TypeOf(opus_check_decstate_ptr(y)) {
    _ = &x;
    _ = &y;
    return blk: {
        _ = &OPUS_MULTISTREAM_GET_DECODER_STATE_REQUEST;
        _ = opus_check_int(x);
        break :blk opus_check_decstate_ptr(y);
    };
}
pub inline fn OP_GNUC_PREREQ(_maj: anytype, _min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((_maj << @as(c_int, 16)) + _min)) {
    _ = &_maj;
    _ = &_min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((_maj << @as(c_int, 16)) + _min);
}
pub const OP_WARN_UNUSED_RESULT = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opusfile.h:137:11
pub const OP_ARG_NONNULL = @compileError("unable to translate macro: undefined identifier `__nonnull__`"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opusfile.h:142:11
pub const OP_FALSE = -@as(c_int, 1);
pub const OP_EOF = -@as(c_int, 2);
pub const OP_HOLE = -@as(c_int, 3);
pub const OP_EREAD = -@as(c_int, 128);
pub const OP_EFAULT = -@as(c_int, 129);
pub const OP_EIMPL = -@as(c_int, 130);
pub const OP_EINVAL = -@as(c_int, 131);
pub const OP_ENOTFORMAT = -@as(c_int, 132);
pub const OP_EBADHEADER = -@as(c_int, 133);
pub const OP_EVERSION = -@as(c_int, 134);
pub const OP_ENOTAUDIO = -@as(c_int, 135);
pub const OP_EBADPACKET = -@as(c_int, 136);
pub const OP_EBADLINK = -@as(c_int, 137);
pub const OP_ENOSEEK = -@as(c_int, 138);
pub const OP_EBADTIMESTAMP = -@as(c_int, 139);
pub const OPUS_CHANNEL_COUNT_MAX = @as(c_int, 255);
pub const OP_PIC_FORMAT_UNKNOWN = -@as(c_int, 1);
pub const OP_PIC_FORMAT_URL = @as(c_int, 0);
pub const OP_PIC_FORMAT_JPEG = @as(c_int, 1);
pub const OP_PIC_FORMAT_PNG = @as(c_int, 2);
pub const OP_PIC_FORMAT_GIF = @as(c_int, 3);
pub const OP_SSL_SKIP_CERTIFICATE_CHECK_REQUEST = @as(c_int, 6464);
pub const OP_HTTP_PROXY_HOST_REQUEST = @as(c_int, 6528);
pub const OP_HTTP_PROXY_PORT_REQUEST = @as(c_int, 6592);
pub const OP_HTTP_PROXY_USER_REQUEST = @as(c_int, 6656);
pub const OP_HTTP_PROXY_PASS_REQUEST = @as(c_int, 6720);
pub const OP_GET_SERVER_INFO_REQUEST = @as(c_int, 6784);
pub inline fn OP_URL_OPT(_request: anytype) [*c]u8 {
    _ = &_request;
    return __helpers.cast([*c]u8, _request);
}
pub inline fn OP_CHECK_INT(_x: anytype) opus_int32 {
    _ = &_x;
    return blk_1: {
        _ = __helpers.cast(anyopaque, _x == __helpers.cast(opus_int32, @as(c_int, 0)));
        break :blk_1 __helpers.cast(opus_int32, _x);
    };
}
pub const OP_CHECK_CONST_CHAR_PTR = @compileError("unable to translate C expr: unexpected token 'const'"); // .zig-cache-spacepass/o/ee5bf3a32ca103acfbc0a5f907616c44/opusfile.h:706:9
pub inline fn OP_CHECK_SERVER_INFO_PTR(_x: anytype) @TypeOf(_x + (_x - __helpers.cast([*c]OpusServerInfo, _x))) {
    _ = &_x;
    return _x + (_x - __helpers.cast([*c]OpusServerInfo, _x));
}
pub inline fn OP_SSL_SKIP_CERTIFICATE_CHECK(_b: anytype) @TypeOf(OP_CHECK_INT(_b)) {
    _ = &_b;
    return blk: {
        _ = OP_URL_OPT(OP_SSL_SKIP_CERTIFICATE_CHECK_REQUEST);
        break :blk OP_CHECK_INT(_b);
    };
}
pub inline fn OP_HTTP_PROXY_HOST(_host: anytype) @TypeOf(OP_CHECK_CONST_CHAR_PTR(_host)) {
    _ = &_host;
    return blk: {
        _ = OP_URL_OPT(OP_HTTP_PROXY_HOST_REQUEST);
        break :blk OP_CHECK_CONST_CHAR_PTR(_host);
    };
}
pub inline fn OP_HTTP_PROXY_PORT(_port: anytype) @TypeOf(OP_CHECK_INT(_port)) {
    _ = &_port;
    return blk: {
        _ = OP_URL_OPT(OP_HTTP_PROXY_PORT_REQUEST);
        break :blk OP_CHECK_INT(_port);
    };
}
pub inline fn OP_HTTP_PROXY_USER(_user: anytype) @TypeOf(OP_CHECK_CONST_CHAR_PTR(_user)) {
    _ = &_user;
    return blk: {
        _ = OP_URL_OPT(OP_HTTP_PROXY_USER_REQUEST);
        break :blk OP_CHECK_CONST_CHAR_PTR(_user);
    };
}
pub inline fn OP_HTTP_PROXY_PASS(_pass: anytype) @TypeOf(OP_CHECK_CONST_CHAR_PTR(_pass)) {
    _ = &_pass;
    return blk: {
        _ = OP_URL_OPT(OP_HTTP_PROXY_PASS_REQUEST);
        break :blk OP_CHECK_CONST_CHAR_PTR(_pass);
    };
}
pub inline fn OP_GET_SERVER_INFO(_info: anytype) @TypeOf(OP_CHECK_SERVER_INFO_PTR(_info)) {
    _ = &_info;
    return blk: {
        _ = OP_URL_OPT(OP_GET_SERVER_INFO_REQUEST);
        break :blk OP_CHECK_SERVER_INFO_PTR(_info);
    };
}
pub const OP_DEC_FORMAT_SHORT = @as(c_int, 7008);
pub const OP_DEC_FORMAT_FLOAT = @as(c_int, 7040);
pub const OP_DEC_USE_DEFAULT = @as(c_int, 6720);
pub const OP_HEADER_GAIN = @as(c_int, 0);
pub const OP_ALBUM_GAIN = @as(c_int, 3007);
pub const OP_TRACK_GAIN = @as(c_int, 3008);
pub const OP_ABSOLUTE_GAIN = @as(c_int, 3009);
pub const OPUSENC_H = "";
pub const OPE_EXPORT = "";
pub const OPE_API_VERSION = @as(c_int, 0);
pub const OPE_OK = @as(c_int, 0);
pub const OPE_BAD_ARG = -@as(c_int, 11);
pub const OPE_INTERNAL_ERROR = -@as(c_int, 13);
pub const OPE_UNIMPLEMENTED = -@as(c_int, 15);
pub const OPE_ALLOC_FAIL = -@as(c_int, 17);
pub const OPE_CANNOT_OPEN = -@as(c_int, 30);
pub const OPE_TOO_LATE = -@as(c_int, 31);
pub const OPE_INVALID_PICTURE = -@as(c_int, 32);
pub const OPE_INVALID_ICON = -@as(c_int, 33);
pub const OPE_WRITE_FAIL = -@as(c_int, 34);
pub const OPE_CLOSE_FAIL = -@as(c_int, 35);
pub const OPE_SET_DECISION_DELAY_REQUEST = @as(c_int, 14000);
pub const OPE_GET_DECISION_DELAY_REQUEST = @as(c_int, 14001);
pub const OPE_SET_MUXING_DELAY_REQUEST = @as(c_int, 14002);
pub const OPE_GET_MUXING_DELAY_REQUEST = @as(c_int, 14003);
pub const OPE_SET_COMMENT_PADDING_REQUEST = @as(c_int, 14004);
pub const OPE_GET_COMMENT_PADDING_REQUEST = @as(c_int, 14005);
pub const OPE_SET_SERIALNO_REQUEST = @as(c_int, 14006);
pub const OPE_GET_SERIALNO_REQUEST = @as(c_int, 14007);
pub const OPE_SET_PACKET_CALLBACK_REQUEST = @as(c_int, 14008);
pub const OPE_SET_HEADER_GAIN_REQUEST = @as(c_int, 14010);
pub const OPE_GET_HEADER_GAIN_REQUEST = @as(c_int, 14011);
pub const OPE_GET_NB_STREAMS_REQUEST = @as(c_int, 14013);
pub const OPE_GET_NB_COUPLED_STREAMS_REQUEST = @as(c_int, 14015);
pub inline fn ope_check_int(x: anytype) opus_int32 {
    _ = &x;
    return blk_1: {
        _ = __helpers.cast(anyopaque, x == __helpers.cast(opus_int32, @as(c_int, 0)));
        break :blk_1 __helpers.cast(opus_int32, x);
    };
}
pub inline fn ope_check_int_ptr(ptr: anytype) @TypeOf(ptr + (ptr - __helpers.cast([*c]opus_int32, ptr))) {
    _ = &ptr;
    return ptr + (ptr - __helpers.cast([*c]opus_int32, ptr));
}
pub const ope_check_packet_func = @compileError("unable to translate C expr: expected ')' instead got '('"); // .zig-cache-spacepass/o/e1c22d9ce8e624ad32fd788ea7a68444/opusenc.h:127:9
pub inline fn ope_check_void_ptr(x: anytype) @TypeOf(x) {
    _ = &x;
    return blk_1: {
        _ = __helpers.cast(anyopaque, __helpers.cast(?*anyopaque, @as(c_int, 0)) == x);
        break :blk_1 x;
    };
}
pub inline fn OPE_SET_DECISION_DELAY(x: anytype) @TypeOf(ope_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_SET_DECISION_DELAY_REQUEST;
        break :blk ope_check_int(x);
    };
}
pub inline fn OPE_GET_DECISION_DELAY(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_DECISION_DELAY_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_SET_MUXING_DELAY(x: anytype) @TypeOf(ope_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_SET_MUXING_DELAY_REQUEST;
        break :blk ope_check_int(x);
    };
}
pub inline fn OPE_GET_MUXING_DELAY(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_MUXING_DELAY_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_SET_COMMENT_PADDING(x: anytype) @TypeOf(ope_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_SET_COMMENT_PADDING_REQUEST;
        break :blk ope_check_int(x);
    };
}
pub inline fn OPE_GET_COMMENT_PADDING(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_COMMENT_PADDING_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_SET_SERIALNO(x: anytype) @TypeOf(ope_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_SET_SERIALNO_REQUEST;
        break :blk ope_check_int(x);
    };
}
pub inline fn OPE_GET_SERIALNO(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_SERIALNO_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_SET_PACKET_CALLBACK(x: anytype, u: anytype) @TypeOf(ope_check_void_ptr(u)) {
    _ = &x;
    _ = &u;
    return blk: {
        _ = &OPE_SET_PACKET_CALLBACK_REQUEST;
        _ = ope_check_packet_func(x);
        break :blk ope_check_void_ptr(u);
    };
}
pub inline fn OPE_SET_HEADER_GAIN(x: anytype) @TypeOf(ope_check_int(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_SET_HEADER_GAIN_REQUEST;
        break :blk ope_check_int(x);
    };
}
pub inline fn OPE_GET_HEADER_GAIN(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_HEADER_GAIN_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_GET_NB_STREAMS(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_NB_STREAMS_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub inline fn OPE_GET_NB_COUPLED_STREAMS(x: anytype) @TypeOf(ope_check_int_ptr(x)) {
    _ = &x;
    return blk: {
        _ = &OPE_GET_NB_COUPLED_STREAMS_REQUEST;
        break :blk ope_check_int_ptr(x);
    };
}
pub const __darwin_pthread_handler_rec = struct___darwin_pthread_handler_rec;
pub const _opaque_pthread_attr_t = struct__opaque_pthread_attr_t;
pub const _opaque_pthread_cond_t = struct__opaque_pthread_cond_t;
pub const _opaque_pthread_condattr_t = struct__opaque_pthread_condattr_t;
pub const _opaque_pthread_mutex_t = struct__opaque_pthread_mutex_t;
pub const _opaque_pthread_mutexattr_t = struct__opaque_pthread_mutexattr_t;
pub const _opaque_pthread_once_t = struct__opaque_pthread_once_t;
pub const _opaque_pthread_rwlock_t = struct__opaque_pthread_rwlock_t;
pub const _opaque_pthread_rwlockattr_t = struct__opaque_pthread_rwlockattr_t;
pub const _opaque_pthread_t = struct__opaque_pthread_t;
pub const __sbuf = struct___sbuf;
pub const __sFILEX = struct___sFILEX;
pub const __sFILE = struct___sFILE;
pub const _OSUnalignedU16 = struct__OSUnalignedU16;
pub const _OSUnalignedU32 = struct__OSUnalignedU32;
pub const _OSUnalignedU64 = struct__OSUnalignedU64;
