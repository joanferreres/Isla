import Foundation
public enum CalendarDay {
 public static func strip(containing date:Date,calendar:Calendar) -> [Date] {
 let start=calendar.startOfDay(for:date)
 return (-7...7).compactMap{calendar.date(byAdding:.day,value:$0,to:start)}
 }
 public static func events(on day:Date,from events:[CalendarEvent],calendar:Calendar) -> [CalendarEvent] {
 let range=interval(containing:day,calendar:calendar)
 return events.filter{$0.start < range.end && $0.end > range.start}
 }
 public static func interval(containing date:Date,calendar:Calendar) -> DateInterval { let start=calendar.startOfDay(for:date);return DateInterval(start:start,end:calendar.date(byAdding:.day,value:1,to:start)!) }
}
public struct CalendarEvent:Identifiable,Equatable,Sendable {
 public var id:String
 public var title:String
 public var start:Date
 public var end:Date
 public var allDay:Bool
 public var calendarID:String
 public var colorRGB:[Double]
 public init(id:String,title:String,start:Date,end:Date,allDay:Bool,calendarID:String,colorRGB:[Double]=[0.2,0.8,0.6]) { self.id=id;self.title=title;self.start=start;self.end=end;self.allDay=allDay;self.calendarID=calendarID;self.colorRGB=colorRGB }
}
