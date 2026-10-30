# AppleMagicTouchstream for Plover (Windows)

1. Close Plover and double-click `Install-PloverPlugin.cmd`. If prompted, select
   `plover_console.exe` in your Plover installation. This installs the bundled
   Python wheel into Plover, without a separate Python installation or driver.
2. Restart Plover. In **Configure → Machine**, select **AppleMagicTouchstream**.
   Existing Gemini PR key mappings are compatible. Enable Plover output.
3. In AppleMagicTouchstream, select **STENO** or **STENO Voyager**, bind your
   trackpads and enable Mouse Takeover. Both pads contribute to one stroke;
   the stroke sends when both hands lift. Ordinary typing and gestures pause.

The plugin reconnects automatically over `127.0.0.1:31572`. Select a STENO
layout to open that connection; leaving STENO or quitting closes it. No COM pair,
driver, internet connection or firewall change is required. Disconnected/full
output drops strokes instead of saving them for a later connection. The app's
Steno panel shows connection state, sent/dropped counts and errors.

STENO is the Mac's Asterisk-style geometry. STENO Voyager retains the existing
6×3 column tuning and its own thumb pairs. Each layout saves mappings independently;
all 42 `STN_*` wire-key assignments are available in the action picker. Hold and
ordinary keyboard actions do not fire in STENO. Lift both hands after changing a
layout/mapping/layer. Ctrl+Alt+R releases Mouse Takeover as usual.

Mac is unchanged and continues using its native Gemini PR serial endpoint.
This plugin's local connection is presently implemented in the Windows app.

For a source build, run `python build_plugin.py` before building the Windows app.
The wheel is deterministic and contains only Python source and package metadata.
It uses Plover's own Gemini PR key chart and machine API. References:
[Plover plugins](https://plover.wiki/index.php/Plugins),
[Gemini PR implementation](https://github.com/openstenoproject/plover/blob/main/plover/machine/gemini_pr.py).
