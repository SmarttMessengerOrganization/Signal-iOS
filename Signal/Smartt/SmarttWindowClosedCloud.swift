import SignalServiceKit
import SignalUI

/// The purple cloud in the chat list's top bar, shown while the user's own communication window is
/// closed (frames 11 and 12 of the design). The iOS counterpart of Android's `SmarttWindowClosedCloud`.
/// It isn't a button: tapping it does nothing.
///
/// It re-checks when the windows change on the device, at the next start or end of a closed period
/// (a single timer, not a polling loop), when the app comes back to the foreground, and when the
/// clock or timezone changes. When the answer changes, it asks the chat list to rebuild its bar.
final class SmarttWindowClosedCloud: NSObject {
    static let shared = SmarttWindowClosedCloud()

    /// Smartt's purple, as in Android's `smartt_window_closed_cloud`.
    private static let purple = UIColor(red: 0x6B / 255.0, green: 0x2E / 255.0, blue: 0xE8 / 255.0, alpha: 1)

    private var isClosed = false
    private var timer: Timer?
    private var onChange: (() -> Void)?
    private var isObserving = false

    private override init() {}

    /// Called while the chat list builds its right bar items. Appends the cloud when the window is
    /// closed, and remembers `onChange` to rebuild the bar when that changes.
    func appendItem(to items: inout [UIBarButtonItem], onChange: @escaping () -> Void) {
        AssertIsOnMainThread()
        self.onChange = onChange
        startObservingIfNeeded()
        update(notify: false)
        if isClosed {
            items.append(makeItem())
        }
    }

    private func makeItem() -> UIBarButtonItem {
        let imageView = UIImageView(image: UIImage(systemName: "cloud.fill"))
        imageView.tintColor = Self.purple
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = OWSLocalizedString(
            "SMARTT_WINDOW_CLOSED_CLOUD",
            tableName: "Smartt",
            comment: "Accessibility label of the cloud in the chat list's top bar, shown while the user's own communication window is closed."
        )
        return UIBarButtonItem(customView: imageView)
    }

    private func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        for name: Notification.Name in [
            .smarttCommunicationWindowsDidChange,
            UIApplication.willEnterForegroundNotification,
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange,
        ] {
            center.addObserver(self, selector: #selector(somethingChanged), name: name, object: nil)
        }
    }

    @objc
    private func somethingChanged() {
        DispatchQueue.main.async { self.update(notify: true) }
    }

    private func update(notify: Bool) {
        AssertIsOnMainThread()
        let windows = SmarttCommunicationWindows.shared.windows()
        let now = Date()
        let calendar = Calendar.current
        let wasClosed = isClosed
        isClosed = Self.isClosed(windows, now: now, calendar: calendar)
        schedule(at: Self.nextChange(windows, now: now, calendar: calendar))
        if notify, isClosed != wasClosed {
            onChange?()
        }
    }

    private func schedule(at date: Date?) {
        timer?.invalidate()
        timer = nil
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.update(notify: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Closed state

    /// Closed when at least one switched-on window has a schedule active at `now`.
    static func isClosed(_ windows: [SmarttCommunicationWindow], now: Date, calendar: Calendar) -> Bool {
        return windows.contains { $0.isCurrentlyActive(now: now, calendar: calendar) }
    }

    /// The next moment after `now` at which `isClosed` may change, or nil when it never will (no
    /// switched-on schedule). Schedules are active by day and minute, so their state can only change
    /// at a start, at an end, or at midnight, when the day changes. Some of those moments change
    /// nothing (a start on a day the schedule is off); re-checking at them costs nothing.
    static func nextChange(_ windows: [SmarttCommunicationWindow], now: Date, calendar: Calendar) -> Date? {
        let boundaries = Set(
            windows.filter(\.enabled)
                .flatMap(\.schedules)
                .filter(\.enabled)
                .flatMap { [$0.start, $0.end] }
        )
        guard !boundaries.isEmpty, let startOfMinute = calendar.dateInterval(of: .minute, for: now)?.start else {
            return nil
        }
        let today = calendar.startOfDay(for: now)
        var candidates = [Date]()
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            for minute in boundaries.union([0]) {
                // Wall-clock times, so a daylight saving change doesn't shift the boundaries.
                if let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day), date > startOfMinute {
                    candidates.append(date)
                }
            }
        }
        return candidates.min()
    }
}
