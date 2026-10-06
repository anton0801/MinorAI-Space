//
//  AuthGate.swift
//  Minor Ai
//
//  AI features (chat, building and changing maps) need an account. The gate shows the sign-in
//  screen when someone without one tries them, and carries on with what they were doing once
//  they have signed in.
//

import SwiftUI

@MainActor
final class AuthGate: ObservableObject {
    static let shared = AuthGate()

    @Published var isPresented = false
    private var pending: (() -> Void)?

    // Runs `action` now when signed in; otherwise asks to sign in first and runs it afterwards.
    func require(_ action: @escaping () -> Void) {
        if AuthService.shared.isSignedIn {
            action()
        } else {
            pending = action
            isPresented = true
        }
    }

    // The sign-in screen asks to close (signed in, or "Not Now").
    func close() {
        isPresented = false
    }

    // The sheet is gone (its onDismiss). The waiting action runs only if the person signed in,
    // now that nothing is closing: a consent sheet or a chat it opens would be dropped if it
    // were presented during the dismissal, which takes longer on iOS 26 than a fixed delay.
    func finish() {
        isPresented = false
        let action = pending
        pending = nil
        guard AuthService.shared.isSignedIn, let action else { return }
        action()
    }
}
