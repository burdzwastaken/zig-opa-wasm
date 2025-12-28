//! Evaluation with external data document.

const std = @import("std");
const opa = @import("zig_opa_wasm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var wasm_backend = try opa.WasmerBackend.init(allocator);
    defer wasm_backend.deinit();

    const wasm_bytes = @embedFile("example_policy");
    var be = wasm_backend.asBackend();

    var policy = try opa.Policy.load(allocator, &be, wasm_bytes);
    defer policy.deinit();

    var instance = try opa.Instance.create(allocator, &policy);
    defer instance.deinit();

    try instance.setData("{\"roles\": {\"admin\": [\"read\", \"write\"]}}");

    const result = try instance.evaluate("example/allow", "{\"user\": \"admin\"}");
    defer allocator.free(result);

    const stdout = std.fs.File.stdout();
    try stdout.writeAll(result);
    try stdout.writeAll("\n");
}
