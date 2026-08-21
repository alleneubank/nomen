---
name: Gazetteer
colors:
  paper: "#c9d4c4"
  ink: "#1b2418"
  muted: "#3a4638"
  rule: "#2f3d2c"
  plate: "#1b2418"
  ochre: "#e4d7a8"
  marker: "#8f3510"
  water: "#1e4a52"
  fault: "#7a2418"
typography:
  root:
    fontFamily: Overpass
    fontSize: 16px
  label:
    fontFamily: Overpass
    fontSize: 0.875rem
  body:
    fontFamily: Overpass
    fontSize: 1.125rem
  section:
    fontFamily: Big Shoulders Display
    fontSize: 1.75rem
  wordmark:
    fontFamily: Big Shoulders Display
    fontSize: 2.75rem
  name:
    fontFamily: Big Shoulders Display
    fontSize: 3rem
  name-max:
    fontFamily: Big Shoulders Display
    fontSize: 6.5rem
  mono:
    fontFamily: Overpass Mono
    fontSize: 1.125rem
rounded:
  none: 0px
spacing:
  1: 4px
  2: 8px
  3: 12px
  4: 16px
  5: 24px
  6: 32px
  7: 48px
  8: 64px
---

## Overview

Creative North Star: *"The Field Gazetteer."* American highway lettering on map-green paper. A generated name sits on a dark destination plate, like a USGS specimen label. The page is a field sheet: labels in a left column, choices as underlined words, no cards.

The playground is an Operate surface that happens to be public. Visitors come to draw a name, copy it, and leave with the CLI. Brand lives in the plate, the type pairing, and the refusal of decoration.

## Colors

- **Paper** (`#c9d4c4`): page background. Cool stone green, not cream, not white.
- **Ink** (`#1b2418`): body text, wordmark, rules of the sheet.
- **Muted** (`#3a4638`): labels, hints, colophon. Meets WCAG AA on Paper.
- **Rule** (`#2f3d2c`): 1px structural lines. Hairlines only, never paired with a shadow.
- **Plate** (`#1b2418`): destination-sign field behind the generated name. Also the Draw button rest state.
- **Ochre** (`#e4d7a8`): lettering on Plate. Highway gold.
- **Marker** (`#8f3510`): links, focus rings, selected underline. Iron-oxide survey mark. Not purple, not cyan.
- **Water** (`#1e4a52`): selected underline for hydrographic categories (rivers, oceans, islands).
- **Fault** (`#7a2418`): error status only.

Never tint Paper toward beige. Never use a gradient, glow, or violet. Neutrals already lean green; do not add a second accent.

## Typography

Aa Big Shoulders Display · Overpass · Overpass Mono

- Display (wordmark, generated name, section titles): **Big Shoulders Display**, self-hosted. Condensed American industrial. Weight 500 for titles, 700 for the name on the plate.
- Body, labels, controls: **Overpass**. Highway Gothic lineage. Weight 400 body, 600 labels and selected options.
- Identifiers (seed, metadata, batch, code): **Overpass Mono**.

Scale (root 16px): 0.875rem labels, 1.125rem body, 1.75rem sections, 2.75rem wordmark, generated name `clamp(3rem, 9vw, 6.5rem)`. Adjacent steps stay at or above a 1.25 ratio except the fluid name, which is a single display role.

Sentence case everywhere. No italic serif hero. No Inter, Geist, Space Grotesk, or Instrument Serif. Body letter-spacing stays at 0. Wordmark may track 0.02em. Line-height 1.55 on body, ~1.4 on labels, 0.95 on the plate name.

## Elevation

Flat. No drop shadows, no glass, no radial halos. Structure is 1px Rule lines and the Plate fill. The destination plate is a color field, not a card: square corners (`0px`), no border, corner ticks as measurement marks.

## Components

- **Destination plate**: full column width, Plate fill, Ochre type, 32px padding (24px on small screens). Four 12px corner ticks. The current name is the only `h1`.
- **Field sheet**: two columns (7.5rem label / 1fr) collapsing to one column below 40rem. Related choices share a row; sections separate with 48–64px.
- **Options**: native radios, visually hidden. The label is the control. Selected state is a 2px Marker (or Water) underline, never a filled pill or side-tab.
- **Draw**: square, Plate fill, Ochre text. Hover inverts to Ochre fill / Plate text. Not full width, not a pill.
- **Plate actions** (Copy, Again): text-only Ochre on Plate. Underline on hover. No chrome.
- **Inputs**: transparent, bottom Rule only, Mono. No boxed form controls.
- **Code blocks**: Plate fill, Ochre Mono, 16px padding, `0px` radius. Install copy measure caps at 42rem.
- **Compare sheet**: HTML table whose columns are the checked sheet/list options. Default columns are the four phrase patterns. Extra columns may be triple, construct techniques, or thematic lists. Hairline Rule rows, `0px` radius, Mono name buttons, Marker underline on the active plate column. Horizontal scroll when the table exceeds the column. Not a card grid.
- **Live draw**: changing a strategy, technique, category, count, or sheet column redraws immediately. Seed/input debounce 280ms. Draw rerolls the seed unless hold is on. Random (die control on the plate) picks a new strategy, category, pattern or technique, and seed, then draws.
- **Random**: text control on the plate, ochre on Plate, inline 16px square die (5 pips, `currentColor`, square corners). Not an emoji, not a mascot.
- **Focus**: 2px Marker outline, 3px offset. Never a glow.

## Do's and Don'ts

Do treat the generated name as the page. Do keep every corner at 0px. Do self-host Overpass and Big Shoulders Display. Do left-align. Do hide category when the strategy ignores it. Do keep motion under 120ms, opacity only, and honor `prefers-reduced-motion`.

Do not add a kicker, pill badge, or eyebrow over the wordmark. Do not build a three-up feature grid, numbered steps, or hero metrics. Do not center a sentence-length headline. Do not use Inter or the 2024–2026 AI default pairings. Do not pair a hairline with a shadow. Do not round the plate. Do not write marketing verbs (empower, supercharge, seamless, world-class). Do not use em-dashes in interface copy. Do not decorate the Paper with a grid.
