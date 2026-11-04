import XCTest
@testable import ShiftCore

final class ShareCompletionGateTests: XCTestCase {
    func testCompletedLocalActionDoesNotMarkSentOrAdvanceTheQueue() {
        var gate = ShareCompletionGate()
        var sent: Set<String> = []
        var nextOperatorOpened = false
        if gate.finish(activity: .local, completed: true, hasError: false) == true {
            sent.insert("示例运营商")
            nextOperatorOpened = true
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(nextOperatorOpened)
    }

    func testCompletedUnknownThirdPartyShareRemainsCompatible() {
        var gate = ShareCompletionGate()
        XCTAssertEqual(gate.finish(activity: .externalOrUnknown, completed: true, hasError: false), true)
    }

    func testErrorAndCancellationCannotMarkSent() {
        var error = ShareCompletionGate()
        XCTAssertEqual(error.finish(activity: .externalOrUnknown, completed: true, hasError: true), false)
        var cancellation = ShareCompletionGate()
        XCTAssertEqual(cancellation.finish(activity: .externalOrUnknown, completed: false, hasError: false), false)
        var noActivity = ShareCompletionGate()
        XCTAssertEqual(noActivity.finish(activity: .none, completed: true, hasError: false), false)
    }

    func testPresentationFailureThenLateSuccessOnlyCompletesOnce() {
        var gate = ShareCompletionGate()
        XCTAssertEqual(gate.finish(activity: .none, completed: false, hasError: false), false)
        XCTAssertNil(gate.finish(activity: .externalOrUnknown, completed: true, hasError: false))
    }

    func testRepeatedSuccessCannotAdvanceTwoOperators() {
        var gate = ShareCompletionGate()
        var completedCount = 0
        for _ in 0..<2 {
            if gate.finish(activity: .externalOrUnknown, completed: true, hasError: false) == true {
                completedCount += 1
            }
        }
        XCTAssertEqual(completedCount, 1)
    }

    func testNewPresentationHasAnIndependentCompletionGate() {
        var cancelled = ShareCompletionGate()
        XCTAssertEqual(cancelled.finish(activity: .externalOrUnknown, completed: false, hasError: false), false)
        var retry = ShareCompletionGate()
        XCTAssertEqual(retry.finish(activity: .externalOrUnknown, completed: true, hasError: false), true)
    }
}
