# macOS project boundaries

- `GlassToKey/`: reference app and future GlassToKey rewrite; improvements are selectively ported here.
- `AppleMagicTouchstream/`: faithful TouchStream emulation project. Remove GTK-specific recognition/product features when preparing this project; preserve the core keyboard bootstrap and capture compatibility until deliberately replaced with validated TouchStream logic. Optional haptic feedback is the user-authorized GTK exception and must remain available.
- `gesturepad/`: faithful FingerWorks gesture/chord research playground, no keyboard output. Keep the separate HID device-link refresh control and opt-in blackhole experiment intact.
- Each project is independent. Do not share source or change siblings unless the task requests it.
- Use each project's `build.sh` / `test.sh`; app identity lives in `project.env`. Preserve existing settings keys and capture formats when renaming UI/project files.
