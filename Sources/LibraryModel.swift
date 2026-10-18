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

    private var generation = 0

    var rootURL: URL { URL(fileURLWithPath: rootPath) }

    init() {
        rootPath = UserDefaults.standard.string(forKey: Self.pathKey) ?? Self.defaultPath
        reload()
    }

    func reload() {
        let root = rootURL
        generation += 1
        let token = generation
        isLoading = true
        rootMissing = false
        taggedCount = 0
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.scan(root)
            }.value
            guard token == self.generation else { return }
            switch scanned {
            case .missing:
                tracks = []
                rootMissing = true
                isLoading = false
            case .tracks(let found):
                tracks = found
                isLoading = false
                let urls = found
                    .filter { $0.url.pathExtension.lowercased() == "mp3" }
                    .map(\.url)
                let tags = await Self.readTags(urls: urls)
                guard token == self.generation else { return }
                apply(tags)
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

    private func apply(_ tags: [(String, ID3Reader.Tag)]) {
        guard !tags.isEmpty else { return }
        var byPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for (path, tag) in tags {
            guard var track = byPath[path] else { continue }
            if let title = tag.title { track.title = title }
            if let artist = tag.artist { track.artist = artist }
            if let album = tag.album { track.album = album }
            byPath[path] = track
        }
        tracks = tracks.map { byPath[$0.id] ?? $0 }
        taggedCount += tags.count
    }

    /// 在协作线程池里读标签。不能从主界面任务组里读，否则会占住主线程，列表一直停在「正在读取」。
    private nonisolated static func readTags(urls: [URL]) async -> [(String, ID3Reader.Tag)] {
        await withTaskGroup(of: (String, ID3Reader.Tag)?.self) { group in
            var pending = urls.makeIterator()
            var result: [(String, ID3Reader.Tag)] = []
            func enqueue() {
                guard let url = pending.next() else { return }
                group.addTask {
                    guard let tag = ID3Reader.read(url: url) else { return nil }
                    return (url.path, tag)
                }
            }
            for _ in 0..<8 { enqueue() }
            for await item in group {
                if let item { result.append(item) }
                enqueue()
            }
            return result
        }
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
