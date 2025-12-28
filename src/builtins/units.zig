//! OPA SI and byte unit parsing builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;
const humanize = @import("humanize");

pub fn parse(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const str = try args.getString(0);
    const result = humanize.si.parseSI(str) catch return error.InvalidArguments;
    return .{ .integer = @intFromFloat(result.value) };
}

pub fn parseBytes(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const str = try args.getString(0);
    const result = humanize.bytes.parseBytes(str) catch return error.InvalidArguments;
    return .{ .integer = @intCast(result) };
}

test "units.parse" {
    const allocator = std.testing.allocator;

    // OPA uses lowercase 'k' for kilo
    var result = try parse(allocator, Args.init(&.{.{ .string = "10k" }}));
    try std.testing.expectEqual(@as(i64, 10000), result.integer);

    result = try parse(allocator, Args.init(&.{.{ .string = "2M" }}));
    try std.testing.expectEqual(@as(i64, 2000000), result.integer);
}

test "units.parse_bytes" {
    const allocator = std.testing.allocator;

    var result = try parseBytes(allocator, Args.init(&.{.{ .string = "1KB" }}));
    try std.testing.expectEqual(@as(i64, 1000), result.integer);

    result = try parseBytes(allocator, Args.init(&.{.{ .string = "1KiB" }}));
    try std.testing.expectEqual(@as(i64, 1024), result.integer);

    result = try parseBytes(allocator, Args.init(&.{.{ .string = "1MiB" }}));
    try std.testing.expectEqual(@as(i64, 1048576), result.integer);
}
