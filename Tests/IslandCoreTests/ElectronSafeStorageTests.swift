import XCTest
import CommonCrypto
@testable import IslandCore
final class ElectronSafeStorageTests:XCTestCase {
 func testUnwrapsCursorSafeStorageV1() throws {
  let sealed="cursor-safe-storage:v1:djEww03mXiOogQVLP8swh7hQqtqlBH7lTtLbkPi9LvYgD+T/p309ZcP2xQuH6COtTRyO"
  let plain=try ElectronSafeStorage.unwrap(sealed,password:"isla-fixture-password")
  XCTAssertEqual(plain,"fixture.eyJzdWIiOiJmaXh0dXJlLWFjY291bnQifQ.sig")
 }
 func testPlaintextPassesThrough() throws {
  XCTAssertEqual(try ElectronSafeStorage.unwrap("plain-token",password:"unused"),"plain-token")
 }
 func testRejectsBadPassword() {
  let sealed="cursor-safe-storage:v1:djEww03mXiOogQVLP8swh7hQqtqlBH7lTtLbkPi9LvYgD+T/p309ZcP2xQuH6COtTRyO"
  XCTAssertThrowsError(try ElectronSafeStorage.unwrap(sealed,password:"wrong"))
 }
 func testChromeCookieStripsHostHashPrefix() throws {
  let password="isla-fixture-password"
  let plain=Data(repeating:0,count:32)+Data("sk-ant-sid-fixture".utf8)
  var key=Data(count:16)
  let salt=Data("saltysalt".utf8)
  let derive=password.withCString{ pass in
   salt.withUnsafeBytes{ saltBytes in
    key.withUnsafeMutableBytes{ keyBytes in
     CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),pass,password.utf8.count,saltBytes.bindMemory(to:UInt8.self).baseAddress,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),1003,keyBytes.bindMemory(to:UInt8.self).baseAddress,16)
    }
   }
  }
  XCTAssertEqual(Int(derive),Int(kCCSuccess))
  var cipher=Data(count:plain.count+16);var moved=0
  let iv=Data(repeating:0x20,count:16)
  let status=key.withUnsafeBytes{ keyBytes in
   iv.withUnsafeBytes{ ivBytes in
    plain.withUnsafeBytes{ dataBytes in
     cipher.withUnsafeMutableBytes{ outBytes in
      CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),keyBytes.baseAddress,16,ivBytes.baseAddress,dataBytes.baseAddress,plain.count,outBytes.baseAddress,outBytes.count,&moved)
     }
    }
   }
  }
  XCTAssertEqual(Int(status),Int(kCCSuccess))
  var blob=Data("v10".utf8);blob.append(cipher.prefix(moved))
  XCTAssertEqual(try ElectronSafeStorage.chromeCookieValue(blob,password:password),"sk-ant-sid-fixture")
 }
}
