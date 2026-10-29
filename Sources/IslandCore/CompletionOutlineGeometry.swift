import Foundation
import CoreGraphics

public enum CompletionOutlineGeometry {
 public static func frame(container:CGSize,notchWidth:CGFloat,notchHeight:CGFloat,physicalNotch:Bool) -> CGRect {
 guard physicalNotch else { return CGRect(origin:.zero,size:container) }
 // A stroke inset inside the hardware bounds cannot be seen through the notch.
 let clearance:CGFloat=5
 let width=max(container.width,max(0,notchWidth))+2*clearance
 return CGRect(x:(container.width-width)/2,y:0,width:width,height:max(container.height,max(0,notchHeight))+clearance)
 }
}
