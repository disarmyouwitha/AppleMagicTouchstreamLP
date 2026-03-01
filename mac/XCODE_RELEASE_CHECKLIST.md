# GlassToKey Xcode Release Checklist

Project:
- Project path: `GlassToKey/GlassToKey.xcodeproj`
- Scheme: `GlassToKey`
- Configuration: `Release`

Target identity:
- Bundle ID: `ink.ranna.glasstokey`
- Product Name: `GlassToKey`
- Executable Name: `GlassToKey`

Signing and runtime:
- Team: `N9XQZJR4EP`
- Code signing style: `Automatic` in Xcode; `release.sh` builds unsigned and re-signs with `Developer ID Application`
- Hardened Runtime: enabled for Release
- Entitlements: `GlassToKey/GlassToKey/GlassToKey.entitlements`

Release build settings:
- Release `ARCHS = arm64 x86_64`
- Release `ONLY_ACTIVE_ARCH = NO`
- `MACOSX_DEPLOYMENT_TARGET = 13.5`
- Default marketing version: `1.0.0`
- Default build number: `1`

Local prerequisites:
- Install a `Developer ID Application` certificate for team `N9XQZJR4EP` in the login keychain.
- Create `release-config.env` from `release-config.env.template`.
- Fill in the certificate identity and either Apple ID or App Store Connect API key notarization credentials.

Release command:
- `./release.sh`

Expected artifact:
- Preferred: `release-output/<version>-<build>/GlassToKey-<version>.dmg`
- Fallback: `release-output/<version>-<build>/GlassToKey-<version>.zip`
