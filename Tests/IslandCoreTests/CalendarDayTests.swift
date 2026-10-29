import XCTest
@testable import IslandCore
final class CalendarDayTests:XCTestCase {
 func testCivilDayCanHaveTwentyThreeHours() {
 var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Europe/Madrid")!
 let date=calendar.date(from:DateComponents(year:2026,month:3,day:29,hour:12))!
 let interval=CalendarDay.interval(containing:date,calendar:calendar)
 XCTAssertEqual(interval.duration,23*3600);XCTAssertTrue(interval.contains(date))
 }
}
extension CalendarDayTests {
 func testStripUsesFifteenCivilDaysAcrossDST() {
 var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Europe/Madrid")!
 let date=calendar.date(from:DateComponents(year:2026,month:3,day:29,hour:12))!
 let days=CalendarDay.strip(containing:date,calendar:calendar)
 XCTAssertEqual(days.count,15);XCTAssertEqual(days[7],calendar.startOfDay(for:date))
 XCTAssertEqual(calendar.dateComponents([.day],from:days.first!,to:days.last!).day,14)
 }
 func testMidnightEndDoesNotCreateAnotherDayDot() {
 let calendar=Calendar(identifier:.gregorian)
 let day=calendar.date(from:DateComponents(year:2026,month:10,day:6))!
 let end=calendar.date(byAdding:.day,value:1,to:day)!
 let event=CalendarEvent(id:"1",title:"All day",start:day,end:end,allDay:true,calendarID:"c")
 XCTAssertEqual(CalendarDay.events(on:day,from:[event],calendar:calendar).count,1)
 XCTAssertTrue(CalendarDay.events(on:end,from:[event],calendar:calendar).isEmpty)
 }
}
