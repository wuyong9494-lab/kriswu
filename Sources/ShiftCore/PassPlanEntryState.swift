/// 页面再次出现时，不把已经接收过的入口计划重新覆盖到正在编辑的会话里。
/// 新的入口内容仍可接收；自动扫描独立按一次请求消费，不受有没有导入计划影响。
public struct PassPlanEntryState: Sendable {
    public struct Actions: Sendable {
        public var reading: PassPlan.Reading?
        public var autoScan: Bool
    }

    private var previousReading: PassPlan.Reading?
    private var previousAutoScan = false

    public init() {}

    public mutating func consume(initial: PassPlan.Reading?, autoScan: Bool) -> Actions {
        let incoming = previousReading != initial && initial?.rows.isEmpty == false ? initial : nil
        previousReading = initial
        let shouldScan = autoScan && !previousAutoScan
        previousAutoScan = autoScan
        return Actions(reading: incoming, autoScan: shouldScan)
    }
}
