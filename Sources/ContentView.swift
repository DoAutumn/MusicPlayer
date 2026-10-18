import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var player: PlayerModel
    @State private var query = ""
    @State private var selection: Track.ID?
    @State private var dragTime: Double?

    private var filtered: [Track] {
        library.tracks.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            songList
            playerBar
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
        .onChange(of: library.tracks) { _, tracks in
            player.sync(with: tracks)
            player.restore(in: tracks)
            player.updateQueue(filtered)
        }
        .onChange(of: query) { _, _ in
            player.updateQueue(filtered)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("MusicPlayer")
                    .font(.system(size: 22, weight: .semibold))
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                QuietIconButton(system: "arrow.clockwise", help: "重新扫描") {
                    library.reload()
                }
                .disabled(library.isLoading)
                .opacity(library.isLoading ? 0.35 : 1)
                QuietIconButton(system: "folder", help: library.rootPath) {
                    library.chooseFolder()
                }
            }
            SearchBar(text: $query)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var countLabel: String {
        if library.isLoading { return "正在读取" }
        if library.rootMissing { return "目录不可用" }
        if !query.isEmpty { return "\(filtered.count) / \(library.tracks.count)" }
        return "\(library.tracks.count) 首"
    }

    @ViewBuilder
    private var songList: some View {
        if library.rootMissing {
            status(
                symbol: "externaldrive.badge.xmark",
                title: "找不到曲库",
                detail: "请先挂载极空间的「共享文件」。歌曲目录是 /Volumes/共享文件/音乐。"
            ) {
                Button("重新检查") { library.reload() }
                    .buttonStyle(.borderedProminent)
                Button("选择文件夹") { library.chooseFolder() }
            }
        } else if library.tracks.isEmpty && library.isLoading {
            ProgressView("正在读取曲库")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.tracks.isEmpty {
            status(symbol: "music.note", title: "这个文件夹里没有歌曲", detail: "支持 MP3、M4A、FLAC、WAV。")
        } else if filtered.isEmpty {
            status(symbol: "magnifyingglass", title: "没有匹配的歌曲", detail: "换个关键词试试。")
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.current?.id == track.id,
                            isPlaying: player.current?.id == track.id && player.isPlaying,
                            isSelected: selection == track.id
                        )
                        .id(track.id)
                        .onTapGesture(count: 2) {
                            selection = track.id
                            player.play(track, queue: filtered)
                        }
                        .onTapGesture {
                            selection = track.id
                        }
                        .contextMenu {
                            Button("播放") {
                                selection = track.id
                                player.play(track, queue: filtered)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .onAppear {
                guard let id = player.current?.id else { return }
                if selection == nil { selection = id }
                proxy.scrollTo(id, anchor: .center)
            }
            }
        }
    }

    private func status(symbol: String, title: String, detail: String) -> some View {
        status(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }

    private func status<Actions: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) { actions() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playerBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "未在播放")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(player.playbackError == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                .frame(maxWidth: 280, alignment: .leading)
                Spacer(minLength: 16)
                transport
            }
            HStack(spacing: 10) {
                Text(formatTime(dragTime ?? player.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { dragTime ?? player.currentTime },
                        set: { dragTime = $0 }
                    ),
                    in: 0...max(player.duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            player.beginScrub()
                            dragTime = player.currentTime
                        } else if let dragTime {
                            player.endScrub(at: dragTime)
                            self.dragTime = nil
                        }
                    }
                )
                .tint(Color.primary.opacity(0.8))
                .controlSize(.small)
                .focusEffectDisabled()
                .disabled(player.current == nil || player.duration <= 0)
                Text(formatTime(player.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Image(systemName: volumeSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(
                    value: Binding(
                        get: { player.volume },
                        set: { player.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(Color.primary.opacity(0.8))
                .controlSize(.small)
                .focusEffectDisabled()
                .frame(width: 84)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            TransportButton(system: "backward.fill", size: 12) { player.previous() }
                .disabled(player.current == nil)
            Button {
                player.togglePlayback(queue: filtered)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .offset(x: player.isPlaying ? 0 : 1)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary))
            }
            .buttonStyle(.plain)
            .disabled(filtered.isEmpty && player.current == nil)
            .opacity(filtered.isEmpty && player.current == nil ? 0.35 : 1)
            TransportButton(system: "forward.fill", size: 12) { player.next() }
                .disabled(player.current == nil)
            Button { player.cycleMode() } label: {
                Image(systemName: player.mode.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.mode.label)
            .padding(.leading, 4)
        }
    }

    private var subtitle: String {
        if let playbackError = player.playbackError { return playbackError }
        guard let current = player.current else { return "双击一首歌开始播放" }
        if current.artist.isEmpty { return current.album.isEmpty ? " " : current.album }
        if current.album.isEmpty { return current.artist }
        return "\(current.artist) · \(current.album)"
    }

    private var volumeSymbol: String {
        if player.volume <= 0.001 { return "speaker.slash.fill" }
        if player.volume < 0.4 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if isCurrent { return Color.accentColor.opacity(0.12) }
        if isSelected || hovering { return Color.primary.opacity(hovering && !isSelected ? 0.045 : 0.07) }
        return .clear
    }
}

private struct QuietIconButton: View {
    let system: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct TransportButton: View {
    let system: String
    let size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
    }
}
