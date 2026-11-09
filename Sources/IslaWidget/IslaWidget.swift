import SwiftUI
import WidgetKit
import AppKit
import Darwin

struct RecordEntry: TimelineEntry {
    var date = Date()
    var title: String?
    var artist: String?
    var artwork: Data?
    var playing = false
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(title: "Tocadiscos", artist: "Apple Music", playing: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(900))))
    }

    private func current() -> RecordEntry {
        guard let user = getpwuid(getuid()) else { return RecordEntry() }
        let url = URL(fileURLWithPath: String(cString: user.pointee.pw_dir))
            .appendingPathComponent("Library/Application Support/Isla/Widget/record.json")
        guard let data = try? Data(contentsOf: url),
              let track = try? JSONDecoder().decode(WidgetTrack.self, from: data) else { return RecordEntry() }
        return RecordEntry(title: track.title, artist: track.artist, artwork: track.artwork, playing: track.playing ?? false)
    }

    private struct WidgetTrack: Decodable {
        let title: String
        let artist: String
        let artwork: Data?
        let playing: Bool?
    }
}

struct RecordWidgetView: View {
    let entry: RecordEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    disc.frame(width: 62, height: 62)
                    track
                }
            } else {
                HStack(spacing: 16) {
                    disc.frame(width: 92, height: 92)
                    track
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(red: 0.07, green: 0.08, blue: 0.11) }
        .environment(\.colorScheme, .dark)
        .widgetURL(URL(string: "isla://tocadiscos"))
    }

    private var disc: some View {
        GeometryReader { geometry in
            vinyl
                .frame(width: geometry.size.width * 0.84, height: geometry.size.height * 0.84)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay { tonearm }
        }
        .accessibilityHidden(true)
    }

    private var tonearm: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width * 0.87, y: size.height * 0.19)
            let elbow = CGPoint(x: size.width * (entry.playing ? 0.77 : 0.95), y: size.height * 0.56)
            let needle = CGPoint(x: size.width * (entry.playing ? 0.65 : 0.94), y: size.height * 0.70)
            let arm = Path {
                $0.move(to: pivot)
                $0.addLine(to: elbow)
                $0.addLine(to: needle)
            }
            context.stroke(arm, with: .color(.black), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (point, diameter) in [(pivot, size.width * 0.12), (needle, size.width * 0.07)] {
                let housing = Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter))
                context.fill(housing, with: .color(.black))
                context.stroke(housing, with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        }
    }

    private var vinyl: some View {
        ZStack {
            Circle().fill(.black)
            ForEach(0..<6) { ring in
                Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1).padding(CGFloat(ring) * 3 + 2)
            }
            GeometryReader { geometry in
                Group {
                    if let data = entry.artwork, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Circle().fill(.blue.opacity(0.55)).overlay(Image(systemName: "music.note").font(.caption))
                    }
                }
                .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.48)
                .clipShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var track: some View {
        VStack(spacing: 3) {
            Text(entry.title ?? "Tocadiscos").font(.headline).lineLimit(1)
            Text(entry.artist ?? "Abrir Isla").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

@main struct IslaRecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IslaRecord", provider: RecordProvider()) { entry in
            RecordWidgetView(entry: entry)
        }
        .configurationDisplayName("Tocadiscos")
        .description("Muestra la última canción que Isla ha detectado y abre el tocadiscos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
