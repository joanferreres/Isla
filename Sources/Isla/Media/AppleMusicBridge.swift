import AppKit
import IslandCore
struct MusicReply:Codable,Sendable { var snapshot:MediaSnapshot?;var artwork:Data?;var artworkTrackID:String?;var error:String?;var errorCode:Int?
 func artwork(for trackID:String) -> Data? { artworkTrackID == trackID ? artwork : nil }
}
@MainActor enum MusicHelper {
 static func run(_ operation:String) {
 var reply=MusicReply()
 if !NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").isEmpty {
 let source:String
 switch operation {
 case "read": source="""
 tell application "Music"
 if player state is stopped then return {}
 set t to current track
 return {persistent ID of t, name of t, artist of t, (player state is playing), player position, duration of t}
 end tell
 """
 case "artwork": source="""
 tell application "Music"
 try
 return {persistent ID of current track, raw data of artwork 1 of current track}
 on error
 return ""
 end try
 end tell
 """
 case "previous": source="tell application \"Music\" to previous track"
 case "next": source="tell application \"Music\" to next track"
 case "playPause": source="tell application \"Music\" to playpause"
 default: source="return {}"
 }
 var error:NSDictionary?
 let descriptor=NSAppleScript(source:source)?.executeAndReturnError(&error)
 if let error { reply.errorCode=error[NSAppleScript.errorNumber] as? Int;reply.error=reply.errorCode == -1743 ? "Permite a Isla controlar Apple Music en Privacidad > Automatización." : "Apple Music no respondió a la consulta." }
 else if operation == "read",let d=descriptor,d.numberOfItems == 6 {
 reply.snapshot=MediaSnapshot(trackID:d.atIndex(1)?.stringValue ?? "",title:d.atIndex(2)?.stringValue ?? "",artist:d.atIndex(3)?.stringValue ?? "",playing:d.atIndex(4)?.booleanValue ?? false,position:Double(d.atIndex(5)?.stringValue ?? "") ?? d.atIndex(5)?.doubleValue ?? 0,duration:Double(d.atIndex(6)?.stringValue ?? "") ?? d.atIndex(6)?.doubleValue ?? 0)
 } else if operation == "artwork",let descriptor,descriptor.numberOfItems == 2,let data=descriptor.atIndex(2)?.data,NSImage(data:data) != nil { reply.artwork=data;reply.artworkTrackID=descriptor.atIndex(1)?.stringValue }
 }
 if let data=try? JSONEncoder().encode(reply) { FileHandle.standardOutput.write(data) }
 }
}
protocol AppleMusicReading:Sendable {
 func isRunning() async -> Bool
 func read() async throws -> MediaSnapshot?
 func artwork(trackID:String) async throws -> Data?
 func send(_ command:MediaCommand) async throws
}
struct MusicFailure:LocalizedError { var message:String;var code:Int?=nil;var errorDescription:String? { message } }
actor AppleMusicBridge:AppleMusicReading {
 private var systemReply:MusicReply?
 private var retrySystemAfter=Date.distantPast

 func isRunning() async -> Bool { await MainActor.run { !NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").isEmpty } }
 func query(_ operation:String) throws -> MusicReply {
 let url=URL(fileURLWithPath:CommandLine.arguments[0])
 let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 FileManager.default.createFile(atPath:file.path,contents:nil)
 defer { try? FileManager.default.removeItem(at:file) }
 let handle=try FileHandle(forWritingTo:file);defer { try? handle.close() }
 let process=Process();process.executableURL=url;process.arguments=["--music-helper",operation];process.standardOutput=handle;process.standardError=FileHandle.nullDevice
 try process.run()
 let deadline=Date().addingTimeInterval(10)
 while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.02) }
 if process.isRunning { process.terminate(); throw MusicFailure(message:"Apple Music tardó demasiado en responder.") }
 let reply=try JSONDecoder().decode(MusicReply.self,from:Data(contentsOf:file))
 if let error=reply.error { throw MusicFailure(message:error,code:reply.errorCode) };return reply
 }
 func read() async throws -> MediaSnapshot? {
 if Date() >= retrySystemAfter {
 do {
 let reply=try SystemMediaArtwork().read()
 systemReply=reply
 if let snapshot=reply?.snapshot { return snapshot }
 } catch { retrySystemAfter=Date().addingTimeInterval(60);systemReply=nil }
 }
 return try query("read").snapshot
 }
 func artwork(trackID:String) async throws -> Data? {
 if trackID.hasPrefix("mediaremote:") { return systemReply?.artwork(for:trackID) }
 return try query("artwork").artwork(for:trackID)
 }
 func send(_ command:MediaCommand) async throws { _=try query(command.rawValue) }
}
