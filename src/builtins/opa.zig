//! OPA runtime builtins (trace, opa.runtime).

const std = @import("std");
const json = std.json;
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn trace(_: std.mem.Allocator, a: Args) BuiltinError!json.Value {
    _ = a.getString(0) catch {};
    return common.makeBool(true);
}

pub fn runtime(allocator: std.mem.Allocator, _: Args) BuiltinError!json.Value {
    var obj = json.ObjectMap.init(allocator);
    obj.put("env", .{ .object = json.ObjectMap.init(allocator) }) catch return BuiltinError.AllocationFailed;
    obj.put("version", .{ .string = "0.0.3" }) catch return BuiltinError.AllocationFailed;
    obj.put("commit", .{ .string = "" }) catch return BuiltinError.AllocationFailed;
    return .{ .object = obj };
}

pub fn print(_: std.mem.Allocator, _: Args) BuiltinError!json.Value {
    return common.makeBool(true);
}

pub fn randIntn(_: std.mem.Allocator, a: Args) BuiltinError!json.Value {
    _ = a.getString(0) catch {};
    const n = a.getInt(1) catch return BuiltinError.InvalidArguments;
    if (n <= 0) return BuiltinError.InvalidArguments;
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const random = prng.random();
    const result = random.intRangeLessThan(i64, 0, n);
    return common.makeNumber(@floatFromInt(result));
}

test "opa.trace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = [_]json.Value{.{ .string = "debug message" }};
    const result = try trace(arena.allocator(), Args.init(&args));
    try std.testing.expect(result.bool == true);
}

test "opa.runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try runtime(arena.allocator(), Args.init(&[_]json.Value{}));
    try std.testing.expect(result == .object);
}

test "rand.intn" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = [_]json.Value{ .{ .string = "seed" }, .{ .integer = 100 } };
    const result = try randIntn(arena.allocator(), Args.init(&args));
    try std.testing.expect(result == .integer or result == .float);
}

test "print" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = [_]json.Value{ .{ .string = "debug" }, .{ .integer = 42 } };
    const result = try print(arena.allocator(), Args.init(&args));
    try std.testing.expect(result.bool == true);
}
