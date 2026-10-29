import XCTest
import AppKit
@testable import Isla

@MainActor final class ScreenshotTests:XCTestCase {
 func testFolderConfigurationIncludesModernScreenshotPreferences() throws {
 let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 let domainName="IslaScreenshotTest."+UUID().uuidString
 let domain=domainName as CFString
 defer {
 try? FileManager.default.removeItem(at:folder)
 for key in ["location","location-screenshot","target","target-screenshot","show-thumbnail"] { CFPreferencesSetAppValue(key as CFString,nil,domain) }
 CFPreferencesAppSynchronize(domain)
 }
 let service=ScreenshotService(folder:folder,onCapture:{_ in})
 try service.configureSystemFolder(domainName:domainName)
 XCTAssertEqual(CFPreferencesCopyAppValue("location" as CFString,domain) as? String,folder.path)
 XCTAssertEqual(CFPreferencesCopyAppValue("location-screenshot" as CFString,domain) as? String,folder.path)
 XCTAssertEqual(CFPreferencesCopyAppValue("target-screenshot" as CFString,domain) as? String,"file")
 XCTAssertEqual(CFPreferencesCopyAppValue("show-thumbnail" as CFString,domain) as? Bool,false)
 }
 func testOnlyNewCapturesAreImportedAndClipboardChoiceIsRespected() async throws {
 let folder=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:folder) }
 let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let png=image.representation(using:.png,properties:[:])!
 try png.write(to:folder.appendingPathComponent("Screenshot-old.png"))
 var imported:[URL]=[];var copied:[URL]=[]
 let service=ScreenshotService(folder:folder,onCapture:{imported.append($0)},copy: {copied.append($0);return true})
 try service.start(copyToClipboard:false)
 let fresh=folder.appendingPathComponent("Screenshot-new.png")
 try png.write(to:fresh)
 await service.scanNow()
 XCTAssertEqual(imported.map{$0.resolvingSymlinksInPath().path},[fresh.resolvingSymlinksInPath().path]);XCTAssertTrue(copied.isEmpty)
 await service.scanNow();XCTAssertEqual(imported.count,1)
 service.copyToClipboard=true
 let other=folder.appendingPathComponent("Captura de pantalla-test.png")
 try png.write(to:other);await service.scanNow()
 XCTAssertEqual(copied.map{$0.resolvingSymlinksInPath().path},[other.resolvingSymlinksInPath().path]);XCTAssertEqual(imported.count,2)
 service.stop()
 }
 func testOrdinaryImagesAreNotTreatedAsScreenshots() async throws {
 let folder=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:folder) }
 let service=ScreenshotService(folder:folder,onCapture:{_ in XCTFail("Ordinary image")},copy:{_ in XCTFail("Clipboard");return true})
 try service.start(copyToClipboard:true)
 try Data([0,1,2]).write(to:folder.appendingPathComponent("photo.png"))
 await service.scanNow();service.stop()
 }
}
