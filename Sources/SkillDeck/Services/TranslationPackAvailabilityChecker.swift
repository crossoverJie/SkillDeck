import Foundation

#if canImport(Translation)
import Translation
#endif

struct TranslationPackAvailabilityChecker {
    enum Availability: Equatable {
        case installed
        case supportedButNotInstalled
        case unavailable
    }

    func englishToSimplifiedChinese() async -> Availability {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let pair = TranslationLanguagePair.englishToSimplifiedChinese
            let availability = LanguageAvailability()
            let status = await availability.status(
                from: pair.source,
                to: pair.target
            )

            switch status {
            case .installed:
                return .installed
            case .supported:
                return .supportedButNotInstalled
            case .unsupported:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }
        #endif

        return .unavailable
    }
}
