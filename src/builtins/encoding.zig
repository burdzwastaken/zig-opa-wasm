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
    const hex_chars = "0123456789abcdef";
    for (input, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return .{ .string = result };
}

pub fn hexDecode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    if (input.len % 2 != 0) return error.InvalidArguments;
    const result = allocator.alloc(u8, input.len / 2) catch return error.AllocationFailed;
    for (0..input.len / 2) |i| {
        const hi = hexCharToNibble(input[i * 2]) orelse return error.InvalidArguments;
        const lo = hexCharToNibble(input[i * 2 + 1]) orelse return error.InvalidArguments;
        result[i] = (hi << 4) | lo;
    }
    return .{ .string = result };
}

fn hexCharToNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

pub fn urlQueryEncode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var result: std.ArrayListUnmanaged(u8) = .{};
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            result.append(allocator, c) catch return error.AllocationFailed;
        } else {
            result.append(allocator, '%') catch return error.AllocationFailed;
            const hex_chars = "0123456789ABCDEF";
            result.append(allocator, hex_chars[c >> 4]) catch return error.AllocationFailed;
            result.append(allocator, hex_chars[c & 0x0f]) catch return error.AllocationFailed;
        }
    }
    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

pub fn urlQueryDecode(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var result: std.ArrayListUnmanaged(u8) = .{};
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = hexCharToNibble(input[i + 1]) orelse {
                result.append(allocator, input[i]) catch return error.AllocationFailed;
                i += 1;
                continue;
            };
            const lo = hexCharToNibble(input[i + 2]) orelse {
                result.append(allocator, input[i]) catch return error.AllocationFailed;
                i += 1;
                continue;
            };
            result.append(allocator, (hi << 4) | lo) catch return error.AllocationFailed;
            i += 3;
        } else if (input[i] == '+') {
            result.append(allocator, ' ') catch return error.AllocationFailed;
            i += 1;
        } else {
            result.append(allocator, input[i]) catch return error.AllocationFailed;
            i += 1;
        }
    }
    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
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
