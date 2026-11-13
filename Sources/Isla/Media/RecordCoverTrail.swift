import AppKit
import IslandCore

/// In-memory bidirectional cover trail for dual-disc previews.
/// Previous/next images are decoded up front so a swipe never waits on NSImage(data:).
@MainActor struct RecordCoverTrail {
    struct Entry: Equatable {
        var keys: Set<String>
        var image: NSImage?
    }

    private(set) var entries: [Entry] = []
    private(set) var index = 0
    private(set) var previousCover: NSImage?
    private(set) var nextCover: NSImage?

    static func keys(trackID: String, title: String, artist: String) -> Set<String> {
        var keys: Set<String> = [trackID]
        let fingerprint = "fp:\(title)\u{001F}\(artist)"
        keys.insert(fingerprint)
        if trackID.hasPrefix("mediaremote:") { keys.insert(trackID) }
        return keys
    }

    mutating func reset() {
        entries = []
        index = 0
        previousCover = nil
        nextCover = nil
    }

    /// Record the landed track and keep a forward/back stack of covers already seen.
    /// `navigation` bridges MediaRemote vs AppleScript ID schemes after a skip.
    mutating func land(keys: Set<String>, image: NSImage?, navigation: RecordSwipe? = nil) {
        guard !keys.isEmpty else { return }
        if entries.isEmpty {
            entries = [Entry(keys: keys, image: image)]
            index = 0
            publish()
            return
        }
        if entries.indices.contains(index), !entries[index].keys.isDisjoint(with: keys) {
            entries[index].keys.formUnion(keys)
            if image != nil { entries[index].image = image }
        } else if index + 1 < entries.count, !entries[index + 1].keys.isDisjoint(with: keys) {
            index += 1
            entries[index].keys.formUnion(keys)
            if image != nil { entries[index].image = image }
        } else if index > 0, !entries[index - 1].keys.isDisjoint(with: keys) {
            index -= 1
            entries[index].keys.formUnion(keys)
            if image != nil { entries[index].image = image }
        } else if navigation == .next {
            if index + 1 < entries.count {
                index += 1
            } else {
                entries.append(Entry(keys: [], image: nil))
                index = entries.count - 1
            }
            entries[index].keys.formUnion(keys)
            if image != nil { entries[index].image = image }
        } else if navigation == .previous {
            if index > 0 {
                index -= 1
            } else {
                entries.insert(Entry(keys: [], image: nil), at: 0)
                index = 0
            }
            entries[index].keys.formUnion(keys)
            if image != nil { entries[index].image = image }
        } else {
            if index + 1 < entries.count {
                entries.removeSubrange((index + 1)...)
            }
            entries.append(Entry(keys: keys, image: image))
            index = entries.count - 1
        }
        trim()
        publish()
    }

    /// Attach playlist-neighbor artwork ahead of / behind the current index without moving it.
    mutating func applyNeighbors(previousKeys: Set<String>, previousImage: NSImage?,
                                 nextKeys: Set<String>, nextImage: NSImage?) {
        guard !entries.isEmpty else { return }
        if !previousKeys.isEmpty {
            install(keys: previousKeys, image: previousImage, at: index - 1, insertingBeforeCurrent: true)
        }
        if !nextKeys.isEmpty {
            install(keys: nextKeys, image: nextImage, at: index + 1, insertingBeforeCurrent: false)
        }
        trim()
        publish()
    }

    private mutating func install(keys: Set<String>, image: NSImage?, at rawIndex: Int, insertingBeforeCurrent: Bool) {
        if entries.indices.contains(rawIndex), !entries[rawIndex].keys.isDisjoint(with: keys) {
            entries[rawIndex].keys.formUnion(keys)
            if image != nil { entries[rawIndex].image = image }
            return
        }
        // Prefer writing into the adjacent empty slot; otherwise insert a dedicated neighbor entry.
        if rawIndex == index - 1 || (insertingBeforeCurrent && rawIndex < index) {
            if index == 0 {
                entries.insert(Entry(keys: keys, image: image), at: 0)
                index = 1
            } else if rawIndex >= 0, rawIndex < entries.count {
                entries[rawIndex] = Entry(keys: entries[rawIndex].keys.union(keys),
                                          image: image ?? entries[rawIndex].image)
            } else {
                entries.insert(Entry(keys: keys, image: image), at: 0)
                index += 1
            }
            return
        }
        if rawIndex == index + 1 {
            if index + 1 < entries.count {
                entries[index + 1].keys.formUnion(keys)
                if image != nil { entries[index + 1].image = image }
            } else {
                entries.append(Entry(keys: keys, image: image))
            }
        }
    }

    private mutating func trim() {
        let limit = 24
        guard entries.count > limit else { return }
        let overflow = entries.count - limit
        let drop = min(overflow, index)
        if drop > 0 {
            entries.removeFirst(drop)
            index -= drop
        }
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    private mutating func publish() {
        previousCover = index > 0 ? entries[index - 1].image : nil
        nextCover = index + 1 < entries.count ? entries[index + 1].image : nil
    }
}
