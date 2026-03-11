# Linux Gold

This file tracks only what is still left to do or test for Linux.

Operational guidance, architecture boundaries, and build commands now live in `AGENTS.md`.

## Remaining Work

### 1. Real Arch Validation

- Validate the checked-in Arch package install/runtime story on a real Arch test environment.
- Document the real Arch install flow once it is proven outside the Ubuntu-hosted local package build path.

## Remaining Linux Tests

### Required

- Real Arch install test:
  - install the generated package on a real Arch environment
  - verify `glasstokey doctor`
  - verify `glasstokey init-config`
  - verify `glasstokey print-keymap` shows saved bindings and a text keymap view
  - verify desktop tray launch through `glasstokey-gui`
  - verify desktop GUI starts with no bound devices until explicit device selection is saved
  - verify headless runtime launch through `glasstokey start` / `glasstokey stop`
  - verify bare `glasstokey` from a graphical session stops detached headless runtime/service first and restores normal pointer use in the full tray host
  - verify foreground `run-engine` uses the same headless pure-keyboard policy as `start`
  - verify the packaged `glasstokey.service` user service also lands in that same headless pure-keyboard path
  - verify headless only auto-resolves trackpads when no saved stable IDs exist, and does not persist those bindings back into settings
  - verify headless stays in pure keyboard mode and ignores typing-toggle gestures/actions
  - verify packaged evdev, `/dev/uinput`, and actuator permissions

### Ongoing Regression Checks

- When Linux packaging behavior changes:
  - recheck the packaged GUI launcher path
  - recheck the packaged CLI headless path
  - recheck `doctor`
- When Linux shared dispatch/keymap behavior changes:
  - re-run Linux self-test
  - re-run representative `.atpcap` fixture checks

## Update Rule

If a Linux item here is finished:

- remove it from this file
- update `AGENTS.md` if the change affects workflows, commands, or boundaries
