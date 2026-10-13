import Foundation

extension String {
    /// 全角数字、字母换成半角（「２０２６年１０月９日」「组Ａ」）；中文和标点不动
    public var halfwidthAlnum: String {
        guard unicodeScalars.contains(where: { (0xFF10...0xFF5A).contains($0.value) }) else { return self }
        var out = String.UnicodeScalarView()
        for u in unicodeScalars {
            switch u.value {
            case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
                out.append(Unicode.Scalar(u.value - 0xFEE0)!)
            default:
                out.append(u)
            }
        }
        return String(out)
    }
}
