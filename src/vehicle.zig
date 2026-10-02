//! Hard-surface vehicles: geometry (hull, airfoils, lathe/fans), mass
//! properties, rigid-body dynamics, hover physics and flight control.
pub const airfoil = @import("vehicle/airfoil.zig");
pub const dynamics = @import("vehicle/dynamics.zig");
pub const prims = @import("vehicle/prims.zig");
pub const fan = @import("vehicle/fan.zig");
pub const hull = @import("vehicle/hull.zig");
pub const nozzle = @import("vehicle/nozzle.zig");
pub const hover = @import("vehicle/hover.zig");
pub const car = @import("vehicle/car.zig");

test {
    _ = airfoil;
    _ = dynamics;
    _ = prims;
    _ = fan;
    _ = hull;
    _ = nozzle;
    _ = hover;
    _ = car;
}
