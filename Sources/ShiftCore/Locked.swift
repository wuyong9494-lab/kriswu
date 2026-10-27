import Foundation

/// 加锁的全局设置：界面线程改规则、节假日的同时，后台线程在算统计、推算，读写不会撞在一起。
/// 读写都在锁里，所以可以跨线程共用（@unchecked Sendable）。全局设置写成
/// `private static let _x = Locked(wrappedValue: …)` 加一个读写它的 `static var x`：
/// 直接写 `@Locked static var` 时并发检查会认为这是没保护的全局可变状态
@propertyWrapper
public final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(wrappedValue: Value) { value = wrappedValue }

    public var wrappedValue: Value {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
