const std = @import("std");
const types = @import("types.zig");
const generator_mod = @import("generator.zig");
const format_mod = @import("format.zig");
const Generator = generator_mod.Generator;
const Name = types.Name;
const Category = types.Category;
const Strategy = types.Strategy;

const construct_mod = @import("construct.zig");
const log = std.log.scoped(.server);

const json_header = [_]std.http.Header{.{ .name = "content-type", .value = "application/json" }};

pub const ServerError = error{
    BindFailed,
};

pub fn run(allocator: std.mem.Allocator, port: u16) !void {
    const address = std.net.Address.parseIp4("127.0.0.1", port) catch return error.BindFailed;
    var net_server = address.listen(.{
        .reuse_address = true,
    }) catch return error.BindFailed;
    defer net_server.deinit();

    log.info("listening on 127.0.0.1:{d}", .{port});

    while (true) {
        const conn = net_server.accept() catch |err| {
            log.err("accept error: {}", .{err});
            continue;
        };
        handleConnection(allocator, conn) catch |err| {
            log.err("connection error: {}", .{err});
        };
    }
}

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection) !void {
    defer conn.stream.close();

    var read_buf: [4096]u8 = undefined;
    var net_reader: std.net.Stream.Reader = .init(conn.stream, &read_buf);
    const reader = net_reader.interface();

    var write_buf: [8192]u8 = undefined;
    var net_writer: std.net.Stream.Writer = .init(conn.stream, &write_buf);
    const writer = &net_writer.interface;

    var http_server = std.http.Server.init(reader, writer);

    var request = http_server.receiveHead() catch return;

    // Reject non-GET methods
    if (request.head.method != .GET) {
        request.respond(
            "{\"error\":{\"code\":\"METHOD_NOT_ALLOWED\",\"message\":\"only GET is supported\"}}\n",
            .{
                .status = .method_not_allowed,
                .extra_headers = &json_header,
                .keep_alive = false,
            },
        ) catch return;
        return;
    }

    const target = request.head.target;
    const path = if (std.mem.indexOf(u8, target, "?")) |qi| target[0..qi] else target;

    if (std.mem.eql(u8, path, "/health")) {
        try request.respond("{\"status\":\"ok\"}\n", .{ .extra_headers = &json_header });
    } else if (std.mem.eql(u8, path, "/categories")) {
        var body_buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&body_buf);
        try format_mod.formatCategories(fbs.writer(), .json);
        try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
    } else if (std.mem.eql(u8, path, "/generate")) {
        handleGenerate(allocator, &request, target) catch |err| {
            log.err("/generate error: {}", .{err});
        };
    } else {
        try request.respond(
            "{\"error\":{\"code\":\"NOT_FOUND\",\"message\":\"unknown endpoint\"}}\n",
            .{ .status = .not_found, .extra_headers = &json_header },
        );
    }
}

const QueryParams = struct {
    count: u32 = 1,
    category: ?Category = null,
    strategy: Strategy = .thematic,
    seed: ?u64 = null,
    fields: ?[]const u8 = null,
    dry_run: bool = false,
    err_code: ?[]const u8 = null,
    err_msg: ?[]const u8 = null,
    construct_input: ?[]const u8 = null,
};

fn parseQueryParams(target: []const u8) QueryParams {
    var result: QueryParams = .{};

    const qi = std.mem.indexOf(u8, target, "?") orelse return result;
    const query = target[qi + 1 ..];
    var params = std.mem.splitScalar(u8, query, '&');

    var explicit_strategy = false;
    var mnemonic_input: ?[]const u8 = null;

    while (params.next()) |param| {
        if (param.len == 0) continue;
        const ei = std.mem.indexOf(u8, param, "=") orelse {
            result.err_code = "INVALID_PARAMETER";
            result.err_msg = "malformed query parameter, expected key=value";
            return result;
        };
        const key = param[0..ei];
        const val = param[ei + 1 ..];

        if (std.mem.eql(u8, key, "count")) {
            const parsed = std.fmt.parseInt(u32, val, 10) catch {
                result.err_code = "INVALID_COUNT";
                result.err_msg = "count must be a positive integer";
                return result;
            };
            if (parsed == 0) {
                result.err_code = "INVALID_COUNT";
                result.err_msg = "count must be a positive integer";
                return result;
            }
            result.count = parsed;
        } else if (std.mem.eql(u8, key, "category")) {
            result.category = Category.fromString(val) catch {
                result.err_code = "INVALID_CATEGORY";
                result.err_msg = "invalid category name";
                return result;
            };
        } else if (std.mem.eql(u8, key, "strategy")) {
            result.strategy = Strategy.fromString(val) catch {
                result.err_code = "INVALID_STRATEGY";
                result.err_msg =
                    "invalid strategy, options: thematic, phrase, " ++
                    "phrase:adjective_noun, phrase:noun_noun, phrase:verb_noun, " ++
                    "phrase:alliterative, triple, mnemonic, construct, " ++
                    "construct:portmanteau, construct:compound, construct:clip, " ++
                    "construct:affix, construct:backform, construct:phonosym, " ++
                    "construct:acronym";
                return result;
            };
            explicit_strategy = true;
        } else if (std.mem.eql(u8, key, "seed")) {
            result.seed = std.fmt.parseInt(u64, val, 10) catch {
                result.err_code = "INVALID_SEED";
                result.err_msg = "seed must be a non-negative integer";
                return result;
            };
        } else if (std.mem.eql(u8, key, "input")) {
            mnemonic_input = val;
        } else if (std.mem.eql(u8, key, "fields")) {
            result.fields = val;
        } else if (std.mem.eql(u8, key, "dry-run") or std.mem.eql(u8, key, "dry_run")) {
            result.dry_run = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        } else {
            result.err_code = "UNKNOWN_PARAMETER";
            result.err_msg = "unknown query parameter";
            return result;
        }
    }

    // Cross-validate input and strategy
    if (mnemonic_input) |input| {
        if (result.strategy == .mnemonic or (!explicit_strategy)) {
            types.validateMnemonicInput(input) catch {
                result.err_code = "INVALID_INPUT";
                result.err_msg = "mnemonic input must be numeric or hex (e.g. 12345, 0xdeadbeef)";
                return result;
            };
            result.strategy = .{ .mnemonic = input };
        } else if (result.strategy == .construct) {
            types.validateConstructInput(input) catch {
                result.err_code = "INVALID_INPUT";
                result.err_msg = "construct input must be comma-separated lowercase words (max 5, each <= 20 chars)";
                return result;
            };
            result.construct_input = input;
        } else {
            result.err_code = "INVALID_INPUT";
            result.err_msg = "input parameter is only valid with strategy=mnemonic or strategy=construct:*";
            return result;
        }
    } else if (result.strategy == .mnemonic) {
        result.err_code = "MISSING_VALUE";
        result.err_msg = "strategy=mnemonic requires input parameter";
        return result;
    }

    return result;
}

fn handleGenerate(allocator: std.mem.Allocator, request: *std.http.Server.Request, target: []const u8) !void {
    const params = parseQueryParams(target);

    if (params.err_code) |code| {
        var err_buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&err_buf);
        try format_mod.formatError(fbs.writer(), .{
            .code = code,
            .message = params.err_msg orelse "invalid parameter",
        }, .json);
        try request.respond(fbs.getWritten(), .{
            .status = .bad_request,
            .extra_headers = &json_header,
        });
        return;
    }

    if (params.dry_run) {
        try request.respond(
            "{\"dry_run\":true,\"valid\":true,\"message\":\"inputs valid, no names generated\"}\n",
            .{ .extra_headers = &json_header },
        );
        return;
    }

    if (params.strategy == .construct) {
        var input_words_buf: [5][]const u8 = undefined;
        var input_word_count: usize = 0;
        if (params.construct_input) |input| {
            var iter = std.mem.splitScalar(u8, input, ',');
            while (iter.next()) |word| {
                if (input_word_count >= 5) break;
                input_words_buf[input_word_count] = word;
                input_word_count += 1;
            }
        }

        var construct_eng = construct_mod.ConstructEngine.init(params.seed);

        if (params.count == 1) {
            const input_words = input_words_buf[0..input_word_count];
            const name = construct_eng.generateConstruct(
                params.strategy.construct,
                params.category,
                input_words,
            ) catch |err| {
                return respondGenerateError(request, err);
            };
            var body_buf: [1024]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&body_buf);
            const names = [_]Name{name};
            try format_mod.formatNames(fbs.writer(), &names, .json, params.fields);
            try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
        } else {
            const input_words = input_words_buf[0..input_word_count];
            const batch = construct_eng.generateConstructBatch(
                allocator,
                params.count,
                params.strategy.construct,
                params.category,
                input_words,
            ) catch |err| {
                return respondGenerateError(request, err);
            };
            defer batch.deinit(allocator);
            var body_buf: [8192]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&body_buf);
            try format_mod.formatNames(fbs.writer(), batch.names, .json, params.fields);
            try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
        }
        return;
    }

    var gen = Generator.init(params.seed);

    if (params.count == 1) {
        const name = gen.generate(params.strategy, params.category) catch |err| {
            return respondGenerateError(request, err);
        };
        var body_buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&body_buf);
        const names = [_]Name{name};
        try format_mod.formatNames(fbs.writer(), &names, .json, params.fields);
        try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
    } else {
        const batch = gen.generateBatch(allocator, params.count, params.strategy, params.category) catch |err| {
            return respondGenerateError(request, err);
        };
        defer batch.deinit(allocator);

        var body_buf: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&body_buf);
        try format_mod.formatNames(fbs.writer(), batch.names, .json, params.fields);
        try request.respond(fbs.getWritten(), .{ .extra_headers = &json_header });
    }
}

fn respondGenerateError(request: *std.http.Server.Request, err: anyerror) !void {
    const code = switch (err) {
        error.EmptyWordList => "EMPTY_WORD_LIST",
        error.NoDistinctNames => "NO_DISTINCT_NAMES",
        error.ConstructionFailed => "CONSTRUCTION_FAILED",
        error.InvalidInput => "INVALID_INPUT",
        else => "INTERNAL_ERROR",
    };
    const msg = switch (err) {
        error.EmptyWordList => "no words available for this category",
        error.NoDistinctNames => "cannot generate enough phonetically distinct names, reduce count",
        error.ConstructionFailed => "construction algorithm produced no valid output",
        error.InvalidInput => "invalid input for strategy",
        else => "unexpected error",
    };
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try format_mod.formatError(fbs.writer(), .{ .code = code, .message = msg }, .json);
    try request.respond(fbs.getWritten(), .{
        .status = .bad_request,
        .extra_headers = &json_header,
    });
}

test "parseQueryParams valid" {
    const params = parseQueryParams("/generate?count=3&category=mountains&seed=42");
    try std.testing.expectEqual(@as(u32, 3), params.count);
    try std.testing.expectEqual(Category.mountains, params.category.?);
    try std.testing.expectEqual(@as(u64, 42), params.seed.?);
    try std.testing.expect(params.err_code == null);
}

test "parseQueryParams invalid category returns error" {
    const params = parseQueryParams("/generate?category=nope");
    try std.testing.expect(params.err_code != null);
    try std.testing.expectEqualStrings("INVALID_CATEGORY", params.err_code.?);
}

test "parseQueryParams invalid count returns error" {
    const params = parseQueryParams("/generate?count=0");
    try std.testing.expect(params.err_code != null);
    try std.testing.expectEqualStrings("INVALID_COUNT", params.err_code.?);
}

test "parseQueryParams fields" {
    const params = parseQueryParams("/generate?fields=value");
    try std.testing.expectEqualStrings("value", params.fields.?);
}

test "parseQueryParams invalid seed returns error" {
    const params = parseQueryParams("/generate?seed=abc");
    try std.testing.expect(params.err_code != null);
    try std.testing.expectEqualStrings("INVALID_SEED", params.err_code.?);
}

test "parseQueryParams construct strategy" {
    const params = parseQueryParams("/generate?strategy=construct:portmanteau&input=spell,master");
    try std.testing.expect(params.err_code == null);
    try std.testing.expect(params.strategy == .construct);
    try std.testing.expectEqualStrings("spell,master", params.construct_input.?);
}

test "parseQueryParams construct invalid technique" {
    const params = parseQueryParams("/generate?strategy=construct:bogus");
    try std.testing.expect(params.err_code != null);
    try std.testing.expectEqualStrings("INVALID_STRATEGY", params.err_code.?);
}
