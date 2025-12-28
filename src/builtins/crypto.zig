//! OPA cryptographic hash builtins (MD5, SHA1, SHA256).

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn md5(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &hash, .{});
    return hexEncodeHash(allocator, &hash);
}

pub fn sha1(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &hash, .{});
    return hexEncodeHash(allocator, &hash);
}

pub fn sha256(allocator: std.mem.Allocator, a: Args) BuiltinError!std.json.Value {
    const input = try a.getString(0);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});
    return hexEncodeHash(allocator, &hash);
}

fn hexEncodeHash(allocator: std.mem.Allocator, hash: []const u8) BuiltinError!std.json.Value {
    const result = allocator.alloc(u8, hash.len * 2) catch return error.AllocationFailed;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return .{ .string = result };
}

test "crypto.md5" {
    const result = try md5(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("5d41402abc4b2a76b9719d911017c592", result.string);
}

test "crypto.sha1" {
    const result = try sha1(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d", result.string);
}

test "crypto.sha256" {
    const result = try sha256(std.testing.allocator, Args.init(&.{.{ .string = "hello" }}));
    defer std.testing.allocator.free(result.string);
    try std.testing.expectEqualStrings("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", result.string);
}
