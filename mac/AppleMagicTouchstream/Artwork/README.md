# App icon

`AppIcon.svg` uses the same traced FingerWorks-style hand as the menu-bar icon,
with a white hand on a shaded graphite macOS tile. The source silhouette came
from the user-supplied `mac/Hand.jpg`; no menu-bar behavior changes are involved.

Regenerate all ten macOS icon sizes from the repository root:

```sh
swift mac/AppleMagicTouchstream/Tools/AppIcon/render.swift
```

The generated PNGs and `Contents.json` live in the existing
`Assets.xcassets/AppIcon.appiconset`. Xcode's AppIcon setting compiles them into
`AppIcon.icns`. The SVG is an editable source asset, not a runtime dependency.
