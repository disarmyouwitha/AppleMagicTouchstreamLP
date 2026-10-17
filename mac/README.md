# macOS projects

| Folder | Purpose | Xcode project / scheme | App |
| --- | --- | --- | --- |
| [GlassToKey](GlassToKey/) | GlassToKey reference and future rewrite; selectively adopt useful TouchStream gesture/gating improvements. | `GlassToKey/GlassToKey.xcodeproj` / `GlassToKey` | `GlassToKey.app` |
| [AppleMagicTouchstream](AppleMagicTouchstream/) | Full TouchStream emulation on Apple Magic Trackpads. Currently retains the conservative keyboard bootstrap; faithful emulation is the development goal. | `AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj` / `AppleMagicTouchstream` | `AppleMagicTouchstream.app` |
| [gesturepad](gesturepad/) | Independent FingerWorks/TouchStream gesture and chord playground, without keyboard output; findings can be ported to AppleMagicTouchstream. | `GesturePad/GesturePad.xcodeproj` / `GesturePad` | `GesturePad.app` |

Each folder owns its app, bridge, Swift package, tests, and fixtures. No project depends on a sibling's source. Legacy runtime symbols, settings keys, bundle identifiers, and capture schemas remain intact for compatibility.

From the repository root:

```sh
./mac/GlassToKey/build.sh
./mac/AppleMagicTouchstream/build.sh
./mac/gesturepad/build.sh
./mac/GlassToKey/test.sh
./mac/AppleMagicTouchstream/test.sh
./mac/gesturepad/test.sh
```

Scripts work from any working directory. App products are under each project's `build/DerivedData/Build/Products/Debug/`. Open the corresponding Xcode project and scheme to run interactively. Test one touch-processing app at a time.

`build_framework.sh` rebuilds that project's bridge and XCFramework using its own cache. `--release` additionally creates the bridge archive, which `checksum.sh` hashes. Normal app builds compile the local bridge through SwiftPM and do not require a prebuilt XCFramework. `release.sh --check` validates Release identity without credentials or publication. `release.sh` reads app identity from `project.env` and signing/notarization credentials from the local ignored `release-config.env`; it performs a real signed release.

Use the wrappers for fresh build caches after moving projects. Old `.build` and DerivedData folders may contain absolute paths from the previous layout.

[Architecture review](ARCHITECTURE_REVIEW.md) and [FingerWorks plan](FINGERWORKS_IMPLEMENTATION_PLAN.md) retain historical design context. The SDK reference material lives under `sdk` (outside all three Swift packages, so Xcode does not discover its legacy sample projects) and is ignored by Git.
