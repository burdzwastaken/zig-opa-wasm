//! OPA glob pattern builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

pub fn quoteMeta(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);

    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    for (pattern) |c| {
        switch (c) {
            '*', '?', '[', ']', '{', '}', '\\' => {
                result.append(allocator, '\\') catch return error.AllocationFailed;
                result.append(allocator, c) catch return error.AllocationFailed;
            },
            else => {
                result.append(allocator, c) catch return error.AllocationFailed;
            },
        }
    }

    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

test "glob.quote_meta" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var result = try quoteMeta(allocator, Args.init(&.{.{ .string = "hello" }}));
    try std.testing.expectEqualStrings("hello", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "*.txt" }}));
    try std.testing.expectEqualStrings("\\*.txt", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "file?.log" }}));
    try std.testing.expectEqualStrings("file\\?.log", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "[abc]" }}));
    try std.testing.expectEqualStrings("\\[abc\\]", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "{a,b}" }}));
    try std.testing.expectEqualStrings("\\{a,b\\}", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "path\\to" }}));
    try std.testing.expectEqualStrings("path\\\\to", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "*.{js,ts}" }}));
    try std.testing.expectEqualStrings("\\*.\\{js,ts\\}", result.string);

    result = try quoteMeta(allocator, Args.init(&.{.{ .string = "" }}));
    try std.testing.expectEqualStrings("", result.string);
}
