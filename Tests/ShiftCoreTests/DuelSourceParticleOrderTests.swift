import XCTest
@testable import ShiftCore

final class DuelSourceParticleOrderTests: XCTestCase {
    private func item(_ emitter: Int, mode: Int = 0, age: Double = 0,
                      depth: Double = -1, order: Int = 0, queue: Int = 3000) -> DuelSourceParticleOrder.Item {
        .init(emitter: emitter, sortingLayer: 0, sortingOrder: order,
              renderQueue: queue, mode: mode, age: age, viewDepth: depth)
    }

    func testOldestAndYoungestFrontRetainAgeTies() throws {
        XCTAssertEqual(try DuelSourceParticleOrder.indices([
            item(0, mode: 2, age: 4), item(0, mode: 2, age: 0.1),
            item(0, mode: 2, age: 2), item(0, mode: 2, age: 2)]), [1, 2, 3, 0])
        XCTAssertEqual(try DuelSourceParticleOrder.indices([
            item(0, mode: 3, age: 4), item(0, mode: 3, age: 0.1),
            item(0, mode: 3, age: 2), item(0, mode: 3, age: 2)]), [0, 2, 3, 1])
    }

    func testDepthDrawsFarParticlesFirstAndNoneRetainsSourceOrder() throws {
        XCTAssertEqual(try DuelSourceParticleOrder.indices([
            item(0, mode: 4, depth: -2), item(0, mode: 4, depth: -9),
            item(0, mode: 4, depth: -4)]), [1, 2, 0])
        XCTAssertEqual(try DuelSourceParticleOrder.indices([
            item(0, age: 9, depth: -2), item(0, age: 1, depth: -9)]), [0, 1])
    }

    func testInterleavedEmittersAreGroupedBeforeAgeSorting() throws {
        let values = [item(0, mode: 2, age: 9), item(1, mode: 3, age: 2),
                      item(0, mode: 2, age: 1), item(1, mode: 3, age: 8)]
        XCTAssertEqual(try DuelSourceParticleOrder.indices(values), [2, 0, 3, 1])
    }

    func testRendererOrderPrecedesQueueAndStableEmitterTies() throws {
        let values = [item(0, order: 1, queue: 3000), item(1, queue: 3003),
                      item(2, queue: 3000), item(3, queue: 3000)]
        XCTAssertEqual(try DuelSourceParticleOrder.indices(values), [2, 3, 1, 0])
    }

    func testRejectsMixedEmitterConfigurationAndInvalidNumericKeys() {
        XCTAssertThrowsError(try DuelSourceParticleOrder.indices([item(0, mode: 2), item(0, mode: 3)]))
        XCTAssertThrowsError(try DuelSourceParticleOrder.indices([item(0, age: .nan)]))
        XCTAssertThrowsError(try DuelSourceParticleOrder.indices([item(0, depth: .infinity)]))
        XCTAssertThrowsError(try DuelSourceParticleOrder.indices([item(0, age: -0.1)]))
        XCTAssertThrowsError(try DuelSourceParticleOrder.indices([item(0, mode: 1)]))
    }
}
