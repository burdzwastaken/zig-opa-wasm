//! Type-safe evaluation with compile-time types.

const std = @import("std");
const opa = @import("zig_opa_wasm");

const Input = struct {
    user: []const u8,
    action: []const u8,
};

// OPA returns results as [{"result": <value>}]
const OpaResult = struct {
    result: bool,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var wasm_backend = try opa.WasmerBackend.init(allocator);
    defer wasm_backend.deinit();

    const wasm_bytes = @embedFile("example_policy");
    var be = wasm_backend.asBackend();

    var policy = try opa.Policy.load(allocator, &be, wasm_bytes);
    defer policy.deinit();

    var instance = try opa.Instance.create(allocator, &policy);
    defer instance.deinit();

    const input = Input{ .user = "admin", .action = "read" };
    const results = try instance.evaluateTyped([]OpaResult, "example/allow", input);

    const stdout = std.Io.File.stdout();
    if (results.len > 0 and results[0].result) {
        stdout.writeStreamingAll(io, "allowed\n") catch {};
    } else {
        stdout.writeStreamingAll(io, "denied\n") catch {};
    }
}
