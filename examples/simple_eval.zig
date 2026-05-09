//! Simple policy evaluation example.

const std = @import("std");
const opa = @import("zig_opa_wasm");

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

    const result = try instance.evaluate("example/allow", "{\"user\": \"admin\"}");
    defer allocator.free(result);

    std.Io.File.stdout().writeStreamingAll(io, result) catch {};
    std.Io.File.stdout().writeStreamingAll(io, "\n") catch {};
}
