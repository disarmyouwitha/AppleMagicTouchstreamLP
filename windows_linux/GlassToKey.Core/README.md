# GlassToKey.Core

Shared Linux-facing core seam/library for the GlassToKey engine path.

Current status:

- this project is no longer scaffold-only
- it currently exposes the shared frame-target seam and `TouchProcessorRuntimeHost`
- the Linux host uses it to drive the shared engine/runtime path on Linux

Responsibilities:

- input/contact models
- shared runtime/dispatch seams
- touch processor engine extraction
- gesture logic extraction
- layout generation extraction
- keymap model extraction
- replay/test logic that can remain platform-neutral
- platform-neutral semantic actions

This project should remain free of:

- WPF
- WinForms
- Raw Input
- `SendInput`
- `uinput`
- `evdev`
- tray/startup UI code

Canonical Linux status and remaining work are documented in `../LINUX_GOLD.md`.
