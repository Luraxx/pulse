import Foundation
import CryptoKit

// MARK: - Konfiguration

/// Google-OAuth-Konfiguration für einen iOS-Client (keine Client-Secret nötig).
public struct GoogleOAuthConfig: Sendable {
    public var clientID: String

    public init(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// iOS-OAuth-Clients nutzen das umgedrehte Client-ID-Schema als Redirect:
    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    public var reversedClientScheme: String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let idPart = String(clientID.dropLast(suffix.count))
        guard !idPart.isEmpty else { return nil }
        return "com.googleusercontent.apps." + idPart
    }

    public var redirectURI: String? {
        reversedClientScheme.map { $0 + ":/oauth2redirect" }
    }

    public var isValid: Bool {
        reversedClientScheme != nil
    }
}

/// OAuth-Scopes der Google Health API (Read-only).
public enum HealthScopes {
    public static let read: [String] = [
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.profile.readonly",
    ]

    public static var scopeString: String {
        read.joined(separator: " ")
    }
}

// MARK: - PKCE

public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init() {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0..<32 {
            bytes.append(UInt8.random(in: 0...255, using: &generator))
        }
        self.init(verifier: PKCE.base64URL(Data(bytes)))
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token

public struct TokenSet: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiry: Date

    public init(accessToken: String, refreshToken: String?, expiry: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiry = expiry
    }

    public var isExpiringSoon: Bool {
        expiry.timeIntervalSinceNow < 120
    }
}

public enum AuthError: Error, LocalizedError, Sendable {
    case notConnected
    case invalidClientID
    case exchangeFailed(String)
    case refreshExpired
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Nicht mit Google verbunden."
        case .invalidClientID:
            return "Ungültige Client-ID. Erwartet wird eine iOS-Client-ID der Form …apps.googleusercontent.com."
        case .exchangeFailed(let message):
            return "Token-Austausch fehlgeschlagen: \(message)"
        case .refreshExpired:
            return "Die Google-Anmeldung ist abgelaufen (im Testing-Modus laufen Refresh-Tokens nach 7 Tagen ab). Bitte neu verbinden."
        case .network(let message):
            return "Netzwerkfehler: \(message)"
        }
    }
}

// MARK: - Auth-Engine

/// Verwaltet Google-OAuth-Tokens (Authorization Code + PKCE, ohne Client-Secret)
/// inklusive Keychain-Persistenz und automatischem Refresh.
public final class GoogleAuth: @unchecked Sendable {
    public static let keychainService = "net.dehlwes.pulse.oauth"
    private let keychainAccount = "google"
    private let session: URLSession
    private let usesKeychain: Bool
    private let lock = NSLock()
    private var _tokens: TokenSet?

    public init(session: URLSession = .shared, usesKeychain: Bool = true) {
        self.session = session
        self.usesKeychain = usesKeychain
        if usesKeychain,
           let data = Keychain.load(service: Self.keychainService, account: keychainAccount),
           let stored = try? Self.decoder.decode(TokenSet.self, from: data) {
            _tokens = stored
        }
    }

    public var tokens: TokenSet? {
        lock.lock()
        defer { lock.unlock() }
        return _tokens
    }

    public var isConnected: Bool {
        tokens != nil
    }

    // MARK: Autorisierungs-URL

    public func authorizationURL(config: GoogleOAuthConfig, pkce: PKCE, state: String) -> URL? {
        guard let redirect = config.redirectURI else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: HealthScopes.scopeString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    public static func extractCode(from url: URL, expectedState: String?) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        if let expectedState,
           items.first(where: { $0.name == "state" })?.value != expectedState {
            return nil
        }
        return items.first(where: { $0.name == "code" })?.value
    }

    // MARK: Token-Flüsse

    @discardableResult
    public func exchange(code: String, pkce: PKCE, config: GoogleOAuthConfig) async throws -> TokenSet {
        guard let redirect = config.redirectURI else { throw AuthError.invalidClientID }
        let response = try await tokenRequest([
            "client_id": config.clientID,
            "code": code,
            "code_verifier": pkce.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
        ])
        let tokens = TokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiry: Date().addingTimeInterval(response.expiresIn ?? 3600)
        )
        store(tokens)
        return tokens
    }

    /// Liefert ein gültiges Access-Token, refresht bei Bedarf.
    public func validAccessToken(config: GoogleOAuthConfig) async throws -> String {
        guard let current = tokens else { throw AuthError.notConnected }
        if current.isExpiringSoon {
            return try await refresh(config: config).accessToken
        }
        return current.accessToken
    }

    @discardableResult
    public func refresh(config: GoogleOAuthConfig) async throws -> TokenSet {
        guard let current = tokens, let refreshToken = current.refreshToken else {
            throw AuthError.refreshExpired
        }
        let response = try await tokenRequest([
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        let updated = TokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiry: Date().addingTimeInterval(response.expiresIn ?? 3600)
        )
        store(updated)
        return updated
    }

    public func disconnect() {
        lock.lock()
        _tokens = nil
        lock.unlock()
        if usesKeychain {
            Keychain.delete(service: Self.keychainService, account: keychainAccount)
        }
    }

    // MARK: Intern

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func store(_ tokens: TokenSet) {
        lock.lock()
        _tokens = tokens
        lock.unlock()
        if usesKeychain, let data = try? Self.encoder.encode(tokens) {
            Keychain.save(data, service: Self.keychainService, account: keychainAccount)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw AuthError.network("Ungültige Token-URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") {
                throw AuthError.refreshExpired
            }
            throw AuthError.exchangeFailed("HTTP \(http.statusCode): \(String(body.prefix(300)))")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.exchangeFailed("Antwort nicht lesbar: \(error.localizedDescription)")
        }
    }

    public static func formEncode(_ params: [String: String]) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .pulseFormAllowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }
}

private extension CharacterSet {
    static let pulseFormAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
