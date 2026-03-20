# nomen Construct Strategies — Design Spec

## Problem

nomen generates names from themed word lists using selection and combination strategies (thematic, phrase, triple, mnemonic). This covers "pick from existing words" but not "build new words." Users naming projects, products, or features need constructed names — portmanteaus, compounds, clipped forms, affixed words, and phonetically crafted nonsense words. Currently, an agent or user must brainstorm these manually outside nomen.

## Solution

Add a `construct` strategy family to nomen's `generate` command. Seven construction techniques produce novel words algorithmically. Each technique works in two modes: **guided** (user provides seed words via `--input`) and **exploratory** (nomen pulls from built-in word lists). All output remains DNS-safe and deterministic with `--seed`.

CLI pattern: `nomen generate --strategy construct:<technique> [--input "word1,word2"] [--category raptors] [--count 5]`

This mirrors the existing `phrase:<pattern>` convention and keeps everything under the `generate` subcommand.

## Domain Model Extension

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  WordList        │────▶│  Generator   │────▶│  Name       │
│  (category)      │     │  (strategy)  │     │  (output)   │
│  AffixList       │────▶│              │     │             │
│  PhonemeTemplates│────▶│              │     │             │
└─────────────────┘     └──────────────┘     └─────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐     ┌──────────────────┐
│  Category enum   │     │  Strategy union   │
│  (unchanged)     │     │  + construct:     │
└─────────────────┘     │    ConstructTech  │
                        └──────────────────┘
```

### Strategy Data Flow

The `construct` variant of the `Strategy` union carries **only the technique enum**, not the input words. This differs from `mnemonic`, which carries its input string in the union payload. For construct strategies, input words are parsed separately and passed to the generator via an extended signature.

```
CLI --input "spell,master"
  → parseConstructInput() splits and validates → []const []const u8
  → GenerateOptions.input = "spell,master" (raw string, unchanged)
  → main.zig parses input into word slice before calling generator
  → Generator.generateConstruct(technique, category, input_words) → Name
```

### Generator Signature

The existing `Generator.generate()` and `Generator.generateBatch()` signatures are **unchanged**. Instead, a new method is added:

```zig
pub fn generateConstruct(
    self: *Generator,
    technique: ConstructTechnique,
    category: ?Category,
    input_words: []const []const u8,  // empty slice = exploratory mode
) GenerateError!Name
```

And a corresponding batch method:

```zig
pub fn generateConstructBatch(
    self: *Generator,
    allocator: std.mem.Allocator,
    count: u32,
    technique: ConstructTechnique,
    category: ?Category,
    input_words: []const []const u8,
) (std.mem.Allocator.Error || GenerateError)!BatchResult
```

The `main.zig` dispatch logic checks for `strategy == .construct` and calls the construct-specific methods. This avoids breaking existing callers.

### Buffer Size

The existing `Generator.buf` is `[38]u8`. Construct strategies can produce longer names (compound of two 20-char words = 40 chars). The `buf` field is resized to `[42]u8` to accommodate the maximum construct output (40 chars) with margin. `BatchResult.values` element size is updated to match. This change is internal to `generator.zig` and does not affect the public `Name` type (which uses slices).

## Requirements

### Type System

- **REQ-CON-001**: Add `ConstructTechnique` enum with variants: `portmanteau`, `compound`, `clip`, `affix`, `backform`, `phonosym`, `acronym`.
- **REQ-CON-002**: Add `construct: ConstructTechnique` variant to the `Strategy` tagged union. The variant carries only the technique enum, not input words.
- **REQ-CON-003**: `Strategy.fromString` must parse `"construct"` (defaults to `portmanteau`), `"construct:portmanteau"`, `"construct:compound"`, `"construct:clip"`, `"construct:affix"`, `"construct:backform"`, `"construct:phonosym"`, `"construct:acronym"`.
- **REQ-CON-004**: When `--strategy construct` is used (bare, no technique suffix), the `strategy_tag` in output is `"construct:portmanteau"` (the resolved default), not `"construct"`.

### Input Handling

- **REQ-CON-010**: Extend `--input` to accept comma-separated alphabetic words for construct strategies. Max 5 words, each word <= 20 characters, lowercase alphabetic only.
- **REQ-CON-011**: `--input` is optional for all construct strategies. When omitted, words are drawn from built-in word lists.
- **REQ-CON-012**: When `--input` provides fewer words than a technique requires (e.g. one word for portmanteau which needs two), the remaining words are drawn from built-in lists. When `--category` is also specified, built-in words come from that category.
- **REQ-CON-013**: Input validation is strategy-aware. `--input` is valid for both `mnemonic` and `construct:*` strategies. Mnemonic validates hex/numeric via `validateMnemonicInput`. Construct validates comma-separated alphabetic words via a new `validateConstructInput` function. The CLI and server dispatch validation based on the active strategy.
- **REQ-CON-014**: User-supplied input words carry no tone metadata. For tonal coherence purposes (REQ-WL-005), user-supplied words are treated as `general` tone (compatible with all tones).

### Construction Algorithms

- **REQ-CON-020**: **Portmanteau** — Blend two words by finding the longest overlapping character sequence (minimum 2 characters) at the end of word1 and the start of word2. Matching is on lowercase bytes (all inputs are already lowercase per REQ-CON-010). If no overlap >= 2 characters exists, cut word1 at the rightmost vowel-consonant boundary and append word2 from its first vowel onward. If word2 has no vowel, append word2 in full.
- **REQ-CON-021**: **Compound** — Concatenate two words directly with no separator. Output is a single DNS-safe token (lowercase, alphabetic only).
- **REQ-CON-022**: **Clip** — Take the first syllable of word1 and the last syllable of word2. Syllable boundaries are determined by vowel groups: scan left-to-right and place a boundary at each consonant-to-vowel transition (where a consonant is followed by a vowel). The first syllable is everything up to and including the first boundary. The last syllable is everything from the last boundary onward. For monosyllabic words (no consonant-to-vowel transition found), use the whole word. Example: `"champion"` splits as `"cham"` | `"pi"` | `"on"` → last syllable = `"on"`. `"spell"` is monosyllabic → whole word. Result: `"spellon"`. This requires a runtime syllable-splitting function (distinct from the existing comptime `comptimeSyllableCount` which only counts).
- **REQ-CON-023**: **Affix** — Select a random prefix or suffix from a curated affix list and attach to the base word. Affix selection respects tonal coherence (REQ-WL-005). User-supplied base words are treated as `general` tone per REQ-CON-014.
- **REQ-CON-024**: **Backform** — Strip the longest recognized suffix from the end of the input word. Recognized suffixes (checked longest-first): `-ible`, `-able`, `-tion`, `-ment`, `-ness`, `-ance`, `-ence`, `-ive`, `-ous`, `-ity`, `-ing`, `-ure`. If no recognized suffix matches, truncate at the first consonant-to-vowel transition after the second vowel group (approximating two syllables). If the result is fewer than 2 characters, return the first 3 characters of the input.
- **REQ-CON-025**: **Phonosym** — Construct a pronounceable word from phoneme templates tagged by mood (`sharp`, `soft`, `rhythmic`). The template engine uses these patterns, selected by PRNG per generation:
  - 4-char: CV-CV (e.g., `ki-xa`)
  - 5-char: CVC-CV (e.g., `krix-a`) or CV-CVC (e.g., `ki-xar`)
  - 6-char: CV-CV-CV (e.g., `ki-xa-te`) or CVC-CVC (e.g., `krix-tar`)
  - 7-char: CVC-CV-CV (e.g., `krix-a-te`) or CV-CVC-CV (e.g., `ki-xar-te`)
  - 8-char: CV-CV-CV-CV (e.g., `ki-xa-te-po`)

  Where C = a single consonant from the mood's consonant set and V = a single vowel from the mood's vowel set. Multi-character phoneme entries in `phonemes.tsv` (e.g., `cr`, `sh`) are treated as consonant clusters — each cluster occupies one C slot and contributes its full length to the output. Mood is specified via `--input "sharp"`, `--input "soft"`, or `--input "rhythmic"`. If `--input` is provided and does not match a valid mood, return `InvalidInput` error. Random mood when `--input` is omitted.
- **REQ-CON-026**: **Acronym** — Take the first letter of each input word. If the resulting string contains at least one vowel and no more than two consecutive consonants, output as-is. Otherwise, insert a PRNG-selected vowel (from `{a, e, i, o, u}`) immediately after the second consonant in each cluster of 3+ consecutive consonants. Example: `"b,c,d,f"` → `bcdf` → `bc` + `a` + `df` → `bcadf`. Continue until no cluster of 3+ consecutive consonants remains.

### Exploratory Mode Word Selection

- **REQ-CON-028**: When `--input` is omitted (exploratory mode), words for two-word techniques (portmanteau, compound, clip) are selected as follows:
  - If `--category` is specified: both words are drawn from that category's word list.
  - If no category: word1 is drawn from the curated noun list and word2 is drawn from the curated noun list (same pool as phrase:noun_noun). This produces noun-noun constructions by default.
  - For affix exploratory mode: the base word is drawn from the curated noun list (or category list if specified).
  - For backform exploratory mode: the base word is drawn from the main `words.tsv` dictionary filtered to words with >= 6 characters (so there is something to strip).
  - For acronym exploratory mode: 3-5 words (count selected by PRNG) are drawn from the curated noun list (or category list if specified).

### Batch Variation

- **REQ-CON-027**: When `--count > 1`, construct strategies produce distinct names by varying the construction for each iteration:
  - **portmanteau, compound, clip**: If two input words are fully specified via `--input`, augment with a different built-in word for the second slot on each iteration (first iteration uses the user's word2, subsequent iterations replace word2 with built-in words).
  - **affix**: Different prefix/suffix selected per iteration.
  - **backform**: Only one output per input word; if `--count > 1`, additional words are drawn from built-in lists and backformed.
  - **phonosym**: Different PRNG state per iteration produces different phoneme combinations.
  - **acronym**: If fully specified via `--input`, additional names are generated by substituting individual input words with built-in alternatives.

### Deduplication

- **REQ-CON-029**: The existing first-syllable phonetic deduplication applies to construct strategy batch output. For short construct outputs (e.g., 4-char phonosym words), first-syllable extraction may produce very short keys (2-3 chars), increasing collision likelihood. This is acceptable — the dedup retry budget (existing 20 attempts) applies. If `NoDistinctNames` is returned, the caller should reduce `--count` or change the mood/technique.

### Data

- **REQ-CON-030**: Add `src/data/affixes.tsv` with columns: `affix<TAB>type<TAB>tone` where `type` is `prefix` or `suffix` and `tone` is `nature`, `tech`, or `general`. Maximum affix length: 6 characters. Minimum entry count: 8 prefixes and 8 suffixes.
- **REQ-CON-031**: Add `src/data/phonemes.tsv` with columns: `mood<TAB>class<TAB>values` where `class` is `consonants` or `vowels`, and `values` is a comma-separated list of phoneme strings. Each phoneme string is 1-2 characters. Minimum: 5 consonants and 3 vowels per mood, for all 3 moods (6 rows total).
- **REQ-CON-032**: Backform suffix list is inlined in the generator as a comptime array (small, static, no external file needed).
- **REQ-CON-033**: All new data is parsed at comptime. No runtime file I/O.

### CLI

- **REQ-CON-040**: `nomen generate --strategy construct:<technique>` is the CLI surface for all construction strategies.
- **REQ-CON-041**: `nomen generate --help` lists all construct techniques alongside existing strategies.
- **REQ-CON-042**: `--llms` manifest includes construct strategy examples for agent discovery.
- **REQ-CON-043**: Error messages for invalid construct techniques list all valid options. The existing `InvalidStrategy` error message is updated to include `construct` and `construct:<technique>` as valid options.

### HTTP API

- **REQ-CON-050**: `/generate` endpoint accepts `strategy=construct:<technique>` and `input=word1,word2` query parameters.
- **REQ-CON-051**: Invalid construct technique in query params returns structured JSON error.

### Output

- **REQ-CON-060**: Construct strategy outputs use the existing `Name` struct: `value` (the constructed name), `category` (set to the specified `--category` when provided, null otherwise), `strategy_tag` (e.g. `"construct:portmanteau"`).
- **REQ-CON-061**: All constructed names are DNS-safe: lowercase, `[a-z0-9]` only (no hyphens). This is a strict subset of the existing DNS-safe character set (`[a-z0-9-]` used by phrase strategies), intentional because construct strategies produce single tokens rather than multi-word phrases.
- **REQ-CON-062**: Batch generation with `--count` produces distinct outputs per REQ-CON-027 and REQ-CON-029.
- **REQ-CON-063**: Deterministic output with `--seed`. Same seed + same parameters = same names.
- **REQ-CON-064**: Maximum constructed name length is 40 characters (to accommodate compound of two 20-character inputs). The `Generator.buf` is resized from `[38]u8` to `[42]u8` and `BatchResult.values` element size is updated to match. This is an internal change; the public `Name` type uses slices and is unaffected.
- **REQ-CON-065**: If a construction algorithm produces an empty or invalid result (e.g. backform strips to fewer than 2 characters, acronym with zero input words), return `GenerateError.ConstructionFailed`. This is a new error variant added to `GenerateError`.

## Invariants

- All existing invariants from SPEC.md are preserved.
- No changes to existing strategies (thematic, phrase, triple, mnemonic).
- No new subcommands — everything under `generate`.
- No new output fields on `Name`.
- Comptime data, no runtime I/O.
- Explicit error sets, no `anyerror`.
- Note: `Name.category` is `?Category` (nullable) in the implementation. The existing SPEC.md describes it as non-optional — this is a pre-existing mismatch that should be corrected in SPEC.md separately.

## Non-Goals

- No interactive/guided naming mode — that is the agent's responsibility, not nomen's.
- No quality scoring or ranking of generated names — nomen generates, the consumer curates.
- No AI/LLM integration — all construction is algorithmic.
- No user-extensible affix or phoneme lists — everything is compiled in.

## Risk Tags

- **LOW**: No schema migrations, no auth, no external dependencies.
- **LOW**: All new code is pure computation on comptime data.
- **MEDIUM**: Portmanteau and clip algorithms involve heuristic splice-point selection — may need tuning for quality. Mitigated by seed-based determinism enabling reproducible testing.

## Acceptance Criteria

- [ ] `zig build test` passes with tests covering all 7 construct techniques
- [ ] `nomen generate --strategy construct:portmanteau --input "spell,master" --seed 42` produces a deterministic blended word that shares a prefix with "spell" and a suffix with "master"
- [ ] `nomen generate --strategy construct:compound --input "storm,forge"` produces `stormforge`
- [ ] `nomen generate --strategy construct:clip --input "spell,champion"` produces `spellon` (first syllable of "spell" = whole word + last syllable of "champion" = "on")
- [ ] `nomen generate --strategy construct:affix --input "quill" --seed 42` produces a deterministic prefixed or suffixed word
- [ ] `nomen generate --strategy construct:backform --input "constellation"` produces `constella` (strips `-tion`, the longest matching suffix)
- [ ] `nomen generate --strategy construct:phonosym --input "sharp" --seed 42` produces a deterministic 4-8 char word using only consonants from the sharp set and vowels
- [ ] `nomen generate --strategy construct:phonosym --input "soft" --seed 42` produces a deterministic 4-8 char word using only consonants from the soft set and vowels
- [ ] `nomen generate --strategy construct:phonosym --input "loud"` returns `InvalidInput` error
- [ ] `nomen generate --strategy construct:acronym --input "spell,practice,app"` produces `spa`
- [ ] `nomen generate --strategy construct` (bare) resolves to `construct:portmanteau` and outputs `strategy_tag` as `"construct:portmanteau"`
- [ ] All construct strategies work without `--input` (exploratory mode using built-in lists per REQ-CON-028)
- [ ] `--category` restricts built-in word selection for construct strategies and sets `Name.category` on output
- [ ] `--count 5` produces 5 distinct constructed names per REQ-CON-027
- [ ] `--seed 42` produces deterministic output for all construct strategies
- [ ] `--format json` outputs valid JSON with `strategy_tag` set to `construct:<technique>`
- [ ] `nomen generate --help` lists all construct techniques
- [ ] `nomen --llms` manifest includes construct strategy examples
- [ ] `/generate?strategy=construct:portmanteau&input=spell,master` works via HTTP API
- [ ] Existing strategies (thematic, phrase, triple, mnemonic) are unaffected
- [ ] CLAUDE.md updated to reflect construct strategies, new data files, and any new source modules
- [ ] `Generator.buf` resized to `[42]u8` and all existing tests still pass
