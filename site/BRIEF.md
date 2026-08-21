# BRIEF — playground

> Law doc for the nomen playground, present-tense, no narrated history — git is the changelog. The Boundary and ratified Decisions amend only with human confirmation; the driver appends provisional Decisions, marked and dated.

## Bar

A stranger can draw a DNS-safe name in one action, copy it, and install the CLI, on a page that fails closed against AI-default visuals.

## Dimensions

- **Fidelity** — playground output matches the CLI for the same seed, strategy, category, count, and input
- **Legibility** — type, contrast, and focus meet WCAG AA; the name is the primary heading
- **Taste** — Field Gazetteer (`DESIGN.md`); zero findings from `npx impeccable detect site/`
- **Operability** — strategy, category, seed, and count are visible; shareable query string; wasm failure still shows install
- **Observability** — generate errors surface in `#status` with a specific message, not a generic fail

## Floors

| Dimension | Floor |
|---|---|
| Fidelity | `nomen generate --seed N --format json` equals playground JSON for the same flags, checked by comparing one seeded draw in the browser against the CLI |
| Legibility | Body contrast ≥ 4.5:1 on Paper; Ochre on Plate ≥ 4.5:1; functional text ≥ 14px; measured in CSS tokens and a contrast script |
| Taste | `npx impeccable detect site/` exits 0 |
| Operability | Draw, Copy, and category/strategy changes work at 360px and 1280px viewport widths |
| Observability | Invalid mnemonic input and missing wasm each set `#status` to a distinct sentence |

## Oracle

- **Pre-ship:** `npx impeccable detect site/` (deterministic slop and design-system rules; maker does not grade). Browser pass: draw, copy, share URL, fail wasm path.
- Independent taste: a reviewer who did not write `site/` runs detect and a 60-second use. Self-review is not the oracle.

## Never — instant fail

- Inter, Geist, Space Grotesk, Instrument Serif, or a purple/violet accent
- Cream or beige page background
- Feature-card grid, numbered steps, hero metrics, kicker/eyebrow above the wordmark
- Border-radius above 0px
- Drop shadow, glass, gradient text, or radial glow
- Marketing verbs: empower, supercharge, seamless, world-class, next-generation
- Em-dashes in interface copy
- A name that is not DNS-safe
- Weakening a floor without a dated waiver Decision

## Decisions

- **Priority:** taste and fidelity outrank extra sections. If the page grows a docs portal, the playground stays the first screen. (2026-08-20, provisional)
- **Type pairing:** Big Shoulders Display + Overpass + Overpass Mono, self-hosted. Highway / USGS, not editorial serif. (2026-08-20, provisional)
- **Surface mode:** Operate, with install as a Read strip below the sheet. Not a Persuade landing. (2026-08-20, provisional)
- **Engine:** wasm32-freestanding from `src/wasm.zig`, same generator as the CLI. No hosted `nomen serve` for the public page. (2026-08-20, provisional)
- **Corners:** 0px everywhere. (2026-08-20, provisional)
- **Public repo:** `alleneubank/nomen`. (2026-08-20, provisional)
- **Phrase sheet:** four-column ledger of phrase patterns from the same seed, Fogleman-style density without feature cards. Default count is 5. (2026-08-20, provisional)
- **Mix-and-match:** CLI stays one strategy and one category per process. The playground compares by issuing one generate per checked column. (2026-08-20, provisional)
- **Live draw:** control changes redraw. Random on the plate shuffles generation settings. No previous-generations pane. (2026-08-20, provisional)

## Boundary — requires the human

- Publish: GitHub Pages enablement, custom domain, flipping the repository public
- Credentials: none on this surface
- Direction: first release tag
