//! Loading policies from OPA bundles.

const std = @import("std");
const opa = @import("zig_opa_wasm");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        std.Io.File.stderr().writeStreamingAll(io, "Usage: bundle_loading <bundle.tar.gz>\n") catch {};
        return;
    }

    var bundle = try opa.Bundle.fromFile(allocator, io, args[1]);
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

    std.Io.File.stdout().writeStreamingAll(io, result) catch {};
    std.Io.File.stdout().writeStreamingAll(io, "\n") catch {};
}
