import Foundation

enum SuzuriTimeLabel {
    static func string(from date: Date, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 60 * 60 {
            return "\(Int(elapsed / 60)) 分钟前"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(timeString(from: date, calendar: calendar))"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(timeString(from: date, calendar: calendar))"
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let year = dateComponents.year ?? calendar.component(.year, from: date)
        let month = dateComponents.month ?? calendar.component(.month, from: date)
        let day = dateComponents.day ?? calendar.component(.day, from: date)
        let nowYear = calendar.component(.year, from: now)
        if year == nowYear {
            return "\(month)月\(day)日"
        }
        return "\(year)年\(month)月\(day)日"
    }

    private static func timeString(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
