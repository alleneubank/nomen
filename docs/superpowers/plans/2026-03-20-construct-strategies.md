# Construct Strategies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 7 word-construction strategies (portmanteau, compound, clip, affix, backform, phonosym, acronym) to nomen's `generate` command via `--strategy construct:<technique>`.

**Architecture:** Extend the existing `Strategy` tagged union with a `construct: ConstructTechnique` variant. Add new `generateConstruct()` and `generateConstructBatch()` methods to `Generator` (existing methods unchanged). New comptime data files for affixes and phonemes. Input validation dispatched by strategy type.

**Tech Stack:** Zig 0.15.2, comptime data embedding, existing PRNG-based generation engine.

**Spec:** `docs/superpowers/specs/2026-03-20-construct-strategies-design.md`

**Skills:** @zig-best-practices

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `src/types.zig` | Modify | Add `ConstructTechnique` enum, extend `Strategy` union, add `ConstructionFailed` error, add `validateConstructInput` |
| `src/construct.zig` | Create | All 7 construction algorithms + runtime syllable splitting + construct batch generation |
| `src/data/affixes.tsv` | Create | Curated prefix/suffix list with tone tags |
| `src/data/phonemes.tsv` | Create | Phoneme sets per mood (sharp/soft/rhythmic) |
| `src/constructdata.zig` | Create | Comptime parsing of affixes.tsv and phonemes.tsv |
| `src/root.zig` | Modify | Export new modules |
| `src/main.zig` | Modify | Strategy-aware input validation dispatch, construct generation dispatch |
| `src/cli.zig` | Modify | Update help text and LLMs manifest for construct strategies |
| `src/server.zig` | Modify | Strategy-aware query param validation, construct generation dispatch |
| `src/generator.zig` | Modify | Resize `buf` to `[42]u8`, update `BatchResult` |
| `CLAUDE.md` | Modify | Document construct strategies, new files, new data |

---

### Task 1: Type System — ConstructTechnique and Strategy Extension

**Files:**
- Modify: `src/types.zig`

- [ ] **Step 1: Write failing test for ConstructTechnique enum**

In `src/types.zig`, add at the bottom:

```zig
test "ConstructTechnique.fromString valid" {
    const ct = ConstructTechnique.fromString("portmanteau");
    try std.testing.expectEqual(ConstructTechnique.portmanteau, ct.?);
}

test "ConstructTechnique.fromString invalid" {
    try std.testing.expect(ConstructTechnique.fromString("bogus") == null);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: compilation error, `ConstructTechnique` not defined.

- [ ] **Step 3: Add ConstructTechnique enum**

In `src/types.zig`, after the `PhrasePattern` enum (line 33), add:

```zig
pub const ConstructTechnique = enum {
    portmanteau,
    compound,
    clip,
    affix,
    backform,
    phonosym,
    acronym,

    pub fn fromString(s: []const u8) ?ConstructTechnique {
        return std.meta.stringToEnum(ConstructTechnique, s);
    }

    pub fn toString(self: ConstructTechnique) []const u8 {
        return @tagName(self);
    }
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 5: Write failing test for Strategy.fromString with construct variants**

```zig
test "Strategy.fromString construct bare" {
    const s = try Strategy.fromString("construct");
    try std.testing.expect(s == .construct);
    try std.testing.expectEqual(ConstructTechnique.portmanteau, s.construct);
}

test "Strategy.fromString construct:compound" {
    const s = try Strategy.fromString("construct:compound");
    try std.testing.expect(s == .construct);
    try std.testing.expectEqual(ConstructTechnique.compound, s.construct);
}

test "Strategy.fromString construct:invalid" {
    const result = Strategy.fromString("construct:bogus");
    try std.testing.expectError(error.InvalidStrategy, result);
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `.construct` is not a valid `Strategy` tag.

- [ ] **Step 7: Extend Strategy union and fromString**

In `src/types.zig`, add `construct: ConstructTechnique` variant to the `Strategy` union (after `mnemonic`). Update `Strategy.fromString`:

```zig
pub const Strategy = union(enum) {
    thematic,
    phrase: PhrasePattern,
    triple,
    mnemonic: []const u8,
    construct: ConstructTechnique,

    pub fn fromString(s: []const u8) ParseError!Strategy {
        if (std.mem.eql(u8, s, "thematic")) return .thematic;
        if (std.mem.eql(u8, s, "phrase")) return .{ .phrase = .adjective_noun };
        if (std.mem.eql(u8, s, "phrase:adjective_noun")) return .{ .phrase = .adjective_noun };
        if (std.mem.eql(u8, s, "phrase:noun_noun")) return .{ .phrase = .noun_noun };
        if (std.mem.eql(u8, s, "phrase:verb_noun")) return .{ .phrase = .verb_noun };
        if (std.mem.eql(u8, s, "phrase:alliterative")) return .{ .phrase = .alliterative };
        if (std.mem.eql(u8, s, "triple")) return .triple;
        if (std.mem.eql(u8, s, "mnemonic")) return .{ .mnemonic = "" };
        if (std.mem.eql(u8, s, "construct")) return .{ .construct = .portmanteau };
        if (std.mem.startsWith(u8, s, "construct:")) {
            const technique_str = s["construct:".len..];
            if (ConstructTechnique.fromString(technique_str)) |technique| {
                return .{ .construct = technique };
            }
            return error.InvalidStrategy;
        }
        return error.InvalidStrategy;
    }
};
```

- [ ] **Step 8: Write failing test for validateConstructInput**

```zig
test "validateConstructInput accepts comma-separated words" {
    try validateConstructInput("spell,master");
}

test "validateConstructInput accepts single word" {
    try validateConstructInput("quill");
}

test "validateConstructInput rejects non-alpha" {
    try std.testing.expectError(error.InvalidInput, validateConstructInput("spell,123"));
}

test "validateConstructInput rejects too many words" {
    try std.testing.expectError(error.InvalidInput, validateConstructInput("a,b,c,d,e,f"));
}

test "validateConstructInput rejects too-long word" {
    try std.testing.expectError(error.InvalidInput, validateConstructInput("abcdefghijklmnopqrstu"));
}

test "validateConstructInput rejects empty" {
    try std.testing.expectError(error.InvalidInput, validateConstructInput(""));
}
```

- [ ] **Step 9: Implement validateConstructInput**

In `src/types.zig`, add after `validateMnemonicInput`:

```zig
/// Validate construct strategy input: comma-separated alphabetic words,
/// max 5 words, each <= 20 characters, lowercase alpha only.
pub fn validateConstructInput(input: []const u8) ParseError!void {
    if (input.len == 0) return error.InvalidInput;

    var word_count: u8 = 0;
    var word_len: u8 = 0;

    for (input) |c| {
        if (c == ',') {
            if (word_len == 0) return error.InvalidInput;
            word_count += 1;
            if (word_count > 5) return error.InvalidInput;
            word_len = 0;
        } else if (c >= 'a' and c <= 'z') {
            word_len += 1;
            if (word_len > 20) return error.InvalidInput;
        } else {
            return error.InvalidInput;
        }
    }

    if (word_len == 0) return error.InvalidInput;
    word_count += 1;
    if (word_count > 5) return error.InvalidInput;
}
```

- [ ] **Step 10: Write failing test for ConstructionFailed error**

```zig
test "GenerateError includes ConstructionFailed" {
    const err: GenerateError = error.ConstructionFailed;
    try std.testing.expect(err == error.ConstructionFailed);
}
```

- [ ] **Step 11: Add ConstructionFailed to GenerateError**

```zig
pub const GenerateError = error{
    EmptyWordList,
    NoDistinctNames,
    ConstructionFailed,
};
```

- [ ] **Step 12: Run all tests and verify they pass**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 13: Commit**

```bash
git add src/types.zig
git commit -m "feat: add ConstructTechnique enum, Strategy.construct variant, and input validation"
```

---

### Task 2: Construct Data — Affixes and Phonemes

**Files:**
- Create: `src/data/affixes.tsv`
- Create: `src/data/phonemes.tsv`
- Create: `src/constructdata.zig`

- [ ] **Step 1: Create affixes.tsv**

Create `src/data/affixes.tsv` with tab-separated columns `affix\ttype\ttone`:

```tsv
neo	prefix	tech
re	prefix	general
un	prefix	general
hyper	prefix	tech
proto	prefix	tech
omni	prefix	tech
meta	prefix	tech
sub	prefix	general
super	prefix	general
micro	prefix	tech
ify	suffix	tech
ium	suffix	nature
lex	suffix	tech
ara	suffix	nature
ion	suffix	general
ix	suffix	tech
oid	suffix	tech
ux	suffix	tech
ova	suffix	nature
ine	suffix	nature
```

- [ ] **Step 2: Create phonemes.tsv**

Create `src/data/phonemes.tsv` with tab-separated columns `mood\tclass\tvalues`:

```tsv
sharp	consonants	k,t,p,x,z,cr,tr,sp
sharp	vowels	i,e,a,ix,ex
soft	consonants	m,l,n,s,w,fl,sl
soft	vowels	a,o,u,el,in
rhythmic	consonants	k,b,t,z,m,d,r
rhythmic	vowels	a,o,i,u,e
```

- [ ] **Step 3: Write failing test for constructdata comptime parsing**

Create `src/constructdata.zig`:

```zig
const std = @import("std");
const worddata = @import("worddata.zig");
const Tone = worddata.Tone;

test "affix data has at least 8 prefixes" {
    var count: usize = 0;
    for (all_affixes) |a| {
        if (a.is_prefix) count += 1;
    }
    try std.testing.expect(count >= 8);
}

test "affix data has at least 8 suffixes" {
    var count: usize = 0;
    for (all_affixes) |a| {
        if (!a.is_prefix) count += 1;
    }
    try std.testing.expect(count >= 8);
}

test "affix length max 6 chars" {
    for (all_affixes) |a| {
        try std.testing.expect(a.value.len <= 6);
    }
}

test "phoneme data has entries for all 3 moods" {
    try std.testing.expect(sharp_consonants.len >= 5);
    try std.testing.expect(sharp_vowels.len >= 3);
    try std.testing.expect(soft_consonants.len >= 5);
    try std.testing.expect(soft_vowels.len >= 3);
    try std.testing.expect(rhythmic_consonants.len >= 5);
    try std.testing.expect(rhythmic_vowels.len >= 3);
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: compilation error, symbols not defined.

- [ ] **Step 5: Implement comptime parsing in constructdata.zig**

```zig
const std = @import("std");
const worddata = @import("worddata.zig");
const Tone = worddata.Tone;

// --- Affix data ---

pub const Affix = struct {
    value: []const u8,
    is_prefix: bool,
    tone: Tone,
};

const affix_raw = @embedFile("data/affixes.tsv");

fn comptimeParseAffixes(comptime data: []const u8) []const Affix {
    @setEvalBranchQuota(data.len * 4);
    var affixes: []const Affix = &.{};
    var line_start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n' or i == data.len - 1) {
            const line_end = if (c == '\n') i else i + 1;
            const line = data[line_start..line_end];
            line_start = i + 1;

            if (line.len == 0) continue;

            // Parse: value\ttype\ttone
            const tab1 = comptimeFindChar(line, '\t', 0) orelse continue;
            const tab2 = comptimeFindChar(line, '\t', tab1 + 1) orelse continue;

            const value = line[0..tab1];
            const type_str = line[tab1 + 1 .. tab2];
            const tone_str = line[tab2 + 1 ..];

            if (value.len == 0 or value.len > 6) @compileError("affix must be 1-6 chars: " ++ value);

            const is_prefix = if (std.mem.eql(u8, type_str, "prefix"))
                true
            else if (std.mem.eql(u8, type_str, "suffix"))
                false
            else
                @compileError("affix type must be prefix or suffix: " ++ type_str);

            const tone: Tone = if (std.mem.eql(u8, tone_str, "nature"))
                .nature
            else if (std.mem.eql(u8, tone_str, "tech"))
                .tech
            else if (std.mem.eql(u8, tone_str, "general"))
                .general
            else
                @compileError("invalid tone: " ++ tone_str);

            affixes = affixes ++ .{Affix{ .value = value, .is_prefix = is_prefix, .tone = tone }};
        }
    }

    return affixes;
}

fn comptimeFindChar(comptime s: []const u8, comptime ch: u8, comptime start: usize) ?usize {
    for (s[start..], start..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

pub const all_affixes: []const Affix = comptimeParseAffixes(affix_raw);

pub fn getPrefixes() []const Affix {
    comptime {
        var result: []const Affix = &.{};
        for (all_affixes) |a| {
            if (a.is_prefix) result = result ++ .{a};
        }
        return result;
    }
}

pub fn getSuffixes() []const Affix {
    comptime {
        var result: []const Affix = &.{};
        for (all_affixes) |a| {
            if (!a.is_prefix) result = result ++ .{a};
        }
        return result;
    }
}

pub const prefixes: []const Affix = getPrefixes();
pub const suffixes: []const Affix = getSuffixes();

// --- Phoneme data ---

const phoneme_raw = @embedFile("data/phonemes.tsv");

fn comptimeParsePhonemes(comptime data: []const u8, comptime mood: []const u8, comptime class: []const u8) []const []const u8 {
    @setEvalBranchQuota(data.len * 4);
    var line_start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n' or i == data.len - 1) {
            const line_end = if (c == '\n') i else i + 1;
            const line = data[line_start..line_end];
            line_start = i + 1;

            if (line.len == 0) continue;

            const tab1 = comptimeFindChar(line, '\t', 0) orelse continue;
            const tab2 = comptimeFindChar(line, '\t', tab1 + 1) orelse continue;

            const line_mood = line[0..tab1];
            const line_class = line[tab1 + 1 .. tab2];
            const values_str = line[tab2 + 1 ..];

            if (std.mem.eql(u8, line_mood, mood) and std.mem.eql(u8, line_class, class)) {
                // Parse comma-separated values
                var result: []const []const u8 = &.{};
                var val_start: usize = 0;
                for (values_str, 0..) |vc, vi| {
                    if (vc == ',') {
                        const val = values_str[val_start..vi];
                        if (val.len > 0 and val.len <= 2) result = result ++ .{val};
                        val_start = vi + 1;
                    }
                }
                // Last value
                const last = values_str[val_start..];
                if (last.len > 0 and last.len <= 3) result = result ++ .{last};
                return result;
            }
        }
    }
    return &.{};
}

pub const sharp_consonants = comptimeParsePhonemes(phoneme_raw, "sharp", "consonants");
pub const sharp_vowels = comptimeParsePhonemes(phoneme_raw, "sharp", "vowels");
pub const soft_consonants = comptimeParsePhonemes(phoneme_raw, "soft", "consonants");
pub const soft_vowels = comptimeParsePhonemes(phoneme_raw, "soft", "vowels");
pub const rhythmic_consonants = comptimeParsePhonemes(phoneme_raw, "rhythmic", "consonants");
pub const rhythmic_vowels = comptimeParsePhonemes(phoneme_raw, "rhythmic", "vowels");

// --- Backform suffixes (inlined, REQ-CON-032) ---

pub const backform_suffixes = [_][]const u8{
    "ible", "able", "tion", "ment", "ness", "ance", "ence", "ive", "ous", "ity", "ing", "ure",
};
```

- [ ] **Step 6: Register constructdata in root.zig**

Add to `src/root.zig`:

```zig
pub const constructdata = @import("constructdata.zig");
```

- [ ] **Step 7: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add src/data/affixes.tsv src/data/phonemes.tsv src/constructdata.zig src/root.zig
git commit -m "feat: add comptime affix and phoneme data for construct strategies"
```

---

### Task 3: Generator Buffer Resize

**Files:**
- Modify: `src/generator.zig`

- [ ] **Step 1: Resize buf from [38]u8 to [42]u8**

In `src/generator.zig`, change line 28:

```zig
// 42 bytes = max compound (20+20) or construct output with margin
buf: [42]u8 = undefined,
```

- [ ] **Step 2: Update BatchResult values type**

Change line 319:

```zig
values: [][42]u8,
```

And in `generateBatch` line 270:

```zig
const values = try allocator.alloc([42]u8, count);
```

- [ ] **Step 3: Add `.construct` arm to `Generator.generate()` switch**

The `Strategy` union now has a `.construct` variant. `Generator.generate()` uses a switch on strategy which must be exhaustive. Add an unreachable arm since construct strategies are handled separately via `ConstructEngine`:

In `src/generator.zig`, in the `generate` function's switch (line 44-49), add:

```zig
.construct => unreachable, // handled by ConstructEngine in main.zig/server.zig
```

- [ ] **Step 4: Run all existing tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass (buffer resize is backward-compatible, existing names fit in 42 bytes).

- [ ] **Step 5: Commit**

```bash
git add src/generator.zig
git commit -m "feat: resize generator buffer to 42 bytes, add construct arm to strategy switch"
```

---

### Task 4: Construction Algorithms — Core Engine

**Files:**
- Create: `src/construct.zig`

This is the largest task. Each algorithm is implemented and tested individually.

- [ ] **Step 1: Write failing test for compound (simplest algorithm)**

Create `src/construct.zig`:

```zig
const std = @import("std");
const types = @import("types.zig");
const worddata = @import("worddata.zig");
const constructdata = @import("constructdata.zig");
const Category = types.Category;
const ConstructTechnique = types.ConstructTechnique;
const GenerateError = types.GenerateError;
const Name = types.Name;
const Tone = worddata.Tone;

test "compound concatenates two words" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.compound, null, &.{ "storm", "forge" });
    try std.testing.expectEqualStrings("stormforge", name.value);
    try std.testing.expectEqualStrings("construct:compound", name.strategy_tag);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: `ConstructEngine` not defined.

- [ ] **Step 3: Implement ConstructEngine struct and compound**

```zig
pub const ConstructEngine = struct {
    prng: std.Random.DefaultPrng,
    buf: [42]u8 = undefined,

    pub fn init(seed: ?u64) ConstructEngine {
        const actual_seed = seed orelse blk: {
            var s: [8]u8 = undefined;
            std.posix.getrandom(&s) catch {
                break :blk @as(u64, 0);
            };
            break :blk std.mem.readInt(u64, &s, .little);
        };
        return .{ .prng = std.Random.DefaultPrng.init(actual_seed) };
    }

    pub fn generateConstruct(
        self: *ConstructEngine,
        technique: ConstructTechnique,
        category: ?Category,
        input_words: []const []const u8,
    ) (GenerateError || types.ParseError)!Name {
        return switch (technique) {
            .compound => self.generateCompound(category, input_words),
            .portmanteau => self.generatePortmanteau(category, input_words),
            .clip => self.generateClip(category, input_words),
            .affix => self.generateAffix(category, input_words),
            .backform => self.generateBackform(category, input_words),
            .phonosym => self.generatePhonosym(category, input_words),
            .acronym => self.generateAcronym(category, input_words),
        };
    }

    fn resolveTwo(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError![2][]const u8 {
        const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
        if (list.len == 0) return error.EmptyWordList;
        const rand = self.prng.random();

        var result: [2][]const u8 = undefined;
        result[0] = if (input_words.len >= 1) input_words[0] else list[rand.intRangeLessThan(usize, 0, list.len)];
        result[1] = if (input_words.len >= 2) input_words[1] else list[rand.intRangeLessThan(usize, 0, list.len)];
        return result;
    }

    fn generateCompound(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
        const words = try self.resolveTwo(category, input_words);
        const len = words[0].len + words[1].len;
        if (len > self.buf.len or len == 0) return error.ConstructionFailed;

        @memcpy(self.buf[0..words[0].len], words[0]);
        @memcpy(self.buf[words[0].len..len], words[1]);

        return .{
            .value = self.buf[0..len],
            .category = category,
            .strategy_tag = "construct:compound",
        };
    }
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 5: Write failing test for portmanteau**

```zig
test "portmanteau blends overlapping words" {
    var eng = ConstructEngine.init(42);
    // "motor" + "oracle" — suffix "or" of "motor" matches prefix "or" of "oracle" (2 chars)
    // Result: "motor" + "acle" = "motorcycle" wait no. "motor"(5) + "oracle"(6) - 2 overlap = "motoracle"
    const name = try eng.generateConstruct(.portmanteau, null, &.{ "motor", "oracle" });
    try std.testing.expectEqualStrings("motoracle", name.value);
    try std.testing.expectEqualStrings("construct:portmanteau", name.strategy_tag);
}

test "portmanteau fallback when no overlap" {
    var eng = ConstructEngine.init(42);
    // "storm" + "fury" — no 2-char overlap
    // Rightmost VC boundary in "storm": s-t-o-r-m → word[i-1]='o' is vowel, word[i]='r' is consonant → return i=3
    // Cut word1 at index 3: "sto"
    // firstVowelIndex("fury"): 'u' at index 1 → suffix = "ury"
    // Result: "sto" + "ury" = "stoury"
    const name = try eng.generateConstruct(.portmanteau, null, &.{ "storm", "fury" });
    try std.testing.expectEqualStrings("stoury", name.value);
}
```

- [ ] **Step 6: Implement portmanteau**

Add to `ConstructEngine`:

```zig
fn generatePortmanteau(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
    const words = try self.resolveTwo(category, input_words);
    const w1 = words[0];
    const w2 = words[1];

    // Try overlap: find longest suffix of w1 that matches prefix of w2 (>= 2 chars)
    var best_overlap: usize = 0;
    const max_check = @min(w1.len, w2.len);
    var check: usize = 2;
    while (check <= max_check) : (check += 1) {
        if (std.mem.eql(u8, w1[w1.len - check ..], w2[0..check])) {
            best_overlap = check;
        }
    }

    if (best_overlap >= 2) {
        // Overlap blend: w1 + w2[overlap..]
        const len = w1.len + w2.len - best_overlap;
        if (len > self.buf.len or len == 0) return error.ConstructionFailed;
        @memcpy(self.buf[0..w1.len], w1);
        @memcpy(self.buf[w1.len..len], w2[best_overlap..]);
        return .{ .value = self.buf[0..len], .category = category, .strategy_tag = "construct:portmanteau" };
    }

    // Fallback: cut w1 at rightmost vowel-consonant boundary, append w2 from first vowel
    const cut = rightmostVCBoundary(w1);
    const w2_start = firstVowelIndex(w2);

    const prefix = w1[0..cut];
    const suffix = w2[w2_start..];
    const len = prefix.len + suffix.len;
    if (len > self.buf.len or len == 0) return error.ConstructionFailed;

    @memcpy(self.buf[0..prefix.len], prefix);
    @memcpy(self.buf[prefix.len..len], suffix);
    return .{ .value = self.buf[0..len], .category = category, .strategy_tag = "construct:portmanteau" };
}

fn isVowel(c: u8) bool {
    return c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u' or c == 'y';
}

/// Find the rightmost vowel-to-consonant boundary in a word.
/// Returns the index after the vowel (i.e., where to cut).
fn rightmostVCBoundary(word: []const u8) usize {
    if (word.len <= 1) return word.len;
    var i = word.len - 1;
    while (i > 0) : (i -= 1) {
        if (!isVowel(word[i]) and isVowel(word[i - 1])) {
            return i;
        }
    }
    return word.len; // no boundary found, use whole word
}

/// Find the index of the first vowel in a word.
/// If no vowel, returns 0 (append whole word per REQ-CON-020).
fn firstVowelIndex(word: []const u8) usize {
    for (word, 0..) |c, i| {
        if (isVowel(c)) return i;
    }
    return 0;
}
```

Update the `generateConstruct` switch to add `.portmanteau => self.generatePortmanteau(category, input_words)`.

- [ ] **Step 7: Run tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 8: Write failing test for clip**

```zig
test "clip takes first syllable of word1, last syllable of word2" {
    var eng = ConstructEngine.init(42);
    // firstSyllableSlice uses C→V boundaries. A boundary is where a consonant
    // is followed by a vowel. The first syllable = word[0..second_boundary].
    // If 0 or 1 boundaries exist, word is monosyllabic → return whole word.
    //
    // "spell": s-p-e-l-l. C→V transitions: p→e at index 1→2. Only 1 boundary → monosyllabic → "spell"
    //
    // lastSyllableSlice: finds last C→V boundary, returns word[boundary..].
    // "master": m-a-s-t-e-r. C→V transitions: m→a (0→1), t→e (3→4).
    //   Last boundary at index 3 (consonant 't'). Return word[3..] = "ter"
    const name = try eng.generateConstruct(.clip, null, &.{ "spell", "master" });
    try std.testing.expectEqualStrings("spellter", name.value);
    try std.testing.expectEqualStrings("construct:clip", name.strategy_tag);
}

test "clip with multi-syllable first word" {
    var eng = ConstructEngine.init(42);
    // "information": i-n-f-o-r-m-a-t-i-o-n
    //   C→V transitions: n→o (2→3 — wait, 'n' is at 1, not 2)
    //   Let me index: i(0) n(1) f(2) o(3) r(4) m(5) a(6) t(7) i(8) o(9) n(10)
    //   C→V: n(1)→o — wait, that's wrong. n is at index 1, but we check word[i] is consonant
    //   and word[i+1] is vowel. Boundaries at the consonant index:
    //   idx 2: f(C) → o(V) → boundary. idx 5: m(C) → a(V) → boundary. idx 7: t(C) → i(V) → boundary.
    //   Also idx 1: n(C) but next is f(C) → no. Wait: boundary = where word[i] is C and word[i+1] is V.
    //   Hmm, the implementation scans for C→V transitions using consecutive chars.
    //   First boundary: f(2)→o(3). Second boundary: m(5)→a(6).
    //   firstSyllableSlice returns word[0..second_boundary_consonant_index].
    //   Second boundary consonant is at index 5. Return word[0..5] = "infor"
    //
    // "master": last C→V boundary at index 3 (t→e). Return word[3..] = "ter"
    const name = try eng.generateConstruct(.clip, null, &.{ "information", "master" });
    try std.testing.expectEqualStrings("inforter", name.value);
}
```

- [ ] **Step 9: Implement clip with runtime syllable splitting**

```zig
fn generateClip(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
    const words = try self.resolveTwo(category, input_words);
    const first_syl = firstSyllableSlice(words[0]);
    const last_syl = lastSyllableSlice(words[1]);

    const len = first_syl.len + last_syl.len;
    if (len > self.buf.len or len == 0) return error.ConstructionFailed;

    @memcpy(self.buf[0..first_syl.len], first_syl);
    @memcpy(self.buf[first_syl.len..len], last_syl);
    return .{ .value = self.buf[0..len], .category = category, .strategy_tag = "construct:clip" };
}

/// Return the first syllable of a word using C→V (consonant-to-vowel) boundaries.
/// A boundary occurs at index i where word[i] is a consonant and word[i+1] is a vowel.
/// The first syllable is everything up to the start of the second syllable.
/// If 0 or 1 boundaries, the word is monosyllabic → return the whole word.
fn firstSyllableSlice(word: []const u8) []const u8 {
    if (word.len <= 2) return word;
    var boundary_count: usize = 0;
    var i: usize = 0;
    while (i + 1 < word.len) : (i += 1) {
        if (!isVowel(word[i]) and isVowel(word[i + 1])) {
            boundary_count += 1;
            if (boundary_count == 2) {
                // Second boundary — the consonant at i starts the second syllable
                return word[0..i];
            }
        }
    }
    return word; // monosyllabic (0 or 1 boundaries)
}

/// Return the last syllable of a word using C→V boundaries.
/// Finds the last C→V boundary and returns from that consonant onward.
/// If no boundaries, the word is monosyllabic → return the whole word.
fn lastSyllableSlice(word: []const u8) []const u8 {
    if (word.len <= 2) return word;
    var last_boundary: usize = 0;
    var found_any = false;
    var i: usize = 0;
    while (i + 1 < word.len) : (i += 1) {
        if (!isVowel(word[i]) and isVowel(word[i + 1])) {
            last_boundary = i;
            found_any = true;
        }
    }
    if (!found_any) return word; // monosyllabic
    return word[last_boundary..];
}
```

Update `generateConstruct` switch: `.clip => self.generateClip(category, input_words)`.

- [ ] **Step 10: Run tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 11: Write failing test for affix**

```zig
test "affix attaches prefix or suffix" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.affix, null, &.{"quill"});
    // Output should start with a known prefix or end with a known suffix
    const value = name.value;
    var found = false;
    for (constructdata.prefixes) |p| {
        if (std.mem.startsWith(u8, value, p.value) and std.mem.eql(u8, value[p.value.len..], "quill")) {
            found = true;
            break;
        }
    }
    if (!found) {
        for (constructdata.suffixes) |s| {
            if (std.mem.endsWith(u8, value, s.value) and std.mem.eql(u8, value[0 .. value.len - s.value.len], "quill")) {
                found = true;
                break;
            }
        }
    }
    try std.testing.expect(found);
    try std.testing.expectEqualStrings("construct:affix", name.strategy_tag);
}
```

- [ ] **Step 12: Implement affix**

```zig
fn generateAffix(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
    const base = if (input_words.len >= 1)
        input_words[0]
    else blk: {
        const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
        if (list.len == 0) return error.EmptyWordList;
        break :blk list[self.prng.random().intRangeLessThan(usize, 0, list.len)];
    };

    const rand = self.prng.random();
    // User input is general tone; built-in words we'd need to look up but for simplicity
    // we pick a random affix (tonal coherence: general is compatible with all)
    const use_prefix = rand.boolean();

    if (use_prefix) {
        const p = constructdata.prefixes[rand.intRangeLessThan(usize, 0, constructdata.prefixes.len)];
        const len = p.value.len + base.len;
        if (len > self.buf.len) return error.ConstructionFailed;
        @memcpy(self.buf[0..p.value.len], p.value);
        @memcpy(self.buf[p.value.len..len], base);
        return .{ .value = self.buf[0..len], .category = category, .strategy_tag = "construct:affix" };
    } else {
        const s = constructdata.suffixes[rand.intRangeLessThan(usize, 0, constructdata.suffixes.len)];
        const len = base.len + s.value.len;
        if (len > self.buf.len) return error.ConstructionFailed;
        @memcpy(self.buf[0..base.len], base);
        @memcpy(self.buf[base.len..len], s.value);
        return .{ .value = self.buf[0..len], .category = category, .strategy_tag = "construct:affix" };
    }
}
```

Update `generateConstruct` switch: `.affix => self.generateAffix(category, input_words)`.

- [ ] **Step 13: Run tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 14: Write failing test for backform**

```zig
test "backform strips longest suffix" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.backform, null, &.{"constellation"});
    try std.testing.expectEqualStrings("constella", name.value);
    try std.testing.expectEqualStrings("construct:backform", name.strategy_tag);
}

test "backform with -ment suffix" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.backform, null, &.{"arrangement"});
    try std.testing.expectEqualStrings("arrange", name.value);
}

test "backform truncates when no recognized suffix" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.backform, null, &.{"crystal"});
    // No recognized suffix. Truncate after 2nd vowel group.
    // c-r-y-s-t-a-l → vowel groups: "y" at index 2 (group 1), "a" at index 5 (group 2)
    // After 2nd vowel group ends, first consonant is 'l' at index 6.
    // truncateAfterSecondVowelGroup returns 6.
    try std.testing.expectEqualStrings("crysta", name.value);
}
```

- [ ] **Step 15: Implement backform**

```zig
fn generateBackform(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
    const word = if (input_words.len >= 1)
        input_words[0]
    else blk: {
        // Exploratory: pick a word >= 6 chars from the dictionary
        const list = worddata.mnemonic_all;
        const rand = self.prng.random();
        var attempts: usize = 0;
        while (attempts < 100) : (attempts += 1) {
            const w = list[rand.intRangeLessThan(usize, 0, list.len)];
            if (w.len >= 6) break :blk w;
        }
        return error.EmptyWordList;
    };

    // Try stripping longest suffix first
    for (constructdata.backform_suffixes) |suffix| {
        if (word.len > suffix.len and std.mem.endsWith(u8, word, suffix)) {
            const result_len = word.len - suffix.len;
            if (result_len < 2) {
                // Too short, use first 3 chars
                const safe_len = @min(3, word.len);
                @memcpy(self.buf[0..safe_len], word[0..safe_len]);
                return .{ .value = self.buf[0..safe_len], .category = category, .strategy_tag = "construct:backform" };
            }
            @memcpy(self.buf[0..result_len], word[0..result_len]);
            return .{ .value = self.buf[0..result_len], .category = category, .strategy_tag = "construct:backform" };
        }
    }

    // No suffix match: truncate after second vowel group
    const cut = truncateAfterSecondVowelGroup(word);
    if (cut < 2) {
        const safe_len = @min(3, word.len);
        @memcpy(self.buf[0..safe_len], word[0..safe_len]);
        return .{ .value = self.buf[0..safe_len], .category = category, .strategy_tag = "construct:backform" };
    }
    @memcpy(self.buf[0..cut], word[0..cut]);
    return .{ .value = self.buf[0..cut], .category = category, .strategy_tag = "construct:backform" };
}

fn truncateAfterSecondVowelGroup(word: []const u8) usize {
    var vowel_groups: u8 = 0;
    var in_vowel = false;
    for (word, 0..) |c, i| {
        if (isVowel(c)) {
            if (!in_vowel) {
                vowel_groups += 1;
                in_vowel = true;
            }
        } else {
            if (in_vowel and vowel_groups >= 2) {
                return i;
            }
            in_vowel = false;
        }
    }
    // If we ended in the 2nd+ vowel group, return word length
    if (vowel_groups >= 2) return word.len;
    return word.len;
}
```

Update `generateConstruct` switch: `.backform => self.generateBackform(category, input_words)`.

- [ ] **Step 16: Run tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 17: Write failing test for phonosym**

```zig
test "phonosym sharp produces hard consonants" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.phonosym, null, &.{"sharp"});
    try std.testing.expect(name.value.len >= 4 and name.value.len <= 8);
    try std.testing.expectEqualStrings("construct:phonosym", name.strategy_tag);
    // Verify only sharp consonants and vowels
    for (name.value) |c| {
        if (!isVowel(c)) {
            // Must be a sharp consonant character (individual char from the set)
            const valid = c == 'k' or c == 't' or c == 'p' or c == 'x' or c == 'z' or
                c == 'c' or c == 'r' or c == 's';
            try std.testing.expect(valid);
        }
    }
}

test "phonosym soft produces soft consonants" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.phonosym, null, &.{"soft"});
    try std.testing.expect(name.value.len >= 4 and name.value.len <= 8);
    for (name.value) |c| {
        if (!isVowel(c)) {
            const valid = c == 'm' or c == 'l' or c == 'n' or c == 's' or c == 'w' or
                c == 'f';
            try std.testing.expect(valid);
        }
    }
}

test "phonosym invalid mood returns error" {
    var eng = ConstructEngine.init(42);
    const result = eng.generateConstruct(.phonosym, null, &.{"loud"});
    try std.testing.expectError(error.InvalidInput, result);
}
```

- [ ] **Step 18: Implement phonosym**

```zig
const Mood = enum { sharp, soft, rhythmic };

fn parseMood(input: []const u8) ?Mood {
    if (std.mem.eql(u8, input, "sharp")) return .sharp;
    if (std.mem.eql(u8, input, "soft")) return .soft;
    if (std.mem.eql(u8, input, "rhythmic")) return .rhythmic;
    return null;
}

fn getMoodConsonants(mood: Mood) []const []const u8 {
    return switch (mood) {
        .sharp => constructdata.sharp_consonants,
        .soft => constructdata.soft_consonants,
        .rhythmic => constructdata.rhythmic_consonants,
    };
}

fn getMoodVowels(mood: Mood) []const []const u8 {
    return switch (mood) {
        .sharp => constructdata.sharp_vowels,
        .soft => constructdata.soft_vowels,
        .rhythmic => constructdata.rhythmic_vowels,
    };
}

// Template patterns by target character count (index = target_len - 4)
// true = consonant, false = vowel
const templates = [_][]const bool{
    &.{ true, false, true, false }, // 4: CVCV
    &.{ true, false, true, true, false }, // 5: CVCCV
    &.{ true, false, true, false, true, false }, // 6: CVCVCV
    &.{ true, false, true, true, false, true, false }, // 7: CVCCVCV
    &.{ true, false, true, false, true, false, true, false }, // 8: CVCVCVCV
};

fn generatePhonosym(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) (GenerateError || types.ParseError)!Name {
    _ = category;
    const rand = self.prng.random();

    const mood: Mood = if (input_words.len >= 1)
        parseMood(input_words[0]) orelse return error.InvalidInput
    else
        @enumFromInt(rand.intRangeLessThan(u2, 0, 3));

    const consonants = getMoodConsonants(mood);
    const vowels = getMoodVowels(mood);
    if (consonants.len == 0 or vowels.len == 0) return error.ConstructionFailed;

    // Pick a random template (4-8 chars)
    const template_idx = rand.intRangeLessThan(usize, 0, templates.len);
    const template = templates[template_idx];

    var pos: usize = 0;
    for (template) |is_consonant| {
        const phoneme = if (is_consonant)
            consonants[rand.intRangeLessThan(usize, 0, consonants.len)]
        else
            vowels[rand.intRangeLessThan(usize, 0, vowels.len)];

        if (pos + phoneme.len > self.buf.len) return error.ConstructionFailed;
        @memcpy(self.buf[pos .. pos + phoneme.len], phoneme);
        pos += phoneme.len;
    }

    if (pos == 0) return error.ConstructionFailed;
    return .{ .value = self.buf[0..pos], .category = null, .strategy_tag = "construct:phonosym" };
}
```

Update `generateConstruct` switch: `.phonosym => self.generatePhonosym(category, input_words)`.

- [ ] **Step 19: Run tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 20: Write failing test for acronym**

```zig
test "acronym pronounceable as-is" {
    var eng = ConstructEngine.init(42);
    // s,p,a → "spa" — has vowel, no 3+ consonant cluster → as-is
    const name = try eng.generateConstruct(.acronym, null, &.{ "spell", "practice", "app" });
    try std.testing.expectEqualStrings("spa", name.value);
    try std.testing.expectEqualStrings("construct:acronym", name.strategy_tag);
}

test "acronym inserts vowels for consonant clusters of 3+" {
    var eng = ConstructEngine.init(42);
    // b,c,d,f → "bcdf" → 4 consecutive consonants (cluster of 3+)
    // Insert vowel after 2nd consonant: "bc[v]df" = 5 chars (e.g., "bcadf")
    const name = try eng.generateConstruct(.acronym, null, &.{ "bold", "calm", "deep", "frost" });
    const value = name.value;
    // Should be 5 chars: 4 original + 1 inserted vowel
    try std.testing.expectEqual(@as(usize, 5), value.len);
    // Should start with 'b'
    try std.testing.expectEqual(@as(u8, 'b'), value[0]);
    try std.testing.expectEqual(@as(u8, 'c'), value[1]);
    // Third char should be an inserted vowel
    try std.testing.expect(isVowel(value[2]));
    try std.testing.expectEqual(@as(u8, 'd'), value[3]);
    try std.testing.expectEqual(@as(u8, 'f'), value[4]);
}
```

- [ ] **Step 21: Implement acronym**

```zig
fn generateAcronym(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
    const rand = self.prng.random();

    // Resolve words: use input or pick from built-in lists
    var picked_buf: [5][]const u8 = undefined;
    var word_count: usize = 0;

    if (input_words.len >= 2) {
        word_count = @min(input_words.len, 5);
        for (input_words[0..word_count], 0..) |w, i| {
            picked_buf[i] = w;
        }
    } else {
        // Exploratory: pick 3-5 words
        const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
        if (list.len == 0) return error.EmptyWordList;
        word_count = rand.intRangeAtMost(usize, 3, @min(5, list.len));
        for (0..word_count) |i| {
            picked_buf[i] = list[rand.intRangeLessThan(usize, 0, list.len)];
        }
    }

    if (word_count == 0) return error.ConstructionFailed;

    // Extract first letters
    var letters: [5]u8 = undefined;
    for (picked_buf[0..word_count], 0..) |w, i| {
        if (w.len == 0) return error.ConstructionFailed;
        letters[i] = w[0];
    }

    // Check if pronounceable as-is
    const raw = letters[0..word_count];
    if (isPronounceable(raw)) {
        @memcpy(self.buf[0..word_count], raw);
        return .{ .value = self.buf[0..word_count], .category = category, .strategy_tag = "construct:acronym" };
    }

    // Two-pass: first identify clusters of 3+ consecutive consonants in raw,
    // then emit characters, inserting a vowel after the 2nd consonant in each such cluster.
    const vowel_options = [_]u8{ 'a', 'e', 'i', 'o', 'u' };
    var pos: usize = 0;
    var consonant_run: usize = 0;

    // Pre-scan to find cluster starts: count consecutive consonants from each position
    // We need to know if the current consonant is part of a 3+ cluster
    var cluster_lengths: [5]usize = .{ 0, 0, 0, 0, 0 };
    var scan_run: usize = 0;
    var scan_start: usize = 0;
    for (raw, 0..) |c, idx| {
        if (!isVowel(c)) {
            if (scan_run == 0) scan_start = idx;
            scan_run += 1;
        } else {
            if (scan_run >= 3) {
                // Mark all positions in this cluster with the cluster length
                var k = scan_start;
                while (k < scan_start + scan_run and k < 5) : (k += 1) {
                    cluster_lengths[k] = scan_run;
                }
            }
            scan_run = 0;
        }
    }
    // Handle trailing cluster
    if (scan_run >= 3) {
        var k = scan_start;
        while (k < scan_start + scan_run and k < 5) : (k += 1) {
            cluster_lengths[k] = scan_run;
        }
    }

    // Emit with vowel insertion after 2nd consonant in 3+ clusters
    consonant_run = 0;
    for (raw, 0..) |c, idx| {
        if (pos >= self.buf.len) return error.ConstructionFailed;
        self.buf[pos] = c;
        pos += 1;

        if (isVowel(c)) {
            consonant_run = 0;
        } else {
            consonant_run += 1;
            // Insert vowel after 2nd consonant only if this is part of a 3+ cluster
            if (consonant_run == 2 and idx < 5 and cluster_lengths[idx] >= 3) {
                if (pos >= self.buf.len) return error.ConstructionFailed;
                self.buf[pos] = vowel_options[rand.intRangeLessThan(usize, 0, vowel_options.len)];
                pos += 1;
                consonant_run = 0;
            }
        }
    }

    if (pos == 0) return error.ConstructionFailed;
    return .{ .value = self.buf[0..pos], .category = category, .strategy_tag = "construct:acronym" };
}

fn isPronounceable(s: []const u8) bool {
    var has_vowel = false;
    var consonant_run: usize = 0;
    for (s) |c| {
        if (isVowel(c)) {
            has_vowel = true;
            consonant_run = 0;
        } else {
            consonant_run += 1;
            if (consonant_run > 2) return false;
        }
    }
    return has_vowel;
}
```

Update `generateConstruct` switch: `.acronym => self.generateAcronym(category, input_words)`.

- [ ] **Step 22: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 23: Write determinism test for all techniques**

```zig
test "all construct techniques are deterministic with seed" {
    const techniques = comptime std.enums.values(ConstructTechnique);
    inline for (techniques) |tech| {
        if (tech == .phonosym) {
            var eng1 = ConstructEngine.init(42);
            var eng2 = ConstructEngine.init(42);
            const n1 = try eng1.generateConstruct(tech, null, &.{"sharp"});
            var saved: [42]u8 = undefined;
            @memcpy(saved[0..n1.value.len], n1.value);
            const n2 = try eng2.generateConstruct(tech, null, &.{"sharp"});
            try std.testing.expectEqualStrings(saved[0..n1.value.len], n2.value);
        } else if (tech == .acronym) {
            var eng1 = ConstructEngine.init(42);
            var eng2 = ConstructEngine.init(42);
            const n1 = try eng1.generateConstruct(tech, null, &.{ "alpha", "beta", "gamma" });
            var saved: [42]u8 = undefined;
            @memcpy(saved[0..n1.value.len], n1.value);
            const n2 = try eng2.generateConstruct(tech, null, &.{ "alpha", "beta", "gamma" });
            try std.testing.expectEqualStrings(saved[0..n1.value.len], n2.value);
        } else {
            var eng1 = ConstructEngine.init(42);
            var eng2 = ConstructEngine.init(42);
            const n1 = try eng1.generateConstruct(tech, null, &.{ "test", "word" });
            var saved: [42]u8 = undefined;
            @memcpy(saved[0..n1.value.len], n1.value);
            const n2 = try eng2.generateConstruct(tech, null, &.{ "test", "word" });
            try std.testing.expectEqualStrings(saved[0..n1.value.len], n2.value);
        }
    }
}
```

- [ ] **Step 24: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 25: Write failing test for batch generation with dedup**

```zig
test "construct batch produces distinct names" {
    const allocator = std.testing.allocator;
    var eng = ConstructEngine.init(42);
    const batch = try eng.generateConstructBatch(allocator, 3, .affix, .mountains, &.{});
    defer batch.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), batch.names.len);

    // Verify all names are distinct
    for (batch.names, 0..) |name, i| {
        for (batch.names[0..i]) |other| {
            try std.testing.expect(!std.mem.eql(u8, name.value, other.value));
        }
    }
}
```

- [ ] **Step 26: Implement generateConstructBatch**

Add to `ConstructEngine`:

```zig
const generator_mod = @import("generator.zig");

pub fn generateConstructBatch(
    self: *ConstructEngine,
    allocator: std.mem.Allocator,
    count: u32,
    technique: ConstructTechnique,
    category: ?Category,
    input_words: []const []const u8,
) !ConstructBatchResult {
    const names = try allocator.alloc(Name, count);
    errdefer allocator.free(names);
    const values = try allocator.alloc([42]u8, count);
    errdefer allocator.free(values);

    var syllables = try allocator.alloc([8]u8, count);
    defer allocator.free(syllables);
    var syllable_lens = try allocator.alloc(u8, count);
    defer allocator.free(syllable_lens);

    var i: u32 = 0;
    var attempts: u32 = 0;
    const max_attempts = count * 20;

    while (i < count and attempts < max_attempts) : (attempts += 1) {
        // For batch variation (REQ-CON-027): on iterations after the first,
        // replace word2 with a built-in word for two-word techniques,
        // or draw a new base word for single-word techniques.
        var varied_words_buf: [5][]const u8 = undefined;
        var varied_words: []const []const u8 = input_words;
        if (i > 0 and input_words.len >= 2) {
            // Replace word2 with a random built-in word
            const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
            if (list.len > 0) {
                const rand = self.prng.random();
                varied_words_buf[0] = input_words[0];
                varied_words_buf[1] = list[rand.intRangeLessThan(usize, 0, list.len)];
                varied_words = varied_words_buf[0..2];
            }
        }

        const name = self.generateConstruct(technique, category, varied_words) catch continue;

        // First-syllable phonetic dedup (REQ-CON-029)
        const new_syl = generator_mod.firstSyllable(name.value);
        var distinct = true;
        for (0..i) |j| {
            const existing_syl = syllables[j][0..syllable_lens[j]];
            if (std.mem.eql(u8, new_syl, existing_syl)) {
                distinct = false;
                break;
            }
        }

        if (distinct) {
            @memcpy(values[i][0..name.value.len], name.value);
            names[i] = .{
                .value = values[i][0..name.value.len],
                .category = name.category,
                .strategy_tag = name.strategy_tag,
            };
            const syl_len: u8 = @intCast(new_syl.len);
            @memcpy(syllables[i][0..syl_len], new_syl);
            syllable_lens[i] = syl_len;
            i += 1;
        }
    }

    if (i < count) return error.NoDistinctNames;
    return .{ .names = names, .values = values };
}
```

And add the result type:

```zig
pub const ConstructBatchResult = struct {
    names: []Name,
    values: [][42]u8,

    pub fn deinit(self: ConstructBatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.names);
    }
};
```

- [ ] **Step 27: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 28: Register construct.zig in root.zig**

Add to `src/root.zig`:

```zig
pub const construct = @import("construct.zig");
pub const ConstructEngine = construct.ConstructEngine;
pub const ConstructBatchResult = construct.ConstructBatchResult;
```

- [ ] **Step 26: Run full test suite**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 27: Commit**

```bash
git add src/construct.zig src/root.zig
git commit -m "feat: implement all 7 construct algorithms with tests"
```

---

### Task 5: CLI Integration — Input Dispatch and Help

**Files:**
- Modify: `src/main.zig`
- Modify: `src/cli.zig`

- [ ] **Step 1: Write integration test — construct via CLI args**

In `src/cli.zig`, add:

```zig
test "parse construct strategy" {
    const args = [_][]const u8{ "generate", "--strategy", "construct:portmanteau", "--input", "spell,master" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| {
            try std.testing.expect(opts.strategy == .construct);
            try std.testing.expectEqualStrings("spell,master", opts.input.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parse bare construct strategy" {
    const args = [_][]const u8{ "generate", "--strategy", "construct" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| {
            try std.testing.expect(opts.strategy == .construct);
            try std.testing.expectEqual(types.ConstructTechnique.portmanteau, opts.strategy.construct);
        },
        else => try std.testing.expect(false),
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

These should pass since `Strategy.fromString` already handles `construct:*`. Run: `zig build test 2>&1 | tail -5`

- [ ] **Step 3: Update main.zig input validation dispatch**

Replace the input validation block in `main.zig` (lines 97-127) with strategy-aware dispatch:

```zig
var strategy = opts.strategy;
if (opts.input) |input| {
    if (strategy == .mnemonic) {
        lib.types.validateMnemonicInput(input) catch {
            const format = opts.format orelse lib.cli.resolveFormat(null);
            try lib.format.formatError(stderr, .{
                .code = "INVALID_INPUT",
                .message = "mnemonic input must be numeric or hex (e.g. 12345, 0xdeadbeef)",
            }, format);
            try stderr.flush();
            std.process.exit(2);
        };
        strategy = .{ .mnemonic = input };
    } else if (strategy == .construct) {
        lib.types.validateConstructInput(input) catch {
            const format = opts.format orelse lib.cli.resolveFormat(null);
            try lib.format.formatError(stderr, .{
                .code = "INVALID_INPUT",
                .message = "construct input must be comma-separated lowercase words (max 5, each <= 20 chars)",
            }, format);
            try stderr.flush();
            std.process.exit(2);
        };
    } else {
        const format = opts.format orelse lib.cli.resolveFormat(null);
        try lib.format.formatError(stderr, .{
            .code = "INVALID_INPUT",
            .message = "--input is only valid with --strategy mnemonic or --strategy construct:*",
        }, format);
        try stderr.flush();
        std.process.exit(2);
    }
} else if (strategy == .mnemonic) {
    const format = opts.format orelse lib.cli.resolveFormat(null);
    try lib.format.formatError(stderr, .{
        .code = "MISSING_VALUE",
        .message = "--strategy mnemonic requires --input <numeric/hex>",
    }, format);
    try stderr.flush();
    std.process.exit(2);
}
```

- [ ] **Step 4: Update main.zig generation dispatch**

Replace the generation block (lines 129-140) to handle construct strategies:

```zig
var gen = lib.Generator.init(opts.seed);
const format = opts.format orelse lib.cli.resolveFormat(null);

if (strategy == .construct) {
    // Parse input words for construct
    var input_words_buf: [5][]const u8 = undefined;
    var input_word_count: usize = 0;
    if (opts.input) |input| {
        var iter = std.mem.splitScalar(u8, input, ',');
        while (iter.next()) |word| {
            if (input_word_count >= 5) break;
            input_words_buf[input_word_count] = word;
            input_word_count += 1;
        }
    }
    const input_words = input_words_buf[0..input_word_count];

    var construct_eng = lib.ConstructEngine.init(opts.seed);

    if (opts.count == 1) {
        const name = try construct_eng.generateConstruct(strategy.construct, opts.category, input_words);
        const names = [_]lib.Name{name};
        try lib.format.formatNames(stdout, &names, format, opts.fields);
    } else {
        const batch = try construct_eng.generateConstructBatch(
            gpa, opts.count, strategy.construct, opts.category, input_words,
        );
        defer batch.deinit(gpa);
        try lib.format.formatNames(stdout, batch.names, format, opts.fields);
    }
} else if (opts.count == 1) {
    const name = try gen.generate(strategy, opts.category);
    const names = [_]lib.Name{name};
    try lib.format.formatNames(stdout, &names, format, opts.fields);
} else {
    const batch = try gen.generateBatch(gpa, opts.count, strategy, opts.category);
    defer batch.deinit(gpa);
    try lib.format.formatNames(stdout, batch.names, format, opts.fields);
}
```

- [ ] **Step 5: Update error messages for InvalidStrategy**

In `main.zig` `errorToMessage`, update the `InvalidStrategy` arm:

```zig
error.InvalidStrategy => "invalid strategy, options: thematic, phrase, phrase:adjective_noun, phrase:noun_noun, phrase:verb_noun, phrase:alliterative, triple, mnemonic, construct, construct:portmanteau, construct:compound, construct:clip, construct:affix, construct:backform, construct:phonosym, construct:acronym",
```

Also add `ConstructionFailed` to `runtimeErrorToCode` and `runtimeErrorToMessage`:

```zig
error.ConstructionFailed => "CONSTRUCTION_FAILED",
// ...
error.ConstructionFailed => "construction algorithm produced no valid output",
```

- [ ] **Step 6: Update help text in cli.zig**

Update `writeGenerateHelp` to list construct strategies in the strategy enum and update input description. In the JSON help, update the `--strategy` enum array to include construct variants. Update `--input` description to: `"Input for mnemonic or construct strategies"`.

In the human help, update the strategy line:
```
\\  --strategy, -s <NAME>   Strategy: thematic, phrase[:pattern], triple, mnemonic, construct[:technique] (default: thematic)
\\  --input, -i <TEXT>      Input for mnemonic (numeric/hex) or construct (comma-separated words)
```

- [ ] **Step 7: Update LLMs manifest in cli.zig**

In `writeLlmsManifest`, add construct strategies to the `--strategy` enum array and add construct examples:

```json
{"command": "nomen generate --strategy construct:portmanteau --input spell,master", "description": "Blend two words into a portmanteau"},
{"command": "nomen generate --strategy construct:compound --input storm,forge", "description": "Concatenate words into compound"},
{"command": "nomen generate --strategy construct:phonosym --input sharp --count 5", "description": "Generate sharp-sounding constructed words"},
{"command": "nomen generate --strategy construct:affix --input quill", "description": "Add prefix or suffix to a word"},
{"command": "nomen generate --strategy construct:acronym --input spell,practice,app", "description": "Create pronounceable acronym"}
```

Also update `--input` description to: `"Input for mnemonic encoding or construct seed words"`.

- [ ] **Step 8: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 9: Run a manual smoke test**

Run: `zig build run -- generate --strategy construct:compound --input "storm,forge" -f human 2>&1`
Expected: `stormforge`

Run: `zig build run -- generate --strategy construct:portmanteau --input "spell,master" -f human 2>&1`
Expected: a blended word.

Run: `zig build run -- generate --strategy construct:phonosym --input "sharp" --count 3 --seed 42 -f human 2>&1`
Expected: 3 sharp-sounding words.

- [ ] **Step 10: Commit**

```bash
git add src/main.zig src/cli.zig
git commit -m "feat: wire construct strategies through CLI with input validation and help"
```

---

### Task 6: Server Integration

**Files:**
- Modify: `src/server.zig`

- [ ] **Step 1: Write failing test for server query param parsing with construct**

In `src/server.zig`, add:

```zig
test "parseQueryParams construct strategy" {
    const params = parseQueryParams("/generate?strategy=construct:portmanteau&input=spell,master");
    try std.testing.expect(params.err_code == null);
    try std.testing.expect(params.strategy == .construct);
}

test "parseQueryParams construct invalid technique" {
    const params = parseQueryParams("/generate?strategy=construct:bogus");
    try std.testing.expect(params.err_code != null);
    try std.testing.expectEqualStrings("INVALID_STRATEGY", params.err_code.?);
}
```

- [ ] **Step 2: Run test — expect failure**

The first test will fail because the server currently validates `input` as mnemonic-only. Run: `zig build test 2>&1 | head -20`

- [ ] **Step 3: Update server parseQueryParams for strategy-aware input**

Replace the `input` and cross-validation blocks in `parseQueryParams` (lines 150-181):

```zig
} else if (std.mem.eql(u8, key, "input")) {
    mnemonic_input = val;  // Don't validate yet — defer to cross-validation
}
```

Update cross-validation:

```zig
// Cross-validate input and strategy
if (mnemonic_input) |input| {
    if (result.strategy == .mnemonic or (!explicit_strategy and mnemonic_input != null)) {
        // Mnemonic validation
        types.validateMnemonicInput(input) catch {
            result.err_code = "INVALID_INPUT";
            result.err_msg = "mnemonic input must be numeric or hex (e.g. 12345, 0xdeadbeef)";
            return result;
        };
        result.strategy = .{ .mnemonic = input };
    } else if (result.strategy == .construct) {
        // Construct validation
        types.validateConstructInput(input) catch {
            result.err_code = "INVALID_INPUT";
            result.err_msg = "construct input must be comma-separated lowercase words (max 5, each <= 20 chars)";
            return result;
        };
        result.construct_input = input;
    } else {
        result.err_code = "INVALID_INPUT";
        result.err_msg = "input parameter is only valid with strategy=mnemonic or strategy=construct:*";
        return result;
    }
} else if (result.strategy == .mnemonic) {
    result.err_code = "MISSING_VALUE";
    result.err_msg = "strategy=mnemonic requires input parameter";
    return result;
}
```

Add `construct_input` field to `QueryParams`:

```zig
construct_input: ?[]const u8 = null,
```

- [ ] **Step 4: Update handleGenerate for construct dispatch**

In `handleGenerate`, add construct dispatch before the existing generation code:

```zig
if (params.strategy == .construct) {
    var input_words_buf: [5][]const u8 = undefined;
    var input_word_count: usize = 0;
    if (params.construct_input) |input| {
        var iter = std.mem.splitScalar(u8, input, ',');
        while (iter.next()) |word| {
            if (input_word_count >= 5) break;
            input_words_buf[input_word_count] = word;
            input_word_count += 1;
        }
    }

    var construct_eng = @import("construct.zig").ConstructEngine.init(params.seed);

    if (params.count == 1) {
        const name = construct_eng.generateConstruct(params.strategy.construct, params.category, input_words_buf[0..input_word_count]) catch |err| {
            return respondGenerateError(request, err);
        };
        var body_buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&body_buf);
        const names = [_]Name{name};
        try format_mod.formatNames(fbs.writer(), &names, .json, params.fields);
        try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
    } else {
        const batch = construct_eng.generateConstructBatch(allocator, params.count, params.strategy.construct, params.category, input_words_buf[0..input_word_count]) catch |err| {
            return respondGenerateError(request, err);
        };
        defer batch.deinit(allocator);
        var body_buf: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&body_buf);
        try format_mod.formatNames(fbs.writer(), batch.names, .json, params.fields);
        try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
    }
    return;
}
```

Also update `respondGenerateError` to handle `ConstructionFailed`:

```zig
error.ConstructionFailed => "CONSTRUCTION_FAILED",
// ...
error.ConstructionFailed => "construction algorithm produced no valid output",
```

Update the strategy error message in `parseQueryParams`:

```zig
result.err_msg = "invalid strategy, options: thematic, phrase, phrase:adjective_noun, phrase:noun_noun, phrase:verb_noun, phrase:alliterative, triple, mnemonic, construct, construct:portmanteau, construct:compound, construct:clip, construct:affix, construct:backform, construct:phonosym, construct:acronym";
```

- [ ] **Step 5: Run all tests**

Run: `zig build test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/server.zig
git commit -m "feat: wire construct strategies through HTTP API with input validation"
```

---

### Task 7: CLAUDE.md and Docs Update

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add construct strategies to the Generation Strategies section:

```markdown
## Generation Strategies

- **thematic** — single word from a category word list
- **phrase** — two-word combination: adjective-noun, noun-noun, verb-noun, alliterative
- **triple** — three-word combination
- **mnemonic** — deterministic word pair from numeric/hex input
- **construct** — word-construction techniques:
  - `construct:portmanteau` — blend two words at overlap point (spell+master → spellegant)
  - `construct:compound` — concatenate two words (storm+forge → stormforge)
  - `construct:clip` — first syllable + last syllable (spell+champion → spellon)
  - `construct:affix` — add prefix/suffix (quill → neoquill)
  - `construct:backform` — strip suffix to root (constellation → constella)
  - `construct:phonosym` — construct word from mood-tagged phonemes (sharp/soft/rhythmic)
  - `construct:acronym` — pronounceable acronym from word initials
```

Update the Project Layout to include new files:

```
  construct.zig    # Word-construction algorithms (portmanteau, compound, etc.)
  constructdata.zig # Comptime parsing of affix and phoneme data
```

Update the Architecture section to mention construct strategies.

- [ ] **Step 2: Run all checks**

Run: `zig build test && zig build fmt 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with construct strategies and new files"
```

---

### Task 8: End-to-End Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `zig build test 2>&1`
Expected: all tests pass.

- [ ] **Step 2: Run format check**

Run: `zig build fmt 2>&1`
Expected: no formatting issues.

- [ ] **Step 3: Run smoke tests for all construct techniques**

```bash
zig build run -- generate --strategy construct:portmanteau --input "spell,master" -f human
zig build run -- generate --strategy construct:compound --input "storm,forge" -f human
zig build run -- generate --strategy construct:clip --input "spell,champion" -f human
zig build run -- generate --strategy construct:affix --input "quill" --seed 42 -f human
zig build run -- generate --strategy construct:backform --input "constellation" -f human
zig build run -- generate --strategy construct:phonosym --input "sharp" --seed 42 -f human
zig build run -- generate --strategy construct:phonosym --input "soft" --seed 42 -f human
zig build run -- generate --strategy construct:acronym --input "spell,practice,app" -f human
```

- [ ] **Step 4: Test JSON output**

Run: `zig build run -- generate --strategy construct:portmanteau --input "spell,master" -f json`
Expected: valid JSON with `strategy_tag: "construct:portmanteau"`.

- [ ] **Step 5: Test bare construct defaults to portmanteau**

Run: `zig build run -- generate --strategy construct --input "spell,master" -f json`
Expected: `strategy_tag` is `"construct:portmanteau"`.

- [ ] **Step 6: Test exploratory mode (no --input)**

Run: `zig build run -- generate --strategy construct:compound --category raptors --seed 42 -f human`
Expected: a compound word from raptor vocabulary.

- [ ] **Step 7: Test error cases**

Run: `zig build run -- generate --strategy construct:phonosym --input "loud" 2>&1`
Expected: error message about invalid input.

Run: `zig build run -- generate --strategy construct:bogus 2>&1`
Expected: error listing valid strategies.

- [ ] **Step 8: Test existing strategies unchanged**

Run: `zig build run -- generate --strategy thematic --category mountains --seed 42 -f human`
Run: `zig build run -- generate --strategy phrase:alliterative --count 3 --seed 42 -f human`
Run: `zig build run -- generate --strategy mnemonic --input 0xdeadbeef -f human`
Expected: same output as before the changes.

- [ ] **Step 9: Verify --help and --llms**

Run: `zig build run -- generate --help`
Expected: lists construct strategies.

Run: `zig build run -- --llms 2>&1 | head -30`
Expected: construct examples in manifest.
