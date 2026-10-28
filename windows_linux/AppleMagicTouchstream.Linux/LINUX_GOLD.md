# Linux validation notes

## Hyper/modifier-only actions — 2026-10-24

Implemented the shared Hyper preset and pure modifier-group semantics, Linux
semantic dispatch expansion, and GUI Key: None modifier-only builder.

- Focused offline `selftest --hyper` passes on the macOS development host.
- Linux CLI and GUI compile; no physical Linux input or desktop activation tested.
- Full Linux `selftest` currently stops at the existing bundled keymap validation:
  Windows-specific EMOJI is present. Do not treat the focused run as a full-suite pass.
- GUI restore reports an existing NuGet advisory for Tmds.DBus.Protocol 0.16.0
  (GHSA-xrw6-gwf8-vvr9); dependency remediation is separate from this feature.
- Remaining hardware check: hold Hyper, type with the other pad, overlap a standalone
  Shift/Ctrl/Alt/Super, lift in either order, repeat with Hyper as Hold, then quit
  with Hyper held and verify ordinary typing. Desktop bindings may intercept keys.

No validation install, device grab, startup service, or package was created.

## Application rename — 2026-10-27

Source projects, namespaces, CLI/GUI launchers and packaging now use
AppleMagicTouchstream. CLI and GUI Release builds pass; focused Hyper tests pass.
GUI restore reports the existing Tmds.DBus.Protocol 0.16.0 NU1903 advisory.
Dependency versions were preserved during the rename. No Linux service, package,
permission group or device configuration was installed or changed on a host.