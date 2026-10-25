import AppKit

enum DockPolicy {
    static func thumbnailSize(for source: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(480 / source.width, 320 / source.height)
        return CGSize(width: max(1, floor(source.width * scale)), height: max(1, floor(source.height * scale)))
    }

    static func appKitFrame(_ frame: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: desktopTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func nearEdge(_ point: CGPoint, screens: [CGRect]) -> Bool {
        screens.contains { frame in
            frame.contains(point) && (point.x - frame.minX < 180 || frame.maxX - point.x < 180 || point.y - frame.minY < 180)
        }
    }

    static func previewFrame(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let bounds = screen.insetBy(dx: 12, dy: 12)
        let size = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        let left = abs(anchor.minX - screen.minX)
        let right = abs(screen.maxX - anchor.maxX)
        let bottom = abs(anchor.minY - screen.minY)
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 8)
        if left < min(right, bottom) { origin = CGPoint(x: anchor.maxX + 8, y: anchor.midY - size.height / 2) }
        if right < min(left, bottom) { origin = CGPoint(x: anchor.minX - size.width - 8, y: anchor.midY - size.height / 2) }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    static func canMinimizeClick(down: CGPoint, up: CGPoint, icon: CGRect, duration: TimeInterval,
                                 modifiers: Bool, clickCount: Int) -> Bool {
        !modifiers && clickCount == 1 && duration < 0.4 && icon.contains(down) && icon.contains(up)
            && hypot(up.x - down.x, up.y - down.y) < 4
    }
}
