import XCTest

final class AIActionTests: XCTestCase {
    // MARK: Actions

    func testBuiltInsCoverFormattingAndBothTranslations() {
        let names = AIAction.builtIns.map(\.name)
        XCTAssertTrue(names.contains("Format as Markdown"))
        XCTAssertTrue(names.contains("Translate to Portuguese (Brazil)"))
        XCTAssertTrue(names.contains("Translate to English"))
        XCTAssertEqual(Set(AIAction.builtIns.map(\.id)).count, names.count, "ids must be unique")
        XCTAssertTrue(AIAction.builtIns.allSatisfy(\.isRunnable))
    }

    func testCustomActionsRoundTripThroughJSON() {
        let actions = [AIAction(name: "Formal", prompt: "Rewrite in a formal tone."),
                       AIAction(name: "Título", prompt: "Sugira um título — \"curto\".")]
        XCTAssertEqual(AIAction.decodeList(AIAction.encodeList(actions)), actions)
    }

    func testUnreadableCustomActionsDecodeToEmpty() {
        XCTAssertEqual(AIAction.decodeList(""), [])
        XCTAssertEqual(AIAction.decodeList("{not json"), [])
    }

    func testHalfFilledActionIsNotRunnable() {
        XCTAssertFalse(AIAction(name: "  ", prompt: "Do it").isRunnable)
        XCTAssertFalse(AIAction(name: "Name", prompt: "\n").isRunnable)
    }

    // MARK: Prompt

    func testUserMessageKeepsInstructionAndTextApart() {
        let message = AIPrompt.userMessage(instruction: "  Translate.\n", text: "olá\nmundo")
        XCTAssertTrue(message.contains("<instruction>\nTranslate.\n</instruction>"))
        XCTAssertTrue(message.contains("<text>\nolá\nmundo\n</text>"))
    }

    // MARK: Tidy

    func testTidyKeepsTheSourcesSurroundingWhitespace() {
        XCTAssertEqual(AIPrompt.tidy("Hello\n", replacing: "  olá\n\n"), "  Hello\n\n")
        XCTAssertEqual(AIPrompt.tidy("\n\nHello  ", replacing: "olá"), "Hello")
    }

    func testTidyStripsAFenceWrappedAroundTheWholeReply() {
        XCTAssertEqual(AIPrompt.tidy("```markdown\n# Title\n\ntext\n```", replacing: "title\ntext"), "# Title\n\ntext")
        XCTAssertEqual(AIPrompt.tidy("```\nplain\n```", replacing: "plain"), "plain")
    }

    func testTidyKeepsFencesThatAreContent() {
        let code = "```swift\nlet a = 1\n```"
        XCTAssertEqual(AIPrompt.tidy(code, replacing: "let a = 1"), code, "a language fence is content")
        let fenced = "```\nls -la\n```"
        XCTAssertEqual(AIPrompt.tidy(fenced, replacing: fenced), fenced, "the source was a fence itself")
        let two = "```\na\n```\ntext\n```\nb\n```"
        XCTAssertEqual(AIPrompt.tidy(two, replacing: "a b"), two, "two blocks are not one wrapper")
    }

    // MARK: Stream parsing

    func testParsesTextDeltas() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Olá \"mundo\"\n"}}"#
        XCTAssertEqual(AIStreamEvent.parse(line: line), .text("Olá \"mundo\"\n"))
    }

    func testParsesStopReasonAndErrors() {
        XCTAssertEqual(AIStreamEvent.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":9}}"#),
                       .stop(reason: "max_tokens"))
        XCTAssertEqual(AIStreamEvent.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
                       .error("Overloaded"))
    }

    func testIgnoresLinesWithoutContent() {
        XCTAssertNil(AIStreamEvent.parse(line: "event: content_block_delta"))
        XCTAssertNil(AIStreamEvent.parse(line: ""))
        XCTAssertNil(AIStreamEvent.parse(line: #"data: {"type":"ping"}"#))
        XCTAssertNil(AIStreamEvent.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}"#))
        XCTAssertNil(AIStreamEvent.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":null}}"#))
    }
}
