"""Driver-free, loopback-only Gemini PR machine. No keyboard injection."""
import socket
import threading

from plover.machine.base import ThreadedStenotypeBase
from plover.machine.gemini_pr import GeminiPr, STENO_KEY_CHART

PORT = 31572
HELLO = b"AMT-GEMINIPR/1\n"


class AppleMagicTouchstream(ThreadedStenotypeBase):
    KEYS_LAYOUT = GeminiPr.KEYS_LAYOUT
    KEYMAP_MACHINE_TYPE = "Gemini PR"

    def __init__(self, params):
        super().__init__()
        self._socket_lock = threading.Lock()
        self._socket = None

    @classmethod
    def get_option_info(cls):
        return {}

    def _close(self):
        with self._socket_lock:
            client, self._socket = self._socket, None
        if client is not None:
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            client.close()

    def stop_capture(self):
        self.finished.set()
        self._close()
        super().stop_capture()

    def run(self):
        self._initializing()
        while not self.finished.is_set():
            try:
                client = socket.create_connection(("127.0.0.1", PORT), timeout=0.5)
                client.settimeout(0.25)
                with self._socket_lock:
                    if self.finished.is_set():
                        client.close()
                        break
                    self._socket = client
                client.sendall(HELLO)
                response = b""
                while len(response) < 6 and not self.finished.is_set():
                    part = client.recv(6 - len(response))
                    if not part:
                        raise OSError("Connection closed during setup")
                    response += part
                if response != b"READY\n":
                    raise OSError("Unsupported AppleMagicTouchstream connection")
                self._ready()
                packet = bytearray()
                while not self.finished.is_set():
                    try:
                        data = client.recv(6 - len(packet))
                    except socket.timeout:
                        continue
                    if not data:
                        raise OSError("AppleMagicTouchstream disconnected")
                    packet.extend(data)
                    if len(packet) != 6:
                        continue
                    if packet[0] & 0x80 and not any(b & 0x80 for b in packet[1:]):
                        keys = [STENO_KEY_CHART[i * 7 + bit]
                                for i, value in enumerate(packet)
                                for bit in range(7) if value & (0x40 >> bit)]
                        if keys:
                            self._notify_keys(keys)
                    packet.clear()
            except OSError:
                if not self.finished.is_set():
                    self._error()
            finally:
                # A partial packet belongs only to this connection. Never carry
                # it into a reconnect or queue strokes for a future connection.
                self._close()
            self.finished.wait(0.5)
        self._stopped()
