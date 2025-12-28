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

    var remove_set = std.StringHashMap(void).init(allocator);
    defer remove_set.deinit();
    for (keys_to_remove) |k| {
        if (k == .string) remove_set.put(k.string, {}) catch return error.AllocationFailed;
    }

    var result = std.json.ObjectMap.init(allocator);
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (!remove_set.contains(entry.key_ptr.*)) {
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

pub fn filter(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    const filter_keys = try a.getSetOrArray(1);

    var keep_set = std.StringHashMap(void).init(allocator);
    defer keep_set.deinit();
    for (filter_keys) |k| {
        if (k == .string) keep_set.put(k.string, {}) catch return error.AllocationFailed;
    }

    var result = std.json.ObjectMap.init(allocator);
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        if (keep_set.contains(entry.key_ptr.*)) {
            result.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.AllocationFailed;
        }
    }
    return .{ .object = result };
}

pub fn subset(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const super = try a.getObject(0);
    const sub = try a.getObject(1);

    var iter = sub.iterator();
    while (iter.next()) |entry| {
        const super_val = super.get(entry.key_ptr.*) orelse return .{ .bool = false };
        if (!common.jsonEqual(entry.value_ptr.*, super_val)) {
            return .{ .bool = false };
        }
    }
    return .{ .bool = true };
}

test "object.filter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("a", .{ .integer = 1 });
    try obj.put("b", .{ .integer = 2 });
    try obj.put("c", .{ .integer = 3 });

    var keys_arr = std.json.Array.init(allocator);
    try keys_arr.append(.{ .string = "a" });
    try keys_arr.append(.{ .string = "c" });

    const result = try filter(allocator, Args.init(&.{ .{ .object = obj }, .{ .array = keys_arr } }));
    try std.testing.expectEqual(@as(usize, 2), result.object.count());
    try std.testing.expect(result.object.get("a") != null);
    try std.testing.expect(result.object.get("c") != null);
    try std.testing.expect(result.object.get("b") == null);
}

test "object.subset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var super_obj = std.json.ObjectMap.init(allocator);
    try super_obj.put("a", .{ .integer = 1 });
    try super_obj.put("b", .{ .integer = 2 });

    var sub_obj = std.json.ObjectMap.init(allocator);
    try sub_obj.put("a", .{ .integer = 1 });

    var result = try subset(allocator, Args.init(&.{ .{ .object = super_obj }, .{ .object = sub_obj } }));
    try std.testing.expect(result.bool);

    var not_sub = std.json.ObjectMap.init(allocator);
    try not_sub.put("a", .{ .integer = 99 });

    result = try subset(allocator, Args.init(&.{ .{ .object = super_obj }, .{ .object = not_sub } }));
    try std.testing.expect(!result.bool);
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
