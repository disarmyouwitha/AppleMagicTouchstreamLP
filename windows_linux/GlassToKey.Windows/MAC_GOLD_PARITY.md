# Mac gold standard → Windows

The reference is `mac/AppleMagicTouchstream`, especially ContentView.swift,
GestureInspector.swift, HandGestureSettings.swift and GestureSessionEngine.swift.
This is a substantial functional port; the remaining differences below are real.

## Implemented

- Dark keyboard/gesture controls, a resizable inspector and resizable gesture
  navigation/detail columns. Keyboard remains the default workspace. Selecting a
  key/custom button retains the existing keyboard editor workflow.
- Gesture Left and Right select independent settings. Mirror Edit writes the same
  edit to both independent settings. Both edits a separate coordinated namespace.
  Mirror Edit never changes coordinated assignments.
- Searchable gesture actions and a shared-identity Action Builder: modifier/key
  shortcuts, Hyper, modifier-only shortcuts, apps, files, folders and URLs.
  These actions fire once, including assignments on Hold. Windows Voice uses the
  explicit Win+H invocation. Nothing starts recording during build/replay/tests.
- Four/five-finger taps, five-finger movement and per-count 2–5-finger Hold.
  New taps/movement/ordinary holds default to None. Hold thresholds are independent,
  default 500 ms, editable from 100–5000 ms.
- Cardinal directional movement for 2–5 fingers. Activation requires 3 mm of
  translation. The winning direction latches through count changes until all-up.
  Optional repeat intervals are bounded to 20–5000 ms (0 disables repeat), and
  each repeat also requires 1 mm of further forward travel. Stationary/reverse
  movement cannot generate repeated shortcuts. Continuous movement remains the
  default and retains the accepted pointer/drag/scroll profile.
- Single-pad four-corner Hold; coordinated 3/4 fingers per hand Tap/Hold; and
  coordinated outer/inner/top/bottom corner Holds. Outer Corners defaults to Open
  Config, independently for each pad and for Both. Other corner bindings default
  None. Corner targets use the outer quarter of each axis.
- TouchStream: all 43 left and 45 right traced rotated hit regions, independent
  side labels, stable row/column identities, per-key geometry overrides and the
  Mac reference GIF at 42% opacity. Column tuning is disabled. The geometry sync
  script reads the Mac source and regenerates the checked-in C# definition.
- Contact pressure labels, bounded contact trails and unknown-anatomy black
  contacts. Windows never assigns a thumb/finger color from contact order.
- Global typing Force Min/Max gates are neutralized for Windows. Per-key Force
  Instead of Hold remains available. Linux's legacy settings remain intact.

## Recognition, ownership and cleanup

All new recognition lives in Core and can be exercised without OS input. Tap
recognizers retain the existing 20 ms overlap, 80 ms landing/lift skew, 500 ms
duration, 1 mm movement limit and identity checks. Holds require a stationary
cohort within 2 mm; motion can acquire an ordinary gesture before a Hold fires.
Pending four-corner holds reserve their cycle instead of becoming tiny scrolls.
An activated motion/force/hold owner persists through membership changes until
all-up; a pressure crossing cannot replace an activated drag.

Coordinated chords require two different selected devices, landing within 80 ms,
fresh samples within 150 ms and stationary original identities within 2 mm.
Coordinated taps finish within 500 ms and 150 ms of the first partial lift.
Rejoining, replacement, invalid data, stale input and loss of eligibility cancel
the session without fallback output. Fired Holds remain one-shot until both pads
lift. An already active independent gesture takes precedence.

Native output still uses the single gated worker: eligibility, generation,
bounded queue, staleness, emergency release and failed-send cleanup apply to the
new actions. Shortcut plans have balanced key edges, including modifier-only
groups. Shortcuts skip output when existing modifiers are held, preserving keys
owned by physical input or the typing engine. Replay never creates this worker.
Settings/export round-trip the new dictionaries, with deep clones. Existing enum
numbers remain unchanged.

## Remaining differences

- Windows PTP reports do not provide trustworthy thumb/hand identity. Thumb+2,
  its diagonal swipes/holds, and thumb-dependent rotation are unavailable. Existing
  Thumb+2 tap assignments remain saved but inert on Windows. Pinch/spread retains
  the previously accepted geometric Windows recognizer; it cannot enforce the
  Mac's positive-thumb prerequisite.
- Gesture shortcuts held until release need shared ownership with the keyboard
  dispatcher's modifier/key reference counts. This port deliberately offers
  one-shot gesture shortcuts; ordinary keyboard key holds remain supported.
- Coordinated movement/directional gestures, growth of pending corner pairs
  into larger chords, and the Mac's bounded deferred keyboard-proposal arbitration
  are not ported. Current Windows gesture reservations retain their existing
  keyboard-cancellation semantics.
- Mouse Takeover retains Windows' session-only all-mouse hook and emergency
  Ctrl+Alt+R. It cannot reproduce Mac selected-device FLTR ownership. Windows shell
  3/4-finger actions may still conflict. No driver/settings changes are made.
- Windows Zoom remains Ctrl+wheel; Voice uses Windows voice typing. Haptic
  transport and strength retain their existing Windows implementation. Force
  pressure feel, speech behavior, reconnect behavior and movement feel require
  hardware acceptance. The Mac's AX autocorrection and native speech pipeline
  are platform-specific and are not claimed to be reproduced.
- Windows import/export preserves Windows settings. Automatic translation of
  the Mac host extension's gesture schema is not implemented.

## Verification and hardware handoff

Build and full `--selftest` run against the Windows project. The suite includes
the existing recorded tap/long-motion regressions and new hold/direction/chord,
custom shortcut-plan, settings export/clone and TouchStream geometry checks.
Optional off-screen rendering parses a plain XAML Window, never MainWindow's
live constructor, and opens no devices or input hooks.

The normal Release folder was locked by a running app during this work. The
verified build is `bin/MacGold/GlassToKey.Windows.exe`. Exit the old tray instance
before starting it. No live takeover or hardware input tests were run by the agent.

Hardware sequence:

1. With takeover off, inspect Keyboard, TouchStream and all gesture pages. Resize
   both column dividers. Confirm selecting a key opens its keyboard inspector.
2. Check Left/Right and Mirror Edit separately; export/import settings and verify
   the new Hold, directional and Both assignments survive.
3. Use the existing **30sec test** on a blank document. Check ordinary typing,
   two-finger tap/pointer, three-finger drag and four-finger scroll first.
4. Assign a harmless action to a 4/5-finger tap and each desired Hold. Check early
   lift, movement before the deadline, added/lifted fingers and one action per cycle.
5. Test a directional action/repeat, Hyper/shortcut and app/URL target. Check that
   held physical modifiers are not released by gesture output.
6. With two different pads selected, test Both taps/holds, the corner chords and
   the per-pad four-corner Open Config gesture. Try staggered lift and reconnect.
7. Confirm Ctrl+Alt+R and timed expiry release takeover. Capture any unexpected
   typing, delayed clicks, missed corner chords or changes in drag/scroll feel.

For optional visual QA, set `GLASSTOKEY_PREVIEW_XAML` to MainWindow.xaml and
`GLASSTOKEY_PREVIEW_DIR` to an output directory before running `--selftest`.
