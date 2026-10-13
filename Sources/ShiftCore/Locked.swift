import Foundation

/// 加锁的全局设置：界面线程改规则、节假日的同时，后台线程在算统计、推算，读写不会撞在一起
@propertyWrapper
public final class Locked<Value> {
    private var value: Value
    private let lock = NSLock()

    public init(wrappedValue: Value) { value = wrappedValue }

    public var wrappedValue: Value {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
