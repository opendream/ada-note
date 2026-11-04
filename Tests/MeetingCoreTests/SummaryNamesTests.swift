import XCTest
@testable import MeetingCore

final class SummaryNamesTests: XCTestCase {
    func testAdvancesVersions() {
        XCTAssertEqual(SummaryNames.next(existing: []), "summary.md")
        XCTAssertEqual(SummaryNames.next(existing: ["summary.md"]), "summary-v2.md")
        XCTAssertEqual(SummaryNames.next(existing: ["summary.md", "summary-v2.md"]), "summary-v3.md")
    }
}
