const std = @import("std");
const types = @import("types.zig");
const CliCommand = types.CliCommand;
const GenerateOptions = types.GenerateOptions;
const ParseError = types.ParseError;
const Category = types.Category;
const OutputFormat = types.OutputFormat;

pub fn parseArgs(args: []const []const u8) ParseError!CliCommand {
    if (args.len == 0) return .{ .help = .{ .format = null } };

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
        return parseTopLevelHelp(args[1..]);
    }
    if (std.mem.eql(u8, subcmd, "--version") or std.mem.eql(u8, subcmd, "-v")) {
        try validateNoTrailingArgs(args[1..]);
        return .version;
    }
    if (std.mem.eql(u8, subcmd, "--llms")) {
        try validateNoTrailingArgs(args[1..]);
        return .llms;
    }
    if (std.mem.eql(u8, subcmd, "categories")) return parseCategoriesArgs(args[1..]);
    if (std.mem.eql(u8, subcmd, "serve")) return parseServeArgs(args[1..]);

    if (!std.mem.eql(u8, subcmd, "generate")) {
        return error.UnknownSubcommand;
    }

    return parseGenerateArgs(args[1..]);
}

fn parseCategoriesArgs(args: []const []const u8) ParseError!CliCommand {
    var format: ?OutputFormat = null;
    var saw_help = false;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            saw_help = true;
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            format = try OutputFormat.fromString(args[i]);
        } else if (std.mem.eql(u8, arg, "--json")) {
            format = .json;
        } else {
            try rejectControlChars(arg);
            return error.UnknownFlag;
        }
    }

    if (saw_help) return .{ .categories_help = .{ .format = format } };
    return .{ .categories = .{ .format = format } };
}

fn parseServeArgs(args: []const []const u8) ParseError!CliCommand {
    var port: u16 = 8080;
    var saw_help = false;
    var help_format: ?OutputFormat = null;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            saw_help = true;
        } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            port = std.fmt.parseInt(u16, args[i], 10) catch return error.InvalidInput;
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            // --format is only valid with --help for serve
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            help_format = try OutputFormat.fromString(args[i]);
            if (!saw_help) {
                // Defer error check — if --help appears later, format is valid
                // We'll check at the end
            }
        } else if (std.mem.eql(u8, arg, "--json")) {
            help_format = .json;
        } else {
            try rejectControlChars(arg);
            return error.UnknownFlag;
        }
    }

    if (saw_help) return .{ .serve_help = .{ .format = help_format } };
    // --format/--json without --help is invalid for serve
    if (help_format != null) return error.UnknownFlag;
    return .{ .serve = .{ .port = port } };
}

fn parseGenerateArgs(args: []const []const u8) ParseError!CliCommand {
    var opts: GenerateOptions = .{};
    var saw_help = false;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            saw_help = true;
            continue;
        }

        try rejectControlChars(arg);

        if (std.mem.eql(u8, arg, "--count") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.count = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidCount;
            if (opts.count == 0) return error.InvalidCount;
        } else if (std.mem.eql(u8, arg, "--category") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.category = try Category.fromString(args[i]);
        } else if (std.mem.eql(u8, arg, "--strategy") or std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.strategy = try types.Strategy.fromString(args[i]);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.seed = std.fmt.parseInt(u64, args[i], 10) catch return error.InvalidSeed;
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.format = try OutputFormat.fromString(args[i]);
        } else if (std.mem.eql(u8, arg, "--fields")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.fields = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            opts.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            opts.input = args[i];
        } else if (std.mem.eql(u8, arg, "--json")) {
            opts.format = .json;
        } else {
            return error.UnknownFlag;
        }
    }

    if (saw_help) return .{ .generate_help = .{ .format = opts.format } };
    return .{ .generate = opts };
}

fn parseTopLevelHelp(args: []const []const u8) ParseError!CliCommand {
    var format: ?OutputFormat = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try rejectControlChars(args[i]);
            format = try OutputFormat.fromString(args[i]);
        } else if (std.mem.eql(u8, arg, "--json")) {
            format = .json;
        } else {
            try rejectControlChars(arg);
            return error.UnknownFlag;
        }
    }
    return .{ .help = .{ .format = format } };
}

fn validateNoTrailingArgs(args: []const []const u8) ParseError!void {
    for (args) |arg| {
        try rejectControlChars(arg);
        return error.UnknownFlag;
    }
}

fn parseFormatFromArgs(args: []const []const u8) ?OutputFormat {
    for (args, 0..) |arg, idx| {
        if ((std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) and idx + 1 < args.len) {
            return OutputFormat.fromString(args[idx + 1]) catch null;
        }
        if (std.mem.eql(u8, arg, "--json")) return .json;
    }
    return null;
}

fn rejectControlChars(s: []const u8) ParseError!void {
    for (s) |c| {
        if ((c < 0x20 and c != '\t' and c != '\n' and c != '\r') or c == 0x7F) {
            return error.ControlCharRejected;
        }
    }
}

pub fn isStdoutTty() bool {
    const file = std.fs.File.stdout();
    return file.isTty();
}

pub fn resolveFormat(explicit: ?OutputFormat) OutputFormat {
    if (explicit) |f| return f;
    if (isStdoutTty()) return .human;
    return .json;
}

pub fn writeHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.writeAll(
                "{\"name\":\"nomen\"," ++
                    "\"description\":\"Categorical name generator\"," ++
                    "\"commands\":[\"generate\",\"categories\",\"serve\"]," ++
                    "\"flags\":[\"--help\",\"--version\",\"--llms\"]}\n",
            );
        },
        .human => {
            try writer.print(
                \\nomen — categorical name generator
                \\
                \\Usage: nomen <command> [options]
                \\
                \\Commands:
                \\  generate    Generate names
                \\  categories  List available categories
                \\  serve       Start HTTP API server
                \\
                \\Options:
                \\  --help, -h     Show this help
                \\  --version, -v  Show version
                \\  --llms         Agent discovery manifest
                \\
            , .{});
        },
    }
}

pub fn writeGenerateHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.writeAll(
                "{\"name\":\"generate\"," ++
                    "\"description\":\"Generate names from themed word lists\"," ++
                    "\"flags\":[\n" ++
                    "{\"name\":\"--count\",\"short\":\"-n\"," ++
                    "\"type\":\"integer\",\"default\":1," ++
                    "\"description\":\"Number of names\"},\n" ++
                    "{\"name\":\"--category\",\"short\":\"-c\"," ++
                    "\"type\":\"string\"," ++
                    "\"enum\":[\"mountains\",\"rivers\",\"deserts\"," ++
                    "\"canyons\",\"islands\",\"passes\",\"moons\"," ++
                    "\"raptors\",\"minerals\",\"norse\"," ++
                    "\"volcanoes\",\"forests\",\"oceans\"," ++
                    "\"storms\"]," ++
                    "\"description\":\"Word list category\"},\n" ++
                    "{\"name\":\"--strategy\",\"short\":\"-s\"," ++
                    "\"type\":\"string\"," ++
                    "\"enum\":[\"thematic\",\"phrase\"," ++
                    "\"phrase:adjective_noun\"," ++
                    "\"phrase:noun_noun\",\"phrase:verb_noun\"," ++
                    "\"phrase:alliterative\",\"triple\"," ++
                    "\"mnemonic\",\"construct\"," ++
                    "\"construct:portmanteau\"," ++
                    "\"construct:compound\",\"construct:clip\"," ++
                    "\"construct:affix\"," ++
                    "\"construct:backform\"," ++
                    "\"construct:phonosym\"," ++
                    "\"construct:acronym\"]," ++
                    "\"default\":\"thematic\"," ++
                    "\"description\":\"Generation strategy\"},\n" ++
                    "{\"name\":\"--seed\",\"type\":\"integer\"," ++
                    "\"description\":" ++
                    "\"Seed for deterministic output\"},\n" ++
                    "{\"name\":\"--input\",\"short\":\"-i\"," ++
                    "\"type\":\"string\",\"description\":" ++
                    "\"Input for mnemonic encoding" ++
                    " or construct seed words\"},\n" ++
                    "{\"name\":\"--format\",\"short\":\"-f\"," ++
                    "\"type\":\"string\"," ++
                    "\"enum\":[\"json\",\"jsonl\",\"human\"]," ++
                    "\"description\":\"Output format\"},\n" ++
                    "{\"name\":\"--fields\",\"type\":\"string\"," ++
                    "\"description\":" ++
                    "\"Comma-separated output fields\"},\n" ++
                    "{\"name\":\"--dry-run\"," ++
                    "\"type\":\"boolean\",\"description\":" ++
                    "\"Validate without generating\"}\n" ++
                    "]}\n",
            );
        },
        .human => {
            try writer.writeAll(
                "nomen generate — generate names\n" ++
                    "\n" ++
                    "Usage: nomen generate [options]\n" ++
                    "\n" ++
                    "Options:\n" ++
                    "  --count, -n <N>         " ++
                    "Number of names (default: 1)\n" ++
                    "  --category, -c <NAME>   " ++
                    "Restrict to category\n" ++
                    "  --strategy, -s <NAME>   " ++
                    "Strategy: thematic, phrase[:pattern], " ++
                    "triple, mnemonic, " ++
                    "construct[:technique] (default: thematic)\n" ++
                    "  --seed <N>              " ++
                    "Seed for deterministic output\n" ++
                    "  --input, -i <TEXT>      " ++
                    "Input for mnemonic (numeric/hex) " ++
                    "or construct (comma-separated words)\n" ++
                    "  --format, -f <FMT>      " ++
                    "Output format: json, jsonl, human\n" ++
                    "  --json                  " ++
                    "Shorthand for --format json\n" ++
                    "  --fields <FIELDS>       " ++
                    "Comma-separated fields to include\n" ++
                    "  --dry-run               " ++
                    "Validate inputs without generating\n" ++
                    "  --help, -h              " ++
                    "Show this help\n" ++
                    "\n" ++
                    "Categories: mountains, rivers, deserts, " ++
                    "canyons, islands, passes, moons, raptors, " ++
                    "minerals, norse, volcanoes, forests, " ++
                    "oceans, storms\n",
            );
        },
    }
}

pub fn writeCategoriesHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.writeAll(
                "{\"name\":\"categories\"," ++
                    "\"description\":" ++
                    "\"List available word list categories\"," ++
                    "\"flags\":[\n" ++
                    "{\"name\":\"--format\",\"short\":\"-f\"," ++
                    "\"type\":\"string\"," ++
                    "\"enum\":[\"json\",\"jsonl\",\"human\"]," ++
                    "\"description\":\"Output format\"},\n" ++
                    "{\"name\":\"--json\"," ++
                    "\"type\":\"boolean\"," ++
                    "\"description\":" ++
                    "\"Shorthand for --format json\"}\n" ++
                    "]}\n",
            );
        },
        .human => {
            try writer.writeAll(
                "nomen categories — " ++
                    "list available word list categories\n" ++
                    "\n" ++
                    "Usage: nomen categories [options]\n" ++
                    "\n" ++
                    "Options:\n" ++
                    "  --format, -f <FMT>  " ++
                    "Output format: json, jsonl, human\n" ++
                    "  --json              " ++
                    "Shorthand for --format json\n" ++
                    "  --help, -h          " ++
                    "Show this help\n",
            );
        },
    }
}

pub fn writeServeHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.writeAll(
                "{\"name\":\"serve\"," ++
                    "\"description\":" ++
                    "\"Start HTTP API server\"," ++
                    "\"flags\":[\n" ++
                    "{\"name\":\"--port\",\"short\":\"-p\"," ++
                    "\"type\":\"integer\",\"default\":8080," ++
                    "\"description\":\"Port to listen on\"}\n" ++
                    "],\"endpoints\":[\n" ++
                    "{\"path\":\"/generate\"," ++
                    "\"method\":\"GET\"," ++
                    "\"description\":\"Generate names " ++
                    "(query params: count, category, " ++
                    "strategy, seed, input, fields)\"},\n" ++
                    "{\"path\":\"/categories\"," ++
                    "\"method\":\"GET\"," ++
                    "\"description\":" ++
                    "\"List categories\"},\n" ++
                    "{\"path\":\"/health\"," ++
                    "\"method\":\"GET\"," ++
                    "\"description\":\"Health check\"}\n" ++
                    "]}\n",
            );
        },
        .human => {
            try writer.writeAll(
                "nomen serve — start HTTP API server\n" ++
                    "\n" ++
                    "Usage: nomen serve [options]\n" ++
                    "\n" ++
                    "Options:\n" ++
                    "  --port, -p <N>  " ++
                    "Port to listen on (default: 8080)\n" ++
                    "  --help, -h      Show this help\n" ++
                    "\n" ++
                    "Endpoints:\n" ++
                    "  GET /generate     " ++
                    "Generate names (query: count, category, " ++
                    "strategy, seed, input, fields)\n" ++
                    "  GET /categories   " ++
                    "List available categories\n" ++
                    "  GET /health       Health check\n",
            );
        },
    }
}

pub fn writeLlmsManifest(
    writer: anytype,
    version_str: []const u8,
) !void {
    try writer.writeAll(
        "{\n" ++
            "  \"name\": \"nomen\",\n" ++
            "  \"version\": \"",
    );
    try writer.writeAll(version_str);
    try writer.writeAll(
        "\",\n" ++
            "  \"description\": " ++
            "\"Categorical name generator " ++
            "for memorable, themed names\",\n" ++
            "  \"commands\": [\n" ++
            "    {\n" ++
            "      \"name\": \"generate\",\n" ++
            "      \"description\": " ++
            "\"Generate names from " ++
            "themed word lists\",\n" ++
            "      \"flags\": [\n" ++
            "        {\"name\": \"--count\", " ++
            "\"type\": \"integer\", " ++
            "\"default\": 1, \"description\": " ++
            "\"Number of names to generate\"},\n" ++
            "        {\"name\": \"--category\", " ++
            "\"type\": \"string\", " ++
            "\"enum\": [\"mountains\"," ++
            "\"rivers\",\"deserts\"," ++
            "\"canyons\",\"islands\"," ++
            "\"passes\",\"moons\"," ++
            "\"raptors\",\"minerals\"," ++
            "\"norse\",\"volcanoes\"," ++
            "\"forests\",\"oceans\"," ++
            "\"storms\"], " ++
            "\"description\": " ++
            "\"Word list category\"},\n" ++
            "        {\"name\": \"--strategy\"," ++
            " \"type\": \"string\", " ++
            "\"enum\": [\"thematic\"," ++
            "\"phrase\"," ++
            "\"phrase:adjective_noun\"," ++
            "\"phrase:noun_noun\"," ++
            "\"phrase:verb_noun\"," ++
            "\"phrase:alliterative\"," ++
            "\"triple\",\"mnemonic\"," ++
            "\"construct\"," ++
            "\"construct:portmanteau\"," ++
            "\"construct:compound\"," ++
            "\"construct:clip\"," ++
            "\"construct:affix\"," ++
            "\"construct:backform\"," ++
            "\"construct:phonosym\"," ++
            "\"construct:acronym\"], " ++
            "\"default\": \"thematic\", " ++
            "\"description\": " ++
            "\"Generation strategy\"},\n" ++
            "        {\"name\": \"--seed\", " ++
            "\"type\": \"integer\", " ++
            "\"description\": " ++
            "\"Seed for deterministic output\"},\n" ++
            "        {\"name\": \"--input\", " ++
            "\"type\": \"string\", " ++
            "\"description\": " ++
            "\"Input for mnemonic encoding " ++
            "or construct seed words\"},\n" ++
            "        {\"name\": \"--format\", " ++
            "\"type\": \"string\", " ++
            "\"enum\": " ++
            "[\"json\",\"jsonl\",\"human\"], " ++
            "\"description\": " ++
            "\"Output format\"},\n" ++
            "        {\"name\": \"--fields\", " ++
            "\"type\": \"string\", " ++
            "\"description\": " ++
            "\"Comma-separated " ++
            "output fields\"},\n" ++
            "        {\"name\": \"--dry-run\", " ++
            "\"type\": \"boolean\", " ++
            "\"description\": " ++
            "\"Validate without generating\"}\n" ++
            "      ],\n" ++
            "      \"examples\": [\n" ++
            "        {\"command\": " ++
            "\"nomen generate\", " ++
            "\"description\": " ++
            "\"Generate one name\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate --count 5 " ++
            "--category rivers\", " ++
            "\"description\": " ++
            "\"Five river names\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy phrase " ++
            "--format json\", " ++
            "\"description\": " ++
            "\"Two-word phrase as JSON\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--seed 42 --format json\", " ++
            "\"description\": " ++
            "\"Deterministic JSON output\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy mnemonic " ++
            "--input 0xdeadbeef\", " ++
            "\"description\": " ++
            "\"Mnemonic encoding\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy construct:portmanteau " ++
            "--input spell,master\", " ++
            "\"description\": " ++
            "\"Blend two words " ++
            "into a portmanteau\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy construct:compound " ++
            "--input storm,forge\", " ++
            "\"description\": " ++
            "\"Concatenate words " ++
            "into compound\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy construct:phonosym " ++
            "--input sharp --count 5\", " ++
            "\"description\": " ++
            "\"Generate sharp-sounding " ++
            "constructed words\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy construct:affix " ++
            "--input quill\", " ++
            "\"description\": " ++
            "\"Add prefix or suffix " ++
            "to a word\"},\n" ++
            "        {\"command\": " ++
            "\"nomen generate " ++
            "--strategy construct:acronym " ++
            "--input spell,practice,app\", " ++
            "\"description\": " ++
            "\"Create pronounceable acronym\"}\n" ++
            "      ],\n" ++
            "      \"mutates\": false,\n" ++
            "      \"destructive\": false,\n" ++
            "      \"idempotent\": true\n" ++
            "    },\n" ++
            "    {\n" ++
            "      \"name\": \"categories\",\n" ++
            "      \"description\": " ++
            "\"List available " ++
            "word list categories\",\n" ++
            "      \"flags\": [\n" ++
            "        {\"name\": \"--format\"," ++
            " \"type\": \"string\", " ++
            "\"enum\": " ++
            "[\"json\",\"jsonl\",\"human\"]," ++
            " \"description\": " ++
            "\"Output format\"}\n" ++
            "      ],\n" ++
            "      \"examples\": [\n" ++
            "        {\"command\": " ++
            "\"nomen categories\", " ++
            "\"description\": " ++
            "\"List all categories\"},\n" ++
            "        {\"command\": " ++
            "\"nomen categories " ++
            "--format json\", " ++
            "\"description\": " ++
            "\"List as JSON array\"}\n" ++
            "      ],\n" ++
            "      \"mutates\": false,\n" ++
            "      \"destructive\": false,\n" ++
            "      \"idempotent\": true\n" ++
            "    },\n" ++
            "    {\n" ++
            "      \"name\": \"serve\",\n" ++
            "      \"description\": " ++
            "\"Start HTTP API server\",\n" ++
            "      \"flags\": [\n" ++
            "        {\"name\": \"--port\"," ++
            " \"type\": \"integer\", " ++
            "\"default\": 8080, " ++
            "\"description\": " ++
            "\"Port to listen on\"}\n" ++
            "      ],\n" ++
            "      \"examples\": [\n" ++
            "        {\"command\": " ++
            "\"nomen serve\", " ++
            "\"description\": " ++
            "\"Start server on port 8080\"},\n" ++
            "        {\"command\": " ++
            "\"nomen serve --port 3000\", " ++
            "\"description\": " ++
            "\"Start on custom port\"}\n" ++
            "      ],\n" ++
            "      \"mutates\": false,\n" ++
            "      \"destructive\": false,\n" ++
            "      \"idempotent\": true\n" ++
            "    }\n" ++
            "  ]\n" ++
            "}\n",
    );
}

test "parse generate command" {
    const args = [_][]const u8{ "generate", "--count", "5", "--category", "mountains" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| {
            try std.testing.expectEqual(@as(u32, 5), opts.count);
            try std.testing.expectEqual(Category.mountains, opts.category.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parse generate defaults" {
    const args = [_][]const u8{"generate"};
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| {
            try std.testing.expectEqual(@as(u32, 1), opts.count);
            try std.testing.expect(opts.category == null);
            try std.testing.expect(opts.seed == null);
        },
        else => try std.testing.expect(false),
    }
}

test "parse help" {
    const args = [_][]const u8{"--help"};
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .help);
}

test "parse version" {
    const args = [_][]const u8{"--version"};
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .version);
}

test "parse categories" {
    const args = [_][]const u8{"categories"};
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .categories);
}

test "parse generate help" {
    const args = [_][]const u8{ "generate", "--help" };
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .generate_help);
}

test "parse categories help" {
    const args = [_][]const u8{ "categories", "--help" };
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .categories_help);
}

test "parse categories help with json" {
    const args = [_][]const u8{ "categories", "--help", "--format", "json" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .categories_help => |h| try std.testing.expectEqual(OutputFormat.json, h.format.?),
        else => try std.testing.expect(false),
    }
}

test "parse serve help" {
    const args = [_][]const u8{ "serve", "--help" };
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .serve_help);
}

test "parse serve help with json" {
    const args = [_][]const u8{ "serve", "--help", "--format", "json" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .serve_help => |h| try std.testing.expectEqual(OutputFormat.json, h.format.?),
        else => try std.testing.expect(false),
    }
}

test "parse generate help with format" {
    const args = [_][]const u8{ "generate", "--help", "--format", "json" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate_help => |h| try std.testing.expectEqual(OutputFormat.json, h.format.?),
        else => try std.testing.expect(false),
    }
}

test "parse unknown subcommand" {
    const args = [_][]const u8{"unknown"};
    const result = parseArgs(&args);
    try std.testing.expectError(error.UnknownSubcommand, result);
}

test "parse invalid category" {
    const args = [_][]const u8{ "generate", "--category", "invalid" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.InvalidCategory, result);
}

test "parse zero count" {
    const args = [_][]const u8{ "generate", "--count", "0" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.InvalidCount, result);
}

test "parse dry-run" {
    const args = [_][]const u8{ "generate", "--dry-run" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| try std.testing.expect(opts.dry_run),
        else => try std.testing.expect(false),
    }
}

test "parse --json shorthand" {
    const args = [_][]const u8{ "generate", "--json" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| try std.testing.expectEqual(OutputFormat.json, opts.format.?),
        else => try std.testing.expect(false),
    }
}

test "parse no args shows help" {
    const args: [0][]const u8 = .{};
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .help);
}

test "parse seed" {
    const args = [_][]const u8{ "generate", "--seed", "42" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .generate => |opts| try std.testing.expectEqual(@as(u64, 42), opts.seed.?),
        else => try std.testing.expect(false),
    }
}

test "parse llms" {
    const args = [_][]const u8{"--llms"};
    const cmd = try parseArgs(&args);
    try std.testing.expect(cmd == .llms);
}

test "parse serve" {
    const args = [_][]const u8{"serve"};
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .serve => |opts| try std.testing.expectEqual(@as(u16, 8080), opts.port),
        else => try std.testing.expect(false),
    }
}

test "parse serve with port" {
    const args = [_][]const u8{ "serve", "--port", "3000" };
    const cmd = try parseArgs(&args);
    switch (cmd) {
        .serve => |opts| try std.testing.expectEqual(@as(u16, 3000), opts.port),
        else => try std.testing.expect(false),
    }
}

test "control chars rejected in flag values" {
    const args = [_][]const u8{ "generate", "--input", "ok\x01bad" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.ControlCharRejected, result);
}

test "categories rejects unknown flags" {
    const args = [_][]const u8{ "categories", "--bogus" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.UnknownFlag, result);
}

test "serve rejects unknown flags" {
    const args = [_][]const u8{ "serve", "--bogus" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.UnknownFlag, result);
}

test "categories rejects control chars in format value" {
    const args = [_][]const u8{ "categories", "--format", "jso\x01n" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.ControlCharRejected, result);
}

test "serve rejects control chars in format value" {
    const args = [_][]const u8{ "serve", "--format", "jso\x01n" };
    const result = parseArgs(&args);
    try std.testing.expectError(error.ControlCharRejected, result);
}

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
        },
        else => try std.testing.expect(false),
    }
}
