import XCTest
@testable import ClaudeLightCore

final class NotificationClassifierTests: XCTestCase {
    func test_permissionMessages_areTrue() {
        XCTAssertTrue(isPermissionNotification(message: "Claude needs your permission to use Bash"))
        XCTAssertTrue(isPermissionNotification(message: "Claude needs your approval to run a command"))
        XCTAssertTrue(isPermissionNotification(message: "Permission required to edit file"))
    }

    func test_idleNudge_isFalse() {
        XCTAssertFalse(isPermissionNotification(message: "Claude is waiting for your input"))
    }

    func test_unknownOrEmpty_isFalse() {
        XCTAssertFalse(isPermissionNotification(message: ""))
        XCTAssertFalse(isPermissionNotification(message: "Some other notification"))
    }
}
