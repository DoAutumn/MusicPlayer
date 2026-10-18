import AppKit
import SwiftUI

@main
struct QukuApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var player = PlayerModel()

    var body: some Scene {
        WindowGroup {
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
