const std = @import("std");
const types = @import("types.zig");
const worddata = @import("worddata.zig");
const Tone = worddata.Tone;
const Category = types.Category;
const Strategy = types.Strategy;
const PhrasePattern = types.PhrasePattern;
const Name = types.Name;
const GenerateError = types.GenerateError;

/// FNV-1a 64-bit hash — better distribution than multiply-add for mnemonic encoding.
fn fnv1a(input: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (input) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

pub const Generator = struct {
    prng: std.Random.DefaultPrng,
    // 38 bytes = max triple-word (12+1+12+1+12) or 3-word mnemonic
    buf: [38]u8 = undefined,

    pub fn init(seed: ?u64) Generator {
        const actual_seed = seed orelse blk: {
            var s: [8]u8 = undefined;
            std.posix.getrandom(&s) catch {
                break :blk @as(u64, 0);
            };
            break :blk std.mem.readInt(u64, &s, .little);
        };
        return .{
            .prng = std.Random.DefaultPrng.init(actual_seed),
        };
    }

    pub fn generate(self: *Generator, strategy: Strategy, category: ?Category) GenerateError!Name {
        return switch (strategy) {
            .thematic => self.generateThematic(category orelse self.randomCategory()),
            .phrase => |pattern| self.generatePhrase(pattern),
            .triple => self.generateTriple(),
            .mnemonic => |input| self.generateMnemonic(input),
        };
    }

    fn randomCategory(self: *Generator) Category {
        const categories = comptime std.enums.values(Category);
        const rand = self.prng.random();
        return categories[rand.intRangeLessThan(usize, 0, categories.len)];
    }

    fn generateThematic(self: *Generator, category: Category) GenerateError!Name {
        const list = worddata.getWordList(category);
        if (list.len == 0) return error.EmptyWordList;
        const rand = self.prng.random();
        const idx = rand.intRangeLessThan(usize, 0, list.len);
        return .{
            .value = list[idx],
            .category = category,
            .strategy_tag = "thematic",
        };
    }

    fn generatePhrase(self: *Generator, pattern: PhrasePattern) GenerateError!Name {
        const first_list: []const []const u8 = switch (pattern) {
            .adjective_noun, .alliterative => worddata.adjectives,
            .noun_noun => worddata.nouns,
            .verb_noun => worddata.verbs,
        };
        const second_list: []const []const u8 = worddata.nouns;

        if (first_list.len == 0 or second_list.len == 0) return error.EmptyWordList;

        const rand = self.prng.random();

        // For alliterative: retry until both words share the same first letter
        const max_attempts: usize = if (pattern == .alliterative) 50 else 10;
        var attempts: usize = 0;

        while (attempts < max_attempts) : (attempts += 1) {
            const first_idx = rand.intRangeLessThan(usize, 0, first_list.len);
            const second_idx = rand.intRangeLessThan(usize, 0, second_list.len);

            const first = first_list[first_idx];
            const second = second_list[second_idx];

            // Alliteration check
            if (pattern == .alliterative and first[0] != second[0]) continue;

            // Tonal coherence: skip incompatible tone pairings
            const tone1 = worddata.getTone(first);
            const tone2 = worddata.getTone(second);
            if (!Tone.compatible(tone1, tone2) and attempts < max_attempts - 1) continue;

            // Syllable rhythm: prefer 3-5 total syllables (soft preference)
            if (attempts < max_attempts / 2) {
                const syl = worddata.getSyllables(first) + worddata.getSyllables(second);
                if (syl < 3 or syl > 5) continue;
            }

            const len = first.len + 1 + second.len;
            if (len > self.buf.len) continue;

            @memcpy(self.buf[0..first.len], first);
            self.buf[first.len] = '-';
            @memcpy(self.buf[first.len + 1 .. len], second);

            return .{
                .value = self.buf[0..len],
                .category = null,
                .strategy_tag = "phrase",
            };
        }

        // Fallback: just pick any pair
        const first = first_list[rand.intRangeLessThan(usize, 0, first_list.len)];
        const second = second_list[rand.intRangeLessThan(usize, 0, second_list.len)];
        const len = first.len + 1 + second.len;
        if (len > self.buf.len) return error.EmptyWordList;

        @memcpy(self.buf[0..first.len], first);
        self.buf[first.len] = '-';
        @memcpy(self.buf[first.len + 1 .. len], second);

        return .{
            .value = self.buf[0..len],
            .category = null,
            .strategy_tag = "phrase",
        };
    }

    fn generateTriple(self: *Generator) GenerateError!Name {
        if (worddata.adjectives.len == 0 or worddata.nouns.len == 0) return error.EmptyWordList;

        const rand = self.prng.random();

        // Randomly choose: adjective-adjective-noun or adjective-noun-noun
        const use_adj_adj_noun = rand.boolean();

        const w1 = worddata.adjectives[rand.intRangeLessThan(usize, 0, worddata.adjectives.len)];
        const w2 = if (use_adj_adj_noun)
            worddata.adjectives[rand.intRangeLessThan(usize, 0, worddata.adjectives.len)]
        else
            worddata.nouns[rand.intRangeLessThan(usize, 0, worddata.nouns.len)];
        const w3 = worddata.nouns[rand.intRangeLessThan(usize, 0, worddata.nouns.len)];

        const adj1 = w1;
        const adj2 = w2;
        const noun = w3;

        const len = adj1.len + 1 + adj2.len + 1 + noun.len;
        if (len > self.buf.len) return error.EmptyWordList;

        var pos: usize = 0;
        @memcpy(self.buf[pos .. pos + adj1.len], adj1);
        pos += adj1.len;
        self.buf[pos] = '-';
        pos += 1;
        @memcpy(self.buf[pos .. pos + adj2.len], adj2);
        pos += adj2.len;
        self.buf[pos] = '-';
        pos += 1;
        @memcpy(self.buf[pos .. pos + noun.len], noun);
        pos += noun.len;

        return .{
            .value = self.buf[0..pos],
            .category = null,
            .strategy_tag = "triple",
        };
    }

    fn generateMnemonic(self: *Generator, input: []const u8) GenerateError!Name {
        if (input.len == 0) return error.EmptyWordList;

        const hash = fnv1a(input);
        const wlen = worddata.mnemonic_all.len;

        // Strip 0x prefix for length check
        const effective_len = if (input.len > 2 and input[0] == '0' and
            (input[1] == 'x' or input[1] == 'X'))
            input.len - 2
        else
            input.len;

        // Long inputs (>8 hex chars) get 3 words for higher entropy.
        // Derive all three indices from the same 64-bit FNV-1a hash:
        // low bits -> word 1, mid bits -> word 2, high bits -> word 3
        if (effective_len > 8) {
            const idx1 = hash % wlen;
            const idx2 = (hash / wlen) % wlen;
            const idx3 = (hash / wlen / wlen) % wlen;

            const w1 = worddata.mnemonic_all[idx1];
            const w2 = worddata.mnemonic_all[idx2];
            const w3 = worddata.mnemonic_all[idx3];

            const len = w1.len + 1 + w2.len + 1 + w3.len;
            if (len > self.buf.len) return error.EmptyWordList;

            var pos: usize = 0;
            @memcpy(self.buf[pos .. pos + w1.len], w1);
            pos += w1.len;
            self.buf[pos] = '-';
            pos += 1;
            @memcpy(self.buf[pos .. pos + w2.len], w2);
            pos += w2.len;
            self.buf[pos] = '-';
            pos += 1;
            @memcpy(self.buf[pos .. pos + w3.len], w3);
            pos += w3.len;

            return .{
                .value = self.buf[0..pos],
                .category = null,
                .strategy_tag = "mnemonic",
            };
        }

        // Short inputs: 2 words
        const first_idx = hash % wlen;
        const second_idx = (hash / wlen) % wlen;

        const w1 = worddata.mnemonic_all[first_idx];
        const w2 = worddata.mnemonic_all[second_idx];

        const len = w1.len + 1 + w2.len;
        if (len > self.buf.len) return error.EmptyWordList;

        @memcpy(self.buf[0..w1.len], w1);
        self.buf[w1.len] = '-';
        @memcpy(self.buf[w1.len + 1 .. len], w2);

        return .{
            .value = self.buf[0..len],
            .category = null,
            .strategy_tag = "mnemonic",
        };
    }

    pub fn generateBatch(
        self: *Generator,
        allocator: std.mem.Allocator,
        count: u32,
        strategy: Strategy,
        category: ?Category,
    ) !BatchResult {
        const names = try allocator.alloc(Name, count);
        errdefer allocator.free(names);

        const values = try allocator.alloc([38]u8, count);
        errdefer allocator.free(values);

        // Store first syllables for existing names
        var syllables = try allocator.alloc([8]u8, count);
        defer allocator.free(syllables);
        var syllable_lens = try allocator.alloc(u8, count);
        defer allocator.free(syllable_lens);

        var i: u32 = 0;
        var attempts: u32 = 0;
        const max_attempts = count * 20;

        while (i < count and attempts < max_attempts) : (attempts += 1) {
            const name = try self.generate(strategy, category);

            const new_syl = firstSyllable(name.value);

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
                names[i] = Name{
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
};

pub const BatchResult = struct {
    names: []Name,
    values: [][38]u8,

    pub fn deinit(self: BatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.names);
    }
};

/// Extract the first syllable of a word for phonetic comparison.
/// Heuristic: consonant onset + first vowel group.
/// For compound names with hyphens, uses only the first word.
pub fn firstSyllable(word: []const u8) []const u8 {
    const w = if (std.mem.indexOf(u8, word, "-")) |hi| word[0..hi] else word;
    if (w.len == 0) return w;

    var seen_vowel = false;
    for (w, 0..) |c, idx| {
        if (isVowelAt(c, idx)) {
            seen_vowel = true;
        } else if (seen_vowel) {
            return w[0..idx];
        }
    }

    return w;
}

fn isVowelAt(c: u8, pos: usize) bool {
    if (c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u') return true;
    if (c == 'y' and pos > 0) return true;
    return false;
}

fn isDnsSafe(s: []const u8) bool {
    if (s.len == 0) return false;
    if (s[0] == '-' or s[s.len - 1] == '-') return false;
    for (s) |c| {
        if (!((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-')) return false;
    }
    return true;
}

// --- Tests ---

test "fnv1a produces consistent hashes" {
    const h1 = fnv1a("test123");
    const h2 = fnv1a("test123");
    try std.testing.expectEqual(h1, h2);
    // Different inputs produce different hashes
    const h3 = fnv1a("test124");
    try std.testing.expect(h1 != h3);
}

test "firstSyllable extracts correctly" {
    try std.testing.expectEqualStrings("de", firstSyllable("denali"));
    try std.testing.expectEqualStrings("dri", firstSyllable("drift"));
    try std.testing.expectEqualStrings("swi", firstSyllable("swift"));
    try std.testing.expectEqualStrings("eu", firstSyllable("europa"));
    try std.testing.expectEqualStrings("o", firstSyllable("odin"));
    try std.testing.expectEqualStrings("bry", firstSyllable("bryce"));
    try std.testing.expectEqualStrings("mo", firstSyllable("mojave"));
    try std.testing.expectEqualStrings("qui", firstSyllable("quick"));
    try std.testing.expectEqualStrings("swi", firstSyllable("swift-stone"));
    try std.testing.expectEqualStrings("bo", firstSyllable("bold-creek"));
}

test "thematic generation produces dns-safe names" {
    var gen = Generator.init(42);
    const name = try gen.generate(.thematic, .mountains);
    try std.testing.expect(isDnsSafe(name.value));
    try std.testing.expectEqualStrings("thematic", name.strategy_tag);
    try std.testing.expectEqual(Category.mountains, name.category.?);
}

test "deterministic with same seed" {
    var gen1 = Generator.init(42);
    var gen2 = Generator.init(42);
    const name1 = try gen1.generate(.thematic, .mountains);
    const name2 = try gen2.generate(.thematic, .mountains);
    try std.testing.expectEqualStrings(name1.value, name2.value);
}

test "phrase generation produces dns-safe names" {
    var gen = Generator.init(42);
    const name = try gen.generate(.{ .phrase = .adjective_noun }, null);
    try std.testing.expect(isDnsSafe(name.value));
    try std.testing.expect(std.mem.indexOf(u8, name.value, "-") != null);
}

test "alliterative phrase shares first letter" {
    var gen = Generator.init(42);
    // Generate several and check at least some are alliterative
    var alliterative_count: usize = 0;
    for (0..20) |_| {
        const name = try gen.generate(.{ .phrase = .alliterative }, null);
        const hyphen = std.mem.indexOf(u8, name.value, "-") orelse continue;
        if (name.value[0] == name.value[hyphen + 1]) alliterative_count += 1;
    }
    // Most should be alliterative (with 26 possible letters and retries)
    try std.testing.expect(alliterative_count >= 10);
}

test "triple generation produces three-word dns-safe names" {
    var gen = Generator.init(42);
    const name = try gen.generate(.triple, null);
    try std.testing.expect(isDnsSafe(name.value));
    try std.testing.expectEqualStrings("triple", name.strategy_tag);
    // Count hyphens — should be exactly 2
    var hyphens: usize = 0;
    for (name.value) |c| {
        if (c == '-') hyphens += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), hyphens);
}

test "mnemonic generation uses FNV-1a and is deterministic" {
    var gen1 = Generator.init(0);
    const name1 = try gen1.generate(.{ .mnemonic = "test123" }, null);
    var val1: [38]u8 = undefined;
    @memcpy(val1[0..name1.value.len], name1.value);
    const saved1 = val1[0..name1.value.len];

    var gen2 = Generator.init(0);
    const name2 = try gen2.generate(.{ .mnemonic = "test123" }, null);
    try std.testing.expectEqualStrings(saved1, name2.value);
}

test "long mnemonic input produces three words" {
    var gen = Generator.init(0);
    const name = try gen.generate(.{ .mnemonic = "0xdeadbeefcafe" }, null);
    // Count hyphens — should be 2 for three words
    var hyphens: usize = 0;
    for (name.value) |c| {
        if (c == '-') hyphens += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), hyphens);
}

test "short mnemonic input produces two words" {
    var gen = Generator.init(0);
    const name = try gen.generate(.{ .mnemonic = "0xdead" }, null);
    var hyphens: usize = 0;
    for (name.value) |c| {
        if (c == '-') hyphens += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), hyphens);
}

test "batch generation with syllable distinctness" {
    const allocator = std.testing.allocator;
    var gen = Generator.init(42);
    const batch = try gen.generateBatch(allocator, 5, .thematic, .mountains);
    defer batch.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), batch.names.len);

    for (batch.names, 0..) |name, i| {
        try std.testing.expect(isDnsSafe(name.value));
        const syl_i = firstSyllable(name.value);
        for (batch.names[0..i]) |other| {
            const syl_j = firstSyllable(other.value);
            try std.testing.expect(!std.mem.eql(u8, syl_i, syl_j));
        }
    }
}

test "all categories produce names" {
    var gen = Generator.init(42);
    const categories = comptime std.enums.values(Category);
    inline for (categories) |cat| {
        const name = try gen.generate(.thematic, cat);
        try std.testing.expect(name.value.len > 0);
        try std.testing.expect(isDnsSafe(name.value));
    }
}

test "phrase batch generation" {
    const allocator = std.testing.allocator;
    var gen = Generator.init(42);
    const batch = try gen.generateBatch(allocator, 5, .{ .phrase = .adjective_noun }, null);
    defer batch.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), batch.names.len);
    for (batch.names) |name| {
        try std.testing.expect(isDnsSafe(name.value));
        try std.testing.expect(std.mem.indexOf(u8, name.value, "-") != null);
    }
}
