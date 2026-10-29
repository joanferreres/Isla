import XCTest
@testable import IslandCore
final class NotchActivationTests:XCTestCase {
 func testSystemRoutedClickInsidePhysicalNotchOpensWithoutTakingSideMenus() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:1,frame:CGRect(x:0,y:0,width:1800,height:1169),notchWidth:220,headerHeight:38,builtIn:true),expandedWidth:640,expandedHeight:205)
 XCTAssertTrue(layout.containsGlobalActivation(CGPoint(x:900,y:1149),physicalNotch:true,sideWidth:0))
 XCTAssertTrue(layout.containsGlobalActivation(CGPoint(x:900,y:1169),physicalNotch:true,sideWidth:0))
 XCTAssertFalse(layout.containsGlobalActivation(CGPoint(x:1030,y:1149),physicalNotch:true,sideWidth:0))
 XCTAssertFalse(layout.containsGlobalActivation(CGPoint(x:900,y:1149),physicalNotch:false,sideWidth:0))
 XCTAssertTrue(layout.containsGlobalActivation(CGPoint(x:900,y:1110),physicalNotch:false,sideWidth:0))
 XCTAssertFalse(layout.containsGlobalActivation(CGPoint(x:900,y:1080),physicalNotch:true,sideWidth:0))
 }
 func testClickAreaIncludesSpaceBelowHardwareNotch() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:1,frame:CGRect(x:0,y:0,width:1800,height:1169),notchWidth:220,headerHeight:38,builtIn:true),expandedWidth:640,expandedHeight:205)
 XCTAssertTrue(layout.containsHover(CGPoint(x:900,y:1169-38-26),expanded:false,sideWidth:0))
 XCTAssertFalse(layout.containsHover(CGPoint(x:900,y:1169-38-40),expanded:false,sideWidth:0))
 XCTAssertFalse(layout.containsHover(CGPoint(x:500,y:1169-50),expanded:false,sideWidth:0))
 }
 func testCompactWindowCoversOnlyItsActivationAreaOnExternalDisplay() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:2,frame:CGRect(x:-1920,y:100,width:1920,height:1080),notchWidth:156,headerHeight:28,builtIn:false),expandedWidth:640,expandedHeight:205)
 let frame=layout.windowFrame(expanded:false,sideWidth:0)
 XCTAssertEqual(frame.height,60);XCTAssertEqual(frame.width,228);XCTAssertEqual(frame.maxY,1180)
 XCTAssertTrue(layout.containsHover(CGPoint(x:frame.midX,y:frame.minY+1),expanded:false,sideWidth:0))
 XCTAssertFalse(frame.contains(CGPoint(x:frame.midX,y:frame.minY-1)))
 XCTAssertEqual(layout.windowFrame(expanded:true,sideWidth:0),layout.containerFrame)
 }
}
