# Hyper and modifier-only actions

Primary and Hold menus in Windows and Linux include **Hyper**. It holds
Ctrl + Shift + Alt + Meta (Win on Windows, Super on Linux). Hyper stays labeled
Hyper on the keymap and in action menus.

The shortcut builder accepts selected modifier toggles with Key set to None.
Only a completely empty selection is disabled; a regular key alone also works.
Modifier keys are not duplicated in the Key list. Generic/left/right selections
retain their existing names, and macOS Option/Cmd aliases are understood.
The named preset and equivalent four generic modifiers display as Hyper.
Existing keymap labels and ordinary modifier+key shortcuts remain compatible.

DispatchShortcutHelper parses pure modifier groups without a primary key.
EngineActionResolver classifies them as Modifier, so Primary begins a held
lifetime and Hold begins at the normal hold/force threshold. Existing all-up,
stale-touch, cancellation and host teardown paths apply. These actions never
schedule repeats or inject a dummy character key.

ModifierDown/Up carry the complete modifier flags; each backend expands them
using its existing reference counts. Windows generic and explicit left
Ctrl/Shift/Alt identities share their physical-key reference index. Right-side
modifiers remain distinct; AltGr retains its existing Ctrl+RightAlt handling.
Linux keeps evdev semantic mapping and does not depend on Windows virtual keys.

Windows may intercept Ctrl+Shift+Alt+Win as the Office key, including associated
letter shortcuts. This feature does not change Windows' system shortcuts or
registry. Linux availability depends on desktop/window-manager bindings too.

## Validation

- Linux CLI: `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- selftest --hyper`.
  Covers all 15 generic combinations, platform display names, macOS aliases,
  real keymap JSON round-trips, Primary/Hold lifecycle, all-up and no repeat.
- Windows `--selftest` includes HyperModifierTests. The real SendInputDispatcher
  runs with physical output suppressed, covering two Hyper owners, overlaps,
  generic/left aliases, AltGr and disposal cleanup.
- Build both GUIs; live input behavior needs the corresponding OS/device.
