//
//  FullScreenView.swift
//  AudioSync
//
//  Created by solo on 5/23/25.
//

import SwiftUI

struct FullScreenView: View {
    @EnvironmentObject var viewmodel: ViewModel

    var body: some View {
        ZStack {
            AnimatedMeshGradientView(
                colors: viewmodel.currentAlbumColor.map { Color($0) })
            .overlay(Color.black.opacity(0.3))
            GeometryReader { geo in
                HStack {
                    albumArt
                        .frame(
                            minWidth: 0.50 * (geo.size.width),
                            maxWidth: canDisplayLyrics
                                ? 0.50 * (geo.size.width) : .infinity)
                    if canDisplayLyrics {
                        lyrics(padding: 0.5 * (geo.size.height))
                            .frame(
                                minWidth: 0.50 * (geo.size.width),
                                maxWidth: 0.50 * (geo.size.width))
                    }
                }
            }
        }

    }

    var canDisplayLyrics: Bool {
        viewmodel.isShowLyrics
    }

    @ViewBuilder func lyricLineView(for element: LyricLine, index: Int)
        -> some View
    {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: element.words)
            if let trlycs = element.attachments[.translation()]?.stringValue,
                !trlycs.isEmpty
            {
                Text(verbatim: trlycs)
            }
        }
        .foregroundStyle(
            .white
        )
        .font(
            .custom(
                viewmodel.karaokeFont.fontName,
                size: 38)
        )
}

    @ViewBuilder func lyrics(padding: CGFloat) -> some View {
        VStack(alignment: .leading) {
            Spacer()
            ScrollViewReader { proxy in
                // 使用ScrollView替代List获得更好的动画控制
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading) {  // Lazy加载优化性能
                        ForEach(
                            Array(
                                viewmodel.currentlyPlayingLyrics.enumerated()),
                            id: \.element
                        ) { offset, element in
                            lyricLineView(for: element, index: offset)
                                .padding(10)
                                .opacity(
                                    offset == viewmodel.currentlyPlayingLyrics
                                        .count - 1
                                        ? 0
                                        :  // 保留原来的末尾隐藏
                                        (offset
                                            == viewmodel
                                            .currentlyPlayingLyricsIndex
                                            ? 1 : 0.5)  // 当前行不透明，其他行30%透明度
                                )
                                // 添加透明度变化的平滑过渡
                                .animation(
                                    .smooth(duration: 0.2),
                                    value: viewmodel.currentlyPlayingLyricsIndex
                                )
                                // 为位置变化添加弹性动画
                                .animation(
                                    .interactiveSpring(
                                        response: 0.9, dampingFraction: 0.6),
                                    value: viewmodel.currentlyPlayingLyricsIndex
                                )
                        }
                    }
                    .padding(.trailing, 100)
                }
                .onAppear {
                    // 优化初始滚动延迟
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 1)) {
                            if let currentIndex = viewmodel
                                .currentlyPlayingLyricsIndex
                            {
                                proxy.scrollTo(
                                    viewmodel.currentlyPlayingLyrics[
                                        currentIndex], anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: viewmodel.currentlyPlayingLyricsIndex) {
                    newValue in
                    withAnimation(.smooth(duration: 1.2)) {
                        if let currentIndex = newValue {
                            proxy.scrollTo(
                                viewmodel.currentlyPlayingLyrics[currentIndex],
                                anchor: .center
                            )
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .mask(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black, .clear]),
                    startPoint: .top, endPoint: .bottom))
            Spacer()
        }
    }

    @ViewBuilder var albumArt: some View {
        VStack {
            Spacer()
            if let album = viewmodel.currentTrack?.albumCover {
                Image(nsImage: album)
                    .resizable()
                    .clipShape(
                        .rect(
                            cornerRadii: .init(
                                topLeading: 10, bottomLeading: 10,
                                bottomTrailing: 10, topTrailing: 10))
                    )
                    .shadow(radius: 5)
                    .frame(
                        width: canDisplayLyrics ? 450 : 700,
                        height: canDisplayLyrics ? 450 : 700)
            } else {
                Image(systemName: "music.note.list")
                    .resizable()
                    .shadow(radius: 3)
                    .scaleEffect(0.5)
                    .background(.gray)
                    .clipShape(
                        .rect(
                            cornerRadii: .init(
                                topLeading: 10, bottomLeading: 10,
                                bottomTrailing: 10, topTrailing: 10))
                    )
                    .shadow(radius: 5)
                    .frame(
                        width: canDisplayLyrics ? 450 : 650,
                        height: canDisplayLyrics ? 450 : 650)
            }
            Group {
                Text(verbatim: viewmodel.currentTrack?.name ?? "")
                    .font(.title)
                    .bold()
                    .padding(.top, 30)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: (canDisplayLyrics ? 450 : 650) * 0.9)
                Text(verbatim: viewmodel.currentTrack?.artist ?? "")
                    .font(.title2)
            }
            .frame(height: 35)
            HStack {
                Button {
                    if viewmodel.isShowLyrics {
                        viewmodel.isShowLyrics = false
                    } else {
                        viewmodel.isShowLyrics = true
                    }

                } label: {
                    Image(systemName: "music.note.list")
                }
                .disabled(viewmodel.currentlyPlayingLyrics.isEmpty)

            }
            Spacer()
        }
    }
    struct AnimatedMeshContent: View {
        var colors: [Color]

        var body: some View {
            TimelineView(.animation) { _ in
                let t = Date().timeIntervalSinceReferenceDate
                let offset = 0.2 * sin(t) * 0.8
                let hueShift = 0.02 * sin(t * 0.4)

                let animatedColors = colors.enumerated().map { index, color in
                    color.adjustedHue(by: Double(index) * hueShift * 360)
                }
                let animatedPoints: [[CGFloat]] = [
                    [0.0, 0.0], [0.5 + offset, 0.0], [1.0, 0.0],
                    [0.0, 0.5 + offset], [0.5, 0.5], [1.0, 0.5 - offset],
                    [0.0, 1.0], [0.5 - offset, 1.0], [1.0, 1.0],
                ]
                let simdPoints: [SIMD2<Float>] = animatedPoints.map { point in
                    SIMD2<Float>(Float(point[0]), Float(point[1]))
                }
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: simdPoints,
                    colors: colors
                )
                .ignoresSafeArea()
            }
        }
    }
    struct AnimatedMeshGradientView: View {
        var colors: [Color]

        var body: some View {
            AnimatedMeshContent(colors: colors)
        }
    }

}
extension Color {
    func adjustedHue(by degrees: Double) -> Color {
        // 将 Color 转换为 UIColor
        let uiColor = NSColor(self)

        // 获取 HSB 分量
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(
            &hue, saturation: &saturation, brightness: &brightness,
            alpha: &alpha)

        // 调整色相值
        let hueAdjustment = CGFloat(degrees / 360)
        var newHue = hue + hueAdjustment
        if newHue > 1.0 { newHue -= 1.0 }
        if newHue < 0.0 { newHue += 1.0 }

        // 创建新的 UIColor 并转换回 Color
        let adjustedUIColor = NSColor(
            hue: newHue, saturation: saturation, brightness: brightness,
            alpha: alpha)
        return Color(adjustedUIColor)
    }
}
extension Animation {
    static let lyricSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.6,
        blendDuration: 0.3
    )
    
    static let lyricTransition = Animation.timingCurve(
        0.25, 0.1, 0.25, 1, // 自定义贝塞尔曲线
        duration: 0.8
    )
    static func smoothScroll(duration: TimeInterval) -> Animation {
            .timingCurve(0.25, 0.8, 0.5, 1, duration: duration) // 缓入缓出加强版
        }
}
