//
//  AudioSyncApp.swift
//  AudioSync
//
//  Created by solo on 4/29/25.
//

import AppKit
import CoreAudio
import Foundation
import SwiftUI

@main
struct AudioSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var viewModel = ViewModel.shared
    @AppStorage("isKaraokeVisible") var isKaraokeVisible: Bool = false
    @State var isFullScreenVisible: Bool = false
    @State var karaoKeWindow: NSWindow? = nil
    @State var selectorWindow: NSWindow? = nil
    @Environment(\.openWindow) var openWindow
    @ObservedObject var audioManager = AudioFormatManager.shared

    private func CreateKaraoke() {
        if isKaraokeVisible && !isFullScreenVisible{
            if karaoKeWindow == nil {
                let contentView = NSHostingView(
                    rootView: KaraokeView().environmentObject(viewModel))
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
                            x: windowX, y: windowY, width: 800,
                            height: windowHeight),
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
    private func createLyricsManualView(needNanualSelection: Bool) {
        if needNanualSelection {
            if selectorWindow == nil {
                let contentView = NSHostingView(
                    rootView: LyricsSelectorView().environmentObject(
                        viewModel)
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
                            x: windowX, y: windowY, width: 450,
                            height: windowHeight
                        ), display: false)
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
    var body: some Scene {
        MenuBarExtra(
            content: {
                Toggle(String(format: "%d Bit  %.1f kHz",
                              audioManager.bitDepth ?? 0,
                              Double(audioManager.sampleRate ?? 0) / 1000.0), isOn: .constant(false))
                Divider()
                Toggle("显示歌词", isOn: $isKaraokeVisible)
                    .keyboardShortcut("s")
                Divider()
                Toggle("全屏歌词", isOn: $isFullScreenVisible)
                    .keyboardShortcut("f")
                Divider()
                Button("删除本地缓存", action: appDelegate.delCurrentSongObject)
                    .keyboardShortcut("d")
                Divider()
                Button("剪贴板读取原始歌曲名", action: appDelegate.manualNamefetch)
                Divider()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            },
            label: {
                Group {
                    Image(systemName: "headphones.circle")
                }
                .onAppear {
                    viewModel.isShowLyrics =
                        isKaraokeVisible || isFullScreenVisible
                    CreateKaraoke()
                }
                .onReceive(viewModel.$needNanualSelection) { newValue in
                    createLyricsManualView(needNanualSelection: newValue)
                }
            }
        )
        .onChange(of: audioManager.bitDepth, {
            #if DEBUG
            print("监听格式: \(audioManager.bitDepth)")
            #endif
        })
        .onChange(
            of: isFullScreenVisible,
            {
                #if DEBUG
                print("isFullScreenVisible change: \(isFullScreenVisible)")
                #endif
                viewModel.isShowLyrics = isKaraokeVisible || isFullScreenVisible
                if isFullScreenVisible {
                    openWindow(id: "fullScreen")
                    NSApplication.shared.activate()
                }
                // 全屏时去掉卡拉OK显示
                CreateKaraoke()
            }
        )
        .onChange(
            of: isKaraokeVisible,
            {
                #if DEBUG
                print("isKaraokeVisible change: \(isKaraokeVisible)")
                #endif
                viewModel.isShowLyrics = isKaraokeVisible || isFullScreenVisible
                CreateKaraoke()
            })
        
        
        WindowGroup("fullScreenLyrics", id: "fullScreen") {
            FullScreenView().environmentObject(viewModel)
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
                        isFullScreenVisible = false
                        window.close()
                    }
                    window.delegate = delegate

                    // 将 delegate 附着到 window 上，避免释放
                    objc_setAssociatedObject(
                        window, "FullScreenDelegateKey", delegate,
                        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

                    // 切换到全屏
                    if !window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                    }
                }
                .onDisappear {
                    isFullScreenVisible = false
                }
        }
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
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.onExitFullScreen?()
        }
    }
}
