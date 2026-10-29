import Foundation
import CoreGraphics
public struct DisplayMetrics: Equatable {
 public var id: UInt32
 public var frame: CGRect
 public var notchWidth: CGFloat
 public var headerHeight: CGFloat
 public var builtIn: Bool
 public init(id: UInt32, frame: CGRect, notchWidth: CGFloat, headerHeight: CGFloat, builtIn: Bool) { self.id=id; self.frame=frame; self.notchWidth=notchWidth; self.headerHeight=headerHeight; self.builtIn=builtIn }
}
public struct IslandLayout {
 public let metrics: DisplayMetrics
 public let openSize: CGSize
 public var closedSize: CGSize { CGSize(width:min(metrics.frame.width,metrics.notchWidth+72),height:metrics.headerHeight) }
 public func compactSize(sideWidth:CGFloat) -> CGSize { CGSize(width:min(metrics.frame.width,metrics.notchWidth+2*max(0,sideWidth)),height:metrics.headerHeight) }
 public var containerFrame: CGRect { CGRect(x:metrics.frame.midX-openSize.width/2-20,y:metrics.frame.maxY-openSize.height-20,width:openSize.width+40,height:openSize.height+20) }
 public init(metrics:DisplayMetrics,expandedWidth:CGFloat,expandedHeight:CGFloat) { self.metrics=metrics; openSize=CGSize(width:min(metrics.frame.width,max(240,expandedWidth)),height:min(metrics.frame.height,expandedHeight)) }
 public func windowFrame(expanded:Bool,sideWidth:CGFloat) -> CGRect {
 if expanded { return containerFrame }
 let width=min(metrics.frame.width,max(closedSize.width,compactSize(sideWidth:sideWidth).width))
 let height=metrics.headerHeight+32
 return CGRect(x:metrics.frame.midX-width/2,y:metrics.frame.maxY-height,width:width,height:height)
 }
 public func containsHover(_ point:CGPoint,expanded:Bool,sideWidth:CGFloat) -> Bool {
 let visible=visibleFrame(expanded:expanded,sideWidth:sideWidth)
 let width=expanded ? visible.width : min(metrics.frame.width,max(closedSize.width,visible.width))
 let frame=expanded ? CGRect(x:metrics.frame.midX-width/2,y:visible.minY,width:width,height:visible.height) : windowFrame(expanded:false,sideWidth:sideWidth)
 // The cursor reaches maxY at the screen edge; CGRect.contains excludes that edge.
 return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
 }
 // Recover clicks taken by the system menu bar only inside the physical camera housing.
 public func containsGlobalActivation(_ point:CGPoint,physicalNotch:Bool,sideWidth:CGFloat) -> Bool {
 guard containsHover(point,expanded:false,sideWidth:sideWidth) else { return false }
 if point.y < metrics.frame.maxY-metrics.headerHeight { return true }
 return physicalNotch && abs(point.x-metrics.frame.midX) <= metrics.notchWidth/2
 }
 public func visibleFrame(expanded:Bool,sideWidth:CGFloat=36) -> CGRect { let size=expanded ? openSize : compactSize(sideWidth:sideWidth); return CGRect(x:metrics.frame.midX-size.width/2,y:metrics.frame.maxY-size.height,width:size.width,height:size.height) }
}
