# Minimal floating capsule design QA — geometry and interaction baseline

Date: 2026-08-16

## Current Liquid Glass status

- The saved comparison in this document predates the user's Dark-appearance correction. It remains valid for the `96×36 pt` geometry, dot/shortcut hierarchy, and compact drag/single-click/double-click behavior only.
- The fixed `245/255` SwiftUI fill, half-point custom outline, and fixed near-black label captured in that pass are superseded. The current compact SwiftUI layer is transparent, the AppKit `NSGlassEffectView(style: .regular)` (or the macOS 13–25 material fallback) is the only surface, and the shortcut uses the dynamic system primary color.
- A signed current preview was built at `/private/tmp/FlotisGlassFix-Preview-20260816/Build/Products/Debug/Flotis.app`, but Computer Use returned `Computer Use was not approved to use Flotis`. Therefore the current Liquid Glass appearance is not marked as visually passed for Light/Dark, Reduce Transparency, or Increase Contrast; no alternate GUI automation was used to bypass that restriction.

## Comparison target

- Source visual truth: `/private/tmp/Flotis-Minimal-Capsule-Reference-20260816.png` (the user's attached screenshot).
- Rendered implementation: `/private/tmp/Flotis-Minimal-Capsule-Shortcut-20260816.jpeg` (isolated signed native macOS Debug app captured through Computer Use after stale Flotis previews released their Carbon registrations).
- Combined comparison input: `/private/tmp/Flotis-Capsule-Reference-vs-Shortcut-Implementation-20260816.png`, source on the left and implementation on the right.
- State: idle compact capsule, with no settings window or review editor open.
- Source image: `284×164 px`; the visible capsule is `192×72 px`, equivalent to `96×36 pt` at `@2x` density.
- Implementation capture: `96×36 px` at `1x`, matching a native `96×36 pt` content size.
- Density normalization: the implementation capture was upscaled exactly `2×` to `192×72 px` and placed at the source capsule's `46,38` origin on an equal `284×164 px` black canvas before the side-by-side comparison.

## Findings

- No actionable P0, P1, or P2 mismatch remains in the captured geometry, content hierarchy, or interaction scope. The captured fixed-light material treatment is historical and is not a pass result for the current glass surface.
- The source word `Ask` is intentionally replaced by the current voice shortcut; this captured default state uses `⌃⌥A`. No product name or explanatory copy remains on the compact surface.
- The implementation capture is a window crop and therefore does not reproduce all of the source canvas's surrounding transparent shadow pixels. Its size and hierarchy remain useful evidence, but its historical light fill and outline no longer describe the current live implementation.

## Required fidelity surfaces

- Fonts and typography: one centered system Semibold Monospaced shortcut at 15 pt, dynamic system-primary foreground, one line, no wrapping or subordinate copy. Its optical weight and vertical centering preserve the source's single-label hierarchy.
- Spacing and layout rhythm: exact `96×36 pt` capsule, full `18 pt` pill radius, centered `6 pt` status dot, `7 pt` dot-to-label spacing, and no additional controls or secondary row.
- Colors and tokens: native transparent system glass/material with no fixed SwiftUI fill or custom full outline, system green idle dot, and dynamic primary label. Busy, recording, and error states change only the semantic dot color; they do not add visible copy or controls.
- Image quality and asset fidelity: the source contains no photographic, illustrative, logo, or icon asset that needs raster reproduction. The dot, type, AppKit glass/material surface, and window shadow remain resolution-independent native UI; no placeholder, emoji, handcrafted SVG, or substitute icon was introduced.
- Copy and content: the captured default compact surface contains only the semantic dot and `⌃⌥A`; the implementation now substitutes the configured voice shortcut in the same slot. The product name, prior microphone button, settings gear, elapsed timer, status sentence, error sentence, and double-click instruction are absent.

## Interaction evidence

- A native drag gesture starting on the compact SwiftUI surface completed through the panel's `performDrag(with:)` route; the capsule remained compact and did not open Settings.
- A native double-click on the compact capsule opened the existing Settings window.
- Closing Settings and performing one click left the capsule compact and did not open Settings.
- The double-click route is disabled while the review editor is open, preserving native double-click text selection there.
- Voice start/stop/copy-and-return remains owned by the existing global hotkey state machine; the compact capsule no longer adds a second visible action surface.

## Focused comparison evidence

The component itself is only `96×36 pt`, so the normalized full-component comparison is also the focused region comparison. A second crop would contain no additional detail. The comparison clearly exposes the radius, fill, border, dot diameter, dot/label spacing, type weight, vertical centering, and absence of extra elements.

## Comparison history

- Pass 1: the first equal-density, equal-size combined comparison validated the requested geometry with the interim `Flotis` label.
- Pass 2: after the user's explicit content correction, the brand label was replaced by the default `⌃⌥A`; the refreshed equal-density comparison found no P0/P1/P2 geometry, spacing, color, typography, asset, or copy issue in that compact state. The later configurable-key change reuses the same text slot and has not been recaptured.
- Current correction: the user rejected Pass 2's fixed light surface after observing it in Dark appearance. Its geometry/content/interaction evidence is retained; its color/material conclusion is withdrawn and replaced by the transparent native-glass contract above.

## Residual test gaps

- The source defines only the idle appearance. Recording, processing, error-dot colors, review expansion, Dark appearance, Reduce Transparency, Increase Contrast, and macOS 13–25 material fallback do not have matching source frames and remain compatibility checks rather than fidelity comparisons. The current glass surface also lacks a new approved native capture because Computer Use was denied access to Flotis.
- The existing review layouts were intentionally preserved and were not re-captured in this capsule-only pass.
- A later attempt to repeat all Computer Use interactions in one capture stream hit ScreenCaptureKit error `-3811`; the saved final idle capture and the earlier separate native drag/single-click/double-click passes remain valid, and the interaction policy is independently covered by XCTest.

final result: geometry/content/interaction baseline passed; current Liquid Glass appearance not visually verified because Computer Use access was denied
