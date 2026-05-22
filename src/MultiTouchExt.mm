// MultiTouchExt.mm
// ControlPro custom RFB multi-touch extension.
//
// Listens for message type 0xFA, parses an array of {id, phase, x, y}
// tuples, and forwards them to STHIDEventGenerator as a single
// sendEventStream: call (true simultaneous multi-touch, not faked
// sequential taps).

#import "MultiTouchExt.h"
#import "STHIDEventGenerator.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rfb/rfb.h>

#include <stdint.h>
#include <string.h>

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

// STHIDEventGenerator's sendEventStream: expects:
//
//   {
//     "events": [
//       {
//         "timeOffset": 0.0,
//         "inputType": "finger",
//         "touches": [
//           { "id": N, "phase": "began|moved|ended|stationary", "x": F, "y": F },
//           ...
//         ]
//       }
//     ]
//   }
//
// We construct that here and dispatch as a single stream entry per frame.
static void dispatchTouchesToHID(NSArray<NSDictionary *> *touches) {
    if (touches.count == 0) return;
    NSDictionary *event = @{
        @"timeOffset":      @(0.0),
        HIDEventInputType:  @"finger",
        HIDEventTouchesKey: touches,
    };
    NSDictionary *stream = @{
        @"events": @[event],
    };
    [[STHIDEventGenerator sharedGenerator] sendEventStream:stream];
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

// libvncserver requires newClient to be non-NULL for the extension to be
// activated for incoming clients. We accept all clients unconditionally.
static rfbBool ControlProNewClient(rfbClientPtr cl, void **data) {
    (void)cl;
    *data = NULL;
    rfbLog("ControlPro: multi-touch extension activated for client\n");
    return TRUE;
}

// libvncserver rfbProtocolExtension struct (libvncserver 0.9.x):
//   1. newClient            rfbBool fn — MUST be non-NULL to activate per-client
//   2. init                 rfbBool fn or NULL
//   3. pseudoEncodings      int* (NULL-terminated list) or NULL
//   4. enablePseudoEncoding rfbBool fn or NULL
//   5. handleMessage        rfbBool fn or NULL
//   6. close                void fn or NULL
//   7. usage                void fn or NULL
//   8. processArgument      int fn or NULL
//   9. next                 (set by registry, init NULL)
static rfbProtocolExtension ControlProExt = {
    ControlProNewClient,         // newClient (NULL = "always deactivated")
    NULL,                        // init
    NULL,                        // pseudoEncodings
    NULL,                        // enablePseudoEncoding
    ControlProHandleMessage,     // handleMessage
    NULL,                        // close
    NULL,                        // usage
    NULL,                        // processArgument
    NULL,                        // next
};

void ControlProRegisterMultiTouchExtension(void) {
    rfbRegisterProtocolExtension(&ControlProExt);
    rfbLog("ControlPro: multi-touch RFB extension registered (msg=0x%02X, max %d touches)\n",
           CONTROLPRO_MSG_MULTITOUCH, CONTROLPRO_MAX_TOUCHES);
}
