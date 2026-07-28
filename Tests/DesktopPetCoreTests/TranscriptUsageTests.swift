import XCTest
@testable import DesktopPetCore

final class TranscriptUsageTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "desktoppet-usage-\(UUID().uuidString).jsonl"
        TranscriptReader.clearCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    private func append(_ lines: [String]) {
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func assistantLine(input: Int, output: Int) -> String {
        #"{"type":"assistant","message":{"usage":{"input_tokens":\#(input),"output_tokens":\#(output)},"content":[{"type":"text","text":"hi"}]}}"#
    }

    func testSumsUsageAcrossLines() {
        append([
            #"{"type":"user","message":{"content":"do the thing"}}"#,
            assistantLine(input: 1_000, output: 250),
            assistantLine(input: 2_000, output: 750),
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 4_000)
    }

    func testSecondCallReturnsOnlyTheDelta() {
        append([assistantLine(input: 500, output: 100)])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 600)
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 0, "nothing new yet")
        append([assistantLine(input: 300, output: 50)])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 350)
    }

    func testIgnoresLinesWithoutUsage() {
        append([
            #"{"type":"user","message":{"content":"hello"}}"#,
            #"{"type":"summary","summary":"A chat"}"#,
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 0)
    }

    func testPartialTrailingLineIsLeftForNextCall() {
        append([assistantLine(input: 100, output: 100)])
        // A torn line with no trailing newline must not be consumed.
        let torn = #"{"type":"assistant","message":{"usage":{"input_tokens":9999"#
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(torn.data(using: .utf8)!)
        }
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 200)
        // Complete the torn line: now it should be picked up.
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(#","output_tokens":1}}}"#.data(using: .utf8)!)
            handle.write("\n".data(using: .utf8)!)
        }
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 10_000)
    }

    func testUnreadableFileReturnsNil() {
        XCTAssertNil(TranscriptReader.newUsageTokens(at: "/nonexistent/nope.jsonl"))
    }
}
