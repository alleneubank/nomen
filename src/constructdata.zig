/// Comptime construct data — affixes and phonemes for construct strategies.
///
/// Source files:
///   data/affixes.tsv:  affix\ttype\ttone\n
///   data/phonemes.tsv: mood\tclass\tvalues\n (values = comma-separated)
///
/// All parsing, validation, and categorization happens at compile time.
/// Runtime cost: zero. Invalid data causes a build failure.
const std = @import("std");
const worddata = @import("worddata.zig");
const Tone = worddata.Tone;

// ── Affix types ────────────────────────────────

pub const Affix = struct {
    value: []const u8,
    is_prefix: bool,
    tone: Tone,
};

// ── Backform suffixes (inlined) ───────────────────────────

pub const backform_suffixes = [_][]const u8{
    "ible", "able", "tion", "ment", "ness", "ance", "ence", "ive", "ous", "ity", "ing", "ure",
};

// ── Comptime helpers ───────────────────────────────

fn comptimeFindChar(comptime s: []const u8, comptime ch: u8, comptime start: usize) ?usize {
    for (s[start..], start..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

fn comptimeCountLines(comptime data: []const u8) comptime_int {
    @setEvalBranchQuota(data.len * 2);
    var count: comptime_int = 0;
    for (data) |c| {
        if (c == '\n') count += 1;
    }
    if (data.len > 0 and data[data.len - 1] != '\n') count += 1;
    return count;
}

fn comptimeParseTone(comptime s: []const u8) Tone {
    if (s.len == 0) return .general;
    if (std.mem.eql(u8, s, "nature")) return .nature;
    if (std.mem.eql(u8, s, "tech")) return .tech;
    if (std.mem.eql(u8, s, "general")) return .general;
    @compileError("unknown tone: " ++ s);
}

// ── Affix parsing ────────────────────────────────

const affix_raw = @embedFile("data/affixes.tsv");

fn comptimeParseAffixLine(comptime line: []const u8) Affix {
    const tab1 = comptimeFindChar(line, '\t', 0) orelse
        @compileError("missing first tab in affix line: " ++ line);
    const tab2 = comptimeFindChar(line, '\t', tab1 + 1) orelse
        @compileError("missing second tab in affix line: " ++ line);

    const value = line[0..tab1];
    const type_str = line[tab1 + 1 .. tab2];
    const tone_str = line[tab2 + 1 ..];

    if (value.len < 1 or value.len > 6) {
        @compileError("affix length out of range [1,6]: " ++ value);
    }

    const is_prefix = if (std.mem.eql(u8, type_str, "prefix"))
        true
    else if (std.mem.eql(u8, type_str, "suffix"))
        false
    else
        @compileError("unknown affix type (expected prefix/suffix): " ++ type_str);

    return .{
        .value = value,
        .is_prefix = is_prefix,
        .tone = comptimeParseTone(tone_str),
    };
}

fn comptimeParseAllAffixes(comptime data: []const u8) [comptimeCountLines(data)]Affix {
    @setEvalBranchQuota(200_000);
    const count = comptimeCountLines(data);
    var result: [count]Affix = undefined;
    var idx: usize = 0;
    var line_start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n') {
            if (i > line_start) {
                result[idx] = comptimeParseAffixLine(data[line_start..i]);
                idx += 1;
            }
            line_start = i + 1;
        }
    }
    if (line_start < data.len) {
        result[idx] = comptimeParseAffixLine(data[line_start..]);
        idx += 1;
    }

    return result;
}

/// All affixes parsed from data/affixes.tsv at comptime.
pub const all_affixes: []const Affix = &comptimeParseAllAffixes(affix_raw);

// ── Affix filtered views ─────────────────────────────

fn comptimeCountAffixMatching(comptime affixes: []const Affix, comptime pred: fn (Affix) bool) comptime_int {
    var count: comptime_int = 0;
    for (affixes) |a| {
        if (pred(a)) count += 1;
    }
    return count;
}

fn comptimeExtractAffixValues(
    comptime affixes: []const Affix,
    comptime pred: fn (Affix) bool,
) [comptimeCountAffixMatching(affixes, pred)]Affix {
    const count = comptimeCountAffixMatching(affixes, pred);
    var result: [count]Affix = undefined;
    var idx: usize = 0;
    for (affixes) |a| {
        if (pred(a)) {
            result[idx] = a;
            idx += 1;
        }
    }
    return result;
}

fn isPrefix(a: Affix) bool {
    return a.is_prefix;
}

fn isSuffix(a: Affix) bool {
    return !a.is_prefix;
}

/// All prefixes from affixes.tsv.
pub const prefixes: []const Affix = &comptimeExtractAffixValues(all_affixes, isPrefix);

/// All suffixes from affixes.tsv.
pub const suffixes: []const Affix = &comptimeExtractAffixValues(all_affixes, isSuffix);

// ── Phoneme parsing ───────────────────────────────

const phoneme_raw = @embedFile("data/phonemes.tsv");

fn comptimeCountCommaValues(comptime s: []const u8) comptime_int {
    if (s.len == 0) return 0;
    var count: comptime_int = 1;
    for (s) |c| {
        if (c == ',') count += 1;
    }
    return count;
}

fn comptimeSplitComma(comptime s: []const u8) [comptimeCountCommaValues(s)][]const u8 {
    const count = comptimeCountCommaValues(s);
    var result: [count][]const u8 = undefined;
    var idx: usize = 0;
    var start: usize = 0;

    for (s, 0..) |c, i| {
        if (c == ',') {
            const val = s[start..i];
            if (val.len < 1 or val.len > 2) {
                @compileError("phoneme length out of range [1,2]: " ++ val);
            }
            result[idx] = val;
            idx += 1;
            start = i + 1;
        }
    }
    // Last value
    const val = s[start..];
    if (val.len < 1 or val.len > 2) {
        @compileError("phoneme length out of range [1,2]: " ++ val);
    }
    result[idx] = val;

    return result;
}

/// Max phoneme values per line (generous upper bound for comptime arrays).
const max_phonemes = 16;

const PhonemeLine = struct {
    mood: []const u8,
    class: []const u8,
    count: usize,
    values: [max_phonemes][]const u8,
};

fn comptimeParsePhonemeLine(comptime line: []const u8) PhonemeLine {
    const tab1 = comptimeFindChar(line, '\t', 0) orelse
        @compileError("missing first tab in phoneme line: " ++ line);
    const tab2 = comptimeFindChar(line, '\t', tab1 + 1) orelse
        @compileError("missing second tab in phoneme line: " ++ line);

    const mood = line[0..tab1];
    const class = line[tab1 + 1 .. tab2];
    const values_str = line[tab2 + 1 ..];

    const split = comptimeSplitComma(values_str);
    var values: [max_phonemes][]const u8 = .{""} ** max_phonemes;
    for (split, 0..) |v, i| {
        values[i] = v;
    }

    return .{
        .mood = mood,
        .class = class,
        .count = split.len,
        .values = values,
    };
}

fn comptimeParseAllPhonemes(comptime data: []const u8) [comptimeCountLines(data)]PhonemeLine {
    @setEvalBranchQuota(200_000);
    const count = comptimeCountLines(data);
    var result: [count]PhonemeLine = undefined;
    var idx: usize = 0;
    var line_start: usize = 0;

    for (data, 0..) |c, i| {
        if (c == '\n') {
            if (i > line_start) {
                result[idx] = comptimeParsePhonemeLine(data[line_start..i]);
                idx += 1;
            }
            line_start = i + 1;
        }
    }
    if (line_start < data.len) {
        result[idx] = comptimeParsePhonemeLine(data[line_start..]);
        idx += 1;
    }

    return result;
}

const all_phonemes: []const PhonemeLine = &comptimeParseAllPhonemes(phoneme_raw);

// ── Phoneme lookup helpers ─────────────────────────────

fn comptimeFindPhonemes(comptime mood: []const u8, comptime class: []const u8) []const []const u8 {
    for (all_phonemes) |p| {
        if (std.mem.eql(u8, p.mood, mood) and std.mem.eql(u8, p.class, class)) {
            const slice: []const []const u8 = p.values[0..p.count];
            return slice;
        }
    }
    @compileError("phoneme entry not found: " ++ mood ++ "/" ++ class);
}

/// Sharp mood consonants.
pub const sharp_consonants: []const []const u8 = comptimeFindPhonemes("sharp", "consonants");

/// Sharp mood vowels.
pub const sharp_vowels: []const []const u8 = comptimeFindPhonemes("sharp", "vowels");

/// Soft mood consonants.
pub const soft_consonants: []const []const u8 = comptimeFindPhonemes("soft", "consonants");

/// Soft mood vowels.
pub const soft_vowels: []const []const u8 = comptimeFindPhonemes("soft", "vowels");

/// Rhythmic mood consonants.
pub const rhythmic_consonants: []const []const u8 = comptimeFindPhonemes("rhythmic", "consonants");

/// Rhythmic mood vowels.
pub const rhythmic_vowels: []const []const u8 = comptimeFindPhonemes("rhythmic", "vowels");

// ── Tests ──────────────────────────────────

test "all_affixes has at least 8 prefixes and 8 suffixes" {
    try std.testing.expect(prefixes.len >= 8);
    try std.testing.expect(suffixes.len >= 8);
}

test "all affixes are <= 6 chars" {
    for (all_affixes) |a| {
        try std.testing.expect(a.value.len <= 6);
    }
}

test "each mood has >= 5 consonants and >= 3 vowels" {
    try std.testing.expect(sharp_consonants.len >= 5);
    try std.testing.expect(sharp_vowels.len >= 3);
    try std.testing.expect(soft_consonants.len >= 5);
    try std.testing.expect(soft_vowels.len >= 3);
    try std.testing.expect(rhythmic_consonants.len >= 5);
    try std.testing.expect(rhythmic_vowels.len >= 3);
}

test "backform suffixes has 12 entries" {
    try std.testing.expect(backform_suffixes.len == 12);
}
