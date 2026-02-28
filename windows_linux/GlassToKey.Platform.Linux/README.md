# GlassToKey.Platform.Linux

Scaffold-only project for the future Linux systems backend.

Planned responsibilities:

- enumerate Magic Trackpad devices from Linux input nodes
- assemble multitouch frames from evdev Type B slots
- expose Linux device capabilities and stable IDs
- inject keyboard and mouse output through `uinput`
- surface Linux-specific diagnostics and permission checks

This project should not contain gesture behavior or layout logic. Those belong in `GlassToKey.Core`.
