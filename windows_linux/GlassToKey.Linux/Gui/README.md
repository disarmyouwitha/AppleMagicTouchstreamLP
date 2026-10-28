# GlassToKey.Linux.Gui

Early Linux GUI control shell.

For the canonical Linux status, validated host findings, and remaining-work checklist, use `../../LINUX_GOLD.md`.

Current scope:

- load the XDG-backed Linux host settings from the shared `GlassToKey.Linux.Host` library
- enumerate current trackpad candidates
- let the user assign left/right trackpads explicitly
- select the layout preset
- run the Linux `doctor` check and inspect its report in-app
- host the default desktop runtime in-process from the tray app while keeping the config window off the hotpath
- inspect a live preview of bound trackpads from that same runtime stream for visual debugging
- expose a first Ubuntu top-bar/tray shell with open, hide, doctor, capture/replay/summarize `.atpcap`, and quit actions
- open `.atpcap` replay directly inside the config visualizer with play/pause and a time scrubber instead of only producing offline output
- save back to the same Linux settings file used by the CLI/runtime
- import/export the same shared GlassToKey profile bundle shape used by Windows (`Version` + `Settings` + `KeymapJson`)

Current phase:

- this is still a starting control shell, not the finished Linux GUI
- the tray app now owns the default desktop runtime in-process
- the reusable CLI/service path remains the supported headless and engineering host
- keymap editing is now in scope for the GUI rather than being deferred out of v1
- rich diagnostics should remain primarily CLI/operator tooling; the GUI should stay focused on config, live preview, and lightweight doctor visibility
- the tray/indicator shell has been manually validated on the current Ubuntu desktop, but packaged behavior should keep being checked as the GUI evolves

Build:

- `dotnet build GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release`

Run:

- `dotnet run --project GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release`

Publish:

- framework-dependent:
  - `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- self-contained:
  - `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

Current note:

- the GUI no longer depends on the CLI executable project; both now share `GlassToKey.Linux.Host`
- the self-contained GUI publish output now includes the Linux bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`
- the GUI now uses a tray-owned in-process desktop runtime by default instead of controlling a user service for normal desktop use
- the first tray/top-bar shell uses Avalonia `TrayIcon` and a linked placeholder status icon from the repo for now
