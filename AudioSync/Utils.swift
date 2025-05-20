//
//  Utils.swift
//  AudioSync
//
//  Created by solo on 5/11/25.
//

import Foundation

/// 将任意 `Encodable` 对象转为 JSON 并打印（格式化输出）
func printAsJSON<T: Encodable>(_ object: T, label: String = "JSON") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(object)
        if let jsonString = String(data: data, encoding: .utf8) {
            print("\(label):\n\(jsonString)")
        } else {
            print("❌ 无法将 JSON 数据转换为字符串")
        }
    } catch {
        print("❌ JSON 编码失败: \(error)")
    }
}
