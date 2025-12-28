//! OPA type checking builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn typeName(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    const name: []const u8 = switch (v) {
        .null => "null",
        .bool => "boolean",
        .integer, .float, .number_string => "number",
        .string => "string",
        .array => "array",
        .object => "object",
    };
    return .{ .string = name };
}

pub fn isString(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .string);
}

pub fn isNumber(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .integer or v == .float or v == .number_string);
}

pub fn isBoolean(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .bool);
}

pub fn isArray(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .array);
}

pub fn isObject(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .object);
}

pub fn isNull(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    return common.makeBool(v == .null);
}

pub fn isSet(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);
    _ = v;
    return common.makeBool(false);
}

test "types.type_name" {
    try std.testing.expectEqualStrings("string", (try typeName(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}))).string);
    try std.testing.expectEqualStrings("number", (try typeName(std.testing.allocator, Args.init(&.{.{ .integer = 42 }}))).string);
    try std.testing.expectEqualStrings("boolean", (try typeName(std.testing.allocator, Args.init(&.{.{ .bool = true }}))).string);
    try std.testing.expectEqualStrings("null", (try typeName(std.testing.allocator, Args.init(&.{.null}))).string);
}

test "types.is_string" {
    try std.testing.expect((try isString(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}))).bool);
    try std.testing.expect(!(try isString(std.testing.allocator, Args.init(&.{.{ .integer = 42 }}))).bool);
}

test "types.is_number" {
    try std.testing.expect((try isNumber(std.testing.allocator, Args.init(&.{.{ .integer = 42 }}))).bool);
    try std.testing.expect((try isNumber(std.testing.allocator, Args.init(&.{.{ .float = 3.14 }}))).bool);
    try std.testing.expect(!(try isNumber(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}))).bool);
}

test "types.is_boolean" {
    try std.testing.expect((try isBoolean(std.testing.allocator, Args.init(&.{.{ .bool = true }}))).bool);
    try std.testing.expect(!(try isBoolean(std.testing.allocator, Args.init(&.{.{ .integer = 1 }}))).bool);
}

test "types.is_array" {
    var arr = std.json.Array.init(std.testing.allocator);
    defer arr.deinit();
    try std.testing.expect((try isArray(std.testing.allocator, Args.init(&.{.{ .array = arr }}))).bool);
    try std.testing.expect(!(try isArray(std.testing.allocator, Args.init(&.{.{ .integer = 1 }}))).bool);
}

test "types.is_object" {
    var obj = std.json.ObjectMap.init(std.testing.allocator);
    defer obj.deinit();
    try std.testing.expect((try isObject(std.testing.allocator, Args.init(&.{.{ .object = obj }}))).bool);
    try std.testing.expect(!(try isObject(std.testing.allocator, Args.init(&.{.{ .integer = 1 }}))).bool);
}

test "types.is_null" {
    try std.testing.expect((try isNull(std.testing.allocator, Args.init(&.{.null}))).bool);
    try std.testing.expect(!(try isNull(std.testing.allocator, Args.init(&.{.{ .integer = 1 }}))).bool);
}

pub fn toNumber(_: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const v = try a.get(0);

    return switch (v) {
        .integer, .float => v,
        .number_string, .string => |s| {
            if (std.fmt.parseInt(i64, s, 10)) |i| return .{ .integer = i } else |_| {}
            if (std.fmt.parseFloat(f64, s)) |f| return .{ .float = f } else |_| {}
            return error.InvalidArguments;
        },
        .bool => |b| .{ .integer = if (b) 1 else 0 },
        .null => .{ .integer = 0 },
        else => error.TypeMismatch,
    };
}

test "to_number - string integer" {
    const result = try toNumber(std.testing.allocator, Args.init(&.{.{ .string = "42" }}));
    try std.testing.expectEqual(@as(i64, 42), result.integer);
}

test "to_number - string float" {
    const result = try toNumber(std.testing.allocator, Args.init(&.{.{ .string = "3.14" }}));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "to_number - boolean" {
    var result = try toNumber(std.testing.allocator, Args.init(&.{.{ .bool = true }}));
    try std.testing.expectEqual(@as(i64, 1), result.integer);
    result = try toNumber(std.testing.allocator, Args.init(&.{.{ .bool = false }}));
    try std.testing.expectEqual(@as(i64, 0), result.integer);
}

test "to_number - passthrough" {
    const result = try toNumber(std.testing.allocator, Args.init(&.{.{ .integer = 99 }}));
    try std.testing.expectEqual(@as(i64, 99), result.integer);
}
