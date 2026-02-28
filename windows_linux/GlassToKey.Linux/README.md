# GlassToKey.Linux

Scaffold-only Linux app host.

Planned responsibilities:

- process entry point
- settings/config under XDG paths
- Linux runtime startup/shutdown
- device selection UI or CLI
- wiring `GlassToKey.Core` to `GlassToKey.Platform.Linux`

This project should remain thin. Most logic belongs in the shared core or the Linux platform backend.

The host's project references are scaffolded but disabled by default via `EnableSharedPortReferences=false` until the shared extraction work starts.
