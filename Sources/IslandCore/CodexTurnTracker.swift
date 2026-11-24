import Foundation
/// Which AI app finished a turn. Each one gets its own colour for the notch alert.
public enum AlertSource:String,Codable,CaseIterable,Sendable {
 case codex,claude,cursor,antigravity
 public var title:String { switch self { case .codex:return "Codex";case .claude:return "Claude";case .cursor:return "Cursor";case .antigravity:return "Antigravity" } }
 /// Brand-like RGB (0…1): OpenAI green, Claude orange, Cursor white, Antigravity blue.
 public var rgb:(r:Double,g:Double,b:Double) {
 switch self {
 case .codex:return (0.06,0.78,0.55)
 case .claude:return (0.85,0.47,0.34)
 case .cursor:return (0.93,0.94,1.0)
 case .antigravity:return (0.25,0.55,1.0)
 }
 }
}
public struct TurnCompletion:Codable,Equatable,Sendable {
 public var sessionID:String
 public var turnID:String
 public var timestamp:Date
 public var reportedTokens:Int?
 /// nil in old saved history = Codex.
 public var source:AlertSource?
 public init(sessionID:String,turnID:String,timestamp:Date,reportedTokens:Int?=nil,source:AlertSource?=nil) { self.sessionID=sessionID;self.turnID=turnID;self.timestamp=timestamp;self.reportedTokens=reportedTokens;self.source=source }
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

/// Claude Code writes one JSON line per message to ~/.claude/projects/**/*.jsonl.
/// A turn is over when the main (non-subagent) assistant message ends with `stop_reason: end_turn`.
public enum ClaudeTurnEvent {
 public static func completion(line:Data) -> TurnCompletion? {
 // Cheap pre-filter: most lines are huge tool results we never need to parse.
 guard line.range(of:Data("end_turn".utf8)) != nil,
 let row=try? JSONSerialization.jsonObject(with:line) as? [String:Any],
 row["type"] as? String == "assistant",row["isSidechain"] as? Bool != true,
 let message=row["message"] as? [String:Any],message["stop_reason"] as? String == "end_turn",
 let session=row["sessionId"] as? String,let id=row["uuid"] as? String else { return nil }
 let fractional=ISO8601DateFormatter();fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
 let stamp=(row["timestamp"] as? String).flatMap{ fractional.date(from:$0) ?? ISO8601DateFormatter().date(from:$0) } ?? Date()
 return TurnCompletion(sessionID:session,turnID:id,timestamp:stamp,source:.claude)
 }
}
