# nomen

## Platform

web

The public surface is a static playground (`site/`) plus a Zig CLI and a local HTTP API. Native apps are out of scope.

## Audience

People who name machines, branches, containers, releases, and side projects, including agents that call the CLI non-interactively.

## Purpose

Draw a short, DNS-safe name from curated geographic and natural-history lists, or construct one from seed words. Same seed and flags always yield the same name.

## Positioning

nomen is a gazetteer, not a branding studio. It does not score names, store history, or call a language model. The claim a neighbor cannot copy is the combination of fourteen embedded lists, phonetic batch dedup, and construct techniques that stay ASCII and deterministic.

## Evidence

- CLI: `nomen generate`, `nomen categories`, `nomen --llms`
- HTTP: `nomen serve` with `/generate`, `/categories`, `/health`
- Playground: `site/index.html` running `site/nomen.wasm` built from `src/wasm.zig`

## Brand commitments

- Names are lowercase `[a-z0-9-]` with no leading or trailing hyphen.
- stdout is data; stderr is human. JSON when stdout is not a TTY.
- Visual system is the Field Gazetteer in `DESIGN.md`: map-green paper, highway display type, destination plate, square corners.
- No telemetry in the generator. Word lists are compiled in.
