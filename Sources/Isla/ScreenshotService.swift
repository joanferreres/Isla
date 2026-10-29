import AppKit
import Combine
import Darwin
import IslandCore

/// Observe directory writes; never capture the screen or poll in the background.
@MainActor final class ScreenshotService:ObservableObject {
 @Published var error:String?
 let folder:URL
 var copyToClipboard=true
 private var source:DispatchSourceFileSystemObject?
 private var pending:Task<Void,Never>?
 private var seen=Set<URL>()
 private var active=false
 private let onCapture:(URL)->Void
 private let copy:@MainActor (URL)->Bool
 init(folder:URL?=nil,onCapture:@escaping (URL)->Void,copy:@escaping @MainActor (URL)->Bool={ ShelfService.copy($0) }) {
 self.folder=folder ?? FileManager.default.urls(for:.desktopDirectory,in:.userDomainMask)[0].appendingPathComponent("capturas",isDirectory:true)
 self.onCapture=onCapture;self.copy=copy
 }
 func configureSystemFolder(domainName:String="com.apple.screencapture") throws {
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 let domain=domainName as CFString
 CFPreferencesSetAppValue("location" as CFString,folder.path as CFString,domain)
 CFPreferencesSetAppValue("location-screenshot" as CFString,folder.path as CFString,domain)
 CFPreferencesSetAppValue("target" as CFString,"file" as CFString,domain)
 CFPreferencesSetAppValue("target-screenshot" as CFString,"file" as CFString,domain)
 // Save immediately so our file observer can copy it without the floating-preview delay.
 CFPreferencesSetAppValue("show-thumbnail" as CFString,kCFBooleanFalse,domain)
 guard CFPreferencesAppSynchronize(domain) else { throw CocoaError(.fileWriteUnknown) }
 error=nil
 }
 func start(copyToClipboard:Bool) throws {
 self.copyToClipboard=copyToClipboard
 guard !active else { return }
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 seen=Set(try contents())
 let descriptor=open(folder.path,O_EVTONLY)
 guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
 let watcher=DispatchSource.makeFileSystemObjectSource(fileDescriptor:descriptor,eventMask:[.write,.rename,.delete],queue:.main)
 watcher.setEventHandler { [weak self] in Task { @MainActor in self?.scheduleScan() } }
 watcher.setCancelHandler { close(descriptor) }
 source=watcher;active=true;watcher.resume();error=nil
 }
 func stop() { active=false;pending?.cancel();pending=nil;source?.cancel();source=nil;seen=[] }
 private func contents() throws -> [URL] {
 try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles).sorted {
 (($0.resourceValuesSafeDate) ?? .distantPast) < (($1.resourceValuesSafeDate) ?? .distantPast)
 }
 }
 private func scheduleScan() {
 guard active else { return }
 pending?.cancel()
 pending=Task { [weak self] in
 // File data and screenshot metadata can arrive in separate directory events.
 for _ in 0..<8 {
 do { try await Task.sleep(for:.milliseconds(250)) } catch { return }
 guard let self,!Task.isCancelled,self.active else { return }
 await self.scanNow()
 }
 }
 }
 func scanNow() async {
 guard active else { return }
 do {
 let files=try contents()
 seen.formIntersection(Set(files))
 for url in files where !seen.contains(url) {
 guard Self.isScreenshot(url),let image=NSImage(contentsOf:url),image.isValid else { continue }
 seen.insert(url);onCapture(url)
 if copyToClipboard && !copy(url) { error="La captura está en Archivos, pero no se pudo copiar." }
 }
 } catch { self.error="No se pudo leer Escritorio/capturas. Revisa el acceso al Escritorio." }
 }
 private static func isScreenshot(_ url:URL) -> Bool {
 guard ["png","jpg","jpeg","heic","tif","tiff"].contains(url.pathExtension.lowercased()) else { return false }
 let key="com.apple.metadata:kMDItemIsScreenCapture"
 let size=getxattr(url.path,key,nil,0,0,0)
 if size > 0 && size < 4096 {
 var bytes=[UInt8](repeating:0,count:size)
 let count=getxattr(url.path,key,&bytes,size,0,0)
 if count > 0,let value=try? PropertyListSerialization.propertyList(from:Data(bytes.prefix(count)),format:nil),value as? Bool == true { return true }
 }
 let name=url.deletingPathExtension().lastPathComponent.lowercased()
 return ["screenshot","screen shot","screen capture","captura de pantalla"].contains { name.hasPrefix($0) }
 }
}
private extension URL {
 var resourceValuesSafeDate:Date? { (try? resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate }
}
