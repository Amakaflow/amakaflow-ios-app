//
//  ProgramStreamService.swift
//  AmakaFlow
//
//  SSE streaming client for the Program Wizard three-phase pipeline (AMA-2096).
//

import Foundation
import os

protocol ProgramStreamProviding {
    func designProgram(request: DesignProgramRequest, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error>
    func generateProgram(previewId: String, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error>
    func saveProgram(previewId: String, scheduleStartDate: String?, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error>
}

final class ProgramStreamService: ProgramStreamProviding {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let logger = Logger(subsystem: "com.amakaflow.app", category: "program-stream")

    init(session: URLSession = .shared) {
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func designProgram(request: DesignProgramRequest, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        stream(path: "/programs/design/stream", body: request, token: token)
    }

    func generateProgram(previewId: String, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        stream(path: "/programs/generate/stream", body: GenerateProgramPreviewRequest(previewId: previewId), token: token)
    }

    func saveProgram(previewId: String, scheduleStartDate: String?, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        stream(path: "/programs/save/stream", body: SaveProgramPreviewRequest(previewId: previewId, scheduleStartDate: scheduleStartDate), token: token)
    }

    private func stream<Body: Encodable>(path: String, body: Body, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(AppEnvironment.current.mobileBFFURL)/v1\(path)") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try encoder.encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        var responseBody = ""
                        for try await byte in bytes {
                            responseBody.append(String(decoding: [byte], as: UTF8.self))
                        }
                        continuation.finish(throwing: ProgramStreamError.httpError(statusCode: httpResponse.statusCode, body: responseBody))
                        return
                    }

                    var framer = SSEFramer()
                    for try await byte in bytes {
                        if Task.isCancelled { return }
                        for blockData in framer.feed(byte) {
                            if let event = Self.processBlock(blockData, decoder: decoder) {
                                continuation.yield(event)
                            }
                        }
                    }

                    let remainderData = framer.flush()
                    if let event = Self.processBlock(remainderData, decoder: decoder) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled { return }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func processBlock(_ blockData: Data, decoder: JSONDecoder) -> ProgramStreamEvent? {
        guard !blockData.isEmpty else { return nil }
        guard let block = String(data: blockData, encoding: .utf8) else {
            logger.warning("Dropped invalid-UTF-8 program SSE block byteLength=\(blockData.count, privacy: .public)")
            return nil
        }
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let event = parseEvent(block: trimmed, decoder: decoder) {
            return event
        }
        logUnparseableSSEBlock(trimmed)
        return nil
    }

    static func parseEvent(block: String, decoder: JSONDecoder) -> ProgramStreamEvent? {
        var eventType = ""
        var dataString = ""

        let normalizedBlock = block
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalizedBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineString = String(line)
            if lineString.hasPrefix("event:") {
                eventType = lineString.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lineString.hasPrefix("data:") {
                let value = String(lineString.dropFirst(5))
                let payload = value.hasPrefix(" ") ? String(value.dropFirst(1)) : value
                dataString = dataString.isEmpty ? payload : dataString + "\n" + payload
            }
        }

        guard !eventType.isEmpty, let data = dataString.data(using: .utf8) else { return nil }

        do {
            switch eventType {
            case "stage":
                let payload = try decoder.decode(ProgramStagePayload.self, from: data)
                return .stage(stage: payload.stage, message: payload.message, subProgress: payload.subProgress)
            case "preview":
                let payload = try decoder.decode(ProgramPreviewPayload.self, from: data)
                return .preview(previewId: payload.previewId, payload: payload)
            case "complete":
                let payload = try decoder.decode(ProgramCompletePayload.self, from: data)
                return .complete(workoutIds: payload.workoutIds, scheduledCount: payload.scheduledCount, workoutCount: payload.workoutCount)
            case "error":
                let payload = try decoder.decode(ProgramErrorPayload.self, from: data)
                return .error(message: payload.message, recoverable: payload.recoverable ?? false)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func logUnparseableSSEBlock(_ block: String) {
        logger.warning("Dropped unparseable program SSE block prefix=\(String(block.prefix(64)), privacy: .public)")
    }
}

enum ProgramStreamError: LocalizedError, Equatable {
    case httpError(statusCode: Int, body: String)
    case streamError(message: String, recoverable: Bool)
    case missingPreviewId(phase: String)
    case missingProgramPreview

    var errorDescription: String? {
        switch self {
        case .httpError(let code, _):
            return "Program API error (\(code)). Please try again."
        case .streamError(let message, _):
            return message
        case .missingPreviewId(let phase):
            return "The \(phase) step finished without a preview ID. Please try again."
        case .missingProgramPreview:
            return "The program preview was empty. Please try again."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .streamError(_, let recoverable): return recoverable
        case .httpError, .missingPreviewId, .missingProgramPreview: return true
        }
    }
}

// MARK: - Mock for Testing

final class MockProgramStreamService: ProgramStreamProviding {
    var designEvents: [ProgramStreamEvent] = []
    var generateEvents: [ProgramStreamEvent] = []
    var saveEvents: [ProgramStreamEvent] = []
    var errorToThrow: Error?

    private(set) var designProgramCalled = false
    private(set) var generateProgramCalled = false
    private(set) var saveProgramCalled = false
    private(set) var lastDesignRequest: DesignProgramRequest?
    private(set) var lastGeneratePreviewId: String?
    private(set) var lastSavePreviewId: String?
    private(set) var lastScheduleStartDate: String?

    func designProgram(request: DesignProgramRequest, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        designProgramCalled = true
        lastDesignRequest = request
        return stream(events: designEvents)
    }

    func generateProgram(previewId: String, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        generateProgramCalled = true
        lastGeneratePreviewId = previewId
        return stream(events: generateEvents)
    }

    func saveProgram(previewId: String, scheduleStartDate: String?, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        saveProgramCalled = true
        lastSavePreviewId = previewId
        lastScheduleStartDate = scheduleStartDate
        return stream(events: saveEvents)
    }

    private func stream(events: [ProgramStreamEvent]) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
        let error = errorToThrow
        return AsyncThrowingStream { continuation in
            Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
