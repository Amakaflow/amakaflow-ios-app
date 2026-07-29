// GarminDeliveryLab.swift
// AMA-2342 Layer B — DEBUG Send-to-Garmin ladder for simulator/device.
// Simulates the companion steps: push → status → openApp (correct CIQ UUID).
// Does not download FIT onto the watch (that is CIQ Layer C).

import Foundation
import SwiftUI

#if DEBUG

struct GarminDeliveryLabStep: Identifiable, Equatable {
    enum Status: String {
        case pending, running, pass, fail, skip, mock
    }

    let id: String
    var title: String
    var status: Status
    var detail: String
}

@MainActor
final class GarminDeliveryLabViewModel: ObservableObject {
    @Published var workoutId: String = ""
    @Published var gymTitle: String = "AMA-2342 Lab Workout"
    @Published var steps: [GarminDeliveryLabStep] = [
        .init(id: "uuid", title: "CIQ app UUID matches widget", status: .pending, detail: ""),
        .init(id: "push", title: "POST watch-delivery push", status: .pending, detail: ""),
        .init(id: "status", title: "GET watch-delivery status", status: .pending, detail: ""),
        .init(id: "wake", title: "openAppRequest (wake widget)", status: .pending, detail: ""),
    ]
    @Published var lastMessage: String = "Paste a workout id and Run ladder."

    private let expectedCIQUUID = GarminCIQAppIdentity.appUUID.uuidString

    func runLadder(
        api: APIServiceProviding = AppDependencies.current.apiService,
        garmin: GarminConnectManager = .shared
    ) async {
        let trimmed = workoutId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastMessage = "Workout id required"
            return
        }
        guard UUID(uuidString: trimmed) != nil else {
            lastMessage = "Workout id must be a UUID"
            return
        }
        let wid = trimmed

        // 1) UUID
        update(id: "uuid", status: .running, detail: "Checking…")
        let status = garmin.getDetailedStatus()
        let appUUID = (status["appUUID"] as? String)?.lowercased() ?? ""
        if appUUID == expectedCIQUUID.lowercased() {
            update(id: "uuid", status: .pass, detail: appUUID)
        } else {
            update(
                id: "uuid",
                status: .fail,
                detail: "app=\(appUUID) expected=\(expectedCIQUUID)"
            )
        }

        // 2) Push
        update(id: "push", status: .running, detail: "Pushing…")
        #if targetEnvironment(simulator)
        // Simulator often has no Clerk session — allow mock pass for UI wiring.
        if ProcessInfo.processInfo.environment["GARMIN_LAB_FORCE_MOCK"] == "1" {
            update(id: "push", status: .mock, detail: "Simulator mock push")
            update(id: "status", status: .mock, detail: "Simulator mock status=pushed")
            update(id: "wake", status: .skip, detail: "No BLE openApp on simulator")
            lastMessage = "MOCK ladder complete (simulator)"
            return
        }
        #endif

        let result = await GarminStartHandoffService(apiService: api).push(
            workoutId: wid,
            gymTitle: gymTitle
        )
        if result.kind == .failed {
            update(id: "push", status: .fail, detail: result.message)
            update(id: "status", status: .skip, detail: "Skipped after push fail")
            update(id: "wake", status: .skip, detail: "Skipped after push fail")
            lastMessage = result.message
            return
        }
        update(id: "push", status: .pass, detail: result.message)

        // 3) Status enrich
        update(id: "status", status: .running, detail: "Fetching…")
        do {
            let st = try await api.watchDeliveryStatus(workoutId: wid)
            update(id: "status", status: .pass, detail: "state=\(String(describing: st.state))")
        } catch {
            update(id: "status", status: .fail, detail: error.localizedDescription)
        }

        // 4) Wake widget
        update(id: "wake", status: .running, detail: "openAppRequest…")
        #if targetEnvironment(simulator)
        update(id: "wake", status: .skip, detail: "Simulator has no GCM BLE bridge")
        #else
        garmin.sendOpenAppRequest()
        update(id: "wake", status: .pass, detail: "openAppRequest sent (check watch)")
        #endif

        lastMessage = "Ladder finished — check steps. Watch FIT is Layer C."
    }

    private func update(id: String, status: GarminDeliveryLabStep.Status, detail: String) {
        guard let idx = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[idx].status = status
        steps[idx].detail = detail
    }
}

struct GarminDeliveryLabView: View {
    @StateObject private var vm = GarminDeliveryLabViewModel()

    var body: some View {
        Form {
            Section("AMA-2342 Layer B") {
                Text("What we're testing: Companion push + correct CIQ UUID + optional wake. Not watch FIT download.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Workout id (UUID)", text: $vm.workoutId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Gym title", text: $vm.gymTitle)
                Button("Run Send-to-Garmin ladder") {
                    Task { await vm.runLadder() }
                }
                Text(vm.lastMessage)
                    .font(.footnote)
            }
            Section("Steps") {
                ForEach(vm.steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(step.title)
                            Spacer()
                            Text(step.status.rawValue.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color(for: step.status))
                        }
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Garmin delivery lab")
    }

    private func color(for status: GarminDeliveryLabStep.Status) -> Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .mock, .skip, .pending, .running: return .orange
        }
    }
}

#endif
