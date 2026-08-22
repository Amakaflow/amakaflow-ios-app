import XCTest
@testable import AmakaFlowCompanion

class DiagnosticEventStoreTestCase: XCTestCase {
    var rootURL: URL!
    var defaults: UserDefaults!
    var suiteName: String!
    var now: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticEventStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        suiteName = "DiagnosticEventStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        now = Date(timeIntervalSince1970: 1_777_000_000)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        now = nil
        try super.tearDownWithError()
    }

    func makeStore(maxBytes: Int = 5 * 1024 * 1024) -> DiagnosticEventStore {
        DiagnosticEventStore(
            rootURL: rootURL,
            userDefaults: defaults,
            now: { self.now },
            maxBytes: maxBytes
        )
    }

    func event(
        _ name: String,
        at timestamp: Date,
        message: String = "safe message",
        accountHash: String? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            id: UUID().uuidString,
            timestamp: timestamp,
            severity: .info,
            category: .general,
            name: name,
            message: message,
            metadata: [:],
            requestID: nil,
            sentryEventID: nil,
            sentryTraceID: nil,
            accountHash: accountHash
        )
    }
}

extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
        try handle.close()
    }
}
