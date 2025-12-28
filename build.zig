const std = @import("std");

fn compileRego(b: *std.Build, policy_path: []const u8, entrypoints: []const []const u8) std.Build.LazyPath {
    const opa_build = b.addSystemCommand(&.{ "opa", "build", "-t", "wasm" });
    for (entrypoints) |ep| {
        opa_build.addArgs(&.{ "-e", ep });
    }
    opa_build.addArg("-o");
    const opa_bundle = opa_build.addOutputFileArg("bundle.tar.gz");
    opa_build.addFileArg(b.path(policy_path));

    const extract_wasm = b.addSystemCommand(&.{ "tar", "-xzf" });
    extract_wasm.addFileArg(opa_bundle);
    extract_wasm.addArgs(&.{ "-O", "/policy.wasm" });
    extract_wasm.step.dependOn(&opa_build.step);

    return extract_wasm.captureStdOut();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasmer_dep = b.dependency("wasmer_zig_api", .{
        .target = target,
        .optimize = optimize,
    });
    const mvzr_dep = b.dependency("mvzr", .{
        .target = target,
        .optimize = optimize,
    });
    const zig_yaml_dep = b.dependency("zig_yaml", .{
        .target = target,
        .optimize = optimize,
    });
    const zul_dep = b.dependency("zul", .{
        .target = target,
        .optimize = optimize,
    });
    const humanize_dep = b.dependency("zig_humanize", .{
        .target = target,
        .optimize = optimize,
    });
    const example_wasm = compileRego(b, "policies/example.rego", &.{"example/allow"});
    const builtin_test_wasm = compileRego(b, "policies/builtin_test.rego", &.{ "builtin_test/allow", "builtin_test/result" });

    const lib_mod = b.addModule("zig_opa_wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wasmer", .module = wasmer_dep.module("wasmer") },
            .{ .name = "mvzr", .module = mvzr_dep.module("mvzr") },
            .{ .name = "yaml", .module = zig_yaml_dep.module("yaml") },
            .{ .name = "zul", .module = zul_dep.module("zul") },
            .{ .name = "humanize", .module = humanize_dep.module("humanize") },
        },
    });
    lib_mod.addAnonymousImport("test_add_wasm", .{
        .root_source_file = b.path("tests/wasm/add.wasm"),
    });
    lib_mod.addAnonymousImport("test_example_wasm", .{
        .root_source_file = example_wasm,
    });
    lib_mod.addAnonymousImport("test_builtin_wasm", .{
        .root_source_file = builtin_test_wasm,
    });

    const exe = b.addExecutable(.{
        .name = "opa-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_opa_wasm", .module = lib_mod },
                .{ .name = "wasmer", .module = wasmer_dep.module("wasmer") },
            },
        }),
    });

    exe.linkLibC();
    if (b.graph.env_map.get("WASMER_DIR")) |wasmer_dir| {
        exe.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{wasmer_dir}) });
    }
    exe.linkSystemLibrary("wasmer");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the CLI");
    run_step.dependOn(&run_cmd.step);

    const bench_cmd = b.addRunArtifact(exe);
    bench_cmd.step.dependOn(b.getInstallStep());
    bench_cmd.addArgs(&.{ "bench", "-e", "example/allow", "-i", "{}" });
    bench_cmd.addArg("-m");
    bench_cmd.addFileArg(example_wasm);

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    lib_tests.linkLibC();
    if (b.graph.env_map.get("WASMER_DIR")) |wasmer_dir| {
        lib_tests.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{wasmer_dir}) });
    }
    lib_tests.linkSystemLibrary("wasmer");

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);

    const examples = [_][]const u8{
        "simple_eval",
        "with_data",
        "typed_eval",
        "instance_pool",
        "bundle_loading",
    };
    for (examples) |example_name| {
        const example_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_opa_wasm", .module = lib_mod },
                .{ .name = "wasmer", .module = wasmer_dep.module("wasmer") },
            },
        });
        example_mod.addAnonymousImport("example_policy", .{ .root_source_file = example_wasm });
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = example_mod,
        });
        example.linkLibC();
        if (b.graph.env_map.get("WASMER_DIR")) |wasmer_dir| {
            example.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{wasmer_dir}) });
        }
        example.linkSystemLibrary("wasmer");

        const install_example = b.addInstallArtifact(example, .{});
        const example_step = b.step(example_name, b.fmt("Build {s} example", .{example_name}));
        example_step.dependOn(&install_example.step);
    }
}
