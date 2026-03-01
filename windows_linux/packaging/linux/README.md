# Linux Packaging

Current install artifacts:

- `90-glasstokey.rules`: starter `udev` rule for the tested Apple Magic Trackpad USB and Bluetooth vendor/product pairs plus `/dev/uinput`
- `install.sh`: install script for a published Linux build with wrapper-vs-service install decisions

Expected workflow:

1. Publish `GlassToKey.Linux`
2. Install the publish output plus `udev` rule
3. Decide whether to install only the wrapper command or also the user service file
4. Run `doctor`
5. Run `init-config`
6. Run `show-config`
7. Run `run-engine`

Example:

```bash
dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
sudo ./packaging/linux/install.sh --launcher-mode wrapper --service-mode user
glasstokey-linux doctor
```

Notes:

- `install.sh` writes to `/opt`, `/usr/local/bin`, and `/etc/udev/rules.d`, so run it with `sudo`
- `--service-mode user` installs a user `systemd` unit but does not force-enable it; the script prints the exact `systemctl --user` commands to run next
- reconnect the trackpads after install if the refreshed `udev` permissions have not applied yet
