# Silver Hour UI design (formerly Film Lab)

## Brief

- **Subject**: give my photos a film look.
- **Reader**: the owner, on an iPhone 17 Pro, one hand, right after a shoot.
- **Job**: choose photos, then save them developed. Two taps for the default look.
- **Voice**: calm, native, warm. It must never feel like a web page inside an app.
- **Constraints**: WKWebView over a native engine; system font; the warm film tones of the app icon.

## System

- **Type**: the system face (SF Pro through `-apple-system`), because the job is to feel like iOS. Sizes follow the iOS text styles: 13 (caption), 15 (subheadline), 17 (body), 22 (title 2), 34 (large title). Large title is 700 weight with -0.02 em tracking; body and controls use 400 or 600. Values and counts use tabular numbers.
- **Space**: base unit 4 px. Scale: 4, 8, 12, 16, 24, 32, 48 (`--s1` … `--s7`). Gutter 16 px or the safe area, whichever is larger.
- **Colour**: `--bg`, `--surface`, `--fill` (control tracks), `--fg`, `--dim`, `--hairline`, plus one accent, `--accent` (amber, from the icon's sky), and `--danger` for failures. Dark is the main design: photo apps use a dark surround so you judge the picture and not the chrome. Light mode is designed as well.
- **Layout**: one column, left-aligned. Welcome: the mark and headline in the upper middle, actions in the thumb zone at the bottom. Work: photo, then thumbnails, then status, then Adjust. Save stays pinned to the bottom edge, so it is always one tap away.

```
welcome                 work
┌──────────────┐        ┌──────────────┐
│              │        │   Film Lab  Choose
│ [mark]       │        │ ┌──────────┐ │
│ Develop your │        │ │  photo   │ │
│ photos like  │        │ └──────────┘ │
│ film.        │        │ ▢▢▢▢          │
│ lede         │        │ 4 photos · 250D
│              │        │ Adjust     ▾ │
│[Choose Photos]        │──────────────│
│ Browse Files │        │[Save 4 ][Share]
└──────────────┘        └──────────────┘
```

- **Motion**: none of it is ambient. A press dims the control (80 ms). The Adjust chevron turns (200 ms). Progress fills ease out (240 ms). The spinner and the thumbnail pulse run only while work is pending. With reduced motion, all of these change at once with no animation.
- **States**:
  - Empty: the welcome screen.
  - Loading: a spinner in the photo frame until the first preview, pulsing thumbnails, and a "Developing n of N" line with a progress bar.
  - Error: red status text that says why, and a "!" on the failed thumbnail.
  - Saving: the button shows "Saving n of N", fills as it goes, and a Stop button appears.
  - Success: "Saved to Photos" with a check mark, disabled until something changes.
  - Denied: a line of text and an "Open Settings" button.
  - Focus: a 2 px accent ring.
- **The one memorable thing**: the photo itself, shown large on the dark surround. The only other colour on screen is the amber Save button.

## Generated-default check

"Near-black with one accent" (item 2) is chosen on purpose. It is the standard surround for viewing photos (the Photos editor, Lightroom), and the accent is the icon's own amber, not acid green. Middle dots in the status line (item 5) stay because they separate real metadata (look, RAW, size). Cards: only the Adjust panel is a surface, because it is an object you act on. Everything else sits on the background.

## What changed in the design pass (from the drafts in `measurements/ui-redesign/draft-*.png`)

- **Edge to edge.** The web view now runs under the status bar with a matching background. Before, a pure black band sat above a warm page.
- **Native button feel.** A press dims the button (brightness 0.86, or 60% opacity on secondary buttons) for 80 ms. There is no scale bounce and no washed-out amber. Disabled buttons use the fill colour, not 40% opacity. `touch-action: manipulation` is on every button, so a tap never waits for double-tap zoom.
- **Save is pinned** to the bottom edge above the home indicator. It carries an inline spinner and a fill while saving, and a check mark when done ("Saved to Photos").
- **Segmented control** fixed. The selected segment is now the raised, lighter one, as in iOS; before, it was darker than its track.
- **The photo sizes to the space that is left**, so the photo, strip, status, Adjust row and Save all fit on an iPhone 17 Pro screen. The compare chip and the "Original" badge sit on the photo's own corners, not the stage's.
- **Welcome.** The copy is in the upper middle and the actions are in the thumb zone. The header title is hidden there, because the headline already names the app.
- **Type and space** are on the scale (13/15/17/22/34, 4 px base). Controls show tabular numbers. Long presses do not select text or open callouts.
- **Accessibility.** Sliders are labelled with `aria-labelledby` and have 44 px tall inputs. Light mode's accent is darkened to #a84d18 (5.0:1 on the page, 5.6:1 under white text). The compare chip is 68% opaque, so its white text stays readable over bright skies.

## QA

- `measurements/ui-redesign/qa-welcome/`: the skill's `qa.sh` matrix for the empty state (320 to 1440 px, light and dark, reduced motion, no web fonts, no JS).
- `tools/qa-work-view.mjs` → `measurements/ui-redesign/web/`: the work view with a batch loaded, 320 and 390 px, light and dark, Adjust closed and open, with `checks.js` run in the page. Each frame shows 3 findings in dark and 4 in light, all false positives:
  - The segments (40 px) and the compare chip (30 px) are flagged as small targets. Their hit areas are extended to 48 and 46 px with pseudo-elements, which the checker cannot measure.
  - The chip's contrast is flagged because the checker cannot see the photo under the chip's translucent background.
- `measurements/ui-redesign/app-*.png`: the real app in the iPhone 17 Pro simulator (welcome, batch, Adjust, saving, saved, light mode).

## Rubric

| # | Line | Score | Why |
|---|---|---|---|
| 1 | One idea | 5 | One button on the first screen; one button to save. |
| 2 | Memorable thing | 4 | The photo, big on a dark surround. The welcome mark repeats the icon. |
| 3 | Type | 4 | The iOS text styles, tabular numbers. The system face was a decision, not a default. |
| 4 | Space | 4 | 4 px scale throughout. A landscape single photo leaves an even gap above and below. |
| 5 | Colour | 4 | Six tokens plus one accent and danger; dark designed first, light checked. |
| 6 | Layout | 5 | One column, left-aligned, Save pinned where the thumb is. |
| 7 | Motion | 5 | Only responses and progress move; reduced motion turns it all off. |
| 8 | States | 4 | Empty, loading, error, saving, saved, denied and focus all exist. Denied is unverified on a device. |
| 9 | Copy | 4 | Verbs on buttons; errors say why. "Choose" in the header could say "New". |
| 10 | Proof | 4 | Matrix run and read, plus simulator frames. A real phone has not been checked by hand. |

Removed in the final look: the stage's grey letterbox box, which put a frame around a frame.

Tried and rejected: a large-title header in the work view, which took space from the photo; a scale-down on press, which feels web-like on iOS.
