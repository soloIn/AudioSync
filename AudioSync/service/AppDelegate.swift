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
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    var statusBarItem: NSStatusItem!
    var audioManager = AudioFormatManager.shared
    var playbackNotifier: PlaybackNotifier?
    var networkUtil: NetworkUtil?
    @ObservedObject var viewModel: ViewModel = ViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    var modelContainer: ModelContainer?
    private var networkQueue = NetWorkQueue()

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            playbackNotifier = PlaybackNotifier(viewModel: self.viewModel)
            networkUtil = NetworkUtil(viewModel: self.viewModel)

            self.playbackNotifier?.onPlay = {
                [weak self] trackInfo, trigger in
                Log.backend.debug("playbackNotifier.onPlay \(trigger)")
                guard let self = self else {
                    return
                }
                // 采样率和位深同步
                if trigger == .formatSwitch {
                    await withCheckedContinuation { continuation in
                        var didResume = false
                        Task {
                            self.audioManager.onFormatUpdate = {
                                sampleRate,
                                bitDepth in
                                self.audioManager.updateOutputFormat()
                                //notifier.scriptNotification()
                                if !didResume {
                                    didResume = true
                                    continuation.resume()
                                }
                            }
                            self.audioManager.startMonitoring()
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 5.0
                            ) {
                                if !didResume {
                                    didResume = true
                                    continuation.resume()
                                }
                                self.audioManager.stopMonitoring()
                            }

                        }
                    }
                }
                // 歌词
                if trigger == .lyrics {
                    Task { [weak self] in
                        guard let self else { return }

                        viewModel.isLyricsPlaying = false
                        if viewModel.isCurrentTrackPlaying
                            && viewModel.isViewLyricsShow
                        {
                            if loadLyricsFromLocal() {
                                return
                            }

                            await loadLyricsFromNetwork()
                        }

                    }
                }
            }

            viewModel.$refreshSimilarArtist
                .removeDuplicates()
                .sink { [weak self] refreshSimilarArtist in
                    guard let self = self else { return }
                    if refreshSimilarArtist {
                        networkUtil?.fetchSimilarArtistsAndCovers()
                        viewModel.refreshSimilarArtist = false
                    }

                }
                .store(in: &cancellables)

            viewModel.$isViewLyricsShow
                .removeDuplicates()
                .sink { [weak self] isShowLyrics in
                    guard let self = self else { return }
                    Log.general.debug("显示歌词 -> \(isShowLyrics)")
                    if isShowLyrics {
                        Task {
                            if let onPlay = self.playbackNotifier?.onPlay {
                                await onPlay(nil, .lyrics)
                            }
                        }
                    } else {
                        viewModel.stopLyricUpdater()
                    }
                }
                .store(in: &cancellables)

            viewModel.$isLyricsPlaying
                .removeDuplicates()
                .sink { [weak self] isLyricsPlaying in
                    guard let self = self else { return }
                    Log.general.debug("isLyricsPlaying -> \(isLyricsPlaying)")
                    if isLyricsPlaying {
                        viewModel.startLyricUpdater()
                    } else {
                        viewModel.stopLyricUpdater()
                        viewModel.currentlyPlayingLyricsIndex = nil
                    }
                }
                .store(in: &cancellables)

        }
        Task {
            let _ = await MusicKit.MusicAuthorization.request()

            do {
                try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                Log.backend.error("用户拒绝了通知权限")
            }
            // 出发启动时歌词显示
            if let onPlay = self.playbackNotifier?.onPlay {
                await onPlay(nil, .lyrics)
            }

        }

    }
    private func loadLyricsFromLocal() -> Bool {
        guard let modelContext = modelContainer?.mainContext else {
            return false
        }
        guard let trackID = viewModel.currentTrack?.trackID else {
            return false
        }
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == trackID }
        )

        if let song = try? modelContext.fetch(descriptor).first {
            let localLyrics = song.getLyrics()
            if !localLyrics.isEmpty {
                Log.general.debug("本地歌词")
                viewModel.currentlyPlayingLyrics = localLyrics
                viewModel.isLyricsPlaying = true
                return true
            }
        }
        return false
    }

    private func loadLyricsFromNetwork() async {
        guard let trackInfo = viewModel.currentTrack else {
            return
        }
        let trackName = trackInfo.name
        let artist = trackInfo.artist
        let queueKey = "\(trackName)-\(artist)"

        do {
            if await networkQueue.contains(queueKey) {
                return
            }
            await networkQueue.append(queueKey)
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
                Log.general.debug("网络歌词")

                viewModel.currentlyPlayingLyrics = finishLyrics
                viewModel.isLyricsPlaying = true

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
                await networkQueue.remove(queueKey)
            }

        } catch {
            Log.general.error("网络歌词获取失败: \(error)")
            Log.notice.notice(
                "网络歌词获取失败",
                error.localizedDescription
            )
            await networkQueue.remove(queueKey)
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
        guard let trackID = viewModel.currentTrack?.trackID
        else {
            return
        }
        viewModel.isLyricsPlaying = false
        // 删除song
        let modelContext = modelContainer?.mainContext
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == trackID }
        )
        if let song = try? modelContext?.fetch(descriptor).first {
            modelContext?.delete(song)
            try? modelContext?.save()
        }

        Task {
            if let onPlay = playbackNotifier?.onPlay {
                await onPlay(nil, .lyrics)
            }
        }
    }

    @objc func manualNamefetch() {
        Task {
            await manulNameAsyncFetch()
        }
    }

    private func manulNameAsyncFetch() async {
        do {
            guard
                let manualName = NSPasteboard.general.string(forType: .string),
                !manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            else {
                Log.general.warning("⚠️ 粘贴板中没有字符串内容")
                Log.notice.notice(
                    "空歌曲名",
                    "⚠️ 粘贴板中没有字符串内容"
                )
                return
            }
            Log.general.debug("来自粘贴板的歌曲: \(manualName)")
            guard let currentTrack = viewModel.currentTrack else {
                return
            }
            viewModel.isLyricsPlaying = false
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

                Task {
                    if let onPlay = playbackNotifier?.onPlay {
                        await onPlay(nil, .lyrics)
                    }
                }
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
// 3. ✅ 实现代理方法，允许前台通知
extension AppDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 告诉系统：即使应用在前台，也要显示 Banner 和声音
        // 注意：macOS 11.0+ 使用 .banner，旧版本可能使用 .alert
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
