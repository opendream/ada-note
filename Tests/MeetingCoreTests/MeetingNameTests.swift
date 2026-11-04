import XCTest
@testable import MeetingCore

final class MeetingNameTests: XCTestCase {
    func testRejectsEmptyAndSlashes() {
        XCTAssertFalse(MeetingName.isValid(""))
        XCTAssertFalse(MeetingName.isValid("a/b"))
        XCTAssertFalse(MeetingName.isValid("a b"))
    }

    func testAcceptsSkillNames() {
        XCTAssertTrue(MeetingName.isValid("2026-11-03-standup"))
        XCTAssertTrue(MeetingName.isValid("a.b_c-1"))
    }

    func testDefaultNameUsesLocalDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        XCTAssertEqual(
            MeetingName.defaultName(date: date, slug: "standup", timeZone: TimeZone(secondsFromGMT: 0)!),
            "2026-11-03-standup"
        )
    }
}
