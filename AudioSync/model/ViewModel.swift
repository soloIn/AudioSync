import AppKit
import Combine
//
//  ViewModel.swift
//  AudioSync
//
//  Created by solo on 5/12/25.
//
import Foundation
import ScriptingBridge
import SwiftUI

@MainActor
class ViewModel: ObservableObject {

    static let shared: ViewModel = ViewModel()
    @Published var currentlyPlayingLyrics: [LyricLine] = []
    @Published var currentlyPlayingLyricsIndex: Int?
    @Published var karaokeFont: NSFont = NSFont.boldSystemFont(ofSize: 30)
    @Published var translationExists: Bool = true
    @Published var karaokeShowMultilingual: Bool = true
    @Published var isPlaying: Bool = false
    @Published var currentAlbumColor: NSColor? = nil
    @Published var allCandidates: [CandidateSong] = []
    @Published var needNanualSelection: Bool = false
    @Published var currentTrack: TrackInfo?
    var onCandidateSelected: ((CandidateSong) -> Void)?  // ❗️等待用的回调

    var appleMusicScript: MusicApplication? = SBApplication(
        bundleIdentifier: "com.apple.Music")
    private var currentLyricsUpdaterTask: Task<Void, Error>?

    private var cancellables = Set<AnyCancellable>()

    init() {
        $isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self = self else { return }
                print("监听 isPlaying 变化: \(playing)")
                if playing {
                    self.startLyricUpdater()
                } else {
                    self.stopLyricUpdater()
                }
            }
            .store(in: &cancellables)
    }

    private func lyricUpdater() async throws {
        repeat {
            print("lyric index: \(String(describing: currentlyPlayingLyricsIndex))")
            guard let playerPosition = appleMusicScript?.playerPosition else {
                print("no player position hence stopped")
                // pauses the timer bc there's no player position
                stopLyricUpdater()
                return
            }
            // add a 700 (milisecond?) delay to offset the delta between spotify lyrics and apple music songs (or maybe the way apple music delivers playback position)
            // No need for Spotify Connect delay or fullscreen, this is APPLE MUSIC
            let currentTime = playerPosition * 1000 + 400
            guard let lastIndex: Int = upcomingIndex(currentTime) else {
                stopLyricUpdater()
                return
            }
            // If there is no current index (perhaps lyric updater started late and we're mid-way of the first lyric, or the user scrubbed and our index is expired)
            // Then we set the current index to the one before our anticipated index
            if currentlyPlayingLyricsIndex == nil && lastIndex > 0 {
                withAnimation {
                    currentlyPlayingLyricsIndex = lastIndex - 1
                }
            }
            let nextTimestamp = currentlyPlayingLyrics[lastIndex].startTimeMS
            let diff = nextTimestamp - currentTime
            print("current time: \(currentTime)")
            print("next time: \(nextTimestamp)")
            print("the difference is \(diff)")
            try await Task.sleep(nanoseconds: UInt64(1_000_000 * diff))
            print("last index: \(lastIndex)")
            if currentlyPlayingLyrics.count > lastIndex {
                withAnimation {
                    currentlyPlayingLyricsIndex = lastIndex
                }
            } else {
                currentlyPlayingLyricsIndex = nil
            }
            print(
                "current lyrics index is now \(currentlyPlayingLyricsIndex?.description ?? "nil")"
            )
        } while !Task.isCancelled
    }

    func startLyricUpdater() {
        print("start update task")
        print(
            "isPlaying: \(self.isPlaying), lyrics.isEmpty: \(currentlyPlayingLyrics.isEmpty)"
        )
        currentLyricsUpdaterTask?.cancel()
        currentLyricsUpdaterTask = Task {
            do {
                try await lyricUpdater()
            } catch {
                print("lyrics were canceled \(error)")
            }
        }
    }

    func stopLyricUpdater() {
        print("stop update task")
        isPlaying = false
        currentlyPlayingLyricsIndex = nil
        currentLyricsUpdaterTask?.cancel()
    }

    func upcomingIndex(_ currentTime: Double) -> Int? {
        if let currentlyPlayingLyricsIndex {
            let newIndex = currentlyPlayingLyricsIndex + 1
            if newIndex >= currentlyPlayingLyrics.count {
                print("REACHED LAST LYRIC!!!!!!!!")
                // if current time is before our current index's start time, the user has scrubbed and rewinded
                // reset into linear search mode
                if currentTime
                    < currentlyPlayingLyrics[currentlyPlayingLyricsIndex]
                    .startTimeMS
                {
                    return currentlyPlayingLyrics.firstIndex(where: {
                        $0.startTimeMS > currentTime
                    })
                }
                return nil
            } else if currentTime
                > currentlyPlayingLyrics[currentlyPlayingLyricsIndex]
                .startTimeMS,
                currentTime < currentlyPlayingLyrics[newIndex].startTimeMS
            {
                print("just the next lyric")
                return newIndex
            }
        }
        // linear search through the array to find the first lyric that's right after the current time
        // done on first lyric update for the song, as well as post-scrubbing
        return currentlyPlayingLyrics.firstIndex(where: {
            $0.startTimeMS > currentTime
        })
    }
    
    var derivedColor: Color? {
        guard let color = currentAlbumColor else { return nil }
        
        // 将 NSColor 转换为 HSL
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var lightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &lightness, alpha: nil)
        
        // 降低饱和度至 0.2-0.4 区间
        let adjustedSaturation = saturation * 0.35
        
        // 保持亮度在安全区间
        let safeLightness = max(0.3, min(lightness, 0.7))
        
        return Color(
            hue: hue,
            saturation: adjustedSaturation,
            brightness: safeLightness,
            opacity: 0.6
        )
    }
}
extension NSImage {
    func toSwiftUIImage() -> Image{
        Image(nsImage: self)
    }
    func findDominantColor() -> NSColor? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        // 缩小图像大小以减少计算量（比如 40x40）
        let size = CGSize(width: 256, height: 256)
        guard let resizedContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        resizedContext.interpolationQuality = .high
        resizedContext.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let data = resizedContext.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height * 4))

        var colorCount: [UInt32: Int] = [:]

        for x in 0 ..< Int(size.width) {
            for y in 0 ..< Int(size.height) {
                let offset = 4 * (y * Int(size.width) + x)
                let r = ptr[offset]
                let g = ptr[offset + 1]
                let b = ptr[offset + 2]
                let a = ptr[offset + 3]

                // 忽略透明像素
                if a < 128 { continue }

                // 压缩精度（减少颜色数目，便于聚合）
                let quantR = r >> 3
                let quantG = g >> 3
                let quantB = b >> 3

                let rgbKey = UInt32(quantR) << 16 | UInt32(quantG) << 8 | UInt32(quantB)
                colorCount[rgbKey, default: 0] += 1
            }
        }

        if let (key, _) = colorCount.max(by: { $0.value < $1.value }) {
            let r = CGFloat((key >> 16) & 0xFF) / 31.0
            let g = CGFloat((key >> 8) & 0xFF) / 31.0
            let b = CGFloat(key & 0xFF) / 31.0
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        return nil
    }
}

// 颜色处理扩展
extension NSColor {
    var balancedColor: Color {
        let ciColor = CIColor(color: self)!
        
        // 计算亮度 (ITU-R BT.709 标准)
        let luminance = 0.2126 * ciColor.red + 0.7152 * ciColor.green + 0.0722 * ciColor.blue
        
        // 动态调整参数
        let targetLuminance: CGFloat = 0.2
        let adjustment = (targetLuminance - luminance) * 0.5
        
        return Color(
            red: Double(ciColor.red + adjustment),
            green: Double(ciColor.green + adjustment),
            blue: Double(ciColor.blue + adjustment),
            opacity: 0.8
        )
    }
}
struct CandidateSong {
    let id: String
    let name: String
    let artist: String
    let album: String
    let source: String
}


