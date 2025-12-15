/// 系统级 Tooltip 管理器（基于 NSPopover）
/// - 特点：
///   - 使用 NSPopover，完全脱离 SwiftUI 布局（性能 & 手感 ≈ Xcode / Apple Music）
///   - Popover 与 NSHostingView 只创建一次，后续复用，避免 hover 卡顿
///   - 双 TrackingArea（源 View + Popover）保证鼠标进入 Tooltip 后不会消失
///   - show / close 均带防抖，避免列表滚动或快速移动导致闪烁

import AppKit
import SwiftUI
final class TooltipPopoverController {
    static let shared = TooltipPopoverController()

    private var popover: NSPopover?
    private var textView: TooltipTextView?
    private var closeWorkItem: DispatchWorkItem?
    private var isHoveringPopover: Bool = false
    private var showWorkItem: DispatchWorkItem?

    private var lastMouseLocation: NSPoint?
    private var lastContentKey: String?

    /// 冻结 hover 发生时的鼠标位置（源 View 局部坐标）
    func freezeMouseLocation(_ pointInWindow: NSPoint, in view: NSView?) {
        guard
            let view,
            let _ = view.window
        else { return }

        // 转换到源 View 的本地坐标系
        let localPoint = view.convert(pointInWindow, from: nil)
        self.lastMouseLocation = localPoint
    }

    /// 根据源 View 在屏幕中的位置，自动选择 Popover 弹出方向
    private func preferredEdge(for view: NSView) -> NSRectEdge {
        guard
            let window = view.window,
            let screen = window.screen
        else {
            return .maxY
        }

        let viewFrameInScreen = view.convert(view.bounds, to: nil)
        let windowFrameInScreen = window.convertToScreen(viewFrameInScreen)

        let screenMidY = screen.visibleFrame.midY
        return windowFrameInScreen.midY > screenMidY ? .minY : .maxY
    }

    /// 为 Popover 内容视图安装 NSTrackingArea
    /// 用于检测鼠标是否进入 / 离开 Tooltip 自身
    private func installPopoverTracking(on view: NSView) {
        // 多次调用不会产生副作用（Popover 内容视图生命周期固定）
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(tracking)
    }

    @objc(mouseEntered:)
    func popoverMouseEntered(_ event: NSEvent) {
        isHoveringPopover = true
        closeWorkItem?.cancel()
    }

    @objc(mouseExited:)
    func popoverMouseExited(_ event: NSEvent) {
        isHoveringPopover = false
        close()
    }

    /// 显示 Tooltip（带防抖）
    /// - 参数：
    ///   - view: 触发 Tooltip 的源 NSView（用于定位 Popover）
    ///   - contentKey: 内容缓存键，避免重复构建
    ///   - content: Tooltip 内部 SwiftUI 内容
    func show(
        relativeTo view: NSView,
        contentKey: String
    ) {
        closeWorkItem?.cancel()
        showWorkItem?.cancel()

        // 延迟显示（防抖）：
        // - 避免快速滚动 / 快速移动鼠标时频繁 show / close
        // - 行为与系统 Tooltip 一致（hover 稳定后才显示）
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }

            if self.lastContentKey == contentKey,
               self.popover?.isShown == true {
                return
            }
            self.lastContentKey = contentKey

            // Popover 仅创建一次，避免重复分配带来的卡顿
            if self.popover == nil {
                let pop = NSPopover()
                pop.behavior = .applicationDefined
                pop.animates = false
                pop.contentViewController = NSViewController()
                self.popover = pop
            }

            // 使用 NSTextView 替代 SwiftUI Text 避免首次卡顿和文本截断
            if self.textView == nil {
                let tv = TooltipTextView(text: contentKey)
                self.textView = tv
                self.popover?.contentViewController?.view = tv
                self.installPopoverTracking(on: tv)
            } else {
                self.textView?.subviews
                    .compactMap { ($0 as? NSScrollView)?.documentView as? NSTextView }
                    .first?
                    .string = contentKey
            }

            if let localPoint = self.lastMouseLocation {

                let anchorRect = NSRect(
                    x: localPoint.x,
                    y: localPoint.y,
                    width: 1,
                    height: 1
                )

                let edge = self.preferredEdge(for: view)
                self.popover?.show(
                    relativeTo: anchorRect,
                    of: view,
                    preferredEdge: edge
                )
                return
            }

            let edge = self.preferredEdge(for: view)
            self.popover?.show(
                relativeTo: view.bounds,
                of: view,
                preferredEdge: edge
            )
        }

        showWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// 请求关闭 Tooltip（带防抖）
    /// - 若鼠标当前位于 Tooltip 内部，则不会关闭
    /// - 延迟关闭可避免从源 View → Tooltip 时误触发关闭
    func close() {
        showWorkItem?.cancel()
        closeWorkItem?.cancel()

        // 若鼠标仍在 Tooltip 内，禁止关闭
        guard !isHoveringPopover else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.popover?.performClose(nil)
        }

        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
}

/// SwiftUI 与 AppKit 的桥接 Hover 捕获层
/// - 使用 NSTrackingArea 捕获 mouseEntered / mouseExited
/// - 不参与 SwiftUI 布局，仅作为事件源
struct HoverTrackingView: NSViewRepresentable {
    let onHoverIn: (NSView) -> Void
    let onHoverOut: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        // 使用 inVisibleRect 确保在视图尺寸变化 / 列表复用时 tracking 仍然有效
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: context.coordinator,
            userInfo: nil
        )

        view.addTrackingArea(tracking)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onHoverIn: onHoverIn, onHoverOut: onHoverOut)
    }

    /// NSTrackingArea 的事件接收者
    /// 注意：
    /// - 必须使用 @objc(mouseEntered:) / @objc(mouseExited:)
    /// - selector 名称必须与 AppKit 期望的完全一致
    /// - 不能使用 override，也不需要继承 NSResponder
    final class Coordinator: NSObject {
        var view: NSView?
        let onHoverIn: (NSView) -> Void
        let onHoverOut: () -> Void

        init(
            onHoverIn: @escaping (NSView) -> Void,
            onHoverOut: @escaping () -> Void
        ) {
            self.onHoverIn = onHoverIn
            self.onHoverOut = onHoverOut
        }

        @objc(mouseEntered:)
        func mouseEntered(_ event: NSEvent) {
            if let view {
                TooltipPopoverController.shared.freezeMouseLocation(
                    event.locationInWindow,
                    in: view
                )
                onHoverIn(view)
            }
        }

        @objc(mouseExited:)
        func mouseExited(_ event: NSEvent) {
            onHoverOut()
        }
    }
}


final class TooltipTextView: NSView {
    init(text: String) {
        super.init(frame: .zero)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .secondaryLabelColor
        textView.string = text

        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        addSubview(scrollView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}
