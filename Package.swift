// swift-tools-version: 6.0
import PackageDescription

// Carbon is not declared as a dependency. SPM handles the Clang autolink on its own, so
// the framework is linked without a linkerSettings entry.
let package = Package(
    name: "ShortcutHelpKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShortcutHelpKit", targets: ["ShortcutHelpKit"]),
    ],
    targets: [
        // swiftLanguageMode(.v6) is not decoration. KeyboardShortcutsView takes
        // `RebindFeedback()` as a default argument, which is an isolated default value
        // expression (SE-0411) and a v6-only rule, so falling back to v5 is a compile
        // error. tools-version 6.0 alone does not carry it: a tool that rewrites this
        // package into a generated Xcode target can drop the language mode and build with
        // -swift-version 5 instead. A plain swift build never shows that.
        .target(
            name: "ShortcutHelpKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShortcutHelpKitTests",
            dependencies: ["ShortcutHelpKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
