import SwiftUI
import ClerkKitUI

/// Clerk-native authentication surface replacing the legacy pairing-code flow.
struct PairingView: View {
    @State private var mode: AuthView.Mode = .signIn

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Welcome to AmakaFlow")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Sign in or create an account to sync your workouts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Picker("Authentication mode", selection: $mode) {
                    Text("Sign in").tag(AuthView.Mode.signIn)
                    Text("Sign up").tag(AuthView.Mode.signUp)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                AuthView(mode: mode, isDismissable: false)
                    .id(mode.rawValue)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
        }
    }
}

#Preview {
    PairingView()
}
