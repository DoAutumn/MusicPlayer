import AppKit
import SwiftUI

@main
struct QukuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryModel()
    @StateObject private var player = PlayerModel()
    @StateObject private var chrome = AppChrome.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .background(SpaceMonitorHost(player: player))
        }
        .defaultSize(width: 880, height: 640)
        .commands {
            CommandMenu("播放") {
                Button("播放或暂停") {
                    player.toggleCurrent()
                }
                Button("下一首") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("上一首") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("重新扫描") { library.reload() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra(isInserted: $chrome.menuBarVisible) {
            MenuBarContent()
                .environmentObject(player)
                .environmentObject(chrome)
        } label: {
            Image(nsImage: Self.trayIcon)
        }
    }

    /// 18pt 模板图标，@2x/@3x 保持菜单栏清晰。
    private static let trayIcon: NSImage = {
        let pointSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: pointSize)
        let scales: [(CGFloat, String)] = [
            (1, "TrayIconTemplate"),
            (2, "TrayIconTemplate@2x"),
            (3, "TrayIconTemplate@3x")
        ]
        var loadedAny = false
        for (_, name) in scales {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
            loadedAny = true
        }
        if !loadedAny {
            let fallback = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MusicPlayer") ?? NSImage()
            fallback.isTemplate = true
            fallback.size = pointSize
            return fallback
        }
        image.isTemplate = true
        image.size = pointSize
        return image
    }()
}

@MainActor
final class AppChrome: ObservableObject {
    static let shared = AppChrome()
    @Published var menuBarVisible = false

    func hideDock() {
        menuBarVisible = true
        NSApp.setActivationPolicy(.accessory)
    }

    func prepareWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidOpen() {
        menuBarVisible = false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Task { @MainActor in
            AppChrome.shared.hideDock()
        }
        return false
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var chrome: AppChrome

    var body: some View {
        Button("打开 MusicPlayer") {
            chrome.prepareWindow()
            openWindow(id: "main")
            DispatchQueue.main.async {
                chrome.windowDidOpen()
            }
        }
        Divider()
        Button(player.isPlaying ? "暂停" : "播放") {
            player.toggleCurrent()
        }
        Button("下一首") { player.next() }
        Button("上一首") { player.previous() }
        Divider()
        Button("退出 MusicPlayer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// 只在这个视图自己成为第一响应者时接收空格。不安装全局 keyDown 监听，避免中文输入法丢掉第一个字母。
private final class PlaybackKeyView: NSView {
    var onSpace: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            if window.firstResponder == nil || window.firstResponder === window {
                window.makeFirstResponder(self)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 49, flags.isEmpty {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

private struct SpaceMonitorHost: NSViewRepresentable {
    let player: PlayerModel

    func makeNSView(context: Context) -> PlaybackKeyView {
        let view = PlaybackKeyView()
        context.coordinator.install(player: player, keyView: view)
        return view
    }

    func updateNSView(_ view: PlaybackKeyView, context: Context) {
        context.coordinator.keyView = view
        view.onSpace = {
            Task { @MainActor in
                player.toggleCurrent()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var keyView: PlaybackKeyView?
        private var monitor: Any?

        func install(player: PlayerModel, keyView: PlaybackKeyView) {
            self.keyView = keyView
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.moveFocusIfNeeded(for: event)
                return event
            }
        }

        func moveFocusIfNeeded(for event: NSEvent) {
            guard let window = event.window, let keyView, let content = window.contentView else { return }
            if Self.containsSearchField(content, at: event.locationInWindow) { return }
            DispatchQueue.main.async {
                guard window.firstResponder is LineSearchTextView
                    || window.firstResponder == nil
                    || window.firstResponder === window else { return }
                window.makeFirstResponder(keyView)
            }
        }

        private static func containsSearchField(_ view: NSView, at windowPoint: NSPoint) -> Bool {
            if let search = view as? LineSearchTextView {
                return search.bounds.contains(search.convert(windowPoint, from: nil))
            }
            return view.subviews.contains { containsSearchField($0, at: windowPoint) }
        }
    }
}
