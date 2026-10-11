const builtin = @import("builtin");

pub const c = if (builtin.target.os.tag == .windows)
    @import("c_opengl_windows")
else if (builtin.target.os.tag == .linux)
    @import("c_opengl_linux")
else
    struct {};
