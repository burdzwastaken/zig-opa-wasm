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

pub fn isValid(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);
    const regex = mvzr.compile(pattern);
    return .{ .bool = regex != null };
}

test "regex.is_valid - valid pattern" {
    const result = try isValid(std.testing.allocator, Args.init(&.{
        .{ .string = "^foo.*bar$" },
    }));
    try std.testing.expect(result.bool);
}

test "regex.is_valid - invalid pattern" {
    const result = try isValid(std.testing.allocator, Args.init(&.{
        .{ .string = "[invalid" },
    }));
    try std.testing.expect(!result.bool);
}

pub fn globsMatch(_: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const glob1 = try args.getString(0);
    const glob2 = try args.getString(1);

    const match1 = globMatchesString(glob1, glob2);
    const match2 = globMatchesString(glob2, glob1);
    return .{ .bool = match1 or match2 };
}

fn globMatchesString(pattern: []const u8, s: []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;
    var star_p: ?usize = null;
    var star_s: usize = 0;

    while (si < s.len) {
        if (pi < pattern.len and (pattern[pi] == s[si] or pattern[pi] == '?')) {
            pi += 1;
            si += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_p = pi;
            star_s = si;
            pi += 1;
        } else if (star_p) |sp| {
            pi = sp + 1;
            star_s += 1;
            si = star_s;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') pi += 1;
    return pi == pattern.len;
}

test "regex.globs_match" {
    const allocator = std.testing.allocator;

    var result = try globsMatch(allocator, Args.init(&.{
        .{ .string = "*.txt" },
        .{ .string = "foo.txt" },
    }));
    try std.testing.expect(result.bool);

    result = try globsMatch(allocator, Args.init(&.{
        .{ .string = "foo.*" },
        .{ .string = "foo.bar" },
    }));
    try std.testing.expect(result.bool);
}

pub fn templateMatch(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const template = try args.getString(0);
    const input = try args.getString(1);
    const delim_start = try args.getString(2);
    const delim_end = try args.getString(3);

    var pattern = std.ArrayListUnmanaged(u8){};
    defer pattern.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (i + delim_start.len <= template.len and std.mem.eql(u8, template[i .. i + delim_start.len], delim_start)) {
            const start = i + delim_start.len;
            if (std.mem.indexOfPos(u8, template, start, delim_end)) |end| {
                pattern.appendSlice(allocator, ".*") catch return error.AllocationFailed;
                i = end + delim_end.len;
                continue;
            }
        }
        const c = template[i];
        if (std.mem.indexOfScalar(u8, ".*+?^$[](){}|\\", c) != null) {
            pattern.append(allocator, '\\') catch return error.AllocationFailed;
        }
        pattern.append(allocator, c) catch return error.AllocationFailed;
        i += 1;
    }

    pattern.append(allocator, 0) catch return error.AllocationFailed;
    const regex = mvzr.compile(pattern.items[0 .. pattern.items.len - 1 :0]) orelse return .{ .bool = false };
    return .{ .bool = regex.isMatch(input) };
}

test "regex.template_match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try templateMatch(arena.allocator(), Args.init(&.{
        .{ .string = "urn:foo:{id}" },
        .{ .string = "urn:foo:bar:baz" },
        .{ .string = "{" },
        .{ .string = "}" },
    }));
    try std.testing.expect(result.bool);
}
