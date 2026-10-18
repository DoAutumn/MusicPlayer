import AppKit
import Foundation

@MainActor
final class LibraryModel: ObservableObject {
    static let defaultPath = "/Volumes/共享文件/音乐"
    private static let pathKey = "libraryPath"

    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var rootMissing = false
    @Published var taggedCount = 0
    @Published var rootPath: String

    var rootURL: URL { URL(fileURLWithPath: rootPath) }

    init() {
        rootPath = UserDefaults.standard.string(forKey: Self.pathKey) ?? Self.defaultPath
    }

    func reload() {
        let root = rootURL
        isLoading = true
        rootMissing = false
        taggedCount = 0
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.scan(root)
            }.value
            switch scanned {
            case .missing:
                tracks = []
                rootMissing = true
                isLoading = false
            case .tracks(let found):
                tracks = found
                isLoading = false
                await enrich(found)
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择曲库"
        panel.message = "选择放歌曲的文件夹"
        panel.directoryURL = rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.pathKey)
        reload()
    }

    private func enrich(_ items: [Track]) async {
        let targets = items.filter { $0.url.pathExtension.lowercased() == "mp3" }
        var cursor = 0
        var pending: [(String, ID3Reader.Tag)] = []

        func flush() {
            guard !pending.isEmpty else { return }
            var byPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            for (path, tag) in pending {
                guard var track = byPath[path] else { continue }
                if let title = tag.title { track.title = title }
                if let artist = tag.artist { track.artist = artist }
                if let album = tag.album { track.album = album }
                byPath[path] = track
            }
            tracks = tracks.map { byPath[$0.id] ?? $0 }
            taggedCount += pending.count
            pending.removeAll(keepingCapacity: true)
        }

        await withTaskGroup(of: (String, ID3Reader.Tag)?.self) { group in
            func enqueue() {
                guard cursor < targets.count else { return }
                let url = targets[cursor].url
                cursor += 1
                group.addTask {
                    guard let tag = ID3Reader.read(url: url) else { return nil }
                    return (url.path, tag)
                }
            }
            for _ in 0..<4 { enqueue() }
            for await item in group {
                if let item { pending.append(item) }
                if pending.count >= 40 { flush() }
                enqueue()
            }
        }
        flush()
    }

    private nonisolated static func scan(_ root: URL) -> ScanResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .missing
        }
        let allowed: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "alac"]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .missing
        }
        let tracks = urls
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .map(Track.from)
            .sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        return .tracks(tracks)
    }
}

private enum ScanResult: Sendable {
    case missing
    case tracks([Track])
}
