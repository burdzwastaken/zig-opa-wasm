//! Info command - displays metadata about an OPA WASM module.

const std = @import("std");
const opa = @import("zig_opa_wasm");

const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();

pub const InfoArgs = struct {
    file: []const u8,
};

pub fn printUsage() !void {
    try stdout.writeAll(
        \\opa-zig info - Inspect a WASM module
        \\
        \\USAGE:
        \\    opa-zig info <FILE>
        \\
        \\ARGS:
        \\    <FILE>    Path to .wasm file
        \\
        \\OPTIONS:
        \\    -h, --help    Show this help message
        \\
    );
}

fn writeError(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    stderr.writeAll(msg) catch {};
}

pub fn runWithArgs(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try stderr.writeAll("error: missing FILE argument\n\n");
        try printUsage();
        return;
    }
    return run(allocator, .{ .file = args[0] });
}

pub fn run(allocator: std.mem.Allocator, args: InfoArgs) !void {
    const wasm_bytes = std.fs.cwd().readFileAlloc(allocator, args.file, 50 * 1024 * 1024) catch |err| {
        writeError("error: failed to read '{s}': {}\n", .{ args.file, err });
        return error.FileReadFailed;
    };
    defer allocator.free(wasm_bytes);

    const file_size = wasm_bytes.len;

    var backend = opa.WasmerBackend.init(allocator) catch |err| {
        writeError("error: failed to initialize backend: {}\n", .{err});
        return error.BackendInitFailed;
    };
    defer backend.deinit();

    var be = backend.asBackend();
    var policy = opa.Policy.load(allocator, &be, wasm_bytes) catch |err| {
        writeError("error: failed to load policy: {}\n", .{err});
        return error.PolicyLoadFailed;
    };
    defer policy.deinit();

    var instance = opa.Instance.create(allocator, &policy) catch |err| {
        writeError("error: failed to create instance: {}\n", .{err});
        return error.InstanceCreateFailed;
    };
    defer instance.deinit();

    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    pos += (std.fmt.bufPrint(buf[pos..], "Module: {s}\n", .{args.file}) catch unreachable).len;
    pos += (std.fmt.bufPrint(buf[pos..], "Size: {} bytes\n", .{file_size}) catch unreachable).len;
    pos += (std.fmt.bufPrint(buf[pos..], "ABI Version: {d}.{d}\n\n", .{ policy.abi_version.major, policy.abi_version.minor }) catch unreachable).len;

    pos += (std.fmt.bufPrint(buf[pos..], "Entrypoints:\n", .{}) catch unreachable).len;
    if (instance.entrypoints.count() == 0) {
        pos += (std.fmt.bufPrint(buf[pos..], "  (none)\n", .{}) catch unreachable).len;
    } else {
        var ep_iter = instance.entrypoints.iterator();
        while (ep_iter.next()) |entry| {
            pos += (std.fmt.bufPrint(buf[pos..], "  {d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* }) catch unreachable).len;
        }
    }

    pos += (std.fmt.bufPrint(buf[pos..], "\nRequired Builtins:\n", .{}) catch unreachable).len;
    try stdout.writeAll(buf[0..pos]);

    if (instance.builtins.count() == 0) {
        try stdout.writeAll("  (none)\n");
    } else {
        const BuiltinEntry = struct {
            id: u32,
            name: []const u8,
        };
        var entries = std.ArrayList(BuiltinEntry){};
        defer entries.deinit(allocator);

        var builtin_iter = instance.builtins.iterator();
        while (builtin_iter.next()) |entry| {
            try entries.append(allocator, .{ .id = entry.value_ptr.*, .name = entry.key_ptr.* });
        }

        std.mem.sort(BuiltinEntry, entries.items, {}, struct {
            fn lessThan(_: void, a: BuiltinEntry, b: BuiltinEntry) bool {
                return a.id < b.id;
            }
        }.lessThan);

        for (entries.items) |entry| {
            var line_buf: [256]u8 = undefined;
            const implemented = isBuiltinImplemented(entry.name);
            const line = if (implemented)
                std.fmt.bufPrint(&line_buf, "  {d}: {s}\n", .{ entry.id, entry.name }) catch unreachable
            else
                std.fmt.bufPrint(&line_buf, "  {d}: {s} (NOT IMPLEMENTED)\n", .{ entry.id, entry.name }) catch unreachable;
            try stdout.writeAll(line);
        }
    }
}

fn isBuiltinImplemented(name: []const u8) bool {
    return opa.builtins.isImplemented(name);
}
