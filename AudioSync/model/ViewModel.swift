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
    @Published var isViewLyricsShow: Bool = false
    @Published var isLyricsPrepared: Bool = false
    @Published var currentAlbumColor: [Color] = []
    @Published var allCandidates: [CandidateSong] = []
    @Published var needNanualSelection: Bool = false
    @Published var currentTrack: TrackInfo?
    @Published var scrollProxy: ScrollViewProxy?
    @Published var isCurrentTrackPlaying: Bool = false
    var onCandidateSelected: ((CandidateSong) -> Void)?  // ❗️等待用的回调

    var appleMusicScript: MusicApplication? = SBApplication(
        bundleIdentifier: "com.apple.Music")
    private var currentLyricsUpdaterTask: Task<Void, Error>?

    private var cancellables = Set<AnyCancellable>()

    private func lyricUpdater() async throws {
        repeat {
            #if DEBUG
                print(
                    "lyric index: \(String(describing: currentlyPlayingLyricsIndex))"
                )
            #endif
            guard let playerPosition = appleMusicScript?.playerPosition else {
                #if DEBUG
                    print("no player position hence stopped")
                #endif
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
                withAnimation(.linear(duration: 0.2)) {
                    currentlyPlayingLyricsIndex = lastIndex - 1
                }
            }

            let nextTimestamp = currentlyPlayingLyrics[lastIndex].startTimeMS
            let diff = nextTimestamp - currentTime
            #if DEBUG
                print("current time: \(currentTime)")
                print("next time: \(nextTimestamp)")
                print("the difference is \(diff)")
            #endif
            try await Task.sleep(nanoseconds: UInt64(1_000_000 * diff))
            #if DEBUG
                print("last index: \(lastIndex)")
            #endif
            if currentlyPlayingLyrics.count > lastIndex {
                withAnimation(.linear(duration: 0.2)) {
                    currentlyPlayingLyricsIndex = lastIndex
                }
            } else {
                currentlyPlayingLyricsIndex = nil
            }
            #if DEBUG
                print(
                    "current lyrics index is now \(currentlyPlayingLyricsIndex?.description )"
                )
            #endif
        } while !Task.isCancelled
    }

    func startLyricUpdater() {
        #if DEBUG
            print("start update task")
            print(
                "isViewLyricsShow: \(self.isViewLyricsShow), lyrics.isEmpty: \(currentlyPlayingLyrics.isEmpty)"
            )
        #endif
        currentLyricsUpdaterTask?.cancel()
        currentLyricsUpdaterTask = Task {
            do {
                try await lyricUpdater()
            } catch {
                #if DEBUG
                    print("lyrics were canceled \(error)")
                #endif
            }
        }
    }

    func stopLyricUpdater() {
        #if DEBUG
            print("stop update task")
        #endif
//        currentlyPlayingLyricsIndex = nil
//        isLyricsPrepared = false
        currentLyricsUpdaterTask?.cancel()
    }

    func upcomingIndex(_ currentTime: Double) -> Int? {
        if let currentlyPlayingLyricsIndex {
            let newIndex = currentlyPlayingLyricsIndex + 1
            if newIndex >= currentlyPlayingLyrics.count {
                #if DEBUG
                    print("REACHED LAST LYRIC!!!!!!!!")
                #endif
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
                #if DEBUG
                    print("just the next lyric")
                #endif
                return newIndex
            }
        }
        // linear search through the array to find the first lyric that's right after the current time
        // done on first lyric update for the song, as well as post-scrubbing
        return currentlyPlayingLyrics.firstIndex(where: {
            $0.startTimeMS > currentTime
        })
    }

}
extension NSImage {
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
            to: UInt8.self, capacity: Int(size.width * size.height * 4))

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
            repeating: [], count: k)

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
                red: sum.0 / count, green: sum.1 / count, blue: sum.2 / count)
        }
    }
    
}
struct CandidateSong {
    let id: String
    let name: String
    let artist: String
    let album: String
    var albumId: String
    var albumCover: String
    let source: LyricsFormat
}
