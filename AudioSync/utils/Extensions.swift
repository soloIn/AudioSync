//
//  Extensions.swift
//  SpotlightLyrics
//
//  Created by Scott Rong on 2017/7/28.
//  Copyright © 2017 Scott Rong. All rights reserved.
//

import AppKit
import Foundation
import SwiftUI

extension CharacterSet {
    public static let quotes = CharacterSet(charactersIn: "\"'")
}

extension String {
    public func emptyToNil() -> String? {
        return self == "" ? nil : self
    }

    public func blankToNil() -> String? {
        return self.trimmingCharacters(in: .whitespacesAndNewlines) == ""
            ? nil : self
    }
    var normalized: String {
        self
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "-")
            .replacingOccurrences(of: "：", with: "-")
            .replacingOccurrences(of: "（", with: "-")
            .replacingOccurrences(of: "）", with: "-")
            .lowercased()
    }
    var toTraditional: String {
        self.applyingTransform(
            StringTransform("Simplified-Traditional"),
            reverse: false
        ) ?? self
    }

    var toSimplified: String {
        self.applyingTransform(
            StringTransform("Traditional-Simplified"),
            reverse: false
        ) ?? self
    }
    var collapseSpaces: String {
        self.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )
    }
}
extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()

        let sourceRect = NSRect(origin: .zero, size: self.size)
        let destRect = NSRect(origin: .zero, size: newSize)

        self.draw(
            in: destRect,
            from: sourceRect,
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }
    func toSwiftUIImage() -> Image {
        Image(nsImage: self)
    }
    func findDominantColors(maxK: Int = 3) -> [Color]? {
        guard let tiffData = self.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            return nil
        }

        let size = CGSize(width: 128, height: 128)
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: Int(size.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(
            to: UInt8.self,
            capacity: Int(size.width * size.height * 4)
        )

        var points: [(CGFloat, CGFloat, CGFloat)] = []

        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                let offset = 4 * (y * Int(size.width) + x)
                let r = CGFloat(ptr[offset]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset + 2]) / 255.0
                let a = CGFloat(ptr[offset + 3]) / 255.0
                if a > 0.5 {
                    points.append((r, g, b))
                }
            }
        }

        // 自动确定聚类数 k（不超过 maxK）
        let k = min(maxK, max(1, Int(sqrt(Double(points.count)) / 2)))

        guard points.count >= k else { return nil }

        // 简易 k-means 聚类
        var centroids = points.shuffled().prefix(k)
        var clusters: [[(CGFloat, CGFloat, CGFloat)]] = Array(
            repeating: [],
            count: k
        )

        for _ in 0..<10 {
            clusters = Array(repeating: [], count: k)
            for point in points {
                let index = centroids.enumerated().min(by: {
                    pow($0.1.0 - point.0, 2) + pow($0.1.1 - point.1, 2)
                        + pow($0.1.2 - point.2, 2)
                        < pow($1.1.0 - point.0, 2) + pow($1.1.1 - point.1, 2)
                        + pow($1.1.2 - point.2, 2)
                })!.offset
                clusters[index].append(point)
            }

            for i in 0..<k {
                if clusters[i].isEmpty { continue }
                let sum = clusters[i].reduce((0.0, 0.0, 0.0)) {
                    ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2)
                }
                let count = CGFloat(clusters[i].count)
                centroids[i] = (sum.0 / count, sum.1 / count, sum.2 / count)
            }
        }

        // 排序并输出颜色
        let sorted = clusters.enumerated().sorted {
            $0.element.count > $1.element.count
        }
        return sorted.map {
            let sum = $0.element.reduce((0.0, 0.0, 0.0)) {
                ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2)
            }
            let count = CGFloat($0.element.count)
            return Color(
                red: sum.0 / count,
                green: sum.1 / count,
                blue: sum.2 / count
            )
        }
    }
}


extension View {
    func systemTooltip(_ text: String) -> some View {
        background(
            HoverTrackingView(
                onHoverIn: { nsView in
                    TooltipPopoverController.shared.show(
                        relativeTo: nsView,
                        contentKey: text
                    )
                },
                onHoverOut: {
                    TooltipPopoverController.shared.close()
                }
            )
        )
    }
}
