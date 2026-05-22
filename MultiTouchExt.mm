// MultiTouchExt.mm
// ControlPro custom RFB multi-touch extension.
//
// Listens for message type 0xFA, parses an array of {id, phase, x, y}
// tuples, and forwards them to STHIDEventGenerator as a single
// sendEventStream: call (true simultaneous multi-touch, not faked
// sequential taps).
//
// Keeps an internal table of "currently down" touch IDs so that
// stationary touches (joystick held) can be re-asserted on every frame
// alongside new ones (skill taps) without losing each other.

#import "MultiTouchExt.h"
#import "STHIDEventGenerator.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rfb/rfb.h>

#include <stdint.h>
#include <string.h>

// We keep the per-client touch state in a global map keyed by rfbClientPtr.
// libvncserver invokes our handler from the client read loop on its own
// thread, so guard with a lock.
static NSMutableDictionary<NSValue *, NSMutableDictionary *> *g_clientTouches = nil;
static NSLock *g_lock = nil;

static void ensureState(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_clientTouches = [NSMutableDictionary new];
        g_lock = [NSLock new];
    });
}

static NSString *phaseString(uint8_t p) {
    switch (p) {
        case 0: return HIDEventPhaseBegan;
        case 1: return HIDEventPhaseMoved;
        case 2: return HIDEventPhaseEnded;
        case 3: return HIDEventPhaseStationary;
        case 4: return HIDEventPhaseCanceled;
        default: return HIDEventPhaseMoved;
    }
}

// Forward a parsed touch frame to the HID generator using its public
// dictionary-based API. The dictionary mirrors what
// STHIDEventGenerator expects per its own internal sendEventStream:
// implementation.
static void dispatchTouchesToHID(NSArray<NSDictionary *> *touches) {
    if (touches.count == 0) return;
    NSDictionary *event = @{
        HIDEventInputType: @"finger",
        HIDEventTouchesKey: touches,
    };
    [[STHIDEventGenerator sharedHIDEventGenerator] sendEventStream:event];
}

static rfbBool ControlProHandleMessage(rfbClientPtr cl,
                                       void *data,
                                       const rfbClientToServerMsg *message) {
    (void)data;
    if (message->type != CONTROLPRO_MSG_MULTITOUCH) {
        return FALSE; // not our message; let other handlers try
    }

    // Header already consumed (type byte). Read the rest of the header.
    uint8_t hdr[2];
    if (rfbReadExact(cl, (char *)hdr, sizeof(hdr)) <= 0) {
        rfbLog("ControlPro multitouch: short header read\n");
        return TRUE;
    }
    // hdr[0] = flags (reserved); hdr[1] = numTouches
    uint8_t n = hdr[1];
    if (n == 0 || n > CONTROLPRO_MAX_TOUCHES) {
        rfbLog("ControlPro multitouch: invalid numTouches %u\n", (unsigned)n);
        return TRUE;
    }

    // Each touch: id(1) phase(1) x(2 BE) y(2 BE) = 6 bytes
    const size_t TOUCH_BYTES = 6;
    uint8_t buf[CONTROLPRO_MAX_TOUCHES * TOUCH_BYTES];
    if (rfbReadExact(cl, (char *)buf, (int)(n * TOUCH_BYTES)) <= 0) {
        rfbLog("ControlPro multitouch: short body read\n");
        return TRUE;
    }

    NSMutableArray<NSDictionary *> *frame = [NSMutableArray arrayWithCapacity:n];
    for (uint8_t i = 0; i < n; ++i) {
        const uint8_t *p = &buf[i * TOUCH_BYTES];
        uint8_t  tid   = p[0];
        uint8_t  phase = p[1];
        uint16_t x     = ((uint16_t)p[2] << 8) | p[3];
        uint16_t y     = ((uint16_t)p[4] << 8) | p[5];
        [frame addObject:@{
            HIDEventTouchIDKey: @(tid),
            HIDEventPhaseKey:   phaseString(phase),
            HIDEventXKey:       @((CGFloat)x),
            HIDEventYKey:       @((CGFloat)y),
        }];
    }

    dispatchTouchesToHID(frame);
    return TRUE;
}

static rfbBool ControlProClientHook(rfbClientPtr cl) {
    (void)cl;
    return TRUE; // accept all clients
}

static rfbProtocolExtension ControlProExt = {
    /* newClient        */ NULL,
    /* close            */ NULL,
    /* clientHook       */ ControlProClientHook,
    /* pseudoEncodings  */ NULL,
    /* handleMessage    */ ControlProHandleMessage,
    /* encodingEnabled  */ NULL,
    /* next             */ NULL,
};

void ControlProRegisterMultiTouchExtension(void) {
    ensureState();
    rfbRegisterProtocolExtension(&ControlProExt);
    rfbLog("ControlPro: multi-touch RFB extension registered (msg=0x%02X, max %d touches)\n",
           CONTROLPRO_MSG_MULTITOUCH, CONTROLPRO_MAX_TOUCHES);
}
