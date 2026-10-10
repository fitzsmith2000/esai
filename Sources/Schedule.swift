import Foundation

struct ScheduleZone: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let followsDST: Bool
    static let choices: [ScheduleZone] = [
        .init(id:"UTC",title:"UTC · 世界协调时间",shortTitle:"UTC",followsDST:false),
        .init(id:"America/Los_Angeles",title:"美西 · 洛杉矶",shortTitle:"美西",followsDST:true),
        .init(id:"America/New_York",title:"美东 · 纽约",shortTitle:"美东",followsDST:true),
        .init(id:"Europe/London",title:"英国 · 伦敦",shortTitle:"伦敦",followsDST:true),
        .init(id:"Asia/Shanghai",title:"中国 · 北京",shortTitle:"北京",followsDST:false),
        .init(id:"Asia/Tokyo",title:"日本 · 东京",shortTitle:"东京",followsDST:false)
    ]
}

struct DailySchedule: Codable, Equatable {
    var hour: Int
    var minute: Int
    var timeZoneID: String
    init(hour: Int = 10, minute: Int = 40, timeZoneID: String = "UTC") {
        self.hour = (0...23).contains(hour) ? hour : 10
        self.minute = (0...59).contains(minute) ? minute : 40
        self.timeZoneID = ScheduleZone.choices.contains { $0.id == timeZoneID } ? timeZoneID : "UTC"
    }
    private enum CodingKeys: String, CodingKey { case hour, minute, timeZoneID }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        let hour = try values.decode(Int.self,forKey:.hour)
        let minute = try values.decode(Int.self,forKey:.minute)
        let zone = try values.decode(String.self,forKey:.timeZoneID)
        guard (0...23).contains(hour), (0...59).contains(minute), ScheduleZone.choices.contains(where: { $0.id == zone }) else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid daily schedule"))
        }
        self.init(hour:hour,minute:minute,timeZoneID:zone)
    }
    var zone: ScheduleZone { ScheduleZone.choices.first { $0.id == timeZoneID } ?? ScheduleZone.choices[0] }
    var timeText: String { String(format:"%02d:%02d",hour,minute) }
    var calendar: Calendar {
        var value = Calendar(identifier:.gregorian)
        value.timeZone = TimeZone(identifier:timeZoneID)!
        return value
    }
    func slot(on date: Date) -> Date {
        let start = calendar.startOfDay(for:date)
        // A spring gap moves 02:30 to 03:30 for that day. A repeated fall hour uses its first occurrence.
        return calendar.nextDate(after:start.addingTimeInterval(-1),matching:DateComponents(hour:hour,minute:minute,second:0),matchingPolicy:.nextTimePreservingSmallerComponents,repeatedTimePolicy:.first)!
    }
    func next(after date: Date) -> Date {
        let today = slot(on:date)
        if today > date { return today }
        let tomorrow = calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:date))!
        return slot(on:tomorrow)
    }
    func cycleDuration(ending next: Date) -> TimeInterval {
        let previousDay = calendar.date(byAdding:.day,value:-1,to:calendar.startOfDay(for:next))!
        return next.timeIntervalSince(slot(on:previousDay))
    }
}

// Kept as the original default and for migration checks.
enum UTCSchedule {
    static var calendar: Calendar { DailySchedule().calendar }
    static func slot(on date: Date) -> Date { DailySchedule().slot(on:date) }
    static func next(after date: Date) -> Date { DailySchedule().next(after:date) }
}

struct ScheduleState: Codable {
    var enabled = false
    var nextDue: Date?
    var lastHandled: Date?
    var configuration = DailySchedule()
    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, nextDue, lastHandled, configuration }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self,forKey:.enabled) ?? false
        nextDue = try values.decodeIfPresent(Date.self,forKey:.nextDue)
        lastHandled = try values.decodeIfPresent(Date.self,forKey:.lastHandled)
        // Version 1.2 has no configuration: retain its fixed UTC 10:40 deadline and enabled state.
        configuration = try values.decodeIfPresent(DailySchedule.self,forKey:.configuration) ?? DailySchedule()
    }
    private func nextEligible(after now: Date) -> Date {
        let candidate = configuration.next(after:max(now,lastHandled ?? .distantPast))
        if let last = lastHandled, configuration.calendar.isDate(last,inSameDayAs:candidate) {
            return configuration.next(after:candidate)
        }
        return candidate
    }
    mutating func setEnabled(_ value: Bool, now: Date) {
        enabled = value
        nextDue = value ? nextEligible(after:now) : nil
    }
    mutating func setConfiguration(_ value: DailySchedule, now: Date) {
        guard value != configuration else { return }
        configuration = value
        // Saving never triggers an immediate kill or repeats an already handled local date.
        nextDue = enabled ? nextEligible(after:now) : nil
    }
    mutating func consume(now: Date) -> Date? {
        guard enabled else { return nil }
        guard let due = nextDue else {
            nextDue = nextEligible(after:now)
            return nil
        }
        guard now >= due else { return nil }
        let today = configuration.slot(on:now)
        nextDue = nextEligible(after:now)
        // Catch up only the current date in the selected scheduling zone.
        guard today <= now, today >= due, today > (lastHandled ?? .distantPast) else { return nil }
        if let last = lastHandled, configuration.calendar.isDate(last,inSameDayAs:today) { return nil }
        lastHandled = today
        return today
    }
}

enum WeChatIdentity {
    static let bundleID = "com.tencent.xinWeChat"
    static func matches(_ identifier: String?) -> Bool { identifier == bundleID }
}
