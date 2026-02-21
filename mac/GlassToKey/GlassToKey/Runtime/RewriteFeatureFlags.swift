import Foundation

enum RewriteFeatureFlags {
    private static let appKitSurfaceEnvironmentKey = "GLASSTOKEY_REWRITE_APPKIT_SURFACE"

    static var useAppKitSurfaceRendererByDefault: Bool {
        if let value = ProcessInfo.processInfo.environment[appKitSurfaceEnvironmentKey] {
            switch value {
            case "1", "true", "TRUE", "yes", "YES":
                return true
            default:
                return false
            }
        }
        return false
    }
}
