# Idle capsule proportion and Liquid Glass design QA

> Current override (2026-08-04, latest): the idle shell is now `108×54`, while both `30×30` hit areas and their 8 pt gap remain unchanged. The shortcut label is now 12 pt Semibold system Monospaced in the dynamic primary color. A signed native-glass runtime capture measured exactly `108×54`; neither control was cropped or crowded, the full `⌃⌥A` label remained accessible and visually clearer, and the preview was then quit without starting recording. The older geometry and typography measurements below are retained only as history.

> Current override (2026-08-04): the 24 pt fixed-white three-section gear documented below was superseded by the user's new transparent black eight-tooth gear. The current control places a 16 pt black gear inside a 28 pt white circle, matching the adjacent waveform button and remaining readable on the white-background runtime capture. The earlier measurements below are retained only as history for the superseded artwork.

## Comparison target

- Baseline visual truth: `/tmp/FlotisSettingsButtonImplementation-final.jpg`
- Supplied icon truth: `/Users/vita/Vitemis/Flotis/docs/assets/voice-waveform-button-reference.png` and `/Users/vita/Vitemis/Flotis/docs/assets/settings-gear-button-reference.png`
- First glass implementation: `/tmp/FlotisLiquidGlassImplementation-pass1.png`
- Final implementation: `/tmp/FlotisLiquidGlassImplementation-handoff.png` (pixel-identical to the `/tmp/FlotisLiquidGlassImplementation-final2.png` capture used by the comparison boards)
- Full-view comparison: `/tmp/FlotisLiquidGlassComparison-final.png` (baseline left, final right)
- Focused gear comparison: `/tmp/FlotisLiquidGlassGearComparison-final.png` (normalized source left, runtime crop right)
- State: native macOS idle capsule, current system appearance, macOS 27.0
- Baseline viewport: `120×56` pixels; final viewport: `116×54` pixels
- Final control geometry: 28 pt waveform art and 24 pt gear art, each centered in its unchanged `30×30` hit area, with an 8 pt hit-area gap
- Density normalization: the final capture was centered in a `120×56` board next to the baseline, then both were enlarged 8x with nearest-neighbor sampling. The supplied gear was downsampled to `24×24`, centered in a `30×30` field, and compared beside the runtime `30×30` crop at 10x.

## Findings

- No actionable P0, P1, or P2 mismatch remains.
- The `116×54` shell is visibly tighter without crowding the shortcut or either control.
- The 24 pt gear is now subordinate to the 28 pt recording control while preserving the supplied tooth count, three internal sections, and central hub.
- The system glass surface is lighter and more dimensional than the previous opaque popover material. The final 18% content tint keeps the fixed-white gear and shortcut legible without hiding the native glass treatment.
- The capsule remains compact enough to read as one control group; no image is cropped and no rectangular highlight or doubled outline is visible.

## Required fidelity surfaces

- Fonts and typography: the existing 11 pt Monospaced shortcut, weight, line limit, and wording are unchanged. It remains centered and fully visible in the shorter shell.
- Spacing and layout rhythm: idle changed only from `120×56`/10 pt to `116×54`/8 pt. The two `30×30` hit areas remain intact; all non-idle panel sizes remain unchanged.
- Colors and visual tokens: the outer surface is native regular Liquid Glass on macOS 26+, with system-provided refraction/highlights and a restrained black contrast tint. The fallback retains the existing popover material. Semantic recording/error colors were not changed.
- Image quality and asset fidelity: the waveform still uses the approved 28/56/84 px image set. The exact supplied gear source was regenerated at 24/48/72 px rather than runtime-downscaling the former 26 pt asset. The focused comparison confirms the source and runtime silhouettes match.
- Copy and content: no app-specific text changed.

## Full-view evidence

The combined board compares the same idle state. The final shell is 4 px narrower and 2 px shorter, the settings artwork is visibly smaller, and the material changes from the previous dense gray fill to a lighter native glass surface. The recording button, shortcut, corner continuity, and control hierarchy remain intact.

## Focused-region evidence

The normalized gear board shows the 24 pt source on the left and the rendered `30×30` settings-button crop on the right. The outer teeth, internal three-way structure, central hub, transparency, and scale are preserved; runtime softness is limited to the 1x Computer Use JPEG capture.

## Interaction evidence

- Computer Use exposed the controls as accessible `Start` and `Settings` buttons.
- Clicking `Settings` opened the existing reusable Settings window; closing it returned to the idle capsule.
- No preference, credential, Accessibility permission, provider request, transcript submission, clipboard write, or injection action was performed.
- A coordinate-based drag attempt accidentally entered the Start hit area and briefly began recording. The temporary preview was terminated immediately without stopping into transcription or injection. The new surface's background drag remains a manual follow-up; the existing drag/resize policy tests and prior native drag verification remain green.

## Comparison history

1. The first native-glass capture was too pale for the fixed-white gear and shortcut. A black native tint plus an availability-scoped 18% content contrast layer was added; the final capture reduces average luma from 184.649 to 176.683 while preserving the glass appearance.
2. The final full-view and focused comparisons show no remaining P0/P1/P2 layout, asset, color-token, typography, or copy mismatch.

## Residual test gaps

- Dark appearance, Reduce Transparency, Increase Contrast, and the macOS 13–25 fallback were not separately captured.
- Empty-background dragging on the final `NSGlassEffectView` surface should be checked manually because coordinate automation cannot safely distinguish the narrow blank strip from the Start hit area.
- Recording and non-idle state transitions were intentionally excluded from visual QA after the accidental Start hit.

## Implementation checklist

- [x] Refine idle proportions without changing non-idle sizes.
- [x] Reduce and regenerate the supplied settings artwork at 24/48/72 px.
- [x] Use native `NSGlassEffectView` on macOS 26+ and retain the existing material fallback.
- [x] Preserve both hit areas, accessibility, actions, shortcut, and voice-state mappings.
- [x] Compare the full idle capsule and the focused gear region.
- [x] Verify Settings opens and closes from the refined control.

final result: passed
