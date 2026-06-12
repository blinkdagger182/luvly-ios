import SwiftUI

// Persisted auth state — shared keys with ReelplayRootView
private enum AuthKeys {
    static let userID       = "reelplay.authUserID"
    static let accessToken  = "reelplay.authAccessToken"
    static let refreshToken = "reelplay.authRefreshToken"
    static let email        = "reelplay.authEmail"
}

// MARK: - Root Gate

/// Shown when the user is not authenticated.
/// Presents sign-up by default; the user can switch to sign-in.
struct ReelAuthRootView: View {
    @AppStorage(AuthKeys.userID)       private var authUserID      = ""
    @AppStorage(AuthKeys.accessToken)  private var accessToken     = ""
    @AppStorage(AuthKeys.refreshToken) private var refreshToken    = ""
    @AppStorage(AuthKeys.email)        private var authEmail       = ""
    @AppStorage("reelplay.socialHandle")      private var socialHandle      = ""
    @AppStorage("reelplay.socialDisplayName") private var socialDisplayName = ""
    @AppStorage("reelplay.socialProfileID")   private var socialProfileID   = ""

    @State private var mode: Mode = .landing

    enum Mode { case landing, signUp, signIn }

    var body: some View {
        ZStack {
            ReelAuthTheme.background.ignoresSafeArea()

            switch self.mode {
            case .landing:
                ReelAuthLandingView(
                    onSignUp: { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { self.mode = .signUp } },
                    onSignIn: { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { self.mode = .signIn } }
                )
            case .signUp:
                ReelSignUpView(
                    onSuccess: self.handleSuccess,
                    onBack: { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { self.mode = .landing } }
                )
            case .signIn:
                ReelSignInView(
                    onSuccess: self.handleSuccess,
                    onBack: { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { self.mode = .landing } }
                )
            }
        }
    }

    private func handleSuccess(_ result: ReelAuthService.AuthResult, handle: String, displayName: String) {
        self.authUserID      = result.userID.uuidString
        self.accessToken     = result.accessToken
        self.refreshToken    = result.refreshToken
        self.authEmail       = result.email
        self.socialProfileID = result.userID.uuidString
        self.socialHandle    = handle.isEmpty ? "user-\(result.userID.uuidString.prefix(8).lowercased())" : handle
        self.socialDisplayName = displayName.isEmpty ? "Reelplay User" : displayName
    }
}

// MARK: - Theme

private enum ReelAuthTheme {
    static let background  = Color(red: 0.969, green: 0.965, blue: 0.949)
    static let surface     = Color.white
    static let black       = Color(red: 0.059, green: 0.059, blue: 0.063)
    static let gold        = Color(red: 0.608, green: 0.478, blue: 0.271)
    static let muted       = Color.black.opacity(0.46)
    static let divider     = Color.black.opacity(0.08)
    static let fieldBg     = Color.white
}

// MARK: - Landing (onboarding carousel + auth buttons)

private struct ReelAuthLandingView: View {
    let onSignUp: () -> Void
    let onSignIn: () -> Void

    @State private var selectedPage   = 0
    @State private var buttonsVisible = false

    private let pages = ReelplayOnboardingPage.all

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ReelplayOnboardingCarousel()
                    .frame(height: min(max(proxy.size.height * 0.26, 190), 248))
                    .padding(.top, proxy.safeAreaInsets.top + 14)
                    .padding(.bottom, 4)

                TabView(selection: self.$selectedPage) {
                    ForEach(Array(self.pages.enumerated()), id: \.offset) { index, page in
                        ReelplayOnboardingPageView(page: page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity)

                ReelplayOnboardingDots(count: self.pages.count, selectedPage: self.selectedPage)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                VStack(spacing: 10) {
                    if self.selectedPage < self.pages.count - 1 {
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                self.selectedPage += 1
                            }
                        } label: {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(ReelAuthTheme.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button(action: self.onSignIn) {
                            Text("Sign in")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ReelAuthTheme.muted)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: self.onSignUp) {
                            Text("Create account")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(ReelAuthTheme.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button(action: self.onSignIn) {
                            Text("Already have an account? **Sign in**")
                                .font(.subheadline)
                                .foregroundStyle(ReelAuthTheme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(self.buttonsVisible ? 1 : 0)
                .offset(y: self.buttonsVisible ? 0 : 14)
                .padding(.horizontal, 28)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 8, 24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReelAuthTheme.background.ignoresSafeArea())
        }
        .onAppear {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.86).delay(0.3)) {
                self.buttonsVisible = true
            }
        }
    }
}

// MARK: - Sign Up (3 steps)

private struct ReelSignUpView: View {
    let onSuccess: (ReelAuthService.AuthResult, String, String) -> Void
    let onBack: () -> Void

    @State private var step        = 0          // 0 = profile, 1 = credentials
    @State private var handle      = ""
    @State private var displayName = ""
    @State private var email       = ""
    @State private var password    = ""
    @State private var confirm     = ""
    @State private var isLoading   = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Back + step indicator
            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ReelAuthTheme.black)
                        .frame(width: 40, height: 40)
                        .background(ReelAuthTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ReelAuthTheme.divider))
                }
                Spacer()
                Text("Step \(self.step + 1) of 2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReelAuthTheme.muted)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 28)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if self.step == 0 {
                        self.profileStep
                    } else {
                        self.credentialsStep
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
        .background(ReelAuthTheme.background.ignoresSafeArea())
    }

    // Step 0 — username + display name
    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create your profile")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ReelAuthTheme.black)
                Text("Choose a unique username. You can change this later.")
                    .font(.subheadline)
                    .foregroundStyle(ReelAuthTheme.muted)
            }

            VStack(spacing: 14) {
                AuthField(
                    label: "Username",
                    placeholder: "e.g. cooluser99",
                    text: self.$handle,
                    prefix: "@",
                    capitalization: .never,
                    autocorrect: false
                )
                AuthField(
                    label: "Display name",
                    placeholder: "Your name",
                    text: self.$displayName
                )
            }

            if let error = self.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button {
                let h = self.handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                guard !h.isEmpty else { self.error = "Username is required."; return }
                guard h.count >= 3 else { self.error = "Username must be at least 3 characters."; return }
                guard h.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
                    self.error = "Username can only contain letters, numbers, _ and ."; return
                }
                self.error = nil
                self.handle = h
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { self.step = 1 }
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(ReelAuthTheme.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // Step 1 — email + password
    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Secure your account")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ReelAuthTheme.black)
                Text("Your email and password let you sign in on any device.")
                    .font(.subheadline)
                    .foregroundStyle(ReelAuthTheme.muted)
            }

            VStack(spacing: 14) {
                AuthField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: self.$email,
                    keyboardType: .emailAddress,
                    capitalization: .never,
                    autocorrect: false
                )
                AuthField(
                    label: "Password",
                    placeholder: "At least 8 characters",
                    text: self.$password,
                    isSecure: true
                )
                AuthField(
                    label: "Confirm password",
                    placeholder: "Re-enter password",
                    text: self.$confirm,
                    isSecure: true
                )
            }

            if let error = self.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await self.submit() }
            } label: {
                ZStack {
                    Text("Create account")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(self.isLoading ? 0 : 1)
                    if self.isLoading { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(ReelAuthTheme.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(self.isLoading)
        }
    }

    private func submit() async {
        let trimEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimEmail.isEmpty else { self.error = "Email is required."; return }
        guard self.password.count >= 8 else { self.error = "Password must be at least 8 characters."; return }
        guard self.password == self.confirm else { self.error = "Passwords don't match."; return }
        self.error = nil
        self.isLoading = true
        defer { self.isLoading = false }

        do {
            let result = try await ReelAuthService().signUp(email: trimEmail, password: self.password)
            self.onSuccess(result, self.handle, self.displayName)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Sign In

private struct ReelSignInView: View {
    let onSuccess: (ReelAuthService.AuthResult, String, String) -> Void
    let onBack: () -> Void

    @State private var email     = ""
    @State private var password  = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ReelAuthTheme.black)
                        .frame(width: 40, height: 40)
                        .background(ReelAuthTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ReelAuthTheme.divider))
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 28)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome back")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(ReelAuthTheme.black)
                        Text("Sign in to access your library on any device.")
                            .font(.subheadline)
                            .foregroundStyle(ReelAuthTheme.muted)
                    }

                    VStack(spacing: 14) {
                        AuthField(
                            label: "Email",
                            placeholder: "you@example.com",
                            text: self.$email,
                            keyboardType: .emailAddress,
                            capitalization: .never,
                            autocorrect: false
                        )
                        AuthField(
                            label: "Password",
                            placeholder: "Your password",
                            text: self.$password,
                            isSecure: true
                        )
                    }

                    if let error = self.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button {
                        Task { await self.submit() }
                    } label: {
                        ZStack {
                            Text("Sign in")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(self.isLoading ? 0 : 1)
                            if self.isLoading { ProgressView().tint(.white) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(ReelAuthTheme.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(self.isLoading)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
        .background(ReelAuthTheme.background.ignoresSafeArea())
    }

    private func submit() async {
        let trimEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimEmail.isEmpty, !self.password.isEmpty else {
            self.error = "Please enter your email and password."
            return
        }
        self.error = nil
        self.isLoading = true
        defer { self.isLoading = false }

        do {
            let result = try await ReelAuthService().signIn(email: trimEmail, password: self.password)
            // On sign-in we don't change the stored handle/displayName — backend profile already exists
            self.onSuccess(result, "", "")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Shared field component

private struct AuthField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(self.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ReelAuthTheme.black)

            HStack(spacing: 4) {
                if let prefix = self.prefix {
                    Text(prefix)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ReelAuthTheme.muted)
                }
                Group {
                    if self.isSecure {
                        SecureField(self.placeholder, text: self.$text)
                    } else {
                        TextField(self.placeholder, text: self.$text)
                            .keyboardType(self.keyboardType)
                            .textInputAutocapitalization(self.capitalization)
                            .autocorrectionDisabled(!self.autocorrect)
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(ReelAuthTheme.fieldBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReelAuthTheme.divider, lineWidth: 1.5))
        }
    }
}
