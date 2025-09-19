import Foundation

enum JSON {
    
    // MARK: - 对象/数组转 JSON 字符串
    static func stringify<T: Encodable>(_ value: T, pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Log.general.error("JSON 编码失败: \(error)")
            return "{}"
        }
    }
    
    static func stringify(_ dict: [AnyHashable: Any], pretty: Bool = false) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: pretty ? [.prettyPrinted] : [])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Log.general.error("字典 JSON 编码失败: \(error)")
            return "{}"
        }
    }
    
    static func stringify(_ array: [Any], pretty: Bool = false) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: array, options: pretty ? [.prettyPrinted] : [])
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            Log.general.error("数组 JSON 编码失败: \(error)")
            return "[]"
        }
    }
    
    // MARK: - JSON 字符串转对象/数组
    static func parse<T: Decodable>(_ jsonString: String, to type: T.Type) -> T? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.general.error("JSON 解码失败: \(error)")
            return nil
        }
    }
    
    static func parseDictionary(_ jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            return obj as? [String: Any]
        } catch {
            Log.general.error("JSON 字符串转字典失败: \(error)")
            return nil
        }
    }
    
    static func parseArray(_ jsonString: String) -> [Any]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            return obj as? [Any]
        } catch {
            Log.general.error("JSON 字符串转数组失败: \(error)")
            return nil
        }
    }
}

// MARK: - Encodable 扩展
extension Encodable {
    func toJSONString(pretty: Bool = false) -> String {
        JSON.stringify(self, pretty: pretty)
    }
}
