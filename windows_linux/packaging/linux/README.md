# Linux Packaging

Packaging-specific surface for the current Linux deliverables.

For Linux implementation status, validated behavior, and the remaining work checklist, use `../../LINUX_GOLD.md` as the source of truth.

Current install artifacts:

- `90-glasstokey.rules`: starter `udev` rule for the tested Apple Magic Trackpad USB and Bluetooth vendor/product pairs plus `/dev/uinput`, now using a dedicated `glasstokey` group with `0660` modes and additive `uaccess`
- `deb/`: first Debian package skeleton, including `dpkg-deb` build script, maintainer scripts, user service unit, and optional GUI desktop entry template
- `arch/`: first local Arch `PKGBUILD` skeleton, including pacman install hooks, user service unit, desktop entry, and sysusers group definition

Expected workflow:

1. Publish `GlassToKey.Linux`
2. Optionally publish `GlassToKey.Linux.Gui`
3. Build a Debian package or Arch package from the publish output
4. Install through the package manager
5. Run `doctor`
6. Run `init-config`
7. Run `show-config`
8. Use `bind-left` / `bind-right` if the defaults need correction
9. For direct CLI validation, run `glasstokey start` and later `glasstokey stop`
10. For desktop use, run `glasstokey-gui` to start the tray host in background, then `glasstokey-gui --show` when you want the config window
11. Only enable the user service if you want the optional headless/background runtime path

Example:

Debian package example:

```bash
dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained
bash ./packaging/linux/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out
```

Arch local package example:

```bash
sudo pacman -S --needed base-devel dotnet-sdk
cd ./packaging/linux/arch
makepkg -f
sudo pacman -U ./glasstokey-linux-0.1.0-1-x86_64.pkg.tar.zst
```

Notes:

- the documented default install story is tray desktop first: launch `glasstokey-gui` for background tray runtime and use `glasstokey-gui --show` to open config on demand
- the documented direct headless path is `glasstokey start` / `glasstokey stop`
- package-manager installs ship a user `systemd` unit for the optional headless/background runtime path; it is not force-enabled
- reconnect the trackpads after install if the refreshed `udev` permissions have not applied yet
- `deb/build-deb.sh` now expects the self-contained GUI publish output by default, so the `.deb` can carry a runnable GUI without a separate `.NET 10` GUI runtime dependency
- current host finding: the packaged rule tags the older Bluetooth trackpad node with `uaccess`, but this Ubuntu session still did not receive a live ACL on the recreated node. Because of that, the checked-in packaging strategy now prefers the dedicated `glasstokey` group model instead of relying on `uaccess` alone.
- the Arch `PKGBUILD` path is now checked in under `packaging/linux/arch`; the next distro-expansion checkpoint is validating this install/runtime story on a real Arch environment
