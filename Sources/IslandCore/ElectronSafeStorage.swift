import Foundation
import CommonCrypto

/// Electron/Chromium `safeStorage` payload used by Cursor for auth tokens at rest.
public enum ElectronSafeStorage {
 public static let cursorPrefix="cursor-safe-storage:v1:"

 public static func unwrap(_ value:String,password:String) throws -> String {
  guard value.hasPrefix(cursorPrefix) else { return value }
  guard let blob=Data(base64Encoded:String(value.dropFirst(cursorPrefix.count))) else { throw Failure() }
  return try decrypt(blob,password:password)
 }

 public static func decrypt(_ blob:Data,password:String) throws -> String {
  guard blob.count>3,String(data:blob.prefix(3),encoding:.utf8)=="v10" else { throw Failure() }
  let cipher=blob.dropFirst(3)
  var key=Data(count:kCCKeySizeAES128)
  let salt=Data("saltysalt".utf8)
  let derive=password.withCString{ pass in
   salt.withUnsafeBytes{ saltBytes in
    key.withUnsafeMutableBytes{ keyBytes in
     CCKeyDerivationPBKDF(
      CCPBKDFAlgorithm(kCCPBKDF2),
      pass,
      password.utf8.count,
      saltBytes.bindMemory(to:UInt8.self).baseAddress,
      salt.count,
      CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
      1003,
      keyBytes.bindMemory(to:UInt8.self).baseAddress,
      kCCKeySizeAES128
     )
    }
   }
  }
  guard derive==kCCSuccess else { throw Failure() }
  var output=Data(count:cipher.count+kCCBlockSizeAES128)
  var moved=0
  let iv=Data(repeating:0x20,count:kCCBlockSizeAES128)
  let status=key.withUnsafeBytes{ keyBytes in
   iv.withUnsafeBytes{ ivBytes in
    cipher.withUnsafeBytes{ dataBytes in
     output.withUnsafeMutableBytes{ outBytes in
      CCCrypt(
       CCOperation(kCCDecrypt),
       CCAlgorithm(kCCAlgorithmAES),
       CCOptions(kCCOptionPKCS7Padding),
       keyBytes.baseAddress,
       kCCKeySizeAES128,
       ivBytes.baseAddress,
       dataBytes.baseAddress,
       cipher.count,
       outBytes.baseAddress,
       outBytes.count,
       &moved
      )
     }
    }
   }
  }
  guard status==kCCSuccess,moved>0,let text=String(data:output.prefix(moved),encoding:.utf8),!text.isEmpty else { throw Failure() }
  return text
 }

 public struct Failure:LocalizedError {
  public init() {}
  public var errorDescription:String? { "No se pudo descifrar la sesión guardada." }
 }
}
