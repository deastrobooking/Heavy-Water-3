const ChainedStruct = @import("main.zig").ChainedStruct;
const PresentMode = @import("main.zig").PresentMode;
const Texture = @import("texture.zig").Texture;
const TextureView = @import("texture_view.zig").TextureView;
const Impl = @import("interface.zig").Impl;

pub const SwapChain = opaque {
    pub const Descriptor = extern struct {
        next_in_chain: ?*const ChainedStruct = null,
        label: ?[*:0]const u8 = null,
        usage: Texture.UsageFlags,
        format: Texture.Format,
        width: u32,
        height: u32,
        present_mode: PresentMode,
        /// Preferred number of presentable swap chain images.
        ///
        /// This does not limit how many frames the application may render ahead of presentation.
        preferred_image_count: u32 = 2,
    };

    /// Returns a backend-specific handle for the currently-acquired frame, or null if no frame
    /// is acquired or the backend does not expose one.
    ///
    /// On Metal this is the `CAMetalDrawable` (castable to `id<CAMetalDrawable>`). The handle is
    /// borrowed: it is valid from a successful `getCurrentTextureView()` until `present()` or the
    /// next `getCurrentTextureView()` call; retain it if you need it longer. Do not present it
    /// yourself; `present()` remains responsible for presentation.
    pub inline fn getCurrentNativeHandle(swap_chain: *SwapChain) ?*anyopaque {
        return Impl.swapChainGetCurrentNativeHandle(swap_chain);
    }

    pub inline fn getCurrentTexture(swap_chain: *SwapChain) ?*Texture {
        return Impl.swapChainGetCurrentTexture(swap_chain);
    }

    pub inline fn getCurrentTextureView(swap_chain: *SwapChain) ?*TextureView {
        return Impl.swapChainGetCurrentTextureView(swap_chain);
    }

    pub inline fn present(swap_chain: *SwapChain) void {
        Impl.swapChainPresent(swap_chain);
    }

    pub inline fn reference(swap_chain: *SwapChain) void {
        Impl.swapChainReference(swap_chain);
    }

    pub inline fn release(swap_chain: *SwapChain) void {
        Impl.swapChainRelease(swap_chain);
    }
};
