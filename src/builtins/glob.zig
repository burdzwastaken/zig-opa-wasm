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

pub fn match(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const pattern = try args.getString(0);
    const delimiters_val = args.get(1) catch return error.InvalidArguments;
    const match_str = try args.getString(2);

    // default to ["."] if null
    var delim_list: std.ArrayListUnmanaged([]const u8) = .{};
    defer delim_list.deinit(allocator);

    if (delimiters_val == .null) {
        return .{ .bool = globMatch(pattern, match_str, null) };
    } else if (delimiters_val == .array) {
        for (delimiters_val.array.items) |d| {
            if (d == .string) {
                delim_list.append(allocator, d.string) catch return error.AllocationFailed;
            }
        }
    } else {
        return error.InvalidArguments;
    }

    const delims = if (delim_list.items.len > 0) delim_list.items else null;
    return .{ .bool = globMatch(pattern, match_str, delims) };
}

fn globMatch(pattern: []const u8, str: []const u8, delimiters: ?[]const []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;
    var star_pi: ?usize = null;
    var star_si: ?usize = null;

    while (si < str.len or pi < pattern.len) {
        if (pi < pattern.len) {
            const pc = pattern[pi];
            if (pc == '*') {
                // ** (matches across delimiters)
                if (pi + 1 < pattern.len and pattern[pi + 1] == '*') {
                    // ** matches everything including delimiters
                    star_pi = pi;
                    star_si = si;
                    pi += 2;
                    continue;
                }
                // * - save position for backtracking
                star_pi = pi;
                star_si = si;
                pi += 1;
                continue;
            } else if (pc == '?' and si < str.len) {
                // ? single char (but not delimiter)
                if (delimiters) |delims| {
                    for (delims) |d| {
                        if (si + d.len <= str.len and std.mem.eql(u8, str[si .. si + d.len], d)) {
                            // Hit delimiter, ? can't match
                            if (star_pi) |spi| {
                                pi = spi + 1;
                                star_si.? += 1;
                                si = star_si.?;
                                continue;
                            }
                            return false;
                        }
                    }
                }
                pi += 1;
                si += 1;
                continue;
            } else if (si < str.len and pc == str[si]) {
                pi += 1;
                si += 1;
                continue;
            }
        }

        // try backtracking
        if (star_pi) |spi| {
            // hit a delimiter (single * stops at delimiters)?
            if (delimiters) |delims| {
                const is_double_star = spi + 1 < pattern.len and pattern[spi + 1] == '*';
                if (!is_double_star) {
                    for (delims) |d| {
                        if (star_si.? + d.len <= str.len and
                            std.mem.eql(u8, str[star_si.? .. star_si.? + d.len], d))
                        {
                            return false;
                        }
                    }
                }
            }
            if (star_si.? < str.len) {
                star_si.? += 1;
                si = star_si.?;
                pi = spi + 1;
                if (pi < pattern.len and pattern[pi] == '*') pi += 1;
                continue;
            }
        }
        return false;
    }
    return true;
}

test "glob.match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var delims = std.json.Array.init(allocator);
    try delims.append(.{ .string = "." });

    var result = try match(allocator, Args.init(&.{ .{ .string = "foo.*" }, .{ .array = delims }, .{ .string = "foo.bar" } }));
    try std.testing.expect(result.bool);

    result = try match(allocator, Args.init(&.{ .{ .string = "foo.*" }, .{ .array = delims }, .{ .string = "foo.bar.baz" } }));
    try std.testing.expect(!result.bool); // single * doesn't cross delimiters

    result = try match(allocator, Args.init(&.{ .{ .string = "foo*" }, .null, .{ .string = "foobar" } }));
    try std.testing.expect(result.bool);
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
