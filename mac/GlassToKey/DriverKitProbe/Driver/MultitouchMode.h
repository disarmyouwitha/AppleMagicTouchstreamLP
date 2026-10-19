#pragma once
#include <stdint.h>

// macOS Bluetooth keyhole transport supplies F1 itself. The Linux wire packet
// F1 02 01 must therefore be requested with reportIDF1 and payload02 01 here.
// USB carries the report ID in its existing02 01 payload without a keyhole prefix.
struct AMTMultitouchModeCommand {
    uint32_t reportID;
    uint8_t payload[2];
};
static constexpr AMTMultitouchModeCommand AMTMultitouchMode(bool usb) {
    return {usb?2U:0xf1U,{0x02,0x01}};
}
