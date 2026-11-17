import SignalServiceKit
import SignalUI

/// The banner a sender sees in a one-to-one chat while the recipient's communication window is
/// closed: a one-line banner like Signal's, and the recipient's expectations in an action sheet on
/// tap. The iOS counterpart of Android's `SmarttWindowBannerManager`.
@MainActor
enum SmarttWindowBanner {
    private struct Entry {
        let metadata: SmarttWindowMetadata?
        let fetchedAt: Date
    }

    /// The server's last answer per chat, so Signal's frequent banner rebuilds don't ask again.
    private static var entries = [String: Entry]()
    private static var fetchingThreadIds = Set<String>()
    private static let maxAge: TimeInterval = 60

    /// The banner, when the chat's recipient has a closed window. Asks the server when the last
    /// answer is missing or older than a minute, and calls `refresh` if the answer changed.
    static func banner(for thread: TSThread, refresh: @escaping () -> Void) -> UIView? {
        guard
            let contactThread = thread as? TSContactThread,
            !contactThread.isNoteToSelf,
            let serviceId = contactThread.contactAddress.serviceId
        else {
            return nil
        }
        let threadId = thread.uniqueId
        let entry = entries[threadId]
        let isStale = entry.map { -$0.fetchedAt.timeIntervalSinceNow > maxAge } ?? true
        if isStale, !fetchingThreadIds.contains(threadId) {
            fetchingThreadIds.insert(threadId)
            Task {
                let metadata: SmarttWindowMetadata?
                do {
                    metadata = try await SmarttCommunicationWindows.shared.windowMetadata(for: serviceId)
                } catch {
                    Logger.warn("Couldn't load the recipient's communication window: \(error)")
                    metadata = nil
                }
                fetchingThreadIds.remove(threadId)
                let changed = entries[threadId]?.metadata != metadata
                entries[threadId] = Entry(metadata: metadata, fetchedAt: Date())
                if changed {
                    refresh()
                }
            }
        }

        guard let metadata = entry?.metadata, metadata.windowActive else {
            return nil
        }
        let name = SSKEnvironment.shared.databaseStorageRef.read { tx in
            SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
        }
        let titleFormat = OWSLocalizedString(
            "SMARTT_WINDOW_BANNER_TITLE",
            tableName: "Smartt",
            comment: "Banner in a one-to-one chat while the recipient's communication window is closed. Embeds {{contact name}}, {{start time}} and {{end time}}."
        )
        let title = String(format: titleFormat, name, timeText(metadata.windowStartMinutes), timeText(metadata.windowEndMinutes))
        // Styled like Signal's `ConversationViewController.createBanner`, without its close icon.
        let banner = GestureView()
        banner.backgroundColor = .ows_accentBlue
        banner.addTap { showExpectations(metadata) }
        let label = UILabel()
        label.text = title
        label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        banner.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
        return banner
    }

    private static func showExpectations(_ metadata: SmarttWindowMetadata) {
        guard let expectations = metadata.expectations, !expectations.isEmpty else {
            return
        }
        var lines = [String]()
        if let checkFrequency = expectations.checkFrequency {
            let format = OWSLocalizedString(
                "SMARTT_WINDOW_BANNER_CHECK_FREQUENCY_FORMAT",
                tableName: "Smartt",
                comment: "How often the recipient checks messages, in the window banner's details. Embeds {{a frequency, e.g. 'once an hour'}}."
            )
            lines.append(String(format: format, text(for: checkFrequency)))
        }
        if let usualReplyTime = expectations.usualReplyTime {
            let format = OWSLocalizedString(
                "SMARTT_WINDOW_BANNER_REPLY_TIME_FORMAT",
                tableName: "Smartt",
                comment: "When the recipient usually replies, in the window banner's details. Embeds {{a time, e.g. 'in the afternoon'}}."
            )
            lines.append(String(format: format, text(for: usualReplyTime)))
        }
        if let personalNote = expectations.personalNote, !personalNote.isEmpty {
            let format = OWSLocalizedString(
                "SMARTT_WINDOW_BANNER_NOTE_FORMAT",
                tableName: "Smartt",
                comment: "The recipient's personal note, in the window banner's details. Embeds {{the note}}."
            )
            lines.append(String(format: format, personalNote))
        }
        OWSActionSheets.showActionSheet(title: metadata.windowName, message: lines.joined(separator: "\n"))
    }

    /// `minutes` since midnight, in the phone's time format.
    private static func timeText(_ minutes: Int) -> String {
        guard let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) else {
            return ""
        }
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private static func text(for checkFrequency: SmarttWindowExpectations.CheckFrequency) -> String {
        switch checkFrequency {
        case .everyFewMinutes:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_CHECK_EVERY_FEW_MINUTES", tableName: "Smartt", comment: "Check frequency in the window banner's details.")
        case .onceAnHour:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_CHECK_ONCE_AN_HOUR", tableName: "Smartt", comment: "Check frequency in the window banner's details.")
        case .everyFewHours:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_CHECK_EVERY_FEW_HOURS", tableName: "Smartt", comment: "Check frequency in the window banner's details.")
        case .onceADay:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_CHECK_ONCE_A_DAY", tableName: "Smartt", comment: "Check frequency in the window banner's details.")
        }
    }

    private static func text(for usualReplyTime: SmarttWindowExpectations.UsualReplyTime) -> String {
        switch usualReplyTime {
        case .withinMinutes:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_WITHIN_MINUTES", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        case .withinAnHour:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_WITHIN_AN_HOUR", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        case .inTheAfternoon:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_IN_THE_AFTERNOON", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        case .inTheEvening:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_IN_THE_EVENING", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        case .nextDay:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_NEXT_DAY", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        case .nextBusinessDay:
            return OWSLocalizedString("SMARTT_WINDOW_BANNER_REPLY_NEXT_BUSINESS_DAY", tableName: "Smartt", comment: "Usual reply time in the window banner's details.")
        }
    }
}
