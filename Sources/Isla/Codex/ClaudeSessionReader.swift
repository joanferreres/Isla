import Foundation
import IslandCore

/// Tails Claude Code's session logs and reports finished turns. History is never replayed:
/// files already present when watching starts are read only from their current end.
actor ClaudeSessionReader {
 private struct Cursor { var offset:UInt64;var buffer=JSONLineBuffer() }
 private var cursors:[URL:Cursor]=[:]
 private var seen=Set<String>()
 private var discovered=Date.distantPast
 private var files:[URL]=[]
 private var started:Date?
 private let root:URL
 init(root:URL?=nil) {
 let home=FileManager.default.homeDirectoryForCurrentUser
 self.root=root ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map{URL(fileURLWithPath:$0)}.map{$0.appendingPathComponent("projects")} ?? home.appendingPathComponent(".claude/projects")
 }
 func reset() { cursors=[:];seen=[];files=[];discovered = .distantPast;started=nil }
 private func discover() {
 guard Date().timeIntervalSince(discovered) > 5 else { return };discovered=Date()
 var found:[URL]=[]
 if let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.contentModificationDateKey],options:[.skipsHiddenFiles]) {
 for case let url as URL in enumerator where url.pathExtension == "jsonl" {
 if let date=try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate,date > Date().addingTimeInterval(-86400) || cursors[url] != nil { found.append(url) }
 }
 }
 files=found
 cursors=cursors.filter{ files.contains($0.key) }
 }
 func scan() -> [TurnCompletion] {
 let isFirst=started == nil;if isFirst { started=Date() };discover()
 var result:[TurnCompletion]=[]
 for url in files {
 guard let size=(try? FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.uint64Value else { continue }
 guard var cursor=cursors[url] else {
 // Unknown file: skip its history, only follow what is written from now on.
 cursors[url]=Cursor(offset:size);continue
 }
 if size < cursor.offset { cursors[url]=Cursor(offset:size);continue }
 guard size > cursor.offset,let handle=try? FileHandle(forReadingFrom:url) else { continue }
 defer { try? handle.close() }
 try? handle.seek(toOffset:cursor.offset)
 guard let data=try? handle.read(upToCount:Int(min(size-cursor.offset,4*1024*1024))) else { continue }
 cursor.offset += UInt64(data.count)
 for line in cursor.buffer.append(data) {
 if let completion=ClaudeTurnEvent.completion(line:line),seen.insert(completion.sessionID+":"+completion.turnID).inserted { result.append(completion) }
 }
 cursors[url]=cursor
 }
 return result
 }
}
