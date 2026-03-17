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
  wordlist.zig    # Comptime word lists organized by category
  generator.zig   # Name generation engine (thematic, phrase, mnemonic)
  format.zig      # Output formatting (json, jsonl, human)
  cli.zig         # CLI argument parser, help text, LLMs manifest
  server.zig      # HTTP API server (/generate, /categories, /health)
build.zig         # Build script (test, docs, fmt, run steps)
build.zig.zon     # Package manifest (name, version, deps)
SPEC.md           # Product specification with requirement IDs
PLAN.md           # Implementation plan (ephemeral)
.ziglint.zon      # Linter configuration
flake.nix         # Nix dev environment
```

## Architecture

- **types.zig** defines the domain model: `Category` enum (10 themes), `Strategy` tagged union (thematic/phrase/mnemonic), `Name` struct, `OutputFormat`, and explicit error sets
- **wordlist.zig** contains comptime arrays of curated words per category (15 words each) plus adjective/noun/verb lists for phrase generation
- **generator.zig** implements `Generator` struct with seeded PRNG. Supports batch generation with first-syllable phonetic deduplication
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

- **thematic** — single word from a category word list (mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse)
- **phrase** — two-word combination: adjective-noun, noun-noun, verb-noun
- **mnemonic** — deterministic word pair from numeric/hex input
