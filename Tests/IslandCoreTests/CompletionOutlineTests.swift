import XCTest
@testable import IslandCore

final class CompletionOutlineTests:XCTestCase {
 func testPhysicalNotchRailHasVisibleClearanceOnSidesAndBottom() {
 let frame=CompletionOutlineGeometry.frame(container:CGSize(width:268,height:32),notchWidth:196,notchHeight:32,physicalNotch:true)
 let hardware=CGRect(x:36,y:0,width:196,height:32)
 XCTAssertLessThan(frame.minX+2,hardware.minX)
 XCTAssertGreaterThan(frame.maxX-2,hardware.maxX)
 XCTAssertGreaterThan(frame.maxY-2,hardware.maxY)
 }
 func testExpandedRailSurroundsBothHardwareAndOurPanel() {
 let frame=CompletionOutlineGeometry.frame(container:CGSize(width:600,height:260),notchWidth:196,notchHeight:32,physicalNotch:true)
 XCTAssertEqual(frame.midX,300)
 XCTAssertEqual(frame.width,610)
 XCTAssertEqual(frame.height,265)
 }
 func testExternalDisplayUsesIslandBoundary() {
 let size=CGSize(width:228,height:28)
 XCTAssertEqual(CompletionOutlineGeometry.frame(container:size,notchWidth:156,notchHeight:28,physicalNotch:false),CGRect(origin:.zero,size:size))
 }
}
