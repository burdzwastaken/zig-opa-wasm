//! OPA numeric operation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

fn toF64(item: std.json.Value) ?f64 {
    return switch (item) {
        .integer => |n| @floatFromInt(n),
        .float => |f| f,
        else => null,
    };
}

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
    for (arr) |item| total += toF64(item) orelse return error.TypeMismatch;
    return common.makeNumber(total);
}

pub fn product(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    var result: f64 = 1;
    for (arr) |item| result *= toF64(item) orelse return error.TypeMismatch;
    return common.makeNumber(result);
}

pub fn max(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    if (arr.len == 0) return error.InvalidArguments;
    var result: f64 = toF64(arr[0]) orelse return error.TypeMismatch;
    for (arr[1..]) |item| {
        const val = toF64(item) orelse return error.TypeMismatch;
        if (val > result) result = val;
    }
    return common.makeNumber(result);
}

pub fn min(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    if (arr.len == 0) return error.InvalidArguments;
    var result: f64 = toF64(arr[0]) orelse return error.TypeMismatch;
    for (arr[1..]) |item| {
        const val = toF64(item) orelse return error.TypeMismatch;
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

pub fn numbersRangeStep(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const start = try a.getInt(0);
    const stop = try a.getInt(1);
    const step = try a.getInt(2);
    if (step == 0) return error.InvalidArguments;
    if ((step > 0 and stop < start) or (step < 0 and stop > start)) {
        return .{ .array = std.json.Array.init(allocator) };
    }
    const diff: usize = if (step > 0)
        @intCast(stop - start)
    else
        @intCast(start - stop);
    const abs_step: usize = @intCast(if (step > 0) step else -step);
    const len: usize = diff / abs_step + 1;
    var arr = std.json.Array.initCapacity(allocator, len) catch return error.AllocationFailed;
    var i = start;
    if (step > 0) {
        while (i <= stop) : (i += step) {
            arr.appendAssumeCapacity(.{ .integer = i });
        }
    } else {
        while (i >= stop) : (i += step) {
            arr.appendAssumeCapacity(.{ .integer = i });
        }
    }
    return .{ .array = arr };
}

pub fn formatInt(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const n = try a.getInt(0);
    const base = try a.getInt(1);
    if (base < 2 or base > 36) return error.InvalidArguments;
    const base_u8: u8 = @intCast(base);
    var buf: [65]u8 = undefined;
    var len: usize = 0;
    var val: u64 = if (n < 0) @intCast(-n) else @intCast(n);
    if (val == 0) {
        buf[0] = '0';
        len = 1;
    } else {
        while (val > 0) : (len += 1) {
            buf[len] = std.fmt.digitToChar(@intCast(val % base_u8), .lower);
            val /= base_u8;
        }
    }
    if (n < 0) {
        buf[len] = '-';
        len += 1;
    }
    const final = allocator.alloc(u8, len) catch return error.AllocationFailed;
    for (0..len) |i| final[i] = buf[len - 1 - i];
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

test "numbers.range_step - positive step" {
    const result = try numbersRangeStep(std.testing.allocator, Args.init(&.{ .{ .integer = 0 }, .{ .integer = 10 }, .{ .integer = 2 } }));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(usize, 6), result.array.items.len);
    try std.testing.expectEqual(@as(i64, 0), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 10), result.array.items[5].integer);
}

test "numbers.range_step - negative step" {
    const result = try numbersRangeStep(std.testing.allocator, Args.init(&.{ .{ .integer = 10 }, .{ .integer = 0 }, .{ .integer = -2 } }));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(usize, 6), result.array.items.len);
    try std.testing.expectEqual(@as(i64, 10), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 0), result.array.items[5].integer);
}
