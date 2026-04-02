//
//  ChatStreamService.swift
//  AmakaFlow
//
//  SSE streaming client for AI Coach chat (AMA-1410)
//  Connects to POST /chat/stream and yields parsed SSE events.
//

import Foundation

// MARK: - SSE Parser

enum SSEParser {
    /// Parse a single SSE event block (between double newlines) into an SSEEvent.
    static func parse(block: String) -> SSEEvent? {
        var eventType = ""
        var dataStr = ""

        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.hasPrefix("event:") {
                eventType = lineStr.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if lineStr.hasPrefix("data:") {
                let value = String(lineStr.dropFirst(5))
                let payload = value.hasPrefix(" ") ? String(value.dropFirst(1)) : value
                if dataStr.isEmpty {
                    dataStr = payload
                } else {
                    dataStr += "\n" + payload
                }
            }
        }

        guard !eventType.isEmpty, !dataStr.isEmpty,
              let data = dataStr.data(using: .utf8) else {
            return nil
        }

        return decodeEvent(type: eventType, data: data)
    }

    /// Utility for non-line-based SSE parsing. Currently unused but tested.
    /// Split a buffer into complete SSE blocks and a remainder (incomplete trailing data).
    static func splitBuffer(_ buffer: String) -> (blocks: [String], remainder: String) {
        let normalized = buffer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let remainder = parts.last ?? ""
        let blocks = parts.dropLast().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (blocks, remainder)
    }

    private static func decodeEvent(type: String, data: Data) -> SSEEvent? {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            switch type {
            case "message_start":
                guard let sessionId = json["session_id"] as? String else { return nil }
                let traceId = json["trace_id"] as? String
                return .messageStart(sessionId: sessionId, traceId: traceId)

            case "content_delta":
                guard let text = json["text"] as? String else { return nil }
                return .contentDelta(text: text)

            case "function_call":
                guard let id = json["id"] as? String,
                      let name = json["name"] as? String else { return nil }
                return .functionCall(id: id, name: name)

            case "function_result":
                guard let toolUseId = json["tool_use_id"] as? String,
                      let name = json["name"] as? String,
                      let result = json["result"] as? String else { return nil }
                return .functionResult(toolUseId: toolUseId, name: name, result: result)

            case "stage":
                guard let stageStr = json["stage"] as? String,
                      let stage = ChatStage(rawValue: stageStr),
                      let message = json["message"] as? String else { return nil }
                return .stage(stage: stage, message: message)

            case "heartbeat":
                guard let status = json["status"] as? String else { return nil }
                let toolName = json["tool_name"] as? String
                let elapsed = json["elapsed_seconds"] as? Double
                return .heartbeat(status: status, toolName: toolName, elapsedSeconds: elapsed)

            case "message_end":
                guard let sessionId = json["session_id"] as? String else { return nil }
                let tokensUsed = json["tokens_used"] as? Int
                let latencyMs = json["latency_ms"] as? Int
                return .messageEnd(sessionId: sessionId, tokensUsed: tokensUsed, latencyMs: latencyMs)

            case "error":
                guard let errorType = json["type"] as? String,
                      let message = json["message"] as? String else { return nil }
                let usage = json["usage"] as? Int
                let limit = json["limit"] as? Int
                return .error(type: errorType, message: message, usage: usage, limit: limit)

            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Chat Stream Service

protocol ChatStreamProviding {
    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error>
}

class ChatStreamService: ChatStreamProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let chatURL = AppEnvironment.current.chatAPIURL
                    guard let url = URL(string: "\(chatURL)/chat/stream") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        continuation.finish(throwing: ChatStreamError.httpError(
                            statusCode: httpResponse.statusCode, body: body
                        ))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line + "\n"

                        // A blank line from the server means event boundary
                        if line.isEmpty {
                            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty, let event = SSEParser.parse(block: trimmed) {
                                continuation.yield(event)
                            }
                            buffer = ""
                        }
                    }

                    // Process any remaining buffer
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let event = SSEParser.parse(block: trimmed) {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled { return }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum ChatStreamError: LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "Chat API error: \(code) — \(body)"
        }
    }
}

// MARK: - Mock for Testing

class MockChatStreamService: ChatStreamProviding {
    var eventsToYield: [SSEEvent] = []
    var errorToThrow: Error?
    var streamCalled = false

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        streamCalled = true
        let events = eventsToYield
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
