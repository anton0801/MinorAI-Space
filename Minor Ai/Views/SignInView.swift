//
//  SignInView.swift
//  Minor Ai
//
//  Sign in or create an account with email and password (sign-up and password reset use a
//  6-digit code from email), or with Apple. AI features need an account; "Not Now" keeps browsing.
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    var onFinish: () -> Void

    private enum Step: Equatable {
        case signIn, signUp, confirm, forgot, reset
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var rawNonce = AppleNonce.make()
    @State private var error: String?
    @State private var info: String?
    @State private var isWorking = false
    @State private var codeVerified = false   // reset: the code worked; only the password is left
    @State private var breathe = false
    @FocusState private var focused: Field?

    private enum Field { case email, password, code }

    private let theme = AppTheme(sphere: UserDefaults.standard.integer(forKey: "SelectedSphere"))

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var emailLooksValid: Bool {
        trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack {
                Spacer()
                Rectangle().fill(theme.blur).frame(height: 120).blur(radius: 50).opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(theme.glowSolid)
                            .frame(width: 130, height: 130)
                            .blur(radius: 30)
                            .opacity(breathe ? 0.4 : 0.22)
                        Image("logo").resizable().scaledToFit().frame(width: 84, height: 84)
                    }
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
                    }

                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .padding(.horizontal, 12)

                    if step == .signIn || step == .signUp {
                        modeSwitch.padding(.top, 24)
                    }

                    VStack(spacing: 12) {
                        fields
                        if let error {
                            message(error, color: MinorColor.dangerText)
                        } else if let info {
                            message(info, color: MinorColor.textSecondary)
                        }
                        primaryButton
                        secondaryActions
                    }
                    .padding(.top, 20)

                    if step == .signIn || step == .signUp {
                        HStack(spacing: 12) {
                            Rectangle().fill(MinorColor.divider).frame(height: 1)
                            Text("or").font(.system(size: 14)).foregroundColor(MinorColor.textTertiary)
                            Rectangle().fill(MinorColor.divider).frame(height: 1)
                        }
                        .padding(.vertical, 20)
                        .accessibilityHidden(true)

                        SignInWithAppleButton(.continue) { request in
                            rawNonce = AppleNonce.make()
                            request.requestedScopes = [.email]
                            request.nonce = AppleNonce.sha256(rawNonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(Capsule())
                        .disabled(isWorking)
                    }

                    Button("Not Now", action: onFinish)
                        .font(.system(size: 17))
                        .foregroundColor(MinorColor.textSecondary)
                        .frame(minHeight: 44)
                        .padding(.top, 12)

                    Text(LegalLinks.agreement)
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                        .tint(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundColor(MinorColor.textPrimary)
        .animation(.easeInOut(duration: 0.2), value: step)
        .onChange(of: step) { _ in
            error = nil
            code = ""
            codeVerified = false
        }
    }

    // MARK: - Parts

    private var title: String {
        switch step {
        case .signIn: return L("Welcome Back")
        case .signUp: return L("Create Your Account")
        case .confirm: return L("Check Your Email")
        case .forgot, .reset: return L("Reset Your Password")
        }
    }

    private var subtitle: String {
        switch step {
        case .signIn, .signUp:
            return L("Sign in to build mind maps and chat with AI. Your plan works on all your devices.")
        case .confirm:
            return L("We sent a 6-digit code to \(trimmedEmail). Enter it to finish creating your account.")
        case .forgot:
            return L("Enter your email and we’ll send you a code to set a new password.")
        case .reset:
            return L("Enter the code from the email sent to \(trimmedEmail) and choose a new password.")
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton(L("Sign In"), .signIn)
            modeButton(L("Create Account"), .signUp)
        }
        .padding(3)
        .background(Capsule().fill(MinorColor.track))
        .overlay(Capsule().stroke(MinorColor.divider, lineWidth: 1))
    }

    private func modeButton(_ title: String, _ target: Step) -> some View {
        Button {
            step = target
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(step == target ? MinorColor.textPrimary : MinorColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Capsule().fill(step == target ? Color.white.opacity(0.14) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(step == target ? .isSelected : [])
    }

    @ViewBuilder
    private var fields: some View {
        if step != .confirm && step != .reset {
            field {
                TextField("", text: $email)
                    .placeholder(when: email.isEmpty) { Text("Email").foregroundColor(theme.placeholderText) }
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(step == .forgot ? .send : .next)
                    .onSubmit { step == .forgot ? submit() : (focused = .password) }
                    .accessibilityLabel("Email")
            }
        }
        if step == .confirm || (step == .reset && !codeVerified) {
            field {
                TextField("", text: $code)
                    .placeholder(when: code.isEmpty) { Text("6-digit code").foregroundColor(theme.placeholderText) }
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focused, equals: .code)
                    .accessibilityLabel("Code from email")
                    .onChange(of: code) { value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { code = digits }
                        if digits.count == 6 && step == .confirm { submit() }
                    }
            }
        }
        if step == .signIn || step == .signUp || step == .reset {
            field {
                SecureField("", text: $password)
                    .placeholder(when: password.isEmpty) {
                        Text(step == .signIn ? "Password" : "New password (8+ characters)").foregroundColor(theme.placeholderText)
                    }
                    .textContentType(step == .signIn ? .password : .newPassword)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .accessibilityLabel(step == .signIn ? "Password" : "New password")
            }
            if step != .signIn { passwordChecklist }
        }
    }

    // What the server will accept, ticked off while typing.
    private var passwordChecklist: some View {
        let check = PasswordRules.check(password)
        let foreignLetters = !check.latinLetter && password.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                rule(L("8+ characters"), check.length)
                rule(L("A–Z letter"), check.latinLetter)
                rule(L("Digit"), check.digit)
            }
            if foreignLetters {
                Text("Only Latin letters count: switch the keyboard to English.")
                    .foregroundColor(Color(hex: "#FFD66B"))
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func rule(_ text: String, _ ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundColor(ok ? MinorColor.accent : MinorColor.textTertiary)
            Text(text).foregroundColor(ok ? MinorColor.textPrimary : MinorColor.textSecondary)
        }
        .accessibilityLabel(ok ? L("\(text): done") : text)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        switch step {
        case .signIn: return L("Sign In")
        case .signUp: return L("Create Account")
        case .confirm: return L("Confirm")
        case .forgot: return L("Send Code")
        case .reset: return L("Set New Password")
        }
    }

    private var canSubmit: Bool {
        switch step {
        case .signIn: return emailLooksValid && !password.isEmpty
        case .signUp: return emailLooksValid && PasswordRules.problem(in: password) == nil
        case .confirm: return code.count == 6
        case .forgot: return emailLooksValid
        case .reset: return (codeVerified || code.count == 6) && PasswordRules.problem(in: password) == nil
        }
    }

    private var primaryButton: some View {
        Button(action: submit) {
            ZStack {
                Text(primaryTitle).opacity(isWorking ? 0 : 1)
                if isWorking { ProgressView().tint(.black) }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(MinorColor.sendFill))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isWorking)
        .opacity(canSubmit || isWorking ? 1 : 0.5)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        switch step {
        case .signIn:
            Button("Forgot password?") { step = .forgot }
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .frame(minHeight: 44)
        case .confirm:
            HStack(spacing: 20) {
                Button("Send the code again") { resendCode() }
                Button("Change email") { step = .signUp }
            }
            .font(.system(size: 15))
            .foregroundColor(MinorColor.textSecondary)
            .frame(minHeight: 44)
            .disabled(isWorking)
        case .forgot, .reset:
            Button("Back to Sign In") { step = .signIn }
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .frame(minHeight: 44)
        case .signUp:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit, !isWorking else { return }
        focused = nil
        error = nil
        info = nil
        isWorking = true
        let auth = AuthService.shared
        Task {
            defer { isWorking = false }
            do {
                switch step {
                case .signIn:
                    try await auth.signIn(email: trimmedEmail, password: password)
                    await didSignIn()
                case .signUp:
                    switch try await auth.signUp(email: trimmedEmail, password: password) {
                    case .signedIn: await didSignIn()
                    case .needsCode:
                        step = .confirm
                        focused = .code
                    }
                case .confirm:
                    try await auth.verifySignUp(email: trimmedEmail, code: code)
                    await didSignIn()
                case .forgot:
                    try await auth.sendPasswordReset(email: trimmedEmail)
                    password = ""
                    step = .reset
                    focused = .code
                case .reset:
                    if !codeVerified {
                        try await auth.verifyPasswordReset(email: trimmedEmail, code: code)
                        codeVerified = true
                        info = L("Code confirmed. Now set the new password.")
                    }
                    try await auth.updatePassword(password)
                    await didSignIn()
                }
            } catch AuthError.emailNotConfirmed {
                // Signed up earlier but never confirmed: send a fresh code and ask for it.
                try? await auth.resendSignUpCode(email: trimmedEmail)
                step = .confirm
                info = L("Confirm your email first: enter the code we sent you.")
            } catch {
                Haptics.error()
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
                UIAccessibility.post(notification: .announcement, argument: self.error)
            }
        }
    }

    private func resendCode() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await AuthService.shared.resendSignUpCode(email: trimmedEmail)
                error = nil
                info = L("We sent a new code.")
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
            }
        }
    }

    // A purchase made before signing in is linked to the new account here.
    private func didSignIn() async {
        Haptics.success()
        await SubscriptionStore.shared.refreshEntitlements()
        await AccountStore.shared.refresh()
        onFinish()
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code != .canceled {
                error = L("Couldn’t sign in with Apple. Try again.")
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                error = L("Couldn’t sign in with Apple. Try again.")
                return
            }
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                    try await AuthService.shared.signInWithApple(idToken: idToken, rawNonce: rawNonce, authorizationCode: code)
                    await didSignIn()
                } catch {
                    self.error = (error as? BackendError) == .offline
                        ? BackendError.offline.errorDescription
                        : L("Couldn’t sign in with Apple. Try again.")
                }
            }
        }
    }
}
