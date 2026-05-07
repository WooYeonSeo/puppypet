import Foundation

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let summary: String?
    let start: Date

    var title: String {
        let s = summary?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? "(제목 없음)" : s
    }
}

enum CalendarError: Error {
    case notConnected
    case requestFailed(Int, String)
}

final class CalendarService {
    private var tokens: GoogleTokens?

    init() {
        self.tokens = KeychainStore.loadTokens()
    }

    var isConnected: Bool { tokens != nil }

    func setTokens(_ tokens: GoogleTokens) {
        self.tokens = tokens
        try? KeychainStore.saveTokens(tokens)
    }

    func disconnect() {
        tokens = nil
        KeychainStore.deleteTokens()
    }

    /// 사용자가 켜놓은(selected) 모든 캘린더(primary + 구독한 것들)의 다음 N초 안 일정.
    func upcomingEvents(within seconds: TimeInterval = 3600) async throws -> [CalendarEvent] {
        let calendars = try await listSelectedCalendars()
        var all: [CalendarEvent] = []
        for cal in calendars {
            do {
                let events = try await fetchEvents(calendarId: cal.id, within: seconds)
                all.append(contentsOf: events)
            } catch {
                NSLog("[Calendar] \(cal.id) fetch failed: \(error)")
            }
        }
        return all.sorted { $0.start < $1.start }
    }

    /// `selected = true`인 캘린더만 (Google 캘린더 UI에서 체크박스 켜둔 것).
    private func listSelectedCalendars() async throws -> [CalendarListItem] {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1,
                                              String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return decoded.items.filter { $0.selected == true || $0.primary == true }
    }

    private func fetchEvents(calendarId: String, within seconds: TimeInterval) async throws -> [CalendarEvent] {
        let token = try await validAccessToken()
        let now = Date()
        let later = now.addingTimeInterval(seconds)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let encodedID = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: now)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: later)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "20")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CalendarError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1,
                                              String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(EventsListResponse.self, from: data)
        return decoded.items.compactMap { item in
            guard let dt = item.start.dateTime,
                  let start = formatter.date(from: dt) else { return nil }
            // 캘린더별로 같은 ID 충돌 방지 위해 calendarId prefix
            return CalendarEvent(id: "\(calendarId)::\(item.id)", summary: item.summary, start: start)
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw CalendarError.notConnected }
        if Date() >= current.expiresAt, let rt = current.refreshToken {
            let new = try await GoogleAuth.refresh(refreshToken: rt)
            self.tokens = new
            try? KeychainStore.saveTokens(new)
            return new.accessToken
        }
        return current.accessToken
    }

    private struct CalendarListResponse: Decodable {
        let items: [CalendarListItem]
    }

    private struct CalendarListItem: Decodable {
        let id: String
        let summary: String?
        let selected: Bool?
        let primary: Bool?
    }

    private struct EventsListResponse: Decodable {
        let items: [EventItem]
    }

    private struct EventItem: Decodable {
        let id: String
        let summary: String?
        let start: EventDateTime
    }

    private struct EventDateTime: Decodable {
        let dateTime: String?
        let date: String?
    }
}
