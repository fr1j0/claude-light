import Foundation

public func isPermissionNotification(message: String) -> Bool {
    let m = message.lowercased()
    return m.contains("permission") || m.contains("approval")
}
