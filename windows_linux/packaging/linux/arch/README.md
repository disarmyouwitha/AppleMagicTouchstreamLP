# Linux Arch Packaging (Local PKGBUILD)

This folder provides a local Arch packaging flow for lifecycle validation on a real Arch host.

Current intent:

- build `glasstokey-linux` from the current local repo state
- install both CLI and GUI self-contained publishes into `/opt`
- install wrappers (`glasstokey`, `glasstokey-gui`)
- install the shared `udev` rule under `/usr/lib/udev/rules.d`
- install the optional user service under `/usr/lib/systemd/user/glasstokey.service`
- create the `glasstokey` access group through `/usr/lib/sysusers.d/glasstokey.conf`

Prerequisites:

- `base-devel`
- `dotnet-sdk`

Build and install:

```bash
sudo pacman -S --needed base-devel dotnet-sdk
cd packaging/linux/arch
makepkg -f
sudo pacman -U ./glasstokey-linux-0.1.0-1-x86_64.pkg.tar.zst
```

Docker build (no Arch host required):

```bash
./packaging/linux/arch/build-in-docker.sh
```

Expected package output:

- `packaging/linux/arch/glasstokey-linux-<pkgver>-<pkgrel>-x86_64.pkg.tar.zst`

Container note:

- `pacman` inside the container may print a systemd key/signing hook warning; this is expected and is harmless for this local build flow.

Lifecycle validation checklist:

1. Install:
   - `sudo pacman -U ./glasstokey-linux-0.1.0-1-x86_64.pkg.tar.zst`
   - `glasstokey doctor`
   - `glasstokey init-config`
   - `glasstokey show-config --print`
   - `glasstokey start` then `glasstokey stop`
   - `glasstokey-gui`
2. Upgrade:
   - increment `pkgrel` in `PKGBUILD`
   - rebuild with `makepkg -f`
   - `sudo pacman -U ./glasstokey-linux-0.1.0-<newrel>-x86_64.pkg.tar.zst`
   - re-run `doctor`, `start`/`stop`, and GUI launch checks
3. Uninstall:
   - `sudo pacman -Rns glasstokey-linux`
   - verify wrappers and desktop entry are removed

Notes:

- this is a local package flow for validation, not an AUR publishing workflow
- the package currently targets `x86_64` because the checked-in publish profiles are `linux-x64`
- after install/upgrade, ensure your user is in the `glasstokey` group and log out/in before live input testing
