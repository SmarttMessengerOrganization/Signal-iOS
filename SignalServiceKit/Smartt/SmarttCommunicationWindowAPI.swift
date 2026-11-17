import Foundation
import LibSignalClient

/// Requests to our server's communication-window API, `/v1/smartt/communication-windows`. The iOS
/// counterpart of Android's `SmarttCommunicationWindowApi`. Signal's network manager adds the
/// account's credentials and sends over the chat connection when it's open.
struct SmarttCommunicationWindowAPI {
    private static let basePath = "v1/smartt/communication-windows"

    private var networkManager: NetworkManager { SSKEnvironment.shared.networkManagerRef }

    func listWindows() async throws -> [SmarttCommunicationWindow] {
        let request = TSRequest(url: URL(string: Self.basePath)!, method: "GET", parameters: nil)
        let response = try await networkManager.asyncRequest(request)
        return try decode([WindowDTO].self, from: response).map { $0.toModel() }
    }

    /// Creates or replaces the window: the server takes the device's window ID.
    func putWindow(_ window: SmarttCommunicationWindow) async throws {
        var request = TSRequest(
            url: URL(string: "\(Self.basePath)/\(window.windowId)")!,
            method: "PUT",
            body: .data(try JSONEncoder().encode(WindowRequestDTO(window)))
        )
        request.headers["Content-Type"] = "application/json"
        _ = try await networkManager.asyncRequest(request)
    }

    func deleteWindow(windowId: String) async throws {
        let request = TSRequest(url: URL(string: "\(Self.basePath)/\(windowId)")!, method: "DELETE", parameters: nil)
        do {
            _ = try await networkManager.asyncRequest(request)
        } catch where error.httpStatusCode == 404 {
            // Already gone.
        }
    }

    /// The window the recipient has active for us, if any.
    func windowMetadata(for recipient: ServiceId) async throws -> SmarttWindowMetadata {
        let request = TSRequest(
            url: URL(string: "\(Self.basePath)/metadata/\(recipient.serviceIdString)")!,
            method: "GET",
            parameters: nil
        )
        let response = try await networkManager.asyncRequest(request)
        return try decode(MetadataDTO.self, from: response).toModel()
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        guard let data = response.responseBodyData else {
            throw OWSAssertionError("Missing response body.")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Wire format
//
// Fields the server leaves out take Android's defaults, and unknown expectation values are dropped.

private struct WindowRequestDTO: Encodable {
    let name: String
    let emoji: String?
    let enabled: Bool
    let schedules: [ScheduleDTO]
    let exceptionContacts: [String]
    let allowCallsFromExceptions: Bool
    let allowCallsFromAll: Bool
    let expectations: ExpectationsDTO?

    init(_ window: SmarttCommunicationWindow) {
        name = window.name
        emoji = window.emoji
        enabled = window.enabled
        schedules = window.schedules.map { ScheduleDTO($0) }
        exceptionContacts = window.exceptionContacts.sorted()
        allowCallsFromExceptions = window.allowCallsFromExceptions
        allowCallsFromAll = window.allowCallsFromAll
        expectations = window.expectations.isEmpty ? nil : ExpectationsDTO(window.expectations)
    }
}

private struct WindowDTO: Decodable {
    let windowId: String
    let name: String?
    let emoji: String?
    let enabled: Bool?
    let schedules: [ScheduleDTO]?
    let exceptionContacts: [String]?
    let allowCallsFromExceptions: Bool?
    let allowCallsFromAll: Bool?
    let expectations: ExpectationsDTO?

    func toModel() -> SmarttCommunicationWindow {
        return SmarttCommunicationWindow(
            windowId: windowId,
            name: name ?? "",
            emoji: emoji ?? "",
            enabled: enabled ?? true,
            schedules: (schedules ?? []).map { $0.toModel() },
            exceptionContacts: Set(exceptionContacts ?? []),
            allowCallsFromExceptions: allowCallsFromExceptions ?? true,
            allowCallsFromAll: allowCallsFromAll ?? true,
            expectations: expectations?.toModel() ?? SmarttWindowExpectations()
        )
    }
}

private struct ScheduleDTO: Codable {
    let enabled: Bool?
    let start: Int?
    let end: Int?
    let daysEnabled: [Int]?

    init(_ schedule: SmarttCommunicationWindowSchedule) {
        enabled = schedule.enabled
        start = schedule.start
        end = schedule.end
        daysEnabled = schedule.daysEnabled.sorted()
    }

    func toModel() -> SmarttCommunicationWindowSchedule {
        let defaults = SmarttCommunicationWindowSchedule()
        return SmarttCommunicationWindowSchedule(
            enabled: enabled ?? defaults.enabled,
            start: start ?? defaults.start,
            end: end ?? defaults.end,
            daysEnabled: daysEnabled.map { Set($0) } ?? defaults.daysEnabled
        )
    }
}

private struct ExpectationsDTO: Codable {
    let checkFrequency: String?
    let usualReplyTime: String?
    let personalNote: String?

    init(_ expectations: SmarttWindowExpectations) {
        checkFrequency = expectations.checkFrequency?.rawValue
        usualReplyTime = expectations.usualReplyTime?.rawValue
        personalNote = expectations.personalNote
    }

    func toModel() -> SmarttWindowExpectations {
        return SmarttWindowExpectations(
            checkFrequency: checkFrequency.flatMap(SmarttWindowExpectations.CheckFrequency.init(rawValue:)),
            usualReplyTime: usualReplyTime.flatMap(SmarttWindowExpectations.UsualReplyTime.init(rawValue:)),
            personalNote: personalNote
        )
    }
}

private struct MetadataDTO: Decodable {
    let windowActive: Bool?
    let windowStartMinutes: Int?
    let windowEndMinutes: Int?
    let windowName: String?
    let expectations: ExpectationsDTO?

    func toModel() -> SmarttWindowMetadata {
        return SmarttWindowMetadata(
            windowActive: windowActive ?? false,
            windowStartMinutes: windowStartMinutes ?? 0,
            windowEndMinutes: windowEndMinutes ?? 0,
            windowName: windowName,
            expectations: expectations?.toModel()
        )
    }
}
