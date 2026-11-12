import XCTest
@testable import MagRead

final class ArticleVocabularyTests: XCTestCase {
    private func entry(_ word: String, meaning: String = "测试释义", phrase: Bool = false) -> VocabularyEntry {
        VocabularyEntry(word: word, phonetic: "", meaning: meaning, context: "", root: "", isPhrase: phrase)
    }

    func testBatchPlanReusesLevelCacheAndIncludesTitle() {
        let article = Article(id: 0, title: "A candid conversation", paragraphs: ["First paragraph", "Second paragraph", " "])
        let cache: [String: [VocabularyEntry]] = ["四级:0": [], "六级:1": []]
        let batches = ArticleVocabulary.batches(article, level: "四级", cache: cache)
        XCTAssertEqual(batches.flatMap { $0.map(\.paragraph) }, [-1, 1])
        XCTAssertEqual(ArticleVocabulary.completed(article, level: "四级", cache: cache), 1)
        XCTAssertEqual(ArticleVocabulary.sections(article).count, 3)
    }

    func testLongParagraphsAreFullyPreservedAndRequestsAreBounded() {
        let text = String(repeating: "We chart our own path. ", count: 1000) + "最后一个词"
        let article = Article(id: 0, title: "Title", paragraphs: [text])
        let batches = ArticleVocabulary.batches(article, level: "四级", cache: [:])
        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertTrue(batches.allSatisfy { $0.count <= 4 && $0.reduce(0, { $0 + $1.text.count }) <= 3500 })
        XCTAssertEqual(batches.flatMap { $0 }.filter { $0.paragraph == 0 }.map(\.text).joined(), text)
        let indices = batches.flatMap { $0.map(\.index) }
        XCTAssertEqual(indices.count, Set(indices).count)
    }

    func testResponseRequiresEveryIndexIncludingEmptyLists() throws {
        let segments = [VocabularySegment(index: 5, paragraph: 7, text: "Simple text.")]
        let response = "```json\n{\"paragraphs\":[{\"index\":5,\"entries\":[]}]}\n```"
        XCTAssertEqual(try ArticleVocabulary.decode(response, expected: segments)[5], [])
        for invalid in [
            #"{"paragraphs":[]}"#,
            #"{"paragraphs":[{"index":7,"entries":[]}]}"#,
            #"{"paragraphs":[{"index":5,"entries":[]},{"index":5,"entries":[]}]}"#,
            #"{"paragraphs":[{"index":5,"entries":[{"word":"","phonetic":"","meaning":"test","context":"","root":"","isPhrase":false}]}]}"#
        ] {
            XCTAssertThrowsError(try ArticleVocabulary.decode(invalid, expected: segments))
        }
    }

    func testAggregationMergesSameSenseAndRetainsDifferentMeanings() {
        let article = Article(id: 0, title: "Chart your path", paragraphs: ["A chart on the wall.", "Chart a course."])
        let verb = entry("chart", meaning: "动词：规划")
        let noun = entry("chart", meaning: "名词：图表")
        let items = ArticleVocabulary.items(article, level: "四级", cache: ["四级:-1": [verb], "四级:0": [noun], "四级:1": [verb]], personal: [])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].paragraphs, [-1, 1])
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertEqual(items[0].location, "标题 · 第 2 段")
    }

    func testPersonalWordsMatchWholeWordsAndPhrases() {
        let article = Article(id: 0, title: "An account", paragraphs: ["A candid conversation. We chart our own path.", "Her candidacy was announced."])
        let candid = entry("candid")
        let phrase = entry("our own path", phrase: true)
        let items = ArticleVocabulary.items(article, level: "四级", cache: ["四级:0": [candid]], personal: [candid, phrase, entry("can"), entry("")])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy(\.personal))
        XCTAssertEqual(items[0].paragraphs, [0])
        XCTAssertTrue(items[1].entry.isPhrase)
    }

    @MainActor
    func testCompletedArticleMakesNoRequests() async throws {
        let article = Article(id: 0, title: "Title", paragraphs: ["Simple text."])
        var calls = 0
        try await ArticleVocabulary.generate(article: article, level: "四级", cache: ["四级:-1": [], "四级:0": []]) { _ in
            calls += 1
            return [:]
        } save: { _, _ in XCTFail("Completed paragraphs must be reused") }
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testFailurePreservesCompletedParagraphsAndResumesOnlyMissingSections() async throws {
        let article = Article(id: 0, title: "Title", paragraphs: (0..<9).map { "Paragraph \($0)" })
        var cache: [String: [VocabularyEntry]] = [:]
        var calls = 0
        do {
            try await ArticleVocabulary.generate(article: article, level: "四级", cache: cache) { batch in
                calls += 1
                if calls == 2 { throw ReaderError.message("Simulated failure") }
                return Dictionary(uniqueKeysWithValues: batch.map { ($0.index, [self.entry("word-\($0.paragraph)")]) })
            } save: { paragraph, entries in cache[ArticleVocabulary.cacheKey(level: "四级", paragraph: paragraph)] = entries }
            XCTFail("The second request should fail")
        } catch { }
        XCTAssertEqual(cache.count, 4)
        var requested: [Int] = []
        try await ArticleVocabulary.generate(article: article, level: "四级", cache: cache) { batch in
            requested += batch.map(\.paragraph)
            return Dictionary(uniqueKeysWithValues: batch.map { ($0.index, []) })
        } save: { paragraph, entries in cache[ArticleVocabulary.cacheKey(level: "四级", paragraph: paragraph)] = entries }
        XCTAssertEqual(requested, Array(3..<9))
        XCTAssertEqual(ArticleVocabulary.completed(article, level: "四级", cache: cache), 10)
    }

    @MainActor
    func testLongParagraphIsNotSavedUntilEveryFragmentCompletes() async throws {
        let text = String(repeating: "long paragraph ", count: 1000)
        let article = Article(id: 0, title: "Title", paragraphs: [text])
        var saved: [Int] = []
        var calls = 0
        do {
            try await ArticleVocabulary.generate(article: article, level: "四级", cache: ["四级:-1": []]) { batch in
                calls += 1
                if calls == 2 { throw ReaderError.message("Simulated failure") }
                return Dictionary(uniqueKeysWithValues: batch.map { ($0.index, []) })
            } save: { paragraph, _ in saved.append(paragraph) }
            XCTFail("The second request should fail")
        } catch { }
        XCTAssertTrue(saved.isEmpty)

        var entries: [VocabularyEntry] = []
        try await ArticleVocabulary.generate(article: article, level: "四级", cache: ["四级:-1": []]) { batch in
            return Dictionary(uniqueKeysWithValues: batch.map { ($0.index, [self.entry("same-word")]) })
        } save: { paragraph, words in saved.append(paragraph); entries = words }
        XCTAssertEqual(saved, [0])
        XCTAssertEqual(entries.count, 1)
    }

    @MainActor
    func testCancellationDiscardsCurrentResponseAndStopsFurtherRequests() async {
        let article = Article(id: 0, title: "Title", paragraphs: (0..<9).map { "Paragraph \($0)" })
        var saved: [Int] = []
        var calls = 0
        let task = Task { @MainActor in
            try await ArticleVocabulary.generate(article: article, level: "四级", cache: [:]) { batch in
                calls += 1
                if calls == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return Dictionary(uniqueKeysWithValues: batch.map { ($0.index, []) })
            } save: { paragraph, _ in saved.append(paragraph) }
        }
        do { try await task.value; XCTFail("Cancellation should propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(saved, [-1, 0, 1, 2])
    }

    @MainActor
    func testMissingParagraphResponseIsNeverSaved() async {
        let article = Article(id: 0, title: "Title", paragraphs: ["Paragraph"])
        do {
            try await ArticleVocabulary.generate(article: article, level: "四级", cache: [:]) { _ in [:] }
                save: { _, _ in XCTFail("Incomplete batch must not be cached") }
            XCTFail("Missing response should be rejected")
        } catch { }
    }
}
