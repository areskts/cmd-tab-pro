import AppKit
import ScreenCaptureKit

final class WindowPreviewCapture {
    private let cache = NSCache<NSString, NSImage>()
    private var task: Task<Void, Never>?

    init() {
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func cached(_ window: AppWindow) -> NSImage? {
        cache.object(forKey: "\(window.pid):\(window.state.id)" as NSString)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func load(_ windows: [AppWindow], onImage: @escaping (CGWindowID, NSImage) -> Void) {
        stop()
        guard CGPreflightScreenCaptureAccess() else { return }
        task = Task { @MainActor [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                for record in windows {
                    guard !Task.isCancelled, let self else { return }
                    guard let window = content.windows.first(where: {
                        $0.windowID == record.state.id && $0.owningApplication?.processID == record.pid
                    }) else { continue }
                    let configuration = SCStreamConfiguration()
                    let size = DockPolicy.thumbnailSize(for: window.frame.size)
                    configuration.width = Int(size.width)
                    configuration.height = Int(size.height)
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    do {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration
                        )
                        guard !Task.isCancelled else { return }
                        let preview = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
                        self.cache.setObject(preview, forKey: "\(record.pid):\(record.state.id)" as NSString,
                                             cost: image.bytesPerRow * image.height)
                        onImage(record.state.id, preview)
                    } catch {
                        continue
                    }
                }
            } catch {
                return
            }
        }
    }
}
