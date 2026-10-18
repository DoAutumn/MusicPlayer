import AVFoundation
import Foundation

enum PlayMode: String {
    case sequential
    case repeatOne
    case shuffle

    var symbol: String {
        switch self {
        case .sequential: return "list.number"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    var label: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var next: PlayMode {
        switch self {
        case .sequential: return .repeatOne
        case .repeatOne: return .shuffle
        case .shuffle: return .sequential
        }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double
    @Published var mode: PlayMode
    @Published var playbackError: String?
    @Published var selectedID: Track.ID?

    private let player = AVPlayer()
    private var queue: [Track] = []
    private var index = 0
    private var shuffleHistory: [Track.ID] = []
    private var scrubbing = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    init() {
        let saved = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.9
        volume = min(max(saved, 0), 1)
        mode = PlayMode(rawValue: UserDefaults.standard.string(forKey: "playMode") ?? "") ?? .sequential
        player.volume = Float(volume)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            Task { @MainActor in
                self.note(time: seconds)
            }
        }
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate > 0.05
            Task { @MainActor in
                self?.isPlaying = playing
            }
        }
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player.volume = Float(clamped)
        UserDefaults.standard.set(clamped, forKey: "volume")
    }

    func cycleMode() {
        mode = mode.next
        if mode != .shuffle {
            shuffleHistory.removeAll()
        }
        UserDefaults.standard.set(mode.rawValue, forKey: "playMode")
    }

    func updateQueue(_ tracks: [Track]) {
        queue = tracks
        if let current, let found = tracks.firstIndex(where: { $0.id == current.id }) {
            index = found
        } else {
            index = -1
        }
    }

    func sync(with tracks: [Track]) {
        guard let current, let fresh = tracks.first(where: { $0.id == current.id }) else { return }
        self.current = fresh
        if let found = queue.firstIndex(where: { $0.id == fresh.id }) {
            queue[found] = fresh
        }
    }

    func play(_ track: Track, queue tracks: [Track]) {
        queue = tracks
        index = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        current = track
        currentTime = 0
        duration = 0
        playbackError = nil
        let item = AVPlayerItem(url: track.url)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            let length = item.duration.seconds
            Task { @MainActor in
                self?.apply(status: status, message: message, length: length)
            }
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAfterEnding()
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    func toggle(selected: Track?, queue tracks: [Track]) {
        if let selected, current?.id != selected.id {
            play(selected, queue: tracks)
            return
        }
        if current == nil {
            if let first = tracks.first {
                play(first, queue: tracks)
            }
            return
        }
        resumeOrPause()
    }

    func toggleCurrent() {
        if let selectedID, current?.id != selectedID,
           let selected = queue.first(where: { $0.id == selectedID }) {
            play(selected, queue: queue)
            return
        }
        if current == nil {
            guard let first = queue.first else { return }
            play(first, queue: queue)
            return
        }
        resumeOrPause()
    }

    private func resumeOrPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, currentTime >= duration - 0.4 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func next() {
        if mode == .shuffle {
            playRandom()
        } else {
            step(by: 1)
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if mode == .shuffle, let previousID = shuffleHistory.popLast(),
           let track = queue.first(where: { $0.id == previousID }) {
            play(track, queue: queue)
            return
        }
        step(by: -1)
    }

    private func advanceAfterEnding() {
        switch mode {
        case .repeatOne:
            replayCurrent()
        case .shuffle:
            playRandom()
        case .sequential:
            step(by: 1)
        }
    }

    private func step(by delta: Int) {
        let target = index + delta
        guard queue.indices.contains(target) else {
            if delta > 0 {
                player.pause()
                isPlaying = false
            } else {
                seek(to: 0)
            }
            return
        }
        play(queue[target], queue: queue)
    }

    private func playRandom() {
        guard !queue.isEmpty else { return }
        if queue.count == 1 {
            replayCurrent()
            return
        }
        if let current {
            shuffleHistory.append(current.id)
            if shuffleHistory.count > 200 {
                shuffleHistory.removeFirst(shuffleHistory.count - 200)
            }
        }
        var nextIndex = Int.random(in: 0..<queue.count)
        var tries = 0
        while nextIndex == index, tries < 6 {
            nextIndex = Int.random(in: 0..<queue.count)
            tries += 1
        }
        play(queue[nextIndex], queue: queue)
    }

    private func replayCurrent() {
        currentTime = 0
        let startTime = CMTime(seconds: 0, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.player.play()
                self?.isPlaying = true
            }
        }
    }

    func beginScrub() {
        scrubbing = true
    }

    func seek(to time: Double) {
        let target = max(time, 0)
        currentTime = target
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func endScrub(at time: Double) {
        seek(to: time)
        scrubbing = false
    }

    private func note(time: Double) {
        guard !scrubbing, time.isFinite else { return }
        currentTime = max(time, 0)
        if let length = player.currentItem?.duration.seconds, length.isFinite, length > 0 {
            duration = length
        }
    }

    private func apply(status: AVPlayerItem.Status, message: String?, length: Double) {
        if status == .failed {
            playbackError = message ?? "这首歌无法播放"
            isPlaying = false
        }
        if length.isFinite, length > 0 {
            duration = length
        }
    }
}

func formatTime(_ time: Double) -> String {
    guard time.isFinite, time > 0 else { return "0:00" }
    let total = Int(time.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
