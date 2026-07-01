// swift-tools-version:5.9
import PackageDescription

// Prebuilt Realm binaries (xcframework), avoiding the ~10-minute from-source
// realm-core compile. Binaries are fetched + cached by SwiftPM (not committed).
// RealmSwift binary is Xcode-version-specific (@26.3 matches Xcode 26.3).
let package = Package(
    name: "RealmBinary",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "RealmSwift", targets: ["RealmSwift", "Realm"]),
    ],
    targets: [
        .binaryTarget(
            name: "Realm",
            url: "https://github.com/realm/realm-swift/releases/download/v20.0.4/Realm.spm.zip",
            checksum: "0b7cc34b1bf28d4e6e93bde58c567d0448248cfd9169f0033480704f2b92f379"
        ),
        .binaryTarget(
            name: "RealmSwift",
            url: "https://github.com/realm/realm-swift/releases/download/v20.0.4/RealmSwift@26.3.spm.zip",
            checksum: "1ddc329898480a94d4677997d81d77dc522a1621b4ac7c576d4cb3ef55683746"
        ),
    ]
)
