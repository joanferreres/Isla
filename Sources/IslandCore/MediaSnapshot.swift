import Foundation
public struct MediaSnapshot:Codable,Equatable,Sendable {
 public var trackID:String
 public var title:String
 public var artist:String
 public var playing:Bool
 public var position:Double
 public var duration:Double
 public init(trackID:String,title:String,artist:String,playing:Bool,position:Double,duration:Double) { self.trackID=trackID;self.title=title;self.artist=artist;self.playing=playing;self.position=position;self.duration=duration }
}
public enum MediaCommand:String,Sendable { case previous,playPause,next }
public struct MediaState {
 public private(set) var snapshot:MediaSnapshot?
 public private(set) var artworkData:Data?
 public init() {}
 public mutating func update(_ snapshot:MediaSnapshot?) { if self.snapshot?.trackID != snapshot?.trackID { artworkData=nil };self.snapshot=snapshot }
 public mutating func acceptArtwork(_ data:Data,for trackID:String) -> Bool { guard snapshot?.trackID == trackID else { return false }; artworkData=data;return true }
}
