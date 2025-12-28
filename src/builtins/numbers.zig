//! OPA numeric operation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn abs(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getNumber(0);
    return common.makeNumber(@abs(n));
}

pub fn round(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getNumber(0);
    return common.makeNumber(@round(n));
}

pub fn ceil(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getNumber(0);
    return common.makeNumber(@ceil(n));
}

pub fn floor(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getNumber(0);
    return common.makeNumber(@floor(n));
}

pub fn sum(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    var total: f64 = 0;
    for (arr) |item| {
        total += switch (item) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .float => |f| f,
            else => return error.TypeMismatch,
        };
    }
    return common.makeNumber(total);
}

pub fn product(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    var result: f64 = 1;
    for (arr) |item| {
        result *= switch (item) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .float => |f| f,
            else => return error.TypeMismatch,
        };
    }
    return common.makeNumber(result);
}

pub fn max(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    if (arr.len == 0) return error.InvalidArguments;
    var result: f64 = switch (arr[0]) {
        .integer => |n| @as(f64, @floatFromInt(n)),
        .float => |f| f,
        else => return error.TypeMismatch,
    };
    for (arr[1..]) |item| {
        const val: f64 = switch (item) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .float => |f| f,
            else => return error.TypeMismatch,
        };
        if (val > result) result = val;
    }
    return common.makeNumber(result);
}

pub fn min(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    if (arr.len == 0) return error.InvalidArguments;
    var result: f64 = switch (arr[0]) {
        .integer => |n| @as(f64, @floatFromInt(n)),
        .float => |f| f,
        else => return error.TypeMismatch,
    };
    for (arr[1..]) |item| {
        const val: f64 = switch (item) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .float => |f| f,
            else => return error.TypeMismatch,
        };
        if (val < result) result = val;
    }
    return common.makeNumber(result);
}

pub fn numbersRange(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const start = try a.getInt(0);
    const stop = try a.getInt(1);
    if (stop < start) return .{ .array = std.json.Array.init(allocator) };
    const len: usize = @intCast(stop - start + 1);
    var arr = std.json.Array.initCapacity(allocator, len) catch return error.AllocationFailed;
    var i = start;
    while (i <= stop) : (i += 1) {
        arr.appendAssumeCapacity(.{ .integer = i });
    }
    return .{ .array = arr };
}

pub fn formatInt(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getInt(0);
    const base = try a.getInt(1);
    if (base < 2 or base > 36) return error.InvalidArguments;
    const base_u8: u8 = @intCast(base);
    var out_buf: [65]u8 = undefined;
    var out_len: usize = 0;
    var val: u64 = if (n < 0) @intCast(-n) else @intCast(n);
    if (val == 0) {
        out_buf[0] = '0';
        out_len = 1;
    } else {
        while (val > 0) {
            const digit: u8 = @intCast(val % base_u8);
            out_buf[out_len] = if (digit < 10) '0' + digit else 'a' + digit - 10;
            out_len += 1;
            val /= base_u8;
        }
    }
    if (n < 0) {
        out_buf[out_len] = '-';
        out_len += 1;
    }
    const final = allocator.alloc(u8, out_len) catch return error.AllocationFailed;
    for (0..out_len) |i| {
        final[i] = out_buf[out_len - 1 - i];
    }
    return .{ .string = final };
}

test "numbers.abs" {
    const result = try abs(std.testing.allocator, Args.init(&.{.{ .float = -5.5 }}));
    try std.testing.expectEqual(@as(f64, 5.5), result.float);
}

test "numbers.round" {
    const result = try round(std.testing.allocator, Args.init(&.{.{ .float = 2.7 }}));
    try std.testing.expectEqual(@as(i64, 3), result.integer);
}

test "numbers.ceil" {
    const result = try ceil(std.testing.allocator, Args.init(&.{.{ .float = 2.1 }}));
    try std.testing.expectEqual(@as(i64, 3), result.integer);
}

test "numbers.floor" {
    const result = try floor(std.testing.allocator, Args.init(&.{.{ .float = 2.9 }}));
    try std.testing.expectEqual(@as(i64, 2), result.integer);
}

test "numbers.sum" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    try arr.append(.{ .integer = 3 });
    const result = try sum(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(i64, 6), result.integer);
}

test "numbers.product" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 2 });
    try arr.append(.{ .integer = 3 });
    try arr.append(.{ .integer = 4 });
    const result = try product(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(i64, 24), result.integer);
}

test "numbers.max" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 3 });
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 4 });
    const result = try max(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(i64, 4), result.integer);
}

test "numbers.min" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 3 });
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 4 });
    const result = try min(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "numbers.range" {
    const result = try numbersRange(std.testing.allocator, Args.init(&.{ .{ .integer = 1 }, .{ .integer = 3 } }));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(usize, 3), result.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.array.items[2].integer);
}
