import CoreText
import Foundation
import UIKit

/// Fonts are installed from the same verified resource manifest as the scenes.
/// Registration is process-local and never changes the user's system fonts.
@MainActor
enum ArenaImportedFonts {
    private static var ownedURLs = Set<URL>()
    private static var loadedIdentity: String?
    private(set) static var availableNames = Set<String>()

    static func prepare(manifest: ArenaResourcePackManifest, resourceURL: (String) -> URL?) {
        let identity = (manifest.fonts ?? []).compactMap { font in
            manifest.files.first(where: { $0.path == font.file }).map { font.file + ":" + $0.sha256 }
        }.joined(separator: "|")
        guard identity != loadedIdentity else { return }
        for url in ownedURLs { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        ownedURLs.removeAll()
        availableNames.removeAll()
        loadedIdentity = identity
        for font in manifest.fonts ?? [] {
            guard let url = resourceURL(font.file) else { continue }
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  descriptors.contains(where: {
                      CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == font.postScriptName
                  }) else { continue }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { ownedURLs.insert(url) }
            if UIFont(name: font.postScriptName, size: 16) != nil { availableNames.insert(font.postScriptName) }
        }
    }
}
