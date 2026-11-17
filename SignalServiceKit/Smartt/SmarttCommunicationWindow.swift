import Foundation

/// A communication window: closed periods during which our server holds incoming messages, except
/// those from exception contacts. The iOS counterpart of Android's `CommunicationWindow`.
public struct SmarttCommunicationWindow: Codable, Equatable {
    /// Created on the device; the server stores the window under this ID.
    public var windowId: String
    public var name: String
    public var emoji: String
    public var enabled: Bool
    public var schedules: [SmarttCommunicationWindowSchedule]
    /// ACIs (bare UUID strings) of the contacts whose messages always go through.
    public var exceptionContacts: Set<String>
    public var allowCallsFromExceptions: Bool
    public var allowCallsFromAll: Bool
    public var expectations: SmarttWindowExpectations

    public init(
        windowId: String = UUID().uuidString.lowercased(),
        name: String = "",
        emoji: String = "",
        enabled: Bool = true,
        schedules: [SmarttCommunicationWindowSchedule] = [],
        exceptionContacts: Set<String> = [],
        allowCallsFromExceptions: Bool = true,
        allowCallsFromAll: Bool = true,
        expectations: SmarttWindowExpectations = SmarttWindowExpectations()
    ) {
        self.windowId = windowId
        self.name = name
        self.emoji = emoji
        self.enabled = enabled
        self.schedules = schedules
        self.exceptionContacts = exceptionContacts
        self.allowCallsFromExceptions = allowCallsFromExceptions
        self.allowCallsFromAll = allowCallsFromAll
        self.expectations = expectations
    }

    public func isCurrentlyActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        return activeSchedule(now: now, calendar: calendar) != nil
    }

    public func activeSchedule(now: Date = Date(), calendar: Calendar = .current) -> SmarttCommunicationWindowSchedule? {
        guard enabled else { return nil }
        return schedules.first { $0.isActive(at: now, calendar: calendar) }
    }
}

/// One closed period of a window.
public struct SmarttCommunicationWindowSchedule: Codable, Equatable {
    public var enabled: Bool
    /// Minutes since midnight, 0–1439. When `end <= start`, the period runs past midnight.
    public var start: Int
    public var end: Int
    /// ISO weekdays: 1 = Monday … 7 = Sunday.
    public var daysEnabled: Set<Int>

    public init(
        enabled: Bool = true,
        start: Int = 9 * 60,
        end: Int = 17 * 60,
        daysEnabled: Set<Int> = [1, 2, 3, 4, 5]
    ) {
        self.enabled = enabled
        self.start = start
        self.end = end
        self.daysEnabled = daysEnabled
    }

    /// Like Android, the day is checked against the current day, also after midnight.
    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute else {
            return false
        }
        // Calendar counts 1 = Sunday … 7 = Saturday.
        let isoWeekday = (weekday + 5) % 7 + 1
        guard daysEnabled.contains(isoWeekday) else { return false }
        let minutes = hour * 60 + minute
        if end <= start {
            return minutes >= start || minutes < end
        }
        return minutes >= start && minutes < end
    }
}

/// What the window's owner tells senders to expect. The raw values are the server's.
public struct SmarttWindowExpectations: Codable, Equatable {
    public enum CheckFrequency: String, Codable, CaseIterable {
        case everyFewMinutes = "EVERY_FEW_MINUTES"
        case onceAnHour = "ONCE_AN_HOUR"
        case everyFewHours = "EVERY_FEW_HOURS"
        case onceADay = "ONCE_A_DAY"
    }

    public enum UsualReplyTime: String, Codable, CaseIterable {
        case withinMinutes = "WITHIN_MINUTES"
        case withinAnHour = "WITHIN_AN_HOUR"
        case inTheAfternoon = "IN_THE_AFTERNOON"
        case inTheEvening = "IN_THE_EVENING"
        case nextDay = "NEXT_DAY"
        case nextBusinessDay = "NEXT_BUSINESS_DAY"
    }

    public var checkFrequency: CheckFrequency?
    public var usualReplyTime: UsualReplyTime?
    public var personalNote: String?

    public init(
        checkFrequency: CheckFrequency? = nil,
        usualReplyTime: UsualReplyTime? = nil,
        personalNote: String? = nil
    ) {
        self.checkFrequency = checkFrequency
        self.usualReplyTime = usualReplyTime
        self.personalNote = personalNote
    }

    public var isEmpty: Bool {
        return checkFrequency == nil && usualReplyTime == nil && personalNote == nil
    }
}

/// A recipient's window as the server reports it to a sender.
public struct SmarttWindowMetadata: Equatable {
    public let windowActive: Bool
    public let windowStartMinutes: Int
    public let windowEndMinutes: Int
    public let windowName: String?
    public let expectations: SmarttWindowExpectations?
}
