import AppKit
import Foundation

enum JSON {

    // MARK: - 对象/数组转 JSON 字符串
    static func stringify<T: Encodable>(_ value: T, pretty: Bool = false)
        -> String
    {
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

    static func stringify(_ dict: [AnyHashable: Any], pretty: Bool = false)
        -> String
    {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict,
                options: pretty ? [.prettyPrinted] : []
            )
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Log.general.error("字典 JSON 编码失败: \(error)")
            return "{}"
        }
    }

    static func stringify(_ array: [Any], pretty: Bool = false) -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: array,
                options: pretty ? [.prettyPrinted] : []
            )
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            Log.general.error("数组 JSON 编码失败: \(error)")
            return "[]"
        }
    }

    // MARK: - JSON 字符串转对象/数组
    static func parse<T: Decodable>(_ jsonString: String, to type: T.Type) -> T?
    {
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
func compressImageData(_ data: Data, maxWidth: CGFloat, quality: CGFloat)
    async throws -> Data
{
    guard let image = NSImage(data: data) else {
        throw NSError(domain: "InvalidImage", code: -1)
    }

    // 取出 CGImage
    guard
        let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        )
    else {
        throw NSError(domain: "InvalidCGImage", code: -1)
    }

    let originalWidth = CGFloat(cgImage.width)
    let originalHeight = CGFloat(cgImage.height)

    // 如果图片本来就够小，直接存
    if originalWidth <= maxWidth {
        return data
    }

    // 计算缩放比
    let scale = maxWidth / originalWidth
    let newWidth = maxWidth
    let newHeight = originalHeight * scale

    // 新图像 context
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard
        let context = CGContext(
            data: nil,
            width: Int(newWidth),
            height: Int(newHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw NSError(domain: "CreateContextFailed", code: -1)
    }

    context.interpolationQuality = .high
    context.draw(
        cgImage,
        in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
    )

    guard let resizedCGImage = context.makeImage() else {
        throw NSError(domain: "ResizeFailed", code: -1)
    }

    // 导出 JPEG 数据
    let rep = NSBitmapImageRep(cgImage: resizedCGImage)
    guard
        let jpegData = rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    else {
        throw NSError(domain: "JPEGEncodeFailed", code: -1)
    }

    return jpegData
}
// MARK: - Encodable 扩展
extension Encodable {
    func toJSONString(pretty: Bool = false) -> String {
        JSON.stringify(self, pretty: pretty)
    }
}
