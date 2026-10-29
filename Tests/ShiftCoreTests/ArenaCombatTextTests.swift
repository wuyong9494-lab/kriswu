import XCTest
@testable import ShiftCore

final class ArenaCombatTextTests: XCTestCase {
    func testSameTargetDamageCombinesButHealingRemainsSeparate() {
        var queue = ArenaCombatText()
        queue.add(target: 1, kind: .damage, amount: 100, time: 0)
        queue.add(target: 1, kind: .damage, amount: 200, time: 0.08)
        queue.add(target: 1, kind: .healing, amount: 50, time: 0)
        queue.add(target: 2, kind: .damage, amount: 75, time: 0)
        XCTAssertTrue(queue.drain(at: 0.1).isEmpty)
        let entries = queue.drain(at: 0.13)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].amount, 300)
        XCTAssertEqual(entries[1].amount, 50)
        XCTAssertEqual(entries[2].target, 2)
        XCTAssertTrue(queue.drain(at: 1).isEmpty)
    }
    func testQueueRemainsBoundedUnderBurst() {
        var queue = ArenaCombatText()
        for target in 0..<1000 { queue.add(target: target, kind: .damage, amount: 1, time: 0) }
        XCTAssertEqual(queue.drain(at: 1).count, 24)
    }
}
