# macOS bundle identity

| Product | Bundle ID | Team |
| --- | --- | --- |
| AppleMagicTouchstream | `ink.ranna.applemagictouchstream` | `N9XQZJR4EP` |

`AppleMagicTouchstream/project.env`, its Xcode project and signed entitlements are
the source of truth for a build. The app uses Developer ID signing/notarization,
with native FLTR input takeover. It embeds no custom DriverKit extension or takeover
helper and requires no new driver entitlement grant for that path.

Existing serialized settings/captures and preference migration remain compatible.
Documentation cleanup does not change those on-disk names or Apple Developer account
registrations. OpenMultitouchSupportXCF retains its own framework identity.
Never commit provisioning profiles, signing credentials or notarization secrets.
