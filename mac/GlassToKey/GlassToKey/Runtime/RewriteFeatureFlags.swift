import Foundation

enum RewriteFeatureFlags {
    private static let appKitSurfaceEnvironmentKey = "GLASSTOKEY_REWRITE_APPKIT_SURFACE"

    static var useAppKitSurfaceRendererByDefault: Bool {
        boolEnvironmentValue(for: appKitSurfaceEnvironmentKey)
    }

    private static func boolEnvironmentValue(for key: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            return false
        }
        switch value {
        case "1", "true", "TRUE", "yes", "YES":
            return true
        default:
            return false
        }
    }
}
