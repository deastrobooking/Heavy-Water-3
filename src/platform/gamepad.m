// Mach's pinned platform API has no controllers. Poll Apple's standard extended profile.
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <stdint.h>
#include <string.h>
typedef struct { float lx, ly, rx, ry; uint32_t buttons, connected; } HWPad;
void hw_gamepads(HWPad *out) {
    @autoreleasepool {
        static GCController *slots[4];
        NSArray<GCController *> *live = [GCController controllers];
        memset(out, 0, sizeof(HWPad) * 4);
        for (int i=0; i<4; ++i) {
            if (slots[i] && ![live containsObject:slots[i]]) { [slots[i] release]; slots[i]=nil; }
        }
        for (GCController *pad in live) {
            if (!pad.extendedGamepad) continue;
            BOOL found=NO;
            for (int i=0;i<4;++i) if (slots[i]==pad) found=YES;
            if (!found) for (int i=0;i<4;++i) if (!slots[i]) { slots[i]=[pad retain]; break; }
        }
        for (int i=0;i<4;++i) {
            GCExtendedGamepad *p=slots[i].extendedGamepad;
            if (!p) continue;
            out[i].connected=1;
            out[i].lx=p.leftThumbstick.xAxis.value; out[i].ly=p.leftThumbstick.yAxis.value;
            out[i].rx=p.rightThumbstick.xAxis.value; out[i].ry=p.rightThumbstick.yAxis.value;
            GCControllerButtonInput *buttons[]={p.buttonA,p.buttonB,p.buttonX,p.buttonY,p.leftShoulder,p.rightShoulder,p.leftTrigger,p.rightTrigger,p.buttonMenu,p.buttonOptions,p.leftThumbstickButton,p.rightThumbstickButton,p.dpad.up,p.dpad.down,p.dpad.left,p.dpad.right};
            for (int b=0;b<16;++b) if (buttons[b].pressed) out[i].buttons |= 1u<<b;
        }
    }
}
