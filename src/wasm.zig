//! Freestanding WASM entry for the nomen playground.
//! Callers pass every seed; this target has no getrandom.

const std = @import("std");
const types = @import("types.zig");
const generator_mod = @import("generator.zig");
const construct_mod = @import("construct.zig");
const format_mod = @import("format.zig");

const Generator = generator_mod.Generator;
const ConstructEngine = construct_mod.ConstructEngine;
const Name = types.Name;
const Strategy = types.Strategy;
const Category = types.Category;

pub const err_invalid_strategy: i32 = -1;
pub const err_invalid_category: i32 = -2;
pub const err_invalid_input: i32 = -3;
pub const err_generate: i32 = -4;
pub const err_no_distinct: i32 = -5;
pub const err_construction: i32 = -6;
pub const err_missing_input: i32 = -7;
pub const err_invalid_count: i32 = -8;
pub const err_truncated: i32 = -9;

const max_count: u32 = 16;
const max_input_words = 5;

var strategy_buf: [64]u8 = undefined;
var category_buf: [32]u8 = undefined;
var input_buf: [160]u8 = undefined;
var out_buf: [8192]u8 = undefined;
var arena_mem: [64 * 1024]u8 = undefined;

export fn nomenStrategyPtr() [*]u8 {
    return &strategy_buf;
}

export fn nomenCategoryPtr() [*]u8 {
    return &category_buf;
}

export fn nomenInputPtr() [*]u8 {
    return &input_buf;
}

export fn nomenOutPtr() [*]u8 {
    return &out_buf;
}

export fn nomenStrategyCap() u32 {
    return strategy_buf.len;
}

export fn nomenCategoryCap() u32 {
    return category_buf.len;
}

export fn nomenInputCap() u32 {
    return input_buf.len;
}

export fn nomenOutCap() u32 {
    return out_buf.len;
}

export fn nomenGenerate(
    strategy_len: u32,
    category_len: u32,
    input_len: u32,
    count: u32,
    seed_lo: u32,
    seed_hi: u32,
) i32 {
    if (count == 0 or count > max_count) return err_invalid_count;
    if (strategy_len > strategy_buf.len) return err_invalid_strategy;
    if (category_len > category_buf.len) return err_invalid_category;
    if (input_len > input_buf.len) return err_invalid_input;

    const strategy_str = strategy_buf[0..strategy_len];
    const category_str = category_buf[0..category_len];
    const input_str = input_buf[0..input_len];
    const seed: u64 = (@as(u64, seed_hi) << 32) | @as(u64, seed_lo);

    const strategy = Strategy.fromString(strategy_str) catch return err_invalid_strategy;

    var category: ?Category = null;
    if (category_len > 0) {
        category = Category.fromString(category_str) catch return err_invalid_category;
    }

    var fba = std.heap.FixedBufferAllocator.init(&arena_mem);
    const allocator = fba.allocator();

    if (strategy == .construct) {
        if (input_len > 0) {
            types.validateConstructInput(input_str) catch return err_invalid_input;
        }
        var words_buf: [max_input_words][]const u8 = undefined;
        const words = splitInput(input_str, &words_buf);
        var engine = ConstructEngine.init(seed);
        if (count == 1) {
            const name = engine.generateConstruct(strategy.construct, category, words) catch |err| switch (err) {
                error.InvalidInput => return err_invalid_input,
                error.ConstructionFailed => return err_construction,
                error.EmptyWordList, error.NoDistinctNames => return err_generate,
                else => return err_generate,
            };
            const names = [_]Name{name};
            return writeJson(&names);
        }
        const batch = engine.generateConstructBatch(
            allocator,
            count,
            strategy.construct,
            category,
            words,
        ) catch |err| switch (err) {
            error.InvalidInput => return err_invalid_input,
            error.NoDistinctNames => return err_no_distinct,
            error.ConstructionFailed => return err_construction,
            else => return err_generate,
        };
        return writeJson(batch.names);
    }

    var resolved = strategy;
    if (resolved == .mnemonic) {
        if (input_len == 0) return err_missing_input;
        types.validateMnemonicInput(input_str) catch return err_invalid_input;
        resolved = .{ .mnemonic = input_str };
    } else if (input_len > 0) {
        return err_invalid_input;
    }

    var gen = Generator.init(seed);
    if (count == 1) {
        const name = gen.generate(resolved, category) catch return err_generate;
        const names = [_]Name{name};
        return writeJson(&names);
    }
    const batch = gen.generateBatch(allocator, count, resolved, category) catch |err| switch (err) {
        error.EmptyWordList => return err_generate,
        error.NoDistinctNames => return err_no_distinct,
        error.ConstructionFailed => return err_construction,
        error.OutOfMemory => return err_generate,
    };
    return writeJson(batch.names);
}

fn splitInput(input: []const u8, words_buf: *[max_input_words][]const u8) []const []const u8 {
    if (input.len == 0) return words_buf[0..0];
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, input, ',');
    while (it.next()) |word| {
        if (n >= words_buf.len) break;
        words_buf[n] = word;
        n += 1;
    }
    return words_buf[0..n];
}

fn writeJson(names: []const Name) i32 {
    var fbs = std.io.fixedBufferStream(&out_buf);
    format_mod.formatNames(fbs.writer(), names, .json, null) catch return err_truncated;
    const written = fbs.getWritten();
    if (written.len > std.math.maxInt(i32)) return err_truncated;
    return @intCast(written.len);
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}
