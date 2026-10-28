# Linux Packaging

Packaging-specific surface for the current Linux deliverables.

For Linux implementation status, validated behavior, and the remaining work checklist, use `../../LINUX_GOLD.md` as the source of truth.

Current install artifacts:

- `90-applemagictouchstream.rules`: starter `udev` rule for the tested Apple Magic Trackpad USB and Bluetooth event nodes, the validated USB actuator hidraw nodes for both `0x0265` and `0x0324`, and `/dev/uinput`, now using a dedicated `applemagictouchstream` group with `0660` modes and additive `uaccess`
- `deb/`: first Debian package skeleton, including `dpkg-deb` build script, maintainer scripts, user service unit, and optional GUI desktop entry template
- `arch/`: first local Arch `PKGBUILD` skeleton, including pacman install hooks, user service unit, desktop entry, and sysusers group definition

Expected workflow:

1. Publish `AppleMagicTouchstream.Linux`
2. Optionally publish `AppleMagicTouchstream.Linux.Gui`
3. Build a Debian package or Arch package from the publish output
4. Install through the package manager
5. Run `doctor`
6. Run `init-config`
7. Run `applemagictouchstream`
8. Use `bind-left` / `bind-right` if the defaults need correction
9. For direct CLI validation, run `applemagictouchstream start` and later `applemagictouchstream stop`
10. For desktop use, run `applemagictouchstream-gui` to start the tray host in background, then `applemagictouchstream-gui --show` when you want the config window
11. Only enable the user service if you want the optional headless/background runtime path

Example:

Debian package example:

```bash
dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
dotnet publish AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained
bash ./AppleMagicTouchstream.Linux/packaging/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/applemagictouchstream-deb-out
```

Arch local package example:

```bash
sudo pacman -S --needed base-devel dotnet-sdk
cd ./AppleMagicTouchstream.Linux/packaging/arch
makepkg -f
sudo pacman -U ./applemagictouchstream-linux-0.1.0-1-x86_64.pkg.tar.zst
```

Notes:

- the documented default install story is tray desktop first: launch `applemagictouchstream-gui` for background tray runtime and use `applemagictouchstream-gui --show` to open config on demand
- the documented direct headless path is `applemagictouchstream start` / `applemagictouchstream stop`
- package-manager installs ship a user `systemd` unit for the optional headless/background runtime path; it is not force-enabled
- reconnect the trackpads after install if the refreshed `udev` permissions have not applied yet
- after install, `applemagictouchstream doctor` should report `HapticsWriteAccess: ok` for each USB-bound trackpad before you expect live haptics to work
- `deb/build-deb.sh` now expects the self-contained GUI publish output by default, so the `.deb` can carry a runnable GUI without a separate `.NET 10` GUI runtime dependency
- current host finding: the packaged rule tags the older Bluetooth trackpad node with `uaccess`, but this Ubuntu session still did not receive a live ACL on the recreated node. Because of that, the checked-in packaging strategy now prefers the dedicated `applemagictouchstream` group model instead of relying on `uaccess` alone.
- the Arch `PKGBUILD` path is now checked in under `AppleMagicTouchstream.Linux/packaging/arch`; the next distro-expansion checkpoint is validating this install/runtime story on a real Arch environment

## Renamed packages

Package, command, service and permission-group names now use
`applemagictouchstream`; installation roots are `/opt/AppleMagicTouchstream.Linux`
and `/opt/AppleMagicTouchstream.Linux.Gui`. Existing Linux settings and keymaps are
copied from their previous GlassToKey locations on first use. When upgrading an
installed legacy package, stop its `glasstokey.service` and remove that package
before installing the renamed package, so two input owners do not run together.
The source rename does not change or install any running service automatically.