import Foundation

enum NowPlayingBridge {
    static let bundleID = "com.doautumn.musicplayer"
    static let notification = Notification.Name("com.doautumn.musicplayer.nowPlaying")

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("now-playing.json")
    }

    static func publish(title: String?, playing: Bool) {
        let payload: [String: Any] = [
            "title": title ?? "",
            "playing": playing && !(title ?? "").isEmpty
        ]
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: payload,
            deliverImmediately: true
        )
    }
}
