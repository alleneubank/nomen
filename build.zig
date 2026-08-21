const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module (exposed to package consumers)
    const mod = b.addModule("nomen", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Executable
    const exe = b.addExecutable(.{
        .name = "nomen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nomen", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Tests
    const test_step = b.step("test", "Run unit tests");

    const mod_tests = b.addTest(.{ .root_module = mod });
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    // Documentation
    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = mod_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // Format check
    const fmt_step = b.step("fmt", "Check source formatting");
    const fmt = b.addFmt(.{ .paths = &.{ "src", "build.zig" } });
    fmt_step.dependOn(&fmt.step);

    // Playground WASM (wasm32-freestanding, no WASI)
    const wasm = b.addExecutable(.{
        .name = "nomen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseSmall,
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    const wasm_step = b.step("wasm", "Build playground WASM into site/");
    const wasm_install = b.addInstallBinFile(wasm.getEmittedBin(), "nomen.wasm");
    wasm_step.dependOn(&wasm_install.step);

    const copy_wasm = b.addSystemCommand(&.{"cp"});
    copy_wasm.addFileArg(wasm.getEmittedBin());
    copy_wasm.addArg(b.pathFromRoot("site/nomen.wasm"));
    wasm_step.dependOn(&copy_wasm.step);
}
