# AGENTS

## Scope
- This file governs the `windows_linux/` working folder only.
- When working from `windows_linux/`, treat only these top-level folders as in scope:
  - `AppleMagicTouchstream.Windows/`
  - `AppleMagicTouchstream.Core/`
  - `AppleMagicTouchstream.Linux/`
- Do not treat sibling folders such as `../mac/` as in scope unless the user explicitly asks.

## Repo Shape
- `AppleMagicTouchstream.Windows/`: active Windows app and the current primary production target.
- `AppleMagicTouchstream.Core/`: shared engine/layout/keymap/input/dispatch/runtime seam library used by both Windows and Linux.
- `AppleMagicTouchstream.Linux/`: Linux product tree containing:
  - `AppleMagicTouchstream.Linux/`: CLI host
  - `AppleMagicTouchstream.Linux/Platform/`: Linux evdev/uinput/haptics backend
  - `AppleMagicTouchstream.Linux/Host/`: Linux settings/runtime/doctor host layer
  - `AppleMagicTouchstream.Linux/Gui/`: Linux Avalonia tray/config GUI
  - `AppleMagicTouchstream.Linux/packaging/`: Linux package/install artifacts

## Target Selection
- Default production target: `AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj`
- Shared extraction target: `AppleMagicTouchstream.Core/AppleMagicTouchstream.Core.csproj`
- Linux backend target: `AppleMagicTouchstream.Linux/Platform/AppleMagicTouchstream.Platform.Linux.csproj`
- Linux host target: `AppleMagicTouchstream.Linux/Host/AppleMagicTouchstream.Linux.Host.csproj`
- Linux CLI target: `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj`
- Linux GUI target: `AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj`
- If the user says "build" without more detail, prefer the target most relevant to the touched code.

## Boundaries

### Windows
- Keep Windows-only code in `AppleMagicTouchstream.Windows/`.
- Windows owns WPF, WinForms, Raw Input, `SendInput`, click suppression, tray/startup UI, Windows haptics, and Windows-hosted diagnostics.
- Preserve current Windows behavior while extracting shared code.
- Keep Windows as one top-level `AppleMagicTouchstream.Windows` app project unless the user explicitly asks for a larger architecture change.

### Core
- Keep shared engine/runtime seams, layout generation, keymap handling, input/contact models, and platform-neutral dispatch semantics in `AppleMagicTouchstream.Core/`.
- Keep `AppleMagicTouchstream.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, `uinput`, XDG/platform settings, and tray/startup/service code.
- Prefer physically moving shared behavior into `AppleMagicTouchstream.Core/` instead of rebuilding similar behavior separately in Windows or Linux.
- Shared code should not remain as linked source back into `AppleMagicTouchstream.Windows/` as a steady state.

### Linux
- Keep Linux evdev ingestion, reconnect supervision, `uinput` output, actuator-hidraw haptics, and Linux permission probing in `AppleMagicTouchstream.Linux/Platform/`.
- Keep Linux settings/config/runtime composition and host-side diagnostics in `AppleMagicTouchstream.Linux/Host/`.
- Keep `AppleMagicTouchstream.Linux/` and `AppleMagicTouchstream.Linux/Gui/` thin as shipped app surfaces.
- Linux work should consume platform-neutral models or semantics, not Windows virtual-key assumptions.
- Prefer semantic actions over Windows-VK fallback whenever the dependency boundary allows it.

## Structural Guardrails
- The Linux repo layout is intentionally nested under `AppleMagicTouchstream.Linux/`, but the project boundaries are still real.
- `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj` is the CLI project only.
- `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj` explicitly excludes `Host/**`, `Platform/**`, `Gui/**`, and `packaging/**` from default item globs.
- Do not add source files from `AppleMagicTouchstream.Linux/Host/`, `AppleMagicTouchstream.Linux/Platform/`, or `AppleMagicTouchstream.Linux/Gui/` directly to `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj`; keep those as project references.
- Treat `AppleMagicTouchstream.Linux/`, `AppleMagicTouchstream.Linux/Platform/`, `AppleMagicTouchstream.Linux/Host/`, `AppleMagicTouchstream.Linux/Gui/`, and `AppleMagicTouchstream.Linux/packaging/` as separate ownership zones even though they share one top-level folder.
- The nested repo layout does not change the installed product split:
  - CLI installs to `/opt/AppleMagicTouchstream.Linux`
  - GUI installs to `/opt/AppleMagicTouchstream.Linux.Gui`
- Do not change packaging install destinations to mirror the nested repo layout.

## Historical Windows research

[RESEARCH_ARCHIVE.md](RESEARCH_ARCHIVE.md) locates the external BT/USB research,
diagnostic scripts, exact Apple driver package, evidence logs and compressed Ghidra
projects. Active test fixtures remain in the Windows project. Archived hardware
probes are manual tools, not build steps.

## Windows Notes
- `AppleMagicTouchstream.Windows` is the active Windows app. Live mode runs as a tray/status app that reads touchpad report `0x05` via Raw Input and drives key mapping in the background.
- Core Windows hot-path/runtime file: `AppleMagicTouchstream.Windows/TouchRuntimeService.cs`
- Windows Raw Input ingestion: `AppleMagicTouchstream.Windows/RawInputInterop.cs`
- Live decoding uses `TrackpadDecoderSession`: learn from a valid touching report, retain profile/layout through movement/all-up/bad packets, and decode without fallback. Reset on device arrival/removal, selection/Refresh, identity/metadata or explicit profile changes; never persist learned Auto choices or reset the active runtime merely for unrelated configuration edits. Keep tray and standalone capture paths on this shared decoder.
- Windows output injection: `AppleMagicTouchstream.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows haptics helper: `AppleMagicTouchstream.Windows/WindowsHaptics/MagicTrackpadActuatorHaptics.cs`
- Windows diagnostics/self-test surface: `AppleMagicTouchstream.Windows/WindowsDiagnostics/`
- Windows Config has a top Gestures / Keyboard workspace selector, in that order; Keyboard remains the default. Device/takeover controls span both workspaces. Gestures replaces the visualizer and keyboard inspector with three resizable columns: navigation, assignment cards, Action inspector. Keyboard retains both pads, typing test and its separate settings inspector. Preserve named controls and runtime bindings. A single selected pad determines the initial gesture editing side; show which side is selected. Preserve disconnected saved device paths. All gesture metadata, including explicit None, round-trips through full settings exports; invalid bundles must not silently fall back to keymap-only import.
- Mac is the UI reference. TouchStream has independent traced geometry, automatic reference backgrounds and disabled column tuning. Gesture Left/Right, Mirror Edit and coordinated Both are distinct. Existing numeric enum identities must remain stable; append new identities. See `AppleMagicTouchstream.Windows/MAC_GOLD_PARITY.md` for implemented contracts, limitations and verification.
- Gesture actions, keyboard Primary/Hold actions and both shortcut-key builders share `SearchableActionComboBox`: a themed panel with category headings, dedicated search, current-choice checkmarks and empty results. Search/browsing uses a separate result view and must never filter the owning ComboBox.Items or publish a live assignment. Only an explicit result choice commits; Escape/Done/outside dismissal preserve it. Keep semantic values, configured shortcut/text labels and STENO eligibility filters. Closed selectors cannot change mappings from incidental typing/arrows/wheel. Keep release builds below `AppleMagicTouchstream.Windows/bin/`.
- The closed action picker binds `SelectedActionTitle` explicitly to the option's Title/Display (or plain key string); never render an option record's diagnostic ToString. Gesture recognition feedback comes from pure recognizer snapshots, not inferred output actions. Display the latest recognized gesture beside each pad's Peak header and in the Gestures footer for two seconds, with separate hands, coordinated Both, directions, Holds, Force and STENO. Reads cannot start input, output or hooks. Feedback is value-only, not settings/capture data, and contains no custom-action text. Continuous ownership refreshes it; normal lift retains it briefly; cancellation, stale/invalid input and configuration reset clear it. Replay must not read live recognition.
- Windows Typing Tuning exposes Hold Duration, Haptic Strength and Restore Defaults. Legacy Typing Grace, Drag Cancel and intent movement/velocity fields remain decode-compatible but cannot gate unified Windows typing. Unreserved contacts stay keyboard input; tap eligibility is bounded by max(200 ms, Hold Duration), release geometry and snap. Preserve Linux legacy policy separately.
- Gesture Hold has independent 100–5000 ms thresholds (500 default) and once/held shortcut output. Held shortcuts use the keyboard dispatch pump and shared modifier/key ownership; Left, Right and coordinated Both have distinct leases. All-up, stale/invalid input, reconfiguration, output failure, queue overflow and teardown release only the appropriate owners. Gesture keyboard events must not use the pointer worker's private native key buffers.
- Established MO/modifier chords and committed key holds retain same-pad priority through all-up. Unresolved candidates retain fixed-capacity owned keyboard proposals while gestures see original frames once. Winning/cancelled gestures discard proposals; never-activated rollover may resolve at partial lift/all-up. Generation/layer/epoch changes and invalid/stale/overflowed input cancel proposals. Live semantic keyboard publication bypasses the offline diagnostic ring and writes directly to the bounded output queue; publication overflow cancels the cycle and inserts a release barrier.
- Windows uses unified keyboard/gesture policy: typing remains enabled; the former Keyboard/Mouse mode, typing toggle and selective click filter are removed. Shared legacy mode fields remain for Linux compatibility but cannot reactivate Windows modes.
- `GlobalMouseInputHook.cs` observes mouse activity and supports explicit Mouse Takeover/diagnostic gates only. Mouse Takeover defaults off on first launch and saves explicit opt-in locally for startup restoration. Uncheck, tray release and Ctrl+Alt+R clear opt-in; tests stay temporary and lifecycle releases preserve it. Startup restoration waits/retries for delayed Bluetooth availability; explicit release, activation, sleep/session changes and disposal cancel the startup retry state. Settings write errors must be visible. The tray/app icon uses the Mac hand silhouette filled black.

- Windows hand gestures include grouped anatomical inspector sections, 1–5-finger force clicks (reported pressure only) and independent 2–5-finger pinch/spread. Keep the legacy Apple reference response available; the explicit captured-Mac option loads bundled per-hand pointer/scroll curves on configuration only. Assigned two-finger taps retain their existing 1 mm/500 ms eligibility before movement acquires. Use Mac's bounded 80 ms fourth-contact landing evidence instead of a blanket drag delay; Windows supplies confident in-range non-tip PTP slots as the available pre-contact evidence. Activated owners remain latched through all-up. A pending four-finger Hold requires three-of-four translation agreement before ordinary movement can steal it. Corner Holds anchor the completed corner chord independently of earlier generic Hold failure. Windows Zoom is balanced Ctrl+wheel; system actions use Windows shortcut plans. See `AppleMagicTouchstream.Windows/MAC_GOLD_PARITY.md` for current contracts and verification.
- Shape pages expose independent Pinch, Spread, Rotate Left and Rotate Right for every 2–5-finger count, with matching demonstrations, recognition notes and automatic Hold/Lift lifecycle cards. Rotation defaults to None. Discrete shape actions offer Once, timed (20–5000 ms) or signed motion repeat (5° rotation / 6% scale); no catch-up bursts, signed-motion reversal output or stale timers. Preserve independent Left/Right, Mirror Edit, same-device fallback and settings export/clone. PTP uses all-contact geometry without inventing thumb anatomy; positive native anatomy, when supplied offline, uses the Mac thumb-vector model. Keep Windows' accepted geometric Pinch/Spread. Per user direction, do not invent a native Rotate Content equivalent: rotation recognition runs assigned shortcuts/actions. A real movement/shape activation beats a pending Hold; an explicitly assigned reported-pressure Force may override an active shape. Preserve established Windows pointer/drag/scroll ownership through all-up.
- Pending Pointer/Drag travel must pass through the selected acceleration curve sample by sample. Retain only the resulting output privately until movement wins, then publish it once. Never run accumulated startup millimetres through the nonlinear curve as a single fast sample. Cohort rebasing/cancellation/reset clears pending output and timing; a winning tap/shape/Hold cannot publish it. Preserve activation distances, tap=None gating, the imported curve, scroll policy and post-activation response. The `2F_skips.atpcap` replay established this startup amplification independently with the recorded tap-enabled settings and an explicit tap=None comparison.

## Linux Notes
- The Linux CLI currently supports:
  - `list-devices`, `probe-axes`, `probe-uinput`, `doctor`, `init-config`
  - `print-keymap`, `bind-left`, `bind-right`, `swap-sides`, `print-udev-rules`
  - `selftest`, `read-events`, `read-frames`, `uinput-smoke`, `watch-runtime`, `run-engine`
  - `capture-atpcap`, `replay-atpcap`, `summarize-atpcap`, `write-atpcap-fixture`, `check-atpcap-fixture`
  - `pulse-haptics`
- Linux keyboard/mouse mode already uses `EVIOCGRAB` for exclusive pointer suppression when `KeyboardModeEnabled && TypingEnabled && !MomentaryLayerActive`.
- Desktop Linux runtime/device selection should stay explicit:
  - GUI defaults to no bound devices unless stable IDs were previously saved
  - do not silently persist first-available trackpads into Linux host settings on desktop startup
- Headless Linux runtime policy is now distinct from desktop:
  - `applemagictouchstream start`, `__background-run`, and `run-engine` use `HeadlessPureKeyboard`
  - the packaged user `systemd` service inherits that same headless policy because it launches `run-engine`
  - headless only auto-resolves devices when no saved left/right stable IDs exist; it does not persist those choices
  - headless forces `KeyboardModeEnabled=true`, `TypingEnabled=true`, and `ThreeFingerDragEnabled=false`
  - headless ignores typing-toggle actions so the background runtime cannot flip itself out of pure keyboard mode
  - headless also disables pointer-intent takeover in core, so it never transitions into `MouseCandidate` or `MouseActive`
  - headless exclusive grab is now policy-driven: in a graphical session it grabs evdev unconditionally for the pure-keyboard policy; in proven no-pointer environments it skips grab; `applemagictouchstream start --no-grab` and `applemagictouchstream run-engine --no-grab` explicitly opt out
- Graphical Linux config handoff should preserve mouse usability:
  - when bare `applemagictouchstream` is used from a graphical session while a detached headless runtime or user service is active, stop that headless runtime first
  - then launch the full tray host so the GUI becomes the active desktop path instead of leaving the headless runtime grabbing pointer input underneath it
- Prefer the Apple `if01` `-event-mouse` node when multiple event nodes represent one physical device.
- On the validated Ubuntu host, `EVIOCGABS` reports real ranges and Linux normalization should produce `MaxX=7612` and `MaxY=5065`.
- Linux force-click tuning uses the Linux pressure range directly; the Linux GUI force-click threshold slider is `80..255` and the bundled Linux default threshold is `80`.
- Over Bluetooth on the validated host, `/dev/input/by-id` may be absent; use `uniq` as the stable-id fallback.
- Linux packaging should use the dedicated `applemagictouchstream` group model rather than relying on `uaccess` alone.
- Linux actuator writes use the raw 14-byte `0x53` report payload on the validated host.
- Treat sandboxed `EVIOCGABS` failures as environment artifacts first, not immediate product bugs.

## Build Commands
- Run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially. Parallel publishes can collide in shared `bin/` / `obj/` paths.

### Windows
- Build:
  - `dotnet build AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release`
- Self-test:
  - `dotnet run --project AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release -- --selftest`

### Core
- Build:
  - `dotnet build AppleMagicTouchstream.Core/AppleMagicTouchstream.Core.csproj -c Release`

### Linux Builds
- Platform:
  - `dotnet build AppleMagicTouchstream.Linux/Platform/AppleMagicTouchstream.Platform.Linux.csproj -c Release`
- Host:
  - `dotnet build AppleMagicTouchstream.Linux/Host/AppleMagicTouchstream.Linux.Host.csproj -c Release`
- CLI:
  - `dotnet build AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release`
- GUI:
  - `dotnet build AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release`

### Linux Publish
- CLI framework-dependent:
  - `dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- CLI self-contained:
  - `dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- GUI framework-dependent:
  - `dotnet publish AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- GUI self-contained:
  - `dotnet publish AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

### Linux `.atpcap`
- Capture:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- capture-atpcap /tmp/capture.atpcap 10`
- Replay:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- replay-atpcap /tmp/capture.atpcap /tmp/replay-trace.json`
- Summary:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- summarize-atpcap /tmp/capture.atpcap`
- Fixture write:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- write-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json`
- Fixture check:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- check-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json /tmp/replay-trace.json`

### Linux Packaging
- Debian:
  - `bash AppleMagicTouchstream.Linux/packaging/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/applemagictouchstream-deb-out`
- Arch:
  - default non-Arch-host path:
    `./AppleMagicTouchstream.Linux/packaging/arch/build-in-docker.sh`
  - only use raw `makepkg` on a real Arch host that already has Arch tooling installed
  - if you need the raw host flow on Arch:
    `sudo pacman -S --needed base-devel dotnet-sdk`
    `cd AppleMagicTouchstream.Linux/packaging/arch`
    `makepkg -f`

## Key Files
- Windows runtime hot path: `AppleMagicTouchstream.Windows/TouchRuntimeService.cs`
- Windows Raw Input: `AppleMagicTouchstream.Windows/RawInputInterop.cs`
- Windows output injection: `AppleMagicTouchstream.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows diagnostics/self-test: `AppleMagicTouchstream.Windows/WindowsDiagnostics/SelfTestRunner.cs`
- Shared touch engine: `AppleMagicTouchstream.Core/Engine/TouchProcessorCore.cs`
- Shared keymap/layout path:
  - `AppleMagicTouchstream.Core/Keymap/KeymapStore.cs`
  - `AppleMagicTouchstream.Core/Layout/LayoutBuilder.cs`
  - `AppleMagicTouchstream.Core/Layout/KeyLayout.cs`

## Working Rules
- Prefer extraction to `AppleMagicTouchstream.Core/` over Linux-only or Windows-only reimplementation when behavior is truly shared.
- For hot paths, prefer precomputed tables and fixed-size state arrays.
- Avoid avoidable allocations, logging, and file I/O in per-frame processing.
- When evolving the Linux GUI, prefer converging toward the Windows config surface rather than inventing parallel Linux-only layouts.
- Do not add duplicate static keymap displays when the same loaded keymap can be shown directly on the live preview surface.
- If Linux device probing or validation requires real host access, request escalation instead of guessing about driver behavior.
- The user has stated they will approve out-of-sandbox access when needed for Linux device validation; still request escalation normally.
- Do not create or enable persistent validation installs, user `systemd` services, or `/opt/AppleMagicTouchstream.Linux.validation`-style test payloads unless the user explicitly asks for that lifecycle.

## Linux Tracking
- `AppleMagicTouchstream.Linux/LINUX_GOLD.md` is now Linux-only remaining work and test tracking.
- If Linux scope, status, packaging defaults, or workflow expectations change:
  - update `AGENTS.md`
  - update `AppleMagicTouchstream.Linux/LINUX_GOLD.md`
  - keep project/package READMEs short and local to their project surface


## Hyper and modifier-only actions (2026-10-24)

The shared DispatchShortcutHelper and EngineActionResolver support Hyper and
modifier-only combinations. Hyper stays named Hyper; it is Ctrl+Shift+Alt+Meta.
Both GUI builders offer Key: None with modifier toggles, plus the Primary/Hold
Hyper preset. Keep ownership reference-counted through lift/cancel/teardown;
never synthesize a dummy character or repeat pure modifier groups. Windows
left/generic modifiers share an index; right-side/AltGr semantics remain intact.
See AppleMagicTouchstream.Core/HYPER_MODIFIERS.md. Focused Linux validation is
`selftest --hyper`; it does not access evdev/uinput or write host settings.

## Windows layouts, STENO and saved Text

Current implementation and acceptance checklist: AppleMagicTouchstream.Windows/WINDOWS_REWRITE.md.
- Compile authored layout documents only on configuration/Apply. Stable key and
  mirror IDs are independent of geometry. Preserve per-hand actions and layer
  visibility; legacy custom buttons migrate only in the editor draft until Apply.
- Layout Editor is inline, both pads, fixed 1 mm snap, Mirror Edit default on,
  with bounded history and isolated 30 Hz contact overlay. No keyboard/STENO
  dispatch while editing; ordinary gestures return temporarily. Show Contacts
  suppresses 4F/5F gesture candidates, retaining normal mouse gestures.
- STENO offers Asterisk, 6x3 and RHS Single behind one main picker. Ordinary key
  actions/configurable gestures stay inert; only STN_* assignments form chords.
  Outer Corners remains Open Config. Fixed 2F pointer, 1F force drag, 2F force
  primary, 3F force secondary, 4F latched force scroll/momentum. Owners remain
  through all-up/count changes; final shared drag owner releases the button.
- Built-in Javelin Lapwing is default; Plover data and loopback Plover plugin are
  alternatives. Mouse Takeover/live generation/focus gates still apply. Native
  translation is serial and never posts input itself. Bundled dictionary edits
  require Save As. Never ship personal dictionaries. Preserve native licenses.
- Independent settled touch/release haptics cancel with pending chords. Force
  feedback is fixed; all haptics remain dispatch-queued and live-only.
- Both 3+3/4+4 force uses reported pressure only, bounded 1 second cohort join
  and 150 ms force-crossing skew, latched through both-all-up. Never replace an
  activated independent owner. Pending corner pairs may grow before firing.
- Saved Text uses DPAPI CurrentUser with no plaintext fallback, opaque refs in
  settings/captures, hidden-by-default editor and worker decryption. Another
  same-user process is not excluded by DPAPI. Type Unicode through the existing
  output pump without clipboard use; cancel on focus/lifecycle/generation loss.
- ATPCAP bytes remain unchanged; the additive settings companion contains initial
  documents/refs, never secrets. Replay is output-free and never reads the vault.
- Windows PTP remains five contacts per pad; do not infer thumb anatomy/force.
  Tests use host translation/private ephemeral sockets, never live Plover/input.
