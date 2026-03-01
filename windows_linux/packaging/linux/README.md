# Linux Packaging

Current install artifacts:

- `90-glasstokey.rules`: starter `udev` rule for the tested Apple Magic Trackpad USB and Bluetooth vendor/product pairs plus `/dev/uinput`
- `install.sh`: first install script for a published Linux build

Expected workflow:

1. Publish `GlassToKey.Linux`
2. Install the publish output plus `udev` rule
3. Run `doctor`
4. Run `init-config`
5. Run `run-engine`

Example:

```bash
dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained
sudo ./packaging/linux/install.sh
glasstokey-linux doctor
```
