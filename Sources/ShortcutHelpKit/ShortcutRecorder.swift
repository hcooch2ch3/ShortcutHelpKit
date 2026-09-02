import AppKit
import Carbon
import SwiftUI

/// Which modifier combinations a capture will accept. Pure and command-agnostic:
/// it knows nothing about which shortcuts already exist.
enum ShortcutCaptureValidation {
  private static let functionKeyCodes: Set<UInt16> = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, // F1 to F15
    106, 64, 79, 80, 90                                                     // F16 to F20
  ]
  static func validate(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, blocksOptionOnly: Bool) -> Bool {
    if functionKeyCodes.contains(keyCode) { return true }        // F1 to F20 need no modifier
    let relevant = modifiers.intersection([.command, .option, .control, .shift])
    // Reject unless a modifier other than ⇧ or fn is held: a bare key is not a shortcut.
    // fn is deliberately not counted: `relevant` never includes it.
    if relevant.subtracting([.shift]).isEmpty { return false }
    // Blocked when the caller asks for it: ⌥ with no ⌘ or ⌃ types alternate characters on
    // the layout in use. ⇧ does not rescue it, since ⌥⇧K is blocked too. The default lives one type
    // away, on RecorderNSView.
    if blocksOptionOnly, relevant.subtracting([.shift]) == [.option] { return false }
    return true
  }
}

/// Renders a chord as glyphs: modifiers in ⌃⌥⇧⌘ order, then the key's display character
/// (resolved through UCKeyTranslate, with a static table for the non-printing keys).
enum ShortcutGlyphs {
  // Takes KeyModifiers, not NSEvent.ModifierFlags, so this stays usable from code that
  // does not import AppKit.
  static func modifierString(_ m: KeyModifiers) -> String {
    var s = ""
    if m.contains(.control) { s += "⌃" }
    if m.contains(.option)  { s += "⌥" }
    if m.contains(.shift)   { s += "⇧" }
    if m.contains(.command) { s += "⌘" }
    return s
  }

  // Static table for keys UCKeyTranslate cannot label: it returns "" for Return and a
  // literal space for Space, and the arrows need multi-character glyphs.
  private static let special: [UInt16: String] = [
    36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
    123: "←", 124: "→", 125: "↓", 126: "↑",
  ]

  static func displayCharacter(forKeyCode keyCode: UInt16) -> String? {
    if let s = special[keyCode] { return s }
    return layoutCharacter(forKeyCode: keyCode)?.uppercased()
  }

  private static func layoutCharacter(forKeyCode keyCode: UInt16) -> String? {
    guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
    let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 8)
    var length = 0
    let err = UCKeyTranslate(keyLayout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                             UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                             &deadKeyState, chars.count, &length, &chars)
    guard err == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
  }
}

/// A reusable capture field: current chord in, new chord out. It validates modifier shape
/// only. Whether a chord collides with an existing binding or a system shortcut is the
/// host's call, delivered through onRebind.
struct ShortcutRecorderField: NSViewRepresentable {
  private let current: KeyChord?
  private let blocksOptionOnly: Bool
  private let onCapture: (KeyChord) -> Void
  private let onRecordingChange: (Bool) -> Void

  init(current: KeyChord?, blocksOptionOnly: Bool = true,
       onCapture: @escaping (KeyChord) -> Void,
       onRecordingChange: @escaping (Bool) -> Void) {
    self.current = current
    self.blocksOptionOnly = blocksOptionOnly
    self.onCapture = onCapture
    self.onRecordingChange = onRecordingChange
  }

  func makeNSView(context: Context) -> RecorderNSView {
    let v = RecorderNSView()
    v.blocksOptionOnly = blocksOptionOnly
    v.onCapture = onCapture
    v.onRecordingChange = onRecordingChange
    v.current = current
    return v
  }

  func updateNSView(_ nsView: RecorderNSView, context: Context) {
    nsView.current = current
    nsView.needsDisplay = true
  }
}

/// What a key event means while recording. Split from the monitor plumbing so it can be
/// tested as a pure function.
enum RecorderAction: Equatable, Sendable {
  case ignore                // flagsChanged; swallow so held modifiers do not reach the host
  case cancel                // bare ESC
  case reject                // invalid combination; beep, keep recording
  case capture(KeyChord)     // valid combination
}

/// Holds the recording state and swallows the events it captures. Capture runs through its
/// own local monitor rather than the responder chain, so the keystroke being recorded
/// cannot also reach a responder-chain shortcut or a menu key equivalent. Engines outside
/// that chain are not covered: a global hotkey or an event tap still fires, which is why
/// the host is asked to pause its own on `onRecordingChange`.
final class RecorderNSView: NSView {
  var current: KeyChord?
  var blocksOptionOnly = true
  var onCapture: ((KeyChord) -> Void)?
  var onRecordingChange: ((Bool) -> Void)?

  private var monitor: Any?
  private var clickAwayMonitor: Any?
  private var willCloseObserver: Any?
  private var resignKeyObserver: Any?
  private var isRecording = false { didSet { needsDisplay = true } }

  /// Live observers, derived from the stored tokens the way `activeMonitorCount` is.
  /// A hand-maintained flag would let a missing `removeObserver` pass unnoticed.
  var activeObserverCount: Int { [willCloseObserver, resignKeyObserver].compactMap { $0 }.count }

  /// Recording no longer requires this view to stay first responder: the observers
  /// installed in `startRecording()` end it on window close and key loss. After that
  /// path the view stays first responder with `isRecording == false`, and re-entry
  /// still works because `makeFirstResponder` returns true early for the current
  /// first responder.
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) {
    guard window?.makeFirstResponder(self) == true else { return }
    startRecording()
  }

  func startRecording() {
    guard !isRecording else { return }
    // NotificationCenter treats `object: nil` as "any object", so a window-less
    // subscription would observe every window in the process.
    guard let window else { return }
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      guard let self else { return event }
      return self.handle(event) ? nil : event   // nil swallows the event
    }
    // A click elsewhere cancels and keeps the previous value. The click itself passes
    // through so buttons and scrolling still work.
    clickAwayMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      self.handleClickAway(event)
      return event
    }
    // The library owns the decision that recording ended: requiring every host to
    // install teardown hooks is the contract this replaces. `queue: nil` delivers
    // synchronously on the posting thread, which keeps onRecordingChange(false)
    // ahead of the host's window teardown.
    // `[weak self]` is required: NotificationCenter retains the block, and the only
    // thing that would break a cycle from self to token to block and back is the very call
    // (`endRecording`) this exists because it may never happen.
    willCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: nil
    ) { [weak self] _ in Self.tearDownOnMain(self) }
    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: window, queue: nil
    ) { [weak self] _ in Self.tearDownOnMain(self) }
    // Notify last, mirroring endRecording's remove-then-notify. If the host's callback tears
    // down synchronously, everything it needs to reclaim is already installed.
    onRecordingChange?(true)   // the host has two jobs here: pause its shortcut engines, and
                               // set its own is-recording flag (which gates its ESC handling)
  }

  /// `MainActor.assumeIsolated` is a precondition that traps in release builds, and
  /// `queue: nil` runs the block on whichever thread posted. AppKit posts both window
  /// notifications on main, so the assumption holds today, but the library must not
  /// crash a keyboard-shortcut recorder if some future poster gets it wrong. Off-main
  /// falls back to an async hop; `queue: .main` is not an alternative for the main path
  /// because it would defer teardown past the host's window close.
  private nonisolated static func tearDownOnMain(_ view: RecorderNSView?) {
    guard let view else { return }
    if Thread.isMainThread {
      MainActor.assumeIsolated { view.endRecording() }
    } else {
      DispatchQueue.main.async { view.endRecording() }
    }
  }

  /// Decision plus effect for a click-away. The monitor closure only calls this, so the
  /// decision stays testable.
  func handleClickAway(_ event: NSEvent) {
    if isClickOutside(event) { endRecording() }
  }

  /// Is this click outside the field? A click in another window counts as outside.
  ///
  /// Uses hitTest rather than `bounds.contains`: the row lives inside a ScrollView, so
  /// once it scrolls out of view its bounds coordinates map onto other chrome and a
  /// contains-check reads "inside". hitTest reflects clipping and occlusion correctly.
  /// (`visibleRect` is zero when the window is offscreen, which inverts the verdict.)
  func isClickOutside(_ event: NSEvent) -> Bool {
    guard let window, event.window === window else { return true }
    guard let hit = window.contentView?.hitTest(event.locationInWindow) else { return true }
    return !hit.isDescendant(of: self)   // self or a subview of self counts as inside
  }

  /// Live local monitors, for tests: 2 while recording, 0 after teardown. The two are
  /// installed and removed together. Derived from the stored tokens rather than counted by
  /// hand, so an unbalanced removeMonitor cannot pass unnoticed.
  var activeMonitorCount: Int { [monitor, clickAwayMonitor].compactMap { $0 }.count }

  /// Idempotent, because several teardown paths reach it and may fire redundantly.
  func endRecording() {
    guard isRecording else { return }
    isRecording = false
    if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    if let m = clickAwayMonitor { NSEvent.removeMonitor(m); clickAwayMonitor = nil }
    if let o = willCloseObserver { NotificationCenter.default.removeObserver(o); willCloseObserver = nil }
    if let o = resignKeyObserver { NotificationCenter.default.removeObserver(o); resignKeyObserver = nil }
    onRecordingChange?(false)  // the host resumes its engines and clears that flag
  }

  // Teardown entry points on the view side: window removal (viewDidMoveToWindow) and losing
  // first responder to another field. The observers in startRecording() cover window close
  // and key loss. Leaving recording on strands the host's engines paused.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Unconditional, not `if window == nil`. startRecording() binds both observers to a
    // specific window instance, so a reparent between two windows would otherwise leave them
    // watching the old window: closing the new one would never tear down and the host's
    // global hotkey would stay unregistered. Safe to call when moving in from no window too:
    // startRecording() requires a window, so isRecording is false there and this no-ops.
    endRecording()
  }
  override func resignFirstResponder() -> Bool {
    endRecording()   // clicking another recorder ends this one
    return super.resignFirstResponder()
  }
  // No deinit backstop: a @MainActor NSView's deinit is nonisolated and cannot touch the
  // non-Sendable monitor tokens. SwiftUI removes the view from its window first, so
  // viewDidMoveToWindow reclaims them before deallocation.

  /// Returns true when the event is consumed. `decide` makes the call; this applies it.
  private func handle(_ event: NSEvent) -> Bool {
    switch Self.decide(keyCode: event.keyCode, modifiers: event.modifierFlags,
                       isKeyDown: event.type == .keyDown, blocksOptionOnly: blocksOptionOnly) {
    case .ignore:              return true
    case .cancel:              endRecording(); return true
    case .reject:              NSSound.beep(); return true
    case .capture(let chord):  onCapture?(chord); endRecording(); return true
    }
  }

  /// The decision tree. nonisolated because it touches no MainActor state.
  /// Bare ESC cancels and anything valid captures. Bare Delete is rejected like any
  /// other invalid key. The recorder unbinds nothing, so accepting Delete would reserve
  /// two keys for an effect the user cannot see.
  nonisolated static func decide(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                                 isKeyDown: Bool, blocksOptionOnly: Bool) -> RecorderAction {
    guard isKeyDown else { return .ignore }                  // swallowed, changes nothing
    let mods = modifiers.intersection([.command, .option, .control, .shift])
    if mods.isEmpty {
      switch keyCode {
      case 53: return .cancel                                // ESC keeps the previous value
      default: break
      }
    }
    guard ShortcutCaptureValidation.validate(keyCode: keyCode, modifiers: modifiers,
                                             blocksOptionOnly: blocksOptionOnly) else {
      return .reject                                         // ⌘⌫ has modifiers, so it captures instead
    }
    return .capture(makeChord(keyCode: keyCode, modifiers: modifiers))
  }

  nonisolated static func makeChord(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyChord {
    var m: KeyModifiers = []
    if modifiers.contains(.command) { m.insert(.command) }
    if modifiers.contains(.option)  { m.insert(.option) }
    if modifiers.contains(.control) { m.insert(.control) }
    if modifiers.contains(.shift)   { m.insert(.shift) }
    return KeyChord(keyCode: Int(keyCode), modifiers: m)
  }

  override func draw(_ dirtyRect: NSRect) {
    let bg: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor
    bg.setFill()
    let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
    path.fill()
    (isRecording ? NSColor.controlAccentColor : .separatorColor).setStroke()
    path.lineWidth = 1
    path.stroke()
    let label = displayLabel()
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: NSColor.labelColor,
    ]
    let s = NSAttributedString(string: label, attributes: attrs)
    s.draw(at: NSPoint(x: 10, y: (bounds.height - s.size().height) / 2))
    // Minimal accessibility: button role and current value only. The labels below are
    // hard-coded English and are not routed through ShortcutHelpStrings.
    setAccessibilityRole(.button)
    setAccessibilityLabel(label.isEmpty ? "No shortcut" : "Shortcut: \(label)")
  }

  private func displayLabel() -> String {
    if isRecording { return "…" }
    guard let c = current else { return "" }
    let mods = ShortcutGlyphs.modifierString(c.modifiers)
    let key = ShortcutGlyphs.displayCharacter(forKeyCode: UInt16(c.keyCode)) ?? ""
    return mods + key
  }
}
