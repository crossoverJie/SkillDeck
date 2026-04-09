import XCTest
@testable import SkillDeck

final class TranslationServiceTests: XCTestCase {

    private actor FakeClient: LocalTranslationClient {
        private(set) var calls: [String] = []
        let result: String

        init(result: String) {
            self.result = result
        }

        func translateEnglishToChinese(_ text: String) async throws -> String {
            calls.append(text)
            return result
        }
    }

    func testTranslateEnglishToChinese_cachesByExactText() async throws {
        let client = FakeClient(result: "你好")
        let service = TranslationService(client: client)

        let t1 = try await service.translateEnglishToChinese("Hello")
        let t2 = try await service.translateEnglishToChinese("Hello")

        XCTAssertEqual(t1, "你好")
        XCTAssertEqual(t2, "你好")

        let calls = await client.calls
        XCTAssertEqual(calls, ["Hello"])
    }

    func testCanonicalEnglishToSimplifiedChineseTranslationPair_usesExplicitSupportedIdentifiers() {
        XCTAssertEqual(
            TranslationLanguagePair.englishToSimplifiedChinese.source,
            Locale.Language(identifier: "en-US")
        )
        XCTAssertEqual(
            TranslationLanguagePair.englishToSimplifiedChinese.target,
            Locale.Language(identifier: "zh-Hans")
        )
    }
}
