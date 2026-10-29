import Foundation
public enum AIProvider:String,CaseIterable,Codable,Sendable,Identifiable {
 case cursor,claude
 public var id:String { rawValue }
 public var title:String { self == .cursor ? "Cursor" : "Claude" }
 public func label(_ id:String) -> String {
 switch id { case "five_hour":return "Sesión · 5 horas";case "seven_day":return "Semana · todos los modelos";case "seven_day_sonnet":return "Semana · Sonnet";case "seven_day_opus":return "Semana · Opus";case "auto":return "Cursor Models / Auto";case "api":return "Modelos API";case "included":return "Uso incluido";case "on_demand":return "Uso adicional";default:return id.replacingOccurrences(of:"_",with:" ") }
 }
}
public enum AIUsageDecoder {
 public static func decode(_ data:Data,provider:AIProvider,fetchedAt:Date) throws -> UsageSnapshot {
 guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw Failure() }
 func number(_ value:Any?) -> Double? { guard let n=value as? NSNumber,n.doubleValue.isFinite else { return nil };return n.doubleValue }
 func date(_ value:Any?) -> Date? {
 guard let s=value as? String else { return nil };let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:s) ?? ISO8601DateFormatter().date(from:s)
 }
 var windows:[UsageWindow]=[]
 if provider == .claude {
 for id in ["five_hour","seven_day","seven_day_sonnet","seven_day_opus"] {
 if let row=root[id] as? [String:Any],let used=number(row["utilization"]),used>=0 { windows.append(UsageWindow(id:id,usedPercent:used,resetsAt:date(row["resets_at"]))) }
 }
 } else {
 let usage=root["individualUsage"] as? [String:Any] ?? [:],plan=usage["plan"] as? [String:Any] ?? [:]
 let reset=date(root["billingCycleEnd"])
 for (id,key) in [("auto","autoPercentUsed"),("api","apiPercentUsed")] {
 if let used=number(plan[key]),used>=0 { windows.append(UsageWindow(id:id,usedPercent:used,resetsAt:reset)) }
 }
 for (id,key) in [("included","overall"),("on_demand","onDemand")] {
 if let row=usage[key] as? [String:Any],row["enabled"] as? Bool == true,let used=number(row["used"]),used>=0,let limit=number(row["limit"]),limit>0 { windows.append(UsageWindow(id:id,usedPercent:used/limit*100,resetsAt:reset)) }
 }
 }
 guard !windows.isEmpty else { throw Failure() }
 return UsageSnapshot(fetchedAt:fetchedAt,windows:windows,creditRemaining:nil,creditUnit:nil)
 }
 public struct Failure:LocalizedError { public var errorDescription:String? { "La cuenta no proporciona límites medibles. No se estima un porcentaje." } }
}
