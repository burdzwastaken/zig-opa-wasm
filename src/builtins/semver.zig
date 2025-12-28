//! OPA semantic versioning builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn compare(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const a_str = try args.getString(0);
    const b_str = try args.getString(1);

    const a = std.SemanticVersion.parse(a_str) catch return error.InvalidArguments;
    const b = std.SemanticVersion.parse(b_str) catch return error.InvalidArguments;

    const order = a.order(b);
    const result: i64 = switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
    return .{ .integer = result };
}

pub fn isValid(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const vsn_str = try args.getString(0);

    const valid = if (std.SemanticVersion.parse(vsn_str)) |_| true else |_| false;
    return .{ .bool = valid };
}

test "semver.compare" {
    const allocator = std.testing.allocator;

    var result = try compare(allocator, Args.init(&.{
        .{ .string = "1.0.0" },
        .{ .string = "1.0.0" },
    }));
    try std.testing.expectEqual(@as(i64, 0), result.integer);

    result = try compare(allocator, Args.init(&.{
        .{ .string = "1.0.0" },
        .{ .string = "2.0.0" },
    }));
    try std.testing.expectEqual(@as(i64, -1), result.integer);

    result = try compare(allocator, Args.init(&.{
        .{ .string = "2.0.0" },
        .{ .string = "1.0.0" },
    }));
    try std.testing.expectEqual(@as(i64, 1), result.integer);

    result = try compare(allocator, Args.init(&.{
        .{ .string = "1.2.0" },
        .{ .string = "1.3.0" },
    }));
    try std.testing.expectEqual(@as(i64, -1), result.integer);

    result = try compare(allocator, Args.init(&.{
        .{ .string = "1.2.4" },
        .{ .string = "1.2.3" },
    }));
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "semver.is_valid" {
    const allocator = std.testing.allocator;

    var result = try isValid(allocator, Args.init(&.{.{ .string = "1.0.0" }}));
    try std.testing.expect(result.bool);

    result = try isValid(allocator, Args.init(&.{.{ .string = "0.1.0" }}));
    try std.testing.expect(result.bool);

    result = try isValid(allocator, Args.init(&.{.{ .string = "10.20.30" }}));
    try std.testing.expect(result.bool);

    result = try isValid(allocator, Args.init(&.{.{ .string = "not-a-version" }}));
    try std.testing.expect(!result.bool);

    result = try isValid(allocator, Args.init(&.{.{ .string = "1.0" }}));
    try std.testing.expect(!result.bool);

    result = try isValid(allocator, Args.init(&.{.{ .string = "" }}));
    try std.testing.expect(!result.bool);
}
