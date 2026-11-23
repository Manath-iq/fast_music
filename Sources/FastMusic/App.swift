import AppKit
import SwiftUI

extension Notification.Name {
    static let fastMusicFocusSearch = Notification.Name("FastMusic.focusSearch")
    static let fastMusicPanelOpened = Notification.Name("FastMusic.panelOpened")
    static let fastMusicPanelClosed = Notification.Name("FastMusic.panelClosed")
}

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
    private var outsideMonitor: Any?
    private var localMonitor: Any?

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
        if !demo {
            Preferences.shared.onAction = { [weak self] action in
                guard let self else { return }
                switch action {
                case .panel: self.toggle()
                case .wave: if !self.store.signedIn { self.showPanel() }; self.store.startWave()
                case .favorites: if !self.store.signedIn { self.showPanel() }; self.store.startFavorites()
                }
            }
            Preferences.shared.start()
            if args.contains("--enable-login") { Preferences.shared.setLogin(true) }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown, event.window === self.popover.contentViewController?.view.window {
                if event.window?.firstResponder is RecorderButton { return event }
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.keyCode == 3 {
                    NotificationCenter.default.post(name: .fastMusicFocusSearch, object: nil)
                    return nil
                }
                if event.keyCode == 53 { self.popover.performClose(nil); return nil }
            } else if event.type != .keyDown,
                      event.window !== self.popover.contentViewController?.view.window,
                      event.window !== self.statusItem?.button?.window {
                self.popover.performClose(nil)
            }
            return event
        }
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
        NotificationCenter.default.post(name: .fastMusicPanelOpened, object: nil)
        // An accessory app otherwise automatically focuses its first text field.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    @objc private func showPanel() { if !popover.isShown { toggle() } }

    func popoverDidShow(_ notification: Notification) {
        NotificationCenter.default.post(name: .fastMusicPanelOpened, object: nil)
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        store.setVisible(false)
        NotificationCenter.default.post(name: .fastMusicPanelClosed, object: nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidResignActive(_ notification: Notification) { popover.performClose(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func renderScreenshot(to path: String) {
        // NSSlider is an AppKit view: capture through NSHostingView so native controls are included.
        let host = NSHostingView(rootView: PlayerView(store: store, previewSettings: ProcessInfo.processInfo.arguments.contains("--settings-preview")))
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
