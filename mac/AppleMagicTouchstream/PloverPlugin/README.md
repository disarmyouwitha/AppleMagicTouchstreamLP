# AppleMagicTouchstream Plover plugin (Mac)

The machine source and wire protocol are the same as the Windows plugin. The Mac
keeps its own bundle copy so the Windows app/build paths remain intact.

1. Select either STENO layout in the Mac app. Set **Connection → Plover Plugin**.
2. Click **Install Plugin / Update Plugin**. The bundled wheel installs into
   Plover's user-plugin directory with Plover's own Python. No separate Python,
   driver, COM pair, network download or administrator access is needed.
3. Restart Plover. In **Configure → Machine**, select **AppleMagicTouchstream** and
   enable Plover output. The plugin reconnects automatically when the Mac app
   restarts; there is no port path to copy. Existing Gemini PR key mappings apply.

The native app listens only on `127.0.0.1:31572` while a live STENO layout uses the
plugin option. The client sends `AMT-GEMINIPR/1\n`, the app replies `READY\n`, then
sends six-byte Gemini PR packets. Incomplete/invalid setup is rejected. Lost/full
connections drop strokes and never queue them for the next connection. Reset
closes the reader so Plover reconnects without receiving stale buffered strokes.
The plugin is the default for new/missing connection settings. An explicitly saved
**Gemini PR Serial** choice remains available; only one sends strokes at a time. Replay opens neither transport.

The Install button does not launch Plover or change its machine/output settings.
It uses the installed Plover.app's bundled Python and Plover's plugin installer,
with `--no-index --no-deps --upgrade --force-reinstall` and the bundled wheel. Failure output is shown
in the panel. The panel checks Plover's installed package/source and disables the
button as **Plugin Installed** when it matches the bundled wheel. Outdated copies
show **Update Plugin**. Status beside it is green when connected and red otherwise.
If the standard Plover application is missing, choose Plover.app.

To rebuild the deterministic wheel and its app resource copy:

```sh
python3 PloverPlugin/build_plugin.py
python3 PloverPlugin/test_plugin.py
./test.sh --filter PloverConnectionTests
```

Swift tests open private ephemeral-port servers. When Plover.app is available,
they load its real machine base and verify exact packets/reconnects, then test the
installer against a temporary Plover profile. These tests never install into the
user's Plover profile, enable native input or start the Plover GUI.

References: [Plover command-line/plugin installer](https://plover.readthedocs.io/en/v5.4.2/cli_reference.html),
[Gemini PR source](https://github.com/openstenoproject/plover/blob/main/plover/machine/gemini_pr.py).
