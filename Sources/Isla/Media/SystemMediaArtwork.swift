import Foundation
import IslandCore
struct SystemMediaReply:Decodable {
 struct Payload:Decodable {
 var bundleIdentifier:String?
 var title:String?
 var artist:String?
 var album:String?
 var durationMicros:Double?
 var elapsedTimeMicros:Double?
 var timestampEpochMicros:Double?
 var playbackRate:Double?
 var isPlaying:Bool?
 var artworkDataBase64:String?
 }
 var payload:Payload?
 static func decode(_ data:Data,now:Date=Date()) throws -> MusicReply {
 let row=try JSONDecoder().decode(Self.self,from:data)
 guard let p=row.payload,p.bundleIdentifier == "com.apple.Music",let title=p.title,!title.isEmpty else { return MusicReply() }
 let duration=(p.durationMicros ?? 0)/1_000_000
 var position=(p.elapsedTimeMicros ?? 0)/1_000_000
 if p.isPlaying == true,let time=p.timestampEpochMicros {
 position += max(0,now.timeIntervalSince1970-time/1_000_000)*(p.playbackRate ?? 1)
 }
 let identity="mediaremote:"+[title,p.artist ?? "",p.album ?? ""].joined(separator:"\u{001F}")
 let snapshot=MediaSnapshot(trackID:identity,title:title,artist:p.artist ?? "",playing:p.isPlaying ?? false,position:max(0,min(position,duration)),duration:max(0,duration))
 return MusicReply(snapshot:snapshot,artwork:p.artworkDataBase64.flatMap{Data(base64Encoded:$0)},artworkTrackID:identity)
 }
}
/// Read-only local adapter. Isolated from the UI, bounded in time and output size.
/// No catalogue request or track metadata is sent over the network.
struct SystemMediaArtwork {
 func read() throws -> MusicReply? {
 guard let resources=Bundle.main.resourceURL else { return nil }
 let folder=resources.appendingPathComponent("MediaRemoteAdapter")
 let script=folder.appendingPathComponent("run.pl")
 let library=folder.appendingPathComponent("libIslaMediaRemoteAdapter.dylib")
 guard FileManager.default.fileExists(atPath:script.path),FileManager.default.fileExists(atPath:library.path) else { return nil }
 let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 FileManager.default.createFile(atPath:file.path,contents:nil)
 defer { try? FileManager.default.removeItem(at:file) }
 let handle=try FileHandle(forWritingTo:file);defer { try? handle.close() }
 let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/perl")
 process.arguments=[script.path,library.path,"get"]
 process.standardOutput=handle;process.standardError=FileHandle.nullDevice
 try process.run()
 let deadline=Date().addingTimeInterval(3)
 while process.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.01) }
 if process.isRunning { process.terminate();throw MusicFailure(message:"La lectura de carátula tardó demasiado.") }
 guard process.terminationStatus == 0 else { throw MusicFailure(message:"La lectura de carátula no está disponible.") }
 let attributes=try FileManager.default.attributesOfItem(atPath:file.path)
 guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 5_000_000 else { return nil }
 return try SystemMediaReply.decode(Data(contentsOf:file))
 }
}

private final class MediaStreamLines:@unchecked Sendable {
 private let lock=NSLock()
 private var buffer=Data()
 func append(_ data:Data) -> [Data] {
 lock.lock();defer { lock.unlock() }
 buffer.append(data)
 guard buffer.count<=5_000_000 else { buffer.removeAll();return [] }
 var result:[Data]=[]
 while let end=buffer.firstIndex(of:10) { result.append(Data(buffer[..<end]));buffer.removeSubrange(...end) }
 return result
 }
}
@MainActor final class SystemMediaStream {
 private var process:Process?
 private var output:Pipe?
 private var input:Pipe?
 var onReply:((MusicReply)->Void)?
 var onStopped:(()->Void)?
 var isRunning:Bool { process?.isRunning ?? false }
 func start() -> Bool {
 if isRunning { return true }
 guard let resources=Bundle.main.resourceURL else { return false }
 let folder=resources.appendingPathComponent("MediaRemoteAdapter")
 let script=folder.appendingPathComponent("run.pl")
 let library=folder.appendingPathComponent("libIslaMediaRemoteAdapter.dylib")
 guard FileManager.default.fileExists(atPath:script.path),FileManager.default.fileExists(atPath:library.path) else { return false }
 let proc=Process();let pipe=Pipe();let stdin=Pipe();let lines=MediaStreamLines()
 proc.executableURL=URL(fileURLWithPath:"/usr/bin/perl");proc.arguments=[script.path,library.path,"loop"]
 proc.standardOutput=pipe;proc.standardError=FileHandle.nullDevice;proc.standardInput=stdin
 pipe.fileHandleForReading.readabilityHandler={ [weak self,weak proc] handle in
 let bytes=handle.availableData
 guard !bytes.isEmpty else { handle.readabilityHandler=nil;return }
 for line in lines.append(bytes) {
 guard let reply=try? SystemMediaReply.decode(line) else { continue }
 Task { @MainActor [weak self,weak proc] in guard let self,let proc,self.process === proc else { return };self.onReply?(reply) }
 }
 }
 proc.terminationHandler={ [weak self] proc in Task { @MainActor [weak self] in
 guard let self,self.process === proc else { return };self.stop();self.onStopped?()
 } }
 do { process=proc;output=pipe;input=stdin;try proc.run();return true }
 catch { stop();return false }
 }
 func stop() {
 let proc=process;process=nil
 output?.fileHandleForReading.readabilityHandler=nil
 try? input?.fileHandleForWriting.close();try? output?.fileHandleForReading.close()
 output=nil;input=nil
 if proc?.isRunning == true { proc?.terminate() }
 }
}
