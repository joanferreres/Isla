import SwiftUI
import IslandCore

struct RecordPlaylistPicker: View {
    let track: MediaSnapshot
    var island: IslandModel?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var service = MusicPlaylistService()
    @State private var isOpen = false
    @State private var holdsIsland = false
    @State private var playlists: [MusicPlaylist]?
    @State private var saving: String?
    @State private var saved: Set<String> = []
    @State private var status: String?
    @State private var error: String?

    var body: some View {
        styledButton
            .accessibilityLabel("Añadir a playlist")
            .help(error ?? status ?? "Añadir la canción a una playlist de Música")
            .onChange(of: isOpen) { _, open in holdIsland(open) }
            .onDisappear { holdIsland(false) }
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Añadir a playlist").font(.headline)
                    Text(track.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let playlists, !playlists.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(playlists) { playlist in
                                    Button {
                                        save(playlist, in: playlists)
                                    } label: {
                                        HStack {
                                            Text(playlist.name).lineLimit(1)
                                            Spacer()
                                            if saving == playlist.id {
                                                ProgressView().controlSize(.small)
                                            } else if saved.contains(playlist.id) {
                                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 6)
                                        .frame(minHeight: 36)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(saving != nil || saved.contains(playlist.id))
                                }
                            }
                        }
                        .frame(height: min(250, CGFloat(playlists.count) * 36))
                    } else if playlists?.isEmpty == true {
                        Text("No hay playlists editables en Música.").font(.callout).foregroundStyle(.secondary)
                    } else if error == nil {
                        ProgressView("Cargando playlists…").controlSize(.small)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    } else if let status {
                        Label(status, systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(width: 274, alignment: .leading)
                .task { await load() }
            }
    }

    @ViewBuilder private var styledButton: some View {
        let button = Button {
            isOpen.toggle()
            holdIsland(isOpen)
        } label: {
            HStack(spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().frame(width: 11, height: 2)
                    Capsule().frame(width: 11, height: 2)
                    Capsule().frame(width: 7, height: 2)
                }
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
                .frame(minWidth: 24, minHeight: island == nil ? 32 : 28)
        }
        .buttonBorderShape(.capsule)
        if island != nil { button.buttonStyle(.plain) }
        else if #available(macOS 26.0, *), !reduceTransparency { button.buttonStyle(.glass) }
        else { button.buttonStyle(.bordered) }
    }

    private func holdIsland(_ hold: Bool) {
        guard let island, holdsIsland != hold else { return }
        holdsIsland = hold
        if hold { island.beginInteraction() }
        else { island.endInteraction() }
    }

    private func load() async {
        if playlists == nil { error = nil }
        do {
            let result = try await service.playlists()
            if !Task.isCancelled { playlists = result }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func save(_ playlist: MusicPlaylist, in playlists: [MusicPlaylist]) {
        saving = playlist.id
        error = nil
        status = nil
        let normalized = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unambiguous = playlists.count {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        } == 1
        Task {
            defer { saving = nil }
            do {
                let added = try await service.add(track, to: playlist, unambiguousName: unambiguous)
                saved.insert(playlist.id)
                status = added ? "Añadida a \(playlist.name)" : "Ya estaba en \(playlist.name)"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
