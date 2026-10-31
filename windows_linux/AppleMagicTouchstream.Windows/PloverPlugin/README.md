# AppleMagicTouchstream for Plover (Windows)

1. Install Plover first. In AppleMagicTouchstream, select a STENO layout and click
   **Install / update Plover plugin**. Alternatively, close Plover and double-click
   `Install-PloverPlugin.cmd`. If prompted, select
   `plover_console.exe` in your Plover installation. This installs the bundled
   Python wheel into Plover, without a separate Python installation or driver.
2. Restart Plover. In **Configure → Machine**, select **AppleMagicTouchstream**.
   Existing Gemini PR key mappings are compatible. Enable Plover output.
3. In AppleMagicTouchstream, select **STENO** or **STENO Voyager**, bind your
   trackpads and enable Mouse Takeover. Both pads contribute to one stroke;
   the stroke sends when all fingers lift. Ordinary keyboard/gesture assignments pause.

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

In the STENO panel, **Pointer movement** selects **One finger** or **Two fingers**
(default). Stationary contacts still chord, including single-key strokes. Deliberate
2 mm movement acquires the pointer; two-finger mode requires both contacts to move
together. Once acquired, the entire pending stroke is cancelled until both pads
lift. The choice saves with settings and exports/imports. One- and two-finger force presses left-click; Ctrl+Alt+R releases Takeover for normal mouse use.

**Steno haptics** offers Off, On key contact (default), or On chord release. It
uses your normal haptic enable/strength settings. Held contacts do not repeat.
Release mode pulses the participating pads when the whole chord finishes; pointer
movement cancels that release pulse. Contact mode can pulse before movement is
recognized. The preference saves and exports with your settings.

One- and two-finger force presses left-click in either STENO pointer mode. A force
click cancels the pending chord; lift all fingers before the next click/stroke.
Only actual reported force is used. Ctrl+Alt+R releases Takeover if needed.
