# Modifier-only actions and Hyper

GitHub issue [#98](https://github.com/disarmyouwitha/AppleMagicTouchstreamLP/issues/98)
requests modifier-only shortcuts. Primary and Hold action menus now include
**Hyper**, meaning Command + Option + Control + Shift. In the shortcut editor,
select modifier toggles and leave Key at None to create a modifier-only action.
Modifier keys are absent from the Key dropdown. All four toggles produce a Hyper
equivalent; the dedicated Hyper preset remains available. With no modifiers,
a regular Key is also valid. Only the entirely empty combination is disabled.

Hyper keeps the existing key-action encoding: Command keycode plus the four
modifier flags. Modifier-only labels omit a trailing key/separator; legacy labels with a
modifier in the final-key position still load and populate the toggles. Hyper
itself populates all four toggles with Key at None. Custom shortcuts retain their
modifier variants in serialized labels. No new
profile schema or permission is required. Both survive keymap import/export.

The engine expands combinations into reference-counted modifier components.
Overlapping Hyper and standalone modifier contacts share ownership; lifting one
must not release the other's modifier. Components release on lift, missing-contact
cleanup, cancellation or reset. Modifier combinations never enter key repeat.
A modifier action assigned to Hold starts after its configured hold/force threshold
and stays down until the original contact ends, without also firing Primary.

Offline production-engine tests cover catalog availability, custom combinations,
keymap round-trips, Hyper plus typing, overlapping Shift in both release orders,
missing terminal records, Hold, reset and repeat suppression. Live OS shortcut
recognition remains a hardware test.


The dedicated Hyper preset and the generic four-modifier-only combination display
as **Hyper** in Primary/Hold menus and on keys. Parsing for the builder retains
all four toggles and Key at None; serialization is unchanged.

## Run at Startup

AppleMagicTouchstream now mirrors GlassToKey's Mode Toggles control and
LaunchAtLoginManager, using SMAppService.mainApp without a helper. It defaults
off, reconciles the persisted preference at app launch, and resynchronizes the
checkbox from actual service status on config load and after changes/errors.
Keymap imports apply an included startup preference and report failures; exports
already include it. Build/tests do not register login items. Login launch and
registration approval require an explicit user test of the installed app.
