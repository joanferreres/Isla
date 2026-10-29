import Foundation
import CoreGraphics
public enum IslandGeometry {
 public static func frame(screen: CGRect, notchHeight: CGFloat, expanded: Bool, width: CGFloat) -> CGRect {
 let height = max(32, notchHeight) + (expanded ? 320 : 0)
 let w = min(max(240, width), screen.width)
 return CGRect(x: screen.midX - w/2, y: screen.maxY-height, width: w, height: height)
 }
}
public struct IslandState {
 public private(set) var expanded = false
 public private(set) var pinned = false
 public init() {}
 public mutating func enter() { expanded = true }
 public mutating func leave() { if !pinned { expanded = false } }
 public mutating func togglePinned() { pinned.toggle(); expanded = true }
 public mutating func close() { expanded = false; pinned = false }
}
public enum AINotificationMode:String,Codable,CaseIterable,Sendable {
 case sound,visual,none
 public var title:String { switch self { case .sound:"Aviso con sonido";case .visual:"Solo aviso visual";case .none:"Sin avisos" } }
 public var icon:String { switch self { case .sound:"bell.badge";case .visual:"moon";case .none:"moon.fill" } }
 public var next:Self { switch self { case .sound:.visual;case .visual:.none;case .none:.sound } }
}
public struct Preferences: Codable, Equatable {
 public var hoverEnabled = true
 public var openOnHover = false
 public var reduceMotion = false
 public var expandedWidth: Double = 640
 public var showOnAllDisplays = true
 public var musicEnabled = false
 public var calendarEnabled = false
 public var cursorEnabled = true
 public var claudeEnabled = true
 public var showCursorOnHome = true
 public var showClaudeOnHome = true
 public var codexEnabled = false
 public var showCodexOnHome = true
 public var lidEffectEnabled = false
 public var completionSoundEnabled = true
 public var moonModeEnabled = false
 public var notificationMode:AINotificationMode?
 public var aiNotificationMode:AINotificationMode {
 get { notificationMode ?? (moonModeEnabled ? .none : completionSoundEnabled ? .sound : .visual) }
 set { notificationMode=newValue;moonModeEnabled=newValue == .none;completionSoundEnabled=newValue == .sound }
 }
 public var aiSoundEnabled:Bool { aiNotificationMode == .sound }
 public var aiVisualEnabled:Bool { aiNotificationMode != .none }
 public var screenshotsEnabled=false
 public var screenshotClipboardEnabled=true
 public var selectedCalendarIDs: [String] = []
 public init() {}
 enum CodingKeys: String, CodingKey { case openOnHover,cursorEnabled,claudeEnabled,showCursorOnHome,showClaudeOnHome,screenshotsEnabled,screenshotClipboardEnabled,notificationMode,moonModeEnabled,showCodexOnHome,hoverEnabled,reduceMotion,expandedWidth,showOnAllDisplays,musicEnabled,calendarEnabled,codexEnabled,lidEffectEnabled,completionSoundEnabled,selectedCalendarIDs }
 public init(from decoder: Decoder) throws {
 let c = try decoder.container(keyedBy:CodingKeys.self)
 openOnHover = try c.decodeIfPresent(Bool.self,forKey:.openOnHover) ?? false
 hoverEnabled = try c.decodeIfPresent(Bool.self,forKey:.hoverEnabled) ?? true
 reduceMotion = try c.decodeIfPresent(Bool.self,forKey:.reduceMotion) ?? false
 expandedWidth = try c.decodeIfPresent(Double.self,forKey:.expandedWidth) ?? 640
 showOnAllDisplays = try c.decodeIfPresent(Bool.self,forKey:.showOnAllDisplays) ?? true
 musicEnabled = try c.decodeIfPresent(Bool.self,forKey:.musicEnabled) ?? false
 calendarEnabled = try c.decodeIfPresent(Bool.self,forKey:.calendarEnabled) ?? false
 showCodexOnHome = try c.decodeIfPresent(Bool.self,forKey:.showCodexOnHome) ?? true
 cursorEnabled = try c.decodeIfPresent(Bool.self,forKey:.cursorEnabled) ?? true
 claudeEnabled = try c.decodeIfPresent(Bool.self,forKey:.claudeEnabled) ?? true
 showCursorOnHome = try c.decodeIfPresent(Bool.self,forKey:.showCursorOnHome) ?? true
 showClaudeOnHome = try c.decodeIfPresent(Bool.self,forKey:.showClaudeOnHome) ?? true
 codexEnabled = try c.decodeIfPresent(Bool.self,forKey:.codexEnabled) ?? false
 lidEffectEnabled = try c.decodeIfPresent(Bool.self,forKey:.lidEffectEnabled) ?? false
 notificationMode = try c.decodeIfPresent(AINotificationMode.self,forKey:.notificationMode)
 moonModeEnabled = try c.decodeIfPresent(Bool.self,forKey:.moonModeEnabled) ?? false
 completionSoundEnabled = try c.decodeIfPresent(Bool.self,forKey:.completionSoundEnabled) ?? true
 screenshotsEnabled = try c.decodeIfPresent(Bool.self,forKey:.screenshotsEnabled) ?? false
 screenshotClipboardEnabled = try c.decodeIfPresent(Bool.self,forKey:.screenshotClipboardEnabled) ?? true
 selectedCalendarIDs = try c.decodeIfPresent([String].self,forKey:.selectedCalendarIDs) ?? []
 }
 public func normalized() -> Self { var p = self; p.expandedWidth = expandedWidth.isFinite ? min(800,max(480,expandedWidth)) : 640; return p }
}
