# AMT embedded Javelin prototype

Upstream: https://github.com/jthlim/javelin-steno
Pinned revision: 7efd1e13a74f00ba4d2e793198546e6dc83c7fbe
Required Notice: Copyright Jeffrey Lim (http://lim.au)
License: PolyForm Noncommercial 1.0.0; see LICENSE.txt (also shipped in the app).

Vendor contains upstream C++ sources, excluding ARM implementation files.
Host changes: engine.h exposes ResetHostTranslation (no output); stroke.h/.cc
adds SetChecked to reject incomplete outlines; the host bridge exposes canonical
stroke formatting for dictionary recording; steno_key_code_buffer.cc bounds
host text appends and throws on overflow (Bridge.cc catches and cancels edits);
pattern.cc and
hal/infrared.cc guard upstream test-only blocks for non-test desktop compilation.
steno_key_code_emitter.cc selects the host emitter with AMT_HOST_EMITTER.
CMake excludes fake_processor.cc and the unused POSIX thread.cc. Bridge.cc
replaces the emitter with Unicode edit collection. No firmware USB, scripting,
console, flash writing or raw key output is enabled by the host dictionaries.
The bridge never posts native input. AMT owns serial translation and gated output.

Lapwing AIO 1.5.0 JSON dictionaries are bundled under Assets/Javelin, with their
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
license (Assets/Javelin/Plover-LICENSE.txt), with version/source/checksums in
plover-manifest.json. No Plover Python engine or plugins are embedded. Numeric
fallback entries implement the standard basic number-key mapping for the Plover
profile only. User JSON dictionaries and their profile lists remain outside the
signed bundle; see ../WINDOWS_REWRITE.md for manager and reload behavior.


## Windows binary and reproducible build

`prebuilt/win-x64/AMTJavelin.dll` is copied explicitly into Windows build/publish
output. It is x86-64, 616,960 bytes, compiled from this vendored tree with Zig
0.13.0 / Clang 18.1.6. `build-info.json` records its SHA256, upstream revision,
C API exports and system-only imports. No Python/Plover runtime is embedded.

From a POSIX host with CMake, Python3 and the official Zig 0.13.0 executable:

```
python3 build_native.py --zig /path/to/zig --output /tmp/AMTJavelin.dll
```

The script uses an isolated build directory and never replaces the bundled DLL.
Inspect exports/imports and run native parity checks before explicitly updating
the prebuilt artifact/provenance. The GNU bitfield layout option
`-mno-ms-bitfields` is required; Microsoft's default layout corrupts stroke bits.
For a Windows-native rebuild use CMake with ClangCL and a Windows SDK; the CMake
project selects the same layout flag and rejects plain MSVC. ClangCL builds are
not yet verified; the shipped artifact uses the pinned cross-compiler above.

Host offline native checks can build this CMake target as a host shared library,
then set `AMT_JAVELIN_LIBRARY=/absolute/path/to/libAMTJavelin.dylib` (or `.so`)
when running WindowsDiagnostics/MotionProfilesOffline. These tests call only the
translator, never native input. On Windows `--selftest` loads the bundled DLL.

Upstream Javelin uses PolyForm Noncommercial; retain LICENSE. Public Lapwing
and Plover dictionary data has its own bundled MIT/GPL licenses and checksum
manifests. Check those terms before distributing a commercial derivative.
