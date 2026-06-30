import XCTest
@testable import ClaudeLightCore

final class SessionTests: XCTestCase {
    func test_session_roundTrips_throughJSON_withSnakeCaseKeys() throws {
        let date = Date(timeIntervalSince1970: 1_719_745_200) // fixed
        let session = Session(
            sessionID: "abc123",
            status: .running,
            project: "vatios",
            cwd: "/Users/x/vatios",
            updatedAt: date
        )

        let data = try ClaudeLightJSON.encoder.encode(session)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"session_id\":\"abc123\""))
        XCTAssertTrue(json.contains("\"status\":\"running\""))
        XCTAssertTrue(json.contains("\"updated_at\""))

        let decoded = try ClaudeLightJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
    }
}
