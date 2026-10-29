import Foundation
public struct UsageHistory:Codable,Sendable {
 public private(set) var readings:[UsageSnapshot]=[]
 public private(set) var completions:[TurnCompletion]=[]
 public init() {}
 public mutating func record(_ snapshot:UsageSnapshot) { guard readings.last != snapshot else { return };readings.append(snapshot) }
 public mutating func record(_ completion:TurnCompletion) { guard !completions.contains(where:{$0.sessionID == completion.sessionID && $0.turnID == completion.turnID}) else { return };completions.append(completion) }
 public mutating func prune(before:Date) { readings.removeAll{$0.fetchedAt < before};completions.removeAll{$0.timestamp < before} }
}
