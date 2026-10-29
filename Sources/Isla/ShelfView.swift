import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
@MainActor struct ShelfView:View {
 @ObservedObject var store:LocalStore
 @ObservedObject var model:IslandModel
 @StateObject private var airDrop=AirDropService()
 @State private var targeted=false
 @State private var airDropTargeted=false
 var body:some View {
 HStack(spacing:12) {
 ZStack {
 RoundedRectangle(cornerRadius:18).strokeBorder(targeted ? Color.mint : .white.opacity(0.16),style:StrokeStyle(lineWidth:1.5,dash:[5,5]))
 if store.document.files.isEmpty {
 VStack(spacing:7) { Image(systemName:"tray.fill").font(.system(size:23));Text("Bandeja de archivos").font(.system(size:11,weight:.medium)) }.foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
 } else {
 ScrollView(.horizontal,showsIndicators:false) {
 HStack(alignment:.top,spacing:12) { ForEach(store.document.files) { item in
 let exists=FileManager.default.fileExists(atPath:item.url.path)
 VStack(spacing:5) {
 ShelfThumbnail(url:item.url).frame(width:44,height:44)
 Text(item.url.lastPathComponent).font(.system(size:10,weight:.medium)).lineLimit(2).multilineTextAlignment(.center).frame(width:72)
 }.frame(width:76,height:78).opacity(exists ? 1 : 0.4)
 .onTapGesture(count:2) { if exists { NSWorkspace.shared.open(item.url) } }
 .onDrag { NSItemProvider(object:item.url as NSURL) }
 .contextMenu {
 Button("Abrir") { NSWorkspace.shared.open(item.url) }.disabled(!exists)
 Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.disabled(!exists)
 Button("Copiar") { ShelfService.copy(item.url) }.disabled(!exists)
 Button("AirDrop…") { airDrop.send([item.url],model:model) }.disabled(!exists)
 Divider();Button("Quitar de la bandeja") { store.removeFile(item.id) }
 }
 .accessibilityLabel(item.url.lastPathComponent)
 } }.padding(.horizontal,12).padding(.top,12)
 }.padding(.trailing,18)
 }
 VStack { HStack { Spacer();Menu {
 Button("Añadir archivos…") { ShelfService.chooseFiles(into:store,onBegin:model.beginInteraction,onEnd:model.endInteraction) }
 Button("Vaciar bandeja",action:store.clearFiles).disabled(store.document.files.isEmpty)
 } label: { Image(systemName:"ellipsis").font(.system(size:12,weight:.bold)).padding(8) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Opciones de la bandeja") };Spacer() }
 }
 .background(targeted ? Color.mint.opacity(0.05) : .clear,in:RoundedRectangle(cornerRadius:18))
 .onDrop(of:[UTType.fileURL],isTargeted:$targeted) { ShelfService.accept($0,into:store) }
 VStack(spacing:7) {
 ZStack { ForEach([12.0,20,28],id:\.self) { diameter in Circle().stroke(lineWidth:1.2).frame(width:diameter,height:diameter) };Circle().fill().frame(width:4,height:4) }.frame(width:32,height:32)
 Text(airDrop.active ? "Elige destinatario" : "AirDrop").font(.system(size:11,weight:.medium))
 Text("Arrastra aquí").font(.system(size:9)).foregroundStyle(.secondary)
 }.frame(width:100).frame(maxHeight:.infinity)
 .foregroundStyle(airDropTargeted ? .mint : .gray)
 .background(airDropTargeted ? Color.mint.opacity(0.12) : .white.opacity(0.04),in:RoundedRectangle(cornerRadius:18))
 .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(airDropTargeted ? Color.mint : .white.opacity(0.12),style:StrokeStyle(lineWidth:1.5,dash:[5,5])))
 .onDrop(of:[UTType.fileURL],isTargeted:$airDropTargeted) { providers in ShelfService.loadURLs(providers) { airDrop.send($0,model:model) } }
 .accessibilityLabel("AirDrop: arrastra archivos para elegir un destinatario")
 }.overlay(alignment:.bottom) { if let error=airDrop.error { Text(error).font(.caption2).foregroundStyle(.orange).padding(5).background(.black.opacity(0.9),in:Capsule()) } }
 }
}
@MainActor private struct ShelfThumbnail:View {
 let url:URL
 @State private var image:NSImage?
 var body:some View {
 Image(nsImage:image ?? NSWorkspace.shared.icon(forFile:url.path)).resizable().scaledToFit()
 .task(id:url) {
 let request=QLThumbnailGenerator.Request(fileAt:url,size:CGSize(width:64,height:64),scale:2,representationTypes:.all)
 QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { thumbnail,_ in
 guard let thumbnail,let data=NSBitmapImageRep(cgImage:thumbnail.cgImage).representation(using:.png,properties:[:]) else { return };Task { @MainActor in image=NSImage(data:data) }
 }
 }
 }
}
