# nomen — Categorical Name Generator

## Problem

Naming resources (servers, projects, deployments, branches) is a recurring friction point. Random alphanumeric strings are unmemorable. Functional names ("auth-server", "prod-db") become lies when roles change (RFC 1178). Teams need short, memorable, phonetically distinct names drawn from curated themes — generated on demand by both humans and automated agents.

## Solution

`nomen` is a Zig CLI and HTTP API that generates memorable, themed names using categorical word lists and combinatorial patterns. It is agent-first: structured output by default, introspectable schemas, and deterministic behavior. Two interfaces serve the same generation engine:

- **CLI** (`nomen generate`) — produces names to stdout following agent-first CLI practices
- **HTTP API** (`nomen serve`) — JSON API for services and agents to generate names over HTTP

## Domain Model

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  WordList    │────▶│  Generator   │────▶│  Name       │
│  (category)  │     │  (strategy)  │     │  (output)   │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │
       ▼                    ▼
┌─────────────┐     ┌──────────────┐
│  Category   │     │  Strategy    │
│  enum       │     │  union       │
└─────────────┘     └──────────────┘
```

### Core Types

**Category** — thematic grouping of words:
- `mountains`, `rivers`, `deserts`, `canyons`, `islands`, `passes` (American geography)
- `moons`, `raptors`, `minerals`, `norse` (additional themes)
- `volcanoes`, `forests`, `oceans`, `storms` (expanded themes)

**Strategy** — name generation algorithm:
- `thematic` — single word from a category word list
- `phrase` — two-word combination (Adjective+Noun, Noun+Noun, Verb+Noun, Alliterative)
- `triple` — three-word combination (Adjective+Adjective+Noun or Adjective+Noun+Noun)
- `mnemonic` — encode numeric/hex input into memorable word pairs (or triples for long inputs)

**Name** — generated output:
- `value: []const u8` — the generated name string
- `category: ?Category` — source category when the strategy uses one, otherwise null
- `strategy_tag: []const u8` — generation method used (e.g. `thematic`, `construct:portmanteau`)

**ConstructTechnique** — word-construction algorithm on the `construct` strategy variant:
- `portmanteau`, `compound`, `clip`, `affix`, `backform`, `phonosym`, `acronym`

**OutputFormat** — serialization target:
- `json` — JSON object (default in non-TTY)
- `jsonl` — newline-delimited JSON
- `human` — plain text (default in TTY)

## Requirements

### Generation

- **REQ-GEN-001**: Generate names from embedded word lists organized by category. Word lists are comptime arrays, no runtime file I/O.
- **REQ-GEN-002**: Support thematic strategy — select a random word from a specified category.
- **REQ-GEN-003**: Support phrase strategy — combine words from two lists using patterns: Adjective+Noun, Noun+Noun, Verb+Noun.
- **REQ-GEN-004**: Support mnemonic strategy — encode a numeric or hex input into a memorable word pair using a deterministic mapping.
- **REQ-GEN-005**: All generated names must be lowercase and DNS-safe (only `[a-z0-9-]`, no leading/trailing hyphens).
- **REQ-GEN-006**: Batch generation must produce phonetically distinct names — no two names in the same batch share a first syllable.
- **REQ-GEN-007**: Accept a `--count N` flag to generate N names in one invocation (default: 1).
- **REQ-GEN-008**: Accept a `--category` flag to restrict generation to a specific category.
- **REQ-GEN-009**: Accept a `--strategy` flag to select the generation strategy (default: thematic).
- **REQ-GEN-010**: Accept a `--seed` flag for deterministic output. Same seed + same parameters = same names.
- **REQ-GEN-011**: Support alliterative phrase pattern — retry normal phrase generation up to 50 times until both words share the same starting letter. Fall back to non-alliterative if no match found. Syllable rhythm (REQ-GEN-012) and tonal coherence (REQ-WL-005) apply during retries.
- **REQ-GEN-012**: Phrase generation should prefer syllable-balanced pairings (total 3-5 syllables) as a soft preference. Fall back to any pairing after 10 attempts.
- **REQ-GEN-013**: Support triple-word strategy — three-word combinations (adjective-adjective-noun or adjective-noun-noun).
- **REQ-GEN-014**: Mnemonic strategy must use FNV-1a hash for better distribution across the word pair space.
- **REQ-GEN-015**: Mnemonic strategy should encode long inputs (>8 hex chars) as three words instead of two for higher entropy.

### Construct

- **REQ-CON-001**: `ConstructTechnique` enum: `portmanteau`, `compound`, `clip`, `affix`, `backform`, `phonosym`, `acronym`.
- **REQ-CON-002**: `Strategy` includes `construct: ConstructTechnique`. The variant carries only the technique, not input words.
- **REQ-CON-003**: `Strategy.fromString` parses `construct` (defaults to portmanteau) and `construct:<technique>`.
- **REQ-CON-004**: Bare `--strategy construct` resolves `strategy_tag` to `construct:portmanteau`.
- **REQ-CON-010**: `--input` for construct is comma-separated lowercase alphabetic words, max 5 words, max 20 characters each.
- **REQ-CON-011**: `--input` is optional for construct. Omitted input draws from built-in lists.
- **REQ-CON-012**: Missing words for a technique are filled from built-in lists (category list when `--category` is set).
- **REQ-CON-013**: Input validation is strategy-aware: mnemonic uses `validateMnemonicInput`, construct uses `validateConstructInput`.
- **REQ-CON-014**: User-supplied construct words have no tone metadata and are treated as `general`.
- **REQ-CON-020**: Portmanteau blends two words on the longest end/start overlap of at least 2 characters; otherwise vowel-consonant splice.
- **REQ-CON-021**: Compound concatenates two words with no separator.
- **REQ-CON-022**: Clip takes the first syllable of word1 and the last syllable of word2.
- **REQ-CON-023**: Affix attaches a tone-compatible prefix or suffix from `src/data/affixes.tsv`.
- **REQ-CON-024**: Backform strips the longest recognized suffix, with a syllable fallback.
- **REQ-CON-025**: Phonosym builds a 4–8 character word from mood templates (`sharp`, `soft`, `rhythmic`). Invalid mood is `InvalidInput`.
- **REQ-CON-026**: Acronym takes initials and inserts vowels to break 3+ consonant clusters.
- **REQ-CON-027**: `--count > 1` varies construction per iteration (replace word2, affix, mood draw, or input substitution).
- **REQ-CON-028**: Exploratory mode (no `--input`) draws from category lists or curated nouns as specified per technique.
- **REQ-CON-029**: First-syllable phonetic dedup applies to construct batches.
- **REQ-CON-030**: `src/data/affixes.tsv` is parsed at comptime (prefix/suffix, tone).
- **REQ-CON-031**: `src/data/phonemes.tsv` is parsed at comptime (mood, class, values).
- **REQ-CON-040**: CLI surface is `nomen generate --strategy construct:<technique>`.
- **REQ-CON-050**: HTTP `/generate` accepts `strategy=construct:<technique>` and `input=word1,word2`.
- **REQ-CON-060**: Construct output uses `Name` with `strategy_tag` `construct:<technique>`.
- **REQ-CON-061**: Constructed names are lowercase `[a-z0-9]` (no hyphens).
- **REQ-CON-063**: Same seed and parameters produce the same construct output.
- **REQ-CON-065**: Empty or invalid construction returns `GenerateError.ConstructionFailed`.

### CLI

- **REQ-CLI-001**: `nomen generate` subcommand produces names to stdout.
- **REQ-CLI-002**: `--format` flag selects output format: `json`, `jsonl`, `human`. Default: `json` when stdout is not a TTY, `human` when it is.
- **REQ-CLI-003**: `--fields` flag filters output keys in structured formats.
- **REQ-CLI-004**: stdout carries data only. Progress, warnings, and errors go to stderr.
- **REQ-CLI-005**: Structured errors with `code` and `message` fields. Exit codes: 0=success, 1=runtime error, 2=validation error.
- **REQ-CLI-006**: `--help` on every subcommand with machine-readable output via `--help --format json`.
- **REQ-CLI-007**: `--version` flag outputs version string.
- **REQ-CLI-008**: `--dry-run` flag validates inputs without generating names.
- **REQ-CLI-009**: Reject control characters (bytes <0x20 except whitespace, 0x7F) in all string inputs.
- **REQ-CLI-010**: `--llms` flag outputs agent discovery manifest (command schemas, flags, examples).
- **REQ-CLI-011**: `nomen categories` subcommand lists available categories.

### HTTP API

- **REQ-HTTP-001**: `nomen serve` starts an HTTP server on a configurable port (default: 8080).
- **REQ-HTTP-002**: `GET /generate` endpoint accepts query parameters matching CLI flags and returns JSON.
- **REQ-HTTP-003**: `GET /categories` endpoint returns available categories.
- **REQ-HTTP-004**: `GET /health` endpoint returns server status.
- **REQ-HTTP-005**: Structured JSON error responses with `code` and `message` fields.

### Playground

- **REQ-SITE-001**: `zig build wasm` emits `site/nomen.wasm` from `src/wasm.zig` targeting wasm32-freestanding.
- **REQ-SITE-002**: The playground exposes thematic, phrase (all patterns), triple, mnemonic, and all construct techniques.
- **REQ-SITE-003**: The same seed, strategy, category, count, and input produce the same names as the CLI.
- **REQ-SITE-004**: Query string round-trips strategy, category, count, seed, and input.
- **REQ-SITE-005**: Visual system is `DESIGN.md`. `npx impeccable detect site/` is the slop floor.
- **REQ-SITE-006**: After a draw, the playground fills a compare sheet: one wasm generate call per checked column, same seed, `count` rows. Default columns are the four phrase patterns. Columns may also be triple, `construct:<technique>`, or `thematic:<category>`.
- **REQ-SITE-007**: Changing strategy, pattern, technique, category, count, or sheet columns redraws without a submit. Seed and input fields debounce.
- **REQ-SITE-008**: A Random control on the plate picks a strategy, category, phrase pattern or construct technique, and seed at random, then draws. Mnemonic gets a random hex input.
- **REQ-SITE-009**: The CLI and HTTP API remain one `--strategy` and one `--category` per invocation. Multi-column compare is playground fan-out of those calls, not a new engine mode.

### Word Lists

- **REQ-WL-001**: Word lists are embedded at compile time via comptime arrays.
- **REQ-WL-002**: Each category contains 10-30 curated words for the initial release.
- **REQ-WL-003**: All words in lists must be lowercase, alphabetic, and <= 12 characters.
- **REQ-WL-004**: Phrase-mode word lists include separate adjective, noun, and verb lists.
- **REQ-WL-005**: Words carry a tone tag (`nature`, `tech`, `general`) for tonal coherence in phrase generation. Compatible pairings: nature+nature, nature+general, tech+tech, tech+general, general+general.
- **REQ-WL-006**: Categories include at minimum: mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse, volcanoes, forests, oceans, storms.
- **REQ-WL-007**: Each category should contain 15-50 curated words. Expanded from initial 10-30 target.

## Invariants

- Generated names contain only `[a-z0-9-]` characters, no leading/trailing hyphens.
- Same seed + same parameters always produces the same output.
- stdout never contains non-data output (progress, warnings, decoration).
- Word lists are immutable at runtime; all data is comptime-embedded.
- Allocators are passed explicitly; no global mutable state.

## Non-Goals

- **Uniqueness guarantees** — nomen does not track previously generated names or maintain state between invocations. Consumers are responsible for deduplication.
- **Dictionary completeness** — word lists are curated for quality over quantity. This is not a dictionary.
- **Internationalization** — names are ASCII-only for DNS compatibility.
- **Configuration files** — all options are flags or environment variables. No config file format.
- **Plugin system** — custom word lists or strategies are not supported in v1. Embed everything.
- **TLS/auth on HTTP** — the HTTP server is plain HTTP for local/internal use. Put it behind a reverse proxy for production.
- **MCP server** — deferred to v2. v1 focuses on CLI, HTTP, and the static playground.
- **Hosted generate API** — the public playground runs the generator in WebAssembly. It does not call `nomen serve`.

## Risk Tags

- **LOW**: No schema migrations, no auth, no external dependencies.
- **LOW**: HTTP server is read-only (no mutations, no state).

## Acceptance Criteria

- [ ] `zig build test` passes with tests covering generator, CLI parsing, output formatting
- [ ] `nomen generate` produces a name to stdout
- [ ] `nomen generate --format json --count 5` produces 5 JSON-formatted names
- [ ] `nomen generate --category mountains` restricts output to mountain names
- [ ] `nomen generate --seed 42` produces deterministic output
- [ ] `nomen categories` lists all available categories
- [ ] `nomen --help` shows subcommands and global flags
- [ ] `nomen generate --help` shows generate-specific flags
- [ ] `nomen --version` prints version
- [ ] Non-TTY stdout defaults to JSON format
- [ ] stderr receives human messages, stdout receives data only
- [ ] Invalid inputs produce structured errors with codes
- [ ] `nomen serve` starts HTTP server with /generate, /categories, /health endpoints
- [ ] CLAUDE.md reflects actual project architecture
- [ ] `nomen generate --strategy phrase:alliterative --count 5` produces mostly alliterative phrases (fallback to non-alliterative after 50 retries)
- [ ] `nomen generate --strategy triple --count 3` produces three-word names
- [ ] `nomen generate --category volcanoes` produces volcano-themed names
- [ ] `nomen generate --strategy mnemonic --input 0xdeadbeefcafe` produces a three-word mnemonic
- [ ] `nomen categories` lists >= 14 categories
- [ ] `nomen generate --strategy construct:compound --input "storm,forge"` produces `stormforge`
- [ ] `nomen generate --strategy construct:portmanteau --input "spell,master" --seed 42` is deterministic
- [ ] `zig build wasm` produces `site/nomen.wasm`
- [ ] `npx impeccable detect site/` exits 0
