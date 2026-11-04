import XCTest
@testable import ShiftCore

final class WeChatReminderGateTests: XCTestCase {
    private let today = DayKey(year: 2032, month: 6, day: 18)
    private let yesterday = DayKey(year: 2032, month: 6, day: 17)
    private let tomorrow = DayKey(year: 2032, month: 6, day: 19)
    private let identity = WeChatReminderGate.Identity(aliases: ["示例甲"], sourceURL: "https://example.invalid/a",
                                                       sourceUsername: "account-a", recipientToken: "test-recipient-a")

    func testAutomaticAndShortcutRequestsShareOneInFlightSlotWithoutMarkingSent() throws {
        var gate = WeChatReminderGate()
        let persisted = WeChatReminderGate.SentDates(morning: yesterday)
        let automatic = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: persisted))
        XCTAssertNil(gate.begin(.morning, on: today, identity: identity, sent: persisted),
                     "快捷指令不能与自动补发同时发送同一天的同一条")
        XCTAssertEqual(persisted.morning, yesterday, "领取占位没有把已发提前写成今天")
        gate.abandon(automatic)
        XCTAssertNotNil(gate.begin(.morning, on: today, identity: identity, sent: persisted))
    }

    func testRestartDuringSynchronizationCanRetryBecauseOnlyMemoryHadTheReservation() {
        var beforeExit = WeChatReminderGate()
        let persisted = WeChatReminderGate.SentDates()
        XCTAssertNotNil(beforeExit.begin(.week, on: today, identity: identity, sent: persisted))
        var afterRestart = WeChatReminderGate()
        XCTAssertNotNil(afterRestart.begin(.week, on: today, identity: identity, sent: persisted))
        XCTAssertNil(persisted.week)
    }

    func testNetworkFailureReleasesReservationWithoutChangingAnySentDate() throws {
        var gate = WeChatReminderGate()
        let persisted = WeChatReminderGate.SentDates(morning: yesterday, evening: yesterday, week: today)
        let request = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: persisted))
        XCTAssertNil(gate.finish(request, succeeded: false, hasData: true, cancelled: false,
                                 currentIdentity: identity, currentDay: today, sent: persisted))
        XCTAssertEqual(persisted.week, today)
        XCTAssertNotNil(gate.begin(.morning, on: today, identity: identity, sent: persisted))
    }

    func testSuccessfulNoDataNoticeDoesNotSuppressLaterScheduleDelivery() throws {
        for kind in [WeChatReminderGate.Kind.morning, .evening, .week] {
            var gate = WeChatReminderGate()
            let persisted = WeChatReminderGate.SentDates()
            let request = try XCTUnwrap(gate.begin(kind, on: today, identity: identity, sent: persisted))
            XCTAssertNil(gate.finish(request, succeeded: true, hasData: false, cancelled: false,
                                     currentIdentity: identity, currentDay: today, sent: persisted))
            XCTAssertNotNil(gate.begin(kind, on: today, identity: identity, sent: persisted))
        }
    }

    func testSuccessCommitsOnlyItsDatesAndPreservesOtherCompletedRequests() throws {
        var gate = WeChatReminderGate()
        var persisted = WeChatReminderGate.SentDates(evening: yesterday)
        let morning = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: persisted))
        let week = try XCTUnwrap(gate.begin(.week, on: today, identity: identity, sent: persisted))
        persisted = try XCTUnwrap(gate.finish(week, succeeded: true, hasData: true, cancelled: false,
                                             currentIdentity: identity, currentDay: today, sent: persisted))
        persisted = try XCTUnwrap(gate.finish(morning, succeeded: true, hasData: true, cancelled: false,
                                             currentIdentity: identity, currentDay: today, sent: persisted))
        XCTAssertEqual(persisted, .init(morning: today, evening: yesterday, week: today))
        XCTAssertNil(gate.begin(.morning, on: today, identity: identity, sent: persisted))
        XCTAssertNil(gate.begin(.week, on: today, identity: identity, sent: persisted))
    }

    func testLateMorningFailureCannotUndoAnEveningSuccess() throws {
        var gate = WeChatReminderGate()
        var persisted = WeChatReminderGate.SentDates()
        let morning = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: persisted))
        let evening = try XCTUnwrap(gate.begin(.evening, on: today, identity: identity, sent: persisted))
        persisted = try XCTUnwrap(gate.finish(evening, succeeded: true, hasData: true, cancelled: false,
                                             currentIdentity: identity, currentDay: today, sent: persisted))
        if let wronglyRolledBack = gate.finish(morning, succeeded: false, hasData: true, cancelled: false,
                                               currentIdentity: identity, currentDay: today, sent: persisted) {
            persisted = wronglyRolledBack
        }
        XCTAssertEqual(persisted, .init(morning: today, evening: today),
                       "晚提醒成功仍免补早提醒，失败请求没有旧快照可回滚")
        XCTAssertNil(gate.begin(.evening, on: today, identity: identity, sent: persisted))
    }

    func testCancellationDoesNotCommitEvenIfTheNetworkReturnedSuccess() throws {
        var gate = WeChatReminderGate()
        let persisted = WeChatReminderGate.SentDates()
        let request = try XCTUnwrap(gate.begin(.week, on: today, identity: identity, sent: persisted))
        XCTAssertNil(gate.finish(request, succeeded: true, hasData: true, cancelled: true,
                                 currentIdentity: identity, currentDay: today, sent: persisted))
        XCTAssertNotNil(gate.begin(.week, on: today, identity: identity, sent: persisted))
    }

    func testEveryIdentityInputPreventsLateSuccessFromMarkingTheNewIdentitySent() throws {
        let changed = [
            WeChatReminderGate.Identity(aliases: ["示例乙"], sourceURL: identity.sourceURL,
                                        sourceUsername: identity.sourceUsername, recipientToken: identity.recipientToken),
            .init(aliases: identity.aliases, sourceURL: "https://example.invalid/b",
                  sourceUsername: identity.sourceUsername, recipientToken: identity.recipientToken),
            .init(aliases: identity.aliases, sourceURL: identity.sourceURL,
                  sourceUsername: "account-b", recipientToken: identity.recipientToken),
            .init(aliases: identity.aliases, sourceURL: identity.sourceURL,
                  sourceUsername: identity.sourceUsername, recipientToken: "test-recipient-b"),
        ]
        for current in changed {
            var gate = WeChatReminderGate()
            let persisted = WeChatReminderGate.SentDates()
            let old = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: persisted))
            let fresh = try XCTUnwrap(gate.begin(.morning, on: today, identity: current, sent: persisted))
            XCTAssertNil(gate.finish(old, succeeded: true, hasData: true, cancelled: false,
                                     currentIdentity: current, currentDay: today, sent: persisted))
            XCTAssertNil(gate.begin(.morning, on: today, identity: current, sent: persisted),
                         "旧请求完成不能释放新身份自己的占位")
            XCTAssertEqual(gate.finish(fresh, succeeded: true, hasData: true, cancelled: false,
                                        currentIdentity: current, currentDay: today, sent: persisted)?.morning, today)
        }
    }

    func testOldCompletionCannotConsumeAReplacementRequestWithTheSameKey() throws {
        var gate = WeChatReminderGate()
        let persisted = WeChatReminderGate.SentDates()
        let old = try XCTUnwrap(gate.begin(.week, on: today, identity: identity, sent: persisted))
        gate.abandon(old)
        let fresh = try XCTUnwrap(gate.begin(.week, on: today, identity: identity, sent: persisted))
        gate.abandon(old)
        XCTAssertNil(gate.finish(old, succeeded: true, hasData: true, cancelled: false,
                                 currentIdentity: identity, currentDay: today, sent: persisted))
        XCTAssertNil(gate.begin(.week, on: today, identity: identity, sent: persisted))
        XCTAssertEqual(gate.finish(fresh, succeeded: true, hasData: true, cancelled: false,
                                    currentIdentity: identity, currentDay: today, sent: persisted)?.week, today)
    }

    func testYesterdayCompletionCannotOverwriteTheNewDaysSuccessfulMarker() throws {
        var gate = WeChatReminderGate()
        let empty = WeChatReminderGate.SentDates()
        let old = try XCTUnwrap(gate.begin(.morning, on: today, identity: identity, sent: empty))
        let fresh = try XCTUnwrap(gate.begin(.morning, on: tomorrow, identity: identity, sent: empty))
        let persisted = try XCTUnwrap(gate.finish(fresh, succeeded: true, hasData: true, cancelled: false,
                                                 currentIdentity: identity, currentDay: tomorrow, sent: empty))
        XCTAssertNil(gate.finish(old, succeeded: true, hasData: true, cancelled: false,
                                 currentIdentity: identity, currentDay: tomorrow, sent: persisted))
        XCTAssertEqual(persisted.morning, tomorrow)
    }
}
