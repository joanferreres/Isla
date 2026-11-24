import SwiftUI
import IslandCore

/// A short, event-driven contour highlight; no idle timer or display link.
/// Every trigger builds a fresh `CompletionRailEffect` (new `.id`), so pressing it again while one is still
/// playing restarts instantly instead of fighting with the animations in flight.
@MainActor struct CompletionRailView:View {
 let trigger:UUID?
 let enabled:Bool
 let source:AlertSource
 let reduceMotion:Bool
 let cornerRadius:CGFloat
 @State private var run=0
 @State private var visible=false
 @State private var shownSource:AlertSource = .codex
 @State private var hideTask:Task<Void,Never>?
 let notchWidth:CGFloat
 let notchHeight:CGFloat
 let physicalNotch:Bool
 var body:some View {
 GeometryReader { proxy in
 let frame=CompletionOutlineGeometry.frame(container:proxy.size,notchWidth:notchWidth,notchHeight:notchHeight,physicalNotch:physicalNotch)
 ZStack {
 if visible && enabled {
 CompletionRailEffect(source:shownSource,container:proxy.size,frame:frame,cornerRadius:cornerRadius,physicalNotch:physicalNotch,reduceMotion:reduceMotion).id(run)
 }
 }.frame(width:frame.width,height:frame.height)
 .position(x:frame.midX,y:frame.midY)
 }.allowsHitTesting(false).accessibilityHidden(true)
 .onChange(of:trigger) { _,pulse in if pulse != nil && enabled { play() } }
 .onChange(of:enabled) { _,active in if !active { cancel() } }
 .onDisappear { cancel() }
 }
 private func play() {
 hideTask?.cancel()
 shownSource=source
 run += 1
 visible=true
 let mine=run
 hideTask=Task { @MainActor in
 do { try await Task.sleep(for:.seconds(3.9)) } catch { return }
 if run == mine { visible=false;hideTask=nil }
 }
 }
 private func cancel() { hideTask?.cancel();hideTask=nil;visible=false }
}

@MainActor private struct CompletionRailEffect:View {
 let source:AlertSource
 let container:CGSize
 let frame:CGRect
 let cornerRadius:CGFloat
 let physicalNotch:Bool
 let reduceMotion:Bool
 @State private var opacity=0.0
 @State private var phase=0.0
 var body:some View {
 let tint=Color(red:source.rgb.r,green:source.rgb.g,blue:source.rgb.b)
 let contour=CompletionContour(physicalNotch:physicalNotch,cornerRadius:cornerRadius)
 ZStack {
 // Static layers are rasterised once on the GPU; only the sweep is re-drawn while it turns.
 // (A live blur + shadows on the main thread made the whole app, Settings included, stutter.)
 // The canvas is a little larger than the outline so the glow is not clipped.
 ZStack {
 CompletionBacking(container:container,outlineFrame:frame,physicalNotch:physicalNotch,cornerRadius:cornerRadius).fill(.black,style:FillStyle(eoFill:true)).frame(width:frame.width,height:frame.height)
 contour.stroke(tint.opacity(0.16),style:StrokeStyle(lineWidth:18,lineCap:.round)).frame(width:frame.width,height:frame.height)
 contour.stroke(tint.opacity(0.30),style:StrokeStyle(lineWidth:11,lineCap:.round)).frame(width:frame.width,height:frame.height)
 contour.stroke(tint,style:StrokeStyle(lineWidth:6,lineCap:.round)).frame(width:frame.width,height:frame.height)
 }.frame(width:frame.width+48,height:frame.height+48).drawingGroup()
 ZStack {
 AngularGradient(colors:[.clear,.clear,tint,.white,tint,.clear],center:.center)
 .scaleEffect(1.5)
 .rotationEffect(.degrees(phase*720))
 .mask(contour.stroke(style:StrokeStyle(lineWidth:7,lineCap:.round)))
 .frame(width:frame.width,height:frame.height)
 }.frame(width:frame.width+48,height:frame.height+48).drawingGroup()
 }.frame(width:frame.width,height:frame.height)
 .opacity(opacity)
 .task {
 withAnimation(.easeOut(duration:0.2)) { opacity=1 }
 if !reduceMotion { withAnimation(.linear(duration:3.0)) { phase=1 } }
 do { try await Task.sleep(for:.seconds(3.0)) } catch { return }
 withAnimation(.easeOut(duration:0.7)) { opacity=0 }
 }
 }
}

/// Open U below and beside the physical camera housing; no hidden top stroke.
private struct CompletionContour:Shape {
 let physicalNotch:Bool
 let cornerRadius:CGFloat
 func path(in rect:CGRect) -> Path {
 let bounds=rect.insetBy(dx:1,dy:1)
 guard physicalNotch else {
 return UnevenRoundedRectangle(bottomLeadingRadius:cornerRadius,bottomTrailingRadius:cornerRadius).path(in:bounds)
 }
 let r=min(cornerRadius,min(bounds.width/2,bounds.height))
 var p=Path()
 p.move(to:CGPoint(x:bounds.minX,y:rect.minY))
 p.addLine(to:CGPoint(x:bounds.minX,y:bounds.maxY-r))
 p.addQuadCurve(to:CGPoint(x:bounds.minX+r,y:bounds.maxY),control:CGPoint(x:bounds.minX,y:bounds.maxY))
 p.addLine(to:CGPoint(x:bounds.maxX-r,y:bounds.maxY))
 p.addQuadCurve(to:CGPoint(x:bounds.maxX,y:bounds.maxY-r),control:CGPoint(x:bounds.maxX,y:bounds.maxY))
 p.addLine(to:CGPoint(x:bounds.maxX,y:rect.minY))
 return p
 }
}

/// Fill only the added band: preserve the content inside our existing island.
private struct CompletionBacking:Shape {
 let container:CGSize
 let outlineFrame:CGRect
 let physicalNotch:Bool
 let cornerRadius:CGFloat
 func path(in rect:CGRect) -> Path {
 guard physicalNotch else { return Path() }
 var path=CompletionContour(physicalNotch:true,cornerRadius:cornerRadius).path(in:rect)
 let inner=CGRect(x:-outlineFrame.minX,y:-outlineFrame.minY,width:container.width,height:container.height)
 path.addPath(UnevenRoundedRectangle(bottomLeadingRadius:cornerRadius,bottomTrailingRadius:cornerRadius).path(in:inner))
 return path
 }
}
