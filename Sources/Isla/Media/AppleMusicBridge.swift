import AppKit
import IslandCore
struct MusicNeighbors:Codable,Sendable,Equatable {
 var nextTrackID:String?
 var nextArtwork:Data?
 var previousTrackID:String?
 var previousArtwork:Data?
}
struct MusicCassetteTrack:Codable,Identifiable,Sendable,Equatable {
 var id:String
 var title:String
 var artist:String
}
struct MusicPlaylistCatalog:Codable,Sendable,Equatable {
 var name:String
 var tracks:[MusicCassetteTrack]
}
struct MusicReply:Codable,Sendable { var snapshot:MediaSnapshot?;var artwork:Data?;var artworkTrackID:String?;var error:String?;var errorCode:Int?;var volume:Int?
 var playlists:[MusicPlaylist]?;var playlistContainsTrack:Bool?
 var neighbors:MusicNeighbors?
 var playlistCatalog:MusicPlaylistCatalog?
 func artwork(for trackID:String) -> Data? { artworkTrackID == trackID ? artwork : nil }
}
@MainActor enum MusicHelper {
 static func run(_ operation:String,argument:String?=nil) {
 var reply=MusicReply()
 if let playlistReply=MusicPlaylistScripts.run(operation,argument:argument) {
 if let data=try? JSONEncoder().encode(playlistReply) { FileHandle.standardOutput.write(data) }
 return
 }
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
 case "neighbors": source="""
 tell application "Music"
 if player state is stopped then return {}
 try
  set cur to current track
  set curID to persistent ID of cur
 on error
  return {}
 end try
 set pl to missing value
 try
  set pl to current playlist
 on error
  try
   set cont to container of cur
   set contClass to (class of cont) as text
   if contClass is in {"playlist", "user playlist", "library playlist", "folder playlist", "radio tuner playlist"} then
    set pl to cont
   end if
  end try
 end try
 if pl is missing value then return {}
 try
  set total to count of tracks of pl
  if total < 2 then return {}
  set idx to 0
  repeat with i from 1 to total
   try
    if persistent ID of track i of pl is equal to curID then
     set idx to i
     exit repeat
    end if
   end try
  end repeat
  if idx is 0 then return {}
  set nextI to idx + 1
  if nextI > total then set nextI to 1
  set prevI to idx - 1
  if prevI < 1 then set prevI to total
  set nt to track nextI of pl
  set pt to track prevI of pl
  set nextArt to ""
  set prevArt to ""
  try
   set nextArt to raw data of artwork 1 of nt
  end try
  try
   set prevArt to raw data of artwork 1 of pt
  end try
  return {persistent ID of nt, nextArt, persistent ID of pt, prevArt}
 on error
  return {}
 end try
 end tell
 """
 case "volume":
 if let argument, let volume = Int(argument), (0...100).contains(volume) {
 source = """
 tell application "Music"
 set sound volume to \(volume)
 return sound volume
 end tell
 """
 } else { source = "tell application \"Music\" to get sound volume" }
 case "previous": source="tell application \"Music\" to previous track"
 case "next": source="tell application \"Music\" to next track"
 case "playPause": source="tell application \"Music\" to playpause"
 case "pause": source="tell application \"Music\" to pause"
 case "playlistTracks": source="""
 tell application "Music"
 set pl to missing value
 try
  set pl to current playlist
 on error
  try
   set cont to container of current track
   set contClass to (class of cont) as text
   if contClass is in {"playlist", "user playlist", "library playlist", "folder playlist", "radio tuner playlist"} then set pl to cont
  end try
 end try
 if pl is missing value then return {}
 set total to count of tracks of pl
 if total is 0 then return {name of pl}
 set limit to total
 if limit > 40 then set limit to 40
 set rows to {name of pl}
 repeat with i from 1 to limit
  set t to track i of pl
  set end of rows to persistent ID of t
  set end of rows to name of t
  try
   set end of rows to artist of t
  on error
   set end of rows to ""
  end try
 end repeat
 return rows
 end tell
 """
 case "upcomingTracks": source="""
 tell application "Music"
 if player state is stopped then return {}
 set rows to {"Próximas"}
 set seen to {}
 try
  set cur to current track
  set cid to persistent ID of cur
  set end of rows to cid
  set end of rows to name of cur
  try
   set end of rows to artist of cur
  on error
   set end of rows to ""
  end try
  set end of seen to cid
 on error
  return {}
 end try
 set pl to missing value
 try
  set pl to current playlist
 on error
  try
   set cont to container of current track
   set contClass to (class of cont) as text
   if contClass is in {"playlist", "user playlist", "library playlist", "folder playlist", "radio tuner playlist"} then set pl to cont
  end try
 end try
 if pl is not missing value then
  try
   set total to count of tracks of pl
   set idx to 0
   repeat with i from 1 to total
    try
     if persistent ID of track i of pl is equal to cid then
      set idx to i
      exit repeat
     end if
    end try
   end repeat
   if idx is not 0 and total > 1 then
    repeat with offset from 1 to 12
     set j to ((idx + offset - 1) mod total) + 1
     set t to track j of pl
     set tid to persistent ID of t
     if tid is not in seen then
      set end of seen to tid
      set end of rows to tid
      set end of rows to name of t
      try
       set end of rows to artist of t
      on error
       set end of rows to ""
      end try
     end if
     if (count of seen) ≥ 12 then exit repeat
    end repeat
   end if
  end try
 end if
 set need to 6 - (count of seen)
 if need > 0 then
  try
   set lib to library playlist 1
   set libCount to count of tracks of lib
   if libCount > 0 then
    repeat with n from 1 to (need * 4)
     set t to some track of lib
     set tid to persistent ID of t
     if tid is not in seen then
      set end of seen to tid
      set end of rows to tid
      set end of rows to name of t
      try
       set end of rows to artist of t
      on error
       set end of rows to ""
      end try
      set need to need - 1
      if need ≤ 0 then exit repeat
     end if
    end repeat
   end if
  end try
 end if
 return rows
 end tell
 """
 case "playTrack":
 if let argument, argument.utf8.count <= 32, argument.utf8.allSatisfy({
  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
 }) {
 source="""
 tell application "Music"
 set targetID to "\(argument)"
 try
  set pl to current playlist
  set t to first track of pl whose persistent ID is targetID
  play t
  return targetID
 on error
  try
   set t to first track whose persistent ID is targetID
   play t
   return targetID
  on error
   return {}
  end try
 end try
 end tell
 """
 } else { source="return {}" }
 case "trackArtwork":
 if let argument, argument.utf8.count <= 32, argument.utf8.allSatisfy({
  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
 }) {
 source="""
 tell application "Music"
 try
  set t to first track whose persistent ID is "\(argument)"
  return {persistent ID of t, raw data of artwork 1 of t}
 on error
  try
   set pl to current playlist
   set t to first track of pl whose persistent ID is "\(argument)"
   return {persistent ID of t, raw data of artwork 1 of t}
  on error
   return ""
  end try
 end try
 end tell
 """
 } else { source="return {}" }
 case "cue":
 if let argument,let seconds=Double(argument),seconds.isFinite,seconds>=0 {
 let position=String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),seconds)
 source="""
 tell application "Music"
 set player position to \(position)
 if player state is not playing then play
 end tell
 """
 } else { source="return {}" }
 default: source="return {}"
 }
 var error:NSDictionary?
 let descriptor=NSAppleScript(source:source)?.executeAndReturnError(&error)
 if let error { reply.errorCode=error[NSAppleScript.errorNumber] as? Int;reply.error=reply.errorCode == -1743 ? "Permite a Isla controlar Apple Music en Privacidad > Automatización." : "Apple Music no respondió a la consulta." }
 else if operation == "volume", let descriptor, descriptor.descriptorType == typeSInt32 {
 reply.volume = Int(descriptor.int32Value)
 }
 else if operation == "read",let d=descriptor,d.numberOfItems == 6 {
 reply.snapshot=MediaSnapshot(trackID:d.atIndex(1)?.stringValue ?? "",title:d.atIndex(2)?.stringValue ?? "",artist:d.atIndex(3)?.stringValue ?? "",playing:d.atIndex(4)?.booleanValue ?? false,position:Double(d.atIndex(5)?.stringValue ?? "") ?? d.atIndex(5)?.doubleValue ?? 0,duration:Double(d.atIndex(6)?.stringValue ?? "") ?? d.atIndex(6)?.doubleValue ?? 0)
 } else if operation == "artwork",let descriptor,descriptor.numberOfItems == 2,let data=descriptor.atIndex(2)?.data,NSImage(data:data) != nil { reply.artwork=data;reply.artworkTrackID=descriptor.atIndex(1)?.stringValue }
 else if operation == "neighbors", let descriptor, descriptor.numberOfItems == 4 {
  var neighbors = MusicNeighbors()
  neighbors.nextTrackID = descriptor.atIndex(1)?.stringValue
  if let data = descriptor.atIndex(2)?.data, NSImage(data: data) != nil { neighbors.nextArtwork = data }
  neighbors.previousTrackID = descriptor.atIndex(3)?.stringValue
  if let data = descriptor.atIndex(4)?.data, NSImage(data: data) != nil { neighbors.previousArtwork = data }
  if neighbors.nextTrackID != nil || neighbors.previousTrackID != nil { reply.neighbors = neighbors }
 } else if operation == "playlistTracks" || operation == "upcomingTracks",
           let descriptor, descriptor.numberOfItems >= 1 {
  let name = descriptor.atIndex(1)?.stringValue ?? (operation == "upcomingTracks" ? "Próximas" : "Playlist")
  var tracks:[MusicCassetteTrack] = []
  var index = 2
  while index + 2 <= descriptor.numberOfItems {
   let id = descriptor.atIndex(index)?.stringValue ?? ""
   let title = descriptor.atIndex(index + 1)?.stringValue ?? ""
   let artist = descriptor.atIndex(index + 2)?.stringValue ?? ""
   if !id.isEmpty, !title.isEmpty {
    tracks.append(MusicCassetteTrack(id: id, title: title, artist: artist))
   }
   index += 3
  }
  reply.playlistCatalog = MusicPlaylistCatalog(name: name, tracks: tracks)
 } else if operation == "trackArtwork", let descriptor, descriptor.numberOfItems == 2,
           let data = descriptor.atIndex(2)?.data, NSImage(data: data) != nil {
  reply.artwork = data
  reply.artworkTrackID = descriptor.atIndex(1)?.stringValue
 } else if operation == "playTrack", let descriptor {
  if let id = descriptor.stringValue, !id.isEmpty {
   reply.artworkTrackID = id
  } else if descriptor.numberOfItems >= 1, let id = descriptor.atIndex(1)?.stringValue, !id.isEmpty {
   reply.artworkTrackID = id
  }
 }
 }
 if let data=try? JSONEncoder().encode(reply) { FileHandle.standardOutput.write(data) }
 }
}
protocol AppleMusicReading:Sendable {
 func isRunning() async -> Bool
 func read() async throws -> MediaSnapshot?
 func artwork(trackID:String) async throws -> Data?
 func neighbors() async throws -> MusicNeighbors?
 func send(_ command:MediaCommand) async throws
 func volume(_ value: Int?) async throws -> Int
}
struct MusicFailure:LocalizedError { var message:String;var code:Int?=nil;var errorDescription:String? { message } }
actor AppleMusicBridge:AppleMusicReading {
 private var systemReply:MusicReply?
 private var retrySystemAfter=Date.distantPast

 func isRunning() async -> Bool { await MainActor.run { !NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").isEmpty } }
 func query(_ operation:String,argument:String?=nil) throws -> MusicReply {
 let url=URL(fileURLWithPath:CommandLine.arguments[0])
 let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 FileManager.default.createFile(atPath:file.path,contents:nil)
 defer { try? FileManager.default.removeItem(at:file) }
 let handle=try FileHandle(forWritingTo:file);defer { try? handle.close() }
 let process=Process();process.executableURL=url;process.arguments=["--music-helper",operation]+(argument.map{[$0]} ?? []);process.standardOutput=handle;process.standardError=FileHandle.nullDevice
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
 func neighbors() async throws -> MusicNeighbors? {
 // Playlist-relative peek via AppleScript. Radio / Autoplay / some cloud queues return nil.
 try query("neighbors").neighbors
 }
 func volume(_ value: Int?) async throws -> Int {
 guard let volume = try query("volume", argument: value.map(String.init)).volume else {
 throw MusicFailure(message: "Abre Música para controlar su volumen.")
 }
 return volume
 }
 func send(_ command:MediaCommand) async throws {
 switch command {
 case .previous: _=try query("previous")
 case .playPause: _=try query("playPause")
 case .pause: _=try query("pause")
 case .next: _=try query("next")
 case .cue(let seconds): _=try query("cue",argument:String(seconds))
 }
 }
}
