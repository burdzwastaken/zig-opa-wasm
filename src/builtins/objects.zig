//! OPA object manipulation builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn get(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    const key = try a.getString(1);
    const default_val = a.get(2) catch common.makeNull();
    return obj.get(key) orelse default_val;
}

pub fn keys(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    var result = std.json.Array.initCapacity(allocator, obj.count()) catch return error.AllocationFailed;
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        result.appendAssumeCapacity(.{ .string = entry.key_ptr.* });
    }
    return .{ .array = result };
}

pub fn remove(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    const keys_to_remove = try a.getArray(1);
    var result = std.json.ObjectMap.init(allocator);
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        var should_remove = false;
        for (keys_to_remove) |k| {
            if (k == .string and std.mem.eql(u8, k.string, entry.key_ptr.*)) {
                should_remove = true;
                break;
            }
        }
        if (!should_remove) {
            result.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.AllocationFailed;
        }
    }
    return .{ .object = result };
}

test "object.get with default" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    const result = try get(std.testing.allocator, Args.init(&.{ .{ .object = obj }, .{ .string = "a" }, .{ .integer = 99 } }));
    try std.testing.expectEqual(@as(i64, 1), result.integer);
}

test "object.get missing with default" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    const result = try get(std.testing.allocator, Args.init(&.{ .{ .object = obj }, .{ .string = "missing" }, .{ .integer = 42 } }));
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "object.keys" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    try obj.put("b", .{ .integer = 2 });
    const result = try keys(std.testing.allocator, Args.init(&.{.{ .object = obj }}));
    defer result.array.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.array.items.len);
}

test "object.remove" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    try obj.put("b", .{ .integer = 2 });
    var keys_arr = std.json.Array.init(std.testing.allocator);
    defer keys_arr.deinit();
    try keys_arr.append(.{ .string = "a" });
    const result = try remove(std.testing.allocator, Args.init(&.{ .{ .object = obj }, .{ .array = keys_arr } }));
    defer @constCast(&result.object).deinit();
    try std.testing.expectEqual(@as(usize, 1), result.object.count());
    try std.testing.expect(result.object.get("b") != null);
}

pub fn unionN(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const objects = try a.getArray(0);
    var result = std.json.ObjectMap.init(allocator);
    for (objects) |obj_val| {
        if (obj_val != .object) continue;
        var iter = obj_val.object.iterator();
        while (iter.next()) |entry| {
            result.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.AllocationFailed;
        }
    }
    return .{ .object = result };
}

test "object.union_n" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var obj1 = std.json.ObjectMap.init(arena.allocator());
    try obj1.put("a", .{ .integer = 1 });
    var obj2 = std.json.ObjectMap.init(arena.allocator());
    try obj2.put("b", .{ .integer = 2 });
    var arr = std.json.Array.init(arena.allocator());
    try arr.append(.{ .object = obj1 });
    try arr.append(.{ .object = obj2 });
    const result = try unionN(arena.allocator(), Args.init(&.{.{ .array = arr }}));
    try std.testing.expectEqual(@as(usize, 2), result.object.count());
}
