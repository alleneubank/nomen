const std = @import("std");
const lib = @import("nomen");

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer: std.fs.File.Writer = .init(stdout_file, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const stderr_file = std.fs.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer: std.fs.File.Writer = .init(stderr_file, &stderr_buf);
    const stderr = &stderr_writer.interface;

    const all_args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, all_args);

    // Skip program name
    const args = if (all_args.len > 1) all_args[1..] else all_args[0..0];

    const cmd = lib.cli.parseArgs(args) catch |err| {
        // Pre-scan args for --format to respect user's format preference on errors
        const format = prescanFormat(args);
        try lib.format.formatError(stderr, .{
            .code = errorToCode(err),
            .message = errorToMessage(err),
        }, format);
        try stderr.flush();
        std.process.exit(2);
    };

    run(gpa, stdout, stderr, cmd) catch |err| {
        const format = prescanFormat(args);
        try lib.format.formatError(stderr, .{
            .code = runtimeErrorToCode(err),
            .message = runtimeErrorToMessage(err),
        }, format);
        try stderr.flush();
        std.process.exit(1);
    };

    try stdout.flush();
    try stderr.flush();
}

/// Pre-scan args for --format or --json to use the user's preferred format on errors.
fn prescanFormat(args: []const []const u8) lib.OutputFormat {
    for (args, 0..) |arg, i| {
        if ((std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) and i + 1 < args.len) {
            return lib.OutputFormat.fromString(args[i + 1]) catch lib.cli.resolveFormat(null);
        }
        if (std.mem.eql(u8, arg, "--json")) return .json;
    }
    return lib.cli.resolveFormat(null);
}

fn run(gpa: std.mem.Allocator, stdout: anytype, stderr: anytype, cmd: lib.types.CliCommand) !void {
    switch (cmd) {
        .help => |h| {
            const format = h.format orelse lib.cli.resolveFormat(null);
            try lib.cli.writeHelp(stdout, format);
        },
        .version => try stdout.print("nomen {s}\n", .{lib.version}),
        .llms => try lib.cli.writeLlmsManifest(stdout, lib.version),
        .categories => |opts| {
            const format = opts.format orelse lib.cli.resolveFormat(null);
            try lib.format.formatCategories(stdout, format);
        },
        .generate_help => |h| {
            const format = h.format orelse lib.cli.resolveFormat(null);
            try lib.cli.writeGenerateHelp(stdout, format);
        },
        .categories_help => |h| {
            const format = h.format orelse lib.cli.resolveFormat(null);
            try lib.cli.writeCategoriesHelp(stdout, format);
        },
        .serve_help => |h| {
            const format = h.format orelse lib.cli.resolveFormat(null);
            try lib.cli.writeServeHelp(stdout, format);
        },
        .serve => |opts| {
            try stderr.print("nomen server starting on port {d}...\n", .{opts.port});
            try stderr.flush();
            try lib.server.run(gpa, opts.port);
        },
        .generate => |opts| {
            if (opts.dry_run) {
                const format = opts.format orelse lib.cli.resolveFormat(null);
                try lib.format.formatDryRun(stdout, format);
                return;
            }

            var strategy = opts.strategy;
            if (opts.input) |input| {
                // --input is only valid with --strategy mnemonic
                if (strategy != .mnemonic) {
                    const format = opts.format orelse lib.cli.resolveFormat(null);
                    try lib.format.formatError(stderr, .{
                        .code = "INVALID_INPUT",
                        .message = "--input is only valid with --strategy mnemonic",
                    }, format);
                    try stderr.flush();
                    std.process.exit(2);
                }
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
            } else if (strategy == .mnemonic) {
                const format = opts.format orelse lib.cli.resolveFormat(null);
                try lib.format.formatError(stderr, .{
                    .code = "MISSING_VALUE",
                    .message = "--strategy mnemonic requires --input <numeric/hex>",
                }, format);
                try stderr.flush();
                std.process.exit(2);
            }

            var gen = lib.Generator.init(opts.seed);
            const format = opts.format orelse lib.cli.resolveFormat(null);

            if (opts.count == 1) {
                const name = try gen.generate(strategy, opts.category);
                const names = [_]lib.Name{name};
                try lib.format.formatNames(stdout, &names, format, opts.fields);
            } else {
                const batch = try gen.generateBatch(gpa, opts.count, strategy, opts.category);
                defer batch.deinit(gpa);
                try lib.format.formatNames(stdout, batch.names, format, opts.fields);
            }
        },
    }
}

fn errorToCode(err: lib.types.ParseError) []const u8 {
    return switch (err) {
        error.InvalidCategory => "INVALID_CATEGORY",
        error.InvalidStrategy => "INVALID_STRATEGY",
        error.InvalidFormat => "INVALID_FORMAT",
        error.InvalidCount => "INVALID_COUNT",
        error.InvalidSeed => "INVALID_SEED",
        error.InvalidInput => "INVALID_INPUT",
        error.ControlCharRejected => "CONTROL_CHAR_REJECTED",
        error.UnknownFlag => "UNKNOWN_FLAG",
        error.MissingValue => "MISSING_VALUE",
        error.UnknownSubcommand => "UNKNOWN_SUBCOMMAND",
    };
}

fn errorToMessage(err: lib.types.ParseError) []const u8 {
    return switch (err) {
        error.InvalidCategory => "invalid category name, use 'nomen categories' to list",
        error.InvalidStrategy => "invalid strategy, options: thematic, phrase, phrase:adjective_noun, phrase:noun_noun, phrase:verb_noun, phrase:alliterative, triple, mnemonic",
        error.InvalidFormat => "invalid format, options: json, jsonl, human",
        error.InvalidCount => "count must be a positive integer",
        error.InvalidSeed => "seed must be a non-negative integer",
        error.InvalidInput => "invalid input",
        error.ControlCharRejected => "input contains control characters",
        error.UnknownFlag => "unknown flag, use --help for usage",
        error.MissingValue => "flag requires a value",
        error.UnknownSubcommand => "unknown subcommand, use --help for usage",
    };
}

fn runtimeErrorToCode(err: anyerror) []const u8 {
    return switch (err) {
        error.EmptyWordList => "EMPTY_WORD_LIST",
        error.NoDistinctNames => "NO_DISTINCT_NAMES",
        error.BindFailed => "BIND_FAILED",
        else => "INTERNAL_ERROR",
    };
}

fn runtimeErrorToMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.EmptyWordList => "no words available for this category/strategy",
        error.NoDistinctNames => "cannot generate enough phonetically distinct names, reduce count or omit category",
        error.BindFailed => "failed to bind server to port",
        else => "unexpected error",
    };
}

test "library import" {
    try std.testing.expectEqualStrings("0.1.0", lib.version);
}
