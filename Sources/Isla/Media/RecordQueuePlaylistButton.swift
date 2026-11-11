import SwiftUI

/// Picks a Music playlist and starts it as the active queue.
struct RecordQueuePlaylistButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var service = MusicPlaylistService()
    @State private var isOpen = false
    @State private var playlists: [MusicPlaylist]?
    @State private var error: String?
    @State private var starting: String?
    var onStarted: (() -> Void)?

    var body: some View {
        styledButton
            .accessibilityLabel("Cambiar playlist")
            .help(error ?? "Elige otra playlist y ponla a sonar")
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reproducir playlist").font(.headline)
                    if let playlists, !playlists.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(playlists) { playlist in
                                    Button {
                                        start(playlist)
                                    } label: {
                                        HStack {
                                            Text(playlist.name).lineLimit(1)
                                            Spacer()
                                            if starting == playlist.id {
                                                ProgressView().controlSize(.small)
                                            }
                                        }
                                        .padding(.horizontal, 6)
                                        .frame(minHeight: 34)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(starting != nil)
                                }
                            }
                        }
                        .frame(height: min(250, CGFloat(playlists.count) * 34))
                    } else if playlists?.isEmpty == true {
                        Text("No hay playlists editables en Música.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if error == nil {
                        ProgressView("Cargando playlists…").controlSize(.small)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(width: 274, alignment: .leading)
                .task { await load() }
            }
    }

    @ViewBuilder private var styledButton: some View {
        let button = Button { isOpen.toggle() } label: {
            Image(systemName: "music.note.list")
                .frame(minWidth: 24, minHeight: 32)
        }
        .buttonBorderShape(.capsule)
        if #available(macOS 26.0, *), !reduceTransparency {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func load() async {
        error = nil
        do {
            playlists = try await service.playlists()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start(_ playlist: MusicPlaylist) {
        starting = playlist.id
        error = nil
        Task {
            defer { starting = nil }
            do {
                try await service.playPlaylist(playlist)
                isOpen = false
                onStarted?()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
