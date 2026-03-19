/// Comptime word data — the unified dictionary for all generation strategies.
///
/// Source file (data/words.tsv) format: word\tpos_tags\ttheme\ttone\n
///   pos_tags: comma-separated POS codes (a=adjective, n=noun, v=verb, p=proper_noun)
///   theme:    optional category name (mountains, rivers, etc.) or empty
///   tone:     optional tone tag (nature, tech) or empty (= general)
///
/// All parsing, validation, and categorization happens at compile time.
/// Runtime cost: zero. Invalid data causes a build failure.
const std = @import("std");
const types = @import("types.zig");
const Category = types.Category;

const raw = @embedFile("data/words.tsv");

pub const Tone = enum {
    general,
    nature,
    tech,

    /// Two tones are compatible for phrase pairing when they share a domain
    /// or one of them is general.
    pub fn compatible(a: Tone, b: Tone) bool {
        if (a == .general or b == .general) return true;
        return a == b;
    }
};

/// A word with its POS tags, theme, tone, and syllable count, resolved at comptime.
pub const TaggedWord = struct {
    word: []const u8,
    is_adjective: bool,
    is_noun: bool,
    is_verb: bool,
    is_proper: bool,
    category: ?Category,
    tone: Tone,
    syllables: u8,
};

// --- Comptime syllable counter ---

fn comptimeSyllableCount(comptime word: []const u8) u8 {
    if (word.len == 0) return 0;
    var count: u8 = 0;
    var prev_vowel = false;
    for (word, 0..) |c, i| {
        const is_vowel = (c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u') or
            (c == 'y' and i > 0);
        if (is_vowel and !prev_vowel) count += 1;
        prev_vowel = is_vowel;
    }
    // Silent 'e' at end: reduce by 1 if word ends in 'e' and has >1 syllable
    if (count > 1 and word[word.len - 1] == 'e') {
        // But not for words ending in 'le' preceded by a consonant (e.g., "maple")
        if (word.len >= 2) {
            const penult = word[word.len - 2];
            const penult_vowel = (penult == 'a' or penult == 'e' or penult == 'i' or
                penult == 'o' or penult == 'u');
            if (!penult_vowel and penult != 'l') count -= 1;
        }
    }
    return if (count == 0) 1 else count;
}

// --- Comptime parsing ---

fn comptimeCountLines(comptime data: []const u8) comptime_int {
    @setEvalBranchQuota(data.len * 2);
    var count: comptime_int = 0;
    for (data) |c| {
        if (c == '\n') count += 1;
    }
    if (data.len > 0 and data[data.len - 1] != '\n') count += 1;
    return count;
}

fn comptimeFindChar(comptime s: []const u8, comptime ch: u8, comptime start: usize) ?usize {
    for (s[start..], start..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

fn comptimeParseTone(comptime s: []const u8) Tone {
    if (s.len == 0) return .general;
    if (std.mem.eql(u8, s, "nature")) return .nature;
    if (std.mem.eql(u8, s, "tech")) return .tech;
    @compileError("unknown tone: " ++ s);
}

fn comptimeParseLine(comptime line: []const u8) TaggedWord {
    // Format: word\tpos\ttheme\ttone
    const tab1 = comptimeFindChar(line, '\t', 0) orelse @compileError("missing first tab: " ++ line);
    const tab2 = comptimeFindChar(line, '\t', tab1 + 1) orelse @compileError("missing second tab: " ++ line);
    const tab3 = comptimeFindChar(line, '\t', tab2 + 1) orelse @compileError("missing third tab: " ++ line);

    const word = line[0..tab1];
    const pos_str = line[tab1 + 1 .. tab2];
    const theme_str = line[tab2 + 1 .. tab3];
    const tone_str = line[tab3 + 1 ..];

    // Validate word
    if (word.len < 1 or word.len > 12) {
        @compileError("word length out of range [1,12]: " ++ word);
    }
    for (word) |c| {
        if (c < 'a' or c > 'z') {
            @compileError("word contains non-lowercase char: " ++ word);
        }
    }

    // Parse POS tags
    var is_adj = false;
    var is_noun = false;
    var is_verb = false;
    var is_proper = false;
    for (pos_str) |c| {
        switch (c) {
            'a' => is_adj = true,
            'n' => is_noun = true,
            'v' => is_verb = true,
            'p' => is_proper = true,
            ',' => {},
            else => @compileError("unknown POS tag in: " ++ pos_str ++ " for word: " ++ word),
        }
    }

    // Parse theme
    const category: ?Category = if (theme_str.len == 0)
        null
    else
        std.meta.stringToEnum(Category, theme_str) orelse
            @compileError("unknown category: " ++ theme_str ++ " for word: " ++ word);

    return .{
        .word = word,
        .is_adjective = is_adj,
        .is_noun = is_noun,
        .is_verb = is_verb,
        .is_proper = is_proper,
        .category = category,
        .tone = comptimeParseTone(tone_str),
        .syllables = comptimeSyllableCount(word),
    };
}

fn comptimeParseAll(comptime data: []const u8) [comptimeCountLines(data)]TaggedWord {
    @setEvalBranchQuota(2_000_000);
    const count = comptimeCountLines(data);
    var result: [count]TaggedWord = undefined;
    var idx: usize = 0;
    var line_start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n') {
            if (i > line_start) {
                result[idx] = comptimeParseLine(data[line_start..i]);
                idx += 1;
            }
            line_start = i + 1;
        }
    }
    if (line_start < data.len) {
        result[idx] = comptimeParseLine(data[line_start..]);
        idx += 1;
    }

    return result;
}

/// All tagged words, parsed and validated at comptime.
pub const all_words: []const TaggedWord = &comptimeParseAll(raw);

// --- Generic comptime filter/extract ---

fn comptimeCountMatching(comptime words: []const TaggedWord, comptime pred: fn (TaggedWord) bool) comptime_int {
    @setEvalBranchQuota(1_000_000);
    var count: comptime_int = 0;
    for (words) |w| {
        if (pred(w)) count += 1;
    }
    return count;
}

fn comptimeExtractWords(
    comptime words: []const TaggedWord,
    comptime pred: fn (TaggedWord) bool,
) [comptimeCountMatching(words, pred)][]const u8 {
    @setEvalBranchQuota(1_000_000);
    const count = comptimeCountMatching(words, pred);
    var result: [count][]const u8 = undefined;
    var idx: usize = 0;
    for (words) |w| {
        if (pred(w)) {
            result[idx] = w.word;
            idx += 1;
        }
    }
    return result;
}

// --- POS-filtered views ---

fn isAdj(w: TaggedWord) bool {
    return w.is_adjective;
}
fn isNoun(w: TaggedWord) bool {
    return w.is_noun or w.is_proper;
}
fn isVerb(w: TaggedWord) bool {
    return w.is_verb;
}
fn isAny(_: TaggedWord) bool {
    return true;
}

/// Words usable as adjectives (modifiers) in phrase generation.
pub const adjectives: []const []const u8 = &comptimeExtractWords(all_words, isAdj);

/// Words usable as nouns (including proper nouns) in phrase generation.
pub const nouns: []const []const u8 = &comptimeExtractWords(all_words, isNoun);

/// Words usable as verbs in phrase generation.
pub const verbs: []const []const u8 = &comptimeExtractWords(all_words, isVerb);

/// Full flat word list for mnemonic encoding strategy.
pub const mnemonic_all: []const []const u8 = &comptimeExtractWords(all_words, isAny);

// --- Category-filtered views (for thematic strategy) ---

fn makeCategoryPred(comptime cat: Category) fn (TaggedWord) bool {
    return struct {
        fn pred(w: TaggedWord) bool {
            return w.category != null and w.category.? == cat;
        }
    }.pred;
}

/// Get the word list for a specific category, built at comptime.
pub fn getWordList(category: Category) []const []const u8 {
    return switch (category) {
        inline else => |cat| {
            const extracted = comptime comptimeExtractWords(all_words, makeCategoryPred(cat));
            return &extracted;
        },
    };
}

// --- Tone lookup (for phrase tonal coherence) ---

/// Look up the tone of a word by scanning all_words at runtime.
/// Returns general if the word isn't found.
pub fn getTone(word: []const u8) Tone {
    for (all_words) |w| {
        if (std.mem.eql(u8, w.word, word)) return w.tone;
    }
    return .general;
}

/// Look up the syllable count of a word.
pub fn getSyllables(word: []const u8) u8 {
    for (all_words) |w| {
        if (std.mem.eql(u8, w.word, word)) return w.syllables;
    }
    return 2; // reasonable default
}

// --- Comptime statistics ---

pub const word_count = all_words.len;
pub const adjective_count = adjectives.len;
pub const noun_count = nouns.len;
pub const verb_count = verbs.len;
pub const category_count = std.enums.values(Category).len;
pub const phrase_combo_space = adjective_count * noun_count;
pub const mnemonic_combo_space = word_count * word_count;

// --- Tests ---

test "word count includes expanded categories" {
    try std.testing.expect(word_count >= 1900);
    try std.testing.expect(word_count <= 2200);
}

test "adjective list is substantial" {
    try std.testing.expect(adjective_count >= 200);
}

test "noun list is substantial" {
    try std.testing.expect(noun_count >= 1000);
}

test "verb list exists" {
    try std.testing.expect(verb_count >= 50);
}

test "phrase combo space exceeds 100k" {
    try std.testing.expect(phrase_combo_space > 100_000);
}

test "mnemonic combo space exceeds 2M" {
    try std.testing.expect(mnemonic_combo_space > 2_000_000);
}

test "all words are dns-safe" {
    for (mnemonic_all) |word| {
        try std.testing.expect(word.len >= 1);
        try std.testing.expect(word.len <= 12);
        for (word) |c| {
            try std.testing.expect(c >= 'a' and c <= 'z');
        }
    }
}

test "at least 14 categories" {
    try std.testing.expect(category_count >= 14);
}

test "every category has words" {
    const categories = comptime std.enums.values(Category);
    inline for (categories) |cat| {
        const list = getWordList(cat);
        try std.testing.expect(list.len >= 10);
    }
}

test "new categories have words" {
    try std.testing.expect(getWordList(.volcanoes).len >= 10);
    try std.testing.expect(getWordList(.forests).len >= 10);
    try std.testing.expect(getWordList(.oceans).len >= 10);
    try std.testing.expect(getWordList(.storms).len >= 10);
}

test "tone compatibility" {
    try std.testing.expect(Tone.compatible(.nature, .nature));
    try std.testing.expect(Tone.compatible(.nature, .general));
    try std.testing.expect(Tone.compatible(.general, .tech));
    try std.testing.expect(!Tone.compatible(.nature, .tech));
}

test "syllable counts are reasonable" {
    // "alpine" = 2, "brave" = 1, "falcon" = 2
    try std.testing.expect(getSyllables("alpine") == 2);
    try std.testing.expect(getSyllables("brave") == 1);
    try std.testing.expect(getSyllables("falcon") == 2);
}

test "category words include known entries" {
    const mountains = getWordList(.mountains);
    var found_denali = false;
    for (mountains) |w| {
        if (std.mem.eql(u8, w, "denali")) found_denali = true;
    }
    try std.testing.expect(found_denali);
}
