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

// MARK: - SSE Framer

/// Stateful byte-level SSE framer. Accumulates raw bytes and yields complete
/// SSE event blocks (Data) whenever a blank-line delimiter is detected.
/// Handles \n\n, \r\n\r\n, and \r\r per RFC 8895.
struct SSEFramer {
    private var buffer = Data()
    private var scanStart = Data.Index()

    private static let delimiters: [Data] = [
        Data([0x0A, 0x0A]),             // \n\n
        Data([0x0D, 0x0A, 0x0D, 0x0A]), // \r\n\r\n
        Data([0x0D, 0x0D])              // \r\r
    ]
    private static let scanOverlap = 4

    /// Append one byte and return any complete SSE event blocks now delimited.
    mutating func feed(_ byte: UInt8) -> [Data] {
        buffer.append(byte)
        var completed: [Data] = []
        while let delimiter = Self.nextDelimiter(in: buffer, from: scanStart) {
            completed.append(Data(buffer[..<delimiter.lowerBound]))
            buffer.removeSubrange(..<delimiter.upperBound)
            scanStart = buffer.startIndex
        }
        scanStart = Self.nextScanStart(in: buffer)
        return completed
    }

    /// Drain and return any buffered tail after EOF, trimming trailing SSE whitespace.
    mutating func flush() -> Data {
        let trimmed = buffer.trimmingTrailingSSEWhitespace()
        buffer = Data()
        scanStart = Data.Index()
        return trimmed
    }

    private static func nextDelimiter(in buffer: Data, from searchStart: Data.Index) -> Range<Data.Index>? {
        guard !buffer.isEmpty else { return nil }
        let boundedStart = max(buffer.startIndex, min(searchStart, buffer.endIndex))
        guard boundedStart < buffer.endIndex else { return nil }
        return delimiters
            .compactMap { buffer.range(of: $0, options: [], in: boundedStart..<buffer.endIndex) }
            .min {
                if $0.lowerBound == $1.lowerBound { return $0.count > $1.count }
                return $0.lowerBound < $1.lowerBound
            }
    }

    private static func nextScanStart(in buffer: Data) -> Data.Index {
        let len = buffer.distance(from: buffer.startIndex, to: buffer.endIndex)
        return buffer.index(buffer.startIndex, offsetBy: max(0, len - scanOverlap))
    }
}

// MARK: - Chat Stream Service

protocol ChatStreamProviding {
    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error>
}

class ChatStreamService: ChatStreamProviding {
    private let session: URLSession
    private static let logger = Logger(subsystem: "com.amakaflow.app", category: "chat-stream")

    init(session: URLSession = .shared) {
        self.session = session
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
                        var bodyLines: [String] = []
                        for try await line in bytes.lines {
                            bodyLines.append(line)
                        }
                        continuation.finish(throwing: ChatStreamError.httpError(
                            statusCode: httpResponse.statusCode, body: bodyLines.joined(separator: "\n")
                        ))
                        return
                    }

                    var framer = SSEFramer()
                    for try await byte in bytes {
                        if Task.isCancelled { return }
                        for blockData in framer.feed(byte) {
                            for event in Self.parsedEvents(from: blockData) {
                                continuation.yield(event)
                            }
                        }
                    }

                    if Task.isCancelled { return }

                    for event in Self.parsedEvents(from: framer.flush()) {
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

// MARK: - Session Messages (AMA-2123)

struct RestoredSessionMessage: Equatable {
    let role: ChatRole
    let content: String
    let timestamp: Date
    let pendingActions: [PendingActionContract]

    init(
        role: ChatRole,
        content: String,
        timestamp: Date,
        pendingActions: [PendingActionContract] = []
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.pendingActions = pendingActions
    }
}

protocol CoachSessionProviding {
    func fetchMessages(sessionId: String, limit: Int, token: String) async throws -> [RestoredSessionMessage]
}

enum CoachSessionError: LocalizedError, Equatable {
    case sessionNotFound
    case unauthorized
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Chat session not found."
        case .unauthorized:
            return "Not authenticated."
        case .httpError(let code, _):
            return "Could not load conversation (\(code))."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .httpError(let code, _):
            return code == 502 || code == 503
        default:
            return false
        }
    }
}

class CoachSessionClient: CoachSessionProviding {
    private let session: URLSession
    private static let requestTimeout: TimeInterval = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMessages(sessionId: String, limit: Int = 50, token: String) async throws -> [RestoredSessionMessage] {
        try await fetchMessages(sessionId: sessionId, limit: limit, token: token, retryOnTransient: true)
    }

    private func fetchMessages(
        sessionId: String,
        limit: Int,
        token: String,
        retryOnTransient: Bool
    ) async throws -> [RestoredSessionMessage] {
        let encodedSessionId = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        let bffURL = "\(AppEnvironment.current.mobileBFFURL)/v1"
        guard var components = URLComponents(string: "\(bffURL)/chat/sessions/\(encodedSessionId)/messages") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = APIService.makeGeneratedDecoder()
            let payload = try decoder.decode(SessionMessagesResponse.self, from: data)
            return payload.messages.compactMap { $0.toRestoredMessage() }
        case 401:
            throw CoachSessionError.unauthorized
        case 404:
            throw CoachSessionError.sessionNotFound
        case 502, 503 where retryOnTransient:
            try await Task.sleep(nanoseconds: 300_000_000)
            return try await fetchMessages(
                sessionId: sessionId,
                limit: limit,
                token: token,
                retryOnTransient: false
            )
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoachSessionError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

private struct SessionMessagesResponse: Decodable {
    let messages: [SessionMessageDTO]
}

private struct SessionMessageDTO: Decodable {
    let role: String
    let content: String?
    let createdAt: Date
    let pendingActions: [PendingActionContract]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case createdAt = "created_at"
        case pendingActions = "pending_actions"
    }

    func toRestoredMessage() -> RestoredSessionMessage? {
        let restoredPendingActions = pendingActions?.map { $0.withFallbackPresentation() } ?? []
        guard content?.isEmpty == false || !restoredPendingActions.isEmpty else { return nil }
        let chatRole: ChatRole
        switch role.lowercased() {
        case "user":
            chatRole = .user
        case "assistant":
            chatRole = .assistant
        default:
            return nil
        }
        return RestoredSessionMessage(
            role: chatRole,
            content: content ?? "",
            timestamp: createdAt,
            pendingActions: restoredPendingActions
        )
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

class MockCoachSessionClient: CoachSessionProviding {
    var messagesToReturn: [RestoredSessionMessage] = []
    var errorToThrow: Error?
    var fetchCalled = false
    var lastSessionId: String?
    var lastLimit: Int?

    func fetchMessages(sessionId: String, limit: Int, token: String) async throws -> [RestoredSessionMessage] {
        fetchCalled = true
        lastSessionId = sessionId
        lastLimit = limit
        if let errorToThrow {
            throw errorToThrow
        }
        return messagesToReturn
    }
}

class MockChatStreamService: ChatStreamProviding {
    var eventsToYield: [SSEEvent] = []
    var errorToThrow: Error?
    var streamCalled = false
    private(set) var lastRequest: ChatStreamRequest?
    private(set) var lastToken: String?

    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        streamCalled = true
        lastRequest = request
        lastToken = token
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
