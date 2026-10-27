import Foundation

/// 读存档（设置、周会、记录）：每一项单独容错。
/// 存档里某一项格式不对（老版本存的、新版本改过类型）只有那一项用默认值，别的照读；存档里没有的项也用默认值。
/// 所以新加的设置项只要写好默认值，不用再写读取代码。
enum TolerantCoding {
    /// stored：存档里这个对象（JSONSerialization 读出来的字典）；encoder / decoder 要和写存档时的日期格式一致
    static func decode<T: Codable>(_ type: T.Type, from stored: Any?, defaults: T,
                                   encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) -> T {
        guard let stored = stored as? [String: Any],
              let defaultData = try? encoder.encode(defaults),
              var good = (try? JSONSerialization.jsonObject(with: defaultData)) as? [String: Any] else { return defaults }
        func attempt(_ object: [String: Any]) -> T? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
        // 一般情况：存档整个都对，一次读完
        var merged = good
        for (key, value) in stored { merged[key] = value }
        if let all = attempt(merged) { return all }
        // 有读不出来的：一项一项试，读不出来的那项用默认值
        for key in stored.keys.sorted() {
            var trial = good
            trial[key] = stored[key]
            if attempt(trial) != nil { good = trial }
        }
        return attempt(good) ?? defaults
    }

    /// 从一个 JSON 文件读
    static func decode<T: Codable>(_ type: T.Type, data: Data?, defaults: T,
                                   encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) -> T {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        return decode(type, from: object, defaults: defaults, encoder: encoder, decoder: decoder)
    }
}
