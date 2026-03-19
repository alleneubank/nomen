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
    var opts = GenerateOptions{};
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
            try writer.print(
                \\{{"name":"nomen","description":"Categorical name generator","commands":["generate","categories","serve"],"flags":["--help","--version","--llms"]}}
                \\
            , .{});
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
            try writer.print(
                \\{{"name":"generate","description":"Generate names from themed word lists","flags":[
                \\{{"name":"--count","short":"-n","type":"integer","default":1,"description":"Number of names"}},
                \\{{"name":"--category","short":"-c","type":"string","enum":["mountains","rivers","deserts","canyons","islands","passes","moons","raptors","minerals","norse","volcanoes","forests","oceans","storms"],"description":"Word list category"}},
                \\{{"name":"--strategy","short":"-s","type":"string","enum":["thematic","phrase","phrase:adjective_noun","phrase:noun_noun","phrase:verb_noun","phrase:alliterative","triple","mnemonic"],"default":"thematic","description":"Generation strategy"}},
                \\{{"name":"--seed","type":"integer","description":"Seed for deterministic output"}},
                \\{{"name":"--input","short":"-i","type":"string","description":"Input for mnemonic strategy"}},
                \\{{"name":"--format","short":"-f","type":"string","enum":["json","jsonl","human"],"description":"Output format"}},
                \\{{"name":"--fields","type":"string","description":"Comma-separated output fields"}},
                \\{{"name":"--dry-run","type":"boolean","description":"Validate without generating"}}
                \\]}}
                \\
            , .{});
        },
        .human => {
            try writer.print(
                \\nomen generate — generate names
                \\
                \\Usage: nomen generate [options]
                \\
                \\Options:
                \\  --count, -n <N>         Number of names (default: 1)
                \\  --category, -c <NAME>   Restrict to category
                \\  --strategy, -s <NAME>   Strategy: thematic, phrase[:pattern], triple, mnemonic (default: thematic)
                \\  --seed <N>              Seed for deterministic output
                \\  --input, -i <TEXT>      Input for mnemonic strategy (numeric/hex)
                \\  --format, -f <FMT>      Output format: json, jsonl, human
                \\  --json                  Shorthand for --format json
                \\  --fields <FIELDS>       Comma-separated fields to include
                \\  --dry-run               Validate inputs without generating
                \\  --help, -h              Show this help
                \\
                \\Categories: mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse, volcanoes, forests, oceans, storms
                \\
            , .{});
        },
    }
}

pub fn writeCategoriesHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.print(
                \\{{"name":"categories","description":"List available word list categories","flags":[
                \\{{"name":"--format","short":"-f","type":"string","enum":["json","jsonl","human"],"description":"Output format"}},
                \\{{"name":"--json","type":"boolean","description":"Shorthand for --format json"}}
                \\]}}
                \\
            , .{});
        },
        .human => {
            try writer.print(
                \\nomen categories — list available word list categories
                \\
                \\Usage: nomen categories [options]
                \\
                \\Options:
                \\  --format, -f <FMT>  Output format: json, jsonl, human
                \\  --json              Shorthand for --format json
                \\  --help, -h          Show this help
                \\
            , .{});
        },
    }
}

pub fn writeServeHelp(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.print(
                \\{{"name":"serve","description":"Start HTTP API server","flags":[
                \\{{"name":"--port","short":"-p","type":"integer","default":8080,"description":"Port to listen on"}}
                \\],"endpoints":[
                \\{{"path":"/generate","method":"GET","description":"Generate names (query params: count, category, strategy, seed, input, fields)"}},
                \\{{"path":"/categories","method":"GET","description":"List categories"}},
                \\{{"path":"/health","method":"GET","description":"Health check"}}
                \\]}}
                \\
            , .{});
        },
        .human => {
            try writer.print(
                \\nomen serve — start HTTP API server
                \\
                \\Usage: nomen serve [options]
                \\
                \\Options:
                \\  --port, -p <N>  Port to listen on (default: 8080)
                \\  --help, -h      Show this help
                \\
                \\Endpoints:
                \\  GET /generate     Generate names (query: count, category, strategy, seed, input, fields)
                \\  GET /categories   List available categories
                \\  GET /health       Health check
                \\
            , .{});
        },
    }
}

pub fn writeLlmsManifest(writer: anytype, version_str: []const u8) !void {
    try writer.print(
        \\{{
        \\  "name": "nomen",
        \\  "version": "{s}",
        \\  "description": "Categorical name generator for memorable, themed names",
        \\  "commands": [
        \\    {{
        \\      "name": "generate",
        \\      "description": "Generate names from themed word lists",
        \\      "flags": [
        \\        {{"name": "--count", "type": "integer", "default": 1, "description": "Number of names to generate"}},
        \\        {{"name": "--category", "type": "string", "enum": ["mountains","rivers","deserts","canyons","islands","passes","moons","raptors","minerals","norse","volcanoes","forests","oceans","storms"], "description": "Word list category"}},
        \\        {{"name": "--strategy", "type": "string", "enum": ["thematic","phrase","phrase:adjective_noun","phrase:noun_noun","phrase:verb_noun","phrase:alliterative","triple","mnemonic"], "default": "thematic", "description": "Generation strategy"}},
        \\        {{"name": "--seed", "type": "integer", "description": "Seed for deterministic output"}},
        \\        {{"name": "--input", "type": "string", "description": "Input for mnemonic encoding"}},
        \\        {{"name": "--format", "type": "string", "enum": ["json","jsonl","human"], "description": "Output format"}},
        \\        {{"name": "--fields", "type": "string", "description": "Comma-separated output fields"}},
        \\        {{"name": "--dry-run", "type": "boolean", "description": "Validate without generating"}}
        \\      ],
        \\      "examples": [
        \\        {{"command": "nomen generate", "description": "Generate one name"}},
        \\        {{"command": "nomen generate --count 5 --category rivers", "description": "Five river names"}},
        \\        {{"command": "nomen generate --strategy phrase --format json", "description": "Two-word phrase as JSON"}},
        \\        {{"command": "nomen generate --seed 42 --format json", "description": "Deterministic JSON output"}},
        \\        {{"command": "nomen generate --strategy mnemonic --input 0xdeadbeef", "description": "Mnemonic encoding"}}
        \\      ],
        \\      "mutates": false,
        \\      "destructive": false,
        \\      "idempotent": true
        \\    }},
        \\    {{
        \\      "name": "categories",
        \\      "description": "List available word list categories",
        \\      "flags": [
        \\        {{"name": "--format", "type": "string", "enum": ["json","jsonl","human"], "description": "Output format"}}
        \\      ],
        \\      "examples": [
        \\        {{"command": "nomen categories", "description": "List all categories"}},
        \\        {{"command": "nomen categories --format json", "description": "List as JSON array"}}
        \\      ],
        \\      "mutates": false,
        \\      "destructive": false,
        \\      "idempotent": true
        \\    }},
        \\    {{
        \\      "name": "serve",
        \\      "description": "Start HTTP API server",
        \\      "flags": [
        \\        {{"name": "--port", "type": "integer", "default": 8080, "description": "Port to listen on"}}
        \\      ],
        \\      "examples": [
        \\        {{"command": "nomen serve", "description": "Start server on port 8080"}},
        \\        {{"command": "nomen serve --port 3000", "description": "Start on custom port"}}
        \\      ],
        \\      "mutates": false,
        \\      "destructive": false,
        \\      "idempotent": true
        \\    }}
        \\  ]
        \\}}
        \\
    , .{version_str});
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
    const args = [_][]const u8{};
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
