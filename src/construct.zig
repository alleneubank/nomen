const std = @import("std");
const types = @import("types.zig");
const worddata = @import("worddata.zig");
const constructdata = @import("constructdata.zig");
const generator_mod = @import("generator.zig");
const Category = types.Category;
const ConstructTechnique = types.ConstructTechnique;
const GenerateError = types.GenerateError;
const Name = types.Name;
const Tone = worddata.Tone;

pub const ConstructBatchResult = struct {
    names: []Name,
    values: [][42]u8,

    pub fn deinit(self: ConstructBatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.names);
    }
};

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

    // ── resolveTwo ──────────────────────────────────────────────────────

    fn resolveTwo(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError![2][]const u8 {
        const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
        if (list.len == 0) return error.EmptyWordList;
        const rand = self.prng.random();

        var result: [2][]const u8 = undefined;
        result[0] = if (input_words.len >= 1) input_words[0] else list[rand.intRangeLessThan(usize, 0, list.len)];
        result[1] = if (input_words.len >= 2) input_words[1] else list[rand.intRangeLessThan(usize, 0, list.len)];
        return result;
    }

    // ── compound ────────────────────────────────────────────────────────

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

    // ── portmanteau ─────────────────────────────────────────────────────

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

    // ── clip ────────────────────────────────────────────────────────────

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

    // ── affix ───────────────────────────────────────────────────────────

    fn generateAffix(self: *ConstructEngine, category: ?Category, input_words: []const []const u8) GenerateError!Name {
        const base = if (input_words.len >= 1)
            input_words[0]
        else blk: {
            const list = if (category) |cat| worddata.getWordList(cat) else worddata.curated_nouns;
            if (list.len == 0) return error.EmptyWordList;
            break :blk list[self.prng.random().intRangeLessThan(usize, 0, list.len)];
        };

        const rand = self.prng.random();
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

    // ── backform ────────────────────────────────────────────────────────

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

    // ── phonosym ────────────────────────────────────────────────────────

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

    // ── acronym ─────────────────────────────────────────────────────────

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

        // Insert vowels to break consonant clusters of 3+.
        // For each such cluster, insert one vowel after the 2nd consonant.
        const vowel_options = [_]u8{ 'a', 'e', 'i', 'o', 'u' };
        var pos: usize = 0;

        // Pre-scan: find clusters of 3+ consecutive consonants and mark
        // positions where a vowel should be inserted (after 2nd consonant in each cluster).
        var insert_after: [5]bool = .{ false, false, false, false, false };
        {
            var scan_run: usize = 0;
            var scan_start: usize = 0;
            for (raw, 0..) |c, idx| {
                if (!isVowel(c)) {
                    if (scan_run == 0) scan_start = idx;
                    scan_run += 1;
                } else {
                    if (scan_run >= 3) {
                        // Mark the 2nd consonant in this cluster for vowel insertion
                        insert_after[scan_start + 1] = true;
                    }
                    scan_run = 0;
                }
            }
            // Handle trailing cluster
            if (scan_run >= 3) {
                insert_after[scan_start + 1] = true;
            }
        }

        // Emit characters, inserting vowels at marked positions
        for (raw, 0..) |c, idx| {
            if (pos >= self.buf.len) return error.ConstructionFailed;
            self.buf[pos] = c;
            pos += 1;

            if (idx < 5 and insert_after[idx]) {
                if (pos >= self.buf.len) return error.ConstructionFailed;
                self.buf[pos] = vowel_options[rand.intRangeLessThan(usize, 0, vowel_options.len)];
                pos += 1;
            }
        }

        if (pos == 0) return error.ConstructionFailed;
        return .{ .value = self.buf[0..pos], .category = category, .strategy_tag = "construct:acronym" };
    }
};

// ── Mood helpers (phonosym) ─────────────────────────────────────────

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

// ── Shared helpers ──────────────────────────────────────────────────

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

/// Return the first syllable of a word using C->V (consonant-to-vowel) boundaries.
/// A boundary occurs at index i where word[i] is a consonant and word[i+1] is a vowel.
/// The first syllable is everything up to the start of the second syllable.
/// If 0 or 1 boundaries, the word is monosyllabic -> return the whole word.
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

/// Return the last syllable of a word using C->V boundaries.
/// Finds the last C->V boundary and returns from that consonant onward.
/// If no boundaries, the word is monosyllabic -> return the whole word.
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
    return word.len;
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

// ── Tests ───────────────────────────────────────────────────────────

test "compound concatenates two words" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.compound, null, &.{ "storm", "forge" });
    try std.testing.expectEqualStrings("stormforge", name.value);
    try std.testing.expectEqualStrings("construct:compound", name.strategy_tag);
}

test "portmanteau blends overlapping words" {
    var eng = ConstructEngine.init(42);
    // "motor" + "oracle" — suffix "or" of "motor" matches prefix "or" of "oracle" (2 chars)
    // Result: "motor" + "acle" = "motoracle"
    const name = try eng.generateConstruct(.portmanteau, null, &.{ "motor", "oracle" });
    try std.testing.expectEqualStrings("motoracle", name.value);
    try std.testing.expectEqualStrings("construct:portmanteau", name.strategy_tag);
}

test "portmanteau fallback when no overlap" {
    var eng = ConstructEngine.init(42);
    // "storm" + "fury" — no 2-char overlap
    // Rightmost VC boundary in "storm": s-t-o-r-m -> word[i-1]='o' is vowel, word[i]='r' is consonant -> return i=3
    // Cut word1 at index 3: "sto"
    // firstVowelIndex("fury"): 'u' at index 1 -> suffix = "ury"
    // Result: "sto" + "ury" = "stoury"
    const name = try eng.generateConstruct(.portmanteau, null, &.{ "storm", "fury" });
    try std.testing.expectEqualStrings("stoury", name.value);
}

test "clip takes first syllable of word1, last syllable of word2" {
    var eng = ConstructEngine.init(42);
    // "spell": s-p-e-l-l. C->V transitions: p->e at index 1->2. Only 1 boundary -> monosyllabic -> "spell"
    // "master": m-a-s-t-e-r. C->V transitions: m->a (0->1), t->e (3->4).
    //   Last boundary at index 3 (consonant 't'). Return word[3..] = "ter"
    const name = try eng.generateConstruct(.clip, null, &.{ "spell", "master" });
    try std.testing.expectEqualStrings("spellter", name.value);
    try std.testing.expectEqualStrings("construct:clip", name.strategy_tag);
}

test "clip with multi-syllable first word" {
    var eng = ConstructEngine.init(42);
    // "information": i(0) n(1) f(2) o(3) r(4) m(5) a(6) t(7) i(8) o(9) n(10)
    //   C->V boundaries: f(2)->o(3), m(5)->a(6), t(7)->i(8)
    //   First boundary at 2, second boundary at 5. firstSyllableSlice returns word[0..5] = "infor"
    // "master": last C->V boundary at index 3. Return word[3..] = "ter"
    const name = try eng.generateConstruct(.clip, null, &.{ "information", "master" });
    try std.testing.expectEqualStrings("inforter", name.value);
}

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
    // c-r-y-s-t-a-l -> vowel groups: "y" at index 2 (group 1), "a" at index 5 (group 2)
    // After 2nd vowel group ends, first consonant is 'l' at index 6.
    // truncateAfterSecondVowelGroup returns 6.
    try std.testing.expectEqualStrings("crysta", name.value);
}

test "phonosym sharp produces hard consonants" {
    var eng = ConstructEngine.init(42);
    const name = try eng.generateConstruct(.phonosym, null, &.{"sharp"});
    // Templates have 4-8 slots; phonemes are 1-2 chars each, so output is 4-16 chars
    try std.testing.expect(name.value.len >= 4 and name.value.len <= 16);
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
    // Templates have 4-8 slots; phonemes are 1-2 chars each, so output is 4-16 chars
    try std.testing.expect(name.value.len >= 4 and name.value.len <= 16);
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

test "acronym pronounceable as-is" {
    var eng = ConstructEngine.init(42);
    // s,p,a -> "spa" — has vowel, no 3+ consonant cluster -> as-is
    const name = try eng.generateConstruct(.acronym, null, &.{ "spell", "practice", "app" });
    try std.testing.expectEqualStrings("spa", name.value);
    try std.testing.expectEqualStrings("construct:acronym", name.strategy_tag);
}

test "acronym inserts vowels for consonant clusters of 3+" {
    var eng = ConstructEngine.init(42);
    // b,c,d,f -> "bcdf" -> 4 consecutive consonants (cluster of 3+)
    // Insert vowel after 2nd consonant: "bc[v]df" = 5 chars
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
