//! OPA bitwise operation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn bitwiseOr(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    const b = try args.getInt(1);
    return .{ .integer = a | b };
}

pub fn bitwiseAnd(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    const b = try args.getInt(1);
    return .{ .integer = a & b };
}

pub fn bitwiseNegate(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    return .{ .integer = ~a };
}

pub fn bitwiseXor(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    const b = try args.getInt(1);
    return .{ .integer = a ^ b };
}

pub fn bitwiseLsh(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    const b = try args.getInt(1);
    if (b < 0 or b >= 64) return error.InvalidArguments;
    const shift: u6 = @intCast(b);
    return .{ .integer = a << shift };
}

pub fn bitwiseRsh(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const a = try args.getInt(0);
    const b = try args.getInt(1);
    if (b < 0 or b >= 64) return error.InvalidArguments;
    const shift: u6 = @intCast(b);
    // Use unsigned right shift to match OPA semantics (logical shift)
    const unsigned: u64 = @bitCast(a);
    const result: u64 = unsigned >> shift;
    return .{ .integer = @bitCast(result) };
}

test "bits.or" {
    const result = try bitwiseOr(std.testing.allocator, Args.init(&.{
        .{ .integer = 0b1010 },
        .{ .integer = 0b1100 },
    }));
    try std.testing.expectEqual(@as(i64, 0b1110), result.integer);
}

test "bits.and" {
    const result = try bitwiseAnd(std.testing.allocator, Args.init(&.{
        .{ .integer = 0b1010 },
        .{ .integer = 0b1100 },
    }));
    try std.testing.expectEqual(@as(i64, 0b1000), result.integer);
}

test "bits.negate" {
    const result = try bitwiseNegate(std.testing.allocator, Args.init(&.{
        .{ .integer = 0 },
    }));
    try std.testing.expectEqual(@as(i64, -1), result.integer);
}

test "bits.xor" {
    const result = try bitwiseXor(std.testing.allocator, Args.init(&.{
        .{ .integer = 0b1010 },
        .{ .integer = 0b1100 },
    }));
    try std.testing.expectEqual(@as(i64, 0b0110), result.integer);
}

test "bits.lsh" {
    const result = try bitwiseLsh(std.testing.allocator, Args.init(&.{
        .{ .integer = 1 },
        .{ .integer = 4 },
    }));
    try std.testing.expectEqual(@as(i64, 16), result.integer);
}

test "bits.rsh" {
    const result = try bitwiseRsh(std.testing.allocator, Args.init(&.{
        .{ .integer = 16 },
        .{ .integer = 4 },
    }));
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}
