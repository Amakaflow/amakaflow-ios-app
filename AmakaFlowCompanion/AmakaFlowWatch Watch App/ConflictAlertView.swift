//
//  ConflictAlertView.swift
//  AmakaFlowWatch Watch App
//
//  Watch notification view when a training conflict is detected (AMA-1150)
//

import SwiftUI

struct ConflictAlertView: View {
    let conflict: ConflictAlert
    let onAdjust: () -> Void
    let onKeep: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(conflict.severity == .critical ? .red : .orange)

                // Title
                Text("Training Conflict")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(conflict.severity == .critical ? .red : .orange)

                // Message
                Text(conflict.message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 4)

                // Suggested action
                if let suggestion = conflict.suggestedAction {
                    Text(suggestion)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onAdjust()
                    } label: {
                        Text("Adjust")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conflict-adjust-button")

                    Button {
                        onKeep()
                    } label: {
                        Text("Keep")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conflict-keep-button")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .accessibilityIdentifier("conflict-alert-view")
    }
}
