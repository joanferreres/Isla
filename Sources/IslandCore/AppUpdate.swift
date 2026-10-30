import Foundation

public struct AppVersion:Comparable,Equatable,Sendable {
 private let components:[Int]
 public init?(_ text:String) {
 let value=text.hasPrefix("v") ? String(text.dropFirst()) : text
 let parts=value.split(separator:".",omittingEmptySubsequences:false)
 guard (1...3).contains(parts.count),parts.allSatisfy({!$0.isEmpty && $0.utf8.allSatisfy{(48...57).contains($0)}}) else { return nil }
 let numbers=parts.compactMap{Int($0)};guard numbers.count == parts.count else { return nil }
 components=numbers+Array(repeating:0,count:3-numbers.count)
 }
 public static func < (lhs:Self,rhs:Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct AppUpdate:Codable,Equatable,Sendable {
 public let tag:String
 public let pageURL:URL
 public var version:String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
 public init?(tag:String,pageURL:URL) {
 guard AppVersion(tag) != nil,pageURL.scheme == "https",pageURL.host == "github.com",
 pageURL.user == nil,pageURL.password == nil,pageURL.port == nil,
 pageURL.path == "/joanferreres/Isla/releases/tag/\(tag)",pageURL.query == nil,pageURL.fragment == nil else { return nil }
 self.tag=tag;self.pageURL=pageURL
 }
 public func isNewer(than installed:String) -> Bool {
 guard let latest=AppVersion(tag),let current=AppVersion(installed) else { return false }
 return latest > current
 }
 public static func decodeLatest(_ data:Data) throws -> Self? {
 let payload=try JSONDecoder().decode(Payload.self,from:data)
 guard !payload.draft,!payload.prerelease,
 payload.assets.contains(where:{$0.name == "Isla.zip"}),
 let update=Self(tag:payload.tag_name,pageURL:payload.html_url) else { return nil }
 return update
 }
 private struct Payload:Decodable {
 let tag_name:String,html_url:URL,draft:Bool,prerelease:Bool
 let assets:[Asset]
 struct Asset:Decodable { let name:String }
 }
}
