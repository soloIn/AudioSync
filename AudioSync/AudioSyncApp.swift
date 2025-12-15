//
//  AudioSyncApp.swift
//  AudioSync
//
//  Created by solo on 4/29/25.
//

import AppKit
import CoreAudio
import Foundation
import SwiftData
import SwiftUI

@main
struct AudioSyncApp: App {
    // 使用 Adaptor 连接传统的 AppKit 委托，处理复杂的窗口逻辑
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) var openWindow
    // 全局状态对象
    @ObservedObject var viewModel = ViewModel.shared

    //持久化存储配置
    @AppStorage("isKaraokeVisible") var isKaraokeVisible: Bool = false
    @AppStorage("isAudioSwitch") var isAudioSwitch: Bool = true

    @ObservedObject var audioManager = AudioFormatManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self  // 注册 Song 模型

        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    // 初始化：注入容器
    init() {
        appDelegate.modelContainer = sharedModelContainer
    }

    var body: some Scene {
        MenuBarExtra(
            content: { menuContent },
            label: {
                Group {
                    Image(systemName: "headphones.circle")
                }
                .onAppear {
                    appDelegate.openWindow = openWindow
                    viewModel.enableAudioSync = isAudioSwitch
                    viewModel.isKaraokeVisible = isKaraokeVisible
                    viewModel.isViewLyricsShow =
                        isKaraokeVisible || viewModel.isFullScreenVisible

                }
            }
        )
        .onChange(
            of: isKaraokeVisible,
            { oldValue, newValue in
                if viewModel.isKaraokeVisible != newValue {
                    viewModel.isKaraokeVisible = newValue
                }

            }
        )
        .onChange(of: isAudioSwitch) {
            viewModel.enableAudioSync = isAudioSwitch
        }
        WindowGroup("fullScreenLyrics", id: "fullScreen") {
            FullScreenView().environmentObject(
                viewModel
            )
            .onWindowDidAppear { window in
                window.collectionBehavior = .fullScreenPrimary

                // 阻止 ESC
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    event in
                    if event.keyCode == 53 { return nil }  // Esc
                    return event
                }

                // 设置退出全屏时关闭窗口
                let delegate = FullScreenWindowDelegate()
                delegate.onExitFullScreen = {
                    viewModel.isFullScreenVisible = false
                    window.close()
                }
                window.delegate = delegate

                // 将 delegate 附着到 window 上，避免释放
                objc_setAssociatedObject(
                    window,
                    "FullScreenDelegateKey",
                    delegate,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )

                // 切换到全屏
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
            .onDisappear {
                viewModel.isFullScreenVisible = false
            }
        }
    }
    @ViewBuilder
    var menuContent: some View {
        // 显示当前音频格式 (采样率/位深)
        Toggle(
            String(
                format: "%d Bit  %.1f kHz",
                AudioFormatManager.shared.bitDepth ?? 0,
                Double(AudioFormatManager.shared.sampleRate ?? 0) / 1000.0
            ),
            isOn: $isAudioSwitch
        )
        Divider()
        Toggle("显示歌词", isOn: $isKaraokeVisible)
        Divider()
        Toggle("全屏歌词", isOn: $viewModel.isFullScreenVisible)
        Divider()
        Button("相似歌手", action: appDelegate.showSimilarArtistWindow)
        Divider()
        Button("剪贴板读取原始歌曲名", action: appDelegate.manualNamefetch)
        Divider()
        Button("删除本地缓存", action: appDelegate.delCurrentSongObject)
        Divider()
        Button("删除所有缓存", action: appDelegate.delAllSongObject)
        Divider()
        
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

extension View {
    func onWindowDidAppear(_ perform: @escaping (NSWindow) -> Void) -> some View
    {
        background(WindowFinder(onWindow: perform))
    }
}
struct WindowFinder: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        if let window = nsView.window {
            Task {
                await MainActor.run {
                    onWindow(window)
                }
            }
        }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// NSWindowDelegate 实现，处理退出全屏
class FullScreenWindowDelegate: NSObject, NSWindowDelegate {
    var onExitFullScreen: (() -> Void)?

    func windowDidExitFullScreen(_ notification: Notification) {
        // 延迟关闭，等系统完成退出动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.onExitFullScreen?()
        }
    }
}
