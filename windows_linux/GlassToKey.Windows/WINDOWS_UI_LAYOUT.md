# Windows configuration layout

The configuration window follows the arrangement in the Mac application's `ContentView.swift`: a trackpad workspace on the left and a 420-pixel settings inspector on the right.

## Trackpad workspace

- Left and right device selectors and decoder selectors sit above the trackpads, alongside Refresh and the existing Mouse Takeover controls.
- The two trackpads remain side by side. The typing test spans the area below them.
- Replay controls appear above the selectors when replay is active.
- The workspace scrolls when the window is too small to show both pads. The minimum window width is 900 pixels.

## Settings inspector

- **Keyboard** is the initial tab. It contains layout selection, column tuning, key and custom-button editing, typing tuning, and existing options.
- **Gestures** contains the existing per-hand gesture settings.
- Selecting a key or custom button reveals the inspector and selects Keyboard before focusing its editor.
- **Hide Settings** expands the trackpad workspace; **Show Settings** restores the inspector.

This change reorganizes the existing controls. It does not change device selection, input processing, gesture recognition, takeover, output dispatch, haptics, or saved preferences.

## Verification

A Release build to `bin/LayoutBuild` completed with zero warnings and zero errors. The full `--selftest` suite passed.

Off-screen WPF renders checked the following configurations without constructing the live input runtime, opening device handles, installing hooks, or injecting input:

- [Keyboard inspector at 1240 × 780](WindowsDiagnostics/LayoutPreview/keyboard.png).
- [Gestures inspector at 1240 × 780](WindowsDiagnostics/LayoutPreview/gestures.png).
- [Compact window at 900 × 600](WindowsDiagnostics/LayoutPreview/compact.png).
- [Replay controls at 1240 × 780](WindowsDiagnostics/LayoutPreview/replay.png).

The renders use placeholder device choices and default settings rather than live device data or the user's preferences. On compact windows, horizontal scrolling provides access to the second pad while the inspector stays accessible.

The regular Release output was locked by the running application during verification. Exit GlassToKey from its tray menu before building the regular output from `windows_linux`:

```powershell
dotnet build .\GlassToKey.Windows\GlassToKey.Windows.csproj -c Release
```

The separately built executable is `GlassToKey.Windows\bin\LayoutBuild\GlassToKey.Windows.exe`.
