import Foundation

/// Central access point for SkillDeck's packaged resources.
///
/// Why does this exist?
/// - In Swift Package Manager (SPM), resources declared in `Package.swift` are bundled and
///   accessed via the synthesized `Bundle.module` value.
/// - `Bundle.module` is a *SwiftPM-generated* bundle that points at the target's resources.
///   It is only available from within the same Swift package target that declares the resources.
/// - By wrapping it here, we make the dependency explicit and keep the rest of the codebase
///   from sprinkling `Bundle.module` everywhere (which is analogous to hard-coding global
///   singletons in Java/Go/Python).
///
/// Note on naming:
/// - We call it `SkillDeckResources` (not just `Resources`) so it is discoverable in autocomplete
///   and unambiguous in a multi-module SwiftPM workspace.
enum SkillDeckResources {
    /// The base bundle that contains SkillDeck's packaged resources.
    ///
    /// Today this includes the app icon, and later it will include localization files
    /// (`*.lproj/Localizable.strings`, etc.).
    static var bundle: Bundle {
        Bundle.module
    }
}
