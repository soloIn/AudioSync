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
    var openWindow: OpenWindowAction?

    // 窗口引用
    var karaoKeWindow: NSWindow?
    var selectorWindow: NSWindow?
    var similarArtistWindow: NSWindow?

    var statusBarItem: NSStatusItem!
    var audioManager = AudioFormatManager.shared
    var playbackNotifier: PlaybackNotifier?
    var networkUtil: NetworkService?
    @ObservedObject var viewModel: ViewModel = ViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    var modelContainer: ModelContainer?
    private var networkQueue = NetWorkQueue()

    func applicationDidFinishLaunching(_ notification: Notification) {
        //只有菜单栏图标，无 Dock 图标
        NSApp.setActivationPolicy(.regular)
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            // 1. 启动播放监听
            playbackNotifier = PlaybackNotifier(viewModel: self.viewModel)
            // 2. 初始化网络服务
            networkUtil = NetworkService(viewModel: self.viewModel)
            // 3. 配置音乐通知回调
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
            // 4. 绑定属性监听
            setupBindings()

        }
        // 权限及其他初始化
        Task {

            let _ = await MusicKit.MusicAuthorization.request()

            do {
                try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                Log.backend.error("用户拒绝了通知权限")
            }

            // 刚启动需要获取歌曲信息
            await self.playbackNotifier?.obtainPlayback()
            // 触发启动时歌词显示
            if let onPlay = self.playbackNotifier?.onPlay {
                await onPlay(nil, .lyrics)
            }

        }

    }
    private func setupBindings() {
        // 刷新相似歌手
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
        // 是否显示歌词
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
        // 歌词是否在播放
        viewModel.$isLyricsPlaying
            .removeDuplicates()
            .sink { [weak self] isLyricsPlaying in
                guard let self = self else { return }
                Log.general.debug("播放歌词 -> \(isLyricsPlaying)")
                Task {
                    await MainActor.run {
                        self.updateKaraokeWindow()
                    }
                }
                if isLyricsPlaying {
                    viewModel.startLyricUpdater()
                } else {
                    viewModel.stopLyricUpdater()
                    viewModel.currentlyPlayingLyricsIndex = nil
                }
            }
            .store(in: &cancellables)
        // 歌词选择窗口切换
        viewModel.$needNanualSelection
            .removeDuplicates()
            .sink { [weak self] needNanualSelection in
                guard let self = self else { return }
                Task {
                    await MainActor.run {
                        self.toggleLyricsSelector(show: needNanualSelection)
                    }
                }

            }
            .store(in: &cancellables)
        viewModel.$isFullScreenVisible
            .removeDuplicates()
            .sink { [weak self] isFullScreenVisible in
                guard let self else { return }
                Log.backend.info(
                    "viewModel.$isFullScreenVisible change \(isFullScreenVisible)"
                )
                viewModel.isViewLyricsShow =
                    viewModel.isKaraokeVisible || isFullScreenVisible
                if isFullScreenVisible {
                    guard let selfOpenWindow = openWindow else { return }
                    Task {
                        await MainActor.run {
                            // 1. 先激活应用 (ignoringOtherApps: true 是关键)
                            NSApplication.shared.activate(
                                ignoringOtherApps: true
                            )

                            // 2. 再打开窗口
                            selfOpenWindow(id: "fullScreen")
                        }
                    }
                }
                // 全屏时去掉卡拉OK显示
                Task {
                    await MainActor.run {
                        self.updateKaraokeWindow()
                    }
                }
            }
            .store(in: &cancellables)
        viewModel.$isKaraokeVisible
            .removeDuplicates()
            .sink { [weak self] isKaraokeVisible in
                guard let self else { return }
                Log.backend.info(
                    "viewModel.$isKaraokeVisible change \(isKaraokeVisible)"
                )
                viewModel.isViewLyricsShow =
                    isKaraokeVisible || viewModel.isFullScreenVisible
                Task {
                    await MainActor.run {
                        self.updateKaraokeWindow()
                    }
                }
            }
            .store(in: &cancellables)

    }
    func showSimilarArtistWindow() {
        viewModel.refreshSimilarArtist = true
        if similarArtistWindow == nil {
            let contentView = NSHostingView(
                rootView: SimilarArtistView()
                    .environmentObject(viewModel)
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 450),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            // window.title = "相似歌手"
            window.center()
            window.contentView = contentView
            window.level = .floating  // 🔹关键：浮动在其他应用前
            //window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)  // 保证出现在最前

            similarArtistWindow = window
        } else {
            similarArtistWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    // 创建或更新卡拉OK窗口
    func updateKaraokeWindow() {
        // 显示条件：开启开关 && 非全屏 && 需要显示歌词 && 有歌词正在播放
        if viewModel.isKaraokeVisible && !viewModel.isFullScreenVisible
            && viewModel.isViewLyricsShow
        {
            if karaoKeWindow == nil {
                let contentView = NSHostingView(
                    rootView: KaraokeView().environmentObject(viewModel)
                )
                karaoKeWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 100, width: 800, height: 100),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )

                karaoKeWindow?.contentView = contentView
                karaoKeWindow?.isOpaque = false
                karaoKeWindow?.backgroundColor = .clear
                karaoKeWindow?.level = .floating

                if let screenFrame = NSScreen.main?.visibleFrame {
                    let windowHeight: CGFloat = 100
                    let windowY = screenFrame.minY
                    let windowX = (screenFrame.width - 800) / 2
                    karaoKeWindow?.setFrame(
                        NSRect(
                            x: windowX,
                            y: windowY,
                            width: 800,
                            height: windowHeight
                        ),
                        display: false
                    )
                }

                karaoKeWindow?.isMovableByWindowBackground = true
            }
            karaoKeWindow?.orderFrontRegardless()
        } else {
            karaoKeWindow?.orderOut(nil)
        }
    }
    // 显示手动选择歌词窗口
    func toggleLyricsSelector(show: Bool) {
        if show {
            if selectorWindow == nil {
                let contentView = NSHostingView(
                    rootView: LyricsSelectorView().environmentObject(
                        viewModel
                    )
                )
                selectorWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 450, width: 450, height: 450),
                    styleMask: [.borderless],  // 无边框
                    backing: .buffered,
                    defer: false
                )
                selectorWindow?.contentView = contentView
                selectorWindow?.isOpaque = false
                selectorWindow?.backgroundColor = .clear
                selectorWindow?.level = .floating  // 后续会修改为前置显示
                // 精确让窗口贴近屏幕底部
                if let screenFrame = NSScreen.main?.visibleFrame {
                    let windowHeight: CGFloat = 450
                    let windowY = screenFrame.minY + 25
                    let windowX = (screenFrame.width - 450) / 2
                    selectorWindow?.setFrame(
                        NSRect(
                            x: windowX,
                            y: windowY,
                            width: 450,
                            height: windowHeight
                        ),
                        display: false
                    )
                }
                selectorWindow?.isMovableByWindowBackground = true
            }
            // 确保显示窗口
            selectorWindow?.makeKeyAndOrderFront(nil)

            // 确保激活应用并将窗口置顶
            NSApp.activate(ignoringOtherApps: true)
        } else {
            selectorWindow?.orderOut(nil)
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
            viewModel.currentTrack?.albumCover = song.cover
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
                    lyrics: finishLyrics,
                    cover: (viewModel.currentTrack?.albumCover)!

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
    @objc func delAllSongObject() {

        guard let modelContext = modelContainer?.mainContext else { return }
        let descriptor = FetchDescriptor<Song>()
        if let songs = try? modelContext.fetch(descriptor) {
            for song in songs {
                modelContext.delete(song)
            }
            try? modelContext.save()
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
                    lyrics: finishLyrics,
                    cover: (viewModel.currentTrack?.albumCover)!
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
