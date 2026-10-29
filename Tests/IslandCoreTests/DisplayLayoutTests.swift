import XCTest
@testable import IslandCore
final class DisplayLayoutTests: XCTestCase {
 func testHoverOpensAtTopEdgeAndBelowPhysicalNotchWithoutMusic() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:1,frame:CGRect(x:0,y:0,width:1800,height:1169),notchWidth:220,headerHeight:38,builtIn:true),expandedWidth:600,expandedHeight:260)
 XCTAssertTrue(layout.containsHover(CGPoint(x:900,y:1169),expanded:false,sideWidth:0))
 XCTAssertTrue(layout.containsHover(CGPoint(x:900,y:1127),expanded:false,sideWidth:0))
 XCTAssertTrue(layout.containsHover(CGPoint(x:775,y:1150),expanded:false,sideWidth:0))
 XCTAssertFalse(layout.containsHover(CGPoint(x:600,y:1150),expanded:false,sideWidth:0))
 XCTAssertEqual(layout.visibleFrame(expanded:false,sideWidth:0).width,220)
 }
 func testExternalHoverUsesItsOwnScreenOrigin() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:2,frame:CGRect(x:1800,y:89,width:1920,height:1080),notchWidth:156,headerHeight:28,builtIn:false),expandedWidth:600,expandedHeight:260)
 XCTAssertTrue(layout.containsHover(CGPoint(x:2760,y:1169),expanded:false,sideWidth:0))
 XCTAssertFalse(layout.containsHover(CGPoint(x:900,y:1169),expanded:false,sideWidth:0))
 }

 func testNegativeOriginAndFixedContainer() {
 let metrics = DisplayMetrics(id:2,frame:CGRect(x:-1440,y:0,width:1440,height:900),notchWidth:196,headerHeight:28,builtIn:false)
 let layout = IslandLayout(metrics:metrics,expandedWidth:600,expandedHeight:340)
 XCTAssertEqual(layout.containerFrame.midX,-720)
 XCTAssertEqual(layout.visibleFrame(expanded:false).maxY,900)
 XCTAssertEqual(layout.visibleFrame(expanded:true).maxY,900)
 XCTAssertTrue(layout.containerFrame.contains(layout.visibleFrame(expanded:true)))
 }
 func testOldPreferencesMigrate() throws {
 let data = Data(#"{"hoverEnabled":true,"reduceMotion":false,"expandedWidth":640}"#.utf8)
 let value = try JSONDecoder().decode(Preferences.self,from:data)
 XCTAssertEqual(value.expandedWidth,640); XCTAssertTrue(value.showOnAllDisplays); XCTAssertFalse(value.lidEffectEnabled)
 }
 func testNarrowDisplayClamps() {
 let metrics = DisplayMetrics(id:3,frame:CGRect(x:0,y:100,width:400,height:600),notchWidth:196,headerHeight:28,builtIn:false)
 let layout = IslandLayout(metrics:metrics,expandedWidth:800,expandedHeight:340)
 XCTAssertLessThanOrEqual(layout.openSize.width,400)
 }
}
