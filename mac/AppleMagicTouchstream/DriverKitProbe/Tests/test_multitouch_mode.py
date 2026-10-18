"""Check the production command against USB and observed macOS keyhole framing."""
import pathlib
import subprocess
import tempfile
import unittest

class MultitouchModeTests(unittest.TestCase):
    def test_mac_bluetooth_adds_exactly_one_f1_prefix(self):
        driver = pathlib.Path(__file__).resolve().parents[1] / 'Driver'
        source = r'''
#include "MultitouchMode.h"
#include <cassert>
#include <array>
int main() {
    constexpr auto usb=AMTMultitouchMode(true);
    constexpr auto bt=AMTMultitouchMode(false);
    static_assert(usb.reportID==2 && sizeof(usb.payload)==2);
    static_assert(bt.reportID==0xf1 && sizeof(bt.payload)==2);
    assert(usb.payload[0]==2 && usb.payload[1]==1);
    // bluetoothd's observed setReportWithKeyhole path prefixes its own F1.
    std::array<uint8_t,3> wire={0xf1,bt.payload[0],bt.payload[1]};
    assert((wire==std::array<uint8_t,3>{0xf1,0x02,0x01}));
}
'''
        with tempfile.TemporaryDirectory(prefix='GesturePad-mode-') as directory:
            path=pathlib.Path(directory)
            (path/'mode.cpp').write_text(source)
            subprocess.run(['xcrun','clang++','-std=c++17','-I',str(driver),str(path/'mode.cpp'),'-o',str(path/'mode')],check=True)
            subprocess.run([str(path/'mode')],check=True)

if __name__=='__main__':unittest.main()
