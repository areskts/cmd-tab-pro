import AppKit

enum DashboardStyle {
    private static let cardBackgroundColor = NSColor(name: NSColor.Name("DashboardCardBackground")) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.14, alpha: 1)
            : NSColor(calibratedWhite: 0.965, alpha: 1)
    }

    static func background() -> NSBox {
        let background = NSBox()
        background.boxType = .custom
        background.isTransparent = false
        background.borderWidth = 0
        background.fillColor = .textBackgroundColor
        return background
    }

    static func card(_ content: NSView) -> NSBox {
        let card = NSBox()
        card.boxType = .custom
        card.isTransparent = false
        card.borderWidth = 0
        card.cornerRadius = 12
        card.fillColor = cardBackgroundColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    static func group(_ rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
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
        stack.spacing = 7
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    static func contentView(_ stack: NSStackView) -> NSView {
        let background = background()
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -20)
        ])
        return background
    }

    static func settingRow(title: String, description: String, control: NSView) -> NSView {
        let labels = NSStackView(views: [
            textLabel(title, size: 12, weight: .medium),
            textLabel(description, size: 11, color: .secondaryLabelColor)
        ])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    static func sectionTitle(_ text: String) -> NSTextField {
        textLabel(text, size: 14, weight: .semibold)
    }

    static func compact(_ control: NSControl) {
        control.controlSize = .mini
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
