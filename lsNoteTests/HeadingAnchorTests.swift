import XCTest

final class HeadingAnchorTests: XCTestCase {
    func testSlugMatchesGitHubForAccentsAndPunctuation() {
        XCTAssertEqual(HeadingAnchor.slug("Topologia da Arquitetura"), "topologia-da-arquitetura")
        XCTAssertEqual(HeadingAnchor.slug("1. Configuração dos Nós"), "1-configuração-dos-nós")
        XCTAssertEqual(HeadingAnchor.slug("Cenário 1 · Fluxo normal (Session Initiation e Update)"),
                       "cenário-1--fluxo-normal-session-initiation-e-update")
        XCTAssertEqual(HeadingAnchor.slug("Cenário 2 · Falha do DRUID Primary DRA: failover no meio da session"),
                       "cenário-2--falha-do-druid-primary-dra-failover-no-meio-da-session")
        XCTAssertEqual(HeadingAnchor.slug("Cenário 3 · Network-Initiated Request (RAR)"),
                       "cenário-3--network-initiated-request-rar")
    }

    func testSlugKeepsHyphensAndUnderscores() {
        XCTAssertEqual(HeadingAnchor.slug("snake_case and kebab-case!"), "snake_case-and-kebab-case")
    }

    func testRepeatedHeadingsGetNumberedSuffixes() {
        var slugger = HeadingAnchor.Slugger()
        XCTAssertEqual(slugger.slug(for: "Notes"), "notes")
        XCTAssertEqual(slugger.slug(for: "Notes"), "notes-1")
        XCTAssertEqual(slugger.slug(for: "Notes"), "notes-2")
        XCTAssertEqual(slugger.slug(for: "Other"), "other")
    }

    func testSuffixSkipsAnIdAnEarlierHeadingTook() {
        var slugger = HeadingAnchor.Slugger()
        XCTAssertEqual(slugger.slug(for: "Notes 1"), "notes-1")
        XCTAssertEqual(slugger.slug(for: "Notes"), "notes")
        XCTAssertEqual(slugger.slug(for: "Notes"), "notes-2")
    }

    func testPlainTextStripsTagsAndDecodesEntities() {
        XCTAssertEqual(HeadingAnchor.plainText(fromHTML: "<strong>Bold</strong> &amp; <code>code</code>"),
                       "Bold & code")
        XCTAssertEqual(HeadingAnchor.slug(HeadingAnchor.plainText(fromHTML: "<em>Why</em> &lt;3")), "why-3")
    }
}
