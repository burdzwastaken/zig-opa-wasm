//! Type-safe evaluation with compile-time types.

const std = @import("std");
const opa = @import("zig_opa_wasm");

const Input = struct {
    user: []const u8,
    action: []const u8,
};

const Output = struct {
    allow: bool,
};

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

    const input = Input{ .user = "admin", .action = "read" };
    const result = try instance.evaluateTyped(Output, "example/allow", input);

    const stdout = std.fs.File.stdout();
    const msg = if (result.allow) "allowed\n" else "denied\n";
    try stdout.writeAll(msg);
}
