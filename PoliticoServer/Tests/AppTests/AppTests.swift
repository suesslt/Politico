import XCTVapor
@testable import App

final class AppTests: XCTestCase {
    func testODataDateParsing() throws {
        let date = ODataDateFormatter.parse("/Date(1234567890000)/")
        XCTAssertNotNil(date)

        let formatted = ODataDateFormatter.format(Date())
        XCTAssertFalse(formatted.isEmpty)
    }

    func testODataDateWithTimezone() throws {
        let date = ODataDateFormatter.parse("/Date(1612137600000+0100)/")
        XCTAssertNotNil(date)
    }
}
