# GlassToKey.Core

Scaffold-only project for the future shared GlassToKey engine.

Planned responsibilities:

- input/contact models
- touch processor engine
- gesture logic
- layout generation
- keymap model
- replay/test logic
- platform-neutral semantic actions

This project should remain free of:

- WPF
- WinForms
- Raw Input
- `SendInput`
- `uinput`
- `evdev`
- tray/startup UI code

First extraction targets are documented in `../LINUX_PROJECT_SKELETON.md`.
