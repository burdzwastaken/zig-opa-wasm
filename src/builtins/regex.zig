//! OPA regular expression builtins.

const std = @import("std");
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;
const mvzr = @import("mvzr");

pub fn match(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const pattern = try args.getString(0);
    const value = try args.getString(1);

    const regex = mvzr.compile(pattern) orelse return error.InvalidArguments;
    const matched = regex.isMatch(value);
    return .{ .bool = matched };
}

pub fn findN(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);
    const value = try args.getString(1);
    const n = try args.getInt(2);

    const regex = mvzr.compile(pattern) orelse return error.InvalidArguments;

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    var count: i64 = 0;
    var iter = regex.iterator(value);
    while (iter.next()) |m| {
        if (n >= 0 and count >= n) break;
        const slice = m.slice;
        results.append(.{ .string = slice }) catch return error.AllocationFailed;
        count += 1;
    }

    return .{ .array = results };
}

pub fn split(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);
    const value = try args.getString(1);

    const regex = mvzr.compile(pattern) orelse return error.InvalidArguments;

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    var last_end: usize = 0;
    var iter = regex.iterator(value);
    while (iter.next()) |m| {
        if (m.start > last_end or m.start == last_end) {
            results.append(.{ .string = value[last_end..m.start] }) catch return error.AllocationFailed;
        }
        last_end = m.end;
    }

    if (last_end <= value.len) {
        results.append(.{ .string = value[last_end..] }) catch return error.AllocationFailed;
    }

    return .{ .array = results };
}

pub fn replace(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const value = try args.getString(0);
    const pattern = try args.getString(1);
    const replacement = try args.getString(2);

    const regex = mvzr.compile(pattern) orelse return error.InvalidArguments;

    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    var last_end: usize = 0;
    var iter = regex.iterator(value);
    while (iter.next()) |m| {
        result.appendSlice(allocator, value[last_end..m.start]) catch return error.AllocationFailed;
        result.appendSlice(allocator, replacement) catch return error.AllocationFailed;
        last_end = m.end;
    }
    result.appendSlice(allocator, value[last_end..]) catch return error.AllocationFailed;

    return .{ .string = result.toOwnedSlice(allocator) catch return error.AllocationFailed };
}

pub fn findAllStringSubmatchN(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);
    const value = try args.getString(1);
    const n = try args.getInt(2);

    const regex = mvzr.compile(pattern) orelse return error.InvalidArguments;

    var results = std.json.Array.init(allocator);
    errdefer results.deinit();

    var count: i64 = 0;
    var iter = regex.iterator(value);
    while (iter.next()) |m| {
        if (n >= 0 and count >= n) break;

        var submatch = std.json.Array.init(allocator);
        submatch.append(.{ .string = m.slice }) catch return error.AllocationFailed;
        results.append(.{ .array = submatch }) catch return error.AllocationFailed;
        count += 1;
    }

    return .{ .array = results };
}

test "regex.match" {
    const allocator = std.testing.allocator;

    var result = try match(allocator, Args.init(&.{
        .{ .string = "^foo" },
        .{ .string = "foobar" },
    }));
    try std.testing.expect(result.bool);

    result = try match(allocator, Args.init(&.{
        .{ .string = "^bar" },
        .{ .string = "foobar" },
    }));
    try std.testing.expect(!result.bool);
}

test "regex.split" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try split(arena.allocator(), Args.init(&.{
        .{ .string = "," },
        .{ .string = "a,b,c" },
    }));
    try std.testing.expectEqual(@as(usize, 3), result.array.items.len);
    try std.testing.expectEqualStrings("a", result.array.items[0].string);
    try std.testing.expectEqualStrings("b", result.array.items[1].string);
    try std.testing.expectEqualStrings("c", result.array.items[2].string);
}

test "regex.replace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try replace(arena.allocator(), Args.init(&.{
        .{ .string = "hello world" },
        .{ .string = "world" },
        .{ .string = "zig" },
    }));
    try std.testing.expectEqualStrings("hello zig", result.string);
}
