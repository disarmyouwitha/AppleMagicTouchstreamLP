# Linux Packaging

Packaging-specific surface for the current Linux deliverables.

For Linux implementation status, validated behavior, and the remaining work checklist, use `../../LINUX_GOLD.md` as the source of truth.

Current install artifacts:

- `90-glasstokey.rules`: starter `udev` rule for the tested Apple Magic Trackpad USB and Bluetooth vendor/product pairs plus `/dev/uinput`, now using a dedicated `glasstokey` group with `0660` modes and additive `uaccess`
- `install.sh`: install script for a published Linux build with wrapper-vs-service install decisions
- `deb/`: first Debian package skeleton, including `dpkg-deb` build script, maintainer scripts, user service unit, and optional GUI desktop entry template

Expected workflow:

1. Publish `GlassToKey.Linux`
2. Install the publish output plus `udev` rule
3. Decide whether to install only the wrapper command or also the user service file
4. Run `doctor`
5. Run `init-config`
6. Run `show-config`
7. Use `bind-left` / `bind-right` if the defaults need correction
8. Run `run-engine`

Example:

```bash
dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
sudo ./packaging/linux/install.sh --launcher-mode wrapper --service-mode user
glasstokey-linux doctor
```

Debian package example:

```bash
dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
dotnet publish GlassToKey.Linux.Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained
bash ./packaging/linux/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out
```

Notes:

- `install.sh` writes to `/opt`, `/usr/local/bin`, and `/etc/udev/rules.d`, so run it with `sudo`
- `--service-mode user` installs a user `systemd` unit but does not force-enable it; the script prints the exact `systemctl --user` commands to run next
- reconnect the trackpads after install if the refreshed `udev` permissions have not applied yet
- `deb/build-deb.sh` now expects the self-contained GUI publish output by default, so the `.deb` can carry a runnable GUI without a separate `.NET 10` GUI runtime dependency
- current host finding: the packaged rule tags the older Bluetooth trackpad node with `uaccess`, but this Ubuntu session still did not receive a live ACL on the recreated node. Because of that, the checked-in packaging strategy now prefers the dedicated `glasstokey` group model instead of relying on `uaccess` alone.
