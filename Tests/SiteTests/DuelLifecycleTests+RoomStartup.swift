import XCTest
@testable import ShiftReminder

/// Explicit suspension points: no Game Center, transport, timers, or sleeps.
@MainActor
private final class RoomStartupGate<Value> {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ name: String) { entered = XCTestExpectation(description: name) }

    func wait() async -> Value {
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }

    func resume(_ value: Value) {
        let pending = continuation
        continuation = nil
        precondition(pending != nil, "Wait for the gate before resuming it")
        pending?.resume(returning: value)
    }
}

private enum RoomStartupFailure: Error { case offline }

// Part of the existing native suite selected by fighter-lab CI.
extension DuelLifecycleTests {
    func testRemoteStartupCancelledBeforeSchedulingNeverSignsIn() async {
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("No search exists") })
        let task = startup.start(signIn: { XCTFail("Already left"); return true },
                                 findMatch: { XCTFail("Already left"); return 1 },
                                 accept: { _ in XCTFail("Already left") },
                                 discard: { _ in XCTFail("No match exists") },
                                 failed: { _ in XCTFail("Already left") })
        startup.cancel()
        await task.value
    }

    func testRemoteStartupIgnoresBothAuthenticationResultsAfterLeaving() async {
        for signedIn in [true, false] {
            let auth = RoomStartupGate<Bool>("authentication pending")
            let startup = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("No search exists") })
            let task = startup.start(signIn: { await auth.wait() },
                                     findMatch: { XCTFail("Already left"); return 1 },
                                     accept: { _ in XCTFail("Already left") },
                                     discard: { _ in XCTFail("No match exists") },
                                     failed: { _ in XCTFail("Late login must not close the room") })
            await fulfillment(of: [auth.entered], timeout: 1)
            startup.cancel()
            startup.cancel()
            auth.resume(signedIn)
            await task.value
        }
    }

    func testRemoteStartupDisconnectsLateMatchAndCancelsOnlyOnce() async {
        let match = RoomStartupGate<Int>("matchmaking pending")
        var cancellations = 0
        var discarded: [Int] = []
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { cancellations += 1 })
        let task = startup.start(signIn: { true }, findMatch: { await match.wait() },
                                 accept: { _ in XCTFail("Already left") },
                                 discard: { discarded.append($0) },
                                 failed: { _ in XCTFail("Already left") })
        await fulfillment(of: [match.entered], timeout: 1)
        startup.cancel()
        startup.cancel()
        XCTAssertEqual(cancellations, 1)
        match.resume(7)
        await task.value
        XCTAssertEqual(discarded, [7])
    }

    func testRemoteStartupSuppressesLateMatchmakingFailure() async {
        let match = RoomStartupGate<Bool>("matchmaking pending")
        var cancellations = 0
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { cancellations += 1 })
        let task = startup.start(signIn: { true }, findMatch: { () async throws -> Int in
            _ = await match.wait()
            throw RoomStartupFailure.offline
        }, accept: { _ in XCTFail("No match exists") },
        discard: { _ in XCTFail("No match exists") },
        failed: { _ in XCTFail("Late error must not close the room") })
        await fulfillment(of: [match.entered], timeout: 1)
        startup.cancel()
        match.resume(true)
        await task.value
        XCTAssertEqual(cancellations, 1)
    }

    func testRemoteStartupRestartRejectsPreviousAuthentication() async {
        let oldAuth = RoomStartupGate<Bool>("old authentication")
        let newAuth = RoomStartupGate<Bool>("new authentication")
        var accepted: [Int] = []
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("No pending search to cancel") })
        let oldTask = startup.start(signIn: { await oldAuth.wait() },
                                    findMatch: { XCTFail("Retired startup"); return 1 },
                                    accept: { _ in XCTFail("Retired startup") },
                                    discard: { _ in XCTFail("No old match exists") },
                                    failed: { _ in XCTFail("Retired startup") })
        await fulfillment(of: [oldAuth.entered], timeout: 1)
        let newTask = startup.start(signIn: { await newAuth.wait() }, findMatch: { 2 },
                                    accept: { accepted.append($0) },
                                    discard: { _ in XCTFail("Current startup") },
                                    failed: { _ in XCTFail("Current startup") })
        await fulfillment(of: [newAuth.entered], timeout: 1)
        oldAuth.resume(true)
        await oldTask.value
        newAuth.resume(true)
        await newTask.value
        XCTAssertEqual(accepted, [2])
        startup.cancel()
    }

    func testRemoteStartupLateCompletionCannotClearNewSearchOwnership() async {
        let oldMatch = RoomStartupGate<Int>("old match")
        let newMatch = RoomStartupGate<Int>("new match")
        var cancellations = 0
        var discarded: [Int] = []
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { cancellations += 1 })
        let oldTask = startup.start(signIn: { true }, findMatch: { await oldMatch.wait() },
                                    accept: { _ in XCTFail("Retired startup") },
                                    discard: { discarded.append($0) },
                                    failed: { _ in XCTFail("Retired startup") })
        await fulfillment(of: [oldMatch.entered], timeout: 1)
        let newTask = startup.start(signIn: { true }, findMatch: { await newMatch.wait() },
                                    accept: { _ in XCTFail("Already left") },
                                    discard: { discarded.append($0) },
                                    failed: { _ in XCTFail("Already left") })
        await fulfillment(of: [newMatch.entered], timeout: 1)
        XCTAssertEqual(cancellations, 1)
        oldMatch.resume(1)
        await oldTask.value
        startup.cancel()
        XCTAssertEqual(cancellations, 2, "Old completion must preserve the new search's cancellation owner")
        newMatch.resume(2)
        await newTask.value
        XCTAssertEqual(discarded, [1, 2])
    }

    func testRemoteStartupLeavingOlderRoomCannotCancelNewerRoom() async {
        let oldMatch = RoomStartupGate<Int>("old room match")
        let newMatch = RoomStartupGate<Int>("new room match")
        var oldCancellations = 0
        var newCancellations = 0
        var discarded: [Int] = []
        let oldRoom = GameRoomRemoteStartup(cancelMatchmaking: { oldCancellations += 1 })
        let newRoom = GameRoomRemoteStartup(cancelMatchmaking: { newCancellations += 1 })
        let oldTask = oldRoom.start(signIn: { true }, findMatch: { await oldMatch.wait() },
                                    accept: { _ in XCTFail("Retired room") },
                                    discard: { discarded.append($0) },
                                    failed: { _ in XCTFail("Retired room") })
        await fulfillment(of: [oldMatch.entered], timeout: 1)
        let newTask = newRoom.start(signIn: {
            XCTAssertEqual(oldCancellations, 1, "Retire the old search before starting the new room")
            return true
        }, findMatch: { await newMatch.wait() },
                                    accept: { _ in XCTFail("Already left") },
                                    discard: { discarded.append($0) },
                                    failed: { _ in XCTFail("Already left") })
        await fulfillment(of: [newMatch.entered], timeout: 1)
        oldRoom.cancel()
        XCTAssertEqual(oldCancellations, 1, "Leaving the retired room must not cancel the newer search")
        XCTAssertEqual(newCancellations, 0)
        oldMatch.resume(1)
        await oldTask.value
        newRoom.cancel()
        XCTAssertEqual(newCancellations, 1)
        newMatch.resume(2)
        await newTask.value
        XCTAssertEqual(discarded, [1, 2])
    }

    func testRemoteStartupOlderAuthenticationCannotStealNewerRoomsSearch() async {
        for oldSignedIn in [true, false] {
            let oldAuth = RoomStartupGate<Bool>("old room authentication")
            let newMatch = RoomStartupGate<Int>("new room matchmaking")
            var accepted: [Int] = []
            let oldRoom = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("Old room never searched") })
            let newRoom = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("Current match must remain active") })
            let oldTask = oldRoom.start(signIn: { await oldAuth.wait() },
                                        findMatch: { XCTFail("Superseded authentication"); return 1 },
                                        accept: { _ in XCTFail("Superseded room") },
                                        discard: { _ in XCTFail("Old room never searched") },
                                        failed: { _ in XCTFail("Superseded authentication") })
            await fulfillment(of: [oldAuth.entered], timeout: 1)
            let newTask = newRoom.start(signIn: { true }, findMatch: { await newMatch.wait() },
                                        accept: { accepted.append($0) },
                                        discard: { _ in XCTFail("The newer room owns this match") },
                                        failed: { _ in XCTFail("The newer search is still current") })
            await fulfillment(of: [newMatch.entered], timeout: 1)
            oldAuth.resume(oldSignedIn)
            await oldTask.value
            oldRoom.cancel()
            newMatch.resume(2)
            await newTask.value
            XCTAssertEqual(accepted, [2])
            newRoom.cancel()
        }
    }

    func testRemoteStartupNewRoomReservesOwnershipWhileAuthenticationIsPending() async {
        let oldAuth = RoomStartupGate<Bool>("old room authentication")
        let newAuth = RoomStartupGate<Bool>("new room authentication")
        var accepted: [Int] = []
        let oldRoom = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("Old room never searched") })
        let newRoom = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("No pending search") })
        let oldTask = oldRoom.start(signIn: { await oldAuth.wait() },
                                    findMatch: { XCTFail("New room already reserved ownership"); return 1 },
                                    accept: { _ in XCTFail("Superseded room") },
                                    discard: { _ in XCTFail("Old room never searched") },
                                    failed: { _ in XCTFail("Superseded room") })
        await fulfillment(of: [oldAuth.entered], timeout: 1)
        let newTask = newRoom.start(signIn: { await newAuth.wait() }, findMatch: { 2 },
                                    accept: { accepted.append($0) },
                                    discard: { _ in XCTFail("Current room") },
                                    failed: { _ in XCTFail("Current room") })
        await fulfillment(of: [newAuth.entered], timeout: 1)
        oldAuth.resume(true)
        await oldTask.value
        oldRoom.cancel()
        newAuth.resume(true)
        await newTask.value
        XCTAssertEqual(accepted, [2])
        newRoom.cancel()
    }

    func testRemoteStartupAcceptsCurrentMatchAndReleasesCancellationOwnership() async {
        var accepted: [Int] = []
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("Match already completed") })
        let task = startup.start(signIn: { true }, findMatch: { 42 },
                                 accept: { accepted.append($0) },
                                 discard: { _ in XCTFail("Current match") },
                                 failed: { _ in XCTFail("Current match") })
        await task.value
        XCTAssertEqual(accepted, [42])
        startup.cancel()
    }

    func testRemoteStartupReportsCurrentAuthenticationAndMatchFailures() async {
        var authenticationFailures = 0
        var matchFailures = 0
        let startup = GameRoomRemoteStartup(cancelMatchmaking: { XCTFail("No pending search") })
        let authTask = startup.start(signIn: { false },
                                     findMatch: { XCTFail("Not authenticated"); return 1 },
                                     accept: { _ in XCTFail("No match exists") },
                                     discard: { _ in XCTFail("No match exists") },
                                     failed: { error in
            XCTAssertNil(error)
            authenticationFailures += 1
        })
        await authTask.value
        let matchTask = startup.start(signIn: { true }, findMatch: { () async throws -> Int in
            throw RoomStartupFailure.offline
        }, accept: { _ in XCTFail("No match exists") },
        discard: { _ in XCTFail("No match exists") }, failed: { error in
            XCTAssertTrue(error is RoomStartupFailure)
            matchFailures += 1
        })
        await matchTask.value
        XCTAssertEqual(authenticationFailures, 1)
        XCTAssertEqual(matchFailures, 1)
        startup.cancel()
    }
}
