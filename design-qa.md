# Intatis-style Provider / Models Settings design QA

## 2026-08-07 shortcut-page hierarchy follow-up

- The user's installed-app screenshot showed two competing cards, repeated explanatory copy, and shortcut controls that were visually subordinate to the text. The implementation now treats this destination as a focused shortcut editor rather than a general product overview.
- The sidebar brand area contains only `Flotis` and the version; its decorative application glyph is removed. The destination and page title are now Shortcuts / 快捷键 instead of General / 概览.
- Fixed voice input and the three configurable shortcuts are consolidated into one card. The visible voice-flow paragraph, floating-capsule drag explanation, duplicate section heading, row icons, and per-row descriptions are removed.
- Every shortcut surface is fixed at `220×50` with 17 pt Semibold Monospaced text; configurable surfaces are clickable across the whole rectangle, and the native recording state keeps the same size with a 14 pt prompt.
- Main App Debug/Release builds, the InputMethod Debug build, 79 Main App tests, and 8 InputMethod tests passed. The signed `0.12 (3)` Release was installed at `/Applications/Flotis.app`; executable and compiled icon assets match the verified Release product.
- Native Computer Use failed to start on both attempts, so this follow-up is not marked as a runtime pixel pass. The installed hierarchy, spacing, text scale, and hit-area feel remain for the user's direct visual check.

## 2026-08-06 interaction follow-up

- Settings disclosure headers now use a shared full-width button with a minimum 44 pt hit target; Provider rows use at least 48 pt, and each comparison route is a full-card button rather than a tiny checkbox target. Source inspection confirms the label, empty row space, and chevron/checkbox area all invoke the same action.
- The compact capsule preserves its existing status icons and copy. Recording replaces only the trailing stop square with a monospaced elapsed timer; stopping/transcribing suppresses only the duplicate trailing disabled action. Multi-result review is `560×300`, uses a fixed two-column grid (four cards become 2×2), opens the first successful candidate immediately, and has no horizontal strip or extra “choose one” prompt.
- Candidate navigation is available through temporary `⌥←` / `⌥→` registrations only while a multi-result review has at least two successful candidates. It skips failed candidates, wraps, preserves per-candidate edits, and leaves the existing voice shortcut responsible for copying the current result.
- Targeted source/build tests cover elapsed-time lifecycle/formatting, the `560×300` contract, Option-only shortcut descriptors, first-success selection, failed-result skipping, wraparound, edit retention, and copying the current candidate.
- A same-state runtime screenshot comparison was attempted through the required native Computer Use path, but the local service failed during startup twice. No substitute screenshot path was used and this iteration is therefore not marked visually passed; whole-row pointer behavior, 2×2 rendering, timer appearance, and physical shortcut registration still require a native manual pass.

## Comparison target

- Source implementation: `/Users/vita/Vitemis/Intatis/Apps/IntatisMac/Sources/IntatisChatScreen.swift`, `IntatisSettingsPanel` provider/model section.
- Source design tokens: `/Users/vita/Vitemis/Intatis/Apps/IntatisMac/Sources/IntatisDesign.swift`.
- Source runtime capture, collapsed: `/private/tmp/Intatis-Providers-Reference-20260805.jpeg`, `1100×760`.
- Source runtime capture, Models expanded: `/private/tmp/Intatis-Models-Reference-20260805.jpeg`, `1100×760`.
- Flotis runtime capture, collapsed: `/private/tmp/Flotis-Intatis-Style-Models-Collapsed-Composited-20260805.png`, Retina `2200×1584` (`1100×792` outer frame, `1100×760` content).
- Flotis runtime capture, Models expanded: `/private/tmp/Flotis-Intatis-Style-Models-Expanded-Composited-20260805.png`, Retina `2200×1584`.
- Combined collapsed comparison: `/private/tmp/Intatis-Flotis-Models-Collapsed-Comparison-20260805.png`, `2200×760`, Intatis left / Flotis right.
- Combined expanded comparison: `/private/tmp/Intatis-Flotis-Models-Expanded-Comparison-20260805.png`, `2200×760`, Intatis left / Flotis right.
- State: native macOS Settings, Dark appearance. The scoped target is the provider/model portion; Flotis retains its own outer product sidebar and page header.

## Required fidelity surfaces

- Primary card uses Intatis' two-column hierarchy at the 1100 pt content width: Providers and Add on the left; selected Provider detail on the right.
- Provider detail order matches the reference: Provider name, API key, Active model, Connection disclosure, Models disclosure.
- Models expanded state includes count, Add model, per-row Model ID, optional Display name, delete action, and Delete provider.
- Test Provider and Save remain directly below the primary card. Cancel appears only for an unsaved draft; the last visible Provider cannot be deleted.
- Card max width, 28 pt page padding, 22 pt card padding, selected-row outline, typography, disclosure spacing, field heights, button hierarchy, and Dark appearance system colors were compared in one combined image rather than from separate screenshots.
- Flotis-only 2–4 route Comparison and Language/Prompt/Temperature remain below the primary card as separate disclosures so they do not distort the copied Provider/Models hierarchy.

## Interaction and state evidence

- Collapsed and Models-expanded states both rendered in the isolated signed Debug app at the same content viewport as Intatis.
- The current real catalog rendered multiple Provider rows and their model counts; the selected row, Active model menu, secure API key placeholder, Connection/Models disclosures, Add/Delete model controls, Test Provider, Save, Comparison, and advanced controls were all present.
- The Intatis sample has one Provider with many models, while the current Flotis catalog has multiple independent Provider groups with one model each. This is a data difference, not a layout substitution. QA did not merge or rewrite user Provider groups merely to imitate sample data.
- No Save, Delete provider, Clear API key, Test Provider, comparison change, recording, provider request, transcript, clipboard, or installation action was performed.
- Computer Use captured the Intatis reference before its local service became unavailable. Flotis then used a temporary Debug-only self-capture path in an isolated bundle. That hook and its imports were removed after capture; no visual-QA switch remains in production source.

## Iteration findings

1. **P1 — actual window collapsed to 820 pt:** assigning the SwiftUI HostingController replaced the requested `1100×760` content size with the view's minimum `820×600`, so the first runtime capture lost the reference's two-column proportions. Fixed by setting `contentMinSize` after host assignment and then explicitly calling `setContentSize(1100×760)`. Final captures measure the intended 1100 pt content width.
2. **P2 — reference copy and action hierarchy:** aligned the API key label and saved-key placeholder, moved key clearing into Connection, hid Cancel until a draft is dirty, disabled deletion of the last visible Provider, and aligned the action wording to Test Provider / Save.
3. **P2 — model identity:** replaced the former multiline model list with independent Model ID + Display name rows and persisted the optional display name without changing the request Model ID or the shared Provider endpoint/key boundary.
4. The final combined collapsed and expanded comparisons show no remaining P0/P1/P2 mismatch inside the requested Provider/Models scope.

## Residual verification gaps

- Light appearance, Reduce Transparency, Increase Contrast, macOS 13 fallback, the compact 820 pt layout, an empty Provider catalog, very long localized names, full keyboard navigation, VoiceOver order, and destructive confirmation dialogs were not separately captured.
- Real OpenRouter credentials, network requests, billing, and one-Provider/many-model data entry were intentionally excluded from visual QA; store and request behavior remain covered by unit tests, while live service use still requires manual validation.
- At the time of the 2026-08-05 Provider/Models capture, that isolated visual build had not been installed over `/Applications/Flotis.app`; the later verified `0.12 (3)` builds have since been installed.

2026-08-05 Provider/Models fidelity result: passed

2026-08-06 interaction follow-up result: implementation/test pass; runtime visual verification pending because Computer Use could not start

2026-08-07 shortcut-page follow-up result: implementation/build/install pass; runtime visual verification pending because Computer Use could not start
