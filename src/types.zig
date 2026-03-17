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
};

pub const Strategy = union(enum) {
    thematic,
    phrase: PhrasePattern,
    mnemonic: []const u8,

    pub fn fromString(s: []const u8) ParseError!Strategy {
        if (std.mem.eql(u8, s, "thematic")) return .thematic;
        if (std.mem.eql(u8, s, "phrase")) return .{ .phrase = .adjective_noun };
        if (std.mem.eql(u8, s, "phrase:adjective_noun")) return .{ .phrase = .adjective_noun };
        if (std.mem.eql(u8, s, "phrase:noun_noun")) return .{ .phrase = .noun_noun };
        if (std.mem.eql(u8, s, "phrase:verb_noun")) return .{ .phrase = .verb_noun };
        if (std.mem.eql(u8, s, "mnemonic")) return .{ .mnemonic = "" };
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
