//! Eval command - evaluates an OPA policy with given input and data.

const std = @import("std");
const opa = @import("zig_opa_wasm");

const Policy = opa.Policy;
const Instance = opa.Instance;
const WasmerBackend = opa.WasmerBackend;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    var wasm_path: ?[]const u8 = null;
    var entrypoint: ?[]const u8 = null;
    var input_json: ?[]const u8 = null;
    var input_file: ?[]const u8 = null;
    var data_json: ?[]const u8 = null;
    var data_file: ?[]const u8 = null;
    var pretty = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--module")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            wasm_path = args[i];
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--entrypoint")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            entrypoint = args[i];
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            input_json = args[i];
        } else if (std.mem.eql(u8, arg, "-I") or std.mem.eql(u8, arg, "--input-file")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            input_file = args[i];
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--data")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            data_json = args[i];
        } else if (std.mem.eql(u8, arg, "-D") or std.mem.eql(u8, arg, "--data-file")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            data_file = args[i];
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--pretty")) {
            pretty = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage();
            return;
        } else {
            if (wasm_path == null and !std.mem.startsWith(u8, arg, "-")) {
                wasm_path = arg;
            }
        }
    }

    if (wasm_path == null) {
        try stderr.writeAll("error: missing required argument: WASM module path\n\n");
        try printUsage();
        return error.MissingArgument;
    }

    if (entrypoint == null) {
        try stderr.writeAll("error: missing required argument: --entrypoint\n\n");
        try printUsage();
        return error.MissingArgument;
    }

    const input = blk: {
        if (input_json) |json| {
            break :blk json;
        } else if (input_file) |path| {
            break :blk try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
        } else {
            break :blk "{}";
        }
    };

    const data = blk: {
        if (data_json) |json| {
            break :blk json;
        } else if (data_file) |path| {
            break :blk try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
        } else {
            break :blk null;
        }
    };

    const path = wasm_path.?;
    const is_bundle = std.mem.endsWith(u8, path, ".tar.gz") or std.mem.endsWith(u8, path, ".tgz");

    var loaded_bundle: ?opa.Bundle = null;
    defer if (loaded_bundle) |*b| b.deinit();

    const wasm_bytes = blk: {
        if (is_bundle) {
            const file_bytes = try std.fs.cwd().readFileAlloc(allocator, path, 50 * 1024 * 1024);
            defer allocator.free(file_bytes);
            loaded_bundle = try opa.bundle.fromBytes(allocator, file_bytes);
            break :blk loaded_bundle.?.wasm;
        } else {
            break :blk try std.fs.cwd().readFileAlloc(allocator, path, 50 * 1024 * 1024);
        }
    };
    defer if (!is_bundle) allocator.free(wasm_bytes);

    var backend = try WasmerBackend.init(allocator);
    defer backend.deinit();

    var be = backend.asBackend();
    var policy = try Policy.load(allocator, &be, wasm_bytes);
    defer policy.deinit();

    var instance = try Instance.create(allocator, &policy);
    defer instance.deinit();

    if (data) |d| {
        try instance.setData(d);
    } else if (loaded_bundle) |b| {
        if (b.data) |bundle_data| {
            try instance.setData(bundle_data);
        }
    }

    const result = try instance.evaluate(entrypoint.?, input);
    defer allocator.free(result);

    if (pretty) {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
        defer parsed.deinit();
        const pretty_output = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{ .whitespace = .indent_2 });
        defer allocator.free(pretty_output);
        try stdout.writeAll(pretty_output);
        try stdout.writeAll("\n");
    } else {
        try stdout.writeAll(result);
        try stdout.writeAll("\n");
    }
}

pub fn printUsage() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\opa-zig eval - Evaluate a policy
        \\
        \\USAGE:
        \\    opa-zig eval [OPTIONS] <WASM_FILE>
        \\
        \\REQUIRED:
        \\    <WASM_FILE>                 Path to .wasm file
        \\    -e, --entrypoint <PATH>     Policy entrypoint (e.g., "example/allow")
        \\
        \\INPUT:
        \\    -i, --input <JSON>          Inline JSON input
        \\    -I, --input-file <FILE>     Path to JSON input file
        \\
        \\DATA:
        \\    -d, --data <JSON>           Inline JSON data
        \\    -D, --data-file <FILE>      Path to JSON data file
        \\
        \\OUTPUT:
        \\    -p, --pretty                Pretty-print JSON output
        \\
        \\EXAMPLES:
        \\    opa-zig eval -m policy.wasm -e "authz/allow" -i '{"user":"alice"}'
        \\    opa-zig eval policy.wasm -e "main/decision" -D data.json -I input.json
        \\
    );
}
