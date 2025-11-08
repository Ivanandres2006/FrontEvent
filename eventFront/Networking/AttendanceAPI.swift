import Foundation

enum AttendanceAPI {
    static func usersGoing(eventId: Int) async throws -> [UserSummaryDTO] {
        let req = APIConfig.authedRequest("/api/attendance/events/\(eventId)/going")
        return try await HTTPClient.shared.send(req, decode: [UserSummaryDTO].self)
    }

    static func eventsUserGoing(userId: Int) async throws -> [EventSummaryDTO] {
        let req = APIConfig.authedRequest("/api/attendance/users/\(userId)/going")
        return try await HTTPClient.shared.send(req, decode: [EventSummaryDTO].self)
    }
}
