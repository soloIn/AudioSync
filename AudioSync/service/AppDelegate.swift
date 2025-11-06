//
//  ContentView.swift
//  AudioSync
//
//  Created by solo on 4/29/25.
//

import AppKit
import Cocoa
import Combine
import CoreAudio
import Foundation
import MusicKit
import SwiftData
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var audioManager = AudioFormatManager.shared
    var playbackNotifier: PlaybackNotifier?
    var networkUtil: NetworkUtil?
    @ObservedObject var viewModel: ViewModel = ViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    var modelContainer: ModelContainer?

    //    override init() {
    //        // 使用你的 .xcdatamodeld 文件名（不带扩展）
    //        self.coreDataContainer = NSPersistentContainer(name: "Lyrics")
    //        super.init()
    //        coreDataContainer.loadPersistentStores { description, error in
    //            if let error = error {
    //                fatalError("❌ CoreData 加载失败: \(error)")
    //            } else {
    //                Log.backend.info("✅ CoreData 加载成功: \(description)")
    //            }
    //        }
    //        coreDataContainer.viewContext.automaticallyMergesChangesFromParent =
    //            true
    //        coreDataContainer.viewContext.mergePolicy =
    //            NSMergeByPropertyObjectTrumpMergePolicy
    //    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.accessory)
        //        registerMetalShaders()
        playbackNotifier = PlaybackNotifier()
        Task { @MainActor in
            self.networkUtil = NetworkUtil(viewModel: self.viewModel)
            self.viewModel.$isViewLyricsShow
                .removeDuplicates()
                .sink { [weak self] isShowLyrics in
                    guard let self = self else { return }
                    Log.general.info("显示歌词 -> \(isShowLyrics)")
                    if isShowLyrics {
                        playbackNotifier?.scriptNotification()
                    } else {
                        viewModel.stopLyricUpdater()
                    }
                }
                .store(in: &cancellables)

        }
        Task {
            let _ = await MusicKit.MusicAuthorization.request()
        }

        // 添加播放通知回调逻辑
        playbackNotifier?.onPlay = { [weak self] trackInfo, trigger in
            // 采样率和位深同步
            if trigger == .notification {
                await withCheckedContinuation { continuation in
                    var didResume = false
                    Task {
                        self?.audioManager.onFormatUpdate = {
                            [weak self] sampleRate, bitDepth in
                            self?.audioManager.updateOutputFormat()
                            self?.playbackNotifier?.scriptNotification()
                            if !didResume {
                                didResume = true
                                continuation.resume()
                            }
                        }
                        self?.audioManager.startMonitoring()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            if !didResume {
                                didResume = true
                                continuation.resume()
                            }
                            self?.audioManager.stopMonitoring()
                        }

                    }
                }
            }
            // 歌词
            if trigger == .script {
                Task { [weak self] in
                    guard let self else { return }
                    let lastTrackID = self.viewModel.currentTrack?.trackID
                    self.viewModel.currentTrack = trackInfo
                    guard viewModel.isViewLyricsShow,
                        let scriptTrackInfo = trackInfo
                    else { return }

                    if scriptTrackInfo.state == .playing {
                        viewModel.isCurrentTrackPlaying = true
                    } else {
                        viewModel.isCurrentTrackPlaying = false
                        viewModel.stopLyricUpdater()
                        return
                    }

                    // 若为同一首歌且已有歌词，不处理
                    if lastTrackID == scriptTrackInfo.trackID,
                        !viewModel.currentlyPlayingLyrics.isEmpty
                    {
                        viewModel.startLyricUpdater()
                        return
                    }

                    viewModel.currentlyPlayingLyrics = []
                    viewModel.currentlyPlayingLyricsIndex = nil
                    viewModel.stopLyricUpdater()

                    viewModel.isCurrentTrackPlaying = true
                    viewModel.startLyricUpdater()
                    if loadLyricsFromLocal(trackInfo: scriptTrackInfo) {
                        return
                    }

                    await loadLyricsFromNetwork(
                        trackInfo: scriptTrackInfo
                    )

                }
            }
        }
        playbackNotifier?.scriptNotification()
    }
    private func loadLyricsFromLocal(
        trackInfo: TrackInfo
    ) -> Bool {
        guard let modelContext = modelContainer?.mainContext else {
            return false
        }
        let trackID = trackInfo.trackID
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == trackID }
        )

        if let song = try? modelContext.fetch(descriptor).first {
            let localLyrics = song.getLyrics()
            if !localLyrics.isEmpty {
                Log.general.info("本地歌词")
                viewModel.currentlyPlayingLyrics = localLyrics
                viewModel.currentAlbumColor = trackInfo.color ?? []
                viewModel.startLyricUpdater()
                return true
            }
        }
        return false
    }

    private func loadLyricsFromNetwork(
        trackInfo: TrackInfo
    ) async {
        do {
            let trackName = trackInfo.name
            let artist = trackInfo.artist

            guard !trackName.isEmpty, !artist.isEmpty else {
                Log.general.warning("⚠️ 原始标题或艺术家为空，跳过歌词请求")
                return
            }

            if let lyrics = try await networkUtil?.fetchLyrics(
                trackName: trackName,
                artist: artist,
                trackID: trackInfo.trackID,
                album: trackInfo.album,
                genre: trackInfo.genre
            ), !lyrics.isEmpty {
                let finishLyrics = finishLyric(lyrics)
                Log.general.info("网络歌词")

                viewModel.currentlyPlayingLyrics = finishLyrics
                viewModel.currentAlbumColor = trackInfo.color ?? []
                viewModel.startLyricUpdater()

                // song 保存
                guard let modelContext = modelContainer?.mainContext else {
                    return
                }
                let song = Song(
                    id: trackInfo.trackID,
                    trackName: trackName,
                    lyrics: finishLyrics
                )
                modelContext.insert(song)
                try? modelContext.save()
            }

        } catch {
            Log.general.error("网络歌词获取失败: \(error)")
        }
    }

    func finishLyric(_ rawLyrics: [LyricLine]) -> [LyricLine] {
        guard let last = rawLyrics.last else { return rawLyrics }
        let virtualEndLine = LyricLine(
            startTime: last.startTimeMS + 5000,
            words: ""
        )
        return rawLyrics + [virtualEndLine]
    }

    @objc func delCurrentSongObject() {
        guard let trackID = playbackNotifier?.fetchCurrentTrack()?.trackID
        else {
            return
        }
        // 删除song
        let modelContext = modelContainer?.mainContext
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == trackID }
        )
        if let song = try? modelContext?.fetch(descriptor).first {
            modelContext?.delete(song)
            try? modelContext?.save()
        }
        viewModel.currentTrack = nil
        playbackNotifier?.scriptNotification()
    }

    @objc func manualNamefetch() {
        Task {
            await manulNameAsyncFetch()
        }
    }

    @objc func similarSingers() {
        Task {
            do {
                Log.general.info("start fetch similar artists")
                let artist = try await networkUtil?.fetchSimilarArtists(
                    name: "周杰倫"
                )

                let artistID = try await IDFetcher.fetchArtistID(by: "周杰倫")
                // 步骤 2: 使用 ID 跳转到艺术家主页 (使用 Universal Link，如 MusicNavigator 中所推荐)
                let success = try MusicNavigator.openArtistPage(by: artistID)

            }
        }
    }
    private func manulNameAsyncFetch() async {
        do {
            guard let manualName = NSPasteboard.general.string(forType: .string)
            else {
                Log.general.warning("⚠️ 粘贴板中没有字符串内容")
                return
            }
            Log.general.info("来自粘贴板的歌曲: \(manualName)")
            guard let currentTrack = playbackNotifier?.fetchCurrentTrack()
            else {
                return
            }

            let netEaseLyrics = try await networkUtil?.fetchLyrics(
                trackName: manualName,
                artist: currentTrack.artist,
                trackID: currentTrack.trackID,
                album: currentTrack.album,
                genre: currentTrack.genre
            )

            if !netEaseLyrics!.isEmpty {
                guard let modelContext = modelContainer?.mainContext else {
                    return
                }
                let finishLyrics = finishLyric(netEaseLyrics!)
                let trackID = currentTrack.trackID
                let descriptor = FetchDescriptor<Song>(
                    predicate: #Predicate { $0.id == trackID }
                )
                if let song = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(song)
                }
                let songNew = Song(
                    id: currentTrack.trackID,
                    trackName: currentTrack.name,
                    lyrics: finishLyrics
                )
                modelContext.insert(songNew)

                try? modelContext.save()

                playbackNotifier?.scriptNotification()
            }

        } catch {
            Log.general.error("粘贴板获取歌词失败：\(error)")
        }
    }

}

// 修改后的AudioFormatManager类

// 保持Core Audio相关扩展和工具方法不变
extension OSStatus {
    func toHexString() -> String {
        return String(format: "0x%08X", self)
    }
}
