# macOS

[AppleMagicTouchstream](AppleMagicTouchstream/) is the macOS app. It combines a
TouchStream-style keyboard, configurable gestures and native selected-trackpad
takeover on Apple Magic Trackpads.

From the repository root:

```sh
./mac/AppleMagicTouchstream/build.sh
./mac/AppleMagicTouchstream/test.sh
./mac/AppleMagicTouchstream/build_framework.sh
./mac/AppleMagicTouchstream/release.sh --check
```

Open `AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream.xcodeproj`,
scheme `AppleMagicTouchstream`, for Xcode. Products use the project-local
`build/DerivedData/Build/Products/` directory. Scripts work from any current directory.
Rebuild the bridge with `build_framework.sh` after native source changes; generated
frameworks are not hand-edited. `release.sh` reads identity from `project.env` and
credentials from the ignored local release configuration, then signs/notarizes.
`--check` validates configuration without publishing or using credentials.

- [Current gesture rules](AppleMagicTouchstream/GESTURE_ENGINE.md)
- [Native takeover](AppleMagicTouchstream/TRACKPAD_TAKEOVER.md)
- [Firmware findings](FINDINGS.md)
- [Implementation plan](FINGERWORKS_IMPLEMENTATION_PLAN.md)
- [Preserved research](RESEARCH_ARCHIVE.md)
- [Bundle identity](BUNDLE_IDENTITIES.md)

SDK/reference material under `sdk` stays outside the app package. Capture/replay
and hardware input are separate: offline tests do not activate takeover, post
native input or play haptics.
