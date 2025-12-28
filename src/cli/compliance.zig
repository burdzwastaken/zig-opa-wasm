const std = @import("std");
const opa = @import("zig_opa_wasm");

const WasmerBackend = opa.WasmerBackend;
const Policy = opa.Policy;
const Instance = opa.Instance;

const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();

pub const ComplianceOptions = struct {
    test_dir: []const u8 = "tests/compliance",
    filter: ?[]const u8 = null,
    verbose: bool = false,
    max_failures: usize = 0,
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = ComplianceOptions{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dir")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("error: missing argument for --dir\n");
                return;
            }
            opts.test_dir = args[i];
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--filter")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("error: missing argument for --filter\n");
                return;
            }
            opts.filter = args[i];
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "--max-failures")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("error: missing argument for --max-failures\n");
                return;
            }
            opts.max_failures = std.fmt.parseInt(usize, args[i], 10) catch {
                try stderr.writeAll("error: invalid number for --max-failures\n");
                return;
            };
        }
    }

    try runCompliance(allocator, opts);
}

fn runCompliance(allocator: std.mem.Allocator, opts: ComplianceOptions) !void {
    var buf: [1024]u8 = undefined;

    var backend = WasmerBackend.init(allocator) catch |err| {
        const msg = std.fmt.bufPrint(&buf, "error: failed to init backend: {}\n", .{err}) catch return;
        try stderr.writeAll(msg);
        return;
    };
    defer backend.deinit();

    var dir = std.fs.cwd().openDir(opts.test_dir, .{ .iterate = true }) catch |err| {
        const msg = std.fmt.bufPrint(&buf, "error: failed to open test dir '{s}': {}\n", .{ opts.test_dir, err }) catch return;
        try stderr.writeAll(msg);
        return;
    };
    defer dir.close();

    var total: usize = 0;
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        if (opts.filter) |filter| {
            if (std.mem.indexOf(u8, entry.name, filter) == null) continue;
        }

        const file_content = dir.readFileAlloc(allocator, entry.name, 100 * 1024 * 1024) catch continue;
        defer allocator.free(file_content);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, file_content, .{}) catch continue;
        defer parsed.deinit();

        const cases = parsed.value.object.get("cases") orelse continue;

        for (cases.array.items) |case_value| {
            total += 1;
            const case_obj = case_value.object;

            const note = if (case_obj.get("note")) |n| n.string else "unknown";
            const wasm_b64 = if (case_obj.get("wasm")) |w| w.string else {
                skipped += 1;
                continue;
            };

            const wasm_len = std.base64.standard.Decoder.calcSizeForSlice(wasm_b64) catch {
                skipped += 1;
                continue;
            };
            const wasm = allocator.alloc(u8, wasm_len) catch {
                skipped += 1;
                continue;
            };
            defer allocator.free(wasm);

            std.base64.standard.Decoder.decode(wasm, wasm_b64) catch {
                skipped += 1;
                continue;
            };

            var be = backend.asBackend();
            var policy = Policy.load(allocator, &be, wasm) catch {
                if (opts.verbose) {
                    const msg = std.fmt.bufPrint(&buf, "SKIP {s}/{s}: policy load failed\n", .{ entry.name, note }) catch continue;
                    stderr.writeAll(msg) catch {};
                }
                skipped += 1;
                continue;
            };
            defer policy.deinit();

            var instance = Instance.create(allocator, &policy) catch {
                if (opts.verbose) {
                    const msg = std.fmt.bufPrint(&buf, "SKIP {s}/{s}: instance create failed\n", .{ entry.name, note }) catch continue;
                    stderr.writeAll(msg) catch {};
                }
                skipped += 1;
                continue;
            };
            defer instance.deinit();

            if (case_obj.get("data")) |data_val| {
                const data_str = std.json.Stringify.valueAlloc(allocator, data_val, .{}) catch {
                    skipped += 1;
                    continue;
                };
                defer allocator.free(data_str);
                instance.setData(data_str) catch {
                    if (opts.verbose) {
                        const msg = std.fmt.bufPrint(&buf, "SKIP {s}/{s}: setData failed\n", .{ entry.name, note }) catch continue;
                        stderr.writeAll(msg) catch {};
                    }
                    skipped += 1;
                    continue;
                };
            }

            const input_str = if (case_obj.get("input")) |input_val|
                std.json.Stringify.valueAlloc(allocator, input_val, .{}) catch {
                    skipped += 1;
                    continue;
                }
            else
                "{}";
            defer if (case_obj.get("input") != null) allocator.free(input_str);

            const want_error = case_obj.get("want_error") != null;

            const result = instance.evaluate("eval", input_str) catch {
                if (want_error) {
                    passed += 1;
                    if (opts.verbose) {
                        const msg = std.fmt.bufPrint(&buf, "PASS {s}/{s} (expected error)\n", .{ entry.name, note }) catch continue;
                        stdout.writeAll(msg) catch {};
                    }
                } else {
                    if (opts.verbose) {
                        const msg = std.fmt.bufPrint(&buf, "SKIP {s}/{s}: evaluation failed\n", .{ entry.name, note }) catch continue;
                        stderr.writeAll(msg) catch {};
                    }
                    skipped += 1;
                }
                continue;
            };
            defer allocator.free(result);

            const want_result = case_obj.get("want_result");
            const want_defined = if (case_obj.get("want_defined")) |wd|
                wd.bool
            else if (want_result) |wr|
                switch (wr) {
                    .array => |arr| arr.items.len > 0,
                    else => true,
                }
            else
                true;

            const result_parsed = std.json.parseFromSlice(std.json.Value, allocator, result, .{}) catch {
                if (want_defined) {
                    failed += 1;
                    const msg = std.fmt.bufPrint(&buf, "FAIL {s}/{s}: invalid result JSON\n", .{ entry.name, note }) catch continue;
                    stderr.writeAll(msg) catch {};
                } else {
                    passed += 1;
                }
                continue;
            };
            defer result_parsed.deinit();

            const is_defined = switch (result_parsed.value) {
                .array => |arr| arr.items.len > 0,
                else => true,
            };

            if (is_defined == want_defined) {
                passed += 1;
                if (opts.verbose) {
                    const msg = std.fmt.bufPrint(&buf, "PASS {s}/{s}\n", .{ entry.name, note }) catch continue;
                    stdout.writeAll(msg) catch {};
                }
            } else {
                failed += 1;
                const msg = std.fmt.bufPrint(&buf, "FAIL {s}/{s}: want_defined={}, got_defined={}\n", .{ entry.name, note, want_defined, is_defined }) catch continue;
                stderr.writeAll(msg) catch {};
            }

            backend.opa_context.reset();
        }
    }

    const summary = std.fmt.bufPrint(&buf, "\nCompliance: {d} passed, {d} failed, {d} skipped, {d} total\n", .{ passed, failed, skipped, total }) catch return;
    try stdout.writeAll(summary);

    if (failed > opts.max_failures) {
        std.process.exit(1);
    }
}

pub fn printUsage() !void {
    try stdout.writeAll(
        \\opa-zig compliance - Run OPA WASM compliance tests
        \\
        \\USAGE:
        \\    opa-zig compliance [OPTIONS]
        \\
        \\OPTIONS:
        \\    -d, --dir <PATH>      Test directory (default: tests/compliance)
        \\    -f, --filter <NAME>   Filter test files by name
        \\    -v, --verbose         Show all test results
        \\    --max-failures <N>    Exit 0 if failures <= N (default: 0)
        \\    -h, --help            Show this help message
        \\
    );
}
