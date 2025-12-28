//! Loading policies from OPA bundles.

const std = @import("std");
const opa = @import("zig_opa_wasm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <bundle.tar.gz>\n", .{args[0]});
        return;
    }

    var bundle = try opa.Bundle.fromFile(allocator, args[1]);
    defer bundle.deinit();

    var wasm_backend = try opa.WasmerBackend.init(allocator);
    defer wasm_backend.deinit();

    var be = wasm_backend.asBackend();

    var policy = try opa.Policy.load(allocator, &be, bundle.wasm);
    defer policy.deinit();

    var instance = try opa.Instance.create(allocator, &policy);
    defer instance.deinit();

    if (bundle.data) |data| {
        try instance.setData(data);
    }

    const result = try instance.evaluate("example/allow", "{\"user\": \"admin\"}");
    defer allocator.free(result);

    const stdout = std.fs.File.stdout();
    try stdout.writeAll(result);
    try stdout.writeAll("\n");
}
