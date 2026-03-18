import XCTest
@testable import SkillDeck

final class TranslationServiceTests: XCTestCase {

    func testParseMyMemoryResponse_statusIsInt() throws {
        let json = """
        {
          \"responseData\": { \"translatedText\": \"你好，世界！\", \"match\": 1 },
          \"quotaFinished\": false,
          \"responseDetails\": \"\",
          \"responseStatus\": 200
        }
        """

        let translated = try MyMemoryResponseParser.parseTranslatedText(from: Data(json.utf8))
        XCTAssertEqual(translated, "你好，世界！")
    }

    func testParseMyMemoryResponse_statusIsString_andReturnsError() {
        let json = """
        {
          \"responseData\": { \"translatedText\": \"NO QUERY SPECIFIED. EXAMPLE REQUEST: GET?Q=HELLO&LANGPAIR=EN|IT\" },
          \"quotaFinished\": false,
          \"responseDetails\": \"NO QUERY SPECIFIED...\",
          \"responseStatus\": \"403\"
        }
        """

        XCTAssertThrowsError(try MyMemoryResponseParser.parseTranslatedText(from: Data(json.utf8)))
    }
}
