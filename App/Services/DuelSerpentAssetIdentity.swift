import Foundation

/// Original v2 D13 match profile, supplied unchanged under the installed name.
/// These external build pins do not trust hashes advertised inside the JSON.
enum DuelSerpentAssetIdentity {
    static let profileName = "SF3_Serpent_Profile.json"
    static let profileSHA256 = "ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53"
    static let characterSHA256 = DuelSerpentBottlePresentation.characterSHA256
    /// H17 final victory targets this exact D13 actor. The legacy hammer
    /// manifest and Wu's separate material contract cannot stand in for it.
    static let victoryMorphManifestName = "SF3_H17_SerpentMorph.json"
    static let victoryMorphManifestSHA256 = "f2b3ab352b6a433fa7910fdc4c04508f9d1498c1933e4315269d2b77d10063bd"
}
