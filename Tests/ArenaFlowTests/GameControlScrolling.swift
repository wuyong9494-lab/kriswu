import XCTest

extension XCTestCase {
    func revealGameControl(of button: XCUIElement, within scroll: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        let safe = scroll.frame.insetBy(dx: 10, dy: 16)
        for _ in 0..<24 {
            if button.exists, button.isHittable, safe.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)) { return }
            let moveUp = !button.exists || button.frame.isEmpty || button.frame.midY > safe.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: moveUp ? 0.8 : 0.2))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: moveUp ? 0.2 : 0.8))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("未能滚动至可点击中心，\(button.identifier)，\(button.frame)", file: file, line: line)
    }
}
