import XCTest

/// Guards on the module boundary, because no one of them alone holds it. Two read the
/// built product (`testBuiltBinaryReferencesOnlyAllowedModules` and the sibling that
/// asserts it inspected the right file), one keeps the adopter-view files importing the
/// module plainly, and two read the sources: `testNoHostLocalizationEscapeHatches` and
/// `testPortableFilesImportOnlyFoundation`, the one the README cites by name.
///
/// **What does NOT hold it: the compiler.** It is tempting to believe that a target with
/// no declared `dependencies:` cannot import a module it never asked for. It can. Build
/// systems that share one output directory across several targets also put that directory
/// on the search path, so once anything has built another module into it, importing that
/// module from here resolves and links. Whether it does depends on what else happened to
/// build first, so the same source can compile in one output directory and fail to find
/// the module in a fresh one.
///
/// So the boundary is held by *the absence of an artifact*, not by a rule, and a violation
/// builds green or red depending on what ran before it. That is worse than an unguarded
/// boundary: it is a nondeterministic one.
///
/// **Guard 1, `testBuiltBinaryReferencesOnlyAllowedModules`**, reads the built binary and
/// is therefore immune to spelling. It is the only check here that catches an import the
/// manifest never declared, and it catches every symbol that comes with one for free,
/// without anyone having to enumerate names.
///
/// It locates that binary rather than assuming its shape: an Xcode-driven build emits a
/// `.framework`, SwiftPM links the library statically into the test bundle's own
/// executable, and a loose dylib if a build ever produces one. Each shape is looked for in
/// turn, the one found is inspected, and finding none fails rather than skips.
///
/// **Guard 2, `testNoHostLocalizationEscapeHatches`**, covers what Guard 1 cannot see:
/// `NSLocalizedString`, `Bundle.main` and friends are *Foundation* symbols, so reaching
/// an adopter's string table through them leaves no trace at all in the binary. That
/// half needs a source-level check, and a source-level check is a denylist: it catches
/// the spellings someone thought of. Treat a green run as "none of these spellings",
/// never as "no coupling".
///
/// Scope, stated so a green run is not over-read: neither guard proves the package is free
/// of untranslated user-facing text, since a hardcoded English literal scores zero in both.
/// One such literal is known and deliberate: `ShortcutRecorder.swift` hardcodes its
/// VoiceOver label ("No shortcut" / "Shortcut: …"), which is read out in English whatever
/// language the rest of the window is in. It sits outside the injected string set on
/// purpose. Neither guard covers it, so a green run here says nothing about it.
final class ShortcutHelpLintTests: XCTestCase {

  // MARK: - Guard 1: the built product

  /// The modules this package's binary is allowed to reference.
  ///
  /// An allowlist, not a denylist: a denylist only catches the names somebody thought of.
  /// This asks the opposite question. Every module the binary reaches for must be one of
  /// these, and anything else fails whatever it is called.
  private static let allowedModules: Set<String> = [
    "Swift", "Foundation", "ObjectiveC", "Darwin", "Dispatch", "os",
    "AppKit", "SwiftUI", "Combine", "CoreGraphics", "CoreFoundation",
    "QuartzCore", "Carbon", "HIToolbox", "Observation", "_Concurrency",
    "XCTest", "Testing",
    "ShortcutHelpKit", "ShortcutHelpKitTests",
  ]

  /// The module a mangled Swift symbol belongs to, or nil when the symbol names no module.
  ///
  /// Swift mangles `_$s` followed by a length-prefixed identifier. For most symbols that
  /// identifier is the module. For associated-type descriptors it is the associated type
  /// instead. `_$s4Body7SwiftUI4ViewPTl` starts with `Body`, not `SwiftUI`, and those all
  /// end in `Tl`, so they are dropped rather than misread as a module named `Body`. The
  /// caller asserts the result is non-empty, so a parse that stopped returning modules
  /// fails rather than passing on an empty set.
  static func moduleOfMangledSymbol(_ symbol: String) -> String? {
    guard !symbol.hasSuffix("Tl"), symbol.hasPrefix("_$s") else { return nil }
    var rest = Substring(symbol.dropFirst(3))
    let digits = rest.prefix(while: \.isNumber)
    guard let length = Int(digits), length > 0 else { return nil }
    rest = rest.dropFirst(digits.count)
    guard rest.count >= length else { return nil }
    return String(rest.prefix(length))
  }

  /// Where the library's compiled code ends up, which is not the same place in every build
  /// system. Returned with a label so a failure says which shape it inspected.
  ///
  /// - An Xcode-driven build puts a `.framework` beside the test bundle.
  /// - SwiftPM links a library target *statically into the test binary*: no `.dylib` and
  ///   no separate product appears in `.build/debug`, and the library's symbols live inside
  ///   `…PackageTests.xctest/Contents/MacOS/…`. So under SwiftPM the test bundle's own
  ///   executable IS the artifact, and scanning it covers the library. The sibling test
  ///   asserts that the file picked here really does carry them.
  ///
  /// Order matters: prefer the framework when both exist, so the Xcode run keeps inspecting
  /// exactly the library and not the library-plus-tests.
  private static func libraryBinary() -> (url: URL, shape: String)? {
    let bundle = Bundle(for: Self.self)
    let products = bundle.bundleURL.deletingLastPathComponent()
    let fm = FileManager.default

    let framework = products
      .appendingPathComponent("ShortcutHelpKit.framework/Versions/A/ShortcutHelpKit")
    if fm.fileExists(atPath: framework.path) { return (framework, "framework") }

    let dylib = products.appendingPathComponent("libShortcutHelpKit.dylib")
    if fm.fileExists(atPath: dylib.path) { return (dylib, "dylib") }

    if let executable = bundle.executableURL, fm.fileExists(atPath: executable.path) {
      return (executable, "statically linked into the test bundle")
    }
    return nil
  }

  /// Reads the library's compiled code and asserts every module it references is allowed.
  /// Structural, not textual: it sees through any spelling, any whitespace, and any
  /// indirection a source lint would miss.
  ///
  /// Runs with the ordinary suite, so it holds on every build rather than on a separate
  /// one somebody has to remember.
  ///
  /// ⚠️ Not-found is a failure, never a skip. Hardcoding the framework path passes under
  /// Xcode and fails the moment the package is built as a plain SwiftPM
  /// package. Turning that into a skip would have been worse, because the guard would report green
  /// in exactly the build layout it exists to guard.
  func testBuiltBinaryReferencesOnlyAllowedModules() throws {
    guard let (binary, shape) = Self.libraryBinary() else {
      return XCTFail("found no ShortcutHelpKit binary to inspect beside "
                     + "\(Bundle(for: Self.self).bundleURL.path); this guard cannot run, "
                     + "which is not the same as passing")
    }

    // Undefined symbols, not load commands: a Swift symbol from another module can be
    // referenced without a matching LC_LOAD_DYLIB, so `otool -L` alone would miss it.
    let undefined = try Self.run("/usr/bin/nm", ["-u", binary.path])
    let referenced = Set(undefined
      .split(separator: "\n")
      .compactMap { Self.moduleOfMangledSymbol($0.trimmingCharacters(in: .whitespaces)) })
    XCTAssertFalse(referenced.isEmpty,
      "no Swift module references found in \(shape); the symbol parse broke, so this "
      + "assertion would pass on anything")
    let offenders = referenced.subtracting(Self.allowedModules).sorted()
    XCTAssertEqual(offenders, [],
      "the package's binary (\(shape)) references modules outside the allowed set: "
      + "\(offenders.joined(separator: ", ")). An `import` slipped past the empty "
      + "dependencies list, which does not prevent one")
  }

  /// Guards the guard: proves `libraryBinary()` found something that actually contains the
  /// library, so a future build-layout change cannot quietly point it at an empty file and
  /// leave `testBuiltBinaryReferencesOnlyAllowedModules` passing on nothing.
  func testTheInspectedBinaryReallyContainsTheLibrary() throws {
    guard let (binary, shape) = Self.libraryBinary() else {
      return XCTFail("no ShortcutHelpKit binary found; see the sibling test")
    }
    let symbols = try Self.run("/usr/bin/nm", [binary.path])
    XCTAssertTrue(symbols.contains("ShortcutHelpKit"),
      "inspected \(binary.lastPathComponent) (\(shape)) but it carries no ShortcutHelpKit "
      + "symbols, so the boundary check would be scanning the wrong file")
  }

  private static func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: - Guard 1b: the files that stand in for an adopter

  /// Test files that must reach the library the way an adopter does, with no `@testable`.
  ///
  /// Marking a member public on an internal type compiles clean and exports nothing, so a
  /// missing `public` is invisible to a suite that runs under `@testable`. These files are
  /// where that mistake shows up **for the declarations they reference**, which is a subset
  /// of the public surface and not all of it. Nothing here computes that fraction, so do
  /// not read the list as coverage. A symbol no
  /// adopter-view file touches can still lose its `public` with this suite green, so
  /// widening the coverage means referencing more of the surface here, not trusting the
  /// list. Adding files is expected; the count below only makes shrinking it visible.
  private static let adopterViewFiles = [
    "ReadmeExample.swift",                    // the README's example, public API only
    "ShortcutModelTests.swift",               // pins the diagnostic surface and the audit
    "ShortcutBindingWireFormatTests.swift",   // pins the stored format
  ]

  func testAdopterViewFilesDoNotUseTestable() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var checked = 0
    for name in Self.adopterViewFiles {
      let url = dir.appendingPathComponent(name)
      guard let body = try? String(contentsOf: url, encoding: .utf8) else {
        XCTFail("\(name) is missing - the list names a file that no longer exists")
        continue
      }
      checked += 1
      // Matched against the normalised body, which blanks comments and string literals
      // before collapsing whitespace. Scanning raw lines instead let three spellings
      // through: a block comment ahead of the attribute, a second statement on the same
      // line after a semicolon, and - for the import check - the phrase appearing inside
      // a string literal, which is how a file that never imports the library at all
      // could satisfy the assertion that says it does.
      let normalized = Self.normalize(body)
      XCTAssertFalse(normalized.contains("@testableimport"),
                     "\(name) imports the library with @testable, which hides a missing public")
      XCTAssertTrue(normalized.contains("importShortcutHelpKit"),
                    "\(name) does not import the library at all, so it proves nothing")
    }
    // The list is self-declared, so this anchor is what makes shortening it visible -
    // the cheapest way to defeat the guard, and the one a reader of the diff would not
    // notice. Growing the list is fine and only needs the number updated; shrinking it
    // should be deliberate.
    XCTAssertEqual(checked, Self.adopterViewFiles.count,
                   "a file was skipped without failing - the loop above grew a path it does not check")
    XCTAssertGreaterThanOrEqual(Self.adopterViewFiles.count, 3,
                                "the adopter-view list lost an entry - shortening it defeats the guard")
  }

  // MARK: - Guard 2: the sources

  /// Every Swift file the `ShortcutHelpKit` target compiles.
  ///
  /// Enumerated recursively on purpose: the target's source glob is
  /// `Sources/ShortcutHelpKit/**/*.swift`, so a file in a subdirectory would be compiled
  /// into the package while a flat `contentsOfDirectory` walk silently skipped it, a lint
  /// that cannot see a file cannot catch anything in it. A recursive enumerator also
  /// reaches hidden directories, so the enumerated set is never narrower than the
  /// compiled set.
  private func shortcutHelpSources() throws -> [(name: String, body: String)] {
    let dir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()   // Tests/ShortcutHelpKitTests
      .deletingLastPathComponent()   // Tests
      .deletingLastPathComponent()   // repo root
      .appendingPathComponent("Sources/ShortcutHelpKit")

    let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
    let urls = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }

    // Two separate guards against a vacuous pass. `isEmpty` catches a path that resolved
    // nowhere; the identity check catches a path that resolved to a *wrong but populated*
    // directory: a sibling of the real one would satisfy `isEmpty` and prove nothing.
    // Deliberately not a count: the package is expected to gain files.
    XCTAssertFalse(urls.isEmpty, "no Swift sources found at \(dir.path)")
    let names = Set(urls.map(\.lastPathComponent))
    for expected in ["KeyboardShortcutsView.swift", "ShortcutModel.swift", "ShortcutRecorder.swift"] {
      XCTAssertTrue(names.contains(expected), "\(dir.path) is not ShortcutHelpKit; \(expected) is missing")
    }

    return try urls.map { (name: $0.lastPathComponent, body: try String(contentsOf: $0, encoding: .utf8)) }
  }

  /// Removes comments and string-literal contents, then removes whitespace.
  ///
  /// A plain `//`-to-end-of-line strip is not enough in either direction. It leaves
  /// `/* … */` intact, so a file *documenting* that the package must not touch
  /// `Bundle.main` fails the lint, the exact scenario comment-stripping exists to
  /// prevent. And it truncates at a `//` inside a string literal (`"https://…"`), hiding
  /// any real violation later on that line. Both are handled by scanning states rather
  /// than searching for a delimiter.
  ///
  /// Whitespace goes last so the needles cannot be split by formatting: `Bundle . main`
  /// and a `Bundle`/`.main` line break both collapse to `Bundle.main`.
  static func normalize(_ source: String) -> String {
    enum State { case code, line, block, string }
    var state = State.code
    var out = ""
    var escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
      switch state {
      case .code:
        if c == "/", next == "/" { state = .line; i += 2; continue }
        if c == "/", next == "*" { state = .block; i += 2; continue }
        if c == "\"" { state = .string; escaped = false; out.append("\"\""); i += 1; continue }
        out.append(c)
      case .line:
        if c == "\n" { state = .code; out.append(c) }
      case .block:
        if c == "*", next == "/" { state = .code; i += 2; continue }
        if c == "\n" { out.append(c) }   // keep line structure
      case .string:
        if escaped { escaped = false }
        else if c == "\\" { escaped = true }
        else if c == "\"" { state = .code }
        else if c == "\n" { state = .code; out.append(c) }   // unterminated: fail open to code
      }
      i += 1
    }
    return out.filter { !$0.isWhitespace }
  }

  /// The Foundation-shaped escape hatches, written whitespace-free because `normalize`
  /// strips whitespace from the body before matching.
  ///
  /// The list names Foundation and SwiftUI APIs and nothing else. A localization helper the
  /// host defines is out of reach by construction: this package declares no such function,
  /// so a call to one does not compile here and the compiler says so before any lint runs.
  ///
  /// `Bundle(` deliberately has no argument label: it covers `for:`, `identifier:`,
  /// `path:` and `url:` in one, rather than enumerating the ones someone thought of.
  ///
  /// `Bundle.module` is not reachable today, since the target declares no resources, so no
  /// accessor is synthesized and writing it would not compile. It is listed so the guard is
  /// already in place on the day resources are added, which is precisely the day someone
  /// would be tempted to give this package its own string table. Whether it should ever have
  /// one is an open question this lint does not settle.
  ///
  /// `Text("` is the subtlest of these, and the one most likely to be written by habit.
  /// A string *literal* binds `Text.init(_: LocalizedStringKey)`, whose `bundle` defaults
  /// to `Bundle.main`, so `Text("Shortcuts")` inside this package silently reads the
  /// adopter's table and, wherever that adopter happens to carry these keys, renders
  /// correctly there and wrongly everywhere else. Passing a `String` variable binds the verbatim
  /// overload instead and is fine; every call site in the package does that today.
  private static let needles = [
    "NSLocalizedString",
    "String(localized:",
    "LocalizedStringKey",
    "localizedStringResource",
    "Text(\"",
    "Bundle(",
    "Bundle.main",
    "Bundle.module",
    "Bundle.allBundles",
  ]

  /// The README tells a consumer that six of the ten sources are Foundation-only and names
  /// this test as what enforces it. Without the test that sentence is a property that holds
  /// today, written down as though it were structural.
  ///
  /// This test is what makes that true. Adding `import AppKit` to `ShortcutModel` fails
  /// here instead of quietly making the README wrong.
  ///
  /// Why it matters beyond tidiness: those six files are the portable half of the
  /// package. If a non-macOS target is ever wanted, they are what can move.
  ///
  /// ⚠️ The list below is hand-maintained, so a new portable file is covered only once
  /// someone adds it here. A new portable file that nobody adds leaves the README claiming
  /// enforcement this list does not provide. The count assertion that follows exists so
  /// such an omission fails instead of passing quietly.
  func testPortableFilesImportOnlyFoundation() throws {
    let portable = ["ShortcutModel.swift", "ShortcutCatalog.swift", "ShortcutProjection.swift",
                    "ShortcutHelpStrings.swift", "KeyboardLayout.swift", "HighlightAudit.swift"]
    let sources = Dictionary(uniqueKeysWithValues: try shortcutHelpSources().map { ($0.name, $0.body) })

    // A file is portable or it is macOS-only; there is no third category. Enumerating both
    // halves means a new source has to be classified rather than silently uncovered.
    let macOSOnly = ["KeyboardIllustration.swift", "KeycapView.swift",
                     "KeyboardShortcutsView.swift", "ShortcutRecorder.swift"]
    XCTAssertEqual(Set(portable).union(macOSOnly), Set(sources.keys),
      "a source file is in neither list; classify it, then update the README's census")

    for name in portable {
      let body = try XCTUnwrap(sources[name], "\(name) is gone; update this list deliberately")
      let imports = body.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("import ") }
        .map { String($0.dropFirst("import ".count)) }
      XCTAssertEqual(imports, ["Foundation"],
        "\(name) is documented as Foundation-only; it now imports \(imports)")
    }
  }

  func testNoHostLocalizationEscapeHatches() throws {
    var offenders: [String] = []
    for file in try shortcutHelpSources() {
      let body = Self.normalize(file.body)
      for needle in Self.needles where body.contains(needle) {
        offenders.append("\(file.name): \(needle)")
      }
    }
    XCTAssertEqual(offenders.sorted(), [],
      "the package must not reach for a bundle; the host injects every user-visible string")
  }

  /// Negative control for the adopter-view matcher, and the reason it runs on the
  /// normalised body rather than raw lines. Scanning line prefixes instead lets a block
  /// comment ahead of the attribute, or a semicolon before it, slip through while still
  /// granting internal access, and it lets the import check be satisfied by the phrase
  /// appearing inside a string literal, which a file that never imports the library can do.
  func testAdopterViewMatcherCatchesEverySpelling() {
    let violations = [
      "@testable import ShortcutHelpKit",
      "/* x */@testable import ShortcutHelpKit",
      "import XCTest; @testable import ShortcutHelpKit",
      "#if DEBUG\n@testable import ShortcutHelpKit\n#endif",
      "  @testable   import   ShortcutHelpKit",
    ]
    for source in violations {
      XCTAssertTrue(Self.normalize(source).contains("@testableimport"),
                    "the matcher misses this spelling: \(source)")
    }

    let benign = [
      "import ShortcutHelpKit   // deliberately not @testable",
      "/// Under @testable this file would compile against internal symbols.",
      "let sample = \"@testable import ShortcutHelpKit\"",
    ]
    for source in benign {
      XCTAssertFalse(Self.normalize(source).contains("@testableimport"),
                     "the matcher reads its own rationale as a violation: \(source)")
    }

    // The companion check has the same failure mode in reverse: prose and literals must
    // not be able to satisfy "this file imports the library".
    XCTAssertTrue(Self.normalize("import ShortcutHelpKit").contains("importShortcutHelpKit"))
    XCTAssertFalse(Self.normalize("// import ShortcutHelpKit").contains("importShortcutHelpKit"))
    XCTAssertFalse(Self.normalize("let s = \"import ShortcutHelpKit\"").contains("importShortcutHelpKit"))
  }

  /// Negative control. Without this, an accidentally emptied `needles` array, or a
  /// `normalize` that swallowed everything, would leave the lint permanently green and
  /// nothing would say so.
  func testNormalizeAndNeedlesActuallyMatch() {
    let violations = [
      "let x = Bundle.main",
      "let x = Bundle . main",
      "let x = Bundle\n  .main",
      "let x = Bundle(for: Self.self)",
      "let x = Bundle(identifier: \"com.example.app\")",
      "let x = NSLocalizedString(\"k\", comment: \"\")",
      "let x = String(localized: \"k\")",
      "var body: some View { Text(\"Shortcuts\") }",
    ]
    for source in violations {
      let body = Self.normalize(source)
      XCTAssertTrue(Self.needles.contains { body.contains($0) }, "no needle matched: \(source)")
    }

    // …and the two shapes that must NOT match, or the lint blocks legitimate work.
    let benign = [
      "/* This package must never call Bundle.main; the host injects strings. */",
      "/// Never reach for NSLocalizedString here.",
      "let url = \"https://example.com/NSLocalizedString\"",
      "Text(strings.title)",   // a String variable binds the verbatim overload, legitimate
    ]
    for source in benign {
      let body = Self.normalize(source)
      XCTAssertFalse(Self.needles.contains { body.contains($0) }, "false positive: \(source)")
    }
  }
}
