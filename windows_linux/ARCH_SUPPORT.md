# Arch Support

This is a planning note for Arch Linux validation.

Current expectation:

- Arch support looks feasible
- the Linux backend is not Ubuntu-specific
- the likely work is packaging, desktop integration, and distro validation rather than a runtime rewrite

## What Should Already Transfer

- evdev input
- `/dev/uinput` output
- `udev` rules
- XDG config/state paths
- `systemd --user`
- self-contained .NET publish

## What Needs Real Validation On Arch

### Runtime

- `glasstokey doctor`
- `glasstokey init-config`
- `glasstokey show-config --print`
- `glasstokey start`
- `glasstokey stop`
- `glasstokey run-engine 10`
- `glasstokey-gui`
- tray-owned runtime behavior
- disconnect/reconnect handling

### Permissions

- confirm the `glasstokey` group flow works as expected
- confirm `/dev/uinput` access after relogin
- confirm matched trackpad event nodes come up with the expected owner/group/mode
- confirm whether Arch session behavior differs materially from the Ubuntu `uaccess` findings

### Desktop Integration

- confirm desktop entry launch behavior
- confirm tray/top-bar behavior on the target Arch desktop
- confirm Wayland session behavior
- confirm `glasstokey show-config` launches or reopens the GUI correctly from a running tray instance

## Packaging Direction

Current `.deb` packaging is Debian/Ubuntu-specific.

For Arch, the likely package shape is:

- package recipe: `PKGBUILD`
- install CLI under `/usr/bin/glasstokey`
- install GUI under `/usr/bin/glasstokey-gui`
- install app payload under `/opt/GlassToKey.Linux` and `/opt/GlassToKey.Linux.Gui`
- install user service under `/usr/lib/systemd/user/glasstokey.service`
- install desktop entry under `/usr/share/applications/glasstokey.desktop`
- install `udev` rules under `/etc/udev/rules.d/90-glasstokey.rules`

## Likely Non-Goals For First Arch Pass

- non-`systemd` support
- broad claims across every Arch desktop environment or window manager
- a separate Arch-specific runtime path

## Tomorrow Checklist

1. Boot or install an Arch test environment.
2. Publish self-contained Linux CLI and GUI builds.
3. Install the files manually first before investing in a `PKGBUILD`.
4. Validate `doctor`, `start/stop`, `run-engine`, and GUI launch.
5. Validate `udev` + `glasstokey` group behavior after relogin.
6. If that passes, write the first `PKGBUILD`.
