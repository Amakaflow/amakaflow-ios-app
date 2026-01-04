//
//  WorkoutsView.swift
//  AmakaFlow
//
//  Main workouts screen with Upcoming and Incoming sections
//

import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var selectedWorkout: Workout?
    @State private var showingDetail = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Search Bar
                        SearchBar(text: $viewModel.searchQuery)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                        
                        // Upcoming Workouts Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            HStack {
                                Text("Upcoming Workouts")
                                    .font(Theme.Typography.title1)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                if !viewModel.upcomingWorkouts.isEmpty {
                                    Text("\(viewModel.upcomingWorkouts.count) saved")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            if viewModel.filteredUpcoming.isEmpty {
                                EmptyStateView(
                                    icon: "calendar",
                                    title: "No Upcoming Workouts",
                                    message: "Workouts you save will appear here"
                                )
                                .padding(.horizontal, Theme.Spacing.lg)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(viewModel.filteredUpcoming) { scheduled in
                                        WorkoutCard(
                                            workout: scheduled.workout,
                                            scheduledDate: scheduled.scheduledDate,
                                            scheduledTime: scheduled.scheduledTime,
                                            isPrimary: true
                                        )
                                        .onTapGesture {
                                            print("🔵 TAPPED WORKOUT: \(scheduled.workout.name)")
                                            selectedWorkout = scheduled.workout
                                            print("🔵 Selected workout: \(selectedWorkout?.name ?? "nil")")
                                            showingDetail = true
                                            print("🔵 showingDetail = true")
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                        .padding(.bottom, 40)

                        // Incoming Workouts Section (pending workouts from API)
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            HStack {
                                Text("Incoming Workouts")
                                    .font(Theme.Typography.title1)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Spacer()

                                if !viewModel.incomingWorkouts.isEmpty {
                                    Text("\(viewModel.incomingWorkouts.count) pending")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)

                            if viewModel.filteredIncoming.isEmpty {
                                EmptyStateView(
                                    icon: "arrow.down.circle",
                                    title: "No Incoming Workouts",
                                    message: "Workouts synced from the web will appear here"
                                )
                                .padding(.horizontal, Theme.Spacing.lg)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(viewModel.filteredIncoming) { workout in
                                        WorkoutCard(
                                            workout: workout,
                                            scheduledDate: nil,
                                            scheduledTime: nil,
                                            isPrimary: false
                                        )
                                        .onTapGesture {
                                            print("🔵 TAPPED INCOMING WORKOUT: \(workout.name)")
                                            selectedWorkout = workout
                                            showingDetail = true
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                        .padding(.bottom, 40)

                        // Add Sample Workout Button (for testing)
                        VStack(spacing: Theme.Spacing.md) {
                            Button(action: {
                                viewModel.addSampleWorkout()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                    Text("Add Sample Workout")
                                        .font(Theme.Typography.bodyBold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.md)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingDetail) {
                if let workout = selectedWorkout {
                    WorkoutDetailView(workout: workout)
                        .environmentObject(viewModel)
                        .onAppear {
                            print("🔵 WorkoutDetailView.onAppear called!")
                        }
                } else {
                    VStack {
                        Text("ERROR: No workout selected")
                            .foregroundColor(.white)
                            .font(.title)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .onAppear {
                        print("🔵 ERROR: workout is nil in sheet!")
                    }
                }
            }
            .onChange(of: showingDetail) { oldValue, newValue in
                print("🔵 showingDetail changed: \(oldValue) → \(newValue)")
            }
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textSecondary)
                .font(.system(size: 16))
            
            TextField("Search workouts...", text: $text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.lg)
            
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
    }
}

#Preview {
    WorkoutsView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
