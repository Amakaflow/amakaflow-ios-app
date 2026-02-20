import SwiftUI

/// Spike debug view — shows live form classification and rep count.
/// Not production UI; used to validate the PoC end-to-end on hardware.
struct FormFeedbackDebugView: View {
    @StateObject private var engine = FormFeedbackEngine()

    var body: some View {
        VStack(spacing: 8) {
            Text("FORM FEEDBACK")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            if let result = engine.lastResult {
                Text(result.label.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(result.label == "good_form" ? .green : .orange)

                Text(String(format: "%.0f%% confidence", result.confidence * 100))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for rep...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("Reps: \(engine.repCount)")
                .font(.system(size: 12))

            Button(engine.isRunning ? "Stop" : "Start") {
                if engine.isRunning {
                    engine.stop()
                } else {
                    engine.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .green)
        }
        .padding()
    }
}
