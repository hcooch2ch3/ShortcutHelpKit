import XCTest
import ShortcutHelpKit

/// The README quotes code to show how the package is used. Quoted code rots: the API
/// changes, the README keeps teaching the old shape, and nobody notices because
/// documentation has no compiler.
///
/// The quoted code therefore lives in `ReadmeExample.swift`, in this bundle, where it
/// **must compile**. This test closes the other half: that the README still quotes what
/// compiles. Two independent guards, because a snippet can be stale *and* plausible.
///
/// ## What this deliberately does not do
///
/// It reads only `Sources/ShortcutHelpKit` and this test bundle. Two things it avoids on
/// purpose, both easy to reach for:
///
/// 1. **Quoting a consumer.** A package README that quotes an app using the package is
///    documentation for the wrong reader. Someone without that app has to be able to use
///    the package, so the example has to be buildable from the public API alone.
/// 2. **Skipping when a directory is missing.** Such a skip cannot tell "directory absent"
///    from "enumeration returned nothing," so it can fire while the directory is present
///    and populated: a silent no-op explaining itself with a cause it never checked. There
///    is no skip path here at all. An empty enumeration is a broken environment and fails
///    loudly.
///
/// ## Honest scope
///
/// This asserts each quoted line still exists in a source file. It does not assert the
/// quote is *complete* or still *representative*: deleting a parameter from a fence
/// leaves the remaining lines matching, and a line can survive inside a function that no
/// longer means what the README says. `ReadmeExampleTests` covers the shape of the
/// example; the prose around it is still human work.
final class ReadmeFidelityTests: XCTestCase {

  private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()   // Tests/ShortcutHelpKitTests
      .deletingLastPathComponent()   // Tests
      .deletingLastPathComponent()   // repo root
  }

  /// Every Swift file under `relativePath`. A path that does not exist, or that exists
  /// and yields nothing, is a failure, never a reason to pass quietly.
  private func swiftFiles(under relativePath: String) throws -> [URL] {
    let url = repoRoot.appendingPathComponent(relativePath)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                  "\(relativePath) not found; path arithmetic is wrong")
    let all = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
      .allObjects as? [URL] ?? []
    let swift = all.filter { $0.pathExtension == "swift" }
    XCTAssertFalse(swift.isEmpty,
      "\(relativePath) exists but enumerated to nothing: a broken environment, not an "
      + "empty package. A macOS privacy gate on the enclosing folder does this: it returns "
      + "an empty enumeration rather than an error. Re-grant the folder in System "
      + "Settings. This fails rather than skips, because a silent pass here would "
      + "make the whole file a no-op that still reports green.")
    return swift
  }

  /// Lines inside ```swift fences, with comments and blank lines dropped and trailing
  /// explanatory comments trimmed.
  ///
  /// `significant` drops lines that are pure punctuation (`}`, `)`, `])`). Those match
  /// every Swift file ever written, so counting them toward the anti-vacuity threshold
  /// would let a README of nothing but closing braces look thoroughly verified.
  static func quotedSwiftLines(in readme: String) -> (all: [String], significant: [String]) {
    var lines: [String] = []
    var inSwift = false
    for raw in readme.split(separator: "\n", omittingEmptySubsequences: false) {
      if raw.hasPrefix("```swift") { inSwift = true; continue }
      if inSwift && raw.hasPrefix("```") { inSwift = false; continue }
      guard inSwift else { continue }
      var line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("//") { continue }
      if let r = line.range(of: "//"), r.lowerBound != line.startIndex {
        line = String(line[line.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
      }
      if !line.isEmpty { lines.append(line) }
    }
    let significant = lines.filter { line in
      line.contains { $0.isLetter || $0.isNumber }
        && line.filter({ $0.isLetter || $0.isNumber }).count >= 4
    }
    return (lines, significant)
  }

  /// The README declares the `.named` vocabulary **closed** and then enumerates it. That
  /// is a promise about a set the code owns, in the paragraph the README itself calls the
  /// silent-failure warning, and nothing else in the suite reads it.
  ///
  /// A cap can be added while that paragraph still lists the set without it, and the only
  /// other way to catch that is for someone to read the paragraph by hand.
  /// `testEveryQuotedSwiftLineExistsInSource` reads only fenced code, and only
  /// README-to-source, so a name the code has and the prose lacks is invisible to it by
  /// direction as well as by scope.
  ///
  /// ## Honest scope
  ///
  /// Only alphabetic names are compared, because the modifier glyphs live in one backticked
  /// group rather than one span each. That filter is a hole, so the glyph half is pinned
  /// separately below: the set of non-alphabetic named tokens must be exactly those four
  /// glyphs, which makes a fifth one, `⌫` as a token name, say, or `F1`, fail here rather
  /// than slip through the filter.
  ///
  /// Two things it still cannot do. It checks *membership in the paragraph*, not the
  /// enumerated sentence, so prose added to the same paragraph that contradicts the list
  /// passes. And it treats every all-letters backticked word as a claimed token name, so
  /// writing `` `keycap` `` in this paragraph fails the lint. If you need a backticked
  /// word here that is not a key name, the lint has to learn about it first.
  func testTheClosedVocabularyParagraphListsEveryNamedToken() throws {
    let readme = try String(
      contentsOf: repoRoot.appendingPathComponent("README.md"),
      encoding: .utf8)

    let lines = readme.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let start = lines.firstIndex(where: { $0.contains("vocabulary is closed") }) else {
      return XCTFail("the closed-vocabulary paragraph is gone; this lint now guards nothing")
    }
    let end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
      ?? lines.endIndex
    let paragraph = lines[start..<end].joined(separator: " ")

    // Backticked spans, keeping only the ones that are a bare identifier.
    let spans = paragraph.split(separator: "`").enumerated()
      .filter { $0.offset % 2 == 1 }.map { String($0.element) }
    let documented = Set(spans.filter { !$0.isEmpty && $0.allSatisfy(\.isLetter) })

    let actual = Set(KeyboardLayout.highlightableTokens.compactMap { token -> String? in
      guard case .named(let name) = token, name.allSatisfy(\.isLetter) else { return nil }
      return name
    })

    XCTAssertFalse(actual.isEmpty, "no alphabetic named tokens found; the filter is broken")
    XCTAssertEqual(documented, actual,
      "the README's closed `.named` vocabulary disagrees with the keycaps the grid draws. "
      + "Undocumented: \(actual.subtracting(documented).sorted()). "
      + "Documented but absent: \(documented.subtracting(actual).sorted()).")

    // The hole in the letters-only filter, closed from the code side. Any named token whose
    // name is not purely alphabetic is invisible to the comparison above, so the set of them
    // is pinned: a new one, a `⌫`-named cap, an `F1`, a `Page Up`, fails here instead of
    // entering a vocabulary the README calls closed with nothing noticing.
    let nonAlphabetic = Set(KeyboardLayout.highlightableTokens.compactMap { token -> String? in
      guard case .named(let name) = token, !name.allSatisfy(\.isLetter) else { return nil }
      return name
    })
    XCTAssertEqual(nonAlphabetic, ["⌘", "⌥", "⌃", "⇧"],
      "a named token sits outside this lint's letters-only comparison and it cannot see it: "
      + "\(nonAlphabetic.symmetricDifference(["⌘", "⌥", "⌃", "⇧"]).sorted()). Either give it "
      + "an alphabetic name or widen the comparison.")

    for glyph in ["⌘", "⌥", "⌃", "⇧"] {
      XCTAssertTrue(paragraph.contains(glyph),
                    "the paragraph stopped mentioning the \(glyph) modifier glyph")
    }

    // The enumeration itself, not just the paragraph around it. Comparing backticked spans
    // alone lets a bare word be smuggled into the list: "`Right`, Enter, Escape, and the
    // modifier glyphs" claims two names that do not exist and stays green, because neither
    // is backticked. So the span between the colon and the glyph clause must consist of
    // backticked names and separators, nothing else.
    guard let listStart = paragraph.range(of: "are fixed: "),
          let listEnd = paragraph.range(of: "and the modifier glyphs") else {
      return XCTFail("the enumeration lost its 'are fixed: … and the modifier glyphs' shape; "
                     + "this half of the lint now reads nothing")
    }
    let list = String(paragraph[listStart.upperBound..<listEnd.lowerBound])
    // omittingEmptySubsequences: false is load-bearing. This span starts with a backtick, so
    // dropping the empty leading piece shifts every index by one and inverts the parity,
    // the filter then collects the names and ignores the prose, which is exactly backwards.
    let residue = list.split(separator: "`", omittingEmptySubsequences: false).enumerated()
      .filter { $0.offset % 2 == 0 }.map { String($0.element) }.joined()
    let stray = residue.filter { !$0.isWhitespace && $0 != "," }
    XCTAssertTrue(stray.isEmpty,
      "the closed-vocabulary list contains text outside backticks (\(stray)); a bare word "
      + "there reads as a token name but is invisible to the set comparison above")
  }

  func testEveryQuotedSwiftLineExistsInSource() throws {
    let readme = try String(
      contentsOf: repoRoot.appendingPathComponent("README.md"),
      encoding: .utf8)

    let quoted = Self.quotedSwiftLines(in: readme)
    XCTAssertGreaterThan(quoted.significant.count, 20,
      "the README stopped quoting real code, or the fence parser broke; either way this "
      + "test would now pass on nothing")

    let files = try swiftFiles(under: "Sources/ShortcutHelpKit")
      + swiftFiles(under: "Tests/ShortcutHelpKitTests")
    let bodies = try files.map { try String(contentsOf: $0, encoding: .utf8) }

    let missing = quoted.all.filter { line in !bodies.contains { $0.contains(line) } }
    XCTAssertEqual(missing, [],
      "the README quotes code that exists in no package source. The example lives in "
      + "ReadmeExample.swift; change it there first, then re-quote it.")
  }

  /// Negative control on the real pipeline, not on a hand-built array: a line that is in
  /// no source file must be reported missing. Without this, a `contains` that always
  /// succeeded, or an enumeration returning a body that swallows everything, would
  /// leave the test permanently and silently green.
  func testMatcherReportsALineThatIsNotThere() throws {
    // Assembled at runtime on purpose. Written as a literal it would appear in this very
    // file, which is inside the corpus, so the sentinel would find itself and the control
    // would pass for the wrong reason.
    let sentinel = "let " + "absentFrom" + "EverySource" + " = 42"
    let fake = "```swift\n\(sentinel)\n```"

    let quoted = Self.quotedSwiftLines(in: fake)
    XCTAssertEqual(quoted.all, [sentinel])
    XCTAssertEqual(quoted.significant, quoted.all, "a real statement must count as significant")

    let bodies = try (swiftFiles(under: "Sources/ShortcutHelpKit")
      + swiftFiles(under: "Tests/ShortcutHelpKitTests"))
      .map { try String(contentsOf: $0, encoding: .utf8) }
    XCTAssertFalse(bodies.contains { $0.contains(sentinel) },
                   "the matcher accepts a line that is not present in any source")
  }

  /// Punctuation-only lines must not count toward the quorum, since they match everything.
  func testPunctuationOnlyLinesAreNotCountedAsSignificant() {
    let fence = """
    ```swift
    }
    )
    ])
    let realStatement = 1
    ```
    """
    let quoted = Self.quotedSwiftLines(in: fence)
    XCTAssertEqual(quoted.all.count, 4)
    XCTAssertEqual(quoted.significant, ["let realStatement = 1"])
  }
}
