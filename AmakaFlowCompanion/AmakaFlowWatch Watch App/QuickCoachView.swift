//
//  QuickCoachView.swift
//  AmakaFlowWatch Watch App
//
//  Quick Q&A coach from wrist via phone bridge (AMA-1150)
//

import SwiftUI

struct QuickCoachView: View {
    @ObservedObject var viewModel: DayStateViewModel

    var body: some View {
        Group {
            if viewModel.isCoachLoading {
                coachLoadingView
            } else if let response = viewModel.coachResponse {
                coachResponseView(response)
            } else {
                questionListView
            }
        }
    }

    // MARK: - Question List

    private var questionListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Quick Coach")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)

                ForEach(QuickCoachQuestion.allCases) { question in
                    Button {
                        viewModel.askCoach(question)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: question.systemImage)
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .frame(width: 20)

                            Text(question.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-question-\(question.id)")
                }

                if !viewModel.isPhoneReachable {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 10))
                        Text("iPhone required")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("coach-questions")
    }

    // MARK: - Loading

    private var coachLoadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Asking coach...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .accessibilityIdentifier("coach-loading")
    }

    // MARK: - Response

    private func coachResponseView(_ response: CoachResponse) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                // Question echo
                Text(response.question)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Answer
                Text(response.answer)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Back button
                Button {
                    viewModel.clearCoachResponse()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 10))
                        Text("Ask another")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityIdentifier("coach-response")
    }
}
