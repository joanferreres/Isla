import Foundation
import IslandCore

/// Antigravity keeps each conversation in `~/.gemini/antigravity/conversations/<id>.pb`, which is encrypted/binary.
/// We can't read turns, but a conversation file is rewritten while the agent works and stops changing when it
/// finishes. A conversation that was being written and then stays quiet is reported as a finished turn.
actor AntigravitySessionReader {
    private struct State {
        var modified: Date
        var size: UInt64
        var writes = 0
        var firstWrite: Date?
        var lastWrite: Date?
    }
    /// Quiet time after the last write before the turn counts as finished.
    static let quietPeriod: TimeInterval = 8
    private var states: [String: State] = [:]
    private var started = false
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/conversations")
    }

    func reset() { states = [:]; started = false }

    func scan(now: Date = Date()) -> [TurnCompletion] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let first = !started
        started = true
        var finished: [TurnCompletion] = []
        var present = Set<String>()
        for url in urls where url.pathExtension == "pb" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            let size = UInt64(values.fileSize ?? 0)
            present.insert(id)
            guard var state = states[id] else {
                // History is never replayed: files already there only seed the baseline.
                states[id] = State(modified: modified, size: size)
                if !first, now.timeIntervalSince(modified) < Self.quietPeriod {
                    states[id]?.writes = 1; states[id]?.firstWrite = modified; states[id]?.lastWrite = modified
                }
                continue
            }
            if modified != state.modified || size != state.size {
                state.modified = modified
                state.size = size
                state.writes += 1
                state.firstWrite = state.firstWrite ?? now
                state.lastWrite = now
            } else if let last = state.lastWrite, now.timeIntervalSince(last) >= Self.quietPeriod {
                // Several writes = the agent actually worked; a single touch is not a finished turn.
                if state.writes >= 2 {
                    finished.append(TurnCompletion(sessionID: id, turnID: "\(id)-\(Int(last.timeIntervalSince1970))", timestamp: now, source: .antigravity))
                }
                state.writes = 0; state.firstWrite = nil; state.lastWrite = nil
            }
            states[id] = state
        }
        states = states.filter { present.contains($0.key) }
        return finished
    }
}
