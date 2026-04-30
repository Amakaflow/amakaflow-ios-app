import SwiftUI
import ClerkKitUI

/// Clerk-native authentication surface replacing the legacy pairing-code flow.
struct PairingView: View {
    var body: some View {
        AuthView(isDismissable: false)
    }
}

#Preview {
    PairingView()
}
