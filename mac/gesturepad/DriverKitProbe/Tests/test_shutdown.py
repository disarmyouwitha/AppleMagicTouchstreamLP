"""Execute the production Stop body with delayed DriverKit cancellation doubles.

This catches destruction before cancellation completes without activating hardware.
The doubles deliberately dereference the timer when its queued cancel callback runs,
matching the lifetime requirement implicated by the macOS crash.
"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

HARNESS = r'''
#include <cassert>
#include <cstdint>
#include <deque>
#include <Block.h>
using kern_return_t = int;
constexpr int kIOReturnSuccess = 0;
#define SUPERDISPATCH 1
#define os_log(...) ((void)0)
static std::deque<void(^)(void)> pending;
struct Source {
    bool alive=true, completed=false;
    int calls=0;
    int Cancel(void(^handler)(void)) {
        assert(alive && ++calls==1);
        auto callback=Block_copy(^{ assert(alive); completed=true; handler(); });
        pending.push_back(callback);
        return 0;
    }
    void SetEnable(bool) { assert(alive); }
};
struct Service {
    int references=1;
    void retain() { ++references; }
    void release() { assert(references>0); --references; }
};
struct State {
    bool stopping=false, counted=true, usb=false;
    Source *timer=nullptr, *timerAction=nullptr, *reportAction=nullptr;
};
struct Receiver {
    State *ivars;
    int references=1;
    bool stopped=false, freed=false;
    void Finish(const char*) {}
    void retain() { assert(!freed); ++references; }
    void release() {
        assert(references>0);
        if(--references==0) {
            freed=true;
            for(auto source: {ivars->timer,ivars->timerAction,ivars->reportAction})
                if(source) { assert(source->completed); source->alive=false; }
        }
    }
    int Stop(Service*,int) {
        for(auto source: {ivars->timer,ivars->timerAction,ivars->reportAction})
            if(source) assert(source->completed);
        assert(!stopped); stopped=true; release(); return 0;
    }
    int Stop_Impl(Service*provider);
};
'''
TAIL = r'''
int main() {
    // Full physical removal plus every partial-startup combination.
    for(unsigned mask=0;mask<8;++mask) {
        Source timer, timerAction, reportAction, usbTimer;
        State state, usbState;
        state.timer=(mask&1)?&timer:nullptr;
        state.timerAction=(mask&2)?&timerAction:nullptr;
        state.reportAction=(mask&4)?&reportAction:nullptr;
        usbState.timer=&usbTimer;
        Receiver receiver{&state}, usb{&usbState};
        Service provider;
        assert(receiver.Stop_Impl(&provider)==0);
        assert(receiver.Stop_Impl(&provider)==0); // Repeated Stop must not recancel.
        if(mask) assert(!receiver.stopped && !receiver.freed);
        while(!pending.empty()) {
            auto callback=pending.front(); pending.pop_front();
            callback(); Block_release(callback);
            assert(!usb.stopped && !usb.freed && usbTimer.alive);
        }
        assert(receiver.stopped && receiver.freed);
        assert(provider.references==1);
        assert(!usbState.stopping && usbTimer.calls==0);
    }
}
'''

class ShutdownTests(unittest.TestCase):
    def test_delayed_cancellation_and_partial_startup_do_not_destroy_live_sources(self):
        source = (ROOT / 'Driver/AMTRawHIDReceiver.cpp').read_text()
        start = source.index('kern_return_t IMPL(AMTRawHIDReceiver, Stop) {')
        end = len(source)
        production = source[start:end].replace(
            'kern_return_t IMPL(AMTRawHIDReceiver, Stop)',
            'int Receiver::Stop_Impl(Service *provider)')
        with tempfile.TemporaryDirectory(prefix='GesturePad-shutdown-') as directory:
            path = pathlib.Path(directory)
            (path/'shutdown.cpp').write_text(HARNESS+production+TAIL)
            subprocess.run(['xcrun','clang++','-std=c++17','-fblocks','-Wall','-Wextra',
                            str(path/'shutdown.cpp'),'-o',str(path/'shutdown')], check=True)
            subprocess.run([str(path/'shutdown')], check=True)

if __name__ == '__main__':
    unittest.main()
