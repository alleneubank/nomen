# nomen Implementation Plan

## Task Graph

### Phase 1: Core Types and Word Lists
**Files**: `src/types.zig`, `src/wordlist.zig`
**Risk**: LOW
**Tests**: Word list validation, type construction

1. Define `Category` enum, `Strategy` tagged union, `Name` struct, `OutputFormat` enum in `src/types.zig`
2. Create `src/wordlist.zig` with comptime word arrays per category (10-20 words each)
3. Add adjective, noun, verb lists for phrase generation
4. Tests: all words are lowercase/alphabetic/<= 12 chars, categories are non-empty

### Phase 2: Generator Engine
**Files**: `src/generator.zig`
**Risk**: LOW
**Tests**: Deterministic output with seeds, DNS-safe output, batch uniqueness

1. Implement `Generator` with PRNG seeded from user input or system entropy
2. `generateThematic(category) -> Name` — random word from category list
3. `generatePhrase(pattern) -> Name` — combine adjective+noun, noun+noun, or verb+noun
4. `generateMnemonic(input) -> Name` — deterministic mapping from numeric input to word pair
5. `generateBatch(count, category, strategy) -> []Name` — batch with phonetic dedup
6. Tests: seed determinism, DNS-safe output validation, batch phonetic distinctness

### Phase 3: Output Formatting
**Files**: `src/format.zig`
**Risk**: LOW
**Tests**: JSON/JSONL/human output correctness, field filtering

1. `formatJson(names, fields) -> []u8` — JSON array output
2. `formatJsonl(names, fields) -> []u8` — newline-delimited JSON
3. `formatHuman(names) -> []u8` — plain text, one name per line
4. `formatError(code, message) -> []u8` — structured error output
5. Tests: output matches expected format, field filtering works

### Phase 4: CLI Argument Parsing
**Files**: `src/cli.zig`
**Risk**: LOW
**Tests**: Argument parsing, validation, help text generation

1. Parse subcommands: `generate`, `categories`, `--help`, `--version`, `--llms`
2. Parse generate flags: `--count`, `--category`, `--strategy`, `--seed`, `--format`, `--fields`, `--dry-run`
3. Detect TTY for format defaulting
4. Input validation: control char rejection, enum validation
5. Tests: flag parsing, default values, error on invalid input

### Phase 5: Main Entrypoint Wiring
**Files**: `src/main.zig`, `src/root.zig`
**Risk**: LOW
**Tests**: Integration via `zig build run -- generate`

1. Wire CLI parser -> generator -> formatter -> stdout
2. Update `src/root.zig` to export public API types
3. Implement `categories` subcommand
4. Implement `--help`, `--version`, `--llms`
5. Tests: end-to-end via `zig build run`

### Phase 6: HTTP Server (deferred)
**Files**: `src/server.zig`
**Risk**: LOW (read-only)
**Tests**: HTTP response format, endpoint routing

1. `nomen serve --port 8080`
2. Routes: `/generate`, `/categories`, `/health`
3. Reuse generator + formatter from library
4. Tests: request/response validation

### Phase 7: Update CLAUDE.md
**Files**: `CLAUDE.md`
**Risk**: NONE

1. Document actual nomen architecture, CLI commands, module layout
2. Update conventions to reflect implemented patterns

## Dependency Graph

```
Phase 1 (types, wordlist)
    ↓
Phase 2 (generator) ← depends on types + wordlist
    ↓
Phase 3 (format) ← depends on types
    ↓
Phase 4 (cli) ← depends on types
    ↓
Phase 5 (main) ← depends on all above
    ↓
Phase 6 (server) ← depends on generator + format
    ↓
Phase 7 (docs)
```

## Build Order

Phases 1-5 are required for the Done-when criteria. Phase 6 (HTTP) is deferred. Phase 7 is cleanup.
