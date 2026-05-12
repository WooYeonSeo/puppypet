import Foundation
import AuthenticationServices
import AppKit
import CryptoKit

struct GoogleTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

enum GoogleAuthError: Error {
    case userCanceled
    case missingCode
    case invalidCallback
    case tokenExchangeFailed(String)
}

final class GoogleAuth: NSObject {
    static let clientID = "381258831743-ac4isn8gm4bbs12srd8ob343l0p1ol05.apps.googleusercontent.com"
    static let urlScheme = "com.googleusercontent.apps.381258831743-ac4isn8gm4bbs12srd8ob343l0p1ol05"
    static let redirectURI = "\(urlScheme):/oauth2redirect"
    // calendarList API도 사용하므로 calendar.readonly(읽기 전용 전체)가 필요.
    // events.readonly 만으로는 calendarList 조회 시 "insufficient permissions"
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"

    private var session: ASWebAuthenticationSession?
    private var presentationProvider: PresentationProvider?

    func authenticate() async throws -> GoogleTokens {
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.codeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        let authURL = components.url!

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let provider = PresentationProvider()
            self.presentationProvider = provider
            let s = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.urlScheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.userCanceled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: GoogleAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            s.presentationContextProvider = provider
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }

        guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleAuthError.missingCode
        }

        return try await Self.exchangeCode(code: code, codeVerifier: codeVerifier)
    }

    static func exchangeCode(code: String, codeVerifier: String) async throws -> GoogleTokens {
        let body: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        return try await postToken(body: body, fallbackRefreshToken: nil)
    }

    static func refresh(refreshToken: String) async throws -> GoogleTokens {
        let body: [String: String] = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        return try await postToken(body: body, fallbackRefreshToken: refreshToken)
    }

    private static func postToken(body: [String: String], fallbackRefreshToken: String?) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.tokenExchangeFailed(errBody)
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? fallbackRefreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expires_in - 60)
        )
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: TimeInterval
        let token_type: String?
        let scope: String?
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: verifier.data(using: .utf8)!)
        return Data(hash).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
