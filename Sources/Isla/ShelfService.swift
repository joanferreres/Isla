import AppKit
import SwiftUI
import UniformTypeIdentifiers
@MainActor enum ShelfService {
 @discardableResult static func copy(_ url:URL) -> Bool {
 guard FileManager.default.fileExists(atPath:url.path) else { return false }
 let item=NSPasteboardItem()
 item.setString(url.absoluteString,forType:.fileURL)
 if url.pathExtension.lowercased() == "png",let png=try? Data(contentsOf:url) {
 item.setData(png,forType:.png)
 } else if let image=NSImage(contentsOf:url),let tiff=image.tiffRepresentation {
 item.setData(tiff,forType:.tiff)
 if let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) { item.setData(png,forType:.png) }
 }
 NSPasteboard.general.clearContents()
 return NSPasteboard.general.writeObjects([item])
 }
 @discardableResult static func loadURLs(_ providers:[NSItemProvider],completion:@escaping @MainActor ([URL]) -> Void) -> Bool {
 let supported=providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
 guard !supported.isEmpty else { return false }
 let batch=ShelfDropBatch(count:supported.count,completion:completion)
 for (index,provider) in supported.enumerated() {
 provider.loadDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier) { data,_ in
 let url=data.flatMap { URL(dataRepresentation:$0,relativeTo:nil) }
 Task { @MainActor in batch.finish(index:index,url:url) }
 }
 }
 return true
 }
 static func accept(_ providers:[NSItemProvider],into store:LocalStore) -> Bool { loadURLs(providers) { store.addFiles($0) } }
 static func chooseFiles(into store: LocalStore,onBegin: () -> Void,onEnd: @escaping () -> Void) {
  let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
  picker.title = "Añadir a la bandeja"; picker.prompt = "Añadir"
  onBegin()
  NSApp.activate(ignoringOtherApps:true)
  picker.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1)
  picker.begin { response in if response == .OK { store.addFiles(picker.urls) }; onEnd() }
 }
}
struct ShareFileButton: NSViewRepresentable {
 let url: URL
 let onBegin: () -> Void
 let onEnd: () -> Void
 func makeNSView(context: Context) -> NSButton {
  let button = NSButton(image: NSImage(systemSymbolName:"square.and.arrow.up",accessibilityDescription:"Compartir archivo")!,target:context.coordinator,action:#selector(Coordinator.share(_:)))
  button.bezelStyle = .accessoryBarAction
  return button
 }
 func updateNSView(_ button: NSButton,context: Context) { context.coordinator.url = url; context.coordinator.onBegin = onBegin; context.coordinator.onEnd = onEnd }
 func makeCoordinator() -> Coordinator { Coordinator(url:url,onBegin:onBegin,onEnd:onEnd) }
 @MainActor final class Coordinator: NSObject, @preconcurrency NSSharingServicePickerDelegate {
  var url: URL
  var onBegin: () -> Void
  var onEnd: () -> Void
  var picker: NSSharingServicePicker?
  init(url: URL,onBegin: @escaping () -> Void,onEnd: @escaping () -> Void) { self.url = url; self.onBegin = onBegin; self.onEnd = onEnd }
  @objc func share(_ sender: NSButton) {
   guard picker == nil else { return }
   onBegin()
   let picker = NSSharingServicePicker(items:[url]); self.picker = picker
   picker.delegate = self
   picker.show(relativeTo:sender.bounds,of:sender,preferredEdge:.minY)
  }
  func sharingServicePicker(_ sharingServicePicker:NSSharingServicePicker,didChoose service:NSSharingService?) { picker = nil; onEnd() }
 }
}

@MainActor private final class ShelfDropBatch {
 private var remaining:Int
 private var urls:[Int:URL]=[:]
 private let completion:@MainActor ([URL]) -> Void
 init(count:Int,completion:@escaping @MainActor ([URL]) -> Void) { remaining=count;self.completion=completion }
 func finish(index:Int,url:URL?) {
 if let url,url.isFileURL,FileManager.default.fileExists(atPath:url.path) { urls[index]=url.standardizedFileURL }
 remaining -= 1
 if remaining == 0 { var seen=Set<URL>();completion(urls.keys.sorted().compactMap{urls[$0]}.filter{seen.insert($0).inserted}) }
 }
}
@MainActor final class AirDropService:NSObject,ObservableObject,@preconcurrency NSSharingServiceDelegate {
 @Published private(set) var active=false
 @Published private(set) var error:String?
 private var sharing:NSSharingService?
 private weak var model:IslandModel?
 func send(_ urls:[URL],model:IslandModel) {
 guard !active else { return }
 let files=urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath:$0.path) }
 guard !files.isEmpty else { error="El archivo ya no está disponible.";return }
 guard let service=NSSharingService(named:.sendViaAirDrop),service.canPerform(withItems:files) else { error="AirDrop no está disponible en este Mac.";return }
 self.model=model;model.beginInteraction();active=true;error=nil;sharing=service;service.delegate=self
 NSApp.activate(ignoringOtherApps:true)
 service.perform(withItems:files)
 }
 func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]) { finish() }
 func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error) { if (error as NSError).code != NSUserCancelledError { self.error="No se pudo compartir el archivo por AirDrop." };finish() }
 private func finish() { sharing=nil;active=false;model?.endInteraction();model=nil }
}
