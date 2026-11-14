import Foundation
public struct MediaSnapshot:Codable,Equatable,Sendable {
 public var trackID:String
 public var title:String
 public var artist:String
 public var playing:Bool
 public var position:Double
 public var duration:Double
 /// Apple Music `genre` when the library provides one (empty for many streams).
 public var genre:String
 public init(trackID:String,title:String,artist:String,playing:Bool,position:Double,duration:Double,genre:String="") {
  self.trackID=trackID;self.title=title;self.artist=artist;self.playing=playing;self.position=position;self.duration=duration;self.genre=genre
 }
 enum CodingKeys:String,CodingKey { case trackID,title,artist,playing,position,duration,genre }
 public init(from decoder:Decoder) throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  trackID=try c.decode(String.self,forKey:.trackID)
  title=try c.decode(String.self,forKey:.title)
  artist=try c.decode(String.self,forKey:.artist)
  playing=try c.decode(Bool.self,forKey:.playing)
  position=try c.decode(Double.self,forKey:.position)
  duration=try c.decode(Double.self,forKey:.duration)
  genre=try c.decodeIfPresent(String.self,forKey:.genre) ?? ""
 }
}
public enum MediaCommand:Sendable { case previous,playPause,pause,next,cue(seconds:Double) }
public struct MediaState {
 public private(set) var snapshot:MediaSnapshot?
 public private(set) var artworkData:Data?
 public init() {}
 public mutating func update(_ snapshot:MediaSnapshot?) { if self.snapshot?.trackID != snapshot?.trackID { artworkData=nil };self.snapshot=snapshot }
 public mutating func acceptArtwork(_ data:Data,for trackID:String) -> Bool { guard snapshot?.trackID == trackID else { return false }; artworkData=data;return true }
}
