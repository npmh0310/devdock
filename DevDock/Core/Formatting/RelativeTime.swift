import Foundation

nonisolated enum RelativeTime {
    /// "3h 53m", "3d 20h", "12m", "now".
    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        guard minutes > 0 else { return "now" }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// "just now", "12m ago", "3h 5m ago", "2d ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        guard minutes > 0 else { return "just now" }
        let (hours, mins) = (minutes / 60, minutes % 60)
        if hours >= 24 { return "\(hours / 24)d ago" }
        return hours > 0 ? "\(hours)h \(mins)m ago" : "\(mins)m ago"
    }

    /// "Updated just now", "Updated 5m ago".
    static func updated(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not updated yet" }
        let elapsed = now.timeIntervalSince(date)
        return elapsed < 60 ? "Updated just now" : "Updated \(shortDuration(elapsed)) ago"
    }

    /// When something happens, short: "15:21", "tomorrow 05:00", "Sun, 18 Oct 17:21".
    static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) \(time)"
    }
}
