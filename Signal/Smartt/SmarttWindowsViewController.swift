import SignalServiceKit
import SignalUI

/// The user's communication windows in Signal's settings-style list, opened from the chat list's
/// window button. The iOS counterpart of Android's `CommunicationWindowSelectionFragment`.
final class SmarttWindowsViewController: OWSTableViewController2 {

    /// The chat list's button for this list, in place of Signal's camera button.
    static func chatListButton(presentingFrom viewController: UIViewController) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "squareshape.split.2x2"),
            primaryAction: UIAction { [weak viewController] _ in
                let navigationController = OWSNavigationController(rootViewController: SmarttWindowsViewController())
                viewController?.presentFormSheet(navigationController, animated: true)
            }
        )
        button.accessibilityLabel = titleText
        return button
    }

    private static var titleText: String {
        OWSLocalizedString("SMARTT_WINDOWS_TITLE", tableName: "Smartt", comment: "Title of the list of the user's communication windows, and label of the chat list button that opens it.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.titleText
        navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowsDidChange),
            name: .smarttCommunicationWindowsDidChange,
            object: nil
        )
        SmarttCommunicationWindows.shared.syncAll()
        updateTableContents()
    }

    @objc
    private func windowsDidChange() {
        updateTableContents()
    }

    private func updateTableContents() {
        let windows = SmarttCommunicationWindows.shared
        let (allWindows, pendingIds) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (windows.store.windows(tx: tx), Set(windows.store.windowsNeedingSync(tx: tx).map(\.windowId)))
        }

        let section = OWSTableSection()
        for window in allWindows {
            section.add(.item(
                name: window.emoji.isEmpty ? window.name : "\(window.emoji) \(window.name)",
                subtitle: summary(for: window, isSynced: !pendingIds.contains(window.windowId)),
                accessoryType: .disclosureIndicator
            ))
        }
        section.add(.actionItem(withText: OWSLocalizedString(
            "SMARTT_WINDOWS_NEW",
            tableName: "Smartt",
            comment: "Row at the end of the communication windows list that starts creating a new window."
        )))
        let contents = OWSTableContents()
        contents.add(section)
        self.contents = contents
    }

    /// "On · 9:00 until 17:00" and the days on a second line, like Android. Only the first schedule
    /// is shown, as on Android.
    private func summary(for window: SmarttCommunicationWindow, isSynced: Bool) -> String {
        var lines = [String]()
        let status = window.enabled
            ? OWSLocalizedString("SMARTT_WINDOWS_ON", tableName: "Smartt", comment: "A communication window is switched on.")
            : OWSLocalizedString("SMARTT_WINDOWS_OFF", tableName: "Smartt", comment: "A communication window is switched off.")
        if window.enabled, let schedule = window.schedules.first, schedule.enabled {
            let rangeFormat = OWSLocalizedString(
                "SMARTT_WINDOWS_TIME_RANGE_FORMAT",
                tableName: "Smartt",
                comment: "When a communication window's closed period runs. Embeds {{start time}} and {{end time}}."
            )
            let range = String(format: rangeFormat, SmarttWindowBanner.timeText(schedule.start), SmarttWindowBanner.timeText(schedule.end))
            lines.append("\(status) · \(range)")
            lines.append(daysText(schedule.daysEnabled))
        } else {
            lines.append(status)
        }
        if !isSynced {
            lines.append(OWSLocalizedString("SMARTT_WINDOWS_NOT_SYNCED", tableName: "Smartt", comment: "A communication window's latest change hasn't reached the server yet."))
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The days in the order of the user's week, or "Every day".
    private func daysText(_ isoDays: Set<Int>) -> String {
        if isoDays.count == 7 {
            return OWSLocalizedString("SMARTT_WINDOWS_EVERY_DAY", tableName: "Smartt", comment: "A communication window's closed period applies every day.")
        }
        let calendar = Calendar.current
        let names = (0..<7).compactMap { offset -> String? in
            // Calendar weekdays run 1 = Sunday … 7 = Saturday; the window uses ISO, 1 = Monday … 7 = Sunday.
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let isoDay = (weekday + 5) % 7 + 1
            return isoDays.contains(isoDay) ? calendar.shortWeekdaySymbols[weekday - 1] : nil
        }
        return names.joined(separator: ", ")
    }
}
