import Foundation
public struct UsageWindow:Codable,Equatable,Sendable,Identifiable {
 public var id:String
 public var usedPercent:Double
 public var resetsAt:Date?
 public var remainingPercent:Double { max(0,min(100,100-usedPercent)) }
 public init(id:String,usedPercent:Double,resetsAt:Date?) { self.id=id;self.usedPercent=usedPercent;self.resetsAt=resetsAt }
}
public struct UsageSnapshot:Codable,Equatable,Sendable {
 public var fetchedAt:Date
 public var windows:[UsageWindow]
 public var creditRemaining:Double?
 public var creditUnit:String?
 public init(fetchedAt:Date,windows:[UsageWindow],creditRemaining:Double?,creditUnit:String?) { self.fetchedAt=fetchedAt;self.windows=windows;self.creditRemaining=creditRemaining;self.creditUnit=creditUnit }
}
public enum CodexUsageDecoder {
 public static func decode(_ data:Data,fetchedAt:Date) throws -> UsageSnapshot {
 guard let row=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw DecodeFailure() }
 var windows:[UsageWindow]=[]
 func number(_ value:Any?) -> Double? { if let n=value as? NSNumber { return n.doubleValue };if let s=value as? String { return Double(s) };return nil }
 func append(_ rate:[String:Any]?,prefix:String) {
 guard let rate else { return }
 for key in ["primary_window","secondary_window"] {
 if let w=rate[key] as? [String:Any],let used=number(w["used_percent"]),used.isFinite {
 windows.append(UsageWindow(id:prefix+key,usedPercent:max(0,used),resetsAt:number(w["reset_at"]).map{Date(timeIntervalSince1970:$0)}))
 }
 }
 }
 append(row["rate_limit"] as? [String:Any],prefix:"")
 append(row["code_review_rate_limit"] as? [String:Any],prefix:"review_")
 if let extras=row["additional_rate_limits"] as? [[String:Any]] {
 for (i,extra) in extras.enumerated() { append(extra["rate_limit"] as? [String:Any],prefix:(extra["limit_name"] as? String ?? "extra_\(i)")+"_") }
 }
 var balance:Double?
 var unit:String?
 if let credits=row["credits"] as? [String:Any],let value=number(credits["balance"]),value.isFinite { balance=max(0,value);unit="créditos" }
 if let spend=row["spend_control"] as? [String:Any],let limit=spend["individual_limit"] as? [String:Any],let maximum=number(limit["limit"]),let used=number(limit["used"]),maximum.isFinite,used.isFinite { balance=max(0,maximum-used);unit="créditos del espacio" }
 guard !windows.isEmpty || balance != nil else { throw DecodeFailure() }
 return UsageSnapshot(fetchedAt:fetchedAt,windows:windows,creditRemaining:balance,creditUnit:unit)
 }
 public struct DecodeFailure:LocalizedError { public var errorDescription:String? { "Codex no proporciona límites o saldo reconocibles." } }
}

public extension UsageWindow {
 var usedFraction:Double { usedPercent.isFinite ? max(0,min(1,usedPercent/100)) : 0 }
}
public extension UsageSnapshot {
 /// The home ring is always the short account window, never code review or an extra limit.
 var homeUsage:UsageWindow? { windows.first { $0.id == "primary_window" && $0.usedPercent.isFinite } }
}
