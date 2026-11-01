# AMT embedded Javelin prototype

Upstream: https://github.com/jthlim/javelin-steno
Pinned revision: 7efd1e13a74f00ba4d2e793198546e6dc83c7fbe
Required Notice: Copyright Jeffrey Lim (http://lim.au)
License: PolyForm Noncommercial 1.0.0; see LICENSE.txt (also shipped in the app).

Vendor contains upstream C++ sources, excluding ARM implementation files.
Host changes: engine.h exposes ResetHostTranslation (no output); stroke.h/.cc
adds SetChecked to reject incomplete outlines; steno_key_code_buffer.cc bounds
host text appends and throws on overflow (Bridge.cc catches and cancels edits);
pattern.cc and
hal/infrared.cc guard upstream test-only blocks for non-test desktop compilation.
steno_key_code_emitter.cc selects the host emitter with AMT_HOST_EMITTER.
SwiftPM excludes fake_processor.cc. Bridge.cc
replaces the emitter with Unicode edit collection. No firmware USB, scripting,
console, flash writing or raw key output is enabled by the host dictionaries.
The bridge never posts native input. AMT owns serial translation and gated output.

Lapwing AIO 1.5.0 JSON dictionaries are bundled under Resources/Javelin, with their
MIT license and file checksums. These are public package dictionaries copied from
Plover's installed plugin; no personal user dictionary or Plover preferences ship.
Priority follows the user's active JSON stack: commands, numbers, UK additions,
proper nouns, base. Python/modal dictionaries, Plover commands, raw key commands,
plugin macros and extended function commands are excluded from translation.
Both visible S keys produce S; all star keys produce *. # is explicit, with no
Plover automatic digit conversion (Lapwing supplies its own number dictionary).
English suffix rules are a small host-authored subset, not full Plover orthography.
Keep Plover available for extensions requiring those features.

Plover 5.4.2 stock commands/main JSON data is bundled separately under its GPLv2+
license (Resources/Javelin/Plover-LICENSE.txt), with version/source/checksums in
plover-manifest.json. No Plover Python engine or plugins are embedded. Numeric
fallback entries implement the standard basic number-key mapping for the Plover
profile only. User JSON dictionaries and their profile lists remain outside the
signed bundle; see RUNTIME.md for manager and reload behavior.
