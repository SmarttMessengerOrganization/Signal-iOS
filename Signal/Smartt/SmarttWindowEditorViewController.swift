import LibSignalClient
import SignalServiceKit
import SignalUI

/// Creates a communication window. One form in Signal's settings style takes the place of Android's
/// wizard: name and emoji, the closed period, allowed contacts and calls, and expectations. As on
/// Android, a window has one schedule.
final class SmarttWindowEditorViewController: OWSTableViewController2 {
    private var draft = SmarttCommunicationWindow(schedules: [SmarttCommunicationWindowSchedule()])
    private let nameField = UITextField()
    private let noteField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = smarttString("SMARTT_WINDOWS_NEW", "Row at the end of the communication windows list that starts creating a new window.")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: smarttString("SMARTT_WINDOW_CREATE", "Button that saves a new communication window."),
            primaryAction: UIAction { [weak self] _ in self?.save() }
        )
        nameField.placeholder = smarttString("SMARTT_WINDOW_NAME_PLACEHOLDER", "Placeholder of the communication window's name field.")
        nameField.font = .dynamicTypeBody
        noteField.placeholder = smarttString("SMARTT_WINDOW_PERSONAL_NOTE", "Placeholder of the field for a note senders see while the window is closed.")
        noteField.font = .dynamicTypeBody
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        contents.add(nameSection())
        contents.add(scheduleSection())
        contents.add(allowedMessagesSection())
        contents.add(allowedCallsSection())
        contents.add(expectationsSection())
        self.contents = contents
    }

    // MARK: - Sections

    private func nameSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(.item(
            name: smarttString("SMARTT_WINDOW_EMOJI", "Row that picks the communication window's emoji."),
            accessoryText: draft.emoji.isEmpty ? noneText : draft.emoji,
            accessoryType: .disclosureIndicator,
            actionBlock: { [weak self] in self?.pickEmoji() }
        ))
        section.add(.textFieldItem(nameField))
        return section
    }

    private func scheduleSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = smarttString("SMARTT_WINDOW_SCHEDULE", "Header of the communication window's closed period.")
        section.footerTitle = smarttString("SMARTT_WINDOW_SCHEDULE_DESCRIPTION", "Explains the communication window's closed period.")
        let schedule = draft.schedules[0]
        section.add(.item(
            name: smarttString("SMARTT_WINDOW_START", "When the communication window's closed period starts."),
            accessoryContentView: timePicker(minutes: schedule.start) { [weak self] minutes in self?.draft.schedules[0].start = minutes }
        ))
        section.add(.item(
            name: smarttString("SMARTT_WINDOW_END", "When the communication window's closed period ends."),
            accessoryContentView: timePicker(minutes: schedule.end) { [weak self] minutes in self?.draft.schedules[0].end = minutes }
        ))
        let calendar = Calendar.current
        for offset in 0..<7 {
            // Calendar weekdays run 1 = Sunday … 7 = Saturday; the window uses ISO, 1 = Monday … 7 = Sunday.
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let isoDay = (weekday + 5) % 7 + 1
            section.add(.item(
                name: calendar.weekdaySymbols[weekday - 1],
                accessoryType: schedule.daysEnabled.contains(isoDay) ? .checkmark : .none,
                actionBlock: { [weak self] in self?.toggleDay(isoDay) }
            ))
        }
        return section
    }

    private func allowedMessagesSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = smarttString("SMARTT_WINDOW_ALLOWED_MESSAGES", "Header of the contacts whose messages go through while the window is closed.")
        section.footerTitle = smarttString("SMARTT_WINDOW_ALLOWED_MESSAGES_DESCRIPTION", "Explains the communication window's exception contacts.")
        let contacts = SSKEnvironment.shared.databaseStorageRef.read { tx in
            draft.exceptionContacts.compactMap { aciString -> (aci: String, name: String)? in
                guard let aci = Aci.parseFrom(aciString: aciString) else { return nil }
                let name = SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(aci), tx: tx).resolvedValue()
                return (aciString, name)
            }
        }
        for contact in contacts.sorted(by: { $0.name < $1.name }) {
            section.add(.item(name: contact.name, actionBlock: { [weak self] in self?.confirmRemoval(of: contact.aci, name: contact.name) }))
        }
        section.add(.actionItem(
            withText: smarttString("SMARTT_WINDOW_ADD_PEOPLE", "Row that adds exception contacts to a communication window."),
            actionBlock: { [weak self] in self?.addPeople() }
        ))
        return section
    }

    private func allowedCallsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = smarttString("SMARTT_WINDOW_ALLOWED_CALLS", "Header of the communication window's call settings.")
        section.add(.switch(
            withText: smarttString("SMARTT_WINDOW_CALLS_FROM_EXCEPTIONS", "Switch that allows calls from exception contacts while the window is closed."),
            isOn: { [weak self] in self?.draft.allowCallsFromExceptions ?? true },
            actionBlock: { [weak self] uiSwitch in self?.draft.allowCallsFromExceptions = uiSwitch.isOn }
        ))
        section.add(.switch(
            withText: smarttString("SMARTT_WINDOW_CALLS_FROM_ALL", "Switch that allows calls from everyone while the window is closed."),
            isOn: { [weak self] in self?.draft.allowCallsFromAll ?? true },
            actionBlock: { [weak self] uiSwitch in self?.draft.allowCallsFromAll = uiSwitch.isOn }
        ))
        return section
    }

    private func expectationsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = smarttString("SMARTT_WINDOW_EXPECTATIONS", "Header of what senders are told while the window is closed.")
        section.footerTitle = smarttString("SMARTT_WINDOW_EXPECTATIONS_DESCRIPTION", "Explains the communication window's expectations.")
        let expectations = draft.expectations
        section.add(.item(
            name: smarttString("SMARTT_WINDOW_CHECK_FREQUENCY", "Row that picks how often the user checks messages."),
            accessoryText: expectations.checkFrequency.map(Self.text(for:)) ?? noneText,
            accessoryType: .disclosureIndicator,
            actionBlock: { [weak self] in
                self?.choose(SmarttWindowExpectations.CheckFrequency.allCases, text: Self.text(for:)) { self?.draft.expectations.checkFrequency = $0 }
            }
        ))
        section.add(.item(
            name: smarttString("SMARTT_WINDOW_REPLY_TIME", "Row that picks when the user usually replies."),
            accessoryText: expectations.usualReplyTime.map(Self.text(for:)) ?? noneText,
            accessoryType: .disclosureIndicator,
            actionBlock: { [weak self] in
                self?.choose(SmarttWindowExpectations.UsualReplyTime.allCases, text: Self.text(for:)) { self?.draft.expectations.usualReplyTime = $0 }
            }
        ))
        section.add(.textFieldItem(noteField))
        return section
    }

    // MARK: - Actions

    private func timePicker(minutes: Int, onChange: @escaping (Int) -> Void) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        if let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) {
            picker.date = date
        }
        picker.addAction(UIAction { [weak picker] _ in
            guard let picker else { return }
            let components = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
            onChange((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }, for: .valueChanged)
        return picker
    }

    private func toggleDay(_ isoDay: Int) {
        if draft.schedules[0].daysEnabled.contains(isoDay) {
            draft.schedules[0].daysEnabled.remove(isoDay)
        } else {
            draft.schedules[0].daysEnabled.insert(isoDay)
        }
        updateTableContents()
    }

    /// Android's presets fill in the emoji, and the name when it's still empty.
    private func pickEmoji() {
        let presets: [(emoji: String, name: String)] = [
            ("💪", smarttString("SMARTT_WINDOW_PRESET_WORK", "Preset name for a communication window.")),
            ("😴", smarttString("SMARTT_WINDOW_PRESET_SLEEP", "Preset name for a communication window.")),
            ("📚", smarttString("SMARTT_WINDOW_PRESET_STUDY", "Preset name for a communication window.")),
            ("👨‍👩‍👧‍👦", smarttString("SMARTT_WINDOW_PRESET_FAMILY", "Preset name for a communication window.")),
            ("⛺", smarttString("SMARTT_WINDOW_PRESET_WEEKEND", "Preset name for a communication window.")),
            ("🏖️", smarttString("SMARTT_WINDOW_PRESET_HOLIDAYS", "Preset name for a communication window.")),
        ]
        let sheet = ActionSheetController(title: nil, message: nil)
        for preset in presets {
            sheet.addAction(ActionSheetAction(title: "\(preset.emoji) \(preset.name)") { [weak self] _ in
                guard let self else { return }
                self.draft.emoji = preset.emoji
                if (self.nameField.text ?? "").isEmpty {
                    self.nameField.text = preset.name
                }
                self.updateTableContents()
            })
        }
        sheet.addAction(ActionSheetAction(title: smarttString("SMARTT_WINDOW_OTHER_EMOJI", "Action that opens the full emoji picker.")) { [weak self] _ in
            let picker = EmojiPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] emoji in
                guard let self, let emoji else { return }
                self.draft.emoji = emoji.rawValue
                self.updateTableContents()
            }
            self?.present(picker, animated: true)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    private func addPeople() {
        let picker = SmarttContactPickerViewController()
        picker.title = smarttString("SMARTT_WINDOW_EXCEPTION_CONTACTS", "Title of the picker that adds exception contacts.")
        picker.onPick = { [weak self] aci in
            self?.draft.exceptionContacts.insert(aci.serviceIdString.lowercased())
            self?.updateTableContents()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func confirmRemoval(of aci: String, name: String) {
        let sheet = ActionSheetController(title: name, message: nil)
        sheet.addAction(ActionSheetAction(
            title: smarttString("SMARTT_WINDOW_REMOVE", "Action that removes a contact from the communication window's exceptions."),
            style: .destructive
        ) { [weak self] _ in
            self?.draft.exceptionContacts.remove(aci)
            self?.updateTableContents()
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    private func choose<Value>(_ values: [Value], text: (Value) -> String, set: @escaping (Value?) -> Void) {
        let sheet = ActionSheetController(title: nil, message: nil)
        for value in values {
            sheet.addAction(ActionSheetAction(title: text(value)) { [weak self] _ in
                set(value)
                self?.updateTableContents()
            })
        }
        sheet.addAction(ActionSheetAction(title: noneText) { [weak self] _ in
            set(nil)
            self?.updateTableContents()
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    private func save() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            OWSActionSheets.showErrorAlert(message: smarttString("SMARTT_WINDOW_NAME_REQUIRED", "Error when saving a communication window without a name."))
            return
        }
        guard !draft.schedules[0].daysEnabled.isEmpty else {
            OWSActionSheets.showErrorAlert(message: smarttString("SMARTT_WINDOW_DAYS_REQUIRED", "Error when saving a communication window without days."))
            return
        }
        draft.name = name
        let note = (noteField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft.expectations.personalNote = note.isEmpty ? nil : note
        let window = draft
        Task { [weak self] in
            await SmarttCommunicationWindows.shared.save(window)
            self?.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Strings

    private var noneText: String {
        smarttString("SMARTT_WINDOW_NONE", "No value chosen for an optional communication window setting.")
    }

    private static func text(for checkFrequency: SmarttWindowExpectations.CheckFrequency) -> String {
        switch checkFrequency {
        case .everyFewMinutes: return smarttString("SMARTT_WINDOW_CHECK_EVERY_FEW_MINUTES", "How often the user checks messages.")
        case .onceAnHour: return smarttString("SMARTT_WINDOW_CHECK_ONCE_AN_HOUR", "How often the user checks messages.")
        case .everyFewHours: return smarttString("SMARTT_WINDOW_CHECK_EVERY_FEW_HOURS", "How often the user checks messages.")
        case .onceADay: return smarttString("SMARTT_WINDOW_CHECK_ONCE_A_DAY", "How often the user checks messages.")
        }
    }

    private static func text(for usualReplyTime: SmarttWindowExpectations.UsualReplyTime) -> String {
        switch usualReplyTime {
        case .withinMinutes: return smarttString("SMARTT_WINDOW_REPLY_WITHIN_MINUTES", "When the user usually replies.")
        case .withinAnHour: return smarttString("SMARTT_WINDOW_REPLY_WITHIN_AN_HOUR", "When the user usually replies.")
        case .inTheAfternoon: return smarttString("SMARTT_WINDOW_REPLY_IN_THE_AFTERNOON", "When the user usually replies.")
        case .inTheEvening: return smarttString("SMARTT_WINDOW_REPLY_IN_THE_EVENING", "When the user usually replies.")
        case .nextDay: return smarttString("SMARTT_WINDOW_REPLY_NEXT_DAY", "When the user usually replies.")
        case .nextBusinessDay: return smarttString("SMARTT_WINDOW_REPLY_NEXT_BUSINESS_DAY", "When the user usually replies.")
        }
    }
}

/// A string from the `Smartt` table.
private func smarttString(_ key: String, _ comment: String) -> String {
    return OWSLocalizedString(key, tableName: "Smartt", comment: comment)
}

/// Signal's contact picker, the one behind "Add to block list", returning one contact's ACI.
private final class SmarttContactPickerViewController: RecipientPickerContainerViewController, RecipientPickerDelegate {
    var onPick: ((Aci) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        recipientPicker.groupsToShow = .noGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        selectionStyleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction
    ) -> UITableViewCell.SelectionStyle {
        return .default
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController, didSelectRecipient recipient: PickedRecipient) {
        guard let aci = recipient.address?.aci else { return }
        onPick?(aci)
        navigationController?.popViewController(animated: true)
    }

    var shouldShowQRCodeButton: Bool { false }

    func openUsernameQRCodeScanner() {}
}
