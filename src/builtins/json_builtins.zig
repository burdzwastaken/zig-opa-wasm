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
