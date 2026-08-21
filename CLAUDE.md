# nomen

Categorical name generator CLI for memorable, themed names.

## Quick Reference

- **Enter dev shell:** `nix develop` (or `direnv allow` with .envrc)
- **Build:** `zig build`
- **Run:** `zig build run`
- **Test:** `zig build test`
- **Format check:** `zig build fmt`
- **Lint:** `ziglint`
- **Generate docs:** `zig build docs` (output in `zig-out/docs/`)
- **All checks:** `zig build test && zig build fmt && ziglint`

## CLI Usage

```
nomen generate                          # one thematic name (human format in TTY, json otherwise)
nomen generate --count 5                # five names
nomen generate --category rivers        # names from rivers word list
nomen generate --strategy phrase        # two-word phrases (adjective-noun)
nomen generate --format json --count 3  # JSON output
nomen generate --seed 42                # deterministic output
nomen generate --fields value           # filter output fields
nomen generate --dry-run                # validate without generating
nomen generate --strategy construct:portmanteau --input "spell,master"  # blend words
nomen generate --strategy construct:compound --input "storm,forge"      # concatenate words
nomen generate --strategy construct:phonosym --input "sharp" --count 5  # sound-symbolic words
nomen generate --strategy construct:affix --input "quill"               # add prefix/suffix
nomen generate --strategy construct:acronym --input "spell,practice,app" # pronounceable acronym
nomen categories                        # list available categories
nomen serve                             # start HTTP API on port 8080
nomen serve --port 3000                 # custom port
nomen --help                            # usage info
nomen --version                         # version string
nomen --llms                            # agent discovery manifest
```

## Project Layout

```
src/
  main.zig        # CLI entrypoint — arg parsing, I/O wiring
  root.zig        # Library root — public API re-exports
  types.zig       # Domain types: Category, Strategy, Name, OutputFormat, errors
  worddata.zig    # Comptime word lists organized by category
  generator.zig   # Name generation engine (thematic, phrase, mnemonic)
  construct.zig   # Word-construction algorithms (portmanteau, compound, clip, affix, backform, phonosym, acronym)
  constructdata.zig # Comptime parsing of affix and phoneme data
  wasm.zig        # wasm32-freestanding playground exports
  format.zig      # Output formatting (json, jsonl, human)
  cli.zig         # CLI argument parser, help text, LLMs manifest
  server.zig      # HTTP API server (/generate, /categories, /health)
  data/
    words.tsv       # Master word list with POS tags, categories, tones
    curated_adjectives.txt  # Curated adjective list for phrase generation
    curated_nouns.txt       # Curated noun list for phrase generation
    affixes.tsv     # Prefix/suffix list with tone tags for construct:affix
    phonemes.tsv    # Phoneme sets per mood for construct:phonosym
build.zig         # Build script (test, docs, fmt, run, wasm steps)
build.zig.zon     # Package manifest (name, version, deps)
SPEC.md           # Product specification with requirement IDs
DESIGN.md         # Playground visual system
site/             # Static playground (HTML/CSS/JS + nomen.wasm)
.ziglint.zon      # Linter configuration
flake.nix         # Nix dev environment and packages.default
```

## Architecture

- **types.zig** defines the domain model: `Category` enum (14 themes), `Strategy` tagged union (thematic/phrase/triple/mnemonic/construct), `ConstructTechnique` enum, `Name` struct, `OutputFormat`, and explicit error sets
- **worddata.zig** contains comptime arrays of curated words per category plus adjective/noun/verb lists for phrase generation
- **wasm.zig** exports the generator to wasm32-freestanding for `site/`
- **generator.zig** implements `Generator` struct with seeded PRNG. Supports batch generation with first-syllable phonetic deduplication
- **construct.zig** implements `ConstructEngine` struct with 7 word-construction algorithms. Supports batch generation with phonetic dedup
- **constructdata.zig** parses `affixes.tsv` and `phonemes.tsv` at comptime. Exports affix lists, phoneme sets, and backform suffixes
- **format.zig** handles JSON, JSONL, and human-readable output with field filtering
- **cli.zig** parses subcommands and flags with control-char rejection, detects TTY for format defaulting, generates per-subcommand help text and `--llms` agent manifest with examples
- **server.zig** HTTP API server with `/generate`, `/categories`, `/health` endpoints; validates all query params and returns structured JSON errors
- **main.zig** wires CLI -> generator -> formatter -> stdout. Errors go to stderr with structured codes; pre-scans args for `--format` to respect user format preference on errors

## Conventions

- Tests live alongside code in `test` blocks within `.zig` files
- Library public API in `src/root.zig`; internal modules imported with `@import`
- `std.log.scoped` for namespaced logging
- Pass allocators explicitly — no global state
- Explicit error sets — no `anyerror`
- Prefer `const` over `var`; prefer slices over raw pointers
- Word lists are comptime arrays, no runtime file I/O
- stdout = data only, stderr = human messages (agent-first CLI design)

## Tooling

- **Zig 0.15.2** — via `mitchellh/zig-overlay` (nix flake)
- **ZLS** — language server from nixpkgs-unstable
- **ziglint** — static analysis (prebuilt binary via nix)
- **lefthook** — git hooks (fmt, lint, test on pre-commit)
- **zig fmt** — canonical formatter (built into zig)

## Generation Strategies

- **thematic** — single word from a category word list (mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse, volcanoes, forests, oceans, storms)
- **phrase** — two-word combination: adjective-noun, noun-noun, verb-noun, alliterative
- **triple** — three-word combination (adjective-adjective-noun or adjective-noun-noun)
- **mnemonic** — deterministic word pair from numeric/hex input
- **construct** — word-construction techniques (use `--input` for seed words):
  - `construct:portmanteau` — blend two words at overlap point (motor+oracle → motoracle)
  - `construct:compound` — concatenate two words (storm+forge → stormforge)
  - `construct:clip` — first syllable + last syllable (information+master → inforter)
  - `construct:affix` — add prefix/suffix (quill → neoquill, quillium)
  - `construct:backform` — strip suffix to root (constellation → constella)
  - `construct:phonosym` — construct word from mood-tagged phonemes (--input sharp/soft/rhythmic)
  - `construct:acronym` — pronounceable acronym from word initials (spell+practice+app → spa)
