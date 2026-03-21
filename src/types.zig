const std = @import("std");

pub const Category = enum {
    mountains,
    rivers,
    deserts,
    canyons,
    islands,
    passes,
    moons,
    raptors,
    minerals,
    norse,
    volcanoes,
    forests,
    oceans,
    storms,

    pub fn toString(self: Category) []const u8 {
        return @tagName(self);
    }

    pub fn fromString(s: []const u8) ParseError!Category {
        return std.meta.stringToEnum(Category, s) orelse error.InvalidCategory;
    }
};

pub const PhrasePattern = enum {
    adjective_noun,
    noun_noun,
    verb_noun,
    alliterative,
};

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

pub const Name = struct {
    value: []const u8,
    category: ?Category,
    strategy_tag: []const u8,
};

pub const OutputFormat = enum {
    json,
    jsonl,
    human,

    pub fn fromString(s: []const u8) ParseError!OutputFormat {
        return std.meta.stringToEnum(OutputFormat, s) orelse error.InvalidFormat;
    }
};

pub const ParseError = error{
    InvalidCategory,
    InvalidStrategy,
    InvalidFormat,
    InvalidCount,
    InvalidSeed,
    InvalidInput,
    ControlCharRejected,
    UnknownFlag,
    MissingValue,
    UnknownSubcommand,
};

pub const GenerateError = error{
    EmptyWordList,
    NoDistinctNames,
    ConstructionFailed,
};

pub const HelpOptions = struct {
    format: ?OutputFormat = null,
};

pub const CategoriesOptions = struct {
    format: ?OutputFormat = null,
};

pub const ServeOptions = struct {
    port: u16 = 8080,
};

pub const CliCommand = union(enum) {
    generate: GenerateOptions,
    categories: CategoriesOptions,
    serve: ServeOptions,
    version,
    help: HelpOptions,
    llms,
    generate_help: HelpOptions,
    categories_help: HelpOptions,
    serve_help: HelpOptions,
};

pub const GenerateOptions = struct {
    count: u32 = 1,
    category: ?Category = null,
    strategy: Strategy = .thematic,
    seed: ?u64 = null,
    format: ?OutputFormat = null,
    fields: ?[]const u8 = null,
    dry_run: bool = false,
    input: ?[]const u8 = null,
};

pub const StructuredError = struct {
    code: []const u8,
    message: []const u8,
};

/// Validate mnemonic input is numeric (decimal) or hex (0x prefix).
pub fn validateMnemonicInput(input: []const u8) ParseError!void {
    if (input.len == 0) return error.InvalidInput;

    // Allow 0x prefix for hex
    const start: usize = if (input.len > 2 and input[0] == '0' and (input[1] == 'x' or input[1] == 'X')) 2 else 0;

    if (start >= input.len) return error.InvalidInput;

    for (input[start..]) |c| {
        if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) {
            return error.InvalidInput;
        }
    }
}

/// Validate construct input: comma-separated lowercase words, max 5 words, max 20 chars each.
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

test "validateMnemonicInput accepts decimal" {
    try validateMnemonicInput("12345");
}

test "validateMnemonicInput accepts hex with prefix" {
    try validateMnemonicInput("0xdeadbeef");
    try validateMnemonicInput("0XABC123");
}

test "validateMnemonicInput accepts hex digits without prefix" {
    try validateMnemonicInput("deadbeef");
    try validateMnemonicInput("abc123");
}

test "validateMnemonicInput rejects non-hex text" {
    try std.testing.expectError(error.InvalidInput, validateMnemonicInput("nothex"));
    try std.testing.expectError(error.InvalidInput, validateMnemonicInput("hello world"));
}

test "validateMnemonicInput rejects empty" {
    try std.testing.expectError(error.InvalidInput, validateMnemonicInput(""));
}

test "validateMnemonicInput rejects bare 0x" {
    try std.testing.expectError(error.InvalidInput, validateMnemonicInput("0x"));
}

test "Category.fromString valid" {
    const cat = try Category.fromString("mountains");
    try std.testing.expectEqual(Category.mountains, cat);
}

test "Category.fromString invalid" {
    const result = Category.fromString("nonexistent");
    try std.testing.expectError(error.InvalidCategory, result);
}

test "Strategy.fromString valid" {
    const s = try Strategy.fromString("thematic");
    try std.testing.expectEqual(Strategy.thematic, s);
}

test "Strategy.fromString phrase" {
    const s = try Strategy.fromString("phrase");
    try std.testing.expect(s == .phrase);
}

test "Strategy.fromString invalid" {
    const result = Strategy.fromString("nonexistent");
    try std.testing.expectError(error.InvalidStrategy, result);
}

test "OutputFormat.fromString valid" {
    const f = try OutputFormat.fromString("json");
    try std.testing.expectEqual(OutputFormat.json, f);
}

test "OutputFormat.fromString invalid" {
    const result = OutputFormat.fromString("xml");
    try std.testing.expectError(error.InvalidFormat, result);
}

test "Category.toString roundtrip" {
    const cat = Category.mountains;
    const s = cat.toString();
    const back = try Category.fromString(s);
    try std.testing.expectEqual(cat, back);
}

test "ConstructTechnique.fromString valid" {
    const ct = ConstructTechnique.fromString("portmanteau");
    try std.testing.expectEqual(ConstructTechnique.portmanteau, ct.?);
}

test "ConstructTechnique.fromString invalid" {
    try std.testing.expect(ConstructTechnique.fromString("bogus") == null);
}

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

test "GenerateError includes ConstructionFailed" {
    const err: GenerateError = error.ConstructionFailed;
    try std.testing.expect(err == error.ConstructionFailed);
}
