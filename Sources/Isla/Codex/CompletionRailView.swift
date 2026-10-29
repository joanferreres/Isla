import SwiftUI
import IslandCore

/// A short, event-driven contour highlight; no idle timer or display link.
@MainActor struct CompletionRailView:View {
 let trigger:UUID?
 let enabled:Bool
 let reduceMotion:Bool
 let cornerRadius:CGFloat
 @State private var visible=false
 @State private var opacity=0.0
 @State private var phase=0.0
 @State private var animationTask:Task<Void,Never>?
 let notchWidth:CGFloat
 let notchHeight:CGFloat
 let physicalNotch:Bool
 var body:some View {
 GeometryReader { proxy in
 let frame=CompletionOutlineGeometry.frame(container:proxy.size,notchWidth:notchWidth,notchHeight:notchHeight,physicalNotch:physicalNotch)
 let contour=CompletionContour(physicalNotch:physicalNotch,cornerRadius:cornerRadius)
 ZStack {
 if visible && enabled {
 CompletionBacking(container:proxy.size,outlineFrame:frame,physicalNotch:physicalNotch,cornerRadius:cornerRadius).fill(.black,style:FillStyle(eoFill:true))
 contour.stroke(Color.mint.opacity(0.95),style:StrokeStyle(lineWidth:4,lineCap:.round))
 AngularGradient(colors:[.clear,.clear,.mint,.white.opacity(0.85),.mint,.clear],center:.center)
 .scaleEffect(1.5)
 .rotationEffect(.degrees(phase*360))
 .mask(contour.stroke(style:StrokeStyle(lineWidth:4,lineCap:.round)))
 .shadow(color:.mint.opacity(0.85),radius:6)
 }
 }.frame(width:frame.width,height:frame.height)
 .position(x:frame.midX,y:frame.midY)
 }.opacity(opacity).allowsHitTesting(false).accessibilityHidden(true)
 .onChange(of:trigger) { _,pulse in if pulse != nil && enabled { play() } }
 .onChange(of:enabled) { _,active in if !active { cancel() } }
 .onDisappear { cancel() }
 }
 private func play() {
 animationTask?.cancel()
 var reset=Transaction();reset.disablesAnimations=true
 withTransaction(reset) { visible=true;opacity=0;phase=0 }
 animationTask=Task { @MainActor in
 // Let the fresh contour enter the hierarchy before animating its properties.
 await Task.yield();guard !Task.isCancelled else { return }
 withAnimation(.easeOut(duration:0.15)) { opacity=1 }
 if !reduceMotion { withAnimation(.linear(duration:1.4)) { phase=1 } }
 do { try await Task.sleep(for:.seconds(1.35)) } catch { return }
 guard !Task.isCancelled else { return }
 withAnimation(.easeOut(duration:0.55)) { opacity=0 }
 do { try await Task.sleep(for:.seconds(0.55)) } catch { return }
 guard !Task.isCancelled else { return }
 visible=false;animationTask=nil
 }
 }
 private func cancel() { animationTask?.cancel();animationTask=nil;visible=false;opacity=0 }
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
