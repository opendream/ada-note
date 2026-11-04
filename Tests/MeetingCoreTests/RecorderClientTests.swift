import XCTest
@testable import MeetingCore

final class RecorderClientTests: XCTestCase {
    func testStatusText() {
        XCTAssertEqual(RecorderClient.parseStatus("no active meeting").recording, false)
        let live = RecorderClient.parseStatus("standup pid=42 alive=true chunks=1 lines=2\n[10:00:00] hi")
        XCTAssertTrue(live.recording)
        XCTAssertEqual(live.name, "standup")
        XCTAssertEqual(live.pid, 42)
    }

    func testStartAndStopJSON() {
        let start = RecorderClient.parseStart("{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"pid\":9,\"transcript\":\"/t.md\",\"log\":\"/r.log\"}")
        XCTAssertEqual(start?.transcript, "/t.md")
        XCTAssertEqual(start?.log, "/r.log")
        XCTAssertEqual(start?.pid, 9)
        XCTAssertEqual(start?.dir, "/repo/.meetings/standup")
        let stop = RecorderClient.parseStop("{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"stopped\":false,\"pid\":9}")
        XCTAssertEqual(stop?.stopped, false)
        XCTAssertEqual(stop?.pid, 9)
    }

    func testKillOnlyAfterSecondFailureAndConfirm() {
        let running = StopInfo(stopped: false, pid: 9, name: "standup", dir: "/repo/.meetings/standup")
        let done = StopInfo(stopped: true, pid: nil, name: "standup", dir: "/repo/.meetings/standup")
        XCTAssertEqual(StopGate.decide(first: running, second: nil, confirmedKill: false), .retry)
        XCTAssertEqual(StopGate.decide(first: running, second: running, confirmedKill: false), .askKill(pid: 9))
        XCTAssertEqual(StopGate.decide(first: running, second: running, confirmedKill: true), .kill(pid: 9))
        XCTAssertEqual(StopGate.decide(first: done, second: nil, confirmedKill: false), .final)
    }
}
