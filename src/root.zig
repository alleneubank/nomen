//! nomen — categorical name generator.
//!
//! CLI + API for generating memorable, themed names for devices,
//! projects, and resources.

const std = @import("std");

pub const version = "0.1.0";

pub const types = @import("types.zig");
pub const worddata = @import("worddata.zig");
pub const constructdata = @import("constructdata.zig");
pub const generator = @import("generator.zig");
pub const format = @import("format.zig");
pub const cli = @import("cli.zig");
pub const server = @import("server.zig");

pub const Category = types.Category;
pub const Strategy = types.Strategy;
pub const Name = types.Name;
pub const OutputFormat = types.OutputFormat;
pub const Generator = generator.Generator;
pub const BatchResult = generator.BatchResult;

test {
    std.testing.refAllDecls(@This());
}
