import XCTest
@testable import IslandCore
final class CompactReminderTests:XCTestCase {
 let now=Date(timeIntervalSince1970:10000)
 func event(_ seconds:Double,allDay:Bool=false) -> CalendarEvent { CalendarEvent(id:"\(seconds)",title:"Evento",start:now.addingTimeInterval(seconds),end:now.addingTimeInterval(seconds+3600),allDay:allDay,calendarID:"test") }
 func testReminderOnlyDuringTenMinutesBeforeStart() {
 XCTAssertNotNil(CalendarReminderPolicy.reminder(in:[event(600)],at:now))
 XCTAssertNotNil(CalendarReminderPolicy.reminder(in:[event(1)],at:now))
 XCTAssertNil(CalendarReminderPolicy.reminder(in:[event(601)],at:now))
 XCTAssertNil(CalendarReminderPolicy.reminder(in:[event(0),event(-60),event(60,allDay:true)],at:now))
 }
 func testNextEventWinsAndUpdatesAtMinuteBoundary() {
 XCTAssertEqual(CalendarReminderPolicy.reminder(in:[event(500),event(125)],at:now)?.id,"125.0")
 XCTAssertEqual(CalendarReminderPolicy.nextUpdate(in:[event(125)],at:now),now.addingTimeInterval(5))
 XCTAssertEqual(CalendarReminderPolicy.nextUpdate(in:[event(900)],at:now),now.addingTimeInterval(300))
 }
 func testNoWingsAndMusicAndReminderWidths() {
 let layout=IslandLayout(metrics:DisplayMetrics(id:1,frame:CGRect(x:0,y:0,width:1800,height:1169),notchWidth:220,headerHeight:38,builtIn:true),expandedWidth:600,expandedHeight:260)
 XCTAssertEqual(layout.compactSize(sideWidth:0).width,220)
 XCTAssertEqual(layout.compactSize(sideWidth:36).width,292)
 XCTAssertEqual(layout.compactSize(sideWidth:104).width,428)
 XCTAssertEqual(layout.visibleFrame(expanded:false,sideWidth:0).width,220)
 }
}
