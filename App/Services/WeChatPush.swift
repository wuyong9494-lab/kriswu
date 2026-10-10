import Foundation

/// 通过 PushPlus（pushplus.plus）把消息推到微信。
/// 用户在官网微信扫码登录后拿到 token，消息会出现在「pushplus 推送加」公众号里。
/// 只发送自己的分工信息，不发送网页上的其它内容。
enum WeChatPush {
    enum PushError: LocalizedError {
        case noToken
        case server(String)

        var errorDescription: String? {
            switch self {
            case .noToken: return "还没有填写 PushPlus token"
            case .server(let msg): return "PushPlus 返回：\(msg)"
            }
        }
    }


    static func send(title: String, content: String, token: String) async throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw PushError.noToken }

        var request = URLRequest(url: URL(string: "https://www.pushplus.plus/send")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": token,
            "title": title,
            "content": content,
            "template": "txt",
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = json["code"] as? Int ?? -1
        guard code == 200 else {
            // msg 只是笼统的「服务端验证错误」，具体原因（未实名、未关注公众号、token 无效…）在 data 里
            let msg = json["msg"] as? String ?? "错误 \(code)"
            let detail = (json["data"] as? String).map { "：\($0)" } ?? ""
            throw PushError.server("\(msg)\(detail)（\(code)）")
        }
    }
}
