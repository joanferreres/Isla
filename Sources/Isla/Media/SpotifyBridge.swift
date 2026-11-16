import AppKit
import IslandCore

struct SpotifyReply:Codable,Sendable {
 var snapshot:MediaSnapshot?
 var artworkURL:String?
 var error:String?
 var errorCode:Int?
 var volume:Int?
 var shuffle:Bool?
}

@MainActor enum SpotifyHelper {
 static func run(_ operation:String,argument:String?=nil) {
  let reply=query(operation,argument:argument)
  if let data=try? JSONEncoder().encode(reply) { FileHandle.standardOutput.write(data) }
 }

 static func query(_ operation:String,argument:String?=nil) -> SpotifyReply {
  var reply=SpotifyReply()
  guard !NSRunningApplication.runningApplications(withBundleIdentifier:"com.spotify.client").isEmpty else {
   return reply
  }
  let source:String
  switch operation {
  case "read": source="""
  tell application "Spotify"
   if player state is stopped then return {}
   set t to current track
   set trackURL to spotify url of t
   return {trackURL, name of t, artist of t, (player state is playing), player position, (duration of t) / 1000, artwork url of t}
  end tell
  """
  case "volume":
   if let argument,let value=Int(argument),(0...100).contains(value) {
    source="tell application \"Spotify\" to set sound volume to \(value)\ntell application \"Spotify\" to get sound volume"
   } else { source="tell application \"Spotify\" to get sound volume" }
  case "previous": source="tell application \"Spotify\" to previous track"
  case "next": source="tell application \"Spotify\" to next track"
  case "playPause": source="tell application \"Spotify\" to playpause"
  case "pause": source="tell application \"Spotify\" to pause"
  case "cue":
   if let argument,let seconds=Double(argument),seconds.isFinite,seconds>=0 {
    let value=String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),seconds)
    source="tell application \"Spotify\" to set player position to \(value)\ntell application \"Spotify\" to play"
   } else { source="return {}" }
  case "shuffle":
   if let argument {
    source="tell application \"Spotify\" to set shuffling to \(argument == "1" ? "true" : "false")\ntell application \"Spotify\" to get shuffling"
   } else { source="tell application \"Spotify\" to get shuffling" }
  default: source="return {}"
  }
  var details:NSDictionary?
  let descriptor=NSAppleScript(source:source)?.executeAndReturnError(&details)
  if let details {
   reply.errorCode=details[NSAppleScript.errorNumber] as? Int
   reply.error=reply.errorCode == -1743
    ? "Permite a Isla controlar Spotify en Privacidad y seguridad → Automatización."
    : "Spotify no respondió a la consulta."
  } else if operation == "read",let descriptor,descriptor.numberOfItems >= 7 {
   let rawID=descriptor.atIndex(1)?.stringValue ?? ""
   let trackID=rawID.hasPrefix("spotify:") ? rawID : "spotify:"+rawID
   guard !rawID.isEmpty else { return reply }
   reply.snapshot=MediaSnapshot(
    trackID:trackID,
    title:descriptor.atIndex(2)?.stringValue ?? "",
    artist:descriptor.atIndex(3)?.stringValue ?? "",
    playing:descriptor.atIndex(4)?.booleanValue ?? false,
    position:descriptor.atIndex(5)?.doubleValue ?? 0,
    duration:descriptor.atIndex(6)?.doubleValue ?? 0,
    source:.spotify
   )
   reply.artworkURL=descriptor.atIndex(7)?.stringValue
  } else if operation == "volume",let descriptor {
   reply.volume=Int(descriptor.int32Value)
  } else if operation == "shuffle",let descriptor {
   reply.shuffle=descriptor.booleanValue
  }
  return reply
 }
}

actor SpotifyBridge:AppleMusicReading {
 private var artworkURLs:[String:URL]=[:]
 private var artworkCache:[String:Data]=[:]

 func isRunning() async -> Bool {
  await MainActor.run { !NSRunningApplication.runningApplications(withBundleIdentifier:"com.spotify.client").isEmpty }
 }

 private func query(_ operation:String,argument:String?=nil) async throws -> SpotifyReply {
  // Run the Apple event from Isla itself. A helper subprocess can wait forever behind
  // macOS Automation consent and never return the artwork URL to the visible app.
  let reply=await SpotifyHelper.query(operation,argument:argument)
  if let error=reply.error { throw MusicFailure(message:error,code:reply.errorCode) }
  return reply
 }

 func read() async throws -> MediaSnapshot? {
  let reply=try await query("read")
  if let id=reply.snapshot?.trackID,let raw=reply.artworkURL,let url=Self.artworkURL(raw) {
   artworkURLs[id]=url
  }
  return reply.snapshot
 }

 func cachedArtwork(trackID:String) async -> Data? { artworkCache[trackID] }
 func rememberCachedArtwork(_ data:Data,for trackID:String) async {
  guard !data.isEmpty,NSImage(data:data) != nil else { return }
  artworkCache[trackID]=data;trimArtworkCache()
 }
 func adoptSystemArtwork(for trackID:String) async {}
 func neighbors() async throws -> MusicNeighbors? { nil }

 func artwork(trackID:String) async throws -> Data? {
  if let cached=artworkCache[trackID] { return cached }
  guard let url=artworkURLs[trackID] else { return nil }
  let (data,response)=try await URLSession.shared.data(from:url)
  guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),data.count<=5_000_000,
        NSImage(data:data) != nil else { throw MusicFailure(message:"Spotify no entregó una carátula válida.") }
  artworkCache[trackID]=data;trimArtworkCache()
  return data
 }

 func send(_ command:MediaCommand) async throws {
  switch command {
  case .previous:_=try await query("previous")
  case .playPause:_=try await query("playPause")
  case .pause:_=try await query("pause")
  case .next:_=try await query("next")
  case .cue(let seconds):_=try await query("cue",argument:String(seconds))
  }
 }
 func volume(_ value:Int?) async throws -> Int {
  guard let volume=try await query("volume",argument:value.map(String.init)).volume else {
   throw MusicFailure(message:"Abre Spotify para controlar su volumen.")
  }
  return volume
 }
 func shuffle(_ value:Bool?) async throws -> Bool {
  guard let enabled=try await query("shuffle",argument:value.map{$0 ? "1":"0"}).shuffle else {
   throw MusicFailure(message:"Spotify no permite cambiar el modo aleatorio ahora mismo.")
  }
  return enabled
 }
 func activeSource() async -> MediaSource? { .spotify }

 static func artworkURL(_ raw:String) -> URL? {
  guard let url=URL(string:raw),url.scheme?.lowercased()=="https",let host=url.host?.lowercased(),
        host=="scdn.co" || host.hasSuffix(".scdn.co") || host=="spotifycdn.com" || host.hasSuffix(".spotifycdn.com") else { return nil }
  return url
 }
 private func trimArtworkCache() {
  while artworkCache.count>32 { artworkCache.removeValue(forKey:artworkCache.keys.first!) }
 }
}

actor MusicSourceBridge:AppleMusicReading {
 private let apple:any AppleMusicReading
 private let spotify:any AppleMusicReading
 private var preference:MusicSourcePreference
 private var selected:MediaSource?

 init(preference:MusicSourcePreference = .automatic,apple:any AppleMusicReading=AppleMusicBridge(),spotify:any AppleMusicReading=SpotifyBridge()) {
  self.preference=preference;self.apple=apple;self.spotify=spotify
 }

 func setSourcePreference(_ preference:MusicSourcePreference) async {
  self.preference=preference
  selected=preference == .appleMusic ? .appleMusic : preference == .spotify ? .spotify : nil
 }
 func activeSource() async -> MediaSource? { selected }
 func isRunning() async -> Bool {
  switch preference {
  case .appleMusic:return await apple.isRunning()
  case .spotify:return await spotify.isRunning()
  case .automatic:
   if await apple.isRunning() { return true }
   return await spotify.isRunning()
  }
 }

 func read() async throws -> MediaSnapshot? {
  switch preference {
  case .appleMusic:selected = .appleMusic;return try await apple.read()
  case .spotify:selected = .spotify;return try await spotify.read()
  case .automatic:return try await readAutomatic()
  }
 }

 private func readAutomatic() async throws -> MediaSnapshot? {
  let appleRunning=await apple.isRunning(),spotifyRunning=await spotify.isRunning()
  let order:[MediaSource] = selected == .appleMusic ? [.appleMusic,.spotify] : [.spotify,.appleMusic]
  var paused:(MediaSource,MediaSnapshot)?
  var firstError:Error?
  for source in order where source == .appleMusic ? appleRunning : spotifyRunning {
   do {
    let snapshot = source == .appleMusic ? try await apple.read() : try await spotify.read()
    guard let snapshot else { continue }
    if snapshot.playing { selected=source;return snapshot }
    if paused == nil { paused=(source,snapshot) }
   } catch { if firstError == nil { firstError=error } }
  }
  if let paused { selected=paused.0;return paused.1 }
  selected=nil
  if let firstError { throw firstError }
  return nil
 }

 private func source(for trackID:String?=nil) -> MediaSource {
  if trackID?.hasPrefix("spotify:") == true { return .spotify }
  return selected ?? (preference == .spotify ? .spotify : .appleMusic)
 }
 func cachedArtwork(trackID:String) async -> Data? {
  source(for:trackID) == .spotify ? await spotify.cachedArtwork(trackID:trackID) : await apple.cachedArtwork(trackID:trackID)
 }
 func rememberCachedArtwork(_ data:Data,for trackID:String) async {
  if source(for:trackID) == .spotify { await spotify.rememberCachedArtwork(data,for:trackID) }
  else { await apple.rememberCachedArtwork(data,for:trackID) }
 }
 func adoptSystemArtwork(for trackID:String) async {
  if source(for:trackID) == .appleMusic { await apple.adoptSystemArtwork(for:trackID) }
 }
 func cacheSystemArtwork(_ reply:MusicReply) async { await apple.cacheSystemArtwork(reply) }
 func artwork(trackID:String) async throws -> Data? {
  source(for:trackID) == .spotify ? try await spotify.artwork(trackID:trackID) : try await apple.artwork(trackID:trackID)
 }
 func neighbors() async throws -> MusicNeighbors? {
  source() == .appleMusic ? try await apple.neighbors() : nil
 }
 func send(_ command:MediaCommand) async throws {
  if source() == .spotify { try await spotify.send(command) } else { try await apple.send(command) }
 }
 func volume(_ value:Int?) async throws -> Int {
  source() == .spotify ? try await spotify.volume(value) : try await apple.volume(value)
 }
 func shuffle(_ value:Bool?) async throws -> Bool {
  source() == .spotify ? try await spotify.shuffle(value) : try await apple.shuffle(value)
 }
}
