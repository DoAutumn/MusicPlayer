import Foundation

struct Track: Identifiable, Hashable, Sendable {
    let url: URL
    let sortKey: String
    var title: String
    var artist: String
    var album: String

    var id: String { url.path }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        return [title, artist, album, sortKey].contains { $0.localizedStandardContains(needle) }
    }

    static func from(url: URL) -> Track {
        let name = displayName(for: url)
        return Track(url: url, sortKey: name, title: name, artist: "", album: "")
    }

    static func displayName(for url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"#[A-Za-z0-9]+$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        name = name.replacingOccurrences(of: "+-+", with: " - ")
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
