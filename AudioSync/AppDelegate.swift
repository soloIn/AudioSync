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
    var audioManager = AudioFormatManager.shared
    var playbackNotifier: PlaybackNotifier?
    var networkUtil: NetworkUtil?
    @ObservedObject var viewModel: ViewModel = ViewModel.shared
    private var cancellables = Set<AnyCancellable>()
    let coreDataContainer: NSPersistentContainer

    override init() {
        // 使用你的 .xcdatamodeld 文件名（不带扩展）
        self.coreDataContainer = NSPersistentContainer(name: "Lyrics")
        super.init()
        coreDataContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("❌ CoreData 加载失败: \(error)")
            } else {
                #if DEBUG
                    print("✅ CoreData 加载成功: \(description)")
                #endif
            }
        }
        coreDataContainer.viewContext.automaticallyMergesChangesFromParent =
            true
        coreDataContainer.viewContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.accessory)
//        registerMetalShaders()
        playbackNotifier = PlaybackNotifier()
        Task { @MainActor in
            self.networkUtil = NetworkUtil(viewModel: self.viewModel)
            self.viewModel.$isShowLyrics
                .removeDuplicates()
                .sink { [weak self] isShowLyrics in
                    guard let self = self else { return }
                    #if DEBUG
                        print("监听 isShowLyrics 变化: \(isShowLyrics)")
                    #endif
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
        playbackNotifier?.onPlay = { [weak self] trackInfo in
            if let lastTrack = self?.viewModel.currentTrack?.trackID,
                lastTrack == trackInfo.trackID,
                self?.viewModel.currentlyPlayingLyrics.isEmpty != true
            {
                self?.viewModel.startLyricUpdater()
                #if DEBUG
                    print("歌曲已准备好,跳过处理")
                #endif
                return
            }
            self?.viewModel.currentTrack = trackInfo
            // 采样率和位深同步
            Task {
                guard trackInfo.state == "Playing" else { return }
                self?.audioManager.onFormatUpdate = {
                    [weak self] sampleRate, bitDepth in
                    self?.audioManager.updateOutputFormat()
                }
                self?.audioManager.startMonitoring()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self?.audioManager.stopMonitoring()
                }
            }
            // 歌词
            Task {
                #if DEBUG
                    print("歌词")
                #endif
                self?.viewModel.currentlyPlayingLyrics = []
                self?.viewModel.stopLyricUpdater()
                if self?.viewModel.isShowLyrics == true {
                    guard let context = self?.coreDataContainer.viewContext
                    else { return }

                    // 先查本地
                    context.refreshAllObjects()
                    if let songObject = SongObject.fetchSong(
                        byID: trackInfo.trackID, context: context)
                    {
                        #if DEBUG
                            print("songObject: \(songObject)")
                        #endif
                        let localLyrics = songObject.getLyrics()
                        if !localLyrics.isEmpty {
                            #if DEBUG
                                print("本地歌词")
                            #endif
                            self?.viewModel.currentlyPlayingLyrics =
                                localLyrics
                            self?.viewModel.currentAlbumColor =
                                trackInfo.color ?? []
                            self?.viewModel.startLyricUpdater()
                            return
                        }
                    }

                    // 网络歌词
                    do {
                        let trackName = trackInfo.name
                        let artist = trackInfo.artist

                        if !trackName.isEmpty, !artist.isEmpty {
                            let lyrics = try await self?.networkUtil?
                                .fetchLyrics(
                                    trackName: trackName, artist: artist,
                                    trackID: trackInfo.trackID,
                                    album: trackInfo.album,
                                    genre: trackInfo.genre)
                            if let lyrics, !lyrics.isEmpty {
                                #if DEBUG
                                    print("网络歌词")
                                #endif
                                guard
                                    let finishLyrics = self?.finishLyric(
                                        lyrics)
                                else {
                                    #if DEBUG
                                        print("finishLyrics error")
                                    #endif
                                    return
                                }
                                self?.viewModel.currentlyPlayingLyrics =
                                    finishLyrics
                                self?.viewModel.currentAlbumColor =
                                    trackInfo.color ?? []
                                self?.viewModel.startLyricUpdater()
                                SongObject.saveSong(
                                    id: trackInfo.trackID,
                                    trackName: trackName,
                                    lyrics: finishLyrics, in: context)
                            }
                        } else {
                            #if DEBUG
                                print("原始标题或艺术家为空，跳过歌词请求")
                            #endif
                        }
                    } catch {
                        #if DEBUG
                            print("网络歌词获取失败: \(error)")
                        #endif
                    }
                }

            }
        }
    }
    func finishLyric(_ rawLyrics: [LyricLine]) -> [LyricLine] {
        guard let last = rawLyrics.last else { return rawLyrics }
        let virtualEndLine = LyricLine(
            startTime: last.startTimeMS + 5000, words: "")
        return rawLyrics + [virtualEndLine]
    }

    @objc func delCurrentSongObject() {
        guard let trackID = playbackNotifier?.fetchCurrentTrack()?.trackID
        else {
            return
        }
        let context = coreDataContainer.viewContext
        SongObject.deleteSong(byID: trackID, context: context)
        viewModel.currentTrack = nil
        playbackNotifier?.scriptNotification()
    }

    @objc func manualNamefetch() {
        Task {
            await manulNameAsyncFetch()
        }
    }

    private func manulNameAsyncFetch() async {
        do {
            guard let manualName = NSPasteboard.general.string(forType: .string)
            else {
                #if DEBUG
                    print("⚠️ 粘贴板中没有字符串内容")
                #endif
                return
            }
            #if DEBUG
                print("粘贴板: \(manualName)")
            #endif
            guard let currentTrack = playbackNotifier?.fetchCurrentTrack()
            else {
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
            #if DEBUG
                print("粘贴板获取歌词失败：\(error)")
            #endif
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
