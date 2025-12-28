//! OPA encoding builtins (base64, hex, URL).

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn base64Encode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const encoder = std.base64.standard;
    const size = encoder.Encoder.calcSize(input.len);
    const buf = allocator.alloc(u8, size) catch return error.AllocationFailed;
    _ = encoder.Encoder.encode(buf, input);
    return .{ .string = buf };
}

pub fn base64Decode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const decoder = std.base64.standard.Decoder;
    const exact_size = decoder.calcSizeForSlice(input) catch return error.InvalidArguments;
    const buf = allocator.alloc(u8, exact_size) catch return error.AllocationFailed;
    decoder.decode(buf, input) catch return error.InvalidArguments;
    return .{ .string = buf };
}

pub fn base64UrlEncode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const encoder = std.base64.url_safe;
    const size = encoder.Encoder.calcSize(input.len);
    const buf = allocator.alloc(u8, size) catch return error.AllocationFailed;
    _ = encoder.Encoder.encode(buf, input);
    return .{ .string = buf };
}

pub fn base64UrlEncodeNoPad(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const encoder = std.base64.url_safe_no_pad;
    const size = encoder.Encoder.calcSize(input.len);
    const buf = allocator.alloc(u8, size) catch return error.AllocationFailed;
    _ = encoder.Encoder.encode(buf, input);
    return .{ .string = buf };
}

pub fn base64UrlDecode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const decoder = std.base64.url_safe;
    const max_size = decoder.Decoder.calcSizeUpperBound(input.len) catch return error.InvalidArguments;
    const buf = allocator.alloc(u8, max_size) catch return error.AllocationFailed;
    decoder.Decoder.decode(buf, input) catch {
        allocator.free(buf);
        return error.InvalidArguments;
    };
    const actual_len = decoder.Decoder.calcSizeForSlice(input) catch {
        allocator.free(buf);
        return error.InvalidArguments;
    };
    if (actual_len == max_size) {
        return .{ .string = buf };
    }
    const result = allocator.realloc(buf, actual_len) catch {
        allocator.free(buf);
        return error.AllocationFailed;
    };
    return .{ .string = result };
}

pub fn hexEncode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const result = allocator.alloc(u8, input.len * 2) catch return error.AllocationFailed;
    for (input, 0..) |byte, i| {
        result[i * 2] = std.fmt.digitToChar(byte >> 4, .lower);
        result[i * 2 + 1] = std.fmt.digitToChar(byte & 0x0f, .lower);
    }
    return .{ .string = result };
}

pub fn hexDecode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    if (input.len % 2 != 0) return error.InvalidArguments;
    const result = allocator.alloc(u8, input.len / 2) catch return error.AllocationFailed;
    _ = std.fmt.hexToBytes(result, input) catch {
        allocator.free(result);
        return error.InvalidArguments;
    };
    return .{ .string = result };
}

pub fn urlQueryEncode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var result: std.ArrayListUnmanaged(u8) = .{};
    encodeComponent(allocator, &result, input) catch return error.AllocationFailed;
    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

pub fn urlQueryDecode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    return .{ .string = decodeComponent(allocator, input) catch return error.AllocationFailed };
}

test "base64.encode" {
    const result = try base64Encode(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("aGVsbG8=", result.string);
}

test "base64.decode" {
    const result = try base64Decode(std.testing.allocator, Args.init(&.{.{ .string = "aGVsbG8=" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "hex.encode" {
    const result = try hexEncode(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("68656c6c6f", result.string);
}

test "hex.decode" {
    const result = try hexDecode(std.testing.allocator, Args.init(&.{.{ .string = "68656c6c6f" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "urlquery.encode" {
    const result = try urlQueryEncode(std.testing.allocator, Args.init(&.{.{ .string = "hello world" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("hello%20world", result.string);
}

test "urlquery.decode" {
    const result = try urlQueryDecode(std.testing.allocator, Args.init(&.{.{ .string = "hello%20world" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("hello world", result.string);
}

pub fn base64IsValid(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(input) catch return .{ .bool = false };
    const buf = allocator.alloc(u8, size) catch return .{ .bool = false };
    defer allocator.free(buf);
    decoder.decode(buf, input) catch return .{ .bool = false };
    return .{ .bool = true };
}

test "base64.is_valid - valid" {
    const result = try base64IsValid(std.testing.allocator, Args.init(&.{.{ .string = "aGVsbG8=" }}));
    try std.testing.expect(result.bool);
}

test "base64.is_valid - invalid" {
    const result = try base64IsValid(std.testing.allocator, Args.init(&.{.{ .string = "not valid!!!" }}));
    try std.testing.expect(!result.bool);
}

pub fn urlQueryDecodeObject(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var result = std.json.ObjectMap.init(allocator);

    var pairs = std.mem.splitScalar(u8, input, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        var kv = std.mem.splitScalar(u8, pair, '=');
        const key = kv.next() orelse continue;
        const val = kv.next() orelse "";

        const decoded_key = decodeComponent(allocator, key) catch continue;
        const decoded_val = decodeComponent(allocator, val) catch continue;

        if (result.get(decoded_key)) |existing| {
            var arr: std.json.Array = if (existing == .array) existing.array else blk: {
                var new_arr = std.json.Array.init(allocator);
                new_arr.append(existing) catch return error.AllocationFailed;
                break :blk new_arr;
            };
            arr.append(.{ .string = decoded_val }) catch return error.AllocationFailed;
            result.put(decoded_key, .{ .array = arr }) catch return error.AllocationFailed;
        } else {
            result.put(decoded_key, .{ .string = decoded_val }) catch return error.AllocationFailed;
        }
    }
    return .{ .object = result };
}

fn decodeComponent(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch {
                try result.append(allocator, input[i]);
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch {
                try result.append(allocator, input[i]);
                i += 1;
                continue;
            };
            try result.append(allocator, (hi << 4) | lo);
            i += 3;
        } else if (input[i] == '+') {
            try result.append(allocator, ' ');
            i += 1;
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn urlQueryEncodeObject(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const obj = try a.getObject(0);
    var result = std.ArrayListUnmanaged(u8){};
    var first = true;

    var iter = obj.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        if (val == .array) {
            for (val.array.items) |item| {
                if (!first) result.append(allocator, '&') catch return error.AllocationFailed;
                first = false;
                encodeComponent(allocator, &result, key) catch return error.AllocationFailed;
                result.append(allocator, '=') catch return error.AllocationFailed;
                if (item == .string) {
                    encodeComponent(allocator, &result, item.string) catch return error.AllocationFailed;
                }
            }
        } else {
            if (!first) result.append(allocator, '&') catch return error.AllocationFailed;
            first = false;
            encodeComponent(allocator, &result, key) catch return error.AllocationFailed;
            result.append(allocator, '=') catch return error.AllocationFailed;
            if (val == .string) {
                encodeComponent(allocator, &result, val.string) catch return error.AllocationFailed;
            }
        }
    }
    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

fn encodeComponent(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), input: []const u8) !void {
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(allocator, c);
        } else {
            try result.append(allocator, '%');
            try result.append(allocator, std.fmt.digitToChar(c >> 4, .upper));
            try result.append(allocator, std.fmt.digitToChar(c & 0x0f, .upper));
        }
    }
}

test "urlquery.decode_object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try urlQueryDecodeObject(arena.allocator(), Args.init(&.{.{ .string = "foo=bar&baz=qux" }}));
    try std.testing.expectEqualStrings("bar", result.object.get("foo").?.string);
    try std.testing.expectEqualStrings("qux", result.object.get("baz").?.string);
}

test "urlquery.encode_object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var obj = std.json.ObjectMap.init(arena.allocator());
    try obj.put("foo", .{ .string = "bar" });

    const result = try urlQueryEncodeObject(arena.allocator(), Args.init(&.{.{ .object = obj }}));
    try std.testing.expectEqualStrings("foo=bar", result.string);
}
