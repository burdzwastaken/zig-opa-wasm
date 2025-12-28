//! OPA JSON parsing and serialization builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn jsonIsValid(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    _ = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{}) catch {
        return common.makeBool(false);
    };
    return common.makeBool(true);
}

pub fn jsonMarshal(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const value = try a.get(0);
    const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.SerializationFailed;
    return .{ .string = json_str };
}

pub fn jsonUnmarshal(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch {
        return error.InvalidArguments;
    };
    return parsed.value;
}

test "json.is_valid with valid json" {
    const result = try jsonIsValid(std.testing.allocator, Args.init(&.{.{ .string = "{\"a\":1}" }}));
    try std.testing.expect(result.bool == true);
}

test "json.is_valid with invalid json" {
    const result = try jsonIsValid(std.testing.allocator, Args.init(&.{.{ .string = "{invalid}" }}));
    try std.testing.expect(result.bool == false);
}

test "json.marshal" {
    const result = try jsonMarshal(std.testing.allocator, Args.init(&.{.{ .integer = 42 }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("42", result.string);
}

fn extractPath(path_val: std.json.Value) ?[]const u8 {
    return switch (path_val) {
        .string => |s| s,
        .array => |arr| if (arr.items.len > 0 and arr.items[0] == .string) arr.items[0].string else null,
        else => null,
    };
}

pub fn jsonFilter(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    const paths = try a.getSetOrArray(1);

    var result = std.json.ObjectMap.init(allocator);
    for (paths) |path_val| {
        const path = extractPath(path_val) orelse continue;
        if (obj.get(path)) |val| result.put(path, val) catch return error.AllocationFailed;
    }
    return .{ .object = result };
}

pub fn jsonRemove(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    const paths = try a.getSetOrArray(1);

    var keys_to_remove = std.StringHashMap(void).init(allocator);
    defer keys_to_remove.deinit();
    for (paths) |path_val| {
        const path = extractPath(path_val) orelse continue;
        keys_to_remove.put(path, {}) catch return error.AllocationFailed;
    }

    var result = std.json.ObjectMap.init(allocator);
    var it = obj.iterator();
    while (it.next()) |entry| {
        if (!keys_to_remove.contains(entry.key_ptr.*)) {
            result.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.AllocationFailed;
        }
    }
    return .{ .object = result };
}

pub fn jsonPatch(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    var obj = try a.get(0);
    const patches = try a.getArray(1);

    for (patches) |patch| {
        const patch_obj = switch (patch) {
            .object => |o| o,
            else => return error.InvalidArguments,
        };

        const op = (patch_obj.get("op") orelse return error.InvalidArguments).string;
        const path = (patch_obj.get("path") orelse return error.InvalidArguments).string;

        if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "replace")) {
            const value = patch_obj.get("value") orelse return error.InvalidArguments;
            obj = applyPatchOp(allocator, obj, path, value, false) catch return error.AllocationFailed;
        } else if (std.mem.eql(u8, op, "remove")) {
            obj = applyPatchOp(allocator, obj, path, null, true) catch return error.AllocationFailed;
        }
    }

    return obj;
}

fn applyPatchOp(allocator: std.mem.Allocator, obj: std.json.Value, path: []const u8, value: ?std.json.Value, remove: bool) !std.json.Value {
    if (path.len == 0 or std.mem.eql(u8, path, "/")) {
        return if (remove) .null else (value orelse .null);
    }

    const clean_path = if (path[0] == '/') path[1..] else path;
    const sep_idx = std.mem.indexOf(u8, clean_path, "/");
    const key = if (sep_idx) |idx| clean_path[0..idx] else clean_path;
    const rest = if (sep_idx) |idx| clean_path[idx..] else "";

    switch (obj) {
        .object => |o| {
            var new_obj = std.json.ObjectMap.init(allocator);
            var it = o.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, key)) {
                    if (rest.len == 0) {
                        if (!remove) {
                            try new_obj.put(key, value orelse .null);
                        }
                    } else {
                        const nested = try applyPatchOp(allocator, entry.value_ptr.*, rest, value, remove);
                        try new_obj.put(key, nested);
                    }
                } else {
                    try new_obj.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            if (rest.len == 0 and !remove and o.get(key) == null) {
                try new_obj.put(key, value orelse .null);
            }
            return .{ .object = new_obj };
        },
        else => return obj,
    }
}

test "json.filter" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    try obj.put("b", .{ .integer = 2 });
    try obj.put("c", .{ .integer = 3 });

    var paths = std.json.Array.init(std.testing.allocator);
    defer paths.deinit();
    try paths.append(.{ .string = "a" });
    try paths.append(.{ .string = "c" });

    var result = try jsonFilter(std.testing.allocator, Args.init(&.{ .{ .object = obj }, .{ .array = paths } }));
    defer result.object.deinit();

    try std.testing.expect(result.object.count() == 2);
    try std.testing.expect(result.object.get("a") != null);
    try std.testing.expect(result.object.get("c") != null);
    try std.testing.expect(result.object.get("b") == null);
}

test "json.remove" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("a", .{ .integer = 1 });
    try obj.put("b", .{ .integer = 2 });
    try obj.put("c", .{ .integer = 3 });

    var paths = std.json.Array.init(std.testing.allocator);
    defer paths.deinit();
    try paths.append(.{ .string = "b" });

    var result = try jsonRemove(std.testing.allocator, Args.init(&.{ .{ .object = obj }, .{ .array = paths } }));
    defer result.object.deinit();

    try std.testing.expect(result.object.count() == 2);
    try std.testing.expect(result.object.get("a") != null);
    try std.testing.expect(result.object.get("c") != null);
    try std.testing.expect(result.object.get("b") == null);
}

pub fn jsonMarshalWithOptions(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const value = try a.get(0);
    _ = try a.getObject(1);
    const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.SerializationFailed;
    return .{ .string = json_str };
}

test "json.marshal_with_options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var opts = std.json.ObjectMap.init(arena.allocator());
    try opts.put("pretty", .{ .bool = true });

    var obj = std.json.ObjectMap.init(arena.allocator());
    try obj.put("a", .{ .integer = 1 });

    const result = try jsonMarshalWithOptions(arena.allocator(), Args.init(&.{ .{ .object = obj }, .{ .object = opts } }));
    try std.testing.expect(result.string.len > 0);
}
