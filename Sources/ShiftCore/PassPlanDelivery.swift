import Foundation

extension PassPlan {
    /// 原图保留照片里的字；文字和重绘图片使用识别值，必须分别验收。
    public enum DeliveryFormat: Equatable, Sendable {
        case originalImage
        case recognizedContent
    }

    public static func deliveryProblems(_ row: PassPlanRow, format: DeliveryFormat,
                                        rules: [OperatorRule] = [], layout: Layout? = nil) -> [String] {
        if isExcludedFromSending(row) { return ["状态为 test，不发送给任何一家"] }
        let all = problems(row, rules: rules, layout: layout)
        guard format == .originalImage else { return all }
        // 只豁免明确属于文字抄录的疑项；站名、状态、应急、行/跨页歧义及未知疑项继续保留。
        var required = all.filter { !isTranscriptionOnlyIssue($0) }
        if row.region.map(isUsableOriginalRegion) != true {
            required.append("缺少完整的原图行，请重新选取照片")
        }
        if layout?.columns.contains(.status) == true,
           !isRecognizedPlanStatus(row.status), row.reviewedStatus != row.status {
            required.append("状态未确认，请核对原图是否为 test")
        }
        var seen = Set<String>()
        return required.filter { seen.insert($0).inserted }
    }

    /// 核对分组不能冒充核对了编号和时间。test 证据必须通过已有的状态编辑入口明确处理。
    public static func confirmedDeliveryReview(_ row: PassPlanRow, format: DeliveryFormat) -> PassPlanRow {
        var result = row
        let remaining = format == .originalImage
            ? (row.recognitionIssues ?? []).filter(isTranscriptionOnlyIssue) : []
        result.recognitionIssues = remaining.isEmpty ? nil : remaining
        result.reviewedStatus = row.status
        return result
    }

    /// 原图标题不引用 OCR 日期；原照片各行仍保留完整日期时间。
    public static func originalImageTitle(name: String, rows: [PassPlanRow]) -> String {
        "数传计划（\(name)）共 \(sendableRows(rows).count) 条"
    }

    private static func isUsableOriginalRegion(_ region: Region) -> Bool {
        guard region.page >= 0,
              [region.y0, region.slope, region.height, region.left, region.right].allSatisfy(\.isFinite),
              region.height > 0, region.left >= 0, region.right <= 1, region.right > region.left else { return false }
        return [region.left, region.right].allSatisfy { x in
            let center = region.y0 + region.slope * x
            return center - region.height / 2 >= -0.00000001 && center + region.height / 2 <= 1.00000001
        }
    }

    private static func isTranscriptionOnlyIssue(_ issue: String) -> Bool {
        let exact: Set<String> = [
            "开始时间没认全", "没有结束时间", "结束时间没认全", "结束比开始还早",
            "没认出圈号", "圈号不全是数字", "没认出卫星编号", "没认出卫星名称",
            "照片中的卫星编号需对照原图确认", "照片中的卫星代号需对照原图确认",
            "圈号由系统表格补读，请对照原图核对", "结束时间原格复识与多轮候选不一致，请核对原图",
            "结束时间由原格补读，请核对原图", "结束时间由原格复识与多轮候选核对，请核对原图",
        ]
        if exact.contains(issue) { return true }
        let fields = ["开始时间", "结束时间", "卫星编号", "卫星名称", "圈号", "数传信息"]
        if fields.contains(where: { issue == "\($0)多次识别不一致，请核对原图" }) { return true }
        return ["卫星编号", "卫星名称"].contains { label in
            issue == "\(label)未能完成独立复核，请核对原图"
                || (issue.hasPrefix("\(label)独立复识与原读数不一致（复识：")
                    && issue.hasSuffix("），请核对原图"))
        }
    }
}
