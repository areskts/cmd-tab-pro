import AppKit

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

enum DashboardStyle {
    static func background() -> NSVisualEffectView {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        return background
    }

    static func card(_ content: NSView) -> NSBox {
        let card = NSBox()
        card.boxType = .custom
        card.isTransparent = false
        card.borderWidth = 0.5
        card.borderColor = .separatorColor
        card.cornerRadius = 14
        card.fillColor = .controlBackgroundColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    static func group(_ rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = separator()
                stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return card(stack)
    }

    static func section(_ title: String, content: NSView) -> NSView {
        let stack = NSStackView(views: [sectionTitle(title), content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    static func contentView(_ stack: NSStackView) -> NSView {
        let background = background()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        background.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        return background
    }

    static func pageHeader(_ title: String, subtitle: String) -> NSView {
        let description = textLabel(subtitle, size: 13, color: .secondaryLabelColor)
        description.maximumNumberOfLines = 2
        description.lineBreakMode = .byWordWrapping
        let header = NSStackView(views: [textLabel(title, size: 24, weight: .semibold), description])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        return header
    }

    static func settingRow(title: String, description: String, control: NSView) -> NSView {
        settingRow(title: title, descriptionLabel: textLabel(description, size: 12, color: .secondaryLabelColor), control: control)
    }

    static func settingRow(title: String, descriptionLabel: NSTextField, control: NSView) -> NSView {
        let labels = NSStackView(views: [
            textLabel(title, size: 14, weight: .medium),
            descriptionLabel
        ])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row
    }

    static func sectionTitle(_ text: String) -> NSTextField {
        textLabel(text, size: 15, weight: .semibold)
    }

    static func configure(_ control: NSControl) {
        control.controlSize = .regular
        control.font = .systemFont(ofSize: 13)
    }

    static func textLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                          color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private static func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}
