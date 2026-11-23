# Fast Music — reference lock

Source: user-supplied `ref.png`, approved direction in this conversation. Native macOS app shell; no web component registries. Final implementation awaits visual review.

## Direction
392pt anchored menu-bar panel. Revised by user 23.11.2026: search only (no brand title) → three tabs → artwork/title → transport → timeline/volume → four shortcut tiles. No gradients or background glow. No vibes, discovery feed, podcasts, equalizer, or full application window. Library/search/settings expand below the same player.

## Color contract
Panel-only deterministic palette extraction (desktop wallpaper excluded): #121112, #0d0c0f, #251e1f, warm yellow/brown and magenta glow. Background #121112; surface #252224; text #f5f5f4; secondary #b4b3b5; accent #ffed00; on-accent #121112.
Verified matrix: text/background 17.27; muted/background 9.02; text/surface 14.44; muted/surface 7.54; on-accent/accent 15.58. Hairlines are decorative, selected state has a yellow outline. Never use white labels on solid yellow.
Dark appearance only. Reduced Transparency uses an opaque background.

## Typography and geometry
System SF Pro, Cyrillic supported. Track title 15pt, artist/tabs 12pt, shortcut labels 10pt. Tabular timestamps. Panel radius 18pt, tile radius 13pt, covers 10pt. Outer inset 16pt; control gaps 8/12/16/24pt. 64pt artwork, 48pt play control. Native sliders share 22pt control height and the same track/knob centerline. Truncated long labels have tooltips.

## Assets
SF Symbols for controls. Burst mark constructed natively to match the reference's ray silhouette, not an official distributed logo asset. `assets/reference-cover.png` is cropped from the user's reference and appears only in explicit demo mode; production artwork comes from Yandex using supported 200/400px presets. Legacy track-glow asset is unused. No stock imagery.

## Interaction
Native NSPopover dismissal and anchoring; native NSSlider tracking/keyboard/VoiceOver with custom cell drawing; SwiftUI buttons and menus. 120ms ease-out press feedback, 0.97 press scale, subtle hover brightness. Reduce Motion disables scaling/animation. No continuous visual loops; no progress observer while panel is closed or playback paused.

## Taste memory
User approved reference fidelity and restrained motion. Implementation review is pending. No personal profile created or modified.
