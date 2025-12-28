//! OPA array and set operation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn concat(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr1 = try a.getArray(0);
    const arr2 = try a.getArray(1);
    var result = std.json.Array.initCapacity(allocator, arr1.len + arr2.len) catch return error.AllocationFailed;
    for (arr1) |item| result.appendAssumeCapacity(item);
    for (arr2) |item| result.appendAssumeCapacity(item);
    return .{ .array = result };
}

pub fn slice(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    const start_signed = try a.getInt(1);
    const stop_signed = try a.getInt(2);
    const start: usize = if (start_signed < 0) 0 else @min(@as(usize, @intCast(start_signed)), arr.len);
    const stop: usize = if (stop_signed < 0) 0 else @min(@as(usize, @intCast(stop_signed)), arr.len);
    if (start >= stop) return .{ .array = std.json.Array.init(std.heap.page_allocator) };
    return .{ .array = .{ .items = @constCast(arr[start..stop]), .capacity = stop - start, .allocator = std.heap.page_allocator } };
}

pub fn reverse(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    var result = std.json.Array.initCapacity(allocator, arr.len) catch return error.AllocationFailed;
    var i: usize = arr.len;
    while (i > 0) {
        i -= 1;
        result.appendAssumeCapacity(arr[i]);
    }
    return .{ .array = result };
}

fn jsonLessThan(a_val: std.json.Value, b_val: std.json.Value) bool {
    const a_num: ?f64 = switch (a_val) {
        .integer => |n| @floatFromInt(n),
        .float => |f| f,
        else => null,
    };
    const b_num: ?f64 = switch (b_val) {
        .integer => |n| @floatFromInt(n),
        .float => |f| f,
        else => null,
    };
    if (a_num != null and b_num != null) return a_num.? < b_num.?;
    if (a_val == .string and b_val == .string) {
        return std.mem.lessThan(u8, a_val.string, b_val.string);
    }
    return false;
}

pub fn sort(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    var result = std.json.Array.initCapacity(allocator, arr.len) catch return error.AllocationFailed;
    for (arr) |item| result.appendAssumeCapacity(item);
    std.mem.sort(std.json.Value, result.items, {}, struct {
        fn lessThan(_: void, lhs: std.json.Value, rhs: std.json.Value) bool {
            return jsonLessThan(lhs, rhs);
        }
    }.lessThan);
    return .{ .array = result };
}

pub fn count(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    const len: i64 = switch (v) {
        .array => |arr| @intCast(arr.items.len),
        .object => |obj| @intCast(obj.count()),
        .string => |s| @intCast(s.len),
        else => return error.TypeMismatch,
    };
    return .{ .integer = len };
}

pub fn intersection(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const sets = try a.getArray(0);
    if (sets.len == 0) return .{ .array = std.json.Array.init(allocator) };
    const first_set = switch (sets[0]) {
        .array => |arr| arr.items,
        else => return error.TypeMismatch,
    };
    var result = std.json.Array.init(allocator);
    outer: for (first_set) |item| {
        for (sets[1..]) |set_val| {
            const set = switch (set_val) {
                .array => |arr| arr.items,
                else => return error.TypeMismatch,
            };
            var found = false;
            for (set) |s_item| {
                if (common.jsonEqual(item, s_item)) {
                    found = true;
                    break;
                }
            }
            if (!found) continue :outer;
        }
        result.append(item) catch return error.AllocationFailed;
    }
    return .{ .array = result };
}

pub fn setUnion(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const sets = try a.getArray(0);
    var result = std.json.Array.init(allocator);
    for (sets) |set_val| {
        const set = switch (set_val) {
            .array => |arr| arr.items,
            else => return error.TypeMismatch,
        };
        outer: for (set) |item| {
            for (result.items) |existing| {
                if (common.jsonEqual(item, existing)) continue :outer;
            }
            result.append(item) catch return error.AllocationFailed;
        }
    }
    return .{ .array = result };
}

test "array.concat" {
    var arr1 = std.json.Array.init(std.testing.allocator);
    defer arr1.deinit();
    try arr1.append(.{ .integer = 1 });
    var arr2 = std.json.Array.init(std.testing.allocator);
    defer arr2.deinit();
    try arr2.append(.{ .integer = 2 });
    const result = try concat(std.testing.allocator, Args.init(&.{ .{ .array = arr1 }, .{ .array = arr2 } }));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.array.items.len);
}

test "array.slice" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    try arr.append(.{ .integer = 3 });
    const result = try slice(std.testing.allocator, Args.init(&.{ .{ .array = arr }, .{ .integer = 1 }, .{ .integer = 2 } }));
    try std.testing.expectEqual(@as(usize, 1), result.array.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.array.items[0].integer);
}

test "array.reverse" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    try arr.append(.{ .integer = 3 });
    const result = try reverse(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(i64, 3), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[2].integer);
}

test "arrays.sort" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 3 });
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    const result = try sort(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(i64, 1), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), result.array.items[2].integer);
}

test "arrays.count array" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    const result = try count(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(i64, 2), result.integer);
}

test "arrays.count string" {
    const result = try count(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    try std.testing.expectEqual(@as(i64, 5), result.integer);
}

/// Returns true if any element in the collection is true.
/// For arrays/sets: returns true if any element equals true.
pub fn any(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    for (arr) |item| {
        if (item == .bool and item.bool) return .{ .bool = true };
    }
    return .{ .bool = false };
}

/// Returns true if all elements in the collection are true.
/// For arrays/sets: returns true if every element equals true.
pub fn all(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const arr = try a.getArray(0);
    if (arr.len == 0) return .{ .bool = true };
    for (arr) |item| {
        if (item != .bool or !item.bool) return .{ .bool = false };
    }
    return .{ .bool = true };
}

test "any - some true" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .bool = false });
    try arr.append(.{ .bool = true });
    try arr.append(.{ .bool = false });
    const result = try any(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expect(result.bool);
}

test "any - all false" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .bool = false });
    try arr.append(.{ .bool = false });
    const result = try any(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expect(!result.bool);
}

test "all - all true" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .bool = true });
    try arr.append(.{ .bool = true });
    const result = try all(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expect(result.bool);
}

test "all - some false" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .bool = true });
    try arr.append(.{ .bool = false });
    const result = try all(std.testing.allocator, Args.init(&.{.{ .array = arr }}));
    try std.testing.expect(!result.bool);
}

test "all - empty array" {
    const allocator = std.testing.allocator;
    var arr = std.json.Array.init(allocator);
    defer arr.deinit();
    var args = [_]std.json.Value{.{ .array = arr }};
    const result = try all(allocator, Args.init(&args));
    try std.testing.expect(result.bool == true);
}

pub fn walk(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.get(0);
    var result = std.json.Array.init(allocator);
    var path = std.json.Array.init(allocator);
    defer path.deinit();
    walkRecursive(allocator, input, &path, &result) catch return error.AllocationFailed;
    return .{ .array = result };
}

fn walkRecursive(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    path: *std.json.Array,
    result: *std.json.Array,
) !void {
    var pair = std.json.Array.init(allocator);
    const path_copy = try path.clone();
    try pair.append(.{ .array = path_copy });
    try pair.append(value);
    try result.append(.{ .array = pair });

    switch (value) {
        .object => |obj| {
            for (obj.keys()) |key| {
                try path.append(.{ .string = key });
                try walkRecursive(allocator, obj.get(key).?, path, result);
                _ = path.pop();
            }
        },
        .array => |arr| {
            for (arr.items, 0..) |item, i| {
                try path.append(.{ .integer = @intCast(i) });
                try walkRecursive(allocator, item, path, result);
                _ = path.pop();
            }
        },
        else => {},
    }
}

test "walk - simple object" {
    const allocator = std.testing.allocator;
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    var args = [_]std.json.Value{.{ .object = obj }};
    const result = try walk(allocator, Args.init(&args));
    defer freeWalkResult(allocator, result);
    try std.testing.expect(result.array.items.len == 2);
}

test "walk - nested" {
    const allocator = std.testing.allocator;
    var inner = std.json.ObjectMap.init(allocator);
    defer inner.deinit();
    try inner.put("b", .{ .integer = 2 });
    var outer = std.json.ObjectMap.init(allocator);
    defer outer.deinit();
    try outer.put("a", .{ .object = inner });
    var args = [_]std.json.Value{.{ .object = outer }};
    const result = try walk(allocator, Args.init(&args));
    defer freeWalkResult(allocator, result);
    try std.testing.expect(result.array.items.len == 3);
}

fn freeWalkResult(_: std.mem.Allocator, result: std.json.Value) void {
    for (result.array.items) |pair| {
        pair.array.items[0].array.deinit();
        pair.array.deinit();
    }
    result.array.deinit();
}
