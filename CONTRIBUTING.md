# Contributing

Thanks for looking. This is a small package with a narrow job, so the bar for what goes in
is deliberately specific rather than a matter of taste.

## What to expect

One person maintains this alongside other work. A reply is not a fix: if a change needs
more thought, the issue says so and stays open.

## The keyboard illustration

This is where the rule needs to be explicit, so here it is. A key gets a cap on the grid
only when all three hold:

1. **It is bindable.** The recorder can capture it and produce a chord. The one exception
   already on the grid is `⇪`, drawn with no token as a decorative cap; it is a landmark,
   not a highlightable key.
2. **It sits on a row the grid already draws.** The grid is five rows: the number row,
   QWERTY, the home row, the bottom letter row, and the modifier row. The function row and
   the keypad are not drawn, so a key that lives there does not get a cap.
3. **Adding it does not make an existing cap lie.** A cap lights by token, not by key code.
   If a new cap shares a token with a key that is already drawn, binding one lights the
   other, and the illustration becomes confidently wrong instead of quietly incomplete.

Point 3 is the hard one, and `⌫` is the worked example: a key map that gives forward
delete the same name as backspace makes `⌘⌦` light the `⌫` cap. The trade is worth it
because the alternative is a bound key that lights
nothing at all, but it is a cost, and `KeyboardLayout.swift` states it beside the rule.

The grid is US-ANSI and only US-ANSI. There is no injection point for another layout and
adding one is not a small change, so an issue asking for a different physical layout is a
feature request about scope, not a bug.

## Known and deferred

- **A `keyCode` overload for the projector.** `KeyToken.keyCode(Int)` already lets a host
  decline to name a key, but naming one still goes through a string. Candidate for `0.3.0`.
- **Unbinding a shortcut.** Not implemented. The recorder has no gesture for it: a key
  that only dismissed a caption would read as one and would not be, and there would be no
  way back from an accidental unbind.
- **Keypad keys light their main-row twin when your projector gives them the main-row
  names.** Documented in the README rather than fixed.
  `foldedKeys(from:over:)` reports it against your own projector.

## Pull requests

- Run `swift test` before you open one. CI asks for more than a pass: it fails the build
  on any compiler warning, from the library or the tests, and checks that the boundary
  lint actually ran rather than trusting a green summary.
- Tests that assert a contract belong next to the contract. A comment that says something
  is pinned and has no test under it is worse than no comment.
- Keep the package's boundary. Six sources import Foundation only; the other four reach
  for SwiftUI, and one of those also for AppKit and Carbon. The Requirements table in the
  README lists which is which. Nothing in the package reaches for a bundle.
  `ShortcutHelpLintTests` enforces the Foundation-only set, the no-bundle rule, the
  adopter-view imports, and the module boundary in the built binary, and will tell you if
  you cross any of them.
- Every ```swift-tagged block in the README is checked line by line against real sources.
  If you change quoted API, change the quote in the same commit. The untagged fences, the
  two install lines, a host's `windowWillClose` and the Storage JSON, are illustrations
  that nothing reads: `ShortcutBindingWireFormatTests` pins the encoder's output against
  its own literals, not against the README, so a wrong literal here ships green. Check
  those by hand.

## Reporting a bug

Use the issue template. The layout field matters more than it looks: a projector that
names a key differently from the grid produces exactly the symptom a real defect would,
and the physical layout is what tells the two apart.
