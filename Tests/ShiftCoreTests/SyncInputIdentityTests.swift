import XCTest
@testable import ShiftCore

final class SyncInputIdentityTests: XCTestCase {
    private let original = SyncInputIdentity(aliases: ["张三"], sourceURL: "https://example.invalid/a",
                                             sourceUsername: "account-a", syncViaWeb: true)

    func testUnchangedInputCanCommitACompletedResult() {
        XCTAssertTrue(original.canCommit(current: original, isCancelled: false))
    }

    func testEachFetchInputChangeRejectsTheOldResultAndRequiresANewRun() {
        let changed = [
            SyncInputIdentity(aliases: ["李四"], sourceURL: original.sourceURL,
                              sourceUsername: original.sourceUsername, syncViaWeb: original.syncViaWeb),
            SyncInputIdentity(aliases: original.aliases, sourceURL: "https://example.invalid/b",
                              sourceUsername: original.sourceUsername, syncViaWeb: original.syncViaWeb),
            SyncInputIdentity(aliases: original.aliases, sourceURL: original.sourceURL,
                              sourceUsername: "account-b", syncViaWeb: original.syncViaWeb),
            SyncInputIdentity(aliases: original.aliases, sourceURL: original.sourceURL,
                              sourceUsername: original.sourceUsername, syncViaWeb: false),
        ]
        for current in changed {
            XCTAssertFalse(original.canCommit(current: current, isCancelled: false))
            XCTAssertTrue(current.requiresNewRun(after: original, previousCancelled: false,
                                                 userInitiated: false, previousUserInitiated: false))
        }
    }

    func testRestoreCancellationRejectsResultsEvenForTheSameAccountAndSource() {
        XCTAssertFalse(original.canCommit(current: original, isCancelled: true))
        XCTAssertTrue(original.requiresNewRun(after: original, previousCancelled: true,
                                              userInitiated: true, previousUserInitiated: true))
    }

    func testReplacementRunCanBeReusedInsteadOfRetryingTheCancelledRunForever() {
        // 等到已取消的旧任务要重新开始；新的同输入任务结束后可直接复用，不再继续重启。
        XCTAssertTrue(original.requiresNewRun(after: original, previousCancelled: true,
                                              userInitiated: true, previousUserInitiated: true))
        XCTAssertFalse(original.requiresNewRun(after: original, previousCancelled: false,
                                               userInitiated: true, previousUserInitiated: true))
    }

    func testManualRefreshRetriesAnAutomaticRunButAutomaticWaitersReuseIt() {
        XCTAssertTrue(original.requiresNewRun(after: original, previousCancelled: false,
                                              userInitiated: true, previousUserInitiated: false))
        XCTAssertFalse(original.requiresNewRun(after: original, previousCancelled: false,
                                               userInitiated: false, previousUserInitiated: false))
        XCTAssertFalse(original.requiresNewRun(after: original, previousCancelled: false,
                                               userInitiated: false, previousUserInitiated: true))
    }

    func testMissingPreviousIdentityCannotStandInForTheCurrentRequest() {
        XCTAssertTrue(original.requiresNewRun(after: nil, previousCancelled: false,
                                              userInitiated: false, previousUserInitiated: false))
    }
}
