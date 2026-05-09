//! Instance pooling for high-throughput evaluation.

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

    var pool = opa.InstancePool.init(allocator, &policy, 4);
    defer pool.deinit();

    const inputs = [_][]const u8{
        "{\"user\": \"admin\"}",
        "{\"user\": \"guest\"}",
        "{\"user\": \"admin\"}",
    };

    const stdout = std.Io.File.stdout();
    for (inputs) |input| {
        var instance = try pool.acquire();
        defer pool.release(instance);

        const result = try instance.evaluate("example/allow", input);
        defer allocator.free(result);

        stdout.writeStreamingAll(io, result) catch {};
        stdout.writeStreamingAll(io, "\n") catch {};
    }
}
