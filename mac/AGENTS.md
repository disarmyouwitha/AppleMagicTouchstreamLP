# macOS project boundaries

- `GlassToKey/`: reference app and future GlassToKey rewrite; improvements are selectively ported here.
- `AppleMagicTouchstream/`: full TouchStream emulation project, currently using the conservative keyboard bootstrap. Do not incidentally strip/rewrite its working input pipeline.
- `gesturepad/`: faithful FingerWorks gesture/chord research playground, no keyboard output. Keep the separate HID device-link refresh control and opt-in blackhole experiment intact.
- Each project is independent. Do not share source or change siblings unless the task requests it.
- Use each project's `build.sh` / `test.sh`; app identity lives in `project.env`. Preserve existing settings keys and capture formats when renaming UI/project files.
