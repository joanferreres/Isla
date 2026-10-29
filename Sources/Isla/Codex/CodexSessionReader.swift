import Foundation
import IslandCore
struct SessionScan:Sendable { var seed:[CodexEvent];var events:[CodexEvent];var found:Int }
actor CodexSessionReader {
 struct Cursor { var id:String;var offset:UInt64;var buffer=JSONLineBuffer();var inode:UInt64 }
 var cursors:[URL:Cursor]=[:]
 var excluded:[URL:(size:UInt64,inode:UInt64)]=[:]
 var files:[URL]=[]
 var discovered=Date.distantPast
 var initialized=false
 let roots:[URL]
 let discoveryInterval:TimeInterval
 var baseline:Date?
 init(roots:[URL]?=nil,discoveryInterval:TimeInterval=5) {
 self.discoveryInterval=discoveryInterval
 let home=FileManager.default.homeDirectoryForCurrentUser
 let defaultRoot=ProcessInfo.processInfo.environment["CODEX_HOME"].map{URL(fileURLWithPath:$0)} ?? home.appendingPathComponent(".codex")
 self.roots=roots ?? [defaultRoot]
 }
 func reset() { excluded=[:];cursors=[:];files=[];discovered = .distantPast;initialized=false;baseline=nil }
 func discover() {
 guard Date().timeIntervalSince(discovered)>discoveryInterval else { return };discovered=Date()
 var candidates:[(URL,Date)]=[]
 for root in roots {
 let sessions=root.appendingPathComponent("sessions")
 // A resumed chat keeps its original dated folder. Discover by modification,
 // across the whole tree; scan() avoids opening files whose size is unchanged.
 if let enumerator=FileManager.default.enumerator(at:sessions,includingPropertiesForKeys:[.contentModificationDateKey],options:[.skipsHiddenFiles]) {
 for case let url as URL in enumerator where url.pathExtension == "jsonl" {
 if let date=try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate,
 date>Date().addingTimeInterval(-86400*2) || cursors[url] != nil { candidates.append((url,date)) }
 }
 }
 }

 files=Array(Set(candidates.sorted{$0.1 > $1.1}.prefix(128).map(\.0)).union(candidates.map(\.0).filter{cursors[$0] != nil}))
 cursors=cursors.filter{files.contains($0.key)};excluded=excluded.filter{files.contains($0.key)}
 }
 func scan() -> SessionScan {
 if baseline == nil { baseline=Date() };discover();var result=SessionScan(seed:[],events:[],found:0)
 for url in files {
 guard let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),let size=(attrs[.size] as? NSNumber)?.uint64Value else { continue }
 let existingInode=(attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
 if let skipped=excluded[url],skipped.size==size,skipped.inode==existingInode { continue }
 if let cursor=cursors[url],cursor.offset==size,cursor.inode==existingInode { result.found += 1;continue }
 guard let handle=try? FileHandle(forReadingFrom:url) else { continue };defer { try? handle.close() }
 let modified=attrs[.modificationDate] as? Date ?? .distantPast
 let inode=(attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
 if cursors[url] == nil || cursors[url]!.offset > size || cursors[url]!.inode != inode {
 try? handle.seek(toOffset:0)
 guard let first=try? handle.read(upToCount:256*1024),let end=first.firstIndex(of:10) else { continue }
 guard let id=CodexSessionMetadata.rootID(line:Data(first[..<end])) else { excluded[url]=(size,inode);continue }
 result.found += 1
 let start=size > 1024*1024 ? size-1024*1024 : 0
 try? handle.seek(toOffset:start)
 guard var data=try? handle.read(upToCount:Int(size-start)) else { continue }
 if start > 0,let newline=data.firstIndex(of:10) { data.removeSubrange(...newline) }
 var cursor=Cursor(id:id,offset:size,inode:inode)
 let parsed=cursor.buffer.append(data).compactMap{try? CodexEvent.decode(line:$0,session:id)}
 // Seed newly discovered files too: never replay a historical completion.
 if !initialized || modified < (baseline ?? Date()) {
 result.seed.append(contentsOf:parsed)
 } else {
 // Only activity occurring after activation can notify. A historical file copied into sessions is seeded.
 var replayBuffer=JSONLineBuffer()
 for line in replayBuffer.append(data) {
 guard let event=try? CodexEvent.decode(line:line,session:id) else { continue }
 let object=try? JSONSerialization.jsonObject(with:line) as? [String:Any]
 let timestamp=(object?["timestamp"] as? String).flatMap{ ISO8601DateFormatter().date(from:$0) }
 if let timestamp,timestamp < (baseline ?? Date()) { result.seed.append(event) } else { result.events.append(event) }
 }
 }
 cursors[url]=cursor
 continue
 }
 guard var cursor=cursors[url] else { continue };result.found += 1
 try? handle.seek(toOffset:cursor.offset)
 guard let data=try? handle.read(upToCount:1024*1024) else { continue }
 cursor.offset += UInt64(data.count)
 result.events.append(contentsOf:cursor.buffer.append(data).compactMap{try? CodexEvent.decode(line:$0,session:cursor.id)})
 cursors[url]=cursor
 }
 initialized=true;return result
 }
}
