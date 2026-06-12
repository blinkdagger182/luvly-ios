import Foundation

// Supabase Auth via REST (no SDK dependency).
// Stores credentials in AppStorage — call from any view that binds those keys.
struct ReelAuthService {

    struct AuthResult {
        let userID: UUID
        let accessToken: String
        let refreshToken: String
        let email: String
    }

    enum AuthError: LocalizedError {
        case invalidResponse
        case backend(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Something went wrong. Please try again."
            case .backend(let msg):
                return msg
            }
        }
    }

    private let base = URL(string: ReelBackendConfig.supabaseURL)!
    private let anonKey = ReelBackendConfig.supabaseAnonKey

    // MARK: – Sign Up

    func signUp(email: String, password: String) async throws -> AuthResult {
        let url = base.appending(path: "auth/v1/signup")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: req)
        return try parse(data: data, response: response, fallbackEmail: email)
    }

    // MARK: – Sign In

    func signIn(email: String, password: String) async throws -> AuthResult {
        var comps = URLComponents(url: base.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: req)
        return try parse(data: data, response: response, fallbackEmail: email)
    }

    // MARK: – Refresh

    func refresh(token: String) async throws -> AuthResult {
        var comps = URLComponents(url: base.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": token])
        let (data, response) = try await URLSession.shared.data(for: req)
        return try parse(data: data, response: response, fallbackEmail: "")
    }

    // MARK: – Sign Out

    func signOut(accessToken: String) async {
        guard let url = URL(string: ReelBackendConfig.supabaseURL + "/auth/v1/logout") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: – Private

    private func parse(data: Data, response: URLResponse, fallbackEmail: String) throws -> AuthResult {
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = json["error_description"] as? String
                ?? json["msg"] as? String
                ?? json["message"] as? String
                ?? "Authentication failed. Check your email and password."
            throw AuthError.backend(msg)
        }
        // Email confirmation required — Supabase returns 200 with no session
        if json["access_token"] == nil {
            throw AuthError.backend("Account created! Check your inbox to confirm your email, then sign in.")
        }
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let idStr = user["id"] as? String,
              let userID = UUID(uuidString: idStr) else {
            throw AuthError.invalidResponse
        }
        let email = (user["email"] as? String) ?? fallbackEmail
        return AuthResult(userID: userID, accessToken: access, refreshToken: refresh, email: email)
    }
}
