import XCTest
@testable import DesktopPetCore

// MARK: - Helpers

private func makeSession(
    id: String = "session-001",
    agentKind: AgentKind = .claude,
    project: String? = "/proj/alpha",
    title: String? = "Test Title",
    message: String? = "All done"
) -> AgentSession {
    AgentSession(
        id: id,
        agentKind: agentKind,
        project: project,
        title: title,
        state: .done,
        message: message,
        source: .hook,
        updatedAt: Date(timeIntervalSince1970: 1_000_000)
    )
}

private func makeTmpStore() -> (SessionArchiveStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
    return (SessionArchiveStore(baseURL: dir), dir)
}

// MARK: - SessionArchive Model Tests

final class SessionArchiveModelTests: XCTestCase {

    // [TEST] SessionArchive JSON encode/decode round-trip，Date 必須以 ISO8601 保留精度
    func testJSONRoundTripPreservesAllFields() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt   = Date(timeIntervalSince1970: 1_700_000_120)
        let archive = SessionArchive(
            sessionId: "abc-123",
            agentKind: .claude,
            project: "/proj/beta",
            title: "Feature: dark mode",
            message: "Implemented successfully",
            tokenCount: 4200,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: 120
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionArchive.self, from: data)

        XCTAssertEqual(decoded.sessionId, "abc-123")
        XCTAssertEqual(decoded.agentKind, .claude)
        XCTAssertEqual(decoded.project, "/proj/beta")
        XCTAssertEqual(decoded.title, "Feature: dark mode")
        XCTAssertEqual(decoded.message, "Implemented successfully")
        XCTAssertEqual(decoded.tokenCount, 4200)
        XCTAssertEqual(decoded.duration, 120, accuracy: 0.001)
        // ISO8601 精度到秒，允許 1 秒誤差
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.endedAt.timeIntervalSince1970, endedAt.timeIntervalSince1970, accuracy: 1)
    }

    // tokenCount 為 optional，nil 時不影響其他欄位 encode/decode
    func testJSONRoundTripWithNilOptionals() throws {
        let archive = SessionArchive(
            sessionId: "xyz-999",
            agentKind: .codex,
            project: nil,
            title: nil,
            message: nil,
            tokenCount: nil,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_000_060),
            duration: 60
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionArchive.self, from: data)

        XCTAssertEqual(decoded.sessionId, "xyz-999")
        XCTAssertNil(decoded.project)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.message)
        XCTAssertNil(decoded.tokenCount)
    }
}

// MARK: - SessionArchiveStore Tests

final class SessionArchiveStoreTests: XCTestCase {

    // [TEST] archive() 後 records(for:) 返回正確記錄
    func testArchiveAndRetrieveOnSameDay() {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt   = startedAt.addingTimeInterval(90)
        let session   = makeSession(id: "s-001")

        store.archive(session, startedAt: startedAt, endedAt: endedAt)

        let records = store.records(for: startedAt)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sessionId, "s-001")
        XCTAssertEqual(records.first?.duration ?? -1, 90, accuracy: 0.001)
    }

    // [TEST] 去重：同一 sessionId archive 兩次，records(for:) 只返回一筆
    func testDeduplicationPreventsDuplicateSessionId() {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt   = startedAt.addingTimeInterval(60)
        let session   = makeSession(id: "dup-session")

        store.archive(session, startedAt: startedAt, endedAt: endedAt)
        store.archive(session, startedAt: startedAt, endedAt: endedAt)

        let records = store.records(for: startedAt)
        XCTAssertEqual(records.count, 1, "same sessionId archived twice should only appear once")
    }

    // [TEST] app restart 後去重仍然有效（新 store 實例讀取同一 baseURL）
    func testDeduplicationPersistsAcrossStoreInstances() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionArchiveStoreTests-restart-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt   = startedAt.addingTimeInterval(60)
        let session   = makeSession(id: "persist-dedup")

        // 第一個 store 實例 archive
        let store1 = SessionArchiveStore(baseURL: dir)
        store1.archive(session, startedAt: startedAt, endedAt: endedAt)

        // 第二個 store 實例（模擬 app restart）嘗試重複 archive
        let store2 = SessionArchiveStore(baseURL: dir)
        store2.archive(session, startedAt: startedAt, endedAt: endedAt)

        let records = store2.records(for: startedAt)
        XCTAssertEqual(records.count, 1, "dedup set must be rebuilt from disk on init so restart cannot create duplicates")
    }

    // [TEST] pruneOlderThan(days:) 刪除超過天數嘅檔案，保留符合條件嘅
    func testPruneOlderThanRemovesOldFilesAndKeepsRecent() {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now          = Date(timeIntervalSince1970: 1_700_000_000)
        // 91 日前
        let oldDate      = now.addingTimeInterval(-91 * 86400)
        // 45 日前
        let midDate      = now.addingTimeInterval(-45 * 86400)
        // 今天
        let recentDate   = now

        let s1 = makeSession(id: "old-session")
        let s2 = makeSession(id: "mid-session")
        let s3 = makeSession(id: "recent-session")

        store.archive(s1, startedAt: oldDate, endedAt: oldDate.addingTimeInterval(60))
        store.archive(s2, startedAt: midDate, endedAt: midDate.addingTimeInterval(60))
        store.archive(s3, startedAt: recentDate, endedAt: recentDate.addingTimeInterval(60))

        store.pruneOlderThan(days: 90)

        // 91 日前的應該被刪除
        XCTAssertTrue(store.records(for: oldDate).isEmpty, "file older than 90 days should be pruned")
        // 45 日前的應該保留
        XCTAssertEqual(store.records(for: midDate).count, 1, "file within 90 days should be kept")
        // 今天的應該保留
        XCTAssertEqual(store.records(for: recentDate).count, 1, "today's file should be kept")
    }

    // [TEST] allRecords(since:) 跨日期聚合返回所有符合日期範圍的記錄
    func testAllRecordsSinceAggregatesAcrossMultipleDays() {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now   = Date(timeIntervalSince1970: 1_700_000_000)
        let day1  = now.addingTimeInterval(-2 * 86400)
        let day2  = now.addingTimeInterval(-1 * 86400)

        store.archive(makeSession(id: "day1-s1"), startedAt: day1, endedAt: day1.addingTimeInterval(60))
        store.archive(makeSession(id: "day2-s1"), startedAt: day2, endedAt: day2.addingTimeInterval(60))
        store.archive(makeSession(id: "today-s1"), startedAt: now, endedAt: now.addingTimeInterval(60))

        let all = store.allRecords(since: day1)
        XCTAssertEqual(all.count, 3, "allRecords(since:) should include records from day1 up to today")
    }

    // [TEST] allRecords(since:) 不返回 since 日期之前的記錄
    func testAllRecordsSinceExcludesBeforeCutoff() {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now          = Date(timeIntervalSince1970: 1_700_000_000)
        let beforeCutoff = now.addingTimeInterval(-10 * 86400)
        let cutoff       = now.addingTimeInterval(-5 * 86400)
        let afterCutoff  = now.addingTimeInterval(-2 * 86400)

        store.archive(makeSession(id: "before"), startedAt: beforeCutoff, endedAt: beforeCutoff.addingTimeInterval(60))
        store.archive(makeSession(id: "after"), startedAt: afterCutoff, endedAt: afterCutoff.addingTimeInterval(60))

        let records = store.allRecords(since: cutoff)
        let ids = records.map(\.sessionId)
        XCTAssertFalse(ids.contains("before"), "records before cutoff date should be excluded")
        XCTAssertTrue(ids.contains("after"), "records after cutoff date should be included")
    }

    // [TEST] 每日 JSON 檔名格式為 YYYY-MM-DD.json
    func testDailyFileUsesDateBasedFilename() throws {
        let (store, dir) = makeTmpStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 使用固定時間確保可預測的日期（UTC）
        // 1_700_000_000 = 2023-11-14 22:13:20 UTC
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        store.archive(makeSession(id: "filename-test"), startedAt: startedAt, endedAt: startedAt.addingTimeInterval(30))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let expectedFilename = formatter.string(from: startedAt) + ".json"
        let expectedPath = dir.appendingPathComponent(expectedFilename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path),
                      "archive file should be named \(expectedFilename)")
    }

    // [TEST] shared singleton baseURL 預設指向 ~/.desktoppet/history/
    func testSharedSingletonBaseURLIsDefaultPath() {
        let shared = SessionArchiveStore.shared
        let expectedBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".desktoppet/history", isDirectory: true)
        XCTAssertEqual(shared.baseURL, expectedBase,
                       "shared singleton baseURL must default to ~/.desktoppet/history/")
    }
}
