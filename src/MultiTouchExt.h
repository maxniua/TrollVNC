// MultiTouchExt.h
// ControlPro custom RFB extension for true multi-touch input.
//
// Wire protocol (client → server):
//
//   byte 0    : message type = 0xFA (250)
//   byte 1    : flags (reserved, send 0)
//   byte 2    : numTouches (1..30)
//   then for each touch:
//     byte 0    : touchId (0..29)
//     byte 1    : phase   (0=began, 1=moved, 2=ended, 3=stationary, 4=canceled)
//     bytes 2-3 : x (uint16 big-endian, framebuffer pixels)
//     bytes 4-5 : y (uint16 big-endian, framebuffer pixels)
//
// Each touch carries an independent ID; the server tracks open touches
// and routes them to STHIDEventGenerator's multi-touch sendEventStream:.

#ifndef CONTROLPRO_MULTITOUCH_EXT_H
#define CONTROLPRO_MULTITOUCH_EXT_H

#ifdef __cplusplus
extern "C" {
#endif

#define CONTROLPRO_MSG_MULTITOUCH 0xFA
#define CONTROLPRO_MAX_TOUCHES    30

// Register the extension with libvncserver. Call once during server init,
// AFTER rfbScreenInfo is created but BEFORE rfbInitServer().
void ControlProRegisterMultiTouchExtension(void);

#ifdef __cplusplus
}
#endif

#endif // CONTROLPRO_MULTITOUCH_EXT_H
