import XCTest

final class SearchQueryTests: XCTestCase {

    // MARK: Parser — syntax forms

    func testIncludedTag() {
        XCTAssertEqual(SearchQuery.parse("#ocs").tagClauses, [.anyOf(["ocs"])])
    }

    func testExcludedTag() {
        let q = SearchQuery.parse("-#todo")
        XCTAssertEqual(q.tagClauses, [.excluding("todo")])
        XCTAssertEqual(q.excludedTags, ["todo"])
    }

    func testOrGroup() {
        XCTAssertEqual(SearchQuery.parse("#ocs|#pulse").includedTagGroups, [["ocs", "pulse"]])
        XCTAssertEqual(SearchQuery.parse("#ocs|pulse").includedTagGroups, [["ocs", "pulse"]])
    }

    func testTerm() {
        let q = SearchQuery.parse("Quota")
        XCTAssertEqual(q.terms, ["quota"])
        XCTAssertTrue(q.tagClauses.isEmpty)
    }

    func testPhrase() {
        XCTAssertEqual(SearchQuery.parse("\"Rating Group\"").phrases, ["rating group"])
    }

    func testHierarchicalTag() {
        XCTAssertEqual(SearchQuery.parse("#OCS/Diameter").tagClauses, [.anyOf(["ocs/diameter"])])
    }

    // MARK: Parser — mixed queries, whitespace, case

    func testMixedQuery() {
        let q = SearchQuery.parse("#surf -#todo quota \"rating group\" #ocs|#pulse")
        XCTAssertEqual(q.tagClauses, [.anyOf(["surf"]), .excluding("todo"), .anyOf(["ocs", "pulse"])])
        XCTAssertEqual(q.terms, ["quota"])
        XCTAssertEqual(q.phrases, ["rating group"])
    }

    func testWhitespaceAndCase() {
        let q = SearchQuery.parse("   #SURF\t\t-#ToDo \n  QUOTA  ")
        XCTAssertEqual(q.tagClauses, [.anyOf(["surf"]), .excluding("todo")])
        XCTAssertEqual(q.terms, ["quota"])
    }

    func testDuplicateClausesCollapse() {
        XCTAssertEqual(SearchQuery.parse("#surf #SURF").tagClauses, [.anyOf(["surf"])])
        XCTAssertEqual(SearchQuery.parse("#a|#a|#b").tagClauses, [.anyOf(["a", "b"])])
    }

    func testEmptyInput() {
        XCTAssertTrue(SearchQuery.parse("").isEmpty)
        XCTAssertTrue(SearchQuery.parse("    ").isEmpty)
    }

    // MARK: Parser — malformed input degrades gracefully

    func testLoneHashIsIgnored() {
        XCTAssertTrue(SearchQuery.parse("#").isEmpty)
        XCTAssertTrue(SearchQuery.parse("-#").isEmpty)
        XCTAssertTrue(SearchQuery.parse("#|#").isEmpty)
        XCTAssertTrue(SearchQuery.parse("##").isEmpty)
    }

    func testLoneMinusIsIgnored() {
        XCTAssertTrue(SearchQuery.parse("-").isEmpty)
        XCTAssertEqual(SearchQuery.parse("- quota").terms, ["quota"])
    }

    func testUnclosedQuoteRunsToEnd() {
        XCTAssertEqual(SearchQuery.parse("#surf \"rating gr").phrases, ["rating gr"])
        XCTAssertTrue(SearchQuery.parse("\"").isEmpty)
        XCTAssertTrue(SearchQuery.parse("\"   \"").isEmpty)
    }

    func testNegationInsideOrGroupIsDropped() {
        XCTAssertEqual(SearchQuery.parse("#a|-#b").tagClauses, [.anyOf(["a"])])
    }

    func testExcludedGroupExcludesEach() {
        XCTAssertEqual(SearchQuery.parse("-#a|#b").tagClauses, [.excluding("a"), .excluding("b")])
    }

    func testTrailingSlashesNormalized() {
        XCTAssertEqual(SearchQuery.parse("#ocs/").tagClauses, [.anyOf(["ocs"])])
    }

    // MARK: Editing

    func testReplaceTagsKeepsText() {
        var q = SearchQuery.parse("#surf -#todo quota")
        q.replaceTags(with: "OCS")
        XCTAssertEqual(q.tagClauses, [.anyOf(["ocs"])])
        XCTAssertEqual(q.terms, ["quota"])
    }

    func testToggleAddsThenRemoves() {
        var q = SearchQuery.parse("#surf")
        q.toggle(tag: "todo")
        XCTAssertEqual(q.tagClauses, [.anyOf(["surf"]), .anyOf(["todo"])])
        q.toggle(tag: "surf")
        XCTAssertEqual(q.tagClauses, [.anyOf(["todo"])])
    }

    func testToggleRemovesFromOrGroupAndExclusion() {
        var q = SearchQuery.parse("#ocs|#pulse -#todo")
        q.toggle(tag: "pulse")
        XCTAssertEqual(q.tagClauses, [.anyOf(["ocs"]), .excluding("todo")])
        q.toggle(tag: "todo")
        XCTAssertEqual(q.tagClauses, [.anyOf(["ocs"])])
    }

    func testExcludeReplacesInclusion() {
        var q = SearchQuery.parse("#surf #todo")
        q.exclude(tag: "todo")
        XCTAssertEqual(q.tagClauses, [.anyOf(["surf"]), .excluding("todo")])
    }

    func testClauseTextRoundTrips() {
        let q = SearchQuery.parse("#ocs|#pulse -#todo")
        let text = q.tagClauses.map(\.text).joined(separator: " ")
        XCTAssertEqual(text, "#ocs|#pulse -#todo")
        XCTAssertEqual(SearchQuery.parse(text), q)
    }

    // MARK: Evaluation

    private let surfQuota = makeNote(["surf"], title: "Quota review", body: "the Rating Group limits")
    private let surfTodo = makeNote(["surf", "todo"], body: "quota for tomorrow")
    private let surfPlain = makeNote(["surf"], body: "nothing relevant")
    private let ocsChild = makeNote(["ocs/diameter"], body: "CCR quota")
    private let pulse = makeNote(["pulse"], body: "config")
    private var all: [Note] { [surfQuota, surfTodo, surfPlain, ocsChild, pulse] }

    private func ids(_ query: String) -> [UUID] {
        SearchQuery.parse(query).evaluate(all, index: TagIndex(notes: all)).map(\.id)
    }

    func testEmptyQueryReturnsAllInOrder() {
        XCTAssertEqual(ids(""), all.map(\.id))
    }

    func testAcceptanceExample() {
        XCTAssertEqual(ids("#surf -#todo quota"), [surfQuota.id])
    }

    func testTextMatchesTitleAndBodyCaseInsensitively() {
        XCTAssertEqual(ids("QUOTA"), [surfQuota.id, surfTodo.id, ocsChild.id])
        XCTAssertEqual(ids("review"), [surfQuota.id])
    }

    func testTextDoesNotMatchTagNames() {
        XCTAssertEqual(ids("pulse"), [])
    }

    func testPhraseRequiresAdjacency() {
        XCTAssertEqual(ids("\"rating group\""), [surfQuota.id])
        XCTAssertEqual(ids("\"group rating\""), [])
    }

    func testOrGroupEvaluation() {
        XCTAssertEqual(ids("#ocs|#pulse"), [ocsChild.id, pulse.id])
    }

    func testParentTagMatchesDescendants() {
        XCTAssertEqual(ids("#ocs"), [ocsChild.id])
        XCTAssertEqual(ids("#ocs/diameter"), [ocsChild.id])
        XCTAssertEqual(ids("#ocs/diameter/ccr"), [])
    }

    func testChildTagDoesNotMatchParent() {
        let parentOnly = makeNote(["ocs"])
        let notes = [parentOnly, ocsChild]
        let result = SearchQuery.parse("#ocs/diameter").evaluate(notes, index: TagIndex(notes: notes))
        XCTAssertEqual(result.map(\.id), [ocsChild.id])
    }

    func testExclusionRemovesSubtree() {
        XCTAssertEqual(ids("quota -#ocs"), [surfQuota.id, surfTodo.id])
    }

    func testUnknownTagMatchesNothing() {
        XCTAssertEqual(ids("#nope"), [])
        XCTAssertEqual(ids("-#nope").count, all.count)
    }

    // MARK: Field text helpers

    func testExtractOnlyTerminatedTags() {
        XCTAssertNil(SearchQuery.extractTags(from: "#su"))
        let r = SearchQuery.extractTags(from: "#surf quo")
        XCTAssertEqual(r?.clauses, [.anyOf(["surf"])])
        XCTAssertEqual(r?.remaining, "quo")
    }

    func testExtractKeepsTrailingSpace() {
        let r = SearchQuery.extractTags(from: "quota -#todo ")
        XCTAssertEqual(r?.clauses, [.excluding("todo")])
        XCTAssertEqual(r?.remaining, "quota ")
    }

    func testExtractIncludingTrailing() {
        let r = SearchQuery.extractTags(from: "quota #surf", includeTrailing: true)
        XCTAssertEqual(r?.clauses, [.anyOf(["surf"])])
        XCTAssertEqual(r?.remaining, "quota")
    }

    func testExtractIgnoresHashInsidePhrase() {
        XCTAssertNil(SearchQuery.extractTags(from: "\"#not a tag\" "))
    }

    func testCompletionContext() {
        XCTAssertEqual(SearchQuery.completionContext(in: "#Su"), .init(prefix: "su", isExclusion: false))
        XCTAssertEqual(SearchQuery.completionContext(in: "quota -#to"), .init(prefix: "to", isExclusion: true))
        XCTAssertEqual(SearchQuery.completionContext(in: "#ocs|#pu"), .init(prefix: "pu", isExclusion: false))
        XCTAssertEqual(SearchQuery.completionContext(in: "#"), .init(prefix: "", isExclusion: false))
        XCTAssertNil(SearchQuery.completionContext(in: "#surf "))
        XCTAssertNil(SearchQuery.completionContext(in: "quota"))
        XCTAssertNil(SearchQuery.completionContext(in: "\"a #b"))
        XCTAssertNil(SearchQuery.completionContext(in: ""))
    }

    func testApplyingCompletion() {
        XCTAssertEqual(SearchQuery.applyingCompletion("surf", to: "quota #su"), "quota #surf ")
        XCTAssertEqual(SearchQuery.applyingCompletion("todo", to: "-#t"), "-#todo ")
        XCTAssertEqual(SearchQuery.applyingCompletion("pulse", to: "#ocs|#pu"), "#ocs|#pulse ")
        XCTAssertEqual(SearchQuery.applyingCompletion("surf", to: "quota"), "quota")
    }

    // MARK: Suggestions

    func testSuggestionRanking() {
        let counts = ["surf": 17, "sudoku": 1, "shell": 6, "ocs/diameter": 2, "ocs": 3, "status": 9]
        XCTAssertEqual(TagSuggester.rank("su", counts: counts).map(\.path), ["surf", "sudoku", "status"])
        XCTAssertEqual(TagSuggester.rank("diam", counts: counts).map(\.path), ["ocs/diameter"])
        XCTAssertEqual(TagSuggester.rank("", counts: counts, limit: 2).map(\.path), ["surf", "status"])
        XCTAssertEqual(TagSuggester.rank("su", counts: counts, excluding: ["surf"]).first?.path, "sudoku")
        XCTAssertEqual(TagSuggester.rank("su", counts: counts).first?.count, 17)
    }

    func testSegmentPrefixOutranksSubsequence() {
        let counts = ["x/diameter": 1, "dxixaxm": 50]
        XCTAssertEqual(TagSuggester.rank("diam", counts: counts).map(\.path), ["x/diameter", "dxixaxm"])
    }
}
