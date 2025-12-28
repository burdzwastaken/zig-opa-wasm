//! Bench command - benchmarks OPA policy evaluation performance.

const std = @import("std");
const opa = @import("zig_opa_wasm");
const bundle = opa.bundle;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout = std.fs.File.stdout();

    var module_path: ?[]const u8 = null;
    var entrypoint: ?[]const u8 = null;
    var input: []const u8 = "{}";
    var data: ?[]const u8 = null;
    var iterations: u32 = 1000;
    var warmup: u32 = 100;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--module")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            module_path = args[i];
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--entrypoint")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            entrypoint = args[i];
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            input = args[i];
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--data")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            data = args[i];
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--iterations")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            iterations = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warmup")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            warmup = std.fmt.parseInt(u32, args[i], 10) catch return error.InvalidNumber;
        }
    }

    if (module_path == null) {
        try stdout.writeAll("error: --module is required\n");
        return error.MissingModule;
    }
    if (entrypoint == null) {
        try stdout.writeAll("error: --entrypoint is required\n");
        return error.MissingEntrypoint;
    }

    const file_bytes = std.fs.cwd().readFileAlloc(allocator, module_path.?, 50 * 1024 * 1024) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: failed to read module: {}\n", .{err}) catch "error: failed to read module\n";
        try stdout.writeAll(msg);
        return err;
    };
    defer allocator.free(file_bytes);

    const is_bundle = std.mem.endsWith(u8, module_path.?, ".tar.gz") or std.mem.endsWith(u8, module_path.?, ".tgz");
    var loaded_bundle: ?bundle.Bundle = null;
    defer if (loaded_bundle) |*b| b.deinit();

    const wasm_bytes = if (is_bundle) blk: {
        loaded_bundle = bundle.fromBytes(allocator, file_bytes) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "error: failed to load bundle: {}\n", .{err}) catch "error: failed to load bundle\n";
            try stdout.writeAll(msg);
            return err;
        };
        break :blk loaded_bundle.?.wasm;
    } else file_bytes;

    var wasmer_backend = try opa.WasmerBackend.init(allocator);
    var backend = wasmer_backend.asBackend();

    var policy = opa.Policy.load(allocator, &backend, wasm_bytes) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: failed to load policy: {}\n", .{err}) catch "error: failed to load policy\n";
        try stdout.writeAll(msg);
        return err;
    };
    defer policy.deinit();

    var instance = opa.Instance.create(allocator, &policy) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: failed to create instance: {}\n", .{err}) catch "error: failed to create instance\n";
        try stdout.writeAll(msg);
        return err;
    };
    defer instance.deinit();

    const effective_data = data orelse if (loaded_bundle) |b| b.data else null;
    if (effective_data) |d| {
        try instance.setData(d);
    }

    var buf: [512]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "Benchmark: {s}\nIterations: {d}\nWarmup: {d}\n\n", .{ entrypoint.?, iterations, warmup }) catch "Benchmark\n";
    try stdout.writeAll(header);

    for (0..warmup) |_| {
        const result = try instance.evaluate(entrypoint.?, input);
        allocator.free(result);
    }

    var times = try allocator.alloc(u64, iterations);
    defer allocator.free(times);

    var timer = try std.time.Timer.start();
    for (0..iterations) |iter| {
        timer.reset();
        const result = try instance.evaluate(entrypoint.?, input);
        times[iter] = timer.read();
        allocator.free(result);
    }

    std.mem.sort(u64, times, {}, std.sort.asc(u64));

    var total: u64 = 0;
    for (times) |t| {
        total += t;
    }

    const mean = total / iterations;
    const median = times[iterations / 2];
    const p95 = times[@as(usize, @intFromFloat(@as(f64, @floatFromInt(iterations)) * 0.95))];
    const p99 = times[@as(usize, @intFromFloat(@as(f64, @floatFromInt(iterations)) * 0.99))];

    const total_ms = @as(f64, @floatFromInt(total)) / 1_000_000.0;
    const mean_us = @as(f64, @floatFromInt(mean)) / 1_000.0;
    const median_us = @as(f64, @floatFromInt(median)) / 1_000.0;
    const p95_us = @as(f64, @floatFromInt(p95)) / 1_000.0;
    const p99_us = @as(f64, @floatFromInt(p99)) / 1_000.0;
    const throughput = @as(f64, @floatFromInt(iterations)) / (total_ms / 1000.0);

    var result_buf: [512]u8 = undefined;
    const results = std.fmt.bufPrint(&result_buf,
        \\Total time: {d:.2}ms
        \\Mean: {d:.2}us
        \\Median: {d:.2}us
        \\P95: {d:.2}us
        \\P99: {d:.2}us
        \\Throughput: {d:.0} eval/sec
        \\
    , .{ total_ms, mean_us, median_us, p95_us, p99_us, throughput }) catch "error formatting results\n";
    try stdout.writeAll(results);
}

pub fn printUsage() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\opa-zig bench - Benchmark policy evaluation
        \\
        \\USAGE:
        \\    opa-zig bench [OPTIONS]
        \\
        \\REQUIRED:
        \\    -m, --module <FILE>         Path to .wasm file
        \\    -e, --entrypoint <PATH>     Policy entrypoint (e.g., "example/allow")
        \\
        \\OPTIONS:
        \\    -i, --input <JSON>          Inline JSON input (default: "{}")
        \\    -d, --data <JSON>           Inline JSON data
        \\    -n, --iterations <N>        Number of iterations (default: 1000)
        \\    -w, --warmup <N>            Warmup iterations (default: 100)
        \\    -h, --help                  Show this help message
        \\
        \\EXAMPLES:
        \\    opa-zig bench -m policy.wasm -e "authz/allow" -n 5000
        \\    opa-zig bench -m policy.wasm -e "main/decision" -i '{"user":"alice"}'
        \\
    );
}
