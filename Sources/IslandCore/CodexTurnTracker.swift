import Foundation
public struct TurnCompletion:Codable,Equatable,Sendable {
 public var sessionID:String
 public var turnID:String
 public var timestamp:Date
 public var reportedTokens:Int?
 public init(sessionID:String,turnID:String,timestamp:Date,reportedTokens:Int?=nil) { self.sessionID=sessionID;self.turnID=turnID;self.timestamp=timestamp;self.reportedTokens=reportedTokens }
}
public enum CodexEvent:Sendable {
 case tokens(session:String,total:Int)
 case started(session:String,turn:String)
 case completed(session:String,turn:String)
 case aborted(session:String,turn:String)
 public static func decode(line:Data,session:String) throws -> Self? {
 guard let record=try JSONSerialization.jsonObject(with:line) as? [String:Any],record["type"] as? String == "event_msg",let payload=record["payload"] as? [String:Any],let type=payload["type"] as? String else { return nil }
 if type == "token_count",let info=payload["info"] as? [String:Any],let usage=info["total_token_usage"] as? [String:Any],let total=usage["total_tokens"] as? Int { return .tokens(session:session,total:total) }
 guard let turn=payload["turn_id"] as? String,!turn.isEmpty else { return nil }
 switch type { case "task_started":return .started(session:session,turn:turn);case "task_complete":return .completed(session:session,turn:turn);case "turn_aborted":return .aborted(session:session,turn:turn);default:return nil }
 }
}
public struct CodexTurnTracker {
 public private(set) var active:[String:String]=[:]
 private var finished=Set<String>()
 private var totals:[String:Int]=[:]
 private var baselines:[String:Int]=[:]
 public init() {}
 public mutating func seed(_ events:[CodexEvent]) { for event in events { _=consume(event) } }
 public mutating func consume(_ event:CodexEvent) -> TurnCompletion? {
 switch event {
 case let .tokens(session,total): totals[session]=total
 case let .started(session,turn): active[session]=turn;baselines[session]=totals[session]
 case let .aborted(session,turn): if active[session] == turn { active.removeValue(forKey:session) };finished.insert(session+":"+turn)
 case let .completed(session,turn):
 let key=session+":"+turn
 guard active[session] == turn,!finished.contains(key) else { finished.insert(key);return nil }
 active.removeValue(forKey:session);finished.insert(key)
 return TurnCompletion(sessionID:session,turnID:turn,timestamp:Date(),reportedTokens:baselines[session].flatMap{ baseline in totals[session].map{max(0,$0-baseline)} })
 }
 return nil
 }
}
public struct JSONLineBuffer {
 private var pending=Data()
 public init() {}
 public mutating func append(_ data:Data) -> [Data] {
 pending.append(data);var lines:[Data]=[]
 while let i=pending.firstIndex(of:10) { lines.append(Data(pending[..<i]));pending.removeSubrange(...i) }
 // Corrupt/malicious lines are bounded rather than growing without limit.
 if pending.count > 4*1024*1024 { pending.removeAll() }
 return lines
 }
}
public enum CodexSessionMetadata {
 public static func rootID(line:Data) -> String? {
 guard let row=try? JSONSerialization.jsonObject(with:line) as? [String:Any],row["type"] as? String == "session_meta",let p=row["payload"] as? [String:Any],p["parent_thread_id"] == nil,let source=p["source"] as? String,["cli","vscode","exec"].contains(source) else { return nil }
 if let thread=p["thread_source"] as? [String:Any],thread["subagent"] != nil { return nil }
 return (p["session_id"] as? String) ?? (p["id"] as? String)
 }
}
