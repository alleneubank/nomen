const std = @import("std");
const types = @import("types.zig");
const Name = types.Name;
const OutputFormat = types.OutputFormat;
const StructuredError = types.StructuredError;

pub fn formatNames(writer: anytype, names: []const Name, format: OutputFormat, fields: ?[]const u8) !void {
    switch (format) {
        .json => try formatJson(writer, names, fields),
        .jsonl => try formatJsonl(writer, names, fields),
        .human => try formatHuman(writer, names),
    }
}

fn formatJson(writer: anytype, names: []const Name, fields: ?[]const u8) !void {
    if (names.len == 1 and fields == null) {
        try formatSingleJson(writer, names[0], fields);
        try writer.print("\n", .{});
        return;
    }
    try writer.print("[", .{});
    for (names, 0..) |name, i| {
        if (i > 0) try writer.print(",", .{});
        try formatSingleJson(writer, name, fields);
    }
    try writer.print("]\n", .{});
}

fn formatSingleJson(writer: anytype, name: Name, fields: ?[]const u8) !void {
    const show_value = shouldShowField("value", fields);
    const show_category = shouldShowField("category", fields);
    const show_strategy = shouldShowField("strategy", fields);

    try writer.print("{{", .{});
    var first = true;

    if (show_value) {
        try writer.print("\"value\":\"{s}\"", .{name.value});
        first = false;
    }
    if (show_category) {
        if (!first) try writer.print(",", .{});
        if (name.category) |cat| {
            try writer.print("\"category\":\"{s}\"", .{@tagName(cat)});
        } else {
            try writer.print("\"category\":null", .{});
        }
        first = false;
    }
    if (show_strategy) {
        if (!first) try writer.print(",", .{});
        try writer.print("\"strategy\":\"{s}\"", .{name.strategy_tag});
    }

    try writer.print("}}", .{});
}

fn formatJsonl(writer: anytype, names: []const Name, fields: ?[]const u8) !void {
    for (names) |name| {
        try formatSingleJson(writer, name, fields);
        try writer.print("\n", .{});
    }
}

fn formatHuman(writer: anytype, names: []const Name) !void {
    for (names) |name| {
        try writer.print("{s}\n", .{name.value});
    }
}

pub fn formatDryRun(writer: anytype, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.print("{{\"dry_run\":true,\"valid\":true,\"message\":\"inputs valid, no names generated\"}}\n", .{});
        },
        .human => {
            try writer.print("dry-run: inputs valid, no names generated\n", .{});
        },
    }
}

pub fn formatError(writer: anytype, err: StructuredError, format: OutputFormat) !void {
    switch (format) {
        .json, .jsonl => {
            try writer.print("{{\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\"}}}}\n", .{ err.code, err.message });
        },
        .human => {
            try writer.print("error: {s}: {s}\n", .{ err.code, err.message });
        },
    }
}

pub fn formatCategories(writer: anytype, format: OutputFormat) !void {
    const categories = comptime std.enums.values(types.Category);
    switch (format) {
        .json => {
            try writer.print("[", .{});
            inline for (categories, 0..) |cat, i| {
                if (i > 0) try writer.print(",", .{});
                try writer.print("\"{s}\"", .{@tagName(cat)});
            }
            try writer.print("]\n", .{});
        },
        .jsonl => {
            inline for (categories) |cat| {
                try writer.print("\"{s}\"\n", .{@tagName(cat)});
            }
        },
        .human => {
            inline for (categories) |cat| {
                try writer.print("{s}\n", .{@tagName(cat)});
            }
        },
    }
}

fn shouldShowField(field: []const u8, fields: ?[]const u8) bool {
    const f = fields orelse return true;
    var iter = std.mem.splitScalar(u8, f, ',');
    while (iter.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (std.mem.eql(u8, trimmed, field)) return true;
    }
    return false;
}

test "formatHuman single name" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    const names = [_]Name{.{ .value = "denali", .category = .mountains, .strategy_tag = "thematic" }};
    try formatNames(writer, &names, .human, null);
    try std.testing.expectEqualStrings("denali\n", fbs.getWritten());
}

test "formatJson single name" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    const names = [_]Name{.{ .value = "denali", .category = .mountains, .strategy_tag = "thematic" }};
    try formatNames(writer, &names, .json, null);
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"value\":\"denali\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\":\"mountains\"") != null);
}

test "formatJson multiple names" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    const names = [_]Name{
        .{ .value = "denali", .category = .mountains, .strategy_tag = "thematic" },
        .{ .value = "rainier", .category = .mountains, .strategy_tag = "thematic" },
    };
    try formatNames(writer, &names, .json, null);
    const output = fbs.getWritten();
    try std.testing.expect(output[0] == '[');
    try std.testing.expect(output[output.len - 2] == ']');
}

test "formatJsonl" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    const names = [_]Name{
        .{ .value = "denali", .category = .mountains, .strategy_tag = "thematic" },
        .{ .value = "rainier", .category = .mountains, .strategy_tag = "thematic" },
    };
    try formatNames(writer, &names, .jsonl, null);
    const output = fbs.getWritten();
    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len > 0) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "field filtering" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    const names = [_]Name{.{ .value = "denali", .category = .mountains, .strategy_tag = "thematic" }};
    try formatNames(writer, &names, .json, "value");
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"value\":\"denali\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"category\"") == null);
}

test "formatError json" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    try formatError(writer, .{ .code = "INVALID_INPUT", .message = "bad input" }, .json);
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"code\":\"INVALID_INPUT\"") != null);
}

test "formatCategories json" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    try formatCategories(writer, .json);
    const output = fbs.getWritten();
    try std.testing.expect(output[0] == '[');
    try std.testing.expect(std.mem.indexOf(u8, output, "\"mountains\"") != null);
}
