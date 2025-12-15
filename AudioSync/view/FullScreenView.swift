import AppKit
import Combine
import SwiftUI

struct FullScreenView: View {
    @EnvironmentObject var viewmodel: ViewModel
    @State private var cachedColors: [Color] = []

    var body: some View {
        Group {
            if viewmodel.isFullScreenVisible {
                ZStack {
                    GeometryReader { geo in
                        HStack {
                            albumArt
                                .frame(
                                    minWidth: 0.50 * (geo.size.width),
                                    maxWidth: canDisplayLyrics
                                        ? 0.50 * (geo.size.width) : .infinity
                                )
                            if canDisplayLyrics {
                                LyricsPlayerViewWrapper(
                                    lyrics: viewmodel.currentlyPlayingLyrics,
                                    currentIndex: $viewmodel
                                        .currentlyPlayingLyricsIndex,
                                    geo: geo
                                )
                                .frame(
                                    minWidth: 0.50 * (geo.size.width),
                                    maxWidth: 0.50 * (geo.size.width)
                                )
                            }
                        }
                    }
                }
                .background {
                    ZStack {
                        if !cachedColors.isEmpty {
                            AnimatedMeshGradientView(
                                colors: cachedColors
                            )
                        }
                        Color.black.opacity(0.1)
                    }
                }
                .onAppear {
                    // 修复：确保视图出现时初始化颜色和歌词
                    cachedColors = meshColors()
                }
                .onChange(of: viewmodel.currentTrack?.color) {
                    oldValue,
                    newValue in
                    cachedColors = meshColors()
                }
                // 修复：监听歌词变化以确保更新
                .onChange(of: viewmodel.currentlyPlayingLyrics) { _, newValue in
                    if !newValue.isEmpty {
                        cachedColors = meshColors()
                    }
                }
            }
        }
    }

    struct LyricsPlayerViewWrapper: NSViewRepresentable {
        let lyrics: [LyricLine]
        @Binding var currentIndex: Int?
        let geo: GeometryProxy
        let padding: CGFloat = 22
        let textHeight: CGFloat = 60
        var translationHeight: CGFloat = 0

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false

            // 创建文档视图容器
            let containerView = NSView()
            scrollView.documentView = containerView
            context.coordinator.containerView = containerView

            // 设置滚动视图代理
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.scrollViewDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            let coordinator = context.coordinator
            coordinator.parent = self

            // 更新歌词行
            updateLyricLines(
                coordinator: coordinator,
                scrollView: scrollView
            )

            // 自动滚动逻辑
            if !coordinator.isUserScrolling {
                scrollToCurrentLyric(
                    coordinator: coordinator,
                    scrollView: scrollView
                )
            }

            // 优化：只更新附近行的透明度
            updateNearbyLineTransparencies(coordinator: coordinator)
        }

        private func updateLyricLines(
            coordinator: Coordinator,
            scrollView: NSScrollView
        ) {
            guard let containerView = coordinator.containerView else { return }

            // 如果歌词数量没有变化，只需更新受影响的行
            if coordinator.lastLyricsCount == lyrics.count {
                // 优化：只更新变化的行
                updateChangedLines(coordinator: coordinator)
                return
            }

            // 清除旧视图
            containerView.subviews.forEach { $0.removeFromSuperview() }
            coordinator.lineViews.removeAll()

            // 创建新歌词行
            var yOffset: CGFloat = 0
            let topSpacing = geo.size.height / 2.5
            let bottomSpacing = geo.size.height / 1.5

            // 添加顶部间距
            let topSpacer = NSView(
                frame: CGRect(
                    x: 0,
                    y: yOffset,
                    width: geo.size.width,
                    height: topSpacing
                )
            )
            containerView.addSubview(topSpacer)
            yOffset += topSpacing

            for (index, line) in lyrics.reversed().enumerated() {
                let reversedIndex = lyrics.count - 1 - index
                let isActive = reversedIndex == currentIndex
                var duration: Int = 0
                if reversedIndex < lyrics.count - 1 {
                    let nextTime = lyrics[reversedIndex + 1].startTimeMS
                    let currentTime = lyrics[reversedIndex].startTimeMS
                    duration = Int((nextTime - currentTime) * 1000)
                }
                // 计算翻译高度（如果存在）
                let translationHeight: CGFloat =
                    if let translation = line.attachments[.translation()]?
                        .stringValue,
                        !translation.isEmpty
                    {
                        30  // 为翻译预留额外高度
                    } else {
                        0
                    }
                let totalHeight = textHeight + translationHeight
                let lineView = LyricLineView(
                    element: line,
                    isActive: isActive,
                    fontName: NSFont.boldSystemFont(ofSize: 30).fontName,
                    currentIndex: currentIndex,
                    lineIndex: reversedIndex,
                    duration: duration,
                    totalHeight: totalHeight,
                    width: geo.size.width
                )

                lineView.frame = CGRect(
                    x: 0,
                    y: yOffset,
                    width: geo.size.width,  // 使用geo的宽度确保初始布局正确
                    height: totalHeight
                )

                containerView.addSubview(lineView)
                yOffset += totalHeight + padding

                // 存储引用
                coordinator.lineViews.append(lineView)
            }

            // 添加底部间距
            let bottomSpacer = NSView(
                frame: CGRect(
                    x: 0,
                    y: yOffset,
                    width: geo.size.width,
                    height: bottomSpacing
                )
            )
            containerView.addSubview(bottomSpacer)
            yOffset += bottomSpacing

            // 更新容器大小
            containerView.frame = CGRect(
                origin: .zero,
                size: CGSize(
                    width: geo.size.width,
                    height: yOffset
                )
            )

            // 更新内容大小
            scrollView.documentView?.setFrameSize(
                NSSize(width: geo.size.width, height: yOffset)
            )

            // 记录当前歌词数量
            coordinator.lastLyricsCount = lyrics.count
            coordinator.lastCurrentIndex = currentIndex
        }

        // 优化：只更新变化的行
        private func updateChangedLines(coordinator: Coordinator) {
            guard let lastIndex = coordinator.lastCurrentIndex,
                let newIndex = currentIndex,
                lastIndex != newIndex
            else { return }

            // 更新旧当前行
            if let oldLineView = coordinator.lineViews.first(where: {
                $0.lineIndex == lastIndex
            }) {
                oldLineView.updateActiveState(isActive: false)
            }

            // 更新新当前行
            if let newLineView = coordinator.lineViews.first(where: {
                $0.lineIndex == newIndex
            }) {
                newLineView.updateActiveState(isActive: true)
            }

            coordinator.lastCurrentIndex = newIndex
        }

        private func scrollToCurrentLyric(
            coordinator: Coordinator,
            scrollView: NSScrollView
        ) {
            guard let currentIndex = currentIndex,
                lyrics.indices.contains(currentIndex),
                let documentView = scrollView.documentView
            else { return }

            let topSpacing = geo.size.height / 2.5
            let totalLines = lyrics.count
            let visibleIndex = totalLines - 1 - currentIndex
            let lineViews = coordinator.lineViews
            let targetLineIndex = visibleIndex

            // 累加目标行之前所有行的高度
            let yOffset = lineViews.prefix(targetLineIndex).reduce(CGFloat(0)) {
                partialResult,
                lineView in
                partialResult + lineView.totalHeight + padding
            }

            // 再加上目标行的一半高度让它居中
            let targetY =
                yOffset - (scrollView.contentSize.height - topSpacing) / 2
                + (lineViews[targetLineIndex].totalHeight / 2)
            // 确保目标位置在有效范围内
            let maxY = documentView.frame.height - scrollView.contentSize.height
            let clampedY = min(max(targetY, 0), maxY)

            coordinator.isProgrammaticScroll = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1  // 缩短动画时间
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                scrollView.contentView.animator().setBoundsOrigin(
                    NSPoint(x: 0, y: clampedY)
                )
            } completionHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coordinator.isProgrammaticScroll = false
                }
            }
        }

        // 优化：只更新附近行的透明度
        private func updateNearbyLineTransparencies(coordinator: Coordinator) {
            guard let currentIndex = currentIndex else { return }

            let visibleRange =
                max(
                    0,
                    currentIndex - 2
                )...min(
                    lyrics.count - 1,
                    currentIndex + 2
                )

            for lineView in coordinator.lineViews {
                if visibleRange.contains(lineView.lineIndex) {
                    lineView.updateTransparency(currentIndex: currentIndex)
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        class Coordinator: NSObject {
            var parent: LyricsPlayerViewWrapper
            var isUserScrolling = false
            var containerView: NSView?
            var lineViews: [LyricLineView] = []
            var isProgrammaticScroll = false
            var lastLyricsCount = 0
            var lastCurrentIndex: Int? = nil  // 跟踪上一次的当前行索引

            init(parent: LyricsPlayerViewWrapper) {
                self.parent = parent
            }

            @objc func scrollViewDidScroll(_ notification: Notification) {
                guard !isProgrammaticScroll else { return }
                isUserScrolling = true
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                perform(
                    #selector(resetScrollingFlag),
                    with: nil,
                    afterDelay: 1.0
                )
            }

            @objc private func resetScrollingFlag() {
                isUserScrolling = false
            }
        }
    }

    // MARK: - macOS 歌词行视图（优化版）
    class LyricLineView: NSView {
        private let backgroundLabel = NSTextField()
        private let highlightLabel = NSTextField()
        private var element: LyricLine
        private var currentIndex: Int?
        let lineIndex: Int
        let duration: Int?
        let dispearMills = 500
        private var lastDistance: Int? = nil
        private var displayLink: CADisplayLink?
        private var animationStartTime: CFTimeInterval = 0
        private var animationDuration: CFTimeInterval = 0
        let totalHeight: CGFloat
        private let translationLabel = NSTextField()  // 将翻译标签改为属性
        private var translationHeight: CGFloat = 0
        private let maxWidth: CGFloat
        init(
            element: LyricLine,
            isActive: Bool,
            fontName: String,
            currentIndex: Int?,
            lineIndex: Int,
            duration: Int?,
            totalHeight: CGFloat,
            width: CGFloat
        ) {
            self.element = element
            self.currentIndex = currentIndex
            self.lineIndex = lineIndex
            self.duration = duration
            self.totalHeight = totalHeight
            self.maxWidth = width
            super.init(frame: .zero)
            self.wantsLayer = true
            setupViews(isActive: isActive, fontName: fontName)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupViews(isActive: Bool, fontName: String) {
            // 配置标签
            configureLabel(
                label: backgroundLabel,
                text: element.words,
                isActive: isActive,
                isHighlight: false,
                fontName: fontName
            )
            configureLabel(
                label: highlightLabel,
                text: element.words,
                isActive: isActive,
                isHighlight: true,
                fontName: fontName
            )

            // 添加翻译（如果存在）
            if let translation = element.attachments[.translation()]?
                .stringValue,
                !translation.isEmpty
            {
                translationHeight = 40  // 翻译行高度
                configureLabel(
                    label: translationLabel,
                    text: translation,
                    isActive: isActive,
                    isHighlight: true,
                    fontName: fontName,
                    isTranslation: true
                )
                addSubview(translationLabel)
            } else {
                translationHeight = 0
            }

            // 添加子视图
            addSubview(backgroundLabel)
            addSubview(highlightLabel)

            // 设置初始透明度
            updateTransparency(currentIndex: currentIndex)
        }

        func updateActiveState(isActive: Bool) {
            configureLabel(
                label: backgroundLabel,
                text: element.words,
                isActive: isActive,
                isHighlight: false,
                fontName: backgroundLabel.font?.fontName ?? ""
            )
            configureLabel(
                label: highlightLabel,
                text: element.words,
                isActive: isActive,
                isHighlight: true,
                fontName: highlightLabel.font?.fontName ?? ""
            )
        }

        func updateElement(element: LyricLine, isActive: Bool, fontName: String)
        {
            self.element = element
            backgroundLabel.stringValue = element.words
            highlightLabel.stringValue = element.words

            // 更新翻译
            if let translation = element.attachments[.translation()]?
                .stringValue, !translation.isEmpty
            {
                // 查找现有的翻译标签或创建新的
                var translationLabel: NSTextField?
                for subview in subviews {
                    if let label = subview as? NSTextField,
                        label != backgroundLabel && label != highlightLabel
                    {
                        translationLabel = label
                        break
                    }
                }

                if translationLabel == nil {
                    translationLabel = NSTextField()
                    translationLabel?.isEditable = false
                    translationLabel?.isBordered = false
                    translationLabel?.isBezeled = false
                    translationLabel?.drawsBackground = false
                    addSubview(translationLabel!)
                }

                configureLabel(
                    label: translationLabel!,
                    text: translation,
                    isActive: isActive,
                    isHighlight: true,
                    fontName: fontName,
                    isTranslation: true
                )
                translationLabel?.frame = CGRect(
                    x: 0,
                    y: 40,
                    width: bounds.width,
                    height: 20
                )
            } else {
                // 移除翻译标签（如果存在）
                for subview in subviews {
                    if let label = subview as? NSTextField,
                        label != backgroundLabel && label != highlightLabel
                    {
                        label.removeFromSuperview()
                    }
                }
            }

            // 更新透明度
            updateTransparency(currentIndex: currentIndex)
        }

        func updateTransparency(currentIndex: Int?) {
            self.currentIndex = currentIndex
            guard let currentIndex = currentIndex else {
                alphaValue = 0.5
                return
            }

            // 计算当前行与目标行的距离
            let distance = lineIndex - currentIndex

            if distance == -1 {
                // 确保动画只在需要时触发
                if lastDistance == 0 || alphaValue > 0 {
                    startFadeOutAnimation()
                }
            }
            // 其他情况直接设置透明度
            else {
                // 根据距离设置透明度
                var opacity: CGFloat
                if distance == 0 {
                    opacity = 1.0
                } else if distance < -1 {
                    opacity = 0
                } else {
                    opacity = 0.5
                }

                // 立即设置透明度
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    self.animator().alphaValue = opacity
                }
            }

            lastDistance = distance
        }

        private func configureLabel(
            label: NSTextField,
            text: String,
            isActive: Bool,
            isHighlight: Bool,
            fontName: String,
            isTranslation: Bool = false
        ) {
            // 添加换行支持
            label.cell?.wraps = true
            label.cell?.isScrollable = false
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.stringValue = text
            label.isEditable = false
            label.isBordered = false
            label.isBezeled = false
            label.drawsBackground = false

            label.font = NSFont(name: fontName, size: isTranslation ? 24 : 38)

            if isActive {
                if isHighlight {
                    label.textColor = .white
                } else {
                    label.textColor = NSColor.white.withAlphaComponent(0.3)
                }
            } else {
                label.textColor = NSColor.white.withAlphaComponent(0.5)
            }

            let textHeight = calculateTextHeight(
                text: text,
                font: label.font,
                width: maxWidth
            )

            // 如果是翻译标签，更新高度
            if isTranslation {
                translationHeight = textHeight
            }
        }
        // 计算文本高度
        private func calculateTextHeight(
            text: String,
            font: NSFont?,
            width: CGFloat
        ) -> CGFloat {
            guard let font = font else { return 40 }

            let textRect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )

            return max(40, textRect.height)  // 最小高度40
        }
        override func layout() {
            super.layout()
            backgroundLabel.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: 60  // 增加高度以适应多行
            )
            highlightLabel.frame = backgroundLabel.frame

            // 翻译标签布局
            if translationHeight > 0 {
                translationLabel.frame = CGRect(
                    x: 0,
                    y: backgroundLabel.frame.maxY + 5,
                    width: bounds.width,
                    height: translationHeight
                )
                translationLabel.isHidden = false
            } else {
                translationLabel.isHidden = true
            }

            // 更新翻译标签位置和高度
            for subview in subviews {
                if let label = subview as? NSTextField,
                    label != backgroundLabel && label != highlightLabel
                {
                    label.frame = CGRect(
                        x: 0,
                        y: 40,
                        width: bounds.width,
                        height: totalHeight - 40  // 使用剩余高度
                    )
                }
            }
        }

        private func startFadeOutAnimation() {
            // 停止任何正在进行的动画
            stopFadeOutAnimation()

            // 计算动画持续时间
            animationDuration =
                Double(min(dispearMills, duration ?? dispearMills)) / 1000.0

            // 设置动画开始时间
            animationStartTime = CACurrentMediaTime()
            // 使用新的 displayLink API
            displayLink = self.displayLink(
                target: self,
                selector: #selector(updateFadeAnimation)
            )
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc private func updateFadeAnimation() {
            guard displayLink != nil else { return }

            let currentTime = CACurrentMediaTime()
            let elapsedTime = currentTime - animationStartTime
            let progress = min(1.0, CGFloat(elapsedTime / animationDuration))

            // 在主线程安全更新 UI
            DispatchQueue.main.async {
                self.alphaValue = 1.0 - progress

                if progress >= 1.0 {
                    self.stopFadeOutAnimation()
                }
            }
        }

        private func stopFadeOutAnimation() {
            if let token = displayLink {
                token.invalidate()
                displayLink = nil
            }
        }

        deinit {
            stopFadeOutAnimation()
        }
    }

    var canDisplayLyrics: Bool {
        viewmodel.isViewLyricsShow
    }

    func meshColors() -> [Color] {
        if var result = viewmodel.currentTrack?.color {
            while result.count < 9 {
                if let color = viewmodel.currentTrack?.color?.randomElement() {
                    result.append(color)
                }
            }
            return result
        }
        return []
    }

    @ViewBuilder var albumArt: some View {
        VStack {
            Spacer()
            if let album = viewmodel.currentTrack?.albumCover,
                let albumImage = NSImage(data: album){
                Image(nsImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(
                        .rect(
                            cornerRadii: .init(
                                topLeading: 10,
                                bottomLeading: 10,
                                bottomTrailing: 10,
                                topTrailing: 10
                            )
                        )
                    )
                    .shadow(radius: 5)
                    .frame(
                        width: canDisplayLyrics ? 450 : 700,
                        height: canDisplayLyrics ? 450 : 700
                    )
            } else {
                Image(systemName: "music.note.list")
                    .resizable()
                    .shadow(radius: 3)
                    .scaleEffect(0.5)
                    .background(.gray)
                    .clipShape(
                        .rect(
                            cornerRadii: .init(
                                topLeading: 10,
                                bottomLeading: 10,
                                bottomTrailing: 10,
                                topTrailing: 10
                            )
                        )
                    )
                    .shadow(radius: 5)
                    .frame(
                        width: canDisplayLyrics ? 450 : 650,
                        height: canDisplayLyrics ? 450 : 650
                    )
            }
            Group {
                Text(verbatim: viewmodel.currentTrack?.name ?? "")
                    .font(
                        .custom(
                            NSFont.boldSystemFont(ofSize: 28).fontName,
                            size: 28
                        )
                    )
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.top, 30)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: (canDisplayLyrics ? 450 : 650) * 0.9)
                Text(verbatim: viewmodel.currentTrack?.artist ?? "")
                    .font(
                        .custom(
                            NSFont.boldSystemFont(ofSize: 22).fontName,
                            size: 22
                        )
                    )
                    .foregroundStyle(.white)
                    .opacity(0.7)
            }
            .frame(height: 35)
            HStack {
                Button {
                    viewmodel.isViewLyricsShow.toggle()
                } label: {
                    Image(systemName: "music.note.list")
                }
                .disabled(viewmodel.currentlyPlayingLyrics.isEmpty)
            }
            Spacer()
        }
    }

}
