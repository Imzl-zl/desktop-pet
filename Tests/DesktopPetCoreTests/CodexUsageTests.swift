import XCTest
@testable import DesktopPetCore

final class CodexUsageTests: XCTestCase {
    private func tmpRollout(_ lines: [String]) -> String {
        let path = NSTemporaryDirectory() + "rollout-\(UUID().uuidString).jsonl"
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func tokenLine(input: Int, cached: Int, output: Int, total: Int) -> String {
        """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"total_tokens":\(input + output)}}}}
        """
    }

    func testSumsFreshInputPlusOutputMinusCache() {
        TranscriptReader.clearCache()
        let path = tmpRollout([
            #"{"type":"session_meta","payload":{"id":"x","cwd":"/p"}}"#,
            tokenLine(input: 1000, cached: 200, output: 50, total: 1050),   // (1000-200)+50 = 850
            tokenLine(input: 1200, cached: 300, output: 80, total: 2330),   // (1200-300)+80 = 980
        ])
        XCTAssertEqual(TranscriptReader.newCodexUsageTokens(at: path), 850 + 980)
        defer { try? FileManager.default.removeItem(atPath: path) }
    }

    func testIncrementalNoDoubleCount() {
        TranscriptReader.clearCache()
        let path = NSTemporaryDirectory() + "rollout-\(UUID().uuidString).jsonl"
        try? (#"{"type":"session_meta","payload":{"id":"x","cwd":"/p"}}"# + "\n"
              + tokenLine(input: 1000, cached: 0, output: 100, total: 1100) + "\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(TranscriptReader.newCodexUsageTokens(at: path), 1100)
        // Second call with no new lines → 0 (offset remembered).
        XCTAssertEqual(TranscriptReader.newCodexUsageTokens(at: path), 0)
        // Append another turn → only the new delta is returned.
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data((tokenLine(input: 500, cached: 100, output: 40, total: 1540) + "\n").utf8))
            try? h.close()
        }
        XCTAssertEqual(TranscriptReader.newCodexUsageTokens(at: path), (500 - 100) + 40)
        try? FileManager.default.removeItem(atPath: path)
    }

    func testIgnoresNonTokenLines() {
        TranscriptReader.clearCache()
        let path = tmpRollout([
            #"{"type":"response_item","payload":{"type":"message","content":"hi"}}"#,
            #"{"type":"event_msg","payload":{"type":"agent_message","message":"working"}}"#,
        ])
        XCTAssertEqual(TranscriptReader.newCodexUsageTokens(at: path), 0)
        try? FileManager.default.removeItem(atPath: path)
    }
}
