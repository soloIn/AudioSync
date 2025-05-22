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
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var audioManager = AudioFormatManager()
    var updateTimer: Timer?
    var playbackNotifier: PlaybackNotifier?
    var networkUtil: NetworkUtil?
    var viewModel: ViewModel?
    var karaoKeWindow: NSWindow!
    var selectorWindow: NSWindow!
    private var cancellables = Set<AnyCancellable>()
    let coreDataContainer: NSPersistentContainer

    @AppStorage("isWindowVisible") var isShowLyric: Bool = false

    override init() {
        // 使用你的 .xcdatamodeld 文件名（不带扩展）
        self.coreDataContainer = NSPersistentContainer(name: "Lyrics")
        super.init()
        coreDataContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("❌ CoreData 加载失败: \(error)")
            } else {
                print("✅ CoreData 加载成功: \(description)")
            }
        }
        coreDataContainer.viewContext.automaticallyMergesChangesFromParent =
            true
        coreDataContainer.viewContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        playbackNotifier = PlaybackNotifier()
        Task { @MainActor in
            self.viewModel = ViewModel.shared
            self.networkUtil = NetworkUtil(viewModel: self.viewModel!)
            self.viewModel?.$isPlaying
                .removeDuplicates()
                .sink { playing in
                    if playing {
                        self.activateCaraokeView()
                    } else {
                        self.deactiveCaraokeView()
                    }
                }
                .store(in: &cancellables)
            self.viewModel?.$needNanualSelection
                .removeDuplicates()
                .sink { manualSelection in
                    if manualSelection {
                        self.activateLyricsSelectorView()
                    } else {
                        self.deactivateLyricsSelectorView()
                    }
                }
                .store(in: &cancellables)

        }
        Task {
            let _ = await MusicKit.MusicAuthorization.request()
        }

        // 添加播放通知回调逻辑
        playbackNotifier?.onPlay = { [weak self] trackInfo in
            self?.viewModel?.currentTrack = trackInfo
            // 采样率和位深同步
            Task {
                guard trackInfo.state == "Playing" else { return }
                self?.audioManager.onFormatUpdate = {
                    [weak self] sampleRate, bitDepth in
                    self?.audioManager.updateOutputFormat()
                    self?.updateStatusTitle()
                }
                self?.audioManager.startMonitoring()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self?.audioManager.stopMonitoring()
                }
            }
            // 歌词
            Task {
                print("歌词")
                self?.viewModel?.isPlaying = false
                self?.viewModel?.currentlyPlayingLyrics = []
                if trackInfo.state == "Playing" || trackInfo.state == "playing"
                {
                    if self?.isShowLyric == true {
                        guard let context = self?.coreDataContainer.viewContext
                        else { return }

                        // 先查本地
                        context.refreshAllObjects()
                        if let songObject = SongObject.fetchSong(
                            byID: trackInfo.trackID, context: context)
                        {
                            print("songObject: \(songObject)")
                            let localLyrics = songObject.getLyrics()
                            if !localLyrics.isEmpty {
                                print("本地歌词")
                                self?.viewModel?.currentlyPlayingLyrics =
                                    localLyrics
                                self?.viewModel?.currentAlbumColor = trackInfo.color ?? nil
                                self?.viewModel?.isPlaying = true
                                return
                            }
                        }

                        // 网络歌词
                        do {
                            let trackName = trackInfo.name
                            let artist = trackInfo.artist

                            if !trackName.isEmpty, !artist.isEmpty {
                                let lyrics =  try await self?.networkUtil?.fetchLyrics(trackName: trackName, artist: artist, trackID: trackInfo.trackID, album: trackInfo.album, genre: trackInfo.genre)

                                if let lyrics, !lyrics.isEmpty {
                                    print("网络歌词")
                                    guard
                                        let finishLyrics = self?.finishLyric(
                                            lyrics)
                                    else {
                                        print("finishLyrics error")
                                        return
                                    }
                                    self?.viewModel?.currentlyPlayingLyrics =
                                        finishLyrics
                                    self?.viewModel?.currentAlbumColor = trackInfo.color ?? nil
                                    self?.viewModel?.isPlaying = true
                                    SongObject.saveSong(
                                        id: trackInfo.trackID,
                                        trackName: trackName,
                                        lyrics: finishLyrics, in: context)
                                }
                            } else {
                                print("原始标题或艺术家为空，跳过歌词请求")
                            }
                        } catch {
                            print("网络歌词获取失败: \(error)")
                        }
                    } else {
                        self?.viewModel?.isPlaying = false
                        self?.viewModel?.currentlyPlayingLyrics = []
                    }
                } else {
                    self?.viewModel?.isPlaying = false
                    self?.viewModel?.currentlyPlayingLyrics = []
                }

            }
        }

        playbackNotifier?.scriptNotification()
    }
    func finishLyric(_ rawLyrics: [LyricLine]) -> [LyricLine] {
        guard let last = rawLyrics.last else { return rawLyrics }
        let virtualEndLine = LyricLine(
            startTime: last.startTimeMS + 5000, words: "")
        return rawLyrics + [virtualEndLine]
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "显示歌词", action: #selector(toggleWindow), keyEquivalent: "s")
        toggleItem.state = isShowLyric ? .on : .off
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "删除本地缓存", action: #selector(delCurrentSongObject),
                keyEquivalent: "del"))
        //        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "剪贴板读取原始歌曲名", action: #selector(manualNamefetch),
                keyEquivalent: "v"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        statusBarItem.menu = menu

        updateStatusTitle()
    }

    private func updateStatusTitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let sampleRate =
                Double(self.audioManager.currentFormat.sampleRate) / 1000.0
            let bit = self.audioManager.currentFormat.bitDepth
            let title = String(format: "%2d Bit\n%.1fkHz", bit, sampleRate)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.minimumLineHeight = 11
            paragraphStyle.maximumLineHeight = 11

            let attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 11, weight: .medium),
                .baselineOffset: -6,
            ]
            let attributedTitle = NSAttributedString(
                string: title, attributes: attributes)

            guard let button = self.statusBarItem.button else { return }
            button.wantsLayer = true  // 确保启用 layer

            // 滚动动画效果
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromTop
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut)
            button.layer?.add(transition, forKey: "textScroll")

            button.attributedTitle = attributedTitle
        }
    }

    private func activateLyricsSelectorView(){
        if selectorWindow == nil{
            createLyricsManualView()
        }
        selectorWindow.makeKeyAndOrderFront(nil)
    }
    private func deactivateLyricsSelectorView(){
        if selectorWindow != nil{
            selectorWindow.orderOut(nil)
        }
    }
    
    private func activateCaraokeView() {
        print("activateCaraokeView")
        if isShowLyric {
            if karaoKeWindow == nil {
                createCaraokeView()
            }
            karaoKeWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func deactiveCaraokeView() {
        print("deactiveCaraokeView")
        if karaoKeWindow != nil {
            karaoKeWindow.orderOut(nil)
        }
    }
    @MainActor @objc func toggleWindow() {
        print("isWindowVisible:\(isShowLyric)")
        isShowLyric.toggle()
        playbackNotifier?.scriptNotification()

        if let toggleItem = statusBarItem.menu?.items.first(where: {
            $0.action == #selector(toggleWindow)
        }) {
            toggleItem.title = isShowLyric ? "显示歌词" : "显示歌词"
            toggleItem.state = isShowLyric ? .on : .off
        }
    }

    @objc func delCurrentSongObject() {
        guard let trackID = playbackNotifier?.fetchCurrentTrack()?.trackID
        else {
            return
        }
        let context = coreDataContainer.viewContext
        SongObject.deleteSong(byID: trackID, context: context)
        playbackNotifier?.scriptNotification()
    }

    @objc func manualNamefetch() {
        Task{
            await manulNameAsyncFetch()
        }
    }
    
    private func manulNameAsyncFetch() async{
        do {
            guard let manualName = NSPasteboard.general.string(forType: .string)
            else {
                print("⚠️ 粘贴板中没有字符串内容")
                return
            }
            print("粘贴板: \(manualName)")
            guard let currentTrack = playbackNotifier?.fetchCurrentTrack() else {
                return
            }

            let context = coreDataContainer.viewContext
            let netEaseLyrics = try await networkUtil?.fetchLyrics(
                trackName: manualName,
                artist: currentTrack.artist,
                trackID: currentTrack.trackID,
                album: currentTrack.album,
                genre: currentTrack.genre
            )

            if !netEaseLyrics!.isEmpty {
                let finishLyrics = finishLyric(netEaseLyrics!)
                SongObject.deleteSong(
                    byID: currentTrack.trackID, context: context)
                SongObject.saveSong(
                    id: currentTrack.trackID, trackName: manualName,
                    lyrics: finishLyrics, in: context)
                playbackNotifier?.scriptNotification()
            }

        } catch {
            print("粘贴板获取歌词失败：\(error)")
        }
    }
    private func createCaraokeView() {
        if karaoKeWindow == nil {
            let contentView = NSHostingView(
                rootView: KaraokeView().environmentObject(self.viewModel!))
            // 创建无边框窗口，初步定位到屏幕底部 100 点高度
            karaoKeWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 100, width: 800, height: 100),
                styleMask: [.borderless],  // 无边框
                backing: .buffered,
                defer: false
            )

            karaoKeWindow.contentView = contentView
            karaoKeWindow.isOpaque = false
            karaoKeWindow.backgroundColor = .clear
            karaoKeWindow.level = .floating  // 后续会修改为前置显示
            // 精确让窗口贴近屏幕底部
            if let screenFrame = NSScreen.main?.visibleFrame {
                let windowHeight: CGFloat = 100
                let windowY = screenFrame.minY
                let windowX = (screenFrame.width - 800) / 2
                karaoKeWindow.setFrame(
                    NSRect(
                        x: windowX, y: windowY, width: 800, height: windowHeight
                    ), display: false)
            }
            karaoKeWindow.isMovableByWindowBackground = true
            karaoKeWindow.orderOut(nil)
        } else {
            karaoKeWindow.makeKeyAndOrderFront(nil)
        }
    }
    private func createLyricsManualView(){
        if selectorWindow == nil{
            let contentView = NSHostingView(
                rootView: LyricsSelectorView().environmentObject(self.viewModel!)
            )
            selectorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 450, width: 450, height: 450),
                styleMask: [.borderless],  // 无边框
                backing: .buffered,
                defer: false
            )
            selectorWindow.contentView = contentView
            selectorWindow.isOpaque = false
            selectorWindow.backgroundColor = .clear
            selectorWindow.level = .floating  // 后续会修改为前置显示
            // 精确让窗口贴近屏幕底部
            if let screenFrame = NSScreen.main?.visibleFrame {
                let windowHeight: CGFloat = 450
                let windowY = screenFrame.minY+25
                let windowX = (screenFrame.width - 450) / 2
                selectorWindow.setFrame(
                    NSRect(
                        x: windowX, y: windowY, width: 450, height: windowHeight
                    ), display: false)
            }
            selectorWindow.isMovableByWindowBackground = true
            selectorWindow.orderOut(nil)
        } else {
            selectorWindow.makeKeyAndOrderFront(nil)
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
