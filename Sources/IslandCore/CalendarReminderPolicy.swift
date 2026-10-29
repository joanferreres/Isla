import Foundation
public enum CalendarReminderPolicy {
 private static func next(in events:[CalendarEvent],at now:Date) -> CalendarEvent? {
 events.filter{!$0.allDay && $0.start>now}.min{ $0.start == $1.start ? $0.id<$1.id : $0.start<$1.start }
 }
 public static func reminder(in events:[CalendarEvent],at now:Date) -> CalendarEvent? {
 guard let event=next(in:events,at:now),event.start.timeIntervalSince(now)<=600 else { return nil };return event
 }
 public static func nextUpdate(in events:[CalendarEvent],at now:Date) -> Date? {
 guard let event=next(in:events,at:now) else { return nil }
 let remaining=event.start.timeIntervalSince(now)
 if remaining>600 { return event.start.addingTimeInterval(-600) }
 let minute=remaining.truncatingRemainder(dividingBy:60)
 return now.addingTimeInterval(min(remaining,minute>0.01 ? minute : 60))
 }
}
