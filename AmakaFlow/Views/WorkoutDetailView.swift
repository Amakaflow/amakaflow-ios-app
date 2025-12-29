//
//  WorkoutDetailView.swift
//  AmakaFlow
//
//  Workout detail screen with step-by-step breakdown and actions
//

import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @Environment(\.dismiss) var dismiss

    let workout: Workout

    @State private var showingCalendarSheet = false
    @State private var showingWorkoutPlayer = false
    @State private var showingDeviceSheet = false
    @State private var watchSent = false
    @State private var calendarScheduled = false
    @State private var selectedDevice: DevicePreference = .phoneOnly
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header Card
                    WorkoutHeaderCard(workout: workout)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.md)
                    
                    // Step-by-Step Breakdown
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Step-by-Step Breakdown")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.lg)
                        
                        Group {
                            if workout.intervals.isEmpty {
                                Text("No intervals defined for this workout")
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, Theme.Spacing.lg)
                                    .padding(.vertical, Theme.Spacing.lg)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                                        IntervalRow(
                                            interval: interval,
                                            stepNumber: index + 1,
                                            isLast: index == workout.intervals.count - 1
                                        )
                                    }
                                }
                            }
                        }
                        .background(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .cornerRadius(Theme.CornerRadius.xl)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Start on Phone (Follow-Along)
                        Button(action: {
                            showingDeviceSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                Text("Start Follow-Along")
                                    .font(Theme.Typography.bodyBold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                LinearGradient(
                                    colors: [Theme.Colors.accentBlue, Theme.Colors.accentGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                        }

                        // Convert to WorkoutKit (Save to Apple Fitness)
                        if #available(iOS 18.0, *) {
                            Button(action: {
                                Task {
                                    do {
                                        try await WorkoutKitConverter.shared.saveToWorkoutKit(workout)
                                        withAnimation {
                                            watchSent = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            withAnimation {
                                                watchSent = false
                                            }
                                        }
                                    } catch {
                                        viewModel.errorMessage = "Failed to save to WorkoutKit: \(error.localizedDescription)"
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if watchSent {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                    } else {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 16))
                                    }
                                    Text(watchSent ? "Saved to Apple Fitness" : "Save to Apple Fitness")
                                        .font(Theme.Typography.bodyBold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(watchSent ? Theme.Colors.accentGreen : Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.md)
                            }
                            .disabled(watchSent)
                        }
                        
                        // For iOS < 18.0, show message about WorkoutKit requirement
                        if #unavailable(iOS 18.0) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                Text("WorkoutKit requires iOS 18.0+. Use Watch sync or Calendar instead.")
                                    .font(Theme.Typography.caption)
                            }
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surfaceElevated)
                            .cornerRadius(Theme.CornerRadius.md)
                        }
                        
                        // Start on Apple Watch
                        Button(action: {
                            Task {
                                await viewModel.sendToWatch(workout)
                                withAnimation {
                                    watchSent = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        watchSent = false
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if watchSent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                } else {
                                    Image(systemName: "applewatch")
                                        .font(.system(size: 16))
                                }
                                Text(watchSent ? "Workout Sent — Ready on Watch" : "Start on Apple Watch")
                                    .font(Theme.Typography.bodyBold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(watchSent ? Theme.Colors.accentGreen : Theme.Colors.accentBlue)
                            .cornerRadius(Theme.CornerRadius.md)
                        }
                        .disabled(watchSent)
                        
                        // Schedule to Calendar
                        Button(action: {
                            showingCalendarSheet = true
                        }) {
                            HStack(spacing: 8) {
                                if calendarScheduled {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                } else {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 16))
                                }
                                Text(calendarScheduled ? "Workout Scheduled — Ready in Calendar" : "Schedule to Calendar")
                                    .font(Theme.Typography.bodyBold)
                            }
                            .foregroundColor(calendarScheduled ? .white : Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(calendarScheduled ? Theme.Colors.accentGreen : Theme.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(calendarScheduled ? Color.clear : Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                        }
                        .disabled(calendarScheduled)
                        
                        // Info Message
                        if watchSent || calendarScheduled {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                Group {
                                    if watchSent {
                                        if #available(iOS 18.0, *) {
                                            Text("Workout saved to Apple Fitness. Open the Fitness app to view and start.")
                                        } else {
                                            Text("Open the AmakaFlow Companion app on your Apple Watch to start")
                                        }
                                    } else {
                                        Text("You'll receive a reminder at the scheduled time")
                                    }
                                }
                                .font(Theme.Typography.caption)
                            }
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                        }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 100) // Extra padding at bottom to ensure scrolling works
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingCalendarSheet) {
                ScheduleCalendarSheet(
                    workout: workout,
                    onSchedule: { date, time in
                        Task {
                            await viewModel.scheduleWorkout(workout, date: date, time: time)
                            withAnimation {
                                calendarScheduled = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    calendarScheduled = false
                                }
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingDeviceSheet) {
                PreWorkoutDeviceSheet(
                    workout: workout,
                    appleWatchConnected: WatchConnectivityManager.shared.isWatchReachable,
                    garminConnected: false,
                    amazfitConnected: false,
                    onSelectDevice: { device in
                        selectedDevice = device
                        showingDeviceSheet = false
                        WorkoutEngine.shared.start(workout: workout)
                        // Small delay to let sheet dismiss before showing player
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingWorkoutPlayer = true
                        }
                    },
                    onClose: {
                        showingDeviceSheet = false
                    },
                    onChangeSettings: {
                        showingDeviceSheet = false
                        // TODO: Navigate to settings
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingWorkoutPlayer) {
                WorkoutPlayerView()
            }
        }
    }
}

// MARK: - Workout Header Card
struct WorkoutHeaderCard: View {
    let workout: Workout
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.accentBlue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.accentBlue.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: sportIcon)
                        .font(.system(size: 28))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text(workout.sport.rawValue.capitalized)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                
                Spacer()
            }
            
            if let description = workout.description {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            // Stats
            HStack(spacing: Theme.Spacing.lg) {
                StatBadge(icon: "clock", label: "Duration", value: workout.formattedDuration)
                StatBadge(icon: "target", label: "Steps", value: "\(workout.intervalCount)")
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
    }
    
    private var sportIcon: String {
        switch workout.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "figure.mixed.cardio"
        case .other: return "figure.elliptical"
        }
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(Theme.Colors.textSecondary)
            
            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

#Preview {
    WorkoutDetailView(
        workout: Workout(
            name: "Full Body Strength",
            sport: .strength,
            duration: 1890,
            intervals: [
                .warmup(seconds: 300, target: nil),
                .reps(reps: 8, name: "Squat", load: "80% 1RM", restSec: 90, followAlongUrl: nil),
                .reps(reps: 8, name: "Bench Press", load: nil, restSec: 90, followAlongUrl: nil),
                .cooldown(seconds: 300, target: nil)
            ],
            description: "Complete full body workout",
            source: .coach
        )
    )
    .environmentObject(WorkoutsViewModel())
    .preferredColorScheme(.dark)
}
