const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

pub const BaseFunctions = vk.BaseWrapper;
pub const InstanceFunctions = vk.InstanceWrapper;
pub const DeviceFunctions = vk.DeviceWrapper;

pub const BaseLoader = *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction;

pub fn loadBase(baseLoader: BaseLoader) BaseFunctions {
    return BaseFunctions.load(baseLoader);
}

pub fn loadInstance(instance: vk.Instance, instanceLoader: vk.PfnGetInstanceProcAddr) InstanceFunctions {
    return InstanceFunctions.load(instance, instanceLoader);
}

pub fn loadDevice(device: vk.Device, deviceLoader: vk.PfnGetDeviceProcAddr) DeviceFunctions {
    return DeviceFunctions.load(device, deviceLoader);
}
