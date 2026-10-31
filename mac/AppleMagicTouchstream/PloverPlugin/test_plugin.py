"""Private socket integration and wheel tests; never starts Plover/native output."""
import importlib.util
from pathlib import Path
import socket
import sys
import threading
import time
import types
import unittest
import zipfile

# Exercise the real plugin's connection/framing against a recording Plover API.
# The canonical chart is Plover's six groups of seven Gemini PR positions.
chart = "Fn #1 #2 #3 #4 #5 #6 S1- S2- T- K- P- W- H- R- A- O- *1 *2 res1 res2 pwr *3 *4 -E -U -F -R -P -B -L -G -T -S -D #7 #8 #9 #A #B #C -Z".split()
class RecordingMachine(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.finished = threading.Event()
        self.strokes = []
        self.errors = 0
    def _notify_keys(self, keys): self.strokes.append(keys)
    def _initializing(self): pass
    def _ready(self): pass
    def _error(self): self.errors += 1
    def _stopped(self): pass
    def start_capture(self): self.start()
    def stop_capture(self): self.finished.set(); self.join(2)

for name in ("plover", "plover.machine", "plover.machine.base", "plover.machine.gemini_pr"):
    sys.modules[name] = types.ModuleType(name)
sys.modules["plover.machine.base"].ThreadedStenotypeBase = RecordingMachine
sys.modules["plover.machine.gemini_pr"].GeminiPr = type("GeminiPr", (), {"KEYS_LAYOUT": " ".join(chart)})
sys.modules["plover.machine.gemini_pr"].STENO_KEY_CHART = chart
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("amt_test_machine", root / "plover_applemagictouchstream/machine.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def wait_for(predicate):
    until = time.monotonic() + 3
    while not predicate() and time.monotonic() < until:
        time.sleep(.01)
    return predicate()

def receive(client, length):
    data = b""
    while len(data) < length:
        part = client.recv(length - len(data))
        if not part: raise OSError("unexpected EOF")
        data += part
    return data

class PluginTests(unittest.TestCase):
    def test_binary_packets_fragmentation_reconnect_and_stop(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0)); server.listen(); server.settimeout(3)
            module.PORT = server.getsockname()[1]
            machine = module.AppleMagicTouchstream({}); machine.start_capture()
            try:
                with server.accept()[0] as client:
                    self.assertEqual(receive(client, 15), module.HELLO)
                    client.sendall(b"READY\n")
                    packet = b"\x80\x0d\x00\x00\x00\x00"
                    for part in (packet[:1], packet[1:3], packet[3:]):
                        client.sendall(part); time.sleep(.02)
                    self.assertTrue(wait_for(lambda: len(machine.strokes) == 1))
                    self.assertEqual(machine.strokes, [["K-", "P-", "H-"]])
                    client.sendall(packet[:3])  # incomplete stroke dies here
                with server.accept()[0] as client:
                    self.assertEqual(receive(client, 15), module.HELLO)
                    client.sendall(b"READY\n\x80\x00\x00\x00\x00\x01")
                    self.assertTrue(wait_for(lambda: len(machine.strokes) == 2))
                    self.assertEqual(machine.strokes[1], ["-Z"])
                    machine.stop_capture()
                    self.assertFalse(machine.is_alive())
            finally:
                machine.stop_capture()

    def test_stop_while_app_is_unavailable(self):
        with socket.socket() as unused:
            unused.bind(("127.0.0.1", 0)); module.PORT = unused.getsockname()[1]
        machine = module.AppleMagicTouchstream({}); machine.start_capture()
        time.sleep(.05); started = time.monotonic(); machine.stop_capture()
        self.assertFalse(machine.is_alive())
        self.assertLess(time.monotonic() - started, 1.5)
        self.assertEqual(machine.strokes, [])

    def test_wheel_contains_current_plugin_and_machine_registration(self):
        wheel = next((root / "dist").glob("*.whl"))
        with zipfile.ZipFile(wheel) as archive:
            self.assertEqual(archive.read("plover_applemagictouchstream/machine.py"), (root / "plover_applemagictouchstream/machine.py").read_bytes())
            entry = next(n for n in archive.namelist() if n.endswith("entry_points.txt"))
            self.assertIn(b"AppleMagicTouchstream = plover_applemagictouchstream.machine:AppleMagicTouchstream", archive.read(entry))

if __name__ == "__main__":
    unittest.main()
