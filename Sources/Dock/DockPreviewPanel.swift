import AppKit
import QuartzCore

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ThumbnailButton: NSButton {
    private let preview = NSView()
    private let icon = NSImageView()

    init(label: String, icon: NSImage?, image: NSImage?) {
        super.init(frame: .zero)
        title = ""
        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 11)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 2
        preview.layer = CALayer()
        preview.wantsLayer = true
        preview.layer?.contentsGravity = .resizeAspectFill
        preview.layer?.masksToBounds = true
        preview.layer?.cornerRadius = 8
        self.icon.image = icon
        self.icon.imageScaling = .scaleProportionallyUpOrDown
        for item in [preview, self.icon, caption] { item.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(preview)
        preview.addSubview(self.icon)
        addSubview(caption)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -4),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            caption.heightAnchor.constraint(equalToConstant: caption.intrinsicContentSize.height),
            self.icon.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            self.icon.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            self.icon.widthAnchor.constraint(equalToConstant: 56),
            self.icon.heightAnchor.constraint(equalToConstant: 56)
        ])
        setPreview(image)
    }

    required init?(coder: NSCoder) { nil }

    func setPreview(_ image: NSImage?) {
        let contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        preview.layer?.contents = contents
        icon.isHidden = contents != nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

final class DockPreviewPanel {
    private let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
    private var buttons = [CGWindowID: NSButton]()
    private var actions = [CGWindowID: () -> Void]()
    var frame: CGRect { panel.frame }
    var isVisible: Bool { panel.isVisible }

    init() {
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none
        panel.setAccessibilityLabel("Dock 窗口预览")
    }

    func show(app: NSRunningApplication, windows: [AppWindow], anchor: CGRect, screen: NSScreen,
              style: DockDisplayStyle = .titles, capture: WindowPreviewCapture? = nil,
              onSelect: @escaping (AppWindow) -> Void) {
        buttons.removeAll()
        actions.removeAll()
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 18
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        let content = NSView()
        content.autoresizingMask = [.width, .height]
        glass.contentView = content
        let title = DashboardStyle.textLabel(app.localizedName ?? "窗口预览", size: 12, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        let thumbnails = style == .thumbnails
        let width = min(thumbnails ? min(CGFloat(windows.count) * 164 + 16, 680) : 320, screen.visibleFrame.width - 24)
        let buttonWidth = thumbnails ? 156 : width - 24 - (windows.count > 6 ? 14 : 0)
        let buttonHeight: CGFloat = thumbnails ? 130 : 42
        let spacing: CGFloat = thumbnails ? 8 : 6
        row.orientation = thumbnails ? .horizontal : .vertical
        row.alignment = thumbnails ? .centerY : .leading
        row.spacing = spacing
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        for window in windows {
            let label = window.title.isEmpty ? "未命名窗口" : window.title
            let suffix = window.state.minimized ? (thumbnails ? "\n已最小化" : " · 已最小化") : ""
            let button = thumbnails
                ? ThumbnailButton(label: label + suffix, icon: app.icon, image: capture?.cached(window))
                : NSButton(title: label + suffix, target: nil, action: nil)
            button.target = self
            button.action = #selector(selectWindow(_:))
            button.tag = Int(window.state.id)
            button.bezelStyle = thumbnails ? .flexiblePush : .accessoryBarAction
            button.showsBorderOnlyWhileMouseInside = true
            if !thumbnails {
                button.imagePosition = .imageLeading
                button.alignment = .left
                button.imageScaling = .scaleProportionallyDown
                button.font = .systemFont(ofSize: 12)
                button.attributedTitle = NSAttributedString(string: label + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
                ])
                button.lineBreakMode = .byTruncatingTail
                button.image = placeholder(app.icon, size: 16)
            }
            button.toolTip = label + (window.state.minimized ? "（已最小化）" : "")
            button.setAccessibilityLabel(button.toolTip)
            button.setAccessibilityHelp("点击前置此窗口；开启点击最小化后，可再次点击前台窗口将其最小化")
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: buttonWidth), button.heightAnchor.constraint(equalToConstant: buttonHeight)])
            row.addArrangedSubview(button)
            buttons[window.state.id] = button
            actions[window.state.id] = { onSelect(window) }
        }
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = thumbnails
        scroll.hasVerticalScroller = !thumbnails
        scroll.autohidesScrollers = true
        row.setFrameSize(NSSize(width: thumbnails ? CGFloat(windows.count) * 164 - 8 : buttonWidth,
                               height: thumbnails ? buttonHeight : CGFloat(windows.count) * (buttonHeight + spacing) - spacing))
        scroll.documentView = row
        content.addSubview(title)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        panel.contentView = glass
        let visibleHeight = thumbnails ? buttonHeight : CGFloat(min(windows.count, 6)) * (buttonHeight + spacing) - spacing
        let scrollerHeight = thumbnails && row.frame.width > width - 24 && scroll.scrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        let size = CGSize(width: width, height: visibleHeight + title.intrinsicContentSize.height + 28 + scrollerHeight)
        panel.setFrame(DockPolicy.previewFrame(anchor: anchor, size: size, screen: screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
    }

    func setImage(_ image: NSImage, for id: CGWindowID) {
        if let button = buttons[id] as? ThumbnailButton {
            button.setPreview(image)
        } else {
            buttons[id]?.image = image
        }
    }

    func hide() {
        panel.orderOut(nil)
        buttons.removeAll()
        actions.removeAll()
    }

    @objc private func selectWindow(_ sender: NSButton) {
        actions[CGWindowID(sender.tag)]?()
    }

    private func placeholder(_ icon: NSImage?, size: CGFloat) -> NSImage? {
        guard let image = icon?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: size, height: size)
        return image
    }
}
