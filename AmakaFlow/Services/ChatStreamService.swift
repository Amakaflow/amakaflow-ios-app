//
//  ChatStreamService.swift
//  AmakaFlow
//
//  SSE streaming client for AI Coach chat (AMA-1410)
//  Connects to POST /chat/stream and yields parsed SSE events.
//

import Foundation
import os

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
    private static let logger = Logger(subsystem: "com.amakaflow.app", category: "chat-stream")
    private static let sseDelimiters: [Data] = [
        Data([0x0A, 0x0A]),             // \\n\\n
        Data([0x0D, 0x0A, 0x0D, 0x0A]), // \\r\\n\\r\\n
        Data([0x0D, 0x0D])              // \\r\\r
    ]
    private static let sseDelimiterScanOverlap = 4

    init(session: URLSession = .shared) {
        self.session = session
    }

    private static func nextSSEDelimiter(in buffer: Data, from searchStart: Data.Index) -> Range<Data.Index>? {
        guard !buffer.isEmpty else { return nil }

        let boundedStart = max(buffer.startIndex, min(searchStart, buffer.endIndex))
        guard boundedStart < buffer.endIndex else { return nil }

        return sseDelimiters
            .compactMap { buffer.range(of: $0, options: [], in: boundedStart..<buffer.endIndex) }
            .min { lhs, rhs in
                if lhs.lowerBound == rhs.lowerBound {
                    return lhs.count > rhs.count
                }
                return lhs.lowerBound < rhs.lowerBound
            }
    }

    private static func nextSSEScanStart(in buffer: Data) -> Data.Index {
        let bufferLength = buffer.distance(from: buffer.startIndex, to: buffer.endIndex)
        let offset = max(0, bufferLength - sseDelimiterScanOverlap)
        return buffer.index(buffer.startIndex, offsetBy: offset)
    }

    private static func parsedEvents(from blockData: Data) -> [SSEEvent] {
        guard !blockData.isEmpty else { return [] }

        guard let block = String(data: blockData, encoding: .utf8) else {
            logUnparseableSSEBlock(eventTypePrefix: "invalid_utf8", byteLength: blockData.count)
            return []
        }

        // Reuse the existing SSE buffer splitter so CRLF/CR line endings are
        // normalized exactly the same way as the tested parser path.
        let (blocks, _) = SSEParser.splitBuffer(block + "\n\n")
        return blocks.compactMap { parsedBlock in
            if let event = SSEParser.parse(block: parsedBlock) {
                return event
            }

            logUnparseableSSEBlock(
                eventTypePrefix: eventTypePrefix(from: parsedBlock),
                byteLength: parsedBlock.utf8.count
            )
            return nil
        }
    }

    private static func eventTypePrefix(from block: String) -> String {
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            guard line.hasPrefix("event:") else { continue }
            return String(line.dropFirst(6).trimmingCharacters(in: .whitespaces).prefix(64))
        }
        return "missing"
    }

    private static func logUnparseableSSEBlock(eventTypePrefix: String, byteLength: Int) {
        logger.warning(
            "Dropped unparseable SSE block eventTypePrefix=\(eventTypePrefix, privacy: .public) byteLength=\(byteLength, privacy: .public)"
        )

        Task { @MainActor in
            DebugLogService.shared.log(
                "Dropped unparseable SSE block",
                details: "eventTypePrefix=\(eventTypePrefix) byteLength=\(byteLength)",
                metadata: [
                    "eventTypePrefix": eventTypePrefix,
                    "byteLength": "\(byteLength)"
                ]
            )
        }
    }

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // AMA-1827: route through mobile-bff `/v1/chat/stream`
                    // (uses BFF's `_proxy_stream` SSE pass-through helper).
                    let bffURL = "\(AppEnvironment.current.mobileBFFURL)/v1"
                    guard let url = URL(string: "\(bffURL)/chat/stream") else {
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

                    var buffer = Data()
                    var scanStart = buffer.startIndex
                    for try await byte in bytes {
                        if Task.isCancelled { return }

                        buffer.append(byte)

                        // Frame SSE events on raw ASCII blank-line delimiters.
                        // Do not depend on AsyncBytes.lines surfacing empty lines,
                        // and do not require the whole accumulated buffer to be
                        // valid UTF-8 before yielding earlier complete events.
                        // Bound each search to the newly appended tail plus a
                        // four-byte overlap so split CRLF delimiters are still
                        // detected without rescanning the whole block.
                        while let delimiter = Self.nextSSEDelimiter(in: buffer, from: scanStart) {
                            let blockData = Data(buffer[..<delimiter.lowerBound])
                            buffer.removeSubrange(..<delimiter.upperBound)
                            scanStart = buffer.startIndex

                            for event in Self.parsedEvents(from: blockData) {
                                continuation.yield(event)
                            }
                        }
                        scanStart = Self.nextSSEScanStart(in: buffer)
                    }

                    if Task.isCancelled { return }

                    // Process any remaining non-empty block after EOF.
                    let trimmedRemainder = buffer.trimmingTrailingSSEWhitespace()
                    for event in Self.parsedEvents(from: trimmedRemainder) {
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

private extension Data {
    func trimmingTrailingSSEWhitespace() -> Data {
        var copy = self
        while let last = copy.last, last == 0x0A || last == 0x0D || last == 0x20 || last == 0x09 {
            copy.removeLast()
        }
        return copy
    }
}

enum ChatStreamError: LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, _):
            return "Chat API error (\(code)). Please try again."
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
