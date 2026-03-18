import Foundation

/// Translate short English snippets to Simplified Chinese (zh-CN) using MyMemory.
actor TranslationService {

    enum TranslationError: Error, LocalizedError {
        case invalidURL
        case networkError(String)
        case invalidHTTPStatus(Int)
        case invalidResponse
        case quotaFinished
        case apiError(code: Int, message: String)
        case textTooLong(maxBytes: Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid translation URL"
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidHTTPStatus(let code):
                return "Server returned status \(code)"
            case .invalidResponse:
                return "Invalid translation response"
            case .quotaFinished:
                return "Translation quota finished"
            case .apiError(let code, let message):
                return "Translation API error \(code): \(message)"
            case .textTooLong(let maxBytes):
                return "Text too long (max \(maxBytes) bytes)"
            }
        }
    }

    private let session: URLSession
    private var cache: [String: String] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translateEnglishToChinese(_ text: String) async throws -> String {
        if let cached = cache[text] {
            return cached
        }

        let maxBytes = 500
        if text.utf8.count > maxBytes {
            throw TranslationError.textTooLong(maxBytes: maxBytes)
        }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|zh-CN")
        ]
        guard let url = components?.url else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SkillDeck", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw TranslationError.invalidHTTPStatus(http.statusCode)
        }

        let translated = try MyMemoryResponseParser.parseTranslatedText(from: data)
        cache[text] = translated
        return translated
    }
}

/// Parsing is separate to keep unit tests network-free.
enum MyMemoryResponseParser {

    struct MyMemoryResponse: Decodable {
        struct ResponseData: Decodable {
            let translatedText: String
        }

        let responseData: ResponseData
        let quotaFinished: Bool?
        let responseDetails: String?
        let responseStatus: StatusCode
    }

    /// MyMemory may encode `responseStatus` as an Int or a String; we accept both.
    struct StatusCode: Decodable {
        let value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self.value = intValue
                return
            }
            if let stringValue = try? container.decode(String.self),
               let intValue = Int(stringValue) {
                self.value = intValue
                return
            }
            throw TranslationService.TranslationError.invalidResponse
        }
    }

    static func parseTranslatedText(from data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response = try decoder.decode(MyMemoryResponse.self, from: data)

        if response.quotaFinished == true {
            throw TranslationService.TranslationError.quotaFinished
        }

        if response.responseStatus.value != 200 {
            let message = response.responseDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranslationService.TranslationError.apiError(
                code: response.responseStatus.value,
                message: (message?.isEmpty == false) ? (message ?? "") : "Unknown error"
            )
        }

        return response.responseData.translatedText
    }
}
