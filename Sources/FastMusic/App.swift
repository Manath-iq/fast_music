import AppKit
import SwiftUI

@main
struct FastMusicApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: MusicStore!
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let demo = args.contains("--demo") || args.contains("--screenshot")
        if !demo, !args.contains("--no-show"), let bundle = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("site.manath.fastmusic.show"), object: nil)
            NSApp.terminate(nil); return
        }
        store = MusicStore(demo: demo)
        if let index = args.firstIndex(of: "--screenshot"), args.indices.contains(index + 1) {
            renderScreenshot(to: args[index + 1]); NSApp.terminate(nil); return
        }
        let controller = NSHostingController(rootView: PlayerView(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showPanel), name: Notification.Name("site.manath.fastmusic.show"), object: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let renderer = ImageRenderer(content: Burst().fill(Theme.yellow).frame(width: 20, height: 20))
            if let image = renderer.nsImage { image.isTemplate = false; button.image = image }
            button.toolTip = "Fast Music"
            button.setAccessibilityLabel("Открыть Fast Music")
            button.target = self; button.action = #selector(toggle)
        }
        if args.contains("--preview-window") {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PlayerView(store: store)))
            window.title = "Fast Music — предпросмотр"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 460)); window.center()
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            previewWindow = window; store.setVisible(true)
        } else if !args.contains("--no-show") && (!UserDefaults.standard.bool(forKey: "hasLaunched") || args.contains("--show")) {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            toggle()
        }
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        store.setVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPanel() { if !popover.isShown { toggle() } }

    func popoverDidClose(_ notification: Notification) { store.setVisible(false) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func renderScreenshot(to path: String) {
        // NSSlider is an AppKit view: capture through NSHostingView so native controls are included.
        let host = NSHostingView(rootView: PlayerView(store: store))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
}
