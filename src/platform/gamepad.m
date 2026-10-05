// Mach's pinned platform API has no controllers. Poll Apple's standard profiles, with a raw HID
// fallback for joystick/gamepad devices that do not publish an Apple GameController profile.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
typedef struct { float lx, ly, rx, ry, lt, rt; uint32_t buttons, connected; char vendor[48], product[64]; } HWPad;
static void copy_name(char *out, size_t capacity, NSString *name) {
    if (!name) return;
    // HID properties are untyped: only strings carry a name.
    if (CFGetTypeID((__bridge CFTypeRef)name) != CFStringGetTypeID()) return;
    const char *utf8 = [name UTF8String];
    if (utf8) { strncpy(out, utf8, capacity - 1); out[capacity - 1] = '\0'; }
}

static IOHIDManagerRef hid_manager;
static IOHIDDeviceRef hid_slots[4];

static CFDictionaryRef usage_match(uint32_t usage) {
    uint32_t page_value = kHIDPage_GenericDesktop;
    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page_value);
    CFNumberRef use = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);
    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) };
    const void *values[] = { page, use };
    CFDictionaryRef result = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (page) CFRelease(page);
    if (use) CFRelease(use);
    return result;
}

static void open_hid_manager(void) {
    if (hid_manager) return;
    hid_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!hid_manager) return;
    const void *matches[] = { usage_match(kHIDUsage_GD_Joystick), usage_match(kHIDUsage_GD_GamePad), usage_match(kHIDUsage_GD_MultiAxisController) };
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, matches, 3, &kCFTypeArrayCallBacks);
    for (int i=0; i<3; ++i) if (matches[i]) CFRelease(matches[i]);
    if (array) {
        IOHIDManagerSetDeviceMatchingMultiple(hid_manager, array);
        CFRelease(array);
    }
    if (IOHIDManagerOpen(hid_manager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        CFRelease(hid_manager);
        hid_manager = NULL;
    }
}

static int same_text(CFTypeRef value, NSString *text) {
    if (!value || !text || CFGetTypeID(value) != CFStringGetTypeID()) return 0;
    NSString *candidate = (__bridge NSString *)value;
    return [candidate caseInsensitiveCompare:text] == NSOrderedSame ||
        [candidate localizedCaseInsensitiveContainsString:text] ||
        [text localizedCaseInsensitiveContainsString:candidate];
}

static int already_in_gamecontroller(IOHIDDeviceRef device, NSArray<GCController *> *controllers) {
    // GameController claims every pad it supports; those are read through its profile only.
    if (@available(macOS 11.0, *)) {
        if ([GCController supportsHIDDevice:device]) return 1;
    }
    // Older systems: GameController's vendorName is the device's name (for example "Xbox
    // Wireless Controller"), which matches the HID product string, not its manufacturer.
    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    for (GCController *pad in controllers) {
        if (!pad.extendedGamepad && !pad.microGamepad) continue;
        if (same_text(product, pad.vendorName) || same_text(product, pad.productCategory)) return 1;
    }
    return 0;
}

static float axis_value(IOHIDValueRef value) {
    IOHIDElementRef element = IOHIDValueGetElement(value);
    long min = IOHIDElementGetLogicalMin(element), max = IOHIDElementGetLogicalMax(element);
    if (max <= min) return 0;
    double v = IOHIDValueGetIntegerValue(value);
    double midpoint = ((double)min + (double)max) * 0.5;
    double half = ((double)max - (double)min) * 0.5;
    double result = (v - midpoint) / half;
    if (result < -1) result = -1;
    if (result > 1) result = 1;
    return (float)result;
}

static void read_hid(IOHIDDeviceRef device, HWPad *out) {
    out->connected = 1;
    copy_name(out->vendor, sizeof(out->vendor), (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDManufacturerKey)));
    copy_name(out->product, sizeof(out->product), (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)));
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
    if (!elements) return;
    float x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, z_trigger = 0, rz_trigger = 0;
    int has_x = 0, has_y = 0, has_z = 0, has_rx = 0, has_ry = 0, has_rz = 0;
    for (CFIndex i=0; i<CFArrayGetCount(elements); ++i) {
        IOHIDElementRef e = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
        if (IOHIDElementGetType(e) != kIOHIDElementTypeInput_Axis && IOHIDElementGetType(e) != kIOHIDElementTypeInput_Misc && IOHIDElementGetType(e) != kIOHIDElementTypeInput_Button) continue;
        IOHIDValueRef value = NULL;
        if (IOHIDDeviceGetValue(device, e, &value) != kIOReturnSuccess || !value) continue;
        uint32_t page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e);
        if (page == kHIDPage_Button && usage >= 1 && usage <= 16 && IOHIDValueGetIntegerValue(value)) {
            out->buttons |= 1u << (usage - 1);
            if (usage == 7) out->lt = 1;
            if (usage == 8) out->rt = 1;
        }
        else if (page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Hatswitch) {
            long hat = IOHIDValueGetIntegerValue(value);
            long min = IOHIDElementGetLogicalMin(e), max = IOHIDElementGetLogicalMax(e);
            long direction = hat - min;
            if (direction >= 0 && direction < 8 && max - min >= 7) {
                static const uint32_t dpad[8] = { 1u<<12, (1u<<12)|(1u<<15), 1u<<15, (1u<<13)|(1u<<15), 1u<<13, (1u<<13)|(1u<<14), 1u<<14, (1u<<12)|(1u<<14) };
                out->buttons = (out->buttons & ~0xf000u) | dpad[direction];
            }
        } else if (page == kHIDPage_GenericDesktop) {
            float v = axis_value(value);
            switch (usage) {
                case kHIDUsage_GD_X: x=v; has_x=1; break;
                case kHIDUsage_GD_Y: y=v; has_y=1; break;
                case kHIDUsage_GD_Z: {
                    z=v; has_z=1;
                    long min=IOHIDElementGetLogicalMin(e), max=IOHIDElementGetLogicalMax(e);
                    if (min >= 0 && max > min) z_trigger=(float)(IOHIDValueGetIntegerValue(value)-min)/(float)(max-min);
                    break;
                }
                case kHIDUsage_GD_Rx: rx=v; has_rx=1; break;
                case kHIDUsage_GD_Ry: ry=v; has_ry=1; break;
                case kHIDUsage_GD_Rz: {
                    rz=v; has_rz=1;
                    long min=IOHIDElementGetLogicalMin(e), max=IOHIDElementGetLogicalMax(e);
                    if (min >= 0 && max > min) rz_trigger=(float)(IOHIDValueGetIntegerValue(value)-min)/(float)(max-min);
                    break;
                }
                default: break;
            }
        }
    }
    CFRelease(elements);
    out->lx = has_x ? x : 0; out->ly = has_y ? y : 0;
    out->rx = has_rx ? rx : (has_z ? z : 0); out->ry = has_ry ? ry : (has_rz ? rz : 0);
    // Z and Rz are triggers only when the right stick has its own Rx/Ry axes. Otherwise they are
    // the right stick (centred at half range), and reading them as triggers would hold both down.
    if (has_rx && z_trigger > out->lt) out->lt=z_trigger;
    if (has_ry && rz_trigger > out->rt) out->rt=rz_trigger;
}

void hw_gamepads(HWPad *out) {
    @autoreleasepool {
        static GCController *slots[4];
        NSArray<GCController *> *live = [GCController controllers];
        memset(out, 0, sizeof(HWPad) * 4);
        open_hid_manager();
        for (int i=0; i<4; ++i) {
            if (slots[i] && ![live containsObject:slots[i]]) { [slots[i] release]; slots[i]=nil; }
        }
        for (GCController *pad in live) {
            if (!pad.extendedGamepad && !pad.microGamepad) continue;
            BOOL found=NO;
            for (int i=0;i<4;++i) if (slots[i]==pad) found=YES;
            if (!found) for (int i=0;i<4;++i) if (!slots[i]) { slots[i]=[pad retain]; break; }
        }
        for (int i=0;i<4;++i) {
            GCController *device=slots[i];
            GCExtendedGamepad *p=device.extendedGamepad;
            GCMicroGamepad *micro=device.microGamepad;
            if (!p && !micro) continue;
            out[i].connected=1;
            copy_name(out[i].vendor, sizeof(out[i].vendor), device.vendorName);
            copy_name(out[i].product, sizeof(out[i].product), device.productCategory);
            if (p) {
                out[i].lx=p.leftThumbstick.xAxis.value; out[i].ly=p.leftThumbstick.yAxis.value;
                out[i].rx=p.rightThumbstick.xAxis.value; out[i].ry=p.rightThumbstick.yAxis.value;
                out[i].lt=p.leftTrigger.value; out[i].rt=p.rightTrigger.value;
                GCControllerButtonInput *buttons[]={p.buttonA,p.buttonB,p.buttonX,p.buttonY,p.leftShoulder,p.rightShoulder,p.leftTrigger,p.rightTrigger,p.buttonMenu,p.buttonOptions,p.leftThumbstickButton,p.rightThumbstickButton,p.dpad.up,p.dpad.down,p.dpad.left,p.dpad.right};
                for (int b=0;b<16;++b) if (buttons[b].pressed) out[i].buttons |= 1u<<b;
            } else {
                out[i].lx=micro.dpad.xAxis.value; out[i].ly=micro.dpad.yAxis.value;
                GCControllerButtonInput *buttons[]={micro.buttonA,micro.buttonX};
                if (buttons[0].pressed) out[i].buttons |= 1u<<0;
                if (buttons[1].pressed) out[i].buttons |= 1u<<2;
                if (micro.dpad.up.pressed) out[i].buttons |= 1u<<12;
                if (micro.dpad.down.pressed) out[i].buttons |= 1u<<13;
                if (micro.dpad.left.pressed) out[i].buttons |= 1u<<14;
                if (micro.dpad.right.pressed) out[i].buttons |= 1u<<15;
            }
        }
        // Generic HID fallback runs after native profiles, avoiding duplicates where the system
        // exposes matching manufacturer/product names. A slot is retained while its device lives.
        if (hid_manager) {
            CFSetRef devices = IOHIDManagerCopyDevices(hid_manager);
            if (devices) {
                IOHIDDeviceRef found[32]; CFIndex found_count = 0;
                CFIndex total = CFSetGetCount(devices);
                const void **items = calloc((size_t)total, sizeof(void *));
                if (items) {
                    CFSetGetValues(devices, items);
                    for (CFIndex j=0; j<total && found_count<32; ++j) {
                        IOHIDDeviceRef candidate = (IOHIDDeviceRef)items[j];
                        if (already_in_gamecontroller(candidate, live)) continue;
                        found[found_count++] = candidate;
                    }
                    free(items);
                }
                for (int s=0; s<4; ++s) {
                    int present=0;
                    for (CFIndex j=0; j<found_count; ++j) if (hid_slots[s] == found[j]) present=1;
                    if (hid_slots[s] && !present) { CFRelease(hid_slots[s]); hid_slots[s]=NULL; }
                }
                for (CFIndex j=0; j<found_count; ++j) {
                    int known=0;
                    for (int s=0; s<4; ++s) if (hid_slots[s] == found[j]) known=1;
                    if (!known) for (int s=0; s<4; ++s) if (!hid_slots[s]) { hid_slots[s]=(IOHIDDeviceRef)CFRetain(found[j]); break; }
                }
                for (int s=0; s<4; ++s) if (hid_slots[s]) {
                    int out_slot=-1;
                    for (int i=0; i<4; ++i) if (!out[i].connected) { out_slot=i; break; }
                    if (out_slot >= 0) read_hid(hid_slots[s], &out[out_slot]);
                }
                CFRelease(devices);
            }
        }
    }
}

// AppKit windows (the save and open panels) must run on the main thread; the game calls these
// from its simulation thread, so each panel runs synchronously on the main queue.
static int save_json_on_main(const char *json, size_t length, const char *suggested_name);
static int open_json_on_main(char *buffer, size_t capacity, size_t *length);

int hw_choose_save_json(const char *json, size_t length, const char *suggested_name) {
    if ([NSThread isMainThread]) return save_json_on_main(json, length, suggested_name);
    __block int result = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{ result = save_json_on_main(json, length, suggested_name); });
    return result;
}

int hw_choose_open_json(char *buffer, size_t capacity, size_t *length) {
    if ([NSThread isMainThread]) return open_json_on_main(buffer, capacity, length);
    __block int result = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{ result = open_json_on_main(buffer, capacity, length); });
    return result;
}

static int save_json_on_main(const char *json, size_t length, const char *suggested_name) {
    @autoreleasepool {
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedFileTypes = @[ @"json" ];
        panel.nameFieldStringValue = [NSString stringWithUTF8String:suggested_name] ?: @"controller-preset.json";
        if ([panel runModal] != NSModalResponseOK || !panel.URL) return 0;
        NSData *data = [NSData dataWithBytes:json length:length];
        NSError *error = nil;
        if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) return -1;
        return 1;
    }
}

static int open_json_on_main(char *buffer, size_t capacity, size_t *length) {
    @autoreleasepool {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = YES; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO;
        panel.allowedFileTypes = @[ @"json" ];
        if ([panel runModal] != NSModalResponseOK || !panel.URL) return 0;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL];
        if (!data || data.length > capacity) return -1;
        memcpy(buffer, data.bytes, data.length);
        *length = data.length;
        return 1;
    }
}
