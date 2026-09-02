import Foundation

/// What the illustration will and will not light for a given catalog and projector.
///
/// This failure is silent, which is what makes it worth a type: a shortcut lists correctly
/// in the window and simply never lights on the keyboard, because the projector produced a
/// token the illustration has no cap for. Nothing crashes and no test fails. This type is
/// the check for it, shaped so an empty result cannot be mistaken for a clean one:
/// `rowsExamined` says how much was looked at.
///
/// **This audit is bound to the catalog you hand it, not to your projector.** It sees only
/// the key codes the rows are bound to right now. Three things it therefore cannot see:
/// a projector case no row currently uses; a key hidden behind `.fixed` glyphs, which never
/// reach the projector; and, the one that matters most for a library that offers
/// rebinding, **any key the user binds after you ship**. A green audit at release says
/// nothing about the state after a rebind. Use ``unnamedKeys(from:over:)`` to check the
/// projector itself over the whole range of key codes your host can bind.
public struct HighlightAudit: Sendable, Hashable {

  /// One row whose tokens the illustration cannot light.
  public struct Finding: Sendable, Hashable {
    public let id: CommandID
    /// Carried through so a diagnostic can name the row without walking the catalog again.
    public let title: String
    /// The tokens with no cap. Modifiers are never in here: every modifier has a cap.
    public let tokens: Set<KeyToken>
    /// Vocabulary entries that differ from a dead token only by letter case. This catches
    /// the lowercase mistake and nothing cleverer. An empty set is not a claim that no
    /// correct token exists, only that no near-spelling of this one does.
    public let suggestions: Set<KeyToken>
  }

  /// Rows that will silently never light. An array, not a dictionary: command ids are
  /// documented as unique per catalog, but the host running this audit is exactly the host
  /// that may have broken that rule, and collapsing two findings into one would be the
  /// quietest failure this type could have.
  public let findings: [Finding]

  /// Rows whose `.single` key the projector declined to name, by key code.
  ///
  /// These are reported rather than hidden, because `.keyCode` tokens genuinely never
  /// light, since no cap carries one. They are listed apart from `findings` because they
  /// may be deliberate: a function key left off the grid lands here, and so does a key the
  /// host chose not to name. Read them; do not assume they are bugs.
  public let unnamedKeys: [CommandID: Set<Int>]

  /// How many catalog rows were examined. Zero with no findings means nothing was checked,
  /// which is not the same as nothing being wrong.
  public let rowsExamined: Int

  /// True when no row is known to be dead. Says nothing about ``unnamedKeys``.
  public var isClean: Bool { findings.isEmpty }

  /// Audits a catalog against the illustration's vocabulary.
  public init(catalog: ShortcutCatalog, projector: KeyProjector) {
    var found: [Finding] = []
    var unnamed: [CommandID: Set<Int>] = [:]
    var examined = 0
    let vocabulary = KeyboardLayout.highlightableTokens

    for item in catalog.allItems {
      examined += 1
      // The projector only runs for `.single`. A `.keyCode` inside `.fixed` glyphs was
      // typed by the host, so nothing declined anything and it is reported like any other
      // token the vocabulary does not contain.
      var projected = false
      if case .single(let chord) = item.unit {
        projected = true
        if case .keyCode(let code) = projector(chord.keyCode) {
          unnamed[item.id, default: []].insert(code)
        }
      }
      let dead = ShortcutHoverMap.tokens(for: item, projector: projector).filter { token in
        if projected, case .keyCode = token { return false }
        return !vocabulary.contains(token)
      }
      if !dead.isEmpty {
        found.append(Finding(id: item.id, title: item.title, tokens: dead,
                             suggestions: Self.nearSpellings(of: dead, in: vocabulary)))
      }
    }
    self.findings = found
    self.unnamedKeys = unnamed
    self.rowsExamined = examined
  }

  private static func nearSpellings(of dead: Set<KeyToken>,
                                    in vocabulary: Set<KeyToken>) -> Set<KeyToken> {
    var out: Set<KeyToken> = []
    for token in dead {
      guard case .character(let s) = token else { continue }
      for candidate in vocabulary {
        if case .character(let c) = candidate, c.lowercased() == s.lowercased(), c != s {
          out.insert(candidate)
        }
      }
    }
    return out
  }

  /// Key codes whose projection has no cap, over a range you choose.
  ///
  /// This is the complement of the catalog audit: it checks the projector's own surface,
  /// so it covers cases no row is bound to yet, including keys a user can reach through
  /// the recorder after you ship. Pass the full range of key codes your host allows.
  ///
  /// The returned token is what the projector produced, so a `.keyCode` result means the
  /// projector declined to name that key and a named result means it produced a name the
  /// illustration does not draw.
  public static func unnamedKeys(from projector: KeyProjector,
                                 over keyCodes: some Sequence<Int>) -> [Int: KeyToken] {
    let vocabulary = KeyboardLayout.highlightableTokens
    var out: [Int: KeyToken] = [:]
    for code in keyCodes {
      let token = projector(code)
      if !vocabulary.contains(token) { out[code] = token }
    }
    return out
  }

  /// Key codes your projector collapses onto one token, which is the failure the other two
  /// checks cannot see.
  ///
  /// ``unnamedKeys(from:over:)`` reports a key code only when its token has *no* cap. A fold
  /// that matters is the opposite case: two physical keys arriving as one token that *does*
  /// have a cap, so the cap lights confidently for the wrong key. Filtering on vocabulary
  /// membership excludes exactly those, which is why they need their own sweep.
  ///
  /// `.keyCode` results are dropped. They are unique per key code by construction, so they
  /// can never fold; including them would only add noise.
  ///
  /// A result is not automatically a bug. A projector that names both bracket keys `[`, or
  /// gives the keypad digits the main-row names, produces folds it meant to produce. Read a
  /// result as "these key codes are indistinguishable to the illustration" and decide.
  public static func foldedKeys(from projector: KeyProjector,
                                over keyCodes: some Sequence<Int>) -> [KeyToken: Set<Int>] {
    var byToken: [KeyToken: Set<Int>] = [:]
    for code in keyCodes {
      let token = projector(code)
      if case .keyCode = token { continue }
      byToken[token, default: []].insert(code)
    }
    return byToken.filter { $0.value.count > 1 }
  }
}

extension KeyToken {
  /// The glyph the window draws for this token, such as `⏎` for `.named("Return")`.
  ///
  /// Exposed so a diagnostic can print what the user will actually see. Without it an
  /// adopter writes their own switch over the cases, and that copy drifts the moment the
  /// library adds a glyph rule.
  public var displayLabel: String { ShortcutProjection.label(for: self) }
}
