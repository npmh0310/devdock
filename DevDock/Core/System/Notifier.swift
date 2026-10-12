import Foundation
import UserNotifications

/// Thin wrapper over macOS notifications: post now, schedule for later, cancel.
enum Notifier {
    private static var center: UNUserNotificationCenter { .current() }

    /// Asks once; macOS remembers the answer.
    static func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(id: String, title: String, body: String) {
        center.add(request(id: id, title: title, body: body, trigger: nil))
    }

    /// Replaces any pending notification with the same id.
    static func schedule(id: String, at date: Date, title: String, body: String) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(request(id: id, title: title, body: body, trigger: trigger))
    }

    /// Cancels pending notifications whose id starts with `prefix`, except `keeping`.
    static func cancelPending(prefix: String, keeping: Set<String>) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && !keeping.contains($0) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func request(id: String, title: String, body: String, trigger: UNNotificationTrigger?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
