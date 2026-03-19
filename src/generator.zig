const std = @import("std");
const types = @import("types.zig");
const worddata = @import("worddata.zig");
const Category = types.Category;
const Strategy = types.Strategy;
const PhrasePattern = types.PhrasePattern;
const Name = types.Name;
const GenerateError = types.GenerateError;

pub const Generator = struct {
    prng: std.Random.DefaultPrng,
    buf: [25]u8 = undefined,

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
        return Name{
            .value = list[idx],
            .category = category,
            .strategy_tag = "thematic",
        };
    }

    fn generatePhrase(self: *Generator, pattern: PhrasePattern) GenerateError!Name {
        const first_list: []const []const u8 = switch (pattern) {
            .adjective_noun => worddata.adjectives,
            .noun_noun => worddata.nouns,
            .verb_noun => worddata.verbs,
        };
        const second_list: []const []const u8 = worddata.nouns;

        if (first_list.len == 0 or second_list.len == 0) return error.EmptyWordList;

        const rand = self.prng.random();
        const first_idx = rand.intRangeLessThan(usize, 0, first_list.len);
        const second_idx = rand.intRangeLessThan(usize, 0, second_list.len);

        const first = first_list[first_idx];
        const second = second_list[second_idx];

        const len = first.len + 1 + second.len;
        if (len > self.buf.len) return error.EmptyWordList;

        @memcpy(self.buf[0..first.len], first);
        self.buf[first.len] = '-';
        @memcpy(self.buf[first.len + 1 .. len], second);

        return Name{
            .value = self.buf[0..len],
            .category = null,
            .strategy_tag = "phrase",
        };
    }

    fn generateMnemonic(self: *Generator, input: []const u8) GenerateError!Name {
        if (input.len == 0) return error.EmptyWordList;

        var hash: u64 = 0;
        for (input) |byte| {
            hash = hash *% 31 +% byte;
        }

        const first_idx = hash % worddata.mnemonic_all.len;
        const second_idx = (hash / worddata.mnemonic_all.len) % worddata.mnemonic_all.len;

        const adj = worddata.mnemonic_all[first_idx];
        const noun = worddata.mnemonic_all[second_idx];

        const len = adj.len + 1 + noun.len;
        if (len > self.buf.len) return error.EmptyWordList;

        @memcpy(self.buf[0..adj.len], adj);
        self.buf[adj.len] = '-';
        @memcpy(self.buf[adj.len + 1 .. len], noun);

        return Name{
            .value = self.buf[0..len],
            .category = null,
            .strategy_tag = "mnemonic",
        };
    }

    pub fn generateBatch(self: *Generator, allocator: std.mem.Allocator, count: u32, strategy: Strategy, category: ?Category) !BatchResult {
        const names = try allocator.alloc(Name, count);
        errdefer allocator.free(names);

        const values = try allocator.alloc([25]u8, count);
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

        return BatchResult{ .names = names, .values = values };
    }
};

pub const BatchResult = struct {
    names: []Name,
    values: [][25]u8,

    pub fn deinit(self: BatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.names);
    }
};

/// Extract the first syllable of a word for phonetic comparison.
/// Heuristic: consonant onset + first vowel group.
/// Examples: "denali" -> "de", "drift" -> "dri", "swift" -> "swi",
///           "europa" -> "eu", "odin" -> "o", "bryce" -> "bry"
/// For compound names with hyphens, uses only the first word.
pub fn firstSyllable(word: []const u8) []const u8 {
    // For phrase names, use only the first component
    const w = if (std.mem.indexOf(u8, word, "-")) |hi| word[0..hi] else word;
    if (w.len == 0) return w;

    var seen_vowel = false;
    for (w, 0..) |c, idx| {
        if (isVowelAt(c, idx)) {
            seen_vowel = true;
        } else if (seen_vowel) {
            // First consonant after a vowel = end of first syllable
            return w[0..idx];
        }
    }

    // Word is all vowels or ends mid-vowel group — return the whole word
    return w;
}

fn isVowelAt(c: u8, pos: usize) bool {
    if (c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u') return true;
    // 'y' is a vowel when not word-initial
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

test "firstSyllable extracts correctly" {
    try std.testing.expectEqualStrings("de", firstSyllable("denali"));
    try std.testing.expectEqualStrings("dri", firstSyllable("drift"));
    try std.testing.expectEqualStrings("swi", firstSyllable("swift"));
    try std.testing.expectEqualStrings("eu", firstSyllable("europa"));
    try std.testing.expectEqualStrings("o", firstSyllable("odin"));
    try std.testing.expectEqualStrings("bry", firstSyllable("bryce"));
    try std.testing.expectEqualStrings("mo", firstSyllable("mojave"));
    try std.testing.expectEqualStrings("qui", firstSyllable("quick"));
    // Phrase names use first component
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

test "mnemonic generation is deterministic" {
    var gen1 = Generator.init(0);
    const name1 = try gen1.generate(.{ .mnemonic = "test123" }, null);
    var val1: [25]u8 = undefined;
    @memcpy(val1[0..name1.value.len], name1.value);
    const saved1 = val1[0..name1.value.len];

    var gen2 = Generator.init(0);
    const name2 = try gen2.generate(.{ .mnemonic = "test123" }, null);
    try std.testing.expectEqualStrings(saved1, name2.value);
}

test "batch generation with syllable distinctness" {
    const allocator = std.testing.allocator;
    var gen = Generator.init(42);
    const batch = try gen.generateBatch(allocator, 5, .thematic, .mountains);
    defer batch.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), batch.names.len);

    // Verify all names have distinct first syllables
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
